import 'dart:async';

import 'package:flutter/foundation.dart';

import '../storage/local_store.dart';
import '../storytel/models.dart';
import '../storytel/storytel_client.dart';
import '../storytel/storytel_http.dart';
import 'audio_engine.dart';
import 'position_rules.dart';

/// State of one opened book. Every async continuation holds its session and
/// drops its work once the session is no longer the current one.
class _Session {
  _Session(this.book);

  final ShelfBook book;
  String get id => book.consumableId;

  bool startApplied = false;

  /// The engine sits at a position this controller applied; false after a
  /// stream error, when the engine may report 0.
  bool positionTrusted = false;
  bool finished = false;
  bool wantsPlay = false;
  bool playRequested = false;
  bool recovering = false;
  bool recoveryUsed = false;
  int? remoteSeen;

  /// The remote could not be read on open and no remote position was ever
  /// seen: nothing is written remotely until a read succeeds. [startBase] is
  /// where the book started (shelf or local position), the stand-in for
  /// `remoteSeen` when that read decides whether another device moved it.
  bool remoteUnknown = false;
  int? startBase;

  /// Remote sync waiting in the queue: its newest target position, and
  /// whether it must re-read the remote first (paused-book write guard).
  bool remoteQueued = false;
  int? remoteTargetMs;
  bool remoteGuarded = false;

  /// Last good position: applied start, seek target or saved value.
  int lastKnownMs = 0;
  DateTime? lastRemoteCheckAt;
}

/// Plays one Storytel book at a time and keeps its position in sync.
///
/// The local position is always saved before any remote call. No position
/// is written before the start position was applied, and none is read from
/// the engine while it is not at a position this controller applied.
class PlayerController extends ChangeNotifier {
  PlayerController({
    required this._engine,
    required this._client,
    required this._store,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _stateSub = _engine.states.listen(_onEngineState);
  }

  static const _tickInterval = Duration(seconds: 15);

  final AudioEngine _engine;
  final StorytelClient _client;
  final LocalStore _store;
  final DateTime Function() _clock;

  late final StreamSubscription<EnginePlayerState> _stateSub;
  Timer? _ticker;
  bool _tickRunning = false;

  /// Serialises remote work (guarded reads, writes, `remoteSeen` updates);
  /// nothing the user or the ticker does waits on it.
  Future<void> _chain = Future.value();

  _Session? _s;
  bool _isPlaying = false;

  /// The engine last reported `playing`: tells a pause the system caused
  /// (audio focus loss) from the brief pauses around a seek or load.
  bool _enginePlaying = false;

  ShelfBook? get book => _s?.book;
  bool get isPlaying => _isPlaying;
  bool get isFinished => _s?.finished ?? false;

  /// The book's start position is applied and no stream recovery runs: OK
  /// acts at once. False while a book opens or its stream reloads.
  bool get isReady {
    final s = _s;
    return s != null && s.startApplied && !s.recovering;
  }

  Duration get duration => Duration(milliseconds: _s?.book.durationMs ?? 0);
  Duration get position {
    final s = _s;
    if (s == null || !s.startApplied) return Duration.zero;
    return Duration(milliseconds: _posMs(s));
  }

  /// Stops the current book, then loads [book] at its resolved start
  /// position without playing it.
  Future<void> open(ShelfBook book) async {
    await stop();
    final s = _s = _Session(book);
    notifyListeners();
    await _store.setLastBook(book);
    final local = _store.position(s.id);
    final read = await _readRemote(s.id);
    if (!identical(s, _s)) return;
    final remote = read.position;
    // A failed read is retried on the first play.
    if (read.ok) s.lastRemoteCheckAt = _clock();
    s.remoteSeen = remote?.positionMs ?? local?.remoteSeen;
    s.remoteUnknown = !read.ok && s.remoteSeen == null;
    // Without a local position and a readable remote, the shelf's copy of
    // the remote position beats starting over from 0.
    final start = !read.ok && local == null
        ? (book.positionMs ?? 0)
        : resolveStartPosition(local, remote);
    if (s.remoteUnknown) s.startBase = start;
    final url = await _client.streamUrl(s.id);
    if (!identical(s, _s)) return;
    await _engine.load(url);
    if (!identical(s, _s)) return;
    await _engine.seek(Duration(milliseconds: start));
    s.lastKnownMs = start;
    s.positionTrusted = true;
    s.startApplied = true;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    final s = _s;
    if (s == null || !s.startApplied) return;
    if (_isPlaying) return _pause(s);
    s.wantsPlay = true;
    _isPlaying = true;
    notifyListeners();
    if (s.recovering) return; // the running recovery plays
    s.recoveryUsed = false;
    final int target;
    if (s.finished) {
      s.finished = false;
      target = 0;
    } else {
      target = await _recheckRemote(s);
      if (!identical(s, _s)) return;
    }
    s.lastKnownMs = target;
    if (!s.positionTrusted) {
      if (!s.wantsPlay) return;
      s.recoveryUsed = true;
      return _reload(s, target);
    }
    if (target != _engine.position.inMilliseconds) {
      await _engine.seek(Duration(milliseconds: target));
    }
    if (!identical(s, _s) || !s.wantsPlay) return;
    s.playRequested = true;
    await _engine.play();
  }

  /// App teardown: saves locally and writes the remote position unless
  /// another device moved it, without pausing or dropping the book (the
  /// engine may outlive the activity and keep playing).
  Future<void> flush() async {
    final s = _s;
    if (s == null || !s.startApplied) return;
    final pos = _posMs(s);
    await _saveLocal(s, pos);
    _queueRemote(s, pos, guarded: true);
  }

  /// Book switch or logout: pauses, saves locally and writes the remote
  /// position unless another device moved it since this app last saw it.
  Future<void> stop() async {
    final s = _s;
    if (s == null) return;
    _s = null;
    _stopTicker();
    _isPlaying = false;
    s.wantsPlay = false;
    notifyListeners();
    if (!s.startApplied) return;
    final pos = _posMs(s);
    await _engine.pause();
    await _saveLocal(s, pos);
    _queueRemote(s, pos, guarded: true);
  }

  Future<void> _pause(_Session s) async {
    _isPlaying = false;
    s.wantsPlay = false;
    _stopTicker();
    notifyListeners();
    final pos = _posMs(s);
    await _engine.pause();
    await _saveAndSync(s, pos);
  }

  /// On resume, returns where to continue: the remote position when another
  /// device moved it (rechecked at most every 10 s), else the current one.
  Future<int> _recheckRemote(_Session s) async {
    final now = _clock();
    final current = _posMs(s);
    final recheck = shouldRecheckRemote(
      awaitingStart: false,
      lastCheckAt: s.lastRemoteCheckAt,
      now: now,
    );
    if (!recheck) return current;
    s.lastRemoteCheckAt = now;
    final read = await _readRemote(s.id);
    if (!read.ok || !identical(s, _s)) return current;
    final remote = read.position;
    final seen = s.remoteUnknown ? s.startBase : s.remoteSeen;
    s.remoteUnknown = false;
    if (remote == null) return current;
    final target = resolveStartPosition(
      storedPosition(current, seen, now: now),
      remote,
    );
    s.remoteSeen = remote.positionMs;
    await _store.setPosition(
      s.id,
      storedPosition(target, s.remoteSeen, now: now),
    );
    return target;
  }

  void _onEngineState(EnginePlayerState state) {
    final wasEnginePlaying = _enginePlaying;
    if (state != EnginePlayerState.loading &&
        state != EnginePlayerState.ready) {
      _enginePlaying = state == EnginePlayerState.playing;
    }
    final s = _s;
    if (s == null || !s.startApplied) return;
    switch (state) {
      case EnginePlayerState.playing:
        s.playRequested = false;
        _isPlaying = true;
        _startTicker();
      case EnginePlayerState.paused:
        // Paused by the system, not by this controller: keep the place like
        // a pause the child made.
        final unsolicited = wasEnginePlaying && _isPlaying && s.wantsPlay;
        _isPlaying = false;
        _stopTicker();
        if (unsolicited) {
          s.wantsPlay = false;
          _guard(_saveAndSync(s, _posMs(s)));
        }
      case EnginePlayerState.completed:
        _isPlaying = false;
        s.finished = true;
        s.wantsPlay = false;
        _stopTicker();
        final pos = _posMs(s);
        _guard(_engine.pause());
        _guard(_saveAndSync(s, pos));
      case EnginePlayerState.error:
        _onPlaybackFailure(s);
      case EnginePlayerState.idle:
        // A play request that ends idle never started; idle while playing is
        // a stream that broke (just_audio keeps `playing` set after an error).
        if (s.playRequested || (_isPlaying && !s.recovering)) {
          _onPlaybackFailure(s);
        }
      case EnginePlayerState.loading:
      case EnginePlayerState.ready:
        break;
    }
    notifyListeners();
  }

  void _onPlaybackFailure(_Session s) {
    // The running recovery loads a new source: a repeated report of the old
    // failure must not mark the recovered stream untrusted.
    if (s.recovering) return;
    // The engine usually keeps its position after an error; it is newer than
    // the last save unless the engine already dropped to 0.
    if (s.positionTrusted) {
      final retained = _engine.position.inMilliseconds;
      if (retained > 0) s.lastKnownMs = retained;
    }
    s.playRequested = false;
    s.positionTrusted = false;
    _stopTicker();
    if (s.wantsPlay && !s.recoveryUsed) {
      s.recoveryUsed = true;
      _guard(_reload(s, s.lastKnownMs));
    } else {
      s.wantsPlay = false;
      _isPlaying = false;
    }
  }

  /// The signed stream URL expired or the stream broke: resolve it again,
  /// return to [targetMs] and play, unless paused or stopped meanwhile.
  Future<void> _reload(_Session s, int targetMs) async {
    s.recovering = true;
    notifyListeners();
    try {
      final url = await _client.streamUrl(s.id);
      if (!identical(s, _s)) return;
      await _engine.load(url);
      if (!identical(s, _s)) return;
      await _engine.seek(Duration(milliseconds: targetMs));
      s.lastKnownMs = targetMs;
      s.positionTrusted = true;
      if (!identical(s, _s) || !s.wantsPlay) return;
      s.recovering = false;
      s.playRequested = true;
      await _engine.play();
    } catch (e) {
      // A rejected login is the client's call (`onCredentialsRejected`); a
      // stray 401 after a good re-login must not log the parent out.
      debugPrint('Stream recovery failed: ${e.runtimeType}');
      if (identical(s, _s)) {
        s.positionTrusted = false;
        s.wantsPlay = false;
        _isPlaying = false;
        notifyListeners();
      }
    } finally {
      if (s.recovering) {
        s.recovering = false;
        if (identical(s, _s)) notifyListeners();
      }
    }
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(_tickInterval, (_) => _guard(_tick()));
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _tick() async {
    final s = _s;
    if (s == null || !s.positionTrusted || !_isPlaying || _tickRunning) return;
    _tickRunning = true;
    try {
      final pos = _posMs(s);
      await _saveAndSync(s, pos);
      s.recoveryUsed = false;
    } finally {
      _tickRunning = false;
    }
  }

  int _posMs(_Session s) =>
      s.positionTrusted ? _engine.position.inMilliseconds : s.lastKnownMs;

  /// Saves locally, then queues the remote write without waiting on it.
  Future<void> _saveAndSync(_Session s, int pos) async {
    await _saveLocal(s, pos);
    _queueRemote(s, pos);
  }

  /// Queues a remote write of [pos] behind earlier remote work. At most one
  /// job per session waits in the queue; a newer call only moves its target.
  void _queueRemote(_Session s, int pos, {bool guarded = false}) {
    s.remoteTargetMs = pos;
    s.remoteGuarded = s.remoteGuarded || guarded;
    if (s.remoteQueued) return;
    s.remoteQueued = true;
    _guard(
      _serial(() async {
        s.remoteQueued = false;
        final target = s.remoteTargetMs!;
        final guard = s.remoteGuarded;
        s.remoteGuarded = false;
        if (s.remoteUnknown) return _syncUnknownRemote(s, target);
        if (!shouldWriteRemote(target, s.remoteSeen)) return;
        if (guard) {
          final current = await _readRemote(s.id);
          if (remoteMovedSince(current.position?.positionMs, s.remoteSeen)) {
            return;
          }
        }
        await _writeRemote(s, target);
      }),
    );
  }

  /// The remote position is still unknown: read it first and write [target]
  /// only once that worked. When another device moved the book away from
  /// where it started here, follow it instead of overwriting it.
  Future<void> _syncUnknownRemote(_Session s, int target) async {
    final read = await _readRemote(s.id);
    // A recovery picks its own target: decide on the next sync instead.
    if (!read.ok || !s.remoteUnknown || s.recovering) return;
    final now = _clock();
    final remote = read.position;
    s.remoteUnknown = false;
    s.remoteSeen = remote?.positionMs;
    s.lastRemoteCheckAt = now;
    final resolved = resolveStartPosition(
      storedPosition(target, s.startBase, now: now),
      remote,
    );
    if (resolved != target) {
      s.lastKnownMs = resolved;
      await _store.setPosition(
        s.id,
        storedPosition(resolved, s.remoteSeen, now: now),
      );
      if (identical(s, _s) && s.positionTrusted) {
        await _engine.seek(Duration(milliseconds: resolved));
        notifyListeners();
      }
      return;
    }
    if (shouldWriteRemote(target, s.remoteSeen)) await _writeRemote(s, target);
  }

  Future<void> _saveLocal(_Session s, int pos) async {
    s.lastKnownMs = pos;
    await _store.setPosition(
      s.id,
      storedPosition(pos, s.remoteSeen, now: _clock()),
    );
  }

  Future<void> _writeRemote(_Session s, int positionMs) async {
    try {
      await _client.writePosition(s.id, positionMs, _store.deviceId());
    } catch (e) {
      _reportRemoteFailure('write', e);
      return;
    }
    s.remoteSeen = positionMs;
    await _store.setPosition(
      s.id,
      withRemoteSeen(_store.position(s.id), positionMs),
    );
  }

  /// `ok` is false when the read failed; a null position with `ok` means
  /// the remote holds no position for the book.
  Future<({bool ok, RemotePosition? position})> _readRemote(String id) async {
    try {
      return (ok: true, position: await _client.readPosition(id));
    } catch (e) {
      _reportRemoteFailure('read', e);
      return (ok: false, position: null);
    }
  }

  void _reportRemoteFailure(String op, Object e) {
    // Only the type and status: messages may carry URLs or tokens.
    debugPrint(
      'Remote position $op failed: '
      '${e is StorytelHttpException ? e : e.runtimeType}',
    );
  }

  Future<void> _serial(Future<void> Function() task) {
    final next = _chain.then((_) => task());
    _chain = next.catchError((Object _) {});
    return next;
  }

  void _guard(Future<void> f) {
    unawaited(
      f.catchError(
        (Object e) => debugPrint('Playback task failed: ${e.runtimeType}'),
      ),
    );
  }

  @override
  void dispose() {
    _s = null;
    _stopTicker();
    _stateSub.cancel();
    super.dispose();
  }
}
