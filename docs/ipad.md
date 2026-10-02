# Slive iPad 专用版

此版本在 `codex/ipad-multiview` 分支开发，面向 iPadOS 15.0 及以上的 iPad。应用名称为 **Slive iPad**，Bundle ID 为 `com.yinkai666.slive.ipad`，设备类型仅为 iPad，支持四个方向及系统分屏窗口。

“检查更新”固定打开 iPad 专用构建页面，即使侧载重新签名改变 Bundle ID，也不会回到普通版更新渠道。

## 多直播观看

从首页的「多直播」进入，也可以长按关注列表中的主播加入多直播。支持同时观看 1–4 个直播间；可从关注中选择，或选择平台并手动填写房间 ID。窗口尺寸变化时会调整布局。

同时只允许一个直播间发声，点击对应音源按钮即可切换。每一路可单独选择清晰度，默认优先使用中等档位，降低多路同时播放时的解码和网络负担。聚焦某一路会放大显示该画面，其他直播间仍继续运行；不需要的直播间应直接关闭，以释放资源。

此版本的多直播模式暂不包含多路弹幕和观看历史统计。四路播放是否流畅取决于 iPad 型号、直播码率及网络，建议先从两路开始体验。

## 与原版共存

原版 Bundle ID 为 `com.yinkai666.slive`。iPad 版使用独立标识和系统数据容器，因此可同时安装，不会直接覆盖原版应用及其本地数据。首次安装的数据为空；如需迁移关注及设置，请从原版导出备份，再在 iPad 版导入。两个版本连接同一 WebDAV 目录时仍可能同步同一份远端数据，建议先备份或使用独立同步目录。

重新签名时应保留 `com.yinkai666.slive.ipad`，或使用另一个与原版不同且固定的标识；不要改回原版 Bundle ID。后续升级保持同一个签名标识，才能继续使用 iPad 版已有数据。

## GitHub Actions 构建

推送到本分支会运行 **iPad build**。也可选择该分支手动运行 `.github/workflows/build_ipad.yml`。构建使用 `simple_live_app/pubspec.yaml` 指定的 Flutter 版本，先执行多直播布局、房间列表和过期任务隔离的回归检查及新模块静态分析，再构建 iOS Release，并检查产物 Bundle ID、显示名与 iPad 设备类型。

在该次运行的 Artifacts 中下载 `Slive-iPad-unsigned`，解压得到 `Slive-iPad-unsigned.ipa`。这是未签名安装包，需要使用自己的证书或侧载工具签名后安装。

本分支保留旧工作流文件，但关闭其所有任务，防止手动触发、PR 或标签推送运行跨平台构建。以后向普通版本合并功能时，不应把这些工作流禁用设置和 iPad 专用 Bundle ID 合回普通版本。

## 本地构建

需要 macOS、Xcode 和项目要求的 Flutter SDK。在 `simple_live_app` 下执行：

```sh
flutter pub get
flutter build ios --release --no-codesign
mkdir -p build/ipad/Payload
ditto build/ios/iphoneos/Runner.app build/ipad/Payload/Runner.app
cd build/ipad
zip -q -r Slive-iPad-unsigned.ipa Payload
```

Windows 可以修改和检查 Dart 代码，但不能运行 Xcode 的 iPad 真机构建。双路或多路视频的流畅度、发热与耗电需要在实际 iPad 上验证。
