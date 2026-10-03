void appendRecent<T>(List<T> target, Iterable<T> values, int capacity) {
  target.addAll(values);
  if (target.length > capacity) target.removeRange(0, target.length - capacity);
}

class BoundedChatBuffer<T> {
  BoundedChatBuffer({required this.capacity});
  final int capacity;
  final List<T> _pending = [];
  int get pendingCount => _pending.length;

  void append(List<T> visible, Iterable<T> values, {required bool readingHistory}) {
    if (readingHistory) {
      appendRecent(_pending, values, capacity);
    } else {
      resume(visible);
      appendRecent(visible, values, capacity);
    }
  }

  void resume(List<T> visible) {
    if (_pending.isEmpty) return;
    appendRecent(visible, _pending, capacity);
    _pending.clear();
  }

  void clear() => _pending.clear();
}
