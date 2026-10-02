import '../lib/services/follow_refresh_policy.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final policy = FollowRefreshPolicy();
  final now = DateTime(2026);
  const interval = Duration(minutes: 1);
  check(policy.canRefresh('a', now), 'New users should refresh');
  policy.failed('a', now, interval);
  check(!policy.canRefresh('a', now.add(interval)), 'First failure backs off');
  check(policy.canRefresh('b', now), 'Failures must be isolated per user');
  check(policy.canRefresh('a', now.add(interval * 2)), 'Retry at deadline');
  for (var i = 0; i < 20; i++) {
    policy.failed('a', now, interval);
  }
  check(policy.canRefresh('a', now.add(interval * 8)), 'Backoff is capped');
  policy.succeeded('a');
  check(policy.canRefresh('a', now), 'Success resets backoff');
  policy.failed('a', now, interval);
  policy.retainUsers({'b'});
  check(policy.canRefresh('a', now), 'Removed users leave no retry state');
  print('Follow refresh policy checks passed');
}
