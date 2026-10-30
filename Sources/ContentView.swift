import SwiftUI
import AppKit

/// 菜单栏弹出的小界面。
/// 一行操作：[播放/暂停] [选择音频…] [开机自启]，下面「最近」两条。
///
/// 两条设计约束：
/// - 没有开关：自动暂停常开；开机自启用按钮底色表示状态（蓝＝已开，灰＝未开）。
/// - 不写死面板宽度：宽度由这一行内容撑开。按钮只有文字那么宽，面板就跟着收窄。
struct ContentView: View {
    @EnvironmentObject var player: PlayerController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("WhiteNoise").font(.headline)
                Spacer(minLength: 12)
                Button("退出") { NSApplication.shared.terminate(nil) }
            }

            Divider()

            HStack(spacing: 6) {
                playButton
                Button("选择音频…") { player.chooseFile() }
                    .buttonStyle(.bordered)
                    .help("支持 \(AudioFormats.displayList)")
                launchAtLoginButton
            }
            .controlSize(.regular)

            if !player.recentFiles.isEmpty {
                recentSection
            }
        }
        .padding(14)
    }

    // MARK: - 播放键

    /// 只有图标。文件出错时图标本身变成红色三角（不额外加文字、不撑宽按钮）。
    private var playButton: some View {
        Button(action: { player.togglePlay() }) {
            Image(systemName: playIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(player.fileError != nil ? .red : .primary)
                .frame(width: 22)
        }
        .buttonStyle(.bordered)
        .help(player.statusText)
    }

    private var playIcon: String {
        if player.fileError != nil { return "exclamationmark.triangle.fill" }
        return player.isPlaying ? "pause.fill" : "play.fill"
    }

    // MARK: - 开机自启

    /// 复用系统按钮样式：尺寸由文字决定（不再写死宽度），开启时整键变蓝。
    /// 报错时红三角画在按钮**里面**，和播放键的红色三角同一套路。
    private var launchAtLoginButton: some View {
        Group {
            if player.launchAtLogin {
                Button(action: player.toggleLaunchAtLogin) { launchLabel }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(nsColor: .linkColor))
            } else {
                Button(action: player.toggleLaunchAtLogin) { launchLabel }
                    .buttonStyle(.bordered)
            }
        }
        .help(launchHint)
    }

    /// 正常显示「开机自启」，出错时只留红三角。
    /// ZStack 里的隐形文字是尺寸锚：不管显示文字还是三角，按钮宽度恒定，
    /// 面板宽度也就不会因为报错而变。
    private var launchLabel: some View {
        ZStack {
            Text("开机自启")
                .opacity(player.loginItemError == nil ? 1 : 0)
            if player.loginItemError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.red)
            }
        }
    }

    private var launchHint: String {
        if let error = player.loginItemError { return "开机自启设置失败：\(error)" }
        return player.launchAtLogin ? "登录时自动启动（点击关闭）" : "登录时自动启动（点击开启）"
    }

    // MARK: - 最近

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("最近").font(.caption).foregroundColor(.secondary)
            ForEach(player.recentFiles, id: \.self) { url in
                Button(action: { player.open(url: url, autoplay: true) }) {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.link)
                .frame(maxWidth: 220, alignment: .leading)
                .help(url.path)
            }
        }
    }
}
