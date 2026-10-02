import 'dart:async';

/// Serializes refresh rounds and invalidates results across lifecycle changes.
class FollowRefreshCoordinator {
  bool closed = false;
  bool background = false;
  int generation = 0;
  Future<void>? active;
  bool _automatic = false;
  int _activeGeneration = -1;

  bool isCurrent(int token) => !closed && !background && token == generation;

  void pause() {
    background = true;
    generation++;
  }

  void resume() => background = false;

  void close() {
    closed = true;
    generation++;
  }

  Future<void> run({required bool automatic, required Future<void> Function() refresh}) {
    if (closed || background) return Future.value();
    final pending = active;
    if (pending != null) {
      // Manual refresh must cover rooms omitted by automatic scheduling.
      if (_activeGeneration != generation || (!automatic && _automatic)) {
        return pending.then((_) => run(automatic: automatic, refresh: refresh));
      }
      return pending;
    }
    _automatic = automatic;
    _activeGeneration = generation;
    return active = Future.sync(refresh).whenComplete(() {
      active = null;
    });
  }
}

/// Per-room retry state for automatic refreshes. Manual refreshes bypass it.
class FollowRefreshPolicy {
  final Map<String, int> _failures = {};
  final Map<String, DateTime> _retryAt = {};

  bool canRefresh(String id, DateTime now) => !_retryAt.containsKey(id) || !now.isBefore(_retryAt[id]!);

  void failed(String id, DateTime now, Duration interval) {
    final failures = ((_failures[id] ?? 0) + 1).clamp(1, 3);
    _failures[id] = failures;
    _retryAt[id] = now.add(interval * (1 << failures));
  }

  void succeeded(String id) {
    _failures.remove(id);
    _retryAt.remove(id);
  }

  void retainUsers(Set<String> ids) {
    _failures.removeWhere((id, _) => !ids.contains(id));
    _retryAt.removeWhere((id, _) => !ids.contains(id));
  }
}
