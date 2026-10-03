import 'dart:async';
import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/app/utils/sandbox.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_block.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/live_room/danmaku/danmaku_emoticon.dart';
import 'package:simple_live_app/modules/live_room/bounded_chat_buffer.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/modules/live_room/player/room_task_scope.dart';
import 'package:simple_live_app/modules/live_room/player/playback_recovery.dart';
import 'package:simple_live_app/modules/settings/danmu_settings_page.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_block_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/history_service.dart';
import 'package:simple_live_app/src/rust/api/danmaku_mask.dart';
import 'package:simple_live_app/widgets/desktop_refresh_button.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class LiveRoomController extends PlayerController with WidgetsBindingObserver {
  final _roomTasks = RoomTaskScope();
  final _playTasks = RoomTaskScope();
  final _recovery = PlaybackRecovery();
  Timer? _recoveryTimer;
  Timer? _recoveryVerificationTimer;
  Timer? _playbackMonitor;
  StreamSubscription<bool>? _recoveryPlaySubscription;
  RecoveryPlayIntent? _pendingRecoveryPlayIntent;
  bool _recoveryOpenedPaused = false;
  bool _recovering = false;
  bool _recoveryFailed = false;
  bool _failureDuringRecovery = false;
  bool _roomClosed = false;
  bool _playlistReady = false;
  Timer? _autoExitGraceTimer;
  StreamSubscription<dynamic>? subscription;
  final Site pSite;
  final String pRoomId;
  late LiveDanmaku liveDanmaku;
  late DanmakuMask rustDanmakuMask;

  List<LiveMessage> danmakuBuffer = [];
  Timer? danmakuTimer;
  bool _isProcessingBuffer = false;
  Future<Object?>? _maskInFlight;
  final _chatBuffer = BoundedChatBuffer<LiveMessage>(capacity: 150);

  LiveRoomController({
    required this.pSite,
    required this.pRoomId,
  }) {
    rxSite = pSite.obs;
    rxRoomId = pRoomId.obs;
    liveDanmaku = site.liveSite.getDanmaku();
    // 抖音应该默认是竖屏的
    if (site.id == "douyin") {
      isVertical.value = true;
    }
  }

  late Rx<Site> rxSite;
  Site get site => rxSite.value;
  late Rx<String> rxRoomId;
  String get roomId => rxRoomId.value;

  Rx<LiveRoomDetail?> detail = Rx<LiveRoomDetail?>(null);
  var online = 0.obs;
  var followed = false.obs;
  var liveStatus = false.obs;
  RxList<LiveSuperChatMessage> superChats = RxList<LiveSuperChatMessage>();

  /// 滚动控制
  final ScrollController scrollController = ScrollController();

  /// 聊天信息
  RxList<LiveMessage> messages = RxList<LiveMessage>();

  /// 当前直播间屏蔽项
  Rx<FollowUserBlock?> followUserBlock = Rx<FollowUserBlock?>(null);

  /// 清晰度数据
  RxList<LivePlayQuality> qualities = RxList<LivePlayQuality>();

  /// 当前清晰度
  var currentQuality = -1;
  var currentQualityInfo = "".obs;

  /// 线路数据
  RxList<String> playUrls = RxList<String>();

  Map<String, String>? playHeaders;

  /// 当前线路
  var currentLineIndex = -1;
  var currentLineInfo = "".obs;

  /// 退出倒计时
  var countdown = 60.obs;

  Timer? autoExitTimer;

  /// 设置的自动关闭时间（分钟）
  var autoExitMinutes = 60.obs;

  ///是否延迟自动关闭
  var delayAutoExit = false.obs;

  /// 是否启用自动关闭
  var autoExitEnable = false.obs;

  /// 是否禁用自动滚动聊天栏
  /// - 当用户向上滚动聊天栏时，不再自动滚动
  var disableAutoScroll = false.obs;

  /// 是否处于后台
  var isBackground = false;

  /// 直播间加载失败
  var loadError = false.obs;
  Error? error;

  int _count = 0;

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    if (FollowService.instance.followList.isEmpty) {
      FollowService.instance.loadData();
    }
    initAutoExit();
    showDanmakuState.value = AppSettingsController.instance.danmuEnable.value;
    followed.value = FollowService.instance.getFollowExist("${site.id}_$roomId");
    // 解冻：更新 lastWatchTime 并从休眠列表移除
    FollowService.instance.resumeUser("${site.id}_$roomId");
    loadData();

    scrollController.addListener(scrollListener);
    subscription = EventBus.instance.listen(Constant.kUpdateDanmaku, (data) {
      if (danmakuController?.option.fontSize != data as double) {
        updateDanmuOption(danmakuController?.option.copyWith(fontSize: data));
      }
    });
    _initDanmakuMask();
    super.onInit();
    _playbackMonitor = Timer.periodic(const Duration(seconds: 1), (_) => _monitorPlayback());
  }

  void _initDanmakuMask() async {
    rustDanmakuMask = DanmakuMask(
      baseWindowMs: AppSettingsController.instance.danmuWindowMs.value * 1000,
      bucketCount: AppSettingsController.instance.danmuWindowMs.value,
      useNormalization: AppSettingsController.instance.danmuTextNormalization.value,
      useFrequencyControl: AppSettingsController.instance.danmuFrequencyControl.value,
      maxFrequency: AppSettingsController.instance.danmuMaxFrequency.value,
    );
    danmakuTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (timer) {
        _processDanmakuBuffer();
        // sc同步计时调用 先刷后删
        _count = (_count + 1) % 2;
        if (_count == 0) {
          superChats.refresh();
          removeSuperChats();
        }
      },
    );
  }

  // 缓存降低跨线程消息开销 估算弹幕延迟在800ms左右
  void _processDanmakuBuffer() async {
    if (_roomClosed || _isProcessingBuffer) return;
    final generation = _roomTasks.current;
    if (danmakuBuffer.isEmpty) return;

    _isProcessingBuffer = true;
    try {
      final batch = List<LiveMessage>.from(danmakuBuffer);
      danmakuBuffer.clear();

      final batchMessages = batch.map((e) => e.message).toList();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final pending = rustDanmakuMask.allowListBatch(texts: batchMessages, nowMs: BigInt.from(nowMs));
      _maskInFlight = pending;
      final allowedResults = await pending;

      if (!_roomTasks.isCurrent(generation)) return;
      final filteredBatch = <LiveMessage>[];
      for (int i = 0; i < batch.length; i++) {
        if (allowedResults[i] == 1) {
          filteredBatch.add(batch[i]);
        }
      }

      if (filteredBatch.isEmpty) return;

      _appendChat(filteredBatch);

      WidgetsBinding.instance.addPostFrameCallback(
        (_) => chatScrollToBottom(),
      );
      if (!liveStatus.value || isBackground) {
        return;
      }

      addDanmaku(filteredBatch
          .map((msg) => DanmakuContentItem(
                msg.message,
                color: Color.fromARGB(
                  255,
                  msg.color.r,
                  msg.color.g,
                  msg.color.b,
                ),
                // 表情包（目前仅 B 站下发）：交给渲染层把 [占位符] 换成图片
                extra: msg.emoticons,
              ))
          .toList());
    } catch (e) {
      if (_roomTasks.isCurrent(generation)) Log.logPrint(e);
    } finally {
      _maskInFlight = null;
      _isProcessingBuffer = false;
    }
  }

  void scrollListener() {
    if (scrollController.position.userScrollDirection == ScrollDirection.forward) {
      disableAutoScroll.value = true;
    }
  }

  void _appendChat(Iterable<LiveMessage> incoming) {
    _chatBuffer.append(messages, incoming, readingHistory: disableAutoScroll.value);
  }

  void resumeChat() {
    if (_roomClosed) return;
    disableAutoScroll.value = false;
    _chatBuffer.resume(messages);
    WidgetsBinding.instance.addPostFrameCallback((_) => chatScrollToBottom());
  }

  /// 初始化自动关闭倒计时
  void initAutoExit() {
    if (AppSettingsController.instance.autoExitEnable.value) {
      autoExitEnable.value = true;
      autoExitMinutes.value = AppSettingsController.instance.autoExitDuration.value;
      setAutoExit();
    } else {
      autoExitMinutes.value = AppSettingsController.instance.roomAutoExitDuration.value;
    }
  }

  void setAutoExit() {
    _autoExitGraceTimer?.cancel();
    if (!autoExitEnable.value) {
      autoExitTimer?.cancel();
      return;
    }
    autoExitTimer?.cancel();
    countdown.value = autoExitMinutes.value * 60;
    autoExitTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      countdown.value -= 1;
      if (countdown.value <= 0) {
        _autoExitGraceTimer = Timer(const Duration(seconds: 10), () async {
          await WakelockPlus.disable();
          exit(0);
        });
        autoExitTimer?.cancel();
        var delay = await Utils.showAlertDialog("定时关闭已到时,是否延迟关闭?",
            title: "延迟关闭", confirm: "延迟", cancel: "关闭", selectable: true);
        if (_roomClosed) return;
        _autoExitGraceTimer?.cancel();
        if (delay) {
          delayAutoExit.value = true;
          showAutoExitSheet();
          setAutoExit();
        } else {
          delayAutoExit.value = false;
          await WakelockPlus.disable();
          exit(0);
        }
      }
    });
  }
  // 弹窗逻辑

  void refreshRoom() {
    if (_roomClosed) return;
    superChats.clear();
    loadData();
  }

  /// 聊天栏始终滚动到底部
  void chatScrollToBottom() {
    if (!_roomClosed && scrollController.hasClients) {
      // 如果手动上拉过，就不自动滚动到底部
      if (disableAutoScroll.value) {
        return;
      }
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    }
  }

  /// 初始化弹幕接收事件
  void initDanmau() {
    final generation = _roomTasks.current;
    liveDanmaku.onMessage = (message) {
      if (_roomTasks.isCurrent(generation)) onWSMessage(message);
    };
    liveDanmaku.onClose = (message) {
      if (_roomTasks.isCurrent(generation)) onWSClose(message);
    };
    liveDanmaku.onReady = () {
      if (_roomTasks.isCurrent(generation)) onWSReady();
    };
  }

  /// 接收到WebSocket信息
  void onWSMessage(LiveMessage msg) async {
    if (_roomClosed || followUserBlock.value == null) return;
    if (msg.type == LiveMessageType.chat) {
      // Reject abnormal payloads before regex work, history retention and FFI.
      if (msg.message.length > 2048) return;
      // 关键词屏蔽检查
      for (var keyword in AppSettingsController.instance.shieldList) {
        Pattern? pattern;
        if (Utils.isRegexFormat(keyword)) {
          String removedSlash = Utils.removeRegexFormat(keyword);
          try {
            pattern = RegExp(removedSlash);
          } catch (e) {
            // should avoid this during add keyword
            Log.d("关键词：$keyword 正则格式错误");
          }
        } else {
          pattern = keyword;
        }
        if (pattern != null && msg.message.contains(pattern)) {
          Log.d("关键词：$keyword\n已屏蔽消息内容：${msg.message}");
          return;
        }
      }

      // 当前直播间关键词屏蔽检查
      for (var keyword in followUserBlock.value!.blockWords) {
        Pattern? pattern;
        if (Utils.isRegexFormat(keyword)) {
          String removedSlash = Utils.removeRegexFormat(keyword);
          try {
            pattern = RegExp(removedSlash);
          } catch (e) {
            Log.d("关键词：$keyword 正则格式错误");
          }
        } else {
          pattern = keyword;
        }
        if (pattern != null && msg.message.contains(pattern)) {
          Log.d("关键词：$keyword\n已屏蔽${site.id}_$roomId消息内容：${msg.message}");
          return;
        }
      }
      // 当前直播间发言用户屏蔽
      // todo: 更精细化的uid匹配
      var accountInBlock = followUserBlock.value!.blockAccounts.any((item) => item.name == msg.userName);
      if (accountInBlock) {
        return;
      }

      //  messages.length>n 预加载部分弹幕后启用去重功能
      if (AppSettingsController.instance.danmakuMaskEnable.value && messages.length > 50) {
        appendRecent(danmakuBuffer, [msg], 300);
      } else {
        _appendChat([msg]);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => chatScrollToBottom(),
        );
        if (!liveStatus.value || isBackground) {
          return;
        }

        addDanmaku([
          DanmakuContentItem(
            msg.message,
            color: Color.fromARGB(
              255,
              msg.color.r,
              msg.color.g,
              msg.color.b,
            ),
            // 表情包（目前仅 B 站下发）：交给渲染层把 [占位符] 换成图片
            extra: msg.emoticons,
          ),
        ]);
      }
    } else if (msg.type == LiveMessageType.online) {
      online.value = msg.data;
    } else if (msg.type == LiveMessageType.superChat) {
      // set newest sc at the top， limit 20 better I think
      // unique ensures from front
      LiveSuperChatMessage scData = msg.data;
      bool contain = superChats.any(
        (s) => s.startTime == scData.startTime && s.userName == scData.userName && s.message == scData.message,
      );
      if (!contain) {
        superChats.insert(0, msg.data);
        if (superChats.length > 20) {
          superChats.removeRange(20, superChats.length);
        }
      }
    }
  }

  /// 添加当前房间屏蔽词
  void addCurBlockWord(String word) {
    // 为剥离getx做准备
    if (!followUserBlock.value!.blockWords.contains(word) && word != "") {
      followUserBlock.value!.blockWords.add(word);
      FollowBlockService.instance.addBlockWord(siteId: site.id, roomId: roomId, word: word);
      followUserBlock.refresh();
    }
    SmartDialog.showToast("已屏蔽词:$word");
  }

  void delCurBlockWord(String word) {
    if (followUserBlock.value!.blockWords.contains(word)) {
      followUserBlock.value!.blockWords.remove(word);
      FollowBlockService.instance.removeBlockWord(siteId: site.id, roomId: roomId, word: word);
      followUserBlock.refresh();
    }
  }

  /// 添加当前房间屏蔽用户
  void addCurBlockAccount(String accName) {
    bool exists = followUserBlock.value!.blockAccounts.any((acc) => acc.name == accName);
    if (!exists && accName != "") {
      //todo: temp use uid == 0
      var accInMessage = messages.firstWhereOrNull((e) => e.userName == accName);
      var accId = accInMessage?.userId ?? "0";
      var acc = FollowUserBlockAccount(uid: accId, name: accName);
      followUserBlock.value!.blockAccounts.add(acc);
      FollowBlockService.instance.addBlockAccount(siteId: site.id, roomId: roomId, account: acc);
      followUserBlock.refresh();
    }
    SmartDialog.showToast("已屏蔽用户:$accName");
  }

  void delCurBlockAccount(String accName) {
    bool exists = followUserBlock.value!.blockAccounts.any((acc) => acc.name == accName);
    if (exists) {
      followUserBlock.value!.blockAccounts.removeWhere((e) => e.name == accName);
      FollowBlockService.instance.removeBlockAccount(siteId: site.id, roomId: roomId, name: accName);
      followUserBlock.refresh();
    }
  }

  /// 添加一条系统消息
  void addSysMsg(String msg) {
    _appendChat([
      LiveMessage(
        type: LiveMessageType.chat,
        userName: "LiveSysMessage",
        message: msg,
        color: LiveMessageColor.white,
      ),
    ]);
  }

  /// 接收到WebSocket关闭信息
  void onWSClose(String msg) {
    addSysMsg(msg);
  }

  /// WebSocket准备就绪
  void onWSReady() {
    addSysMsg("弹幕服务器连接正常");
  }

  /// 加载直播间信息
  void loadData() async {
    if (_roomClosed) return;
    _resetPlaybackRecovery();
    final generation = _roomTasks.invalidate();
    _playTasks.invalidate();
    _playlistReady = false;
    // A refresh must not expose the previous detail/quality selection to taps.
    detail.value = null;
    liveStatus.value = false;
    qualities.clear();
    playUrls.clear();
    currentQuality = -1;
    currentLineIndex = -1;
    currentQualityInfo.value = "";
    currentLineInfo.value = "";
    _stopDanmaku();
    liveDanmaku = site.liveSite.getDanmaku();
    danmakuBuffer.clear();
    final requestSite = site;
    final requestRoomId = roomId;
    try {
      SmartDialog.showLoading(msg: "");
      loadError.value = false;
      addSysMsg("正在读取直播间信息");
      final room = await requestSite.liveSite.getRoomDetail(roomId: requestRoomId);
      if (!_roomTasks.isCurrent(generation)) return;
      detail.value = room;

      if (site.id == Constant.kDouyin) {
        // 1.6.0之前收藏的WebRid
        // 1.6.0收藏的RoomID
        // 1.6.0之后改回WebRid
        if (detail.value!.roomId != roomId) {
          var oldId = roomId;
          rxRoomId.value = detail.value!.roomId;
          if (followed.value) {
            // 更新关注列表
            DBService.instance.deleteFollow("${site.id}_$oldId");
            DBService.instance.addFollow(
              FollowUser(
                id: "${site.id}_$roomId",
                roomId: roomId,
                siteId: site.id,
                userName: detail.value!.userName,
                face: detail.value!.userAvatar,
                addTime: DateTime.now(),
              ),
            );
          } else {
            followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
          }
        }
      }

      addHistory();
      // 确认房间关注状态
      followed.value = FollowService.instance.getFollowExist("${site.id}_$roomId");
      online.value = detail.value!.online;
      liveStatus.value = detail.value!.status || detail.value!.isRecord;
      followUserBlock.value = FollowBlockService.instance.getBlock(siteId: site.id, roomId: roomId);
      if (liveStatus.value) {
        getSuperChatMessage();
        getPlayQualites();
        addSysMsg("开始连接弹幕服务器");
        initDanmau();
        _startDanmaku(generation, liveDanmaku, detail.value?.danmakuData);
      }
      if (detail.value!.isRecord) {
        addSysMsg("当前主播未开播，正在轮播录像");
      }
    } catch (e) {
      if (!_roomTasks.isCurrent(generation)) return;
      Log.logPrint(e);
      //SmartDialog.showToast(e.toString());
      loadError.value = true;
      if (e is Error) {
        error = e;
      }
    } finally {
      if (_roomTasks.isCurrent(generation)) {
        SmartDialog.dismiss(status: SmartStatus.loading);
      }
    }
  }

  /// 初始化播放器
  void getPlayQualites() async {
    final generation = _roomTasks.current;
    currentQuality = -1;

    try {
      var playQualites = await site.liveSite.getPlayQualites(detail: detail.value!);

      if (!_roomTasks.isCurrent(generation)) return;
      if (playQualites.isEmpty) {
        SmartDialog.showToast("无法读取播放清晰度");
        return;
      }
      qualities.assignAll(playQualites);
      var qualityLevel = await getQualityLevel();
      if (!_roomTasks.isCurrent(generation)) return;
      if (qualityLevel == 2) {
        //最高
        currentQuality = 0;
      } else if (qualityLevel == 0) {
        //最低
        currentQuality = playQualites.length - 1;
      } else {
        //中间值
        int middle = (playQualites.length / 2).floor();
        currentQuality = middle;
      }
      await getPlayUrl();
    } catch (e) {
      Log.logPrint(e);
      if (_roomTasks.isCurrent(generation)) {
        SmartDialog.showToast("无法读取播放清晰度");
      }
    }
  }

  Future<int> getQualityLevel() async {
    var qualityLevel = AppSettingsController.instance.qualityLevel.value;
    try {
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult.first == ConnectivityResult.mobile) {
        qualityLevel = AppSettingsController.instance.qualityLevelCellular.value;
      }
    } catch (e) {
      Log.logPrint(e);
    }
    return qualityLevel;
  }

  Future<void> getPlayUrl() async {
    if (_roomClosed || detail.value == null || currentQuality < 0 || currentQuality >= qualities.length) return;
    // All manual quality controls enter here; automatic recovery fetches its
    // own URLs so it cannot accidentally replenish the attempt budget.
    _resetPlaybackRecovery();
    final roomGeneration = _roomTasks.current;
    final generation = _playTasks.invalidate();
    _playlistReady = false;
    try {
      currentQualityInfo.value = qualities[currentQuality].quality;
      currentLineInfo.value = "";
      currentLineIndex = -1;
      var playUrl = await site.liveSite.getPlayUrls(detail: detail.value!, quality: qualities[currentQuality]);
      if (!_isCurrentPlayRequest(generation, roomGeneration)) return;
      if (playUrl.urls.isEmpty) {
        SmartDialog.showToast("无法读取播放地址");
        return;
      }
      playUrls.assignAll(playUrl.urls); // 深拷贝
      playHeaders = playUrl.headers;
      currentLineIndex = 0;
      currentLineInfo.value = "线路${currentLineIndex + 1}";
      await initPlaylist(generation, roomGeneration);
    } catch (e) {
      if (_isCurrentPlayRequest(generation, roomGeneration)) {
        Log.logPrint(e);
        SmartDialog.showToast("无法读取播放地址");
      }
    }
  }

  void changePlayLine(int index) {
    if (_roomClosed || !_playlistReady || index < 0 || index >= playUrls.length) return;
    currentLineIndex = index;
    _resetPlaybackRecovery();
    _playTasks.invalidate();
    setPlayer();
  }

  bool _isCurrentPlayRequest(int generation, int roomGeneration) =>
      _playTasks.isCurrent(generation) && _roomTasks.isCurrent(roomGeneration);

  Future<void> initPlaylist(int generation, int roomGeneration, {bool Function()? shouldPlay}) async {
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    errorMsg.value = "";

    final mediaList = playUrls.map((url) {
      var finalUrl = url;
      if (AppSettingsController.instance.playerForceHttps.value) {
        finalUrl = finalUrl.replaceAll("http://", "https://");
      }
      return Media(finalUrl, httpHeaders: playHeaders);
    }).toList();

    // 初始化播放器并设置 ao 参数
    await playerCommands.run(() async {
      if (!_isCurrentPlayRequest(generation, roomGeneration)) return;
      await initializePlayer();
      if (!_isCurrentPlayRequest(generation, roomGeneration)) return;
      _playlistReady = true;
      await player.open(Playlist(mediaList, index: currentLineIndex), play: shouldPlay?.call() ?? true);
    });
  }

  void setPlayer() async {
    if (_roomClosed || !_playlistReady || currentLineIndex < 0 || currentLineIndex >= playUrls.length) return;
    final generation = _playTasks.current;
    final line = currentLineIndex;
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    errorMsg.value = "";

    try {
      await playerCommands.run(() async {
        if (_playTasks.isCurrent(generation)) await player.jump(line);
      });
    } catch (e) {
      if (_playTasks.isCurrent(generation)) Log.logPrint(e);
    }
  }

  @override
  void mediaEnd() {
    if (_recovery.busy) _failureDuringRecovery = true;
    _schedulePlaybackRecovery('播放中断');
  }

  @override
  void mediaError(String error) {
    if (_recovery.busy) _failureDuringRecovery = true;
    Log.d('播放错误，准备重新获取播放地址：$error');
    _schedulePlaybackRecovery('播放连接异常');
  }

  void _clearRecoveryPlayIntent() {
    _recoveryPlaySubscription?.cancel();
    _recoveryPlaySubscription = null;
    _pendingRecoveryPlayIntent = null;
  }

  RecoveryPlayIntent _ensureRecoveryPlayIntent() {
    final existing = _pendingRecoveryPlayIntent;
    if (existing != null) return existing;
    final intent = RecoveryPlayIntent(initiallyPlaying: player.state.playing);
    _pendingRecoveryPlayIntent = intent;
    final roomGeneration = _roomTasks.current;
    _recoveryPlaySubscription = player.stream.playing.listen((playing) {
      if (_roomTasks.isCurrent(roomGeneration) && identical(_pendingRecoveryPlayIntent, intent)) {
        intent.observe(playing: playing, completed: player.state.completed);
      }
    });
    return intent;
  }

  void _resetPlaybackRecovery() {
    _clearRecoveryPlayIntent();
    _recoveryOpenedPaused = false;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _recoveryVerificationTimer?.cancel();
    _recoveryVerificationTimer = null;
    _recovery.reset();
    _recovering = false;
    _recoveryFailed = false;
    _failureDuringRecovery = false;
  }

  void _monitorPlayback() {
    if (_roomClosed || !_playlistReady) return;
    final state = player.state;
    if (state.playing) _recoveryOpenedPaused = false;
    final now = DateTime.now();
    final eligible = !isBackground && state.playing && !state.buffering && !_recovery.busy;
    if (_recovery.observeProgress(state.position, now, eligible: eligible) && _recovering) {
      _recovering = false;
      _clearRecoveryPlayIntent();
      _recoveryFailed = false;
      _recoveryTimer?.cancel();
      _recoveryTimer = null;
      _recoveryVerificationTimer?.cancel();
      _recoveryVerificationTimer = null;
      errorMsg.value = '';
      addSysMsg('播放已恢复');
    }
    // A deliberate pause or background playback must not start this watchdog.
    if (_recovery.observeBuffering(now,
        eligible: !isBackground && state.playing && state.buffering && !_recovery.busy)) {
      _schedulePlaybackRecovery('缓冲时间过长');
    }
  }

  void _schedulePlaybackRecovery(String reason) {
    if (_roomClosed || !_playlistReady || _recoveryFailed) return;
    final mayRequest = _recovery.request(background: isBackground);
    _recovering = true;
    if (_recovery.busy) return;
    _ensureRecoveryPlayIntent();
    if (!mayRequest) return;
    if (_recoveryOpenedPaused && !player.state.playing) return;
    if (_recovery.exhausted) {
      _showRecoveryFailed();
      return;
    }
    if (_recoveryTimer != null) return;
    _recoveryVerificationTimer?.cancel();
    _recoveryVerificationTimer = null;
    final roomGeneration = _roomTasks.current;
    _recoveryTimer = Timer(_recovery.retryDelay(DateTime.now()), () {
      _recoveryTimer = null;
      if (_roomTasks.isCurrent(roomGeneration) && !isBackground) {
        unawaited(_recoverPlayback(reason));
      }
    });
  }

  Future<void> _recoverPlayback(String reason) async {
    if (_roomClosed || isBackground || detail.value == null || currentQuality < 0 || currentQuality >= qualities.length)
      return;
    final recoveryToken = _recovery.begin(DateTime.now());
    if (recoveryToken == null) return;
    final roomGeneration = _roomTasks.current;
    final playGeneration = _playTasks.invalidate();
    final selectedLine = currentLineIndex;
    bool current() =>
        !_roomClosed &&
        !isBackground &&
        _recovery.isCurrent(recoveryToken) &&
        _isCurrentPlayRequest(playGeneration, roomGeneration);
    var opened = false;
    var openedPaused = false;
    _failureDuringRecovery = false;
    final playIntent = _ensureRecoveryPlayIntent();
    addSysMsg('$reason，正在尝试恢复（${_recovery.attempts}/${PlaybackRecovery.maxAttempts}）');
    try {
      final result = await site.liveSite
          .getPlayUrls(
            detail: detail.value!,
            quality: qualities[currentQuality],
          )
          .timeout(const Duration(seconds: 12));
      if (!current()) return;
      if (result.urls.isEmpty) throw StateError('未获取到可用播放地址');
      playUrls.assignAll(result.urls);
      playHeaders = result.headers;
      currentLineIndex = recoveryLineIndex(selectedLine, playUrls.length, _recovery.attempts);
      await initPlaylist(playGeneration, roomGeneration, shouldPlay: () {
        // Stop observing before native open emits its own stop/play sequence.
        _clearRecoveryPlayIntent();
        final play = playIntent.beginOpen();
        openedPaused = !play;
        _recoveryOpenedPaused = openedPaused;
        return play;
      });
      if (!current()) return;
      opened = true;
    } catch (e) {
      if (current()) Log.logPrint(e);
    } finally {
      if (current()) {
        _recovery.finish(recoveryToken, DateTime.now());
        if (opened) {
          // open() completion isn't playback success: errors emitted during
          // single-flight recovery can be coalesced, so always verify progress.
          _recoveryVerificationTimer = Timer(const Duration(seconds: 20), () {
            _recoveryVerificationTimer = null;
            if (!current() || !_recovering) return;
            final state = player.state;
            if (openedPaused && !state.playing) return;
            // A paused player without an error must stay paused.
            if (!_failureDuringRecovery && !state.playing && !state.completed && !state.buffering) return;
            _schedulePlaybackRecovery('播放仍未恢复');
          });
        } else {
          _schedulePlaybackRecovery('重新连接失败');
        }
      }
    }
  }

  void _showRecoveryFailed() {
    if (_recoveryFailed) return;
    _recoveryFailed = true;
    _clearRecoveryPlayIntent();
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _recoveryVerificationTimer?.cancel();
    _recoveryVerificationTimer = null;
    const message = '播放中断，自动恢复未成功，请手动刷新';
    errorMsg.value = message;
    addSysMsg(message);
    SmartDialog.showToast(message);
    // Connection failure alone is not proof that the broadcaster went offline.
    super.mediaEnd();
  }

  /// 读取SC
  void getSuperChatMessage() async {
    final generation = _roomTasks.current;
    try {
      var sc = await site.liveSite.getSuperChatMessage(roomId: detail.value!.roomId);
      if (!_roomTasks.isCurrent(generation)) return;
      superChats.addAll(sc);
    } catch (e) {
      Log.logPrint(e);
      if (_roomTasks.isCurrent(generation)) addSysMsg("SC读取失败");
    }
  }

  /// 移除掉已到期的SC
  void removeSuperChats() async {
    var now = DateTime.now().millisecondsSinceEpoch;
    superChats.removeWhere((x) => x.endTime.millisecondsSinceEpoch <= now);
  }

  /// 添加历史记录
  void addHistory() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    History history = History(
      id: id,
      roomId: roomId,
      siteId: site.id,
      userName: detail.value?.userName ?? "",
      face: detail.value?.userAvatar ?? "",
      updateTime: DateTime.now(),
    );
    HistoryService.instance.start(history);
  }

  /// 关注用户
  Future<void> followUser() async {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    var historyDurationSec = HistoryService.instance.getHistoryDurationSec(followUserId: id);
    await FollowService.instance.addFollow(
      FollowUser(
        id: id,
        roomId: roomId,
        siteId: site.id,
        userName: detail.value?.userName ?? "",
        face: detail.value?.userAvatar ?? "",
        addTime: DateTime.now(),
        lastWatchTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        watchDurationSec: historyDurationSec,
      )
        ..liveStatus.value = liveStatus.value ? 2 : 1
        ..cover.value = detail.value?.cover ?? "",
    );
    followed.value = true;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
  }

  /// 取消关注用户
  void removeFollowUser() async {
    if (detail.value == null) {
      return;
    }
    if (!await Utils.showAlertDialog("确定要取消关注该用户吗？", title: "取消关注")) {
      return;
    }

    var id = "${site.id}_$roomId";
    await FollowService.instance.removeFollowUser(id);
    followed.value = false;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
  }

  void share() {
    if (detail.value == null) {
      return;
    }
    SharePlus.instance.share(ShareParams(text: detail.value!.url));
  }

  void copyUrl() {
    if (detail.value == null) {
      return;
    }
    Utils.copyToClipboard(detail.value!.url);
    SmartDialog.showToast("已复制直播间链接");
  }

  Future<void> visitWebLive() async {
    Uri uri = Uri.parse(detail.value!.url);
    if (await canLaunchUrl(uri) || runningInSandbox()) {
      await launchUrl(uri);
    } else {
      throw '无法打开网页 $uri';
    }
  }

  /// 底部打开播放器设置
  void showDanmuSettingsSheet() {
    Utils.showBottomSheet(
      title: "弹幕设置",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          DanmuSettingsView(
            danmakuController: danmakuController,
            onTapDanmuShield: () {
              Get.back();
              showFollowBlockShield();
            },
          ),
        ],
      ),
    );
  }

  void showVolumeSlider(BuildContext targetContext) {
    SmartDialog.showAttach(
      targetContext: targetContext,
      alignment: Alignment.topCenter,
      displayTime: const Duration(seconds: 3),
      maskColor: const Color(0x00000000),
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: AppStyle.radius12,
            color: Theme.of(context).cardColor,
          ),
          padding: AppStyle.edgeInsetsA4,
          child: Obx(
            () => SizedBox(
              width: 200,
              child: Slider(
                min: 0,
                max: 100,
                value: AppSettingsController.instance.playerVolume.value,
                onChanged: (newValue) {
                  player.setVolume(newValue);
                  AppSettingsController.instance.setPlayerVolume(newValue);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void showQualitySheet() {
    Utils.showBottomSheet(
      title: "切换清晰度",
      child: RadioGroup(
        groupValue: currentQuality,
        onChanged: (e) async {
          Get.back();
          _resetPlaybackRecovery();
          currentQuality = e ?? 0;
          await getPlayUrl();
        },
        child: ListView.builder(
          itemCount: qualities.length,
          itemBuilder: (_, i) {
            var item = qualities[i];
            return RadioListTile(
              value: i,
              title: Text(item.quality),
            );
          },
        ),
      ),
    );
  }

  void showPlayUrlsSheet() {
    Utils.showBottomSheet(
      title: "切换线路",
      child: RadioGroup(
        groupValue: currentLineIndex,
        onChanged: (e) {
          Get.back();
          //currentLineIndex = i;
          //setPlayer();
          changePlayLine(e ?? 0);
        },
        child: ListView.builder(
          itemCount: playUrls.length,
          itemBuilder: (_, i) {
            return RadioListTile(
              value: i,
              title: Text("线路${i + 1}"),
              secondary: Text(
                playUrls[i].contains(".flv") ? "FLV" : "HLS",
              ),
            );
          },
        ),
      ),
    );
  }

  void showPlayerSettingsSheet() {
    Utils.showBottomSheet(
      title: "画面尺寸",
      child: Obx(
        () => ListView(
          padding: AppStyle.edgeInsetsV12,
          children: [
            RadioGroup(
              groupValue: AppSettingsController.instance.scaleMode.value,
              onChanged: (e) {
                AppSettingsController.instance.setScaleMode(e ?? 0);
                updateScaleMode();
              },
              child: Column(
                children: [
                  RadioListTile(
                    value: 0,
                    title: const Text("适应"),
                    visualDensity: VisualDensity.compact,
                  ),
                  RadioListTile(
                    value: 1,
                    title: const Text("拉伸"),
                    visualDensity: VisualDensity.compact,
                  ),
                  RadioListTile(
                    value: 2,
                    title: const Text("铺满"),
                    visualDensity: VisualDensity.compact,
                  ),
                  RadioListTile(
                    value: 3,
                    title: const Text("16:9"),
                    visualDensity: VisualDensity.compact,
                  ),
                  RadioListTile(
                    value: 4,
                    title: const Text("4:3"),
                    visualDensity: VisualDensity.compact,
                  ),
                  RadioListTile(
                    value: 5,
                    title: Obx(() => Text(
                        "自定义（${AppSettingsController.instance.aspectWidth.value}:${AppSettingsController.instance.aspectHeight.value}）")),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void showAspectRatioSheet() {
    final widthController = TextEditingController(text: AppSettingsController.instance.aspectWidth.value.toString());
    final heightController = TextEditingController(text: AppSettingsController.instance.aspectHeight.value.toString());
    Utils.showBottomSheet(
      title: "自定义缩放比例",
      child: Padding(
        padding: AppStyle.edgeInsetsH16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widthController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "宽",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                AppStyle.hGap12,
                const Text("x", style: TextStyle(fontSize: 18)),
                AppStyle.hGap12,
                Expanded(
                  child: TextField(
                    controller: heightController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "高",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            AppStyle.vGap12,
            TextButton(
              onPressed: () {
                final w = int.tryParse(widthController.text) ?? 16;
                final h = int.tryParse(heightController.text) ?? 9;
                if (w <= 0 || h <= 0) return;
                AppSettingsController.instance.setAspectWidth(w);
                AppSettingsController.instance.setAspectHeight(h);
                AppSettingsController.instance.setAspectByUser(w / h);
                AppSettingsController.instance.setScaleMode(5);
                updateScaleMode();
                Get.back();
              },
              child: const Text("确定"),
            ),
          ],
        ),
      ),
    );
  }

  void showFollowBlockShield({bool blockWords = true}) {
    TextEditingController keywordController = TextEditingController();

    void addKeyword() {
      if (keywordController.text.isEmpty) {
        SmartDialog.showToast("请输入${blockWords ? "关键词" : "用户名"}");
        return;
      }
      addCurBlockWord(keywordController.text.trim());
      keywordController.text = "";
    }

    Utils.showBottomSheet(
      title: "当前主播${blockWords ? "弹幕" : "用户"}屏蔽",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          TextField(
            controller: keywordController,
            decoration: InputDecoration(
              contentPadding: AppStyle.edgeInsetsH12,
              border: const OutlineInputBorder(),
              hintText: "请输入${blockWords ? "关键词" : "用户名"}",
              suffixIcon: TextButton.icon(
                onPressed: addKeyword,
                icon: const Icon(Icons.add),
                label: const Text("添加"),
              ),
            ),
            onSubmitted: (e) {
              addKeyword();
            },
          ),
          AppStyle.vGap12,
          Obx(() {
            var len =
                blockWords ? followUserBlock.value!.blockWords.length : followUserBlock.value!.blockAccounts.length;
            return Text(
              "已添加$len个${blockWords ? "关键词" : "用户"}（点击移除）",
              style: Get.textTheme.titleSmall,
            );
          }),
          AppStyle.vGap12,
          Obx(() {
            final block = followUserBlock.value!;

            final List<({String label, VoidCallback onTap})> items = blockWords
                ? block.blockWords
                    .map(
                      (item) => (
                        label: item,
                        onTap: () => delCurBlockWord(item),
                      ),
                    )
                    .toList()
                : block.blockAccounts
                    .map(
                      (item) => (
                        label: item.name,
                        onTap: () => delCurBlockAccount(item.name),
                      ),
                    )
                    .toList();

            return Wrap(
              runSpacing: 12,
              spacing: 12,
              children: items
                  .map(
                    (item) => InkWell(
                      borderRadius: AppStyle.radius24,
                      onTap: item.onTap,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: AppStyle.radius24,
                        ),
                        padding: AppStyle.edgeInsetsH12.copyWith(top: 4, bottom: 4),
                        child: Text(item.label, style: Get.textTheme.bodyMedium),
                      ),
                    ),
                  )
                  .toList(),
            );
          })
        ],
      ),
    );
  }

  void showFollowUserSheet() {
    Utils.showBottomSheet(
      title: "关注列表",
      child: Obx(
        () {
          final followList = FollowService.instance.getLiveRoomFollowList(
            AppSettingsController.instance.liveRoomFollowSortMethod.value,
          );
          return Stack(
            children: [
              RefreshIndicator(
                onRefresh: FollowService.instance.loadData,
                child: ListView.builder(
                  itemCount: followList.length,
                  itemBuilder: (_, i) {
                    var item = followList[i];
                    return Obx(
                      () => FollowUserItem(
                        item: item,
                        showTag: false,
                        playing: rxSite.value.id == item.siteId && rxRoomId.value == item.roomId,
                        onTap: () {
                          Get.back();
                          resetRoom(
                            Sites.allSites[item.siteId]!,
                            item.roomId,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Obx(
                    () => DesktopRefreshButton(
                      refreshing: FollowService.instance.updating.value,
                      onPressed: FollowService.instance.loadData,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void showAutoExitSheet() {
    if (AppSettingsController.instance.autoExitEnable.value && !delayAutoExit.value) {
      SmartDialog.showToast("已设置了全局定时关闭");
      return;
    }
    Utils.showBottomSheet(
      title: "定时关闭",
      child: ListView(
        children: [
          Obx(
            () => SwitchListTile(
              title: Text(
                "启用定时关闭",
                style: Get.textTheme.titleMedium,
              ),
              value: autoExitEnable.value,
              onChanged: (e) {
                autoExitEnable.value = e;

                setAutoExit();
                //controller.setAutoExitEnable(e);
              },
            ),
          ),
          Obx(
            () => ListTile(
              enabled: autoExitEnable.value,
              title: Text(
                "自动关闭时间：${autoExitMinutes.value ~/ 60}小时${autoExitMinutes.value % 60}分钟",
                style: Get.textTheme.titleMedium,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                var value = await showTimePicker(
                  context: Get.context!,
                  initialTime: TimeOfDay(
                    hour: autoExitMinutes.value ~/ 60,
                    minute: autoExitMinutes.value % 60,
                  ),
                  initialEntryMode: TimePickerEntryMode.inputOnly,
                  builder: (_, child) {
                    return MediaQuery(
                      data: Get.mediaQuery.copyWith(
                        alwaysUse24HourFormat: true,
                      ),
                      child: child!,
                    );
                  },
                );
                if (value == null || (value.hour == 0 && value.minute == 0)) {
                  return;
                }
                var duration = Duration(hours: value.hour, minutes: value.minute);
                autoExitMinutes.value = duration.inMinutes;
                AppSettingsController.instance.setRoomAutoExitDuration(autoExitMinutes.value);
                //setAutoExitDuration(duration.inMinutes);
                setAutoExit();
              },
            ),
          ),
        ],
      ),
    );
  }

  void openNaviteAPP() async {
    var naviteUrl = "";
    var webUrl = "";
    if (site.id == Constant.kBiliBili) {
      naviteUrl = "bilibili://live/${detail.value?.roomId}";
      webUrl = "https://live.bilibili.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyin) {
      var args = detail.value?.danmakuData as DouyinDanmakuArgs;
      naviteUrl = "snssdk1128://webcast_room?room_id=${args.roomId}";
      webUrl = "https://live.douyin.com/${args.webRid}";
    } else if (site.id == Constant.kHuya) {
      var args = detail.value?.danmakuData as HuyaDanmakuArgs;
      naviteUrl =
          "yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html%3Fhyaction%3Dlive%26channelid%3D${args.subSid}%26subid%3D${args.subSid}%26liveuid%3D${args.subSid}%26screentype%3D1%26sourcetype%3D0%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide";
      webUrl = "https://www.huya.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyu) {
      naviteUrl =
          "douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D${detail.value?.roomId}";
      webUrl = "https://www.douyu.com/${detail.value?.roomId}";
    }
    try {
      await launchUrlString(naviteUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("无法打开APP，将使用浏览器打开");
      await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  void resetRoom(Site site, String roomId) async {
    if (_roomClosed || (this.site == site && this.roomId == roomId)) {
      return;
    }

    _resetPlaybackRecovery();
    final generation = _roomTasks.invalidate();
    _playTasks.invalidate();
    _playlistReady = false;
    rxSite.value = site;
    rxRoomId.value = roomId;
    detail.value = null;
    liveStatus.value = false;
    qualities.clear();
    playUrls.clear();
    currentQuality = -1;
    currentLineIndex = -1;
    currentQualityInfo.value = "";
    currentLineInfo.value = "";

    // 清除全部消息
    _stopDanmaku();
    danmakuBuffer.clear();
    messages.clear();
    _chatBuffer.clear();
    disableAutoScroll.value = false;
    superChats.clear();
    danmakuController?.clear();
    // 表情包是分房间下发的，换房间后上一个房间的合成位图没有复用价值
    DanmakuEmoticonRenderer.clearCache();

    rustDanmakuMask.reset();

    // 停止播放
    HistoryService.instance.stop();
    try {
      await playerCommands.run(() async {
        if (_roomTasks.isCurrent(generation)) await player.stop();
      });
    } catch (e) {
      if (_roomTasks.isCurrent(generation)) Log.logPrint(e);
    }
    if (!_roomTasks.isCurrent(generation)) return;

    // 刷新信息
    loadData();
  }

  void copyErrorDetail() {
    Utils.copyToClipboard('''直播平台：${rxSite.value.name}
房间号：${rxRoomId.value}
错误信息：
${error?.toString()}
----------------
${error?.stackTrace}''');
    SmartDialog.showToast("已复制错误信息");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_roomClosed) return;

    if (state == AppLifecycleState.paused) {
      Log.d("进入后台");
      //进入后台，关闭弹幕
      danmakuController?.clear();
      isBackground = true;
      _recoveryTimer?.cancel();
      _recoveryTimer = null;
      _recoveryVerificationTimer?.cancel();
      _recoveryVerificationTimer = null;
      if (_recovery.busy) _playTasks.invalidate();
      _recovery.cancel();
    } else
    //返回前台
    if (state == AppLifecycleState.resumed) {
      // update();
      Log.d("返回前台");
      danmakuController?.resume();
      isBackground = false;
      if (_recovery.pending && !_recoveryFailed) _schedulePlaybackRecovery('返回前台后恢复播放');
    }
  }

  Future<void> _startDanmaku(int generation, LiveDanmaku connection, dynamic args) async {
    try {
      await connection.start(args);
    } catch (e) {
      if (_roomTasks.isCurrent(generation)) {
        Log.logPrint(e);
        addSysMsg("弹幕连接失败");
      }
    } finally {
      // Some platforms prepare a signature asynchronously before opening WS.
      if (!_roomTasks.isCurrent(generation)) {
        try {
          await connection.stop();
        } catch (e) {
          Log.logPrint(e);
        }
      }
    }
  }

  void _stopDanmaku() {
    liveDanmaku.onMessage = null;
    liveDanmaku.onClose = null;
    liveDanmaku.onReady = null;
    unawaited(liveDanmaku.stop().then<void>((_) {}, onError: (Object e, StackTrace s) {
      Log.logPrint(e);
    }));
  }

  @override
  void onClose() {
    _roomClosed = true;
    _playbackMonitor?.cancel();
    _resetPlaybackRecovery();
    _roomTasks.close();
    _playTasks.close();
    _playlistReady = false;
    subscription?.cancel();
    _autoExitGraceTimer?.cancel();
    danmakuBuffer.clear();
    SmartDialog.dismiss(status: SmartStatus.loading);
    WidgetsBinding.instance.removeObserver(this);
    scrollController.removeListener(scrollListener);
    scrollController.dispose();
    autoExitTimer?.cancel();
    danmakuTimer?.cancel();
    HistoryService.instance.stop();

    _stopDanmaku();
    danmakuController?.clear();
    danmakuController = null;
    // 直接退出直播间不经过 resetRoom，这里补一次：表情是分房间下发的，
    // 留在静态缓存里的源图句柄与合成位图出房间后就没有复用价值了。
    DanmakuEmoticonRenderer.clearCache();
    _chatBuffer.clear();
    unawaited(_releaseDanmakuMask());
    super.onClose();
  }

  Future<void> _releaseDanmakuMask() async {
    // Native owned disposal must not race a batch borrowing the same handle.
    try {
      await _maskInFlight;
    } catch (_) {
      // A failed batch still needs disposal.
    }
    try {
      rustDanmakuMask.dispose();
    } catch (e) {
      Log.logPrint(e);
    }
  }
}
