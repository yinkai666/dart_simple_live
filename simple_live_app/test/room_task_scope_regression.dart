// Standalone regression runner; no Flutter/package resolution required.
// ignore_for_file: avoid_relative_lib_imports, avoid_print

import 'dart:async';

import '../lib/modules/live_room/player/room_task_scope.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final scope = RoomTaskScope();
  final first = Completer<String>();
  final second = Completer<String>();
  final published = <String>[];
  Future<void> load(Future<String> request) async {
    final generation = scope.invalidate();
    final result = await request;
    if (scope.isCurrent(generation)) published.add(result);
  }

  final firstLoad = load(first.future);
  final secondLoad = load(second.future);
  second.complete('B');
  await secondLoad;
  first.complete('A');
  await firstLoad;
  check(published.join() == 'B', 'Old room response overwrote the new room');

  final pending = Completer<String>();
  final closedLoad = load(pending.future);
  scope.close();
  pending.complete('closed');
  await closedLoad;
  check(published.length == 1, 'Closed page accepted a pending response');
  check(!scope.isCurrent(scope.invalidate()), 'Closed scope reopened');

  final commands = PlayerCommandQueue();
  final room = RoomTaskScope();
  final nativeOpen = Completer<void>();
  final events = <String>[];
  final opening = commands.run(() async {
    events.add('open');
    await nativeOpen.future;
    events.add('opened');
  });
  final stale = room.current;
  final staleJump = commands.run(() async {
    if (room.isCurrent(stale)) events.add('stale jump');
  });
  room.invalidate();
  final stopping = commands.run(() async => events.add('stop'));
  await Future<void>.delayed(Duration.zero);
  check(events.join(',') == 'open', 'Native stop raced with open');
  nativeOpen.complete();
  await Future.wait([opening, staleJump, stopping]);
  check(events.join(',') == 'open,opened,stop', 'Stale queued command ran');

  final failure = commands.run(() async => throw StateError('native failure'));
  try {
    await failure;
  } on StateError {
    // A failed command must not prevent subsequent disposal.
  }
  await commands.run(() async => events.add('dispose'));
  check(events.last == 'dispose', 'Failed native command blocked disposal');
  // A current play request must not escape the room generation it belongs to.
  final refreshRoom = RoomTaskScope();
  final refreshPlay = RoomTaskScope();
  final oldRoomGeneration = refreshRoom.current;
  final oldPlayGeneration = refreshPlay.current;
  refreshRoom.invalidate();
  refreshPlay.invalidate();
  check(!refreshPlay.isCurrent(oldPlayGeneration), 'Refresh retained old playlist work');
  final newPlayGeneration = refreshPlay.invalidate();
  check(!(refreshRoom.isCurrent(oldRoomGeneration) && refreshPlay.isCurrent(newPlayGeneration)),
      'Fresh playback token admitted data from a stale room generation');

  // Screenshot waits behind native work; closing while queued must skip it.
  final screenshotQueue = PlayerCommandQueue();
  final nativePending = Completer<void>();
  final nativeBusy = screenshotQueue.run(() => nativePending.future);
  var closing = false;
  var screenshots = 0;
  final screenshot = screenshotQueue.run(() async {
    if (!closing) screenshots++;
  });
  closing = true;
  final disposal = screenshotQueue.run(() async => events.add('screenshot dispose'));
  nativePending.complete();
  await Future.wait([nativeBusy, screenshot, disposal]);
  check(screenshots == 0, 'Queued screenshot touched a closing player');
  check(events.last == 'screenshot dispose', 'Screenshot queue blocked disposal');
  print(
      'PASS: stale responses, closed scope, serialized commands, failure recovery, refresh scopes, queued screenshots');
}
