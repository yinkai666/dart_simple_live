import 'dart:async';
import '../lib/services/follow_refresh_policy.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final coordinator = FollowRefreshCoordinator();
  final first = Completer<void>();
  var calls = 0;
  final automatic = coordinator.run(
      automatic: true,
      refresh: () {
        calls++;
        return first.future;
      });
  final duplicate = coordinator.run(
      automatic: true,
      refresh: () async {
        calls++;
      });
  check(identical(automatic, duplicate), 'Automatic callers share one round');
  final manual = coordinator.run(
      automatic: false,
      refresh: () async {
        calls++;
      });
  check(calls == 1, 'Manual round waits for automatic work');
  first.complete();
  await Future.wait([automatic, duplicate, manual]);
  check(calls == 2, 'Manual request receives its full refresh');

  final pending = Completer<void>();
  final generation = coordinator.generation;
  final old = coordinator.run(automatic: false, refresh: () => pending.future);
  coordinator.pause();
  check(!coordinator.isCurrent(generation), 'Background invalidates old responses');
  await coordinator.run(
      automatic: true,
      refresh: () async {
        calls++;
      });
  check(calls == 2, 'Background schedules no new work');
  coordinator.resume();
  check(!coordinator.isCurrent(generation), 'Resume never revalidates an old response');
  check(coordinator.isCurrent(coordinator.generation), 'New foreground generation is usable');
  final resumedManual = coordinator.run(
      automatic: false,
      refresh: () async {
        calls++;
      });
  pending.complete();
  await old;
  await resumedManual;
  check(calls == 3, 'Manual refresh after resume must not reuse invalidated work');
  await coordinator.run(
      automatic: true,
      refresh: () async {
        calls++;
      });
  check(calls == 4, 'Foreground work resumes once old work completes');
  coordinator.close();
  await coordinator.run(
      automatic: false,
      refresh: () async {
        calls++;
      });
  check(calls == 4, 'Closed service schedules no work');
  print('Follow refresh coordinator checks passed');
}
