/// Playback membership and audio ownership, independent of Flutter/native media.
class MultiViewRoster {
  static const maxSessions = 4;
  final List<String> _ids = [];
  String? audioId;

  List<String> get ids => List.unmodifiable(_ids);

  bool shouldSuspend(String id, {required bool background}) => background && id != audioId;

  String? add(String id) {
    if (_ids.contains(id)) return '这个直播间已经在同屏中';
    if (_ids.length >= maxSessions) return '最多同时观看 4 个直播间';
    _ids.add(id);
    audioId ??= id;
    return null;
  }

  void selectAudio(String id) {
    if (_ids.contains(id)) audioId = id;
  }

  void remove(String id) {
    _ids.remove(id);
    if (audioId == id) audioId = _ids.isEmpty ? null : _ids.first;
  }

  void swap(int a, int b) {
    if (a < 0 || b < 0 || a >= _ids.length || b >= _ids.length) return;
    final old = _ids[a];
    _ids[a] = _ids[b];
    _ids[b] = old;
  }
}
