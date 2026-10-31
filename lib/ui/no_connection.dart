import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Shown while Storytel cannot be reached; the owner retries on its own.
/// With [onOpenLibrary] it offers a focused Library button, so the child is
/// never stuck on this screen.
class NoConnection extends StatelessWidget {
  const NoConnection({super.key, this.onOpenLibrary});

  final VoidCallback? onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 64),
          const SizedBox(height: 16),
          Text(
            l10n.noConnection,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (onOpenLibrary != null) ...[
            const SizedBox(height: 32),
            _LibraryButton(label: l10n.library, onPressed: onOpenLibrary!),
          ],
        ],
      ),
    );
  }
}

class _LibraryButton extends StatefulWidget {
  const _LibraryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_LibraryButton> createState() => _LibraryButtonState();
}

class _LibraryButtonState extends State<_LibraryButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: true,
      onFocusChange: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        label: widget.label,
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
      ),
    );
  }
}
