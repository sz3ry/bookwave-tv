import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'l10n/app_localizations.dart';
import 'ui/library_screen.dart';
import 'ui/login_screen.dart';

class BookwaveTvApp extends StatelessWidget {
  const BookwaveTvApp(this.state, {super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: ThemeData.dark(useMaterial3: true),
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ListenableBuilder(
        listenable: Listenable.merge([state, state.controller]),
        builder: (context, _) {
          if (!state.started) return const Scaffold();
          return switch (state.route) {
            AppRoute.login => LoginScreen(onLogin: state.login),
            AppRoute.library => LibraryScreen(
              loadShelf: state.loadShelf,
              onPick: state.pickBook,
              onBack: state.closeLibrary,
              canGoBack: state.controller.book != null,
            ),
            AppRoute.player => _PlayerPlaceholder(state),
          };
        },
      ),
    );
  }
}

/// Stand-in until the real player screen replaces it.
class _PlayerPlaceholder extends StatelessWidget {
  const _PlayerPlaceholder(this.state);

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              state.controller.book?.title ?? '',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              autofocus: true,
              onPressed: state.openLibrary,
              child: Text(l10n.library),
            ),
          ],
        ),
      ),
    );
  }
}
