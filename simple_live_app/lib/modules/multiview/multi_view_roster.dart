/// Playback membership and audio ownership, independent of Flutter/native media.
class MultiViewRoster {
  static const maxSessions = 4;
  final List<String> _ids = [];
  final Set<String> _audioIds = {};
  final Map<String, double> _volumes = {};

  String? get audioId => _audioIds.firstOrNull;
  bool isAudible(String id) => _audioIds.contains(id);
  double volume(String id) => _volumes[id] ?? 100;

  List<String> get ids => List.unmodifiable(_ids);

  bool shouldSuspend(String id, {required bool background}) => background && !isAudible(id);

  String? add(String id) {
    if (_ids.contains(id)) return '这个直播间已经在同屏中';
    if (_ids.length >= maxSessions) return '最多同时观看 4 个直播间';
    if (_ids.isEmpty) _audioIds.add(id);
    _ids.add(id);
    _volumes[id] = 100;
    return null;
  }

  void selectAudio(String id) {
    if (!_ids.contains(id)) return;
    _audioIds
      ..clear()
      ..add(id);
  }

  void toggleAudio(String id) {
    if (!_ids.contains(id)) return;
    if (!_audioIds.remove(id)) _audioIds.add(id);
  }

  void setVolume(String id, double value) {
    if (!_ids.contains(id) || !value.isFinite) return;
    _volumes[id] = value.clamp(0, 100).toDouble();
  }

  void remove(String id) {
    _ids.remove(id);
    _audioIds.remove(id);
    _volumes.remove(id);
  }

  void swap(int a, int b) {
    if (a < 0 || b < 0 || a >= _ids.length || b >= _ids.length) return;
    final old = _ids[a];
    _ids[a] = _ids[b];
    _ids[b] = old;
  }
}
