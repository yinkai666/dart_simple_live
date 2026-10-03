# 普通 dev 版播放稳定性修复

本次将 iPad 分支已经验证的 mpv 原生 EOF 状态修复和普通单直播稳定性改动移入 dev。普通版仍使用 `com.yinkai666.slive`，支持 iPhone 与 iPad，未加入多直播界面或 iPad 专用安装标识，未关闭其他平台构建。

## 原生修复

现有崩溃报告匹配 `mpv 0.36.0` 的 `loadfile.c:1918 / mpctx->stop_play` 断言。iOS 构建回移上游 d59f4fd 修复，重编 ARM64 动态库，在 Xcode 构建后、IPA 封装前安装并核对二进制哈希、UUID、dSYM 和补丁记录。保留原有断言。构建方法与来源见 `scripts/native-mpv/README.md`。

仅 iOS 原生库使用这套重编流程，其他平台的原生库依赖未替换。开发和 PR 工作流均接入 iOS 校验；原有 macOS、Android、Windows、Linux 和 Flatpak 任务保留。

## 同步的普通直播改动

- 限制聊天记录、待处理弹幕、图片缓存和活跃位图占用，测量文本位图并限制突发绘制。
- iOS 短时前向缓存；断流或持续缓冲后获取当前清晰度的新地址，有限重试并验证实际播放进度。
- 后台断流保留待恢复状态，手动暂停、换台、退出使相关恢复任务失效或保持暂停意图。
- Rust 去重窗口归一化异常参数，长时间挂起后一次清理整窗过期数据。
- Android 专用兼容解码参数不再应用于 iOS。

关注排序切换、观看/开播时长展示和普通版身份配置保留。默认画质配置与用户设置保持 dev 原有行为，自动恢复不会降低当前清晰度。

## 构建产物

`app-build-action-dev` 的 `ios` artifact 提供 `ios_no_sign.ipa`；`ios-native-mpv-symbols` 保存对应符号和校验记录。安装普通版应使用普通版原有签名标识，与 Slive iPad 专用版分开。
