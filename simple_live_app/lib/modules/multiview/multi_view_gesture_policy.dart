double gestureLevel(double start, double deltaY, double height, {double minimum = 0}) {
  if (!height.isFinite || height <= 0 || !deltaY.isFinite) return start;
  return (start - deltaY / (height * 0.65)).clamp(minimum, 1.0);
}

/// Serializes platform writes across pages. An old page cannot restore over a
/// newer page's brightness, including when a platform call is still in flight.
class BrightnessCoordinator {
  BrightnessCoordinator({required this.apply, required this.reset});
  final Future<void> Function(double) apply;
  final Future<void> Function() reset;
  Object? _owner;
  Future<void> _tail = Future.value();

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> set(Object owner, double value) {
    _owner = owner;
    return _enqueue(() async {
      if (identical(_owner, owner)) await apply(value);
    });
  }

  Future<void> restore(Object owner) => _enqueue(() async {
        if (!identical(_owner, owner)) return;
        await reset();
        if (identical(_owner, owner)) _owner = null;
      });
}

/// Coalesces rapid gesture updates, keeping only the newest waiting value.
class GestureValueWriter {
  GestureValueWriter(this.apply);
  final Future<void> Function(double) apply;
  double? _pending;
  Future<void>? _draining;
  bool _closed = false;

  Future<void> write(double value) {
    if (_closed) return Future.value();
    _pending = value;
    return _draining ??= _drain().whenComplete(() => _draining = null);
  }

  Future<void> _drain() async {
    while (!_closed && _pending != null) {
      final value = _pending!;
      _pending = null;
      await apply(value);
    }
  }

  Future<void> close() async {
    _closed = true;
    _pending = null;
    try {
      await _draining;
    } catch (_) {
      // Cleanup must still run after a platform channel error.
    }
  }
}
