import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'audio_engine.dart';

/// [AudioEngine] backed by `just_audio`.
class JustAudioEngine implements AudioEngine {
  JustAudioEngine([AudioPlayer? player]) : _player = player ?? AudioPlayer() {
    _subs.add(_player.playerStateStream.listen((s) => _emit(_map(s))));
    // just_audio 0.10 reports native errors on errorStream and as an idle
    // playback event with an error code; its streams never carry errors.
    _subs.add(_player.errorStream.listen((_) => _emitError()));
    _subs.add(
      _player.playbackEventStream.listen((e) {
        if (e.processingState == ProcessingState.idle && e.errorCode != null) {
          _emitError();
        }
      }),
    );
  }

  final AudioPlayer _player;
  final _states = StreamController<EnginePlayerState>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  EnginePlayerState? _last;

  /// Whether the loaded source played yet: tells `paused` from `ready`.
  bool _wasPlaying = false;

  /// Counts [load] calls; one source failure is reported once, however many
  /// of just_audio's channels repeat it.
  int _generation = 0;
  int? _failedGeneration;

  @override
  Stream<EnginePlayerState> get states => _states.stream;

  @override
  Duration get position => _player.position;

  @override
  Future<void> load(String url) async {
    _wasPlaying = false;
    _generation++;
    try {
      await _player.setUrl(url);
    } catch (_) {
      _emitError();
      rethrow;
    }
  }

  @override
  Future<void> seek(Duration p) => _player.seek(p);

  @override
  Future<void> play() async {
    // Nothing loaded (e.g. the source failed): playing would stay silent.
    if (_player.processingState == ProcessingState.idle) {
      _emitError();
      return;
    }
    // just_audio's play() completes only when playback stops: do not wait.
    unawaited(_player.play().catchError((Object _) => _emitError()));
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
    await _states.close();
  }

  EnginePlayerState _map(PlayerState s) => switch (s.processingState) {
    ProcessingState.idle => EnginePlayerState.idle,
    ProcessingState.loading ||
    ProcessingState.buffering => EnginePlayerState.loading,
    ProcessingState.completed => EnginePlayerState.completed,
    ProcessingState.ready =>
      s.playing
          ? EnginePlayerState.playing
          : (_wasPlaying ? EnginePlayerState.paused : EnginePlayerState.ready),
  };

  /// Reports the current source's failure once: the controller recovers
  /// with a new [load], so a repeated error would only disturb that.
  void _emitError() {
    if (_failedGeneration == _generation) return;
    _failedGeneration = _generation;
    _emit(EnginePlayerState.error);
  }

  /// Emits only changes (errors excepted): just_audio repeats states (e.g. on
  /// pause after the end), and the controller acts on each one.
  void _emit(EnginePlayerState state) {
    if (_states.isClosed) return;
    if (state == _last && state != EnginePlayerState.error) return;
    if (state == EnginePlayerState.playing) _wasPlaying = true;
    _last = state;
    _states.add(state);
  }
}
