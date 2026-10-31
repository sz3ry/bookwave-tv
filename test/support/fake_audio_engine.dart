import 'dart:async';

import 'package:bookwave_tv/playback/audio_engine.dart';

class FakeAudioEngine implements AudioEngine {
  final loads = <String>[];
  final seeks = <Duration>[];
  int plays = 0;
  int pauses = 0;
  bool failNextPlay = false;
  bool idleNextPlay = false;
  final _states = StreamController<EnginePlayerState>.broadcast();

  @override
  Duration position = Duration.zero;

  void emit(EnginePlayerState s) => _states.add(s);

  @override
  Stream<EnginePlayerState> get states => _states.stream;

  @override
  Future<void> load(String url) async {
    loads.add(url);
    position = Duration.zero;
    emit(EnginePlayerState.ready);
  }

  @override
  Future<void> seek(Duration p) async {
    seeks.add(p);
    position = p;
  }

  @override
  Future<void> play() async {
    plays++;
    if (failNextPlay) {
      failNextPlay = false;
      emit(EnginePlayerState.error);
      return;
    }
    if (idleNextPlay) {
      idleNextPlay = false;
      emit(EnginePlayerState.idle);
      return;
    }
    emit(EnginePlayerState.playing);
  }

  @override
  Future<void> pause() async {
    pauses++;
    emit(EnginePlayerState.paused);
  }

  @override
  Future<void> dispose() => _states.close();
}
