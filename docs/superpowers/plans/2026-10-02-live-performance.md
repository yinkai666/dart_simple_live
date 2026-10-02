# 直播与关注列表性能优化

目标：减少重复关注请求、快速切台的过期回写和无效列表重建，关闭页面时清理相关资源。

设计：保持现有 UI、排序设置与后台/PiP 播放行为。关注刷新使用单轮 Future、生命周期失效检查与失败退避；直播请求使用代次标识、播放器操作顺序保护。列表结构与普通元数据变化才发布列表更新，实时字段由条目局部监听。

- [x] 关注刷新：单轮合并等待，前后台切换使旧轮次失效；自动请求失败退避，手动刷新绕过退避；请求超时退出等待。
- [x] 切台与释放：房间与播放双代次保护；原生播放器命令串行；停止旧弹幕并清理订阅、计时器与滚动控制器。
- [x] 列表局部更新：先显示缓存，刷新不清空列表；结构/元数据快照去重；卡片实时字段局部监听。
- [x] 验证：纯 Dart 回归、辅助逻辑静态分析与独立交叉审查；完整 Flutter 验证受下述环境限制。

本机 Flutter 3.41.9 低于项目要求 3.47.5。纯 Dart 检查不替代 Flutter 编译或实机性能测试。不在本任务中升级全局 SDK。

## 验证记录

使用 `C:/dev/flutter/bin/cache/dart-sdk/bin/dart.exe` 执行以下检查，均通过：

- `simple_live_app/test/follow_refresh_policy_check.dart`：重试退避、成功重置、用户隔离。
- `simple_live_app/test/follow_refresh_coordinator_check.dart`：轮次合并、手动全量补刷、前后台切换及关闭；恢复后新手刷不复用旧代次。
- `simple_live_app/test/list_projection_check.dart`：无变化不重建、实时字段局部更新、同对象元数据变化和对象替换。
- `simple_live_app/test/room_task_scope_regression.dart`：乱序请求、关闭后回调、播放器命令顺序、失败恢复和截图排队。
- `simple_live_core/test/web_socket_lifecycle_check.dart`：本地延迟握手关闭与 onReady 内关闭；运行时需传 `--packages=simple_live_app/.dart_tool/package_config.json`。

`list_projection.dart`、`follow_refresh_policy.dart`、`room_task_scope.dart` 的 `dart analyze` 通过。`flutter pub get --offline` 因 SDK 版本不满足要求失败，现有依赖缓存也缺少上游 material_ui；未宣称完整编译、Flutter 集成测试或实机性能验证通过。

HTTP 边界：现有 core 请求接口没有取消令牌，已发出的 HTTP 仍可能完成；代次检查阻止其结果回写和后续请求，未开始的关注排队任务直接跳过。
