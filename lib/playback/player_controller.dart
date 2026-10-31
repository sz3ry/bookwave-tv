import 'dart:async';

import 'package:flutter/foundation.dart';

import '../storage/local_store.dart';
import '../storytel/models.dart';
import '../storytel/storytel_client.dart';
import '../storytel/storytel_http.dart';
import 'audio_engine.dart';
import 'position_rules.dart';

/// Plays one Storytel book at a time and keeps its position in sync.
///
/// The local position is always saved before any remote call, and no
/// position is written before the start position was applied in [open].
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

  /// Called when Storytel rejects the session during a background sync.
  final void Function()? onAuthFailure;

  late final StreamSubscription<EnginePlayerState> _stateSub;
  Timer? _ticker;
  bool _tickRunning = false;

  ShelfBook? _book;
  bool _isPlaying = false;
  bool _isFinished = false;
  bool _startApplied = false;
  int? _remoteSeen;
  DateTime? _lastRemoteCheckAt;

  /// Last position known to be good (applied start, seek or saved value);
  /// the engine may report 0 after a stream error.
  int _lastKnownMs = 0;

  /// Whether the one stream re-resolve per play attempt was used.
  bool _recoveryUsed = false;

  ShelfBook? get book => _book;
  bool get isPlaying => _isPlaying;
  bool get isFinished => _isFinished;
  Duration get position => _startApplied ? _engine.position : Duration.zero;
  Duration get duration => Duration(milliseconds: _book?.durationMs ?? 0);

  /// Stops the current book, then loads [book] at its resolved start
  /// position without playing it.
  Future<void> open(ShelfBook book) async {
    await stop();
    _book = book;
    _isFinished = false;
    notifyListeners();
    await _store.setLastBook(book);
    final id = book.consumableId;
    final local = _store.position(id);
    final remote = await _readRemote(id);
    _lastRemoteCheckAt = _clock();
    _remoteSeen = remote?.positionMs ?? local?.remoteSeen;
    final start = resolveStartPosition(local, remote);
    await _engine.load(await _client.streamUrl(id));
    await _engine.seek(Duration(milliseconds: start));
    _lastKnownMs = start;
    _startApplied = true;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_book == null || !_startApplied) return;
    if (_isPlaying) return _pause();
    _recoveryUsed = false;
    if (_isFinished) {
      _isFinished = false;
      await _engine.seek(Duration.zero);
      _lastKnownMs = 0;
    } else {
      await _recheckRemote();
    }
    _isPlaying = true;
    notifyListeners();
    await _engine.play();
  }

  /// Book switch or app teardown: pauses, saves locally and writes the remote
  /// position unless another device moved it since this app last saw it.
  Future<void> stop() async {
    final book = _book;
    if (book == null) return;
    _stopTicker();
    final applied = _startApplied;
    _startApplied = false;
    _isPlaying = false;
    if (applied) {
      await _engine.pause();
      final pos = await _saveLocal(book.consumableId);
      if (shouldWriteRemote(pos, _remoteSeen)) {
        final current = await _readRemote(book.consumableId);
        if (!remoteMovedSince(current?.positionMs, _remoteSeen)) {
          await _writeRemote(book.consumableId, pos);
        }
      }
    }
    _book = null;
    notifyListeners();
  }

  Future<void> _pause() async {
    final book = _book!;
    _isPlaying = false;
    _stopTicker();
    notifyListeners();
    await _engine.pause();
    await _saveAndSync(book.consumableId);
  }

  /// On resume, follows a remote position another device moved.
  Future<void> _recheckRemote() async {
    final now = _clock();
    final recheck = shouldRecheckRemote(
      awaitingStart: !_startApplied,
      lastCheckAt: _lastRemoteCheckAt,
      now: now,
    );
    if (!recheck) return;
    _lastRemoteCheckAt = now;
    final id = _book!.consumableId;
    final remote = await _readRemote(id);
    if (remote == null || _book?.consumableId != id) return;
    final currentMs = _engine.position.inMilliseconds;
    final target = resolveStartPosition(
      storedPosition(currentMs, _remoteSeen, now: now),
      remote,
    );
    _remoteSeen = remote.positionMs;
    await _store.setPosition(id, storedPosition(target, _remoteSeen, now: now));
    if (target != currentMs) {
      await _engine.seek(Duration(milliseconds: target));
    }
    _lastKnownMs = target;
  }

  void _onEngineState(EnginePlayerState state) {
    switch (state) {
      case EnginePlayerState.playing:
        _isPlaying = true;
        _startTicker();
      case EnginePlayerState.paused:
        _isPlaying = false;
        _stopTicker();
      case EnginePlayerState.completed:
        _isPlaying = false;
        _isFinished = true;
        _stopTicker();
        final book = _book;
        if (book != null && _startApplied) {
          unawaited(_engine.pause());
          unawaited(_saveAndSync(book.consumableId));
        }
      case EnginePlayerState.error:
        _stopTicker();
        if (_book != null && _startApplied && !_recoveryUsed) {
          _recoveryUsed = true;
          unawaited(_recover());
        } else {
          _isPlaying = false;
        }
      case EnginePlayerState.idle:
      case EnginePlayerState.loading:
      case EnginePlayerState.ready:
        break;
    }
    notifyListeners();
  }

  /// The signed stream URL expired or the stream broke: resolve it again,
  /// return to the last good position and play once more.
  Future<void> _recover() async {
    final id = _book!.consumableId;
    final savedMs = _lastKnownMs;
    try {
      final url = await _client.streamUrl(id);
      if (_book?.consumableId != id) return;
      await _engine.load(url);
      await _engine.seek(Duration(milliseconds: savedMs));
      await _engine.play();
    } catch (e) {
      if (e is StorytelAuthException) onAuthFailure?.call();
      debugPrint('Stream recovery failed: ${e.runtimeType}');
      _isPlaying = false;
      notifyListeners();
    }
  }

  void _startTicker() {
    if (!_startApplied) return;
    _ticker ??= Timer.periodic(_tickInterval, (_) => _tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _tick() async {
    final book = _book;
    if (book == null || !_startApplied || _tickRunning) return;
    _tickRunning = true;
    try {
      await _saveAndSync(book.consumableId);
      _recoveryUsed = false;
    } finally {
      _tickRunning = false;
    }
  }

  /// Saves locally, then writes the remote when the position moved.
  Future<void> _saveAndSync(String id) async {
    final pos = await _saveLocal(id);
    if (shouldWriteRemote(pos, _remoteSeen)) await _writeRemote(id, pos);
  }

  Future<int> _saveLocal(String id) async {
    final pos = _engine.position.inMilliseconds;
    _lastKnownMs = pos;
    await _store.setPosition(
      id,
      storedPosition(pos, _remoteSeen, now: _clock()),
    );
    return pos;
  }

  Future<void> _writeRemote(String id, int positionMs) async {
    try {
      await _client.writePosition(id, positionMs, _store.deviceId());
    } catch (e) {
      _reportRemoteFailure('write', e);
      return;
    }
    _remoteSeen = positionMs;
    await _store.setPosition(
      id,
      withRemoteSeen(_store.position(id), positionMs),
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

  @override
  void dispose() {
    _stopTicker();
    _stateSub.cancel();
    super.dispose();
  }
}
