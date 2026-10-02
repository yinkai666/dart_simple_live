import 'dart:async';
import '../../lib/modules/multiview/multi_view_playback.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final firstMute = Completer<void>();
  final volumes = {'a': 0, 'b': 100};
  var owner = 'b';
  final transaction = muteBeforeSelect<String>(
    ['a', 'b'],
    mute: (id) async {
      if (id == 'a') await firstMute.future;
      volumes[id] = 0;
    },
    apply: () async {
      check(volumes.values.every((value) => value == 0), 'removed audio must be muted before successor');
      volumes[owner] = 100;
    },
  );
  owner = 'a'; // remove old owner during another player's native mute await
  firstMute.complete();
  await transaction;
  check(volumes['a'] == 100 && volumes['b'] == 0, 'only new owner audible');

  final opened = Completer<void>();
  var current = true;
  var ready = false;
  var stopped = false;
  final loading = openCurrentStream(
    isCurrent: () => current,
    open: () => opened.future,
    stop: () async => stopped = true,
    onReady: () async => ready = true,
  );
  current = false; // a retry supersedes an in-flight native open
  opened.complete();
  await loading;
  check(stopped && !ready, 'stale native open must stop and never become playable');
  print('PASS: removed audio muted before handover; stale native open stopped');
}
