import 'dart:async';
import '../../lib/modules/multiview/multi_view_gesture_policy.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  check(gestureLevel(.5, -100, 200) == 1, 'Upward drag increases level with upper bound');
  check(gestureLevel(.5, 100, 200) == 0, 'Downward drag decreases volume');
  check(gestureLevel(.5, 100, 200, minimum: .05) == .05, 'Brightness keeps visible minimum');
  check(gestureLevel(.5, 0, 0) == .5, 'Transient zero size is safe');
  final gate = Completer<void>();
  final writes = <double>[];
  final writer = GestureValueWriter((value) async {
    writes.add(value);
    if (writes.length == 1) await gate.future;
  });
  final first = writer.write(.1);
  writer.write(.2);
  writer.write(.8);
  gate.complete();
  await first;
  check(writes.length == 2 && writes.last == .8, 'Intermediate drag values are coalesced');
  final lastGate = Completer<void>();
  final closingWrites = <double>[];
  final closing = GestureValueWriter((value) async {
    closingWrites.add(value);
    await lastGate.future;
  });
  closing.write(.3);
  closing.write(.7);
  final closed = closing.close();
  lastGate.complete();
  await closed;
  await closing.write(.9);
  check(closingWrites.length == 1, 'Closing drops pending updates before brightness restoration');
  final ownerA = Object();
  final ownerB = Object();
  final nativeGate = Completer<void>();
  final started = Completer<void>();
  final nativeValues = <double>[];
  var resets = 0;
  final shared = BrightnessCoordinator(apply: (value) async {
    nativeValues.add(value);
    if (value == .2) {
      started.complete();
      await nativeGate.future;
    }
  }, reset: () async {
    resets++;
  });
  final a = shared.set(ownerA, .2);
  await started.future;
  final b = shared.set(ownerB, .8);
  final restoreA = shared.restore(ownerA);
  nativeGate.complete();
  await Future.wait([a, b, restoreA]);
  check(nativeValues.last == .8 && resets == 0, 'Old page cleanup cannot overwrite a newer page');
  await shared.restore(ownerB);
  check(resets == 1, 'Current brightness owner restores exactly once');
  print('PASS: gesture direction, bounds, coalescing and close');
}
