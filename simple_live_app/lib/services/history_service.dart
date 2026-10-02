import 'dart:async';

import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils/extensions/duration_2_str_utils.dart';
import 'package:simple_live_app/models/db/history.dart';

import 'db_service.dart';

class HistoryService extends GetxService {
  static HistoryService get instance => Get.find<HistoryService>();
  final Stopwatch _stopwatch = Stopwatch();
  var _elapsed = Duration.zero;
  int _savedElapsedSeconds = 0;
  Duration _oldWatchedDuration = Duration.zero;
  History? curLiveRoomHistory;

  //两分钟自动保存一次，防止用户直接关闭app，丢失数据
  final _saveInterval = const Duration(minutes: 2);
  Timer? _timer; // 定时器

  // 开始计时
  void start(History history) {
    if (curLiveRoomHistory?.id == history.id && _stopwatch.isRunning) return;
    stop();
    _loadHistory(history);
    _stopwatch.start();
    _timer = Timer.periodic(_saveInterval, (timer) {
      _updateHistory();
    });
  }

  // reset
  void reset(String roomId) {
    _updateHistory();
    _stopwatch.reset();
    _savedElapsedSeconds = 0;
    History? history = DBService.instance.getHistory(roomId);
    if (history != null) {
      _loadHistory(history);
    }
  }

  // 停止计时
  void stop() {
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
    _updateHistory();
    final elapsed = _stopwatch.elapsed;
    _stopwatch.reset();
    _elapsed = Duration.zero;
    _savedElapsedSeconds = 0;
    curLiveRoomHistory = null;
    Log.i("本次观看时长：$elapsed");
  }

  @override
  void onClose() {
    stop();
    super.onClose();
  }

  void _loadHistory(History history) {
    curLiveRoomHistory = DBService.instance.getHistory(history.id);
    // 首次观看则创建
    curLiveRoomHistory ??= history;
    curLiveRoomHistory!.updateTime = DateTime.now();
    DBService.instance.addOrUpdateHistory(curLiveRoomHistory!);
    EventBus.instance.emit(Constant.kUpdateFollow, curLiveRoomHistory);
    _oldWatchedDuration = curLiveRoomHistory!.duration;
  }

  // updateHistory
  void _updateHistory() {
    if (curLiveRoomHistory == null) {
      return;
    }
    // 累加到当前历史记录
    _elapsed = _stopwatch.elapsed;
    Duration curTime = _oldWatchedDuration + _elapsed;
    Log.i("已观看时间：${_oldWatchedDuration.toHMSString()}_增加时间：${_elapsed.toHMSString()}");
    curLiveRoomHistory?.watchDuration = curTime.toHMSString();
    curLiveRoomHistory?.syncDuration += _elapsed.inSeconds - _savedElapsedSeconds;
    _savedElapsedSeconds = _elapsed.inSeconds;
    curLiveRoomHistory?.updateTime = DateTime.now();
    DBService.instance.addOrUpdateHistory(curLiveRoomHistory!);
    EventBus.instance.emit(Constant.kUpdateFollow, curLiveRoomHistory);
  }

  // 获取历史记录中存储的累计观看时长
  int getHistoryDurationSec({required String followUserId}) {
    var historyWatchDurationSec = 0;
    History? history = DBService.instance.getHistory(followUserId);
    historyWatchDurationSec = history?.watchDuration?.toDuration().inSeconds ?? 0;
    return historyWatchDurationSec;
  }

  // history crud
  History? getHistory(String id) {
    return DBService.instance.getHistory(id);
  }

  Future<void> addOrUpdateHistory(History history) async {
    await DBService.instance.addOrUpdateHistory(history);
  }

  Future<void> delHistory(String id) async {
    await DBService.instance.delHistory(id);
  }

  List<History> getHistories() {
    return DBService.instance.getHistories();
  }

  Future<void> historyClear() async {
    await DBService.instance.historyBox.clear();
  }
}
