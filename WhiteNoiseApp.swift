import SwiftUI

@main
struct WhiteNoiseApp: App {
    @StateObject private var player = PlayerController()

    var body: some Scene {
        // 菜单栏图标 + 弹出小窗口（.window 风格支持按钮/滑块等交互）
        MenuBarExtra("White-Noise", systemImage: "speaker.wave.2") {
            ContentView().environmentObject(player)
        }
        .menuBarExtraStyle(.window)

        // 不显示主窗口
        Settings { EmptyView() }
    }
}
