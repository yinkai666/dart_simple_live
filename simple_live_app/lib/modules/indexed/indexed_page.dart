import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/routes/app_navigation.dart';

import 'indexed_controller.dart';

class IndexedPage extends GetView<IndexedController> {
  const IndexedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760 && constraints.maxHeight >= 480;
        return Scaffold(
          body: Row(
            children: [
              Visibility(
                visible: wide,
                child: Obx(
                  () => NavigationRail(
                    scrollable: true,
                    selectedIndex: controller.index.value,
                    onDestinationSelected: controller.setIndex,
                    labelType: NavigationRailLabelType.all,
                    leading: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Slive\niPad', textAlign: TextAlign.center),
                    ),
                    trailing: Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: IconButton(
                        tooltip: '多直播观看',
                        onPressed: AppNavigator.toMultiView,
                        icon: const Icon(Icons.grid_view_rounded),
                      ),
                    ),
                    destinations: controller.items
                        .map(
                          (item) => NavigationRailDestination(
                            icon: Icon(item.iconData),
                            label: Text(item.title),
                            padding: AppStyle.edgeInsetsV8,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              Expanded(
                child: Obx(
                  () => Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: wide
                            ? BorderSide(
                                color: Colors.grey.withAlpha(50),
                                width: 1,
                              )
                            : BorderSide.none,
                      ),
                    ),
                    child: IndexedStack(
                      index: controller.index.value,
                      children: controller.pages,
                    ),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: wide
              ? null
              : FloatingActionButton.extended(
                  onPressed: AppNavigator.toMultiView,
                  icon: const Icon(Icons.grid_view_rounded),
                  label: const Text('多直播'),
                ),
          bottomNavigationBar: Visibility(
            visible: !wide,
            child: Obx(
              () => NavigationBar(
                selectedIndex: controller.index.value,
                onDestinationSelected: controller.setIndex,
                height: 64,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: controller.items
                    .map(
                      (item) => NavigationDestination(
                        icon: Icon(item.iconData),
                        label: item.title,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}
