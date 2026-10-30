import Foundation
import AppKit
import CoreAudio
import AudioToolbox

/// 封装所有 Core Audio 系统/音频状态读取。
/// 注意：kAudioHardwarePropertyProcessObjectList / kAudioProcessPropertyIsRunningOutput
/// 是 macOS 14.2 才公开的 API，Deployment Target 必须 >= 14.2。
struct AudioMonitor {

    /// 返回「除自己以外，是否有别的进程正在输出音频」以及它们的名字。
    /// 这正是实现「别的声音一响就暂停」的核心能力。
    static func otherAppsPlaying(excludingPID: pid_t) -> (isPlaying: Bool, names: [String]) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return (false, []) }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            return (false, [])
        }

        var names: [String] = []
        for id in ids {
            // 取该进程的 PID，跳过我们自己
            var pidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            let pidStatus = AudioObjectGetPropertyData(id, &pidAddr, 0, nil, &pidSize, &pid)
            if pidStatus == noErr, pid == excludingPID { continue }

            // 该进程是否正在输出音频（注意：这是「持有活跃音频 IO」，不代表一定在出声）
            var runAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &runAddr, 0, nil, &runSize, &running) == noErr, running != 0 else {
                continue
            }

            let name: String
            if pidStatus == noErr, let app = NSRunningApplication(processIdentifier: pid) {
                name = app.localizedName ?? "PID \(pid)"
            } else {
                name = "PID \(pid)"
            }
            names.append(name)
        }
        return (!names.isEmpty, names)
    }

    /// 默认输出设备是否被静音（主通道或左右声道任一静音即视为静音）。
    static func isSystemMuted() -> Bool {
        var defAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0)
        var devSize = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defAddr, 0, nil, &devSize, &device) == noErr,
              device != 0 else { return false }

        for element in [kAudioObjectPropertyElementMain, 0, 1] {
            var muteAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element)
            var mute: UInt32 = 0
            var muteSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &muteAddr, 0, nil, &muteSize, &mute) == noErr, mute != 0 {
                return true
            }
        }
        return false
    }

    /// 是否有控制台用户会话。
    /// 对一个「用户自己启动的菜单栏代理 App」来说，它本就不可能运行在登录界面，
    /// 因此这里直接返回 true（保留接口，避免引入易碎的私有 API）。
    static func isOnConsole() -> Bool { true }
}
