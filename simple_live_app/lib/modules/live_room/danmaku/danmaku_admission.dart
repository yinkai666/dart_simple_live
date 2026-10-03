import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:canvas_danmaku/utils/utils.dart';

/// Limit synchronous text rasterization work; chat history is kept separately.
class DanmakuAdmission {
  final _clock = Stopwatch()..start();
  int _window = 0;
  int _count = 0;

  bool allow({int? elapsedMilliseconds}) {
    final now = elapsedMilliseconds ?? _clock.elapsedMilliseconds;
    if (now - _window >= 1000 || now < _window) {
      _window = now;
      _count = 0;
    }
    if (_count >= 24) return false;
    _count++;
    return true;
  }
}

/// Measure with the same paragraph builder as canvas_danmaku, before toImage.
int? estimateDanmakuBytes(DanmakuContentItem content, DanmakuOption option, double dpr) {
  if (content.text.length > 512 ||
      content.text.isEmpty ||
      !dpr.isFinite ||
      dpr <= 0 ||
      dpr > 4 ||
      !option.fontSize.isFinite ||
      option.fontSize <= 0 ||
      option.fontSize > 96 ||
      option.fontWeight < 0 ||
      option.fontWeight > 8 ||
      !option.strokeWidth.isFinite ||
      option.strokeWidth < 0 ||
      option.strokeWidth > 16) {
    return null;
  }
  final paragraph = DmUtils.generateParagraph(
    content: content,
    fontSize: option.fontSize,
    fontWeight: option.fontWeight,
    fontFamily: option.fontFamily,
  );
  try {
    final width = ((paragraph.maxIntrinsicWidth + option.strokeWidth + (content.selfSend ? 4 : 0)) * dpr).ceil();
    final height = ((paragraph.height + option.strokeWidth) * dpr).ceil();
    final bytes = width * height * 4;
    return width > 0 && height > 0 && width <= 4096 && height <= 4096 && bytes <= 2 * 1024 * 1024 ? bytes : null;
  } finally {
    paragraph.dispose();
  }
}
