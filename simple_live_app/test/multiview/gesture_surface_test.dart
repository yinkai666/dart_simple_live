import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/modules/multiview/multi_view_gesture_surface.dart';

class FakeBrightness extends MultiViewBrightnessController {
  final values = <double>[];
  @override
  Future<double> read() async => .5;
  @override
  Future<void> setBrightness(double value) async => values.add(value);
}

void main() {
  testWidgets('right side changes only this room volume', (tester) async {
    final brightness = FakeBrightness();
    final values = <double>[];
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox(
      width: 400,
      height: 300,
      child: MultiViewGestureSurface(
        brightness: brightness,
        volume: 50,
        isAudible: true,
        onVolumeChanged: (value) async => values.add(value),
        onDoubleTap: () {},
        child: const ColoredBox(color: Colors.black),
      ),
    ))));
    final box = tester.getRect(find.byType(MultiViewGestureSurface));
    await tester.dragFrom(box.topLeft + const Offset(300, 200), const Offset(0, -100));
    await tester.pump();
    expect(values, isNotEmpty);
    expect(values.last, greaterThan(50));
    expect(brightness.values, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('left side changes screen brightness and keeps volume', (tester) async {
    final brightness = FakeBrightness();
    final values = <double>[];
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox(
      width: 400,
      height: 300,
      child: MultiViewGestureSurface(
        brightness: brightness,
        volume: 50,
        isAudible: false,
        onVolumeChanged: (value) async => values.add(value),
        onDoubleTap: () {},
        child: const ColoredBox(color: Colors.black),
      ),
    ))));
    final box = tester.getRect(find.byType(MultiViewGestureSurface));
    final gesture = await tester.startGesture(box.topLeft + const Offset(100, 100));
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    await gesture.up();
    expect(brightness.values, isNotEmpty);
    expect(brightness.values.last, lessThan(.5));
    expect(values, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('unfocused tiles leave vertical drags for scrolling', (tester) async {
    final values = <double>[];
    var scrollUpdates = 0;
    await tester.pumpWidget(MaterialApp(
        home: GestureDetector(
      onVerticalDragUpdate: (_) => scrollUpdates++,
      child: MultiViewGestureSurface(
        enabled: false,
        brightness: FakeBrightness(),
        volume: 50,
        isAudible: true,
        onVolumeChanged: (value) async => values.add(value),
        onDoubleTap: () {},
        child: const ColoredBox(color: Colors.black),
      ),
    )));
    await tester.drag(find.byType(MultiViewGestureSurface), const Offset(0, -150));
    expect(scrollUpdates, greaterThan(0));
    expect(values, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
