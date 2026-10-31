import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../storytel/models.dart';
import 'no_connection.dart';

const _retryInterval = Duration(seconds: 10);

/// Kids books only, most recently used first, never-used last.
List<ShelfBook> kidsBooksByActivity(List<ShelfBook> shelf) {
  DateTime? activity(ShelfBook b) {
    final p = b.positionUpdatedTime;
    final s = b.stateUpdateTime;
    if (p == null) return s;
    if (s == null) return p;
    return p.isAfter(s) ? p : s;
  }

  final kids = shelf.where((b) => b.kidsBook).toList();
  // List.sort is not stable, so break ties by the original index.
  final index = {for (var i = 0; i < kids.length; i++) kids[i]: i};
  kids.sort((a, b) {
    final x = activity(a);
    final y = activity(b);
    if (x == null && y == null) return index[a]!.compareTo(index[b]!);
    if (x == null) return 1;
    if (y == null) return -1;
    final c = y.compareTo(x);
    return c != 0 ? c : index[a]!.compareTo(index[b]!);
  });
  return kids;
}

/// The cover grid the child's parent picks a book from.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.loadShelf,
    required this.onPick,
    required this.onBack,
    required this.canGoBack,
  });

  final Future<List<ShelfBook>> Function() loadShelf;
  final void Function(ShelfBook) onPick;
  final VoidCallback onBack;

  /// Back returns to the player only while a book is loaded; otherwise it
  /// is left to the system and leaves the app.
  final bool canGoBack;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<ShelfBook>? _books;
  Timer? _retry;
  bool _loading = false;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final shelf = await widget.loadShelf();
      _retry?.cancel();
      _retry = null;
      if (mounted) {
        setState(() {
          _offline = false;
          _books = kidsBooksByActivity(shelf);
        });
      }
    } catch (_) {
      if (mounted && _books == null) {
        _retry ??= Timer.periodic(_retryInterval, (_) => _load());
        setState(() => _offline = true);
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final books = _books;
    final Widget body;
    if (books == null) {
      body = _offline
          ? const NoConnection()
          : const Center(child: CircularProgressIndicator());
    } else if (books.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Text(
            l10n.libraryEmpty,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      body = FocusTraversalGroup(
        child: GridView.builder(
          padding: const EdgeInsets.all(48),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            mainAxisSpacing: 32,
            crossAxisSpacing: 32,
          ),
          itemCount: books.length,
          itemBuilder: (context, i) => LibraryTile(
            book: books[i],
            autofocus: i == 0,
            onPick: () => widget.onPick(books[i]),
          ),
        ),
      );
    }
    return Shortcuts(
      // Without a book to return to the keys stay unmapped, so the event is
      // not consumed and Android's Back leaves the app.
      shortcuts: widget.canGoBack
          ? const {
              SingleActivator(LogicalKeyboardKey.goBack): _BackIntent(),
              SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
            }
          : const {},
      child: Actions(
        actions: {
          _BackIntent: CallbackAction<_BackIntent>(
            onInvoke: (_) {
              if (widget.canGoBack) widget.onBack();
              return null;
            },
          ),
        },
        child: PopScope(
          canPop: !widget.canGoBack,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && widget.canGoBack) widget.onBack();
          },
          child: Scaffold(body: body),
        ),
      ),
    );
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}

/// One cover; the focused tile grows and gets an orange outline.
class LibraryTile extends StatefulWidget {
  const LibraryTile({
    super.key,
    required this.book,
    required this.onPick,
    this.autofocus = false,
  });

  final ShelfBook book;
  final VoidCallback onPick;
  final bool autofocus;

  @override
  State<LibraryTile> createState() => _LibraryTileState();
}

class _LibraryTileState extends State<LibraryTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cover = widget.book.coverUrl;
    final title = Container(
      color: Colors.grey.shade900,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        widget.book.title,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
    );
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPick();
            return null;
          },
        ),
      },
      child: AnimatedScale(
        scale: _focused ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? Colors.orange : Colors.transparent,
              width: 4,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: cover == null
                ? title
                : Image.network(
                    cover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => title,
                  ),
          ),
        ),
      ),
    );
  }
}
