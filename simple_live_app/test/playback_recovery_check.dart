// ignore_for_file: avoid_relative_lib_imports, avoid_print
import '../lib/modules/live_room/player/playback_recovery.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final deferred = PlaybackRecovery();
  check(!deferred.request(background: true), 'Background failure records intent without starting requests');
  check(deferred.pending, 'Background failure must survive until foreground');
  deferred.cancel();
  check(deferred.pending, 'Suspending in-flight work must preserve pending recovery');
  check(deferred.request(background: false), 'Foreground can resume deferred recovery');
  deferred.reset();
  check(!deferred.pending, 'Manual reset/close clears deferred recovery');
  final waitingIntent = RecoveryPlayIntent(initiallyPlaying: true);
  waitingIntent.observe(playing: false, completed: false);
  deferred.request(background: true);
  deferred.cancel();
  deferred.request(background: false);
  check(!waitingIntent.beginOpen(), 'The same intent must survive retry delay and background suspension');
  final pausedDuringFetch = RecoveryPlayIntent(initiallyPlaying: true);
  pausedDuringFetch.observe(playing: false, completed: false);
  check(!pausedDuringFetch.beginOpen(), 'A pause while fetching URLs must open paused');
  final stoppedByError = RecoveryPlayIntent(initiallyPlaying: false);
  check(stoppedByError.beginOpen(), 'An initially stopped failed stream must be restarted');
  final completed = RecoveryPlayIntent(initiallyPlaying: true);
  completed.observe(playing: false, completed: true);
  check(completed.beginOpen(), 'EOF is not a user pause');
  final resumed = RecoveryPlayIntent(initiallyPlaying: true);
  resumed.observe(playing: false, completed: false);
  resumed.observe(playing: true, completed: false);
  check(resumed.beginOpen(), 'Resume during fetch restores play intent');
  resumed.observe(playing: false, completed: false);
  check(resumed.beginOpen(), 'Native open stop events cannot change captured intent');
  check(recoveryLineIndex(2, 4, 1) == 2, 'First recovery preserves the selected line');
  check(recoveryLineIndex(2, 4, 2) == 3, 'Later recovery rotates to the next fresh line');
  check(recoveryLineIndex(3, 4, 3) == 0, 'Line rotation wraps');
  check(recoveryLineIndex(-1, 3, 1) == 0, 'Unset line falls back to the first');
  check(recoveryLineIndex(8, 3, 1) == 2, 'A shorter fresh list clamps the selected line');
  check(recoveryLineIndex(0, 1, 3) == 0, 'Single-line streams remain valid');
  check(recoveryLineIndex(0, 0, 1) == -1, 'An empty result has no valid line');
  final policy = PlaybackRecovery();
  final now = DateTime(2026);
  check(!policy.observeBuffering(now, eligible: true), 'Buffering starts a timer');
  check(!policy.observeBuffering(now.add(const Duration(seconds: 14)), eligible: true), '14s is too early');
  check(policy.observeBuffering(now.add(const Duration(seconds: 15)), eligible: true), '15s triggers recovery');
  check(!policy.observeBuffering(now.add(const Duration(seconds: 16)), eligible: true), 'A trigger restarts timing');
  check(!policy.observeBuffering(now.add(const Duration(seconds: 25)), eligible: false),
      'Pause/background resets timing');
  check(!policy.observeBuffering(now.add(const Duration(seconds: 30)), eligible: true), 'Resume starts fresh');
  check(!policy.observeBuffering(now.add(const Duration(seconds: 44)), eligible: true),
      'Old background time is excluded');
  check(policy.observeBuffering(now.add(const Duration(seconds: 45)), eligible: true), 'Resume allows a full 15s');
  final first = policy.begin(now)!;
  check(policy.begin(now) == null, 'Simultaneous error/completed must coalesce');
  policy.finish(first, now);
  check(policy.begin(now) == null, 'A retry must respect the minimum interval');
  final second = policy.begin(now.add(const Duration(seconds: 5)))!;
  policy.finish(second, now.add(const Duration(seconds: 5)));
  final third = policy.begin(now.add(const Duration(seconds: 10)))!;
  policy.finish(third, now.add(const Duration(seconds: 10)));
  check(policy.exhausted, 'Opening a URL must not reset the attempt budget');
  check(policy.begin(now.add(const Duration(minutes: 1))) == null, 'Budget must be finite');

  policy.observeProgress(const Duration(seconds: 1), now, eligible: true);
  policy.observeProgress(const Duration(seconds: 2), now.add(const Duration(seconds: 5)), eligible: true);
  check(policy.exhausted, 'One position update is not stable playback');
  policy.observeProgress(const Duration(seconds: 3), now.add(const Duration(seconds: 10)), eligible: true);
  check(policy.exhausted, 'Slow playback (2s over 10s) must not reset the budget');
  policy.observeProgress(Duration.zero, now, eligible: false);
  policy.observeProgress(Duration.zero, now, eligible: true);
  policy.observeProgress(const Duration(seconds: 5), now.add(const Duration(seconds: 5)), eligible: true);
  policy.observeProgress(const Duration(seconds: 10), now.add(const Duration(seconds: 10)), eligible: true);
  check(!policy.exhausted && policy.attempts == 0, 'Sustained real-time progress resets the budget');
  final pending = policy.begin(now.add(const Duration(seconds: 11)))!;
  policy.reset();
  check(!policy.isCurrent(pending), 'Manual intervention invalidates pending recovery');
  policy.finish(pending, now);
  check(policy.attempts == 0, 'Stale completion must not affect a new session');
  policy.begin(now);
  policy.observeProgress(const Duration(seconds: 5), now, eligible: true);
  policy.observeProgress(const Duration(seconds: 6), now.add(const Duration(seconds: 5)), eligible: false);
  policy.observeProgress(const Duration(seconds: 7), now.add(const Duration(seconds: 10)), eligible: true);
  check(policy.attempts == 1, 'Paused/background playback must not qualify as recovery');
  print('PASS: bounded recovery, coalescing, spacing, progress, invalidation');
}
