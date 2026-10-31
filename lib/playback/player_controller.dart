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
    this.onAuthFailure,
  }) : _clock = clock ?? DateTime.now {
    _stateSub = _engine.states.listen(_onEngineState);
  }

  static const _tickInterval = Duration(seconds: 15);

  final AudioEngine _engine;
  final StorytelClient _client;
  final LocalStore _store;
  final DateTime Function() _clock;

  /// Called when Storytel rejects the session during a background call.
  final void Function()? onAuthFailure;

  late final StreamSubscription<EnginePlayerState> _stateSub;
  Timer? _ticker;
  bool _tickRunning = false;

  /// Serialises remote work (guarded reads, writes, `remoteSeen` updates);
  /// local saves never wait on it.
  Future<void> _chain = Future.value();

  _Session? _s;
  bool _isPlaying = false;

  ShelfBook? get book => _s?.book;
  bool get isPlaying => _isPlaying;
  bool get isFinished => _s?.finished ?? false;
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
    final remote = await _readRemote(s.id);
    if (!identical(s, _s)) return;
    s.lastRemoteCheckAt = _clock();
    s.remoteSeen = remote?.positionMs ?? local?.remoteSeen;
    final start = resolveStartPosition(local, remote);
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

  /// Book switch or app teardown: pauses, saves locally and writes the remote
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
    await _serial(() async {
      if (!shouldWriteRemote(pos, s.remoteSeen)) return;
      final current = await _readRemote(s.id);
      if (!remoteMovedSince(current?.positionMs, s.remoteSeen)) {
        await _writeRemote(s, pos);
      }
    });
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
    final remote = await _readRemote(s.id);
    if (remote == null || !identical(s, _s)) return current;
    final target = resolveStartPosition(
      storedPosition(current, s.remoteSeen, now: now),
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
    final s = _s;
    if (s == null || !s.startApplied) return;
    switch (state) {
      case EnginePlayerState.playing:
        s.playRequested = false;
        _isPlaying = true;
        _startTicker();
      case EnginePlayerState.paused:
        _isPlaying = false;
        _stopTicker();
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
        // A play request that ends idle never started.
        if (s.playRequested) _onPlaybackFailure(s);
      case EnginePlayerState.loading:
      case EnginePlayerState.ready:
        break;
    }
    notifyListeners();
  }

  void _onPlaybackFailure(_Session s) {
    s.playRequested = false;
    s.positionTrusted = false;
    _stopTicker();
    if (s.recovering) return;
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
      if (e is StorytelAuthException) onAuthFailure?.call();
      debugPrint('Stream recovery failed: ${e.runtimeType}');
      if (identical(s, _s)) {
        s.positionTrusted = false;
        s.wantsPlay = false;
        _isPlaying = false;
        notifyListeners();
      }
    } finally {
      s.recovering = false;
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

  /// Saves locally at once, then (queued behind earlier remote work) writes
  /// the remote when the position moved.
  Future<void> _saveAndSync(_Session s, int pos) async {
    await _saveLocal(s, pos);
    await _serial(() async {
      if (shouldWriteRemote(pos, s.remoteSeen)) await _writeRemote(s, pos);
    });
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

  Future<RemotePosition?> _readRemote(String id) async {
    try {
      return await _client.readPosition(id);
    } catch (e) {
      _reportRemoteFailure('read', e);
      return null;
    }
  }

  void _reportRemoteFailure(String op, Object e) {
    if (e is StorytelAuthException) onAuthFailure?.call();
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
