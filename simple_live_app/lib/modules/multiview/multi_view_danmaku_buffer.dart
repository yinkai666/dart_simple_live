import 'dart:collection';

/// Keep live messages fresh: a slow renderer must never accumulate a backlog.
class MultiViewDanmakuBuffer<T> {
  MultiViewDanmakuBuffer({this.capacity = 24, this.batchSize = 3});

  final int capacity;
  final int batchSize;
  final Queue<T> _items = Queue<T>();

  void add(T item) {
    if (_items.length >= capacity) _items.removeFirst();
    _items.addLast(item);
  }

  List<T> drain() {
    final result = <T>[];
    while (_items.isNotEmpty && result.length < batchSize) {
      result.add(_items.removeFirst());
    }
    // Older messages are less useful than the next live burst.
    _items.clear();
    return result;
  }

  void clear() => _items.clear();
}
