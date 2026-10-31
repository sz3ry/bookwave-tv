import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Shown while the shelf cannot be loaded; the owner retries on its own.
class NoConnection extends StatelessWidget {
  const NoConnection({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 64),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context).noConnection,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ],
      ),
    );
  }
}
