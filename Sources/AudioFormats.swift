import Foundation
import UniformTypeIdentifiers

/// 能播哪些格式——全项目唯一出处：文件选择器、最近记录校验、报错文案都读这里。
///
/// 只收 Core Audio 真能解码的容器（`AVAudioFile` 直接读）：
/// m4a / aac / mp3 / wav / aiff / flac / caf。
/// 故意不含 ogg、opus、wma：UTType 把它们标成 audio，但 macOS 没有对应解码器，
/// 收进选择器只会让用户选完才看到报错。
enum AudioFormats {

    static let extensions = ["m4a", "aac", "mp3", "wav", "aif", "aiff", "flac", "caf"]

    /// 系统文件选择器允许的类型。
    static let contentTypes: [UTType] = extensions.compactMap { UTType(filenameExtension: $0) }

    /// 给用户看的格式清单。
    static let displayList = "m4a、aac、mp3、wav、aiff、flac、caf"

    static func isSupported(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}
