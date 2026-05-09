import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

class Constant {
  static const String kUpdateFollow = "UpdateFollow";
  static const String kUpdateHistory = "UpdateHistory";

  static final Map<String, HomePageItem> allHomePages = {
    "recommend": HomePageItem(
      iconData: Remix.home_smile_line,
      title: "首页",
      index: 0,
    ),
    "follow": HomePageItem(
      iconData: Remix.heart_line,
      title: "关注",
      index: 1,
    ),
    "category": HomePageItem(
      iconData: Remix.apps_line,
      title: "分类",
      index: 2,
    ),
    "user": HomePageItem(
      iconData: Remix.user_smile_line,
      title: "我的",
      index: 3,
    ),
  };

  static const String kBiliBili = "bilibili";
  static const String kDouyu = "douyu";
  static const String kHuya = "huya";
  static const String kDouyin = "douyin";
  static const String kTwitch = "twitch";
}

class HomePageItem {
  final IconData iconData;
  final String title;
  final int index;
  HomePageItem({
    required this.iconData,
    required this.title,
    required this.index,
  });
}

enum DownloadState {
  notDownloaded,
  downloading,
  downloaded,
}

// 排序方法
enum SortMethod {
  watchDuration,
  siteId,
  recently,
  userNameASC,
  userNameDESC,
}

extension SortMethodStore on SortMethod {
  String get storeValue => name;
  static SortMethod fromStore(String? v) {
    if (v == null) return SortMethod.watchDuration;
    return SortMethod.values.firstWhere(
      (e) => e.name == v,
      orElse: () => SortMethod.watchDuration,
    );
  }
}

// 直播间关注列表排序方法
enum LiveRoomFollowSortMethod {
  watchDuration,
  recentEnter,
}

extension LiveRoomFollowSortMethodStore on LiveRoomFollowSortMethod {
  String get storeValue => name;

  static LiveRoomFollowSortMethod fromStore(String? v) {
    if (v == null) return LiveRoomFollowSortMethod.watchDuration;
    return LiveRoomFollowSortMethod.values.firstWhere(
      (e) => e.name == v,
      orElse: () => LiveRoomFollowSortMethod.watchDuration,
    );
  }
}

// 关注列表上时长信息的显示模式
enum FollowInfoDisplayMode {
  watchDuration, // 只显示用户累计观看时长
  liveDuration, // 只显示主播本次开播时长
  both, // 同时显示两者
}

extension FollowInfoDisplayModeStore on FollowInfoDisplayMode {
  String get storeValue => name;

  static FollowInfoDisplayMode fromStore(String? v) {
    if (v == null) return FollowInfoDisplayMode.watchDuration;
    return FollowInfoDisplayMode.values.firstWhere(
      (e) => e.name == v,
      orElse: () => FollowInfoDisplayMode.watchDuration,
    );
  }
}
