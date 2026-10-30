import SwiftUI
import AppKit

/// 菜单栏弹出的小界面：播放/暂停、选文件、最近文件、自动暂停开关、开机自启、退出。
struct ContentView: View {
    @EnvironmentObject var player: PlayerController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题 + 退出按钮（右上角）
            HStack {
                Text("WhiteNoise").font(.headline)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
            }

            Divider()

            Button(action: { player.togglePlay() }) {
                Label(player.isPlaying ? "暂停" : "播放",
                      systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 64)
            }

            Text(player.statusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Button("选择音频文件…") { player.chooseFile() }

            if !player.recentFiles.isEmpty {
                Text("最近使用").font(.caption).foregroundColor(.secondary)
                ForEach(player.recentFiles, id: \.self) { url in
                    Button(action: { player.open(url: url, autoplay: true) }) {
                        Text(url.lastPathComponent).lineLimit(1)
                    }
                    .buttonStyle(.link)
                    .help(url.path)
                }
            }

            Toggle("自动暂停（检测其他声音）", isOn: $player.autoPauseEnabled)
            Toggle("开机自启", isOn: Binding(
                get: { player.launchAtLogin },
                set: { player.updateLaunchAtLogin($0) }))
        }
        .padding(16)
        .frame(width: 290)
    }
}
