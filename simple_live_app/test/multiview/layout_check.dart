import '../../lib/modules/multiview/multiview_layout.dart';

void main() {
  void check(bool value, String label) {
    if (!value) throw StateError(label);
  }

  check(MultiViewLayout.columns(2, 1000, 650) == 2, 'landscape pair');
  check(MultiViewLayout.columns(2, 650, 1000) == 1, 'portrait pair');
  check(MultiViewLayout.columns(4, 800, 900) == 2, 'portrait quad');
  check(MultiViewLayout.columns(4, 320, 700) == 1, 'narrow multitasking');
  check(MultiViewLayout.showSidebar(1180), 'wide sidebar');
  check(!MultiViewLayout.showSidebar(820), 'portrait drawer');
  check(MultiViewLayout.columns(1, 1300, 700) == 1, 'single room');
  check(MultiViewLayout.tileHeight(4, 1, 600) >= 210, 'narrow scrollable tiles');
  check(MultiViewLayout.tileHeight(4, 2, 600) == 296, 'quad fits');
  print('MultiView layout checks passed');
}
