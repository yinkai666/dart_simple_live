import 'dart:math' as math;

/// Window-based layout: narrow Stage Manager windows remain scrollable.
abstract final class MultiViewLayout {
  static bool showSidebar(double width) => width >= 1100;

  static int columns(int count, double width, double height) {
    if (count <= 1 || width < 600) return 1;
    if (count == 2 && height > width) return 1;
    return 2;
  }

  static double tileHeight(int count, int columns, double height) {
    final rows = (count / columns).ceil().clamp(1, 4);
    return math.max(210, (height - (rows - 1) * 8) / rows);
  }
}
