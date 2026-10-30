import Foundation

/// 极简日志：只记状态跃迁和错误（路径只记文件名），落到 ~/Library/Logs/WhiteNoise.log。
/// 出问题时这是唯一的排查线索——没有它，用户报「没声音」就只能靠猜。
///
/// 写入串行化：播放器的补块回调、轮询、UI 动作会从不同线程写同一文件。
enum Log {
    private static let fileURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/WhiteNoise.log")
    private static let formatter = ISO8601DateFormatter()
    private static let maxBytes = 512 * 1024
    private static let queue = DispatchQueue(label: "wn.log")

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.async {
            let fm = FileManager.default
            if let size = try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int, size > maxBytes {
                try? fm.removeItem(at: fileURL)
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}
