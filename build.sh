#!/bin/zsh
# 一键编译 + 打包成 .app + 本地签名。不需要 Xcode、不需要开发者账号。
set -e

cd "$(dirname "$0")"

APP_NAME="White-Noise"
APP="build/${APP_NAME}.app"
MIN_MACOS="14.2"
SRC=(WhiteNoiseApp.swift PlayerController.swift AudioMonitor.swift ContentView.swift)

echo "==> 清理旧构建"
rm -rf build
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"

echo "==> 编译 (swiftc, target ${MIN_MACOS})"
swiftc \
  -target arm64-apple-macosx${MIN_MACOS} \
  -framework AppKit \
  -framework AVFoundation \
  -framework CoreAudio \
  -framework AudioToolbox \
  -framework SwiftUI \
  -framework UniformTypeIdentifiers \
  -O \
  -o "${APP}/Contents/MacOS/${APP_NAME}" \
  "${SRC[@]}"

echo "==> 拷贝 Info.plist"
cp Info.plist "${APP}/Contents/Info.plist"

echo "==> 拷贝 App 图标"
cp AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"

echo "==> 本地签名 (ad-hoc)"
codesign --force --deep --sign - "${APP}"

echo "==> 完成: ${APP}"
echo "    双击打开，或在终端执行: open ${APP}"
