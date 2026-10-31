import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/app_localizations.dart';
import '../playback/player_controller.dart';

/// `h:mm:ss`, e.g. 4360 s -> `1:12:40`.
String formatClock(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

Future<void> _defaultWakelock(bool enable) async {
  try {
    await WakelockPlus.toggle(enable: enable);
  } catch (_) {
    // The screen stays on best-effort; a platform failure must not crash.
  }
}

/// The start screen: cover, title, one big play/pause button and progress.
/// The remote has no play/pause key, so focus always returns to the button.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.controller,
    required this.onOpenLibrary,
    this.setWakelock = _defaultWakelock,
  });

  final PlayerController controller;
  final VoidCallback onOpenLibrary;
  final Future<void> Function(bool enable) setWakelock;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

final _toggleKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
  LogicalKeyboardKey.mediaPlayPause,
};

class _ToggleIntent extends Intent {
  const _ToggleIntent();
}

class _FocusPlayIntent extends Intent {
  const _FocusPlayIntent();
}

class _FocusLibraryIntent extends Intent {
  const _FocusLibraryIntent();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // Holding OK must toggle once per press, so key repeats are swallowed
  // before the activation shortcuts see them.
  final _playNode = FocusNode(
    debugLabel: 'play',
    onKeyEvent: (_, event) =>
        event is KeyRepeatEvent && _toggleKeys.contains(event.logicalKey)
        ? KeyEventResult.handled
        : KeyEventResult.ignored,
  );
  final _libraryNode = FocusNode(debugLabel: 'library');
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _wakelock(true);
    // The position moves without notifications, so redraw once a second.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.isPlaying) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _wakelock(false);
    _playNode.dispose();
    _libraryNode.dispose();
    super.dispose();
  }

  void _wakelock(bool enable) {
    try {
      widget.setWakelock(enable).catchError((Object _) {});
    } catch (_) {}
  }

  void _toggle() => widget.controller.togglePlayPause();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Shortcuts(
      shortcuts: const {
        SingleActivator(
          LogicalKeyboardKey.mediaPlayPause,
          includeRepeats: false,
        ): _ToggleIntent(),
      },
      child: Actions(
        actions: {
          _ToggleIntent: CallbackAction<_ToggleIntent>(
            onInvoke: (_) {
              _toggle();
              return null;
            },
          ),
        },
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final c = widget.controller;
            final book = c.book;
            final duration = c.duration;
            final position = c.position;
            final fraction = duration.inMilliseconds <= 0
                ? 0.0
                : (position.inMilliseconds / duration.inMilliseconds).clamp(
                    0.0,
                    1.0,
                  );
            return Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: _LibraryButton(
                        node: _libraryNode,
                        label: l10n.library,
                        onPressed: widget.onOpenLibrary,
                        onLeave: _playNode.requestFocus,
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            flex: 28,
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: _Cover(
                                  url: book?.coverUrl,
                                  title: book?.title ?? '',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                          Expanded(
                            flex: 72,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  book?.title ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  book?.authors ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 32),
                                Row(
                                  children: [
                                    _PlayButton(
                                      node: _playNode,
                                      playing: c.isPlaying,
                                      label: c.isPlaying
                                          ? l10n.pause
                                          : l10n.play,
                                      onPressed: _toggle,
                                      onUp: _libraryNode.requestFocus,
                                    ),
                                    if (c.isFinished) ...[
                                      const SizedBox(width: 24),
                                      Flexible(
                                        child: Text(
                                          l10n.finished,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineSmall,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 32),
                                LinearProgressIndicator(
                                  value: fraction,
                                  minHeight: 8,
                                  color: Colors.orange,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '${formatClock(position)} / '
                                  '${formatClock(duration)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.title});

  final String? url;
  final String title;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: Colors.grey.shade900,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Text(title, textAlign: TextAlign.center),
    );
    final u = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: u == null || u.isEmpty
          ? fallback
          : Image.network(
              u,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _PlayButton extends StatefulWidget {
  const _PlayButton({
    required this.node,
    required this.playing,
    required this.label,
    required this.onPressed,
    required this.onUp,
  });

  final FocusNode node;
  final bool playing;
  final String label;
  final VoidCallback onPressed;
  final VoidCallback onUp;

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.node,
      autofocus: true,
      onFocusChange: (v) => setState(() => _focused = v),
      // Up goes to the Library button; the other arrows are consumed so
      // focus never leaves the button. Back stays unmapped and leaves the app.
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowUp): _FocusLibraryIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown): DoNothingIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): DoNothingIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): DoNothingIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
        _FocusLibraryIntent: CallbackAction<_FocusLibraryIntent>(
          onInvoke: (_) {
            widget.onUp();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        label: widget.label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey.shade800,
            border: Border.all(
              color: _focused ? Colors.orange : Colors.transparent,
              width: 6,
            ),
          ),
          child: Icon(
            widget.playing ? Icons.pause : Icons.play_arrow,
            size: 88,
          ),
        ),
      ),
    );
  }
}

class _LibraryButton extends StatefulWidget {
  const _LibraryButton({
    required this.node,
    required this.label,
    required this.onPressed,
    required this.onLeave,
  });

  final FocusNode node;
  final String label;
  final VoidCallback onPressed;
  final VoidCallback onLeave;

  @override
  State<_LibraryButton> createState() => _LibraryButtonState();
}

class _LibraryButtonState extends State<_LibraryButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.node,
      onFocusChange: (v) => setState(() => _focused = v),
      // Mapped only here, so Back on the play button reaches the system.
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowUp): DoNothingIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown): _FocusPlayIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _FocusPlayIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): _FocusPlayIntent(),
        SingleActivator(LogicalKeyboardKey.goBack): _FocusPlayIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _FocusPlayIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
        _FocusPlayIntent: CallbackAction<_FocusPlayIntent>(
          onInvoke: (_) {
            widget.onLeave();
            return null;
          },
        ),
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: _focused ? Colors.orange : Colors.transparent,
            width: 4,
          ),
        ),
        child: Text(
          widget.label,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}
