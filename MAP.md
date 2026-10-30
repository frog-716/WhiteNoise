# MAP.md — WhiteNoise

macOS 菜单栏白噪音播放器。别人出声 → 自动暂停；对方安静 → 自动恢复。纯本地，无网络。

## 一句话架构

```
NSStatusItem + NSPopover(ContentView) ──observes──> PlayerController ──reads──> AudioMonitor(CoreAudio)
                                              │
                                              ├── StreamingPlayer (AVAudioEngine + AVAudioFile，分块读 + 环形回绕)
                                              ├── AudioFormats（能播哪些格式的唯一出处）
                                              ├── Timer 1s → tick()  ← 状态机唯一入口
                                              ├── UserDefaults["wn_recent_bookmarks"]（bookmark，不是明文路径）
                                              ├── SMAppService.mainApp（开机自启）
                                              └── Log → ~/Library/Logs/WhiteNoise.log
```

## 文件职责

| 文件 | 职责 | 不该做的事 |
| --- | --- | --- |
| `Sources/WhiteNoiseApp.swift` | `@main` 入口、AppKit `NSStatusItem` 菜单栏图标 + `NSPopover`（内嵌 SwiftUI `ContentView`）、单实例互斥、清理旧版登录项、持有 `PlayerController` | 不放业务逻辑 |
| `Sources/PlayerController.swift` | 全部状态与状态机：`isPlaying` / `userPaused` / `forcePlayUntilClear` / `awake` / `fileError` / `loginItemError`；`tick()` 每 1 秒评估；选文件、最近记录、开机自启 | 不直接调 Core Audio API（仅经 AudioMonitor / StreamingPlayer）；不读文件格式细节（问 AudioFormats） |
| `Sources/AudioMonitor.swift` | 纯函数式系统状态读取：`otherAppsPlaying` / `isSystemMuted` / `isOnConsole` | 不持状态、不改播放 |
| `Sources/StreamingPlayer.swift` | `AVAudioEngine + AVAudioFile` 流式播放：16384 帧一块、管线保持 3 块、读到头回绕到 0、设备切换自动重启 | 不读系统音频状态、不碰 UI |
| `Sources/AudioFormats.swift` | 支持的扩展名清单 + `contentTypes`（选择器用）+ `displayList`（报错/提示文案用） | 不判断文件是否存在 |
| `Sources/ContentView.swift` | 弹窗 UI（播放图标 + 选文件 + 自启 + 最近）；不写死面板宽度；报错只换按钮内的图标、不改宽度 | 不写播放逻辑 |
| `Sources/Log.swift` | 串行写日志、512 KB 自动重建 | 不记完整路径（只记文件名） |

## 核心流程：tick()

唯一判定式（改行为只改这一行）：

```swift
shouldPlay = !userPaused && awake && onConsole && !muted && !otherAudio
```

- `shouldPlay && !isPlaying` → `startPlayback()`
- `!shouldPlay && isPlaying` → `stopPlayback(reason:)`
- `tick()` 触发源：1 秒 Timer、睡眠/唤醒通知、播放/选文件后的主动调用。**全部在主线程**，不加锁。

优先级：手动暂停(`userPaused`) > 强制播放(`forcePlayUntilClear`) > 自动判定。

## 流式播放与循环

- 一个 `AVAudioFile` 打开后**只在一个串行队列上读**（它不线程安全）；`AVAudioPlayerNode` 只负责播。
- 每次调度 16384 帧（≈0.37 s），完成回调里立刻补一块，管线始终有 3 块——这样块与块之间不会断。
- `file.framePosition >= file.length` 时拨回 0：**同一个文件对象继续读**，不重新 open、不 seek、不重建节点。每次回绕写一行 `loop ·` 日志，用来区分「在循环」和「读完了静悄悄停住」。
- 回绕点仍有几毫秒空隙（块边界 + 解码），已确认可接受；做真无缝需要预混两条环形流，超出本项目的必要复杂度。

## 关键约束（改代码前必读）

1. **Deployment Target ≥ 14.2**：`kAudioHardwarePropertyProcessObjectList` / `kAudioProcessPropertyIsRunningOutput` 是 14.2 才公开的 API。
2. **不加网络、不加麦克风**：产品的全部卖点就是"纯本地"。任何网络依赖都会让 README 的隐私承诺变成假话。
3. **手动操作必须永远压过自动逻辑**，否则用户会觉得 App "抢控制权"。
4. **自动暂停常开、不设开关**：这是它唯一的功能。加回开关等于承认它可以被关掉。
5. **出声必须有人授权**：`init()` 里 `open(autoplay: false)` 写死。任何"开机/唤醒/启动就自动放"的改动都是在制造事故。
6. **失败必须可见**：`fileError` / `loginItemError` 两个字段驱动 UI 的红色三角。新增错误分支不许只写 `statusText` 就完事——`statusText` 现在只在悬停提示里。
7. **图标不许说谎**：`isPlaying` 每轮都要和 `stream.isPlaying`（`AVAudioPlayerNode.isPlaying`）核对。
8. **格式清单只有 AudioFormats 一个出处**：加一个能播的格式，只改 `AudioFormats.extensions`；别在 ContentView 或 NSOpenPanel 里另写一份 `[.audio]`（那样会把 ogg / wma 也放进选择器，用户选完才报错）。
9. **不用 SwiftUI `MenuBarExtra`**：本项目实测 `MenuBarExtra(.window)` 在代理型 App（`LSUIElement=true`）下要么启动即被系统判为"无界面"退出，要么图标不进状态栏（只铺一层看不见的窗口）。改用 AppKit `NSStatusItem + NSPopover`；状态项必须在 `app.run()` **之前** 创建才会被状态栏托管。
10. **一个 bundle id 一个进程**：`WhiteNoiseApp.terminateOtherInstances()`。去掉它，两个实例会互相把对方当成"别的 App 在出声"。
11. **bundle id 是状态栏缓存的一部分**：曾出现旧 id `com.github.frog716.whitenoise` 被系统状态项缓存"毒化"——同一个二进制换新 id 立刻正常显示。若日后再遇到"进程在跑但菜单栏无图标"，先换 bundle id 验证，别死磕代码。换 id 后旧登录项（BTM 托管，不是 `LaunchAgents` plist）需另行清理。
12. **面板宽度不写死**：`ContentView` 不给 `.frame(width:)`，宽度由按钮行撑开（约 248 pt），由 `NSHostingController.sizingOptions = [.preferredContentSize]` 自动跟随。写死宽度会让按钮一改就出现大片空白。
13. 无沙盒、ad-hoc 签名、无 entitlements。正式分发前必须处理签名与公证。

## 构建

```bash
./build.sh          # swiftc 直编 Sources/*.swift + ad-hoc 签名 → build/WhiteNoise.app（build/ 已 gitignore）
```

`build.sh` 用 `SRC=(Sources/*.swift)` 通配收文件——新增文件不用改脚本（历史上漏加过一个文件，白查了半天启动崩溃）。

## 资产与文档

- `Resources/app-icon-source.jpg` 原始设计稿 → `Resources/AppIcon-1024.png` → `Resources/AppIcon.icns`（派生物，打包时拷进 bundle）
- `docs/images/*.png` 只服务 README，不参与打包；都是脚本离屏渲染生成（`NSHostingView` + `NSBitmapImageRep` 2× 输出），改界面后要重新生成，不要直接截屏（会带壁纸和分辨率噪音）
- `音频/` 本地音频，已被 `.gitignore` 忽略，不进仓库
