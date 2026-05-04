import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/utils/duration_2_str_utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';

List<FollowUser> sortLiveRoomFollowUsers({
  required Iterable<FollowUser> users,
  required LiveRoomFollowSortMethod method,
  required Map<String, History> historiesById,
}) {
  final sorted = List<FollowUser>.of(users);
  sorted.sort((a, b) {
    switch (method) {
      case LiveRoomFollowSortMethod.watchDuration:
        return _compareWatchDurationDesc(a, b);
      case LiveRoomFollowSortMethod.recentEnter:
        final recentCompare = _compareDateTimeDesc(
          historiesById[a.id]?.updateTime,
          historiesById[b.id]?.updateTime,
        );
        if (recentCompare != 0) {
          return recentCompare;
        }
        return _compareWatchDurationDesc(a, b);
    }
  });
  return sorted;
}

int _compareDateTimeDesc(DateTime? a, DateTime? b) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return 1;
  }
  if (b == null) {
    return -1;
  }
  return b.compareTo(a);
}

int _compareWatchDurationDesc(FollowUser a, FollowUser b) {
  final durationCompare = _watchDurationOf(b).compareTo(_watchDurationOf(a));
  if (durationCompare != 0) {
    return durationCompare;
  }
  return a.id.compareTo(b.id);
}

Duration _watchDurationOf(FollowUser user) {
  if (user.watchDurationSec > 0) {
    return Duration(seconds: user.watchDurationSec);
  }
  final watchDuration = user.watchDuration;
  if (watchDuration == null || watchDuration.isEmpty) {
    return Duration.zero;
  }
  try {
    return watchDuration.toDuration();
  } on FormatException {
    return Duration.zero;
  }
}
