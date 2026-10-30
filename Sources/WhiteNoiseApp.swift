import SwiftUI
import AppKit

// MARK: - 单实例互斥 / 旧登录项清理

/// 只准开一个：新实例启动时把旧实例踢掉。
/// 否则两个进程会同时放同一首，还会把对方当成"别的 App 在出声"互相摁停。
private func terminateOtherInstances() {
    guard let bundleID = Bundle.main.bundleIdentifier else { return }
    let myPID = ProcessInfo.processInfo.processIdentifier
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    where app.processIdentifier != myPID {
        app.terminate()
    }
}

/// 清掉旧版遗留的登录项 plist。
/// 早期版本用过 com.example.whitenoise 这个占位身份证号，后来又换过一次 bundle id，
/// 这些旧 id 的登录项不会被新版本自动覆盖、也清不掉；不处理的话，登录时旧项仍会拉起
/// App，和「只准开一个」打架。用户无需任何手动操作。
private func cleanLegacyLoginItems() {
    let agents = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")
    let stale = ["com.example.whitenoise.plist",
                 "com.github.frog716.whitenoise.plist"]
    for name in stale {
        let url = agents.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { continue }
        try? FileManager.default.removeItem(at: url)
        Log.write("removed legacy login item: \(name)")
    }
}

// MARK: - 菜单栏 App（AppKit NSStatusItem + NSPopover）

/// 用 AppKit 的 NSStatusItem + NSPopover 承载菜单栏图标和弹出面板。
///
/// 不用 SwiftUI 的 MenuBarExtra：在本项目环境下实测不可靠（启动即退出 / 图标不进状态栏）。
/// NSStatusItem 是几十年验证过的老方案，行为确定。
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var player: PlayerController!

    /// 在 app.run() 之前创建状态项——这是能稳定进入菜单栏的时机。
    func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        let img = NSImage(systemSymbolName: "speaker.wave.2",
                          accessibilityDescription: "WhiteNoise")
        img?.isTemplate = true
        button.image = img
        button.target = self
        button.action = #selector(togglePopover)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        player = PlayerController()

        let hosting = NSHostingController(rootView: ContentView().environmentObject(player))
        hosting.sizingOptions = [.preferredContentSize]
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = hosting
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 关掉所有窗口也不退出——菜单栏 App 靠状态栏图标常驻。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// MARK: - 入口

@main
struct WhiteNoiseApp {
    static func main() {
        terminateOtherInstances()
        cleanLegacyLoginItems()

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        delegate.setUpStatusItem()   // 关键：在 run 之前建
        app.run()
    }
}
