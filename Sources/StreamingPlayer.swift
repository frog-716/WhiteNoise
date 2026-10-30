import Foundation
import AVFoundation

/// 流式播放器：AVAudioEngine + AVAudioFile 边读边播，内存恒定（不再把整首读进内存）。
///
/// 循环＝环形读指针：文件切成固定帧数的块，读到末尾就把读位置拨回 0 继续读，
/// 不做 seek、不重建节点，所以回绕时没有额外开销。
///
/// 衔接靠「保持管线里有几块排着」：一块播完的回调里立刻补一块，
/// 节点内部队列始终不断流。块边界本身仍有极短空隙（块尺寸 + 解码延迟），
/// 白噪音场景听不出来，已确认可接受。
final class StreamingPlayer {

    /// 16384 帧 ≈ 44.1 kHz 下 0.37 秒：够长，回绕次数少；又够短，暂停响应快。
    private static let chunkFrames: AVAudioFrameCount = 16384
    /// 管线深度：排 3 块，补块慢一拍也不会断。
    private static let pipeline = 3

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let file: AVAudioFile
    private let format: AVAudioFormat
    private let name: String

    /// 调度状态和文件读取都只在这个串行队列上发生（AVAudioFile 不是线程安全的）。
    private let queue = DispatchQueue(label: "wn.stream.scheduler")
    private var playing = false
    private var queued = 0
    private var configObserver: NSObjectProtocol?

    /// 节点是否真的在出声。UI 的「图标不许说谎」以它为准。
    var isPlaying: Bool { node.isPlaying }

    init?(url: URL) {
        guard let opened = try? AVAudioFile(forReading: url) else {
            Log.write("error · open failed: \(url.lastPathComponent)")
            return nil
        }
        file = opened
        format = opened.processingFormat
        name = url.lastPathComponent

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            Log.write("error · engine start: \(error.localizedDescription)")
            return nil
        }

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    deinit {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        node.stop()
        engine.stop()
    }

    /// 开始（或继续）播放：从文件当前读位置接着读，暂停后恢复不会跳回开头。
    func play() {
        if !engine.isRunning, !startEngine() { return }
        guard !playing else { return }
        playing = true
        queue.sync {
            queued = 0
            fill()
        }
        node.play()
    }

    /// 暂停：停节点清空已排队的块（回调仍会来，但 playing 已为 false，不再补）。
    func pause() {
        guard playing else { return }
        playing = false
        node.stop()
        queue.sync { queued = 0 }
    }

    // MARK: - 环形调度（只在 queue 上调用）

    /// 把管线填满：始终维持 `pipeline` 块在队列里等播。
    private func fill() {
        while playing, queued < Self.pipeline {
            guard let buffer = readChunk() else { return }
            queued += 1
            node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    self.queued = max(0, self.queued - 1)
                    self.fill()
                }
            }
        }
    }

    /// 读一块；读到末尾就拨回开头——这就是循环。
    private func readChunk() -> AVAudioPCMBuffer? {
        if file.framePosition >= file.length {
            file.framePosition = 0
            // 有这行日志，才分得清「在循环」和「读完了静悄悄停住」
            Log.write("loop · \(name)")
        }
        let remaining = file.length - file.framePosition
        guard remaining > 0 else { return nil }

        let frames = AVAudioFrameCount(min(remaining, Int64(Self.chunkFrames)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        do {
            try file.read(into: buffer, frameCount: frames)
        } catch {
            Log.write("error · read chunk: \(error.localizedDescription)")
            return nil
        }
        return buffer
    }

    // MARK: - 设备切换

    private func startEngine() -> Bool {
        do {
            try engine.start()
            return true
        } catch {
            Log.write("error · engine restart: \(error.localizedDescription)")
            return false
        }
    }

    /// 拔耳机 / 蓝牙断连会让引擎失效：重连接、重启、续播。
    private func handleConfigurationChange() {
        guard playing else { return }
        Log.write("engine config change · restarting")
        playing = false          // 先关闸，避免旧回调补块
        node.stop()
        queue.sync { queued = 0 }
        engine.connect(node, to: engine.mainMixerNode, format: format)
        playing = startEngine()
        guard playing else { return }
        queue.sync { fill() }
        node.play()
    }
}
