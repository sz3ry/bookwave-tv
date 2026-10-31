import 'package:bookwave_tv/playback/position_rules.dart';
import 'package:bookwave_tv/storytel/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);
  StoredPosition local(int ms, {int? seen}) =>
      StoredPosition(positionMs: ms, updatedAt: t0, remoteSeen: seen);

  group('resolveStartPosition', () {
    test('no local uses remote or 0', () {
      expect(resolveStartPosition(null, RemotePosition(4000, null)), 4000);
      expect(resolveStartPosition(null, null), 0);
    });
    test('remote null keeps local', () {
      expect(resolveStartPosition(local(9000), null), 9000);
    });
    test('remote equal to remoteSeen keeps local', () {
      expect(resolveStartPosition(local(100000, seen: 500000), RemotePosition(500000, null)), 100000);
    });
    test('within threshold keeps local', () {
      expect(resolveStartPosition(local(100000, seen: 1), RemotePosition(130000, null)), 100000);
    });
    test('follow when another device moved it', () {
      expect(resolveStartPosition(local(100000, seen: 100000), RemotePosition(500000, null)), 500000);
    });
    test('no remoteSeen: newer remote wins, older loses', () {
      expect(resolveStartPosition(local(100000), RemotePosition(500000, t0.add(const Duration(minutes: 1)))), 500000);
      expect(resolveStartPosition(local(100000), RemotePosition(500000, t0.subtract(const Duration(minutes: 1)))), 100000);
      expect(resolveStartPosition(local(100000), RemotePosition(500000, null)), 100000);
    });
  });

  test('shouldWriteRemote', () {
    expect(shouldWriteRemote(1500, 1000), false);
    expect(shouldWriteRemote(2001, 1000), true);
    expect(shouldWriteRemote(0, null), true);
  });

  test('remoteMovedSince', () {
    expect(remoteMovedSince(5000, 1000), true);
    expect(remoteMovedSince(1500, 1000), false);
    expect(remoteMovedSince(null, 1000), false);
    expect(remoteMovedSince(5000, null), false);
  });

  test('withRemoteSeen', () {
    final a = withRemoteSeen(null, 7000, now: t0);
    expect(a.positionMs, 7000);
    expect(a.remoteSeen, 7000);
    final b = withRemoteSeen(local(9000), 7000);
    expect(b.positionMs, 9000);
    expect(b.remoteSeen, 7000);
  });

  test('storedPosition and json round trip', () {
    final s = storedPosition(5, null, now: t0);
    expect(s.toJson().containsKey('remoteSeen'), false);
    final r = StoredPosition.fromJson(storedPosition(5, 3, now: t0).toJson());
    expect(r.positionMs, 5);
    expect(r.remoteSeen, 3);
    expect(r.updatedAt, t0);
    expect(StoredPosition.fromJson({'positionMs': 1}).remoteSeen, isNull);
  });

  test('shouldRecheckRemote', () {
    final now = DateTime.utc(2026, 1, 1, 12, 1);
    expect(shouldRecheckRemote(awaitingStart: true, lastCheckAt: null, now: now), false);
    expect(shouldRecheckRemote(awaitingStart: false, lastCheckAt: null, now: now), true);
    expect(shouldRecheckRemote(awaitingStart: false, lastCheckAt: now.subtract(const Duration(seconds: 5)), now: now), false);
    expect(shouldRecheckRemote(awaitingStart: false, lastCheckAt: now.subtract(const Duration(seconds: 10)), now: now), true);
  });
}
