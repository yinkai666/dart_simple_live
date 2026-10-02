import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/follow_block_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

import 'multi_view_danmaku_buffer.dart';

/// Independent connection per tile. Messages never notify the workspace.
class MultiViewDanmaku {
  MultiViewDanmaku({required this.site, required this.roomId})
      : enabled = ValueNotifier(AppSettingsController.instance.danmuEnable.value);

  final Site site;
  final String roomId;
  final ValueNotifier<bool> enabled;
  final _batches = StreamController<List<LiveMessage>>.broadcast();
  final _clears = StreamController<void>.broadcast();
  final _buffer = MultiViewDanmakuBuffer<LiveMessage>();
  Stream<List<LiveMessage>> get batches => _batches.stream;
  Stream<void> get clears => _clears.stream;
  LiveRoomDetail? _detail;
  LiveDanmaku? _connection;
  Timer? _timer;
  bool _active = false;
  bool _disposed = false;
  int _epoch = 0;

  void connect(LiveRoomDetail detail) {
    if (_disposed || identical(detail, _detail)) return;
    _disconnect();
    _detail = detail;
    _sync();
  }

  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    _sync();
  }

  void setEnabled(bool value) {
    if (_disposed || enabled.value == value) return;
    enabled.value = value;
    _sync();
  }

  void _sync() {
    if (!_active || !enabled.value || _detail == null) {
      _disconnect();
      return;
    }
    if (_connection != null) return;
    final connection = site.liveSite.getDanmaku();
    _connection = connection;
    final epoch = ++_epoch;
    connection.onMessage = (message) {
      if (!_disposed &&
          epoch == _epoch &&
          message.type == LiveMessageType.chat &&
          message.message.trim().isNotEmpty &&
          message.message.length <= 300) {
        _buffer.add(message);
      }
    };
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_disposed || epoch != _epoch) return;
      final pending = _buffer.drain();
      if (pending.isEmpty || !_batches.hasListener) return;
      final block = FollowBlockService.instance.getBlock(siteId: site.id, roomId: roomId);
      final patterns = <Pattern>[];
      for (final word in [...AppSettingsController.instance.shieldList, ...block.blockWords]) {
        if (word.isEmpty) continue;
        try {
          patterns.add(Utils.isRegexFormat(word) ? RegExp(Utils.removeRegexFormat(word)) : word);
        } on FormatException {
          // A malformed saved rule must not break playback or message delivery.
        }
      }
      final messages = pending
          .where((message) =>
              !patterns.any(message.message.contains) &&
              !block.blockAccounts.any((account) => account.name == message.userName))
          .toList();
      if (messages.isNotEmpty && _batches.hasListener) _batches.add(messages);
    });
    unawaited(_start(connection, epoch, _detail!.danmakuData));
  }

  Future<void> _start(LiveDanmaku connection, int epoch, dynamic args) async {
    try {
      await connection.start(args);
    } catch (_) {
      if (epoch == _epoch && !_disposed) _disconnect();
    } finally {
      // Signature preparation can finish after stop. Close that late socket too.
      if (_disposed || epoch != _epoch) await _stop(connection);
    }
  }

  Future<void> _stop(LiveDanmaku connection) async {
    try {
      await connection.stop();
    } catch (_) {
      // One failed connection must not prevent native player disposal.
    }
  }

  void _disconnect() {
    ++_epoch;
    _timer?.cancel();
    _timer = null;
    _buffer.clear();
    if (!_clears.isClosed) _clears.add(null);
    final old = _connection;
    _connection = null;
    if (old != null) {
      old.onMessage = null;
      old.onClose = null;
      old.onReady = null;
      unawaited(_stop(old));
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _disconnect();
    enabled.dispose();
    // Do not await broadcast close: a paused widget subscription can delay it.
    unawaited(_batches.close());
    unawaited(_clears.close());
  }
}
