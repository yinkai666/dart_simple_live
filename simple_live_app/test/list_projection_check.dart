import '../lib/app/utils/list_projection.dart';

class Entry {
  Entry(this.id, this.label);
  final int id;
  String label;
  int liveStatus = 0;
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final projection = ListProjection<Entry>();
  final a = Entry(1, 'a');
  final b = Entry(2, 'b');
  Object label(Entry e) => (e.id, e.label);
  check(projection.update([a, b], label), 'Initial rows must be published');
  check(!projection.update([a, b], label), 'Unchanged refresh must not publish');
  a.liveStatus = 2;
  check(!projection.update([a, b], label), 'Row-local state must not rebuild the list');
  a.label = 'renamed';
  check(projection.update([a, b], label), 'In-place metadata edits must publish');
  check(projection.update([b, a], label), 'Reordering must publish');
  check(projection.update([b, Entry(1, 'renamed')], label), 'Replacement models must rebind observers');
  check(projection.update([], label), 'Removing all rows must publish');
  check(!projection.update([], label), 'Repeated empty refresh must not publish');
  print('PASS: list projection (8 cases)');
}
