import 'package:audio_service/audio_service.dart';

import 'player_controller.dart';

/// Publishes the controller's book and state to the Android media session,
/// and routes media buttons (play, pause, stop) back to the controller.
class MediaSessionHandler extends BaseAudioHandler {
  MediaSessionHandler(this._controller) {
    _controller.addListener(_publish);
    _publish();
  }

  final PlayerController _controller;

  @override
  Future<void> play() async {
    if (!_controller.isPlaying) await _controller.togglePlayPause();
  }

  @override
  Future<void> pause() async {
    if (_controller.isPlaying) await _controller.togglePlayPause();
  }

  @override
  Future<void> stop() async {
    // Keep the chosen book when the system stops the session (for example a
    // dismissed notification); only app detach clears it.
    await pause();
    await super.stop();
  }

  void _publish() {
    final book = _controller.book;
    final item = book == null
        ? null
        : MediaItem(
            id: book.consumableId,
            title: book.title,
            artist: book.authors,
            duration: _controller.duration,
            artUri: book.coverUrl == null ? null : Uri.tryParse(book.coverUrl!),
          );
    if (item?.id != mediaItem.value?.id) mediaItem.add(item);

    final playing = _controller.isPlaying;
    playbackState.add(
      PlaybackState(
        controls: [playing ? MediaControl.pause : MediaControl.play],
        androidCompactActionIndices: const [0],
        systemActions: const {MediaAction.playPause},
        processingState: book == null
            ? AudioProcessingState.idle
            : _controller.isFinished
            ? AudioProcessingState.completed
            : AudioProcessingState.ready,
        playing: playing,
        updatePosition: _controller.position,
      ),
    );
  }
}
