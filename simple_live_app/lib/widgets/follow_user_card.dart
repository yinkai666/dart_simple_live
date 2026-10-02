import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// Observe live fields inside each card so a status refresh leaves siblings alone.
class FollowUserCard extends StatelessWidget {
  const FollowUserCard({required this.item, this.onRemove, this.onLongPress, super.key});

  final FollowUser item;
  final VoidCallback? onRemove;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Obx(() => LiveRoomCard(
          Sites.allSites[item.siteId]!,
          LiveRoomItem(
            roomId: item.roomId,
            title: item.title.value,
            cover: item.cover.value,
            userName: item.userName,
            online: item.online.value,
          ),
          onFollowRemove: onRemove,
          onLongPress: onLongPress,
        ));
  }
}
