import 'dart:async';
import 'package:flutter/material.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'multi_view_gesture_policy.dart';

/// One owner per workspace: closing an individual tile must not reset brightness.
class MultiViewBrightnessController {
  static final _platform = BrightnessCoordinator(
    apply: (value) => ScreenBrightnessPlatform.instance.setApplicationScreenBrightness(value),
    reset: () => ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness(),
  );
  late final _writer = GestureValueWriter((value) => _platform.set(this, value));
  Future<void>? _closing;
  bool _changed = false;

  Future<double> read() => ScreenBrightnessPlatform.instance.application;

  Future<void> setBrightness(double value) {
    if (_closing != null) return Future.value();
    _changed = true;
    return _writer.write(value.clamp(.05, 1.0));
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    await _writer.close();
    if (!_changed) return;
    try {
      await _platform.restore(this);
    } catch (_) {
      // Unsupported platforms must still allow page teardown.
    }
  }
}

class MultiViewGestureSurface extends StatefulWidget {
  const MultiViewGestureSurface({
    super.key,
    required this.child,
    required this.brightness,
    required this.volume,
    required this.isAudible,
    required this.onVolumeChanged,
    required this.onDoubleTap,
    this.enabled = true,
  });
  final Widget child;
  final MultiViewBrightnessController brightness;
  final double volume;
  final bool isAudible;
  final Future<void> Function(double) onVolumeChanged;
  final VoidCallback onDoubleTap;
  final bool enabled;

  @override
  State<MultiViewGestureSurface> createState() => _MultiViewGestureSurfaceState();
}

class _MultiViewGestureSurfaceState extends State<MultiViewGestureSurface> {
  late final _volumeWriter = GestureValueWriter((value) => widget.onVolumeChanged(value));
  Timer? _hide;
  int _epoch = 0;
  bool _active = false;
  bool _ready = false;
  bool _left = false;
  double _start = 0;
  double _delta = 0;
  double _height = 1;
  String? _tip;

  void _show(String text) {
    if (mounted) setState(() => _tip = text);
  }

  void _startDrag(DragStartDetails details) async {
    final box = context.findRenderObject() as RenderBox;
    _left = details.localPosition.dx < box.size.width / 2;
    _height = box.size.height;
    _hide?.cancel();
    _active = true;
    _ready = false;
    _delta = 0;
    final epoch = ++_epoch;
    try {
      final value = _left ? await widget.brightness.read() : widget.volume / 100;
      if (!mounted || !_active || epoch != _epoch) return;
      _start = value;
      _ready = true;
      _apply();
    } catch (_) {
      if (mounted && epoch == _epoch) _show('暂时无法调节亮度');
    }
  }

  void _updateDrag(DragUpdateDetails details) {
    if (!_active) return;
    _delta += details.delta.dy;
    if (_ready) _apply();
  }

  void _apply() {
    final level = gestureLevel(_start, _delta, _height, minimum: _left ? .05 : 0);
    final epoch = _epoch;
    _show(
        _left ? '屏幕亮度 ${(level * 100).round()}%' : '本路音量 ${(level * 100).round()}%${widget.isAudible ? '' : ' · 静音'}');
    final action = _left ? widget.brightness.setBrightness(level) : _volumeWriter.write(level * 100);
    unawaited(action.catchError((Object _) {
      if (mounted && epoch == _epoch) _show('调节失败，请重试');
    }));
  }

  void _endDrag() {
    _active = false;
    _ready = false;
    ++_epoch;
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _tip = null);
    });
  }

  @override
  void dispose() {
    ++_epoch;
    _hide?.cancel();
    unawaited(_volumeWriter.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onDoubleTap,
        onVerticalDragStart: widget.enabled ? _startDrag : null,
        onVerticalDragUpdate: widget.enabled ? _updateDrag : null,
        onVerticalDragEnd: widget.enabled ? (_) => _endDrag() : null,
        onVerticalDragCancel: widget.enabled ? _endDrag : null,
        child: Stack(fit: StackFit.expand, children: [
          widget.child,
          if (_tip != null)
            IgnorePointer(
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_tip!, style: const TextStyle(color: Colors.white))),
                ),
              ),
            ),
        ]),
      );
}
