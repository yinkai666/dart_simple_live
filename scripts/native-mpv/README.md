# iPad mpv 原生断言修复

用户崩溃报告显示 `Mpv` UUID `6c684115-0731-3252-97d8-a5fcaad35862`，`mp_play_files.cold.4 + 40` 调用 `__assert_rtn`。

已校验旧 0.6.6 发布归档 SHA-256，并确认其 ARM64 切片 UUID 完全匹配。该位置反汇编恢复的断言参数为：

- 函数：`play_current_file`
- 文件与行号：`loadfile.c:1918`
- 表达式：`mpctx->stop_play`

0.6.6 与当前 0.6.8 构建均基于 mpv 0.36.0，未包含 [上游修复 d59f4fd](https://github.com/mpv-player/mpv/commit/d59f4fd3ec141693da4f7f6677aa729e1bb92f4d)。补丁回移该修复，保留断言；修复 EOF 后视频输出重建所排队的 seek 过早清除终止状态的问题。新版本报告是否命中同一断言仍需对应新日志，但当前依赖源代码也包含相同缺陷。

## 构建方式

`build_patched_mpv.py` 在 macOS 上复用锁定的 0.6.8 iOS 依赖 frameworks，下载并校验匹配的 mpv/FFmpeg/libass/uchardet 源码头文件，仅重新编译 ARM64 iOS 的 libmpv。交叉编译限定 iPhoneOS SDK、iOS 15.0，隔离宿主机 pkg-config 库，保留调试信息并生成 dSYM。

准备旧 Pod 后替换其 `Mpv.framework`，并在本次隔离 CI 任务中停止 Podspec 再次调用 make 下载旧框架。`verify_patched_mpv.py` 在 IPA 打包前检查最终嵌入库、dSYM 和构建 manifest 的 UUID 一致，并校验当前补丁哈希；校验失败不能生成可交付 IPA。

`Slive-iPad-native-mpv-symbols` artifact 包含 dSYM、构建来源、链接依赖、补丁、配置与校验结果。原生崩溃定位应使用与安装包 UUID 对应的 dSYM。

## 验证范围

本地 Windows 已验证源归档校验值、补丁在 pristine v0.36.0 上可应用及校验 helper 单元测试。实际 iOS 交叉编译和 IPA 嵌入校验由 Actions 执行；修复效果需要安装新包后验证。没有禁用断言，也没有把内存风险修复当成本次断言根因。
