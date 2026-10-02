import '../../lib/modules/multiview/multi_view_danmaku_buffer.dart';

void main() {
  final buffer = MultiViewDanmakuBuffer<int>(capacity: 6, batchSize: 2);
  for (var i = 0; i < 1000; i++) {
    buffer.add(i);
  }
  check(buffer.drain().join(',') == '994,995', 'bounded buffer retains recent messages');
  check(buffer.drain().isEmpty, 'burst backlog is discarded');
  buffer.add(1);
  buffer.clear();
  check(buffer.drain().isEmpty, 'background clear drops stale messages');
  buffer.add(2);
  check(buffer.drain().single == 2, 'new connection can deliver fresh messages');
  print('multiview danmaku buffer checks passed');
}

void check(bool passed, String message) {
  if (!passed) throw StateError(message);
}
