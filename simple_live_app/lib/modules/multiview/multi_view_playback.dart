/// Must run in the native command queue: a removed target is still alive until
/// its queued release, and must be muted even after membership invalidation.
Future<void> muteBeforeSelect<T>(
  List<T> snapshot, {
  required Future<void> Function(T) mute,
  required Future<void> Function() apply,
}) async {
  for (final target in snapshot) {
    await mute(target);
  }
  await apply();
}

/// Native open is not cancellable. Stop a superseded open inside the same
/// queue transaction before any subsequent command may play that source.
Future<void> openCurrentStream({
  required bool Function() isCurrent,
  required Future<void> Function() open,
  required Future<void> Function() stop,
  required Future<void> Function() onReady,
}) async {
  if (!isCurrent()) return;
  await open();
  if (!isCurrent()) {
    await stop();
    return;
  }
  await onReady();
}
