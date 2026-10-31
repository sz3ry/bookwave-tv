import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'audio_engine.dart';

/// [AudioEngine] backed by `just_audio`.
class JustAudioEngine implements AudioEngine {
  JustAudioEngine([AudioPlayer? player]) : _player = player ?? AudioPlayer() {
    _subs.add(
      _player.playerStateStream.listen(
        (s) => _emit(_map(s)),
        onError: (Object _) => _emit(EnginePlayerState.error),
      ),
    );
    _subs.add(
      _player.playbackEventStream.listen(
        (_) {},
        onError: (Object _) => _emit(EnginePlayerState.error),
      ),
    );
  }

  final AudioPlayer _player;
  final _states = StreamController<EnginePlayerState>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  EnginePlayerState? _last;

  /// Whether the loaded source played yet: tells `paused` from `ready`.
  bool _wasPlaying = false;

  @override
  Stream<EnginePlayerState> get states => _states.stream;

  @override
  Duration get position => _player.position;

  @override
  Future<void> load(String url) async {
    _wasPlaying = false;
    try {
      await _player.setUrl(url);
    } catch (_) {
      _emit(EnginePlayerState.error);
      rethrow;
    }
  }

  @override
  Future<void> seek(Duration p) => _player.seek(p);

  @override
  Future<void> play() async {
    // just_audio's play() completes only when playback stops: do not wait.
    unawaited(
      _player.play().catchError((Object _) => _emit(EnginePlayerState.error)),
    );
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

  /// Emits only changes: just_audio repeats states (e.g. on pause after the
  /// end), and the controller acts on each one.
  void _emit(EnginePlayerState state) {
    if (state == _last || _states.isClosed) return;
    if (state == EnginePlayerState.playing) _wasPlaying = true;
    _last = state;
    _states.add(state);
  }
}
