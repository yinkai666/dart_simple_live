import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'dart:ui' as ui;

class FollowUserItem extends StatelessWidget {
  final FollowUser item;
  final Function()? onRemove;
  final Function()? onTap;
  final Function()? onLongPress;
  final bool playing;
  final bool showTag;
  const FollowUserItem({
    required this.item,
    this.onRemove,
    this.onTap,
    this.onLongPress,
    this.playing = false,
    this.showTag = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var site = Sites.allSites[item.siteId]!;
    return ListTile(
      contentPadding: AppStyle.edgeInsetsL16.copyWith(right: 4),
      leading: NetImage(
        item.face,
        width: 48,
        height: 48,
        borderRadius: 24,
      ),
      title: Text.rich(
        TextSpan(
          text: item.remark?.isNotEmpty == true ? item.remark : item.userName,
          children: [
            WidgetSpan(
              alignment: ui.PlaceholderAlignment.middle,
              child: Obx(
                () => Offstage(
                  offstage: item.liveStatus.value == 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppStyle.hGap12,
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: item.liveStatus.value == 2
                              ? Colors.green
                              : Colors.grey,
                          borderRadius: AppStyle.radius12,
                        ),
                      ),
                      AppStyle.hGap4,
                      Text(
                        getStatus(item.liveStatus.value),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.normal,
                          color:
                              item.liveStatus.value == 2 ? null : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      subtitle: Wrap(
        runSpacing: 1.0,
        children: [
          Image.asset(
            site.logo,
            width: 20,
          ),
          AppStyle.hGap4,
          Text(
            site.name,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          AppStyle.hGap4,
          Obx(() {
            final mode =
                AppSettingsController.instance.followInfoDisplayMode.value;
            final showWatch = mode != FollowInfoDisplayMode.liveDuration;
            final showLive = mode != FollowInfoDisplayMode.watchDuration;
            final liveText = showLive ? _liveDurationText() : "";

            final parts = <String>[];
            if (showWatch) {
              parts.add("看 ${item.watchDuration ?? "00:00:00"}");
            }
            if (liveText.isNotEmpty) {
              parts.add(liveText);
            }
            if (parts.isEmpty) {
              return const SizedBox.shrink();
            }
            return Text(
              parts.join(" · "),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            );
          }),
          AppStyle.hGap4,
          if (showTag)
            Text(
              item.tag.length > 8 ? '${item.tag.substring(0, 8)}...' : item.tag,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: playing
          ? const SizedBox(
              width: 64,
              child: Center(
                child: Icon(
                  Icons.play_arrow,
                ),
              ),
            )
          : (onRemove == null
              ? null
              : IconButton(
                  onPressed: () {
                    onRemove?.call();
                  },
                  icon: const Icon(Remix.dislike_line),
                )),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  String getStatus(int status) {
    if (status == 0) {
      return "读取中";
    } else if (status == 1) {
      return "未开播";
    } else {
      return "直播中";
    }
  }

  /// 仅在主播正在直播且拿到了开播时间戳时返回非空文案
  String _liveDurationText() {
    if (item.liveStatus.value != 2) return "";
    final ts = item.liveStartTime.value;
    if (ts == null || ts.isEmpty || ts == "0") return "";
    final start = int.tryParse(ts);
    if (start == null) return "";
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final secs = now - start;
    if (secs < 60) return "开播 不足1分钟";
    final hours = secs ~/ 3600;
    final minutes = (secs % 3600) ~/ 60;
    final h = hours > 0 ? "$hours小时" : "";
    final m = minutes > 0 ? "$minutes分钟" : "";
    return "开播 $h$m";
  }
}
