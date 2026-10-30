import Foundation
import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement

// MARK: - 播放控制器

/// 播放控制器：状态机 + 轮询监测 + 文件选择 + 最近记录 + 开机自启。
///
/// 三条硬规则：
/// 1. 出声只能由人触发（启动一律 autoplay: false）。
/// 2. 手动暂停永远压过自动逻辑。
/// 3. `isPlaying` 必须与 `AVAudioPlayerNode.isPlaying` 对齐——图标不许说谎。
final class PlayerController: NSObject, ObservableObject {

    @Published var isPlaying = false
    @Published var currentURL: URL? = nil
    @Published var launchAtLogin = false
    @Published var statusText = "未选择音频"
    @Published var recentFiles: [URL] = []

    /// 文件层错误（打不开 / 解码失败）→ 播放键显示红色警告。
    @Published var fileError: String? = nil
    /// 开机自启注册失败 → 「开机自启」按钮右侧显示红色警告。
    @Published var loginItemError: String? = nil

    private var stream: StreamingPlayer?
    private var timer: Timer?
    private var userPaused = false          // 用户显式暂停：自动逻辑绝不再抢着播
    private var forcePlayUntilClear = false // 手动播放时对方还在响 → 强行播到对方安静
    private var lastOtherPresent = false
    private var awake = true
    private var activityToken: NSObjectProtocol?

    /// 新版存 bookmark（不是明文路径），旧版键只用于一次性迁移。
    private let recentKey = "wn_recent_bookmarks"
    private let legacyRecentKey = "wn_recent_files"

    override init() {
        super.init()
        loadRecent()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if let last = recentFiles.first {
            // 硬边界：启动（含开机自启）只把上次的文件装好，一律停在暂停态。
            // 出声必须由人手动点播放。
            open(url: last, autoplay: false)
        }
        Log.write("launch · launchAtLogin=\(launchAtLogin)")
        startMonitoring()
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.awake = false
            self?.tick()
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.awake = true
            self?.tick()
        }
    }

    deinit {
        timer?.invalidate()
        endActivity()
    }

    // MARK: - 选择 / 打开本地音频

    /// 默认打开项目里的「音频」文件夹（根据 App 自身位置自动定位），找不到就退回桌面。
    private var defaultPickDirectory: URL {
        let projectRoot = Bundle.main.bundleURL      // .../WhiteNoise/build/WhiteNoise.app
            .deletingLastPathComponent()             // .../WhiteNoise/build
            .deletingLastPathComponent()             // .../WhiteNoise
        let audioDir = projectRoot.appendingPathComponent("音频")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: audioDir.path, isDirectory: &isDir), isDir.boolValue {
            return audioDir
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    /// 弹出系统文件选择器，默认停在项目的「音频」文件夹，选完即播。
    /// 只列真正能解码的格式（清单唯一出处：AudioFormats），避免选完才报错。
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = AudioFormats.contentTypes
        panel.directoryURL = defaultPickDirectory
        panel.message = "选择一个本地音频文件作为背景音（支持 \(AudioFormats.displayList)）"
        panel.prompt = "选这个"
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url, autoplay: true)
        }
    }

    func open(url: URL, autoplay: Bool) {
        guard prepare(url: url) else { return }
        currentURL = url
        fileError = nil
        userPaused = !autoplay
        addRecent(url)
        tick()
    }

    /// 只创建流式播放器，不出声。失败时写 fileError（UI 会变红）。
    /// 用 AVAudioEngine + AVAudioFile 边读边播，内存占用恒定（不再把整首读进内存）。
    private func prepare(url: URL) -> Bool {
        guard isAudioFile(url) else {
            fail("无法打开文件：只支持 \(AudioFormats.displayList)")
            return false
        }
        stream?.pause()
        guard let s = StreamingPlayer(url: url) else {
            fail("无法打开文件：音频解码失败或文件已损坏")
            return false
        }
        stream = s
        return true
    }

    private func fail(_ message: String) {
        fileError = message
        statusText = message
        isPlaying = false
        endActivity()
        Log.write("error · \(message)")
    }

    // MARK: - 播放控制（手动永远优先）

    func togglePlay() {
        if isPlaying {
            userPaused = true
            stopPlayback(reason: "by user")
        } else {
            if currentURL == nil {
                fileError = "还没选音频文件"
                statusText = fileError!
                return
            }
            userPaused = false
            fileError = nil
            // 若此刻正有别的声音，强行播到对方消失为止，解决「永远不恢复」的焦虑
            let (other, _) = AudioMonitor.otherAppsPlaying(excludingPID: ProcessInfo.processInfo.processIdentifier)
            forcePlayUntilClear = other
            startPlayback()
            tick()
        }
    }

    // MARK: - 监测循环

    private func startMonitoring() {
        timer?.invalidate()
        // 1 秒是刻意选的：Core Audio 没有可靠的「某进程开始出声」属性监听，
        // 只能轮询；降频会让"该让路时没让路"变得明显。
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 0.2
    }

    /// 每秒评估一次：是否应该播放。
    private func tick() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let (other, names) = AudioMonitor.otherAppsPlaying(excludingPID: myPID)
        let muted = AudioMonitor.isSystemMuted()
        let onConsole = AudioMonitor.isOnConsole()

        // 对方声音真正消失后，解除「强行播放」状态，自动逻辑恢复
        if lastOtherPresent && !other {
            forcePlayUntilClear = false
        }
        lastOtherPresent = other

        let effectiveOther = other && !forcePlayUntilClear
        let shouldPlay = !userPaused && awake && onConsole && !muted && !effectiveOther

        // 真相核对：以播放节点自己的状态为准。系统打断（拔耳机 / 切设备 / 解码失败）
        // 时它会自己停，但我们的小本子还写着"在放"——这里把它拉回来，下一轮会自动重启。
        if isPlaying, let s = stream, !s.isPlaying {
            isPlaying = false
            endActivity()
            Log.write("playback interrupted by system")
        }

        if shouldPlay && !isPlaying {
            startPlayback()
        } else if !shouldPlay && isPlaying {
            stopPlayback(reason: reasonText(other: effectiveOther, names: names, muted: muted))
        }

        if let err = fileError {
            statusText = err
        } else if userPaused {
            statusText = "已暂停：\(currentURL?.lastPathComponent ?? "未选择音频")"
        } else if !awake {
            statusText = "已暂停：系统睡眠"
        } else if muted {
            statusText = "已暂停：系统静音"
        } else if effectiveOther {
            let who = names.prefix(2).joined(separator: "、")
            statusText = "已暂停：检测到 \(who) 正在播放"
        } else if isPlaying {
            statusText = "播放中：\(currentURL?.lastPathComponent ?? "")"
        }
    }

    private func reasonText(other: Bool, names: [String], muted: Bool) -> String {
        if userPaused { return "by user" }
        if !awake { return "system sleep" }
        if muted { return "system muted" }
        if other { return "other audio: \(names.prefix(2).joined(separator: ","))" }
        return "unknown"
    }

    private func startPlayback() {
        // 播放器被回收（静音 / 睡眠时暂停）后需重建；否则直接续播
        if stream == nil, let url = currentURL {
            guard prepare(url: url) else { return }
        }
        guard let s = stream else { return }
        s.play()
        isPlaying = true
        beginActivity()
        Log.write("play · \(currentURL?.lastPathComponent ?? "?")")
    }

    private func stopPlayback(reason: String = "") {
        stream?.pause()
        isPlaying = false
        endActivity()
        if !reason.isEmpty { Log.write("pause · \(reason)") }
    }

    /// 播放期间禁止 App Nap，否则轮询会被降频，"该让路时没让路"。
    private func beginActivity() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "WhiteNoise is playing")
    }

    private func endActivity() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    // MARK: - 开机自启

    /// 点一下切换。开启时先尽力清掉可能指向「旧路径 / 已删除 App」的残留登录项，
    /// 再注册当前 App——换机器或重新 build 后点一下就能用，不需要先手动去关旧项。
    /// 无论成败都把状态同步成系统真实值，避免「显示已开但实际未注册」的假象。
    func toggleLaunchAtLogin() {
        let target = !launchAtLogin
        do {
            if target {
                try? SMAppService.mainApp.unregister()   // 清残留（失败忽略）
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
            Log.write("launchAtLogin → \(target)")
        } catch {
            loginItemError = "开机自启设置失败：\(error.localizedDescription)"
            Log.write("error · \(loginItemError ?? "")")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - 最近文件（bookmark，不落明文路径）

    private func loadRecent() {
        var urls: [URL] = []

        if let data = UserDefaults.standard.array(forKey: recentKey) as? [Data] {
            urls = data.compactMap { resolveBookmark($0) }
        }

        // 旧版存的是明文绝对路径 → 一次性迁移成 bookmark，然后删掉旧键
        if urls.isEmpty, let legacy = UserDefaults.standard.array(forKey: legacyRecentKey) as? [String] {
            let migrated = legacy.compactMap { URL(string: $0) }.filter { isAudioFile($0) }
            if !migrated.isEmpty {
                urls = migrated
                saveRecent(urls)
            }
            UserDefaults.standard.removeObject(forKey: legacyRecentKey)
        }

        recentFiles = urls
    }

    private func addRecent(_ url: URL) {
        var list = recentFiles.filter { $0.standardizedFileURL != url.standardizedFileURL }
        list.insert(url, at: 0)
        recentFiles = Array(list.prefix(2))   // 最近只保留最新两首用于点播
        saveRecent(recentFiles)
    }

    private func saveRecent(_ urls: [URL]) {
        let bookmarks = urls.compactMap {
            try? $0.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        UserDefaults.standard.set(bookmarks, forKey: recentKey)
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        return isAudioFile(url) ? url : nil
    }

    /// 旧记录不能再被信任：文件可能被改名、删掉，或者被换成别的东西。
    private func isAudioFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return AudioFormats.isSupported(url)
    }
}
