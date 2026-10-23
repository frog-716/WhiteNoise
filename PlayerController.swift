import Foundation
import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement

/// 播放控制器：状态机 + 轮询监测 + 文件选择 + 最近记录。
/// 核心逻辑：每 1 秒评估一次条件，决定是否该播；手动开关永远优先。
final class PlayerController: ObservableObject {

    @Published var isPlaying = false
    @Published var currentURL: URL? = nil
    @Published var volume: Double = 0.8
    @Published var autoPauseEnabled = true
    @Published var statusText = "未选择音频"
    @Published var recentFiles: [URL] = []

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var userPaused = false          // 用户显式暂停：自动逻辑绝不再抢着播
    private var forcePlayUntilClear = false // 用户手动播放时，若正有别人出声，则强行播到对方消失
    private var lastOtherPresent = false
    private var awake = true

    private let recentKey = "wn_recent_files"

    init() {
        loadRecent()
        if let last = recentFiles.first {
            open(url: last, autoplay: true)
        }
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

    // MARK: - 选择 / 打开本地音频

    /// 默认打开项目里的「音频」文件夹（根据 App 自身位置自动定位），找不到就退回桌面。
    private var defaultPickDirectory: URL {
        let projectRoot = Bundle.main.bundleURL      // .../White-Noise/build/White-Noise.app
            .deletingLastPathComponent()             // .../White-Noise/build
            .deletingLastPathComponent()             // .../White-Noise
        let audioDir = projectRoot.appendingPathComponent("音频")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: audioDir.path, isDirectory: &isDir), isDir.boolValue {
            return audioDir
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    /// 弹出系统文件选择器，默认停在项目的「音频」文件夹，选完即播。
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.directoryURL = defaultPickDirectory
        panel.message = "选择一个本地音频文件作为背景音"
        panel.prompt = "选这个"
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url, autoplay: true)
        }
    }

    func open(url: URL, autoplay: Bool) {
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = -1          // -1 = 无限循环
            newPlayer.volume = Float(volume)
            newPlayer.prepareToPlay()
            player?.stop()
            player = newPlayer
            currentURL = url
            userPaused = !autoplay
            addRecent(url)
            tick()
        } catch {
            statusText = "无法打开文件：\(error.localizedDescription)"
        }
    }

    // MARK: - 播放控制（手动永远优先）

    func togglePlay() {
        if isPlaying {
            userPaused = true
            stopPlayback()
        } else {
            userPaused = false
            // 若此刻正有别的声音，强行播到对方消失为止，解决「永远不恢复」的焦虑
            let (other, _) = AudioMonitor.otherAppsPlaying(excludingPID: ProcessInfo.processInfo.processIdentifier)
            forcePlayUntilClear = other
            startPlayback()
            tick()
        }
    }

    func setVolume(_ v: Double) {
        volume = v
        player?.volume = Float(v)
    }

    // MARK: - 监测循环

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
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
        let shouldPlay = !userPaused && awake && onConsole && !muted && (!autoPauseEnabled || !effectiveOther)

        if shouldPlay && !isPlaying {
            startPlayback()
        } else if !shouldPlay && isPlaying {
            stopPlayback()
        }

        // 状态文案（让人知道为什么停了）
        if userPaused {
            statusText = "已暂停（手动）"
        } else if !awake {
            statusText = "已暂停：系统睡眠"
        } else if !onConsole {
            statusText = "已暂停：无用户会话"
        } else if muted {
            statusText = "已暂停：系统静音"
        } else if autoPauseEnabled && effectiveOther {
            let who = names.prefix(2).joined(separator: "、")
            statusText = "已暂停：检测到 \(who) 正在播放"
        } else if isPlaying {
            statusText = "播放中：\(currentURL?.lastPathComponent ?? "")"
        }
    }

    private func startPlayback() {
        player?.volume = Float(volume)
        if player?.play() == true {
            isPlaying = true
        }
    }

    private func stopPlayback() {
        player?.pause()
        isPlaying = false
    }

    // MARK: - 开机自启

    func isLaunchAtLogin() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusText = "开机自启设置失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 最近文件（记忆上次选择）

    private func loadRecent() {
        if let arr = UserDefaults.standard.array(forKey: recentKey) as? [String] {
            // 过滤掉已被移动/删除的失效路径，避免启动时报"无法打开文件"
            recentFiles = arr.compactMap { URL(string: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    private func addRecent(_ url: URL) {
        var list = recentFiles.filter { $0 != url }
        list.insert(url, at: 0)
        recentFiles = Array(list.prefix(5))
        UserDefaults.standard.set(recentFiles.map { $0.absoluteString }, forKey: recentKey)
    }
}
