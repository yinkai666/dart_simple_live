import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/services/follow_service.dart';

import 'multi_view_controller.dart';
import 'multiview_layout.dart';

/// A video-first workspace. Layout depends on window size, not device identity.
class MultiViewPage extends StatefulWidget {
  const MultiViewPage({
    super.key,
    this.initialSite,
    this.initialRoomId,
    this.initialLabel,
  });

  final Site? initialSite;
  final String? initialRoomId;
  final String? initialLabel;

  @override
  State<MultiViewPage> createState() => _MultiViewPageState();
}

class _MultiViewPageState extends State<MultiViewPage> {
  final _controller = MultiViewController();
  final _scaffold = GlobalKey<ScaffoldState>();
  String? _focusedId;
  bool _sidebarVisible = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialSite != null && widget.initialRoomId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_addRoom(widget.initialSite!, widget.initialRoomId!, label: widget.initialLabel));
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addRoom(Site site, String roomId, {String? label}) async {
    final error = await _controller.addRoom(site, roomId, label: label);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _manualRoom() async {
    final sites = Sites.supportSites;
    if (sites.isEmpty) return;
    var site = sites.first;
    var roomId = '';
    String? error;
    final result = await showDialog<(Site, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('添加直播间'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Site>(
                    initialValue: site,
                    decoration: const InputDecoration(labelText: '平台'),
                    items: [
                      for (final item in sites) DropdownMenuItem(value: item, child: Text(item.name)),
                    ],
                    onChanged: (value) {
                      if (value != null) update(() => site = value);
                    },
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    autofocus: true,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: '房间 ID',
                      helperText: '填写平台房间号或频道名，不是完整链接',
                      errorText: error,
                    ),
                    onChanged: (value) => roomId = value.trim(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (roomId.isEmpty || roomId.contains('://')) {
                  update(() => error = '请输入房间 ID 或频道名');
                  return;
                }
                Navigator.pop(context, (site, roomId));
              },
              child: const Text('开始观看'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) await _addRoom(result.$1, result.$2);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff7ac9c0), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xff101315),
    );
    return Theme(
      data: theme,
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = MultiViewLayout.showSidebar(constraints.maxWidth);
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final hasFocus = _controller.sessions.any((room) => room.id == _focusedId);
            return Scaffold(
              key: _scaffold,
              appBar: AppBar(
                title: const Text('多直播'),
                backgroundColor: const Color(0xff101315),
                actions: [
                  if (hasFocus)
                    IconButton(
                      tooltip: '恢复多屏布局',
                      onPressed: () => setState(() => _focusedId = null),
                      icon: const Icon(Icons.grid_view),
                    ),
                  if (_controller.sessions.length > 1)
                    IconButton(
                      tooltip: '交换前两个直播间',
                      onPressed: () => _controller.swap(0, 1),
                      icon: const Icon(Icons.swap_horiz),
                    ),
                  IconButton(
                    tooltip: wide ? '显示或隐藏关注侧栏' : '从关注添加直播间',
                    onPressed: () {
                      if (wide) {
                        setState(() => _sidebarVisible = !_sidebarVisible);
                      } else {
                        _scaffold.currentState?.openEndDrawer();
                      }
                    },
                    icon: const Icon(Icons.people_outline),
                  ),
                  IconButton(
                    tooltip: '输入房间 ID 添加',
                    onPressed: _controller.sessions.length < MultiViewController.maxSessions ? _manualRoom : null,
                    icon: const Icon(Icons.add),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              endDrawer: wide ? null : Drawer(child: SafeArea(child: _followPanel(drawer: true))),
              body: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(child: _workspace(hasFocus)),
                    if (wide && _sidebarVisible) ...[
                      const VerticalDivider(width: 1),
                      SizedBox(width: 292, child: _followPanel()),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
  }

  Widget _workspace(bool hasFocus) {
    if (_controller.sessions.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.view_quilt_outlined, size: 64, color: Color(0xff7ac9c0)),
              const SizedBox(height: 20),
              const Text('把想看的直播放在一起', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              const Text('最多同时观看 4 路直播，单独选择一路声音。\n从关注添加，或输入直播间 ID。',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, height: 1.6)),
              const SizedBox(height: 24),
              FilledButton.icon(onPressed: _manualRoom, icon: const Icon(Icons.add), label: const Text('添加直播间')),
            ],
          ),
        ),
      );
    }
    final rooms =
        hasFocus ? _controller.sessions.where((room) => room.id == _focusedId).toList() : _controller.sessions;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              hasFocus ? '已放大单路 · 其余直播仍在播放' : '${rooms.length} / 4 路直播 · 点声音按钮切换音源',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: LayoutBuilder(builder: (context, constraints) {
              final columns = MultiViewLayout.columns(rooms.length, constraints.maxWidth, constraints.maxHeight);
              final height = MultiViewLayout.tileHeight(rooms.length, columns, constraints.maxHeight);
              return GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: height,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: rooms.length,
                itemBuilder: (context, index) => _tile(rooms[index], hasFocus),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _tile(MultiViewSession room, bool focused) {
    final name = room.detail?.userName ?? room.label;
    return Container(
      key: ValueKey(room.id),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: room.isAudible ? const Color(0xff7ac9c0) : Colors.white12, width: 1.5),
      ),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Video(
                  controller: room.videoController,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                  pauseUponEnteringBackgroundMode: false,
                  resumeUponEnteringForegroundMode: false,
                ),
                if (room.loading)
                  const ColoredBox(color: Colors.black54, child: Center(child: CircularProgressIndicator())),
                if (room.error != null)
                  ColoredBox(
                    color: Colors.black87,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(room.error!,
                                textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
                            TextButton.icon(
                                onPressed: () => _controller.retry(room.id),
                                icon: const Icon(Icons.refresh),
                                label: const Text('重新连接')),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (room.suspended) const ColoredBox(color: Colors.black54, child: Center(child: Text('后台暂停'))),
              ],
            ),
          ),
          ColoredBox(
            color: const Color(0xff1b2023),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: room.isAudible ? '正在播放声音' : '切换到此直播间的声音',
                  onPressed: () => _controller.selectAudio(room.id),
                  color: room.isAudible ? const Color(0xff7ac9c0) : Colors.white54,
                  icon: Icon(room.isAudible ? Icons.volume_up : Icons.volume_off),
                ),
                IconButton(
                  tooltip: focused ? '恢复多屏布局' : '放大此直播间',
                  onPressed: () => setState(() => _focusedId = focused ? null : room.id),
                  icon: Icon(focused ? Icons.fullscreen_exit : Icons.fullscreen),
                ),
                PopupMenuButton<String>(
                  tooltip: '清晰度与直播间操作',
                  onSelected: (value) {
                    if (value == 'close') {
                      unawaited(_controller.remove(room.id));
                    } else if (value == 'retry') {
                      unawaited(_controller.retry(room.id));
                    } else {
                      unawaited(_controller.changeQuality(room.id, int.parse(value)));
                    }
                  },
                  itemBuilder: (context) => [
                    for (var i = 0; i < room.qualities.length; i++)
                      CheckedPopupMenuItem(
                        value: '$i',
                        checked: room.qualityIndex == i,
                        child: Text(room.qualities[i].quality),
                      ),
                    const PopupMenuItem(value: 'retry', child: Text('重新连接')),
                    const PopupMenuItem(value: 'close', child: Text('关闭此直播间')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _followPanel({bool drawer = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
          child: Row(children: [
            const Expanded(child: Text('我的关注', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
            if (drawer)
              IconButton(onPressed: () => Navigator.pop(context), tooltip: '关闭侧栏', icon: const Icon(Icons.close)),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('点选加入多屏，最多 4 路', style: TextStyle(color: Colors.white60, fontSize: 12)),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Get.isRegistered<FollowService>()
              ? Obx(() {
                  final users = FollowService.instance.followList.where((user) => !user.deleted).toList();
                  if (users.isEmpty) return const Center(child: Text('还没有关注，试试输入房间 ID'));
                  return ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, index) => _followRow(users[index], drawer),
                  );
                })
              : const Center(child: Text('输入房间 ID 开始观看')),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: _controller.sessions.length < MultiViewController.maxSessions ? _manualRoom : null,
            icon: const Icon(Icons.add),
            label: const Text('输入房间 ID'),
          ),
        ),
      ],
    );
  }

  Widget _followRow(FollowUser user, bool drawer) {
    final site = Sites.allSites[user.siteId];
    final selected = _controller.sessions.any((room) => room.site.id == user.siteId && room.roomId == user.roomId);
    return Obx(() => ListTile(
          selected: selected,
          enabled: site != null && !selected && _controller.sessions.length < MultiViewController.maxSessions,
          leading: CircleAvatar(
            backgroundColor: const Color(0xff273235),
            child: Icon(selected ? Icons.check : Icons.live_tv,
                color: user.liveStatus.value == 2 ? const Color(0xff7ac9c0) : Colors.white38),
          ),
          title: Text(user.userName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${site?.name ?? user.siteId} · ${selected ? "已加入" : user.liveStatus.value == 2 ? "直播中" : user.liveStatus.value == 1 ? "未开播" : "状态未知"}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          onTap: () {
            if (drawer) Navigator.pop(context);
            unawaited(_addRoom(site!, user.roomId, label: user.userName));
          },
        ));
  }
}
