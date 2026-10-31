/// Playback state reported by an [AudioEngine].
enum EnginePlayerState {
  idle,
  loading,
  ready,
  playing,
  paused,
  completed,
  error,
}

/// The audio player the [PlayerController] drives; a seam for tests.
abstract class AudioEngine {
  /// Loads [url] without playing it.
  Future<void> load(String url);

  Future<void> seek(Duration p);

  /// Starts playback and returns without waiting for it to end; a failure is
  /// reported as [EnginePlayerState.error] on [states].
  Future<void> play();

  Future<void> pause();

  Duration get position;

  Stream<EnginePlayerState> get states;

  Future<void> dispose();
}
