<p align="center">
  <img src="docs/images/banner.png" alt="White-Noise" width="100%">
</p>

<h1 align="center">White-Noise</h1>

<p align="center">
  <b>让背景音学会「让路」——别人出声，它就自动安静。</b><br>
  macOS 菜单栏白噪音播放器 · 循环播放本地音频 · 检测到其他声音自动暂停 / 恢复 · 纯本地零上传
</p>

<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-14.2%2B-blue">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9%2B-orange">
  <img alt="License" src="https://img.shields.io/badge/License-MIT-green">
  <img alt="Platform" src="https://img.shields.io/badge/Apple%20Silicon%20%7C%20Intel-lightgrey">
</p>

---

## 这是什么

**White-Noise** 是一个常驻 macOS 菜单栏的轻量白噪音工具。它能**循环播放你指定的本地音频**（白噪音、雨声、学习氛围音等），并在你开始看视频、听歌或开会——也就是**有其他 App 出声时，自动把背景音暂停**；等对方安静下来，再**自动恢复**。

整个过程无需手动切换，也不会打断正在播放的媒体，适合专注工作、阅读、学习或需要稳定环境音的场景。

<p align="center">
  <img src="docs/images/ui.png" width="360" alt="White-Noise 界面">
</p>

## ✨ 主要特性

- **自动避让**：检测到其他 App 播放音频（视频 / 音乐 / 通话）时自动暂停，结束后自动恢复，带 2 秒去抖，避免通知提示音误触发。
- **无缝循环**：本地音频自动循环播放，支持随时切换文件，并记住上次选择。
- **菜单栏常驻**：不占用 Dock、不遮挡桌面，点开图标即用小面板操作。
- **自选音频**：通过系统文件选择器挑选任意本地音频（M4A / MP3 / WAV / AIFF / CAF / ALAC 等），无需内置曲库。
- **开机自启**：可在面板中一键开启，登录后自动开始播放。
- **纯本地 · 零上传**：不录音、不开麦克风、不接管系统声音，音频数据不离开你的电脑。

## 🎬 工作流程

<p align="center">
  <img src="docs/images/flow.png" width="100%" alt="工作流程">
</p>

系统同时监测四个条件，全部满足才播放：

1. **Mac 处于唤醒状态** —— 睡眠时暂停；
2. **用户会话已登录** —— 登录界面不播放；
3. **系统未静音** —— 读取输出设备的静音 / 音量状态；
4. **没有其他 App 正在播放音频** —— 基于 Core Audio 进程音频枚举判断。

任一条变化即暂停，恢复时做去抖处理，避免频繁闪烁。

## 🚀 快速开始

### 环境要求

- macOS **14.2 或更高**（依赖 Core Audio 的进程音频枚举 API）
- Xcode Command Line Tools（提供 `swiftc`）

  ```bash
  xcode-select --install
  ```

### 编译与运行

```bash
git clone https://github.com/frog-716/White-Noise.git
cd White-Noise
./build.sh                    # 编译 + 本地签名，生成 build/White-Noise.app
open build/White-Noise.app    # 启动
```

无需 Xcode 工程、无需开发者账号。`build.sh` 使用 `swiftc` 直接编译，并用 ad-hoc 签名打包成 `.app`。

### 使用

1. 启动后，菜单栏出现**扬声器图标**；
2. 点开图标 → **选择音频文件…** → 选中任意本地音频，立即开始循环播放；
3. 打开视频 / 音乐 / 通话时，它会**自动暂停**；对方结束后**自动恢复**；
4. 面板底部可开关「自动暂停」「开机自启」，也可随时手动播放 / 暂停。

## 📁 项目结构

```text
White-Noise/
├── WhiteNoiseApp.swift      入口（菜单栏图标 + 弹窗）
├── PlayerController.swift   播放控制 / 状态轮询 / 文件选择 / 开机自启
├── AudioMonitor.swift       Core Audio：谁在出声、是否静音
├── ContentView.swift        弹窗界面
├── Assets/                  图标源文件
├── docs/images/             README 图片
├── AppIcon.icns             App 图标
├── Info.plist / build.sh    bundle 配置与一键编译脚本
└── 音频/                    本地音频目录（已在 .gitignore 中忽略，不上传）
```

> `音频/` 目录不会被提交，仓库中不包含任何用户音频。请自备音频文件放入该目录，或用「选择音频文件…」从任意位置选择。

## 🔒 隐私与安全

- 音频文件**仅在本机播放**，不上传、不联网；
- 不访问麦克风、不录音、不截取系统音频内容；
- 仅通过公开的 Core Audio 接口**读取**「哪些进程正在输出音频」这一状态，用于判断是否暂停；
- 开源可审计，欢迎查看源码。

## ⚠️ 已知限制

- 静音的通话、暂停但仍占用音频通道的视频，系统会持续报告「正在播放」，可能导致背景音暂不恢复——此时可手动点「播放」或关闭「自动暂停」兜底。
- 极少数不走标准音频通道的应用可能检测不到。
- 不能压低其他 App 的音量（只控制自身播放 / 暂停）。

## 📄 License

本项目采用 [MIT License](LICENSE)。

---

<p align="center"><sub>Made for focused work · macOS menu bar · White-Noise</sub></p>
