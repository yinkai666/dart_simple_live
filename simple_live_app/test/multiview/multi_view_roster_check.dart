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
  check(roster.audioId == null, 'removing audible room must not unmute another room');
  roster.swap(0, 1);
  check(roster.ids.first == 'd' && roster.audioId == null, 'reorder preserves silence');
  roster.remove('b');
  roster.remove('d');
  check(roster.audioId == null, 'empty workspace is silent');
  roster.add('a');
  roster.add('b');
  roster.toggleAudio('b');
  check(roster.isAudible('a') && roster.isAudible('b'), 'multiple rooms can sound together');
  check(!roster.shouldSuspend('a', background: true) && !roster.shouldSuspend('b', background: true),
      'background retains all enabled sound sources');
  roster.setVolume('b', 35);
  roster.toggleAudio('b');
  check(!roster.isAudible('b') && roster.volume('b') == 35, 'mute retains independent volume');
  roster.toggleAudio('b');
  check(roster.isAudible('b') && roster.volume('b') == 35, 'unmute restores chosen level');
  roster.selectAudio('b');
  check(!roster.isAudible('a') && roster.isAudible('b'), 'solo mutes other rooms');
  roster.toggleAudio('b');
  roster.add('c');
  check(roster.audioId == null, 'adding to muted workspace does not enable audio');
  roster.setVolume('b', -1);
  check(roster.volume('b') == 0, 'volume lower bound');
  roster.setVolume('b', 101);
  check(roster.volume('b') == 100, 'volume upper bound');
  roster.setVolume('b', double.nan);
  check(roster.volume('b') == 100, 'invalid volume ignored');
  roster.toggleAudio('missing');
  check(roster.audioId == null, 'unknown room cannot become audible');
  print('PASS: multi-view capacity, duplicate, audio ownership, removal and reorder');
}
