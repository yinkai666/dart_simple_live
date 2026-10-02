/// Invalidates work when the user switches rooms, refreshes or closes the page.
/// Core platform APIs do not expose cancellation, so callers must check after
/// every await before publishing results or starting another request.
class RoomTaskScope {
  int _generation = 0;
  bool _closed = false;

  int get current => _generation;
  int invalidate() => ++_generation;
  bool isCurrent(int generation) => !_closed && generation == _generation;

  void close() {
    _closed = true;
    invalidate();
  }
}

/// Orders native stop/open/dispose calls even if an earlier command fails.
class PlayerCommandQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> run(Future<void> Function() command) {
    final result = _tail.then((_) => command());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
