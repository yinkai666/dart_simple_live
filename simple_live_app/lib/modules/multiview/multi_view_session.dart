import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/player/room_task_scope.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// Owns one native player. Global orientation, audio focus and history are not
/// managed per tile: closing a tile must never stop another room.
class MultiViewSession {
  MultiViewSession({required this.site, required this.roomId, String? label})
      : label = label ?? roomId,
        id = '${site.id}:$roomId' {
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'Slive iPad',
        // Each tile owns its own demuxer; avoid multiplying the 32 MiB default.
        bufferSize: 8 * 1024 * 1024,
      ),
    );
    videoController = VideoController(
      player,
      configuration: const VideoControllerConfiguration(enableHardwareAcceleration: true),
    );
  }

  final String id;
  final Site site;
  final String roomId;
  String label;
  late final Player player;
  late final VideoController videoController;
  final tasks = RoomTaskScope();
  LiveRoomDetail? detail;
  List<LivePlayQuality> qualities = [];
  int qualityIndex = -1;
  bool loading = true;
  String? error;
  bool isAudible = false;
  bool suspended = false;
  bool ready = false;
  bool closed = false;
  final List<StreamSubscription<dynamic>> subscriptions = [];

  void invalidate() {
    closed = true;
    tasks.close();
  }

  /// Called by the workspace's native command queue after pending opens finish.
  Future<void> release() async {
    for (final subscription in subscriptions) {
      try {
        await subscription.cancel();
      } catch (_) {
        // Always continue to dispose the native decoder.
      }
    }
    subscriptions.clear();
    await player.dispose();
  }
}
