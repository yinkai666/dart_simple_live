import '../lib/modules/live_room/bounded_chat_buffer.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final visible = <int>[];
  final buffer = BoundedChatBuffer<int>(capacity: 150);
  buffer.append(visible, List.generate(1000, (i) => i), readingHistory: false);
  check(visible.length == 150 && visible.first == 850, 'Live messages must stay bounded');
  final frozen = visible.toList();
  for (var i = 1000; i < 50000; i++) {
    buffer.append(visible, [i], readingHistory: true);
  }
  check(visible.length == 150 && visible.first == frozen.first, 'Reading history preserves visible rows');
  check(buffer.pendingCount == 150, 'Paused view must not retain unlimited incoming messages');
  buffer.resume(visible);
  check(visible.length == 150 && visible.last == 49999, 'Returning to live displays latest bounded messages');
  check(buffer.pendingCount == 0, 'Resume releases pending references');
  buffer.append(visible, [50001], readingHistory: true);
  buffer.clear();
  check(buffer.pendingCount == 0, 'Room switch discards pending messages');
  final pendingRust = <int>[];
  appendRecent(pendingRust, List.generate(10000, (i) => i), 300);
  check(pendingRust.length == 300 && pendingRust.last == 9999, 'Rust work queue bounded during slow processing');
  print('PASS: bounded live/frozen chat, resume, room reset and pending batch');
}
