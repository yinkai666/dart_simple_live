import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/utils/live_room_follow_sort.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';

void main() {
  group('sortLiveRoomFollowUsers', () {
    test('sorts by cumulative watch duration descending', () {
      final users = [
        _followUser('site_1', watchDuration: '00:05:00'),
        _followUser('site_2', watchDuration: '01:00:00'),
        _followUser('site_3', watchDuration: '00:30:00'),
      ];

      final sorted = sortLiveRoomFollowUsers(
        users: users,
        method: LiveRoomFollowSortMethod.watchDuration,
        historiesById: const {},
      );

      expect(sorted.map((e) => e.id), ['site_2', 'site_3', 'site_1']);
      expect(users.map((e) => e.id), ['site_1', 'site_2', 'site_3']);
    });

    test('sorts by recent room enter time and pushes missing histories last',
        () {
      final users = [
        _followUser('site_1', watchDuration: '02:00:00'),
        _followUser('site_2', watchDuration: '03:00:00'),
        _followUser('site_3', watchDuration: '00:30:00'),
      ];
      final historiesById = {
        'site_1': _history('site_1', DateTime(2026, 1, 1, 10)),
        'site_3': _history('site_3', DateTime(2026, 1, 2, 10)),
      };

      final sorted = sortLiveRoomFollowUsers(
        users: users,
        method: LiveRoomFollowSortMethod.recentEnter,
        historiesById: historiesById,
      );

      expect(sorted.map((e) => e.id), ['site_3', 'site_1', 'site_2']);
      expect(users.map((e) => e.id), ['site_1', 'site_2', 'site_3']);
    });
  });
}

FollowUser _followUser(String id, {required String watchDuration}) {
  return FollowUser(
    id: id,
    roomId: id.split('_').last,
    siteId: id.split('_').first,
    userName: id,
    face: '',
    addTime: DateTime(2026),
    watchDuration: watchDuration,
  );
}

History _history(String id, DateTime updateTime) {
  return History(
    id: id,
    roomId: id.split('_').last,
    siteId: id.split('_').first,
    userName: id,
    face: '',
    updateTime: updateTime,
  );
}
