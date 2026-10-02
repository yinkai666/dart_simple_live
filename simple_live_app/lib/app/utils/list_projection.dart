/// Keeps immutable metadata snapshots for lists whose row state updates itself.
class ListProjection<T> {
  List<T> _items = [];
  List<Object> _metadata = [];

  bool update(Iterable<T> values, Object Function(T) metadata) {
    final items = values.toList(growable: false);
    final fingerprints = items.map(metadata).toList(growable: false);
    var changed = items.length != _items.length;
    if (!changed) {
      for (var i = 0; i < items.length; i++) {
        if (!identical(items[i], _items[i]) || fingerprints[i] != _metadata[i]) {
          changed = true;
          break;
        }
      }
    }
    _items = items;
    _metadata = fingerprints;
    return changed;
  }
}
