import 'package:flutter_test/flutter_test.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import '../lib/modules/live_room/danmaku/danmaku_admission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bounds rasterization bursts and recovers next window', () {
    final budget = DanmakuAdmission();
    for (var i = 0; i < 24; i++) {
      expect(budget.allow(elapsedMilliseconds: 0), isTrue);
    }
    expect(budget.allow(elapsedMilliseconds: 999), isFalse);
    expect(budget.allow(elapsedMilliseconds: 1000), isTrue);
  });
  test('normal messages are admitted with measured size', () {
    final bytes = estimateDanmakuBytes(DanmakuContentItem('hello'), DanmakuOption(), 2);
    expect(bytes, isNotNull);
    expect(bytes!, greaterThan(0));
    expect(bytes, lessThan(2 * 1024 * 1024));
  });
  test('rejects oversized text and malformed rendering settings before rasterization', () {
    expect(estimateDanmakuBytes(DanmakuContentItem('a' * 513), DanmakuOption(), 2), isNull);
    expect(estimateDanmakuBytes(DanmakuContentItem('a'), DanmakuOption(fontSize: double.nan), 2), isNull);
    expect(estimateDanmakuBytes(DanmakuContentItem('a'), DanmakuOption(fontWeight: 90), 2), isNull);
    expect(estimateDanmakuBytes(DanmakuContentItem('a'), DanmakuOption(), double.infinity), isNull);
    expect(estimateDanmakuBytes(DanmakuContentItem('W' * 400), DanmakuOption(fontSize: 80), 3), isNull);
  });
}
