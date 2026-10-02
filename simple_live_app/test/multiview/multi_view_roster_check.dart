import '../../lib/modules/multiview/multi_view_roster.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final roster = MultiViewRoster();
  check(roster.add('a') == null && roster.audioId == 'a', 'first room owns audio');
  check(roster.add('a') != null && roster.ids.length == 1, 'duplicate rejected');
  for (final id in ['b', 'c', 'd']) {
    check(roster.add(id) == null, 'four simultaneous rooms supported');
  }
  check(roster.add('e') != null && roster.ids.length == 4, 'capacity enforced');
  roster.selectAudio('c');
  check(!roster.shouldSuspend('c', background: true), 'background preserves audible room');
  check(roster.shouldSuspend('b', background: true), 'background pauses secondary room');
  check(!roster.shouldSuspend('b', background: false), 'foreground restores secondary room');
  roster.selectAudio('missing');
  check(roster.audioId == 'c', 'unknown selection cannot steal audio');
  roster.remove('a');
  check(roster.audioId == 'c', 'removing secondary preserves audio');
  roster.remove('c');
  check(roster.audioId == 'b', 'removing audible room selects survivor');
  roster.swap(0, 1);
  check(roster.ids.first == 'd' && roster.audioId == 'b', 'reorder preserves audio');
  roster.remove('b');
  roster.remove('d');
  check(roster.audioId == null, 'empty workspace is silent');
  print('PASS: multi-view capacity, duplicate, audio ownership, removal and reorder');
}
