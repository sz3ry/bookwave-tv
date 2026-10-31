import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'l10n/app_localizations.dart';
import 'ui/library_screen.dart';
import 'ui/login_screen.dart';
import 'ui/no_connection.dart';
import 'ui/player_screen.dart';

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
            // The last book is retried; Back still leaves the app, OK on the
            // button opens the library.
            AppRoute.player when state.offline => Scaffold(
              body: NoConnection(onOpenLibrary: state.openLibrary),
            ),
            AppRoute.player => PlayerScreen(
              controller: state.controller,
              onOpenLibrary: state.openLibrary,
            ),
          };
        },
      ),
    );
  }
}
