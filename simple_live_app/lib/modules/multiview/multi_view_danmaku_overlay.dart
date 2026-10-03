import 'dart:async';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/live_room/danmaku/danmaku_admission.dart';
import 'package:simple_live_app/modules/live_room/danmaku/danmaku_emoticon.dart';

import 'multi_view_danmaku.dart';

class MultiViewDanmakuOverlay extends StatefulWidget {
  const MultiViewDanmakuOverlay({super.key, required this.danmaku});
  final MultiViewDanmaku danmaku;

  @override
  State<MultiViewDanmakuOverlay> createState() => _MultiViewDanmakuOverlayState();
}

class _MultiViewDanmakuOverlayState extends State<MultiViewDanmakuOverlay> {
  DanmakuController? _controller;
  final _admission = DanmakuAdmission();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _subscriptions.add(widget.danmaku.batches.listen((messages) {
      if (!mounted || !widget.danmaku.enabled.value) return;
      if (_controller?.running == false) _controller?.resume();
      final controller = _controller;
      if (controller == null) return;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      for (final message in messages) {
        if (!_admission.allow()) break;
        final item = DanmakuContentItem(message.message,
            color: Color.fromARGB(255, message.color.r, message.color.g, message.color.b));
        final bytes = estimateDanmakuBytes(item, controller.option, dpr);
        if (bytes == null) continue;
        if (!fitsLiveDanmakuBitmapBudget([...controller.scrollDanmaku, ...controller.staticDanmaku], addedBytes: bytes)) {
          break;
        }
        controller.addDanmaku(item);
      }
    }));
    _subscriptions.add(widget.danmaku.clears.listen((_) {
      _controller?.clear();
      _controller?.pause();
    }));
  }

  @override
  void didUpdateWidget(covariant MultiViewDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.danmaku != widget.danmaku) {
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
      _subscriptions.clear();
      _controller?.clear();
      _subscribe();
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return IgnorePointer(
      child: ClipRect(
        child: RepaintBoundary(
          child: DanmakuScreen(
            createdController: (controller) {
              _controller = controller;
              controller.pause();
            },
            option: DanmakuOption(
              fontSize: settings.danmuSize.value.clamp(14.0, 26.0),
              area: settings.danmuArea.value.clamp(0.1, 0.7),
              duration: settings.danmuSpeed.value,
              opacity: settings.danmuOpacity.value,
              strokeWidth: settings.danmuStrokeWidth.value,
              fontWeight: settings.danmuFontWeight.value,
              massiveMode: false,
            ),
          ),
        ),
      ),
    );
  }
}
