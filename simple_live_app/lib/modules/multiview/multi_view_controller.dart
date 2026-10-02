import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/player/room_task_scope.dart';

import 'multi_view_roster.dart';
import 'multi_view_playback.dart';
import 'multi_view_session.dart';

export 'multi_view_session.dart';

class MultiViewController extends ChangeNotifier with WidgetsBindingObserver {
  MultiViewController() {
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _background = state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
  }

  static const maxSessions = MultiViewRoster.maxSessions;
  static const _requestTimeout = Duration(seconds: 25);
  final _roster = MultiViewRoster();
  final Map<String, MultiViewSession> _sessions = {};
  // Retiring players remain here until queued native disposal completes.
  final Set<MultiViewSession> _nativeSessions = {};
  // A shared native queue guarantees mute-before-unmute across different players.
  final _commands = PlayerCommandQueue();
  bool _closed = false;
  bool _background = false;
  Future<void>? _closing;

  List<MultiViewSession> get sessions => List.unmodifiable(_roster.ids.map((id) => _sessions[id]!));
  String? get audioSessionId => _roster.audioId;

  void _changed() {
    if (!_closed) notifyListeners();
  }

  Future<String?> addRoom(Site site, String roomId, {String? label}) async {
    if (_closed) return '同屏观看已关闭';
    roomId = roomId.trim();
    if (roomId.isEmpty) return '请输入直播间 ID';
    final id = '${site.id}:$roomId';
    final problem = _roster.add(id);
    if (problem != null) return problem;
    late final MultiViewSession session;
    try {
      session = MultiViewSession(site: site, roomId: roomId, label: label);
    } catch (_) {
      _roster.remove(id);
      return '无法创建播放器';
    }
    _sessions[id] = session;
    _nativeSessions.add(session);
    session.subscriptions.add(session.player.stream.error.listen((message) {
      if (session.closed || _closed || message.isEmpty) return;
      session.error = '播放中断，请重试或切换清晰度';
      session.loading = false;
      _changed();
    }));
    _updateFlags();
    _changed();
    // Return after insertion so picking several rooms does not await the network.
    unawaited(_load(session));
    return null;
  }

  Future<void> _load(MultiViewSession session, {int? quality}) async {
    if (_closed || session.closed) return;
    final generation = session.tasks.invalidate();
    bool current() => !_closed && session.tasks.isCurrent(generation);
    session.loading = true;
    session.ready = false;
    session.error = null;
    _changed();
    try {
      await _commands.run(() async {
        if (!current()) return;
        await session.player.setVolume(0);
        await session.player.stop();
      });
      if (!current()) return;
      if (quality == null || session.detail == null) {
        final detail = await session.site.liveSite.getRoomDetail(roomId: session.roomId).timeout(_requestTimeout);
        if (!current()) return;
        if (!detail.status) throw StateError('主播暂未开播');
        final qualities = await session.site.liveSite.getPlayQualites(detail: detail).timeout(_requestTimeout);
        if (!current()) return;
        if (qualities.isEmpty) throw StateError('没有可用清晰度');
        // Publish the matching detail/qualities pair atomically.
        session.detail = detail;
        session.label = detail.userName;
        session.qualities = qualities;
        // Medium quality limits decoder and network pressure with up to 4 feeds.
        session.qualityIndex = (qualities.length / 2).floor();
      } else {
        session.qualityIndex = quality;
      }
      final source = await session.site.liveSite
          .getPlayUrls(
            detail: session.detail!,
            quality: session.qualities[session.qualityIndex],
          )
          .timeout(_requestTimeout);
      if (!current()) return;
      if (source.urls.isEmpty) throw StateError('没有可用播放线路');
      await _commands.run(() async {
        if (!current()) return;
        await session.player.setVolume(0);
        if (!current()) return;
        await openCurrentStream(
          isCurrent: current,
          open: () => session.player.open(Media(source.urls.first, httpHeaders: source.headers), play: false),
          stop: session.player.stop,
          onReady: () async {
            session.ready = true;
            await _applyPlayback();
          },
        );
      });
      if (!current()) return;
      session.loading = false;
      _changed();
    } catch (e) {
      if (!current()) return;
      session.loading = false;
      session.error = e is StateError ? e.message.toString() : '加载失败，请重试或选择其他清晰度';
      _changed();
    }
  }

  void _updateFlags() {
    for (final session in _sessions.values) {
      session.isAudible = session.id == audioSessionId;
      session.suspended = _roster.shouldSuspend(session.id, background: _background);
    }
  }

  /// Only call inside _commands. Complete every mute before enabling any audio.
  Future<void> _applyPlayback() async {
    if (_closed) return;
    final snapshot = List<MultiViewSession>.of(_nativeSessions);
    await muteBeforeSelect<MultiViewSession>(
      snapshot,
      mute: (session) => session.player.setVolume(0),
      apply: () async {
        for (final session in snapshot) {
          if (_closed || session.closed || !session.ready) continue;
          if (session.suspended) {
            await session.player.pause();
          } else {
            await session.player.play();
          }
        }
        final audible = _sessions[audioSessionId];
        if (!_closed && audible != null && !audible.closed && audible.ready) {
          await audible.player.setVolume(100);
        }
      },
    );
  }

  Future<void> _syncPlayback() async {
    try {
      await _commands.run(_applyPlayback);
    } catch (_) {
      if (_closed) return;
      final session = _sessions[audioSessionId];
      if (session != null) session.error = '播放器状态更新失败，请重试';
      _changed();
    }
  }

  Future<void> selectAudio(String id) async {
    if (_closed) return;
    _roster.selectAudio(id);
    _updateFlags();
    _changed();
    await _syncPlayback();
  }

  Future<void> remove(String id) async {
    final session = _sessions.remove(id);
    if (session == null) return;
    session.invalidate();
    _roster.remove(id);
    _updateFlags();
    _changed();
    try {
      await _commands.run(() async {
        try {
          await session.release();
        } finally {
          _nativeSessions.remove(session);
        }
      });
    } catch (_) {
      // Removal remains final even if the native backend reports a close error.
    } finally {
      await _syncPlayback();
    }
  }

  Future<void> retry(String id) async {
    final session = _sessions[id];
    if (session != null) await _load(session);
  }

  Future<void> changeQuality(String id, int index) async {
    final session = _sessions[id];
    if (session == null || session.loading || index < 0 || index >= session.qualities.length) return;
    await _load(session, quality: index);
  }

  Future<void> swap(int a, int b) async {
    if (_closed) return;
    _roster.swap(a, b);
    _changed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closed) return;
    if (state == AppLifecycleState.resumed) {
      _background = false;
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _background = true;
    } else {
      return; // Permission prompts / Control Center do not rebuild the streams.
    }
    _updateFlags();
    _changed();
    unawaited(_syncPlayback());
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    final snapshot = sessions;
    for (final session in snapshot) {
      session.invalidate();
    }
    _sessions.clear();
    for (final id in _roster.ids) {
      _roster.remove(id);
    }
    return _closing = _commands.run(() async {
      for (final session in snapshot) {
        try {
          await session.release();
        } catch (_) {
          // One native teardown failure must not leak the remaining players.
        } finally {
          _nativeSessions.remove(session);
        }
      }
    });
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
