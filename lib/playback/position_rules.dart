import '../storytel/models.dart';

/// Local position saved per book. [remoteSeen] is the last remote position
/// this app saw or wrote, used to tell whether another device moved it.
class StoredPosition {
  const StoredPosition({
    required this.positionMs,
    required this.updatedAt,
    this.remoteSeen,
  });

  final int positionMs;
  final DateTime updatedAt;
  final int? remoteSeen;

  Map<String, dynamic> toJson() => {
        'positionMs': positionMs,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (remoteSeen != null) 'remoteSeen': remoteSeen,
      };

  factory StoredPosition.fromJson(Map<String, dynamic> json) {
    final pos = json['positionMs'];
    final seen = json['remoteSeen'];
    final at = json['updatedAt'];
    return StoredPosition(
      positionMs: pos is num ? pos.toInt() : 0,
      updatedAt: (at is String ? DateTime.tryParse(at) : null) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      remoteSeen: seen is num ? seen.toInt() : null,
    );
  }
}

/// The record written locally; always carries the known [remoteSeen].
StoredPosition storedPosition(int positionMs, int? remoteSeen, {DateTime? now}) =>
    StoredPosition(
      positionMs: positionMs,
      updatedAt: now ?? DateTime.now(),
      remoteSeen: remoteSeen,
    );

/// The stored record after a remote write of [writtenMs] succeeded: only
/// `remoteSeen` changes; a newer local position is kept.
StoredPosition withRemoteSeen(StoredPosition? stored, int writtenMs,
    {DateTime? now}) {
  if (stored == null) return storedPosition(writtenMs, writtenMs, now: now);
  return StoredPosition(
    positionMs: stored.positionMs,
    updatedAt: stored.updatedAt,
    remoteSeen: writtenMs,
  );
}

/// Position a book opens at (`follow` policy): the remote one wins only when
/// another device moved it and it differs from local by more than
/// [thresholdMs]. Without `remoteSeen`, the remote must be newer than local.
int resolveStartPosition(StoredPosition? local, RemotePosition? remote,
    {int thresholdMs = 30000}) {
  if (local == null) return remote?.positionMs ?? 0;
  if (remote == null) return local.positionMs;
  if (remote.positionMs == local.remoteSeen) return local.positionMs;
  if ((local.positionMs - remote.positionMs).abs() <= thresholdMs) {
    return local.positionMs;
  }
  if (local.remoteSeen == null) {
    final t = remote.updatedTime;
    if (t == null || !t.isAfter(local.updatedAt)) return local.positionMs;
  }
  return remote.positionMs;
}

/// Whether a position is worth sending: only one this app moved since the
/// last sync.
bool shouldWriteRemote(int positionMs, int? remoteSeen,
    {int toleranceMs = 1000}) {
  if (remoteSeen == null) return true;
  return (positionMs - remoteSeen).abs() > toleranceMs;
}

/// Whether the remote now holds a position other than [ifRemoteAt].
bool remoteMovedSince(int? currentMs, int? ifRemoteAt,
    {int toleranceMs = 1000}) {
  if (ifRemoteAt == null || currentMs == null) return false;
  return (currentMs - ifRemoteAt).abs() > toleranceMs;
}

/// Whether resuming asks the remote for its position again.
bool shouldRecheckRemote({
  required bool awaitingStart,
  required DateTime? lastCheckAt,
  required DateTime now,
  Duration minInterval = const Duration(seconds: 10),
}) {
  if (awaitingStart) return false;
  return lastCheckAt == null || now.difference(lastCheckAt) >= minInterval;
}
