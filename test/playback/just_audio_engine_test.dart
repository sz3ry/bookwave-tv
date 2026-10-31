import 'dart:async';

import 'package:bookwave_tv/playback/audio_engine.dart';
import 'package:bookwave_tv/playback/just_audio_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

/// Stands in for just_audio's player: only the streams and calls the engine
/// uses. In just_audio 0.10 errors arrive on [errorStream] and as playback
/// events carrying an error code, never as stream errors.
class FakeAudioPlayer implements AudioPlayer {
  final playerStates = StreamController<PlayerState>.broadcast();
  final events = StreamController<PlaybackEvent>.broadcast();
  final errors = StreamController<PlayerException>.broadcast();

  @override
  ProcessingState processingState = ProcessingState.ready;

  @override
  Stream<PlayerState> get playerStateStream => playerStates.stream;

  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;

  @override
  Stream<PlayerException> get errorStream => errors.stream;

  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeAudioPlayer player;
  late JustAudioEngine engine;
  late List<EnginePlayerState> states;

  setUp(() {
    player = FakeAudioPlayer();
    engine = JustAudioEngine(player);
    states = [];
    engine.states.listen(states.add);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('an error on errorStream is reported', () async {
    await engine.load('https://cdn.example/1.mp3');
    player.playerStates.add(PlayerState(true, ProcessingState.ready));
    await settle();
    player.errors.add(PlayerException(2001, 'source error', 0));
    await settle();
    expect(states, [EnginePlayerState.playing, EnginePlayerState.error]);
  });

  test('an idle playback event with an error code is reported', () async {
    await engine.load('https://cdn.example/1.mp3');
    player.events.add(
      PlaybackEvent(processingState: ProcessingState.idle, errorCode: 2001),
    );
    await settle();
    expect(states, contains(EnginePlayerState.error));
  });

  test('one error per loaded source', () async {
    await engine.load('https://cdn.example/1.mp3');
    player.errors.add(PlayerException(2001, 'source error', 0));
    player.events.add(
      PlaybackEvent(processingState: ProcessingState.idle, errorCode: 2001),
    );
    player.errors.add(PlayerException(2001, 'source error', 0));
    await settle();
    expect(states.where((s) => s == EnginePlayerState.error), hasLength(1));
    // A new source may fail again.
    await engine.load('https://cdn.example/2.mp3');
    player.errors.add(PlayerException(2001, 'source error', 0));
    await settle();
    expect(states.where((s) => s == EnginePlayerState.error), hasLength(2));
  });
}
