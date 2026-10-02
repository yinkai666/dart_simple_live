/// Keep the selected line first, then rotate across newly fetched alternatives.
int recoveryLineIndex(int selectedLine, int lineCount, int attempt) {
  if (lineCount <= 0) return -1;
  final base = selectedLine.clamp(0, lineCount - 1);
  return attempt <= 1 ? base : (base + 1) % lineCount;
}

/// Capture user play/pause transitions while fetching/queueing a recovery.
/// Initial stopped state may be EOF/error and must not suppress recovery.
class RecoveryPlayIntent {
  RecoveryPlayIntent({required bool initiallyPlaying}) : _wasPlaying = initiallyPlaying;
  bool _wasPlaying;
  bool _paused = false;
  bool _opening = false;

  void observe({required bool playing, required bool completed}) {
    if (_opening) return;
    if (playing) {
      _paused = false;
    } else if (_wasPlaying && !completed) {
      _paused = true;
    }
    _wasPlaying = playing;
  }

  bool beginOpen() {
    _opening = true;
    return !_paused;
  }
}

/// A URL opening successfully is not evidence that playback recovered.
/// Keep a bounded attempt budget until position advances over a stable period.
class PlaybackRecovery {
  static const retryInterval = Duration(seconds: 5);
  static const stablePeriod = Duration(seconds: 10);
  static const maxAttempts = 3;

  int _generation = 0;
  int attempts = 0;
  bool busy = false;
  DateTime? _retryAt;
  DateTime? _progressSince;
  DateTime? _lastProgressAt;
  Duration? _position;
  Duration? _progressPosition;
  DateTime? _bufferingSince;

  bool get exhausted => attempts >= maxAttempts;
  bool isCurrent(int token) => token == _generation;

  bool observeBuffering(DateTime now, {required bool eligible}) {
    if (!eligible) {
      _bufferingSince = null;
      return false;
    }
    _bufferingSince ??= now;
    if (now.difference(_bufferingSince!) < const Duration(seconds: 15)) return false;
    _bufferingSince = null;
    return true;
  }

  Duration retryDelay(DateTime now) {
    final remaining = _retryAt?.difference(now) ?? Duration.zero;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  int? begin(DateTime now) {
    if (busy || exhausted || retryDelay(now) > Duration.zero) return null;
    busy = true;
    attempts++;
    _progressSince = null;
    _progressPosition = null;
    _lastProgressAt = null;
    _position = null;
    return _generation;
  }

  void finish(int token, DateTime now) {
    if (!isCurrent(token)) return;
    busy = false;
    _retryAt = now.add(retryInterval);
  }

  /// Returns true only after successive advancing samples span ten seconds.
  bool observeProgress(Duration position, DateTime now, {required bool eligible}) {
    if (!eligible || (_position != null && position < _position!)) {
      _progressSince = null;
      _progressPosition = null;
      _lastProgressAt = null;
      _position = null;
      return false;
    }
    if (_position == position) return false;
    if (_lastProgressAt != null && now.difference(_lastProgressAt!) > const Duration(seconds: 5)) {
      _progressSince = null;
      _progressPosition = null;
    }
    _position = position;
    _lastProgressAt = now;
    _progressSince ??= now;
    _progressPosition ??= position;
    final elapsed = now.difference(_progressSince!);
    final advanced = position - _progressPosition!;
    if (elapsed < stablePeriod || advanced.inMilliseconds < elapsed.inMilliseconds * 0.8) return false;
    attempts = 0;
    _retryAt = null;
    return true;
  }

  void reset() {
    cancel();
    attempts = 0;
    _retryAt = null;
  }

  /// Suspend pending work without giving an interrupted attempt a new budget.
  void cancel() {
    _generation++;
    busy = false;
    _bufferingSince = null;
    _progressSince = null;
    _progressPosition = null;
    _lastProgressAt = null;
    _position = null;
  }
}
