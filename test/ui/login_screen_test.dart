import 'package:bookwave_tv/l10n/app_localizations.dart';
import 'package:bookwave_tv/storytel/storytel_http.dart';
import 'package:bookwave_tv/ui/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(
  locale: const Locale('pl'),
  supportedLocales: const [Locale('pl')],
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: child,
);

void main() {
  testWidgets('login shows rejection message', (tester) async {
    await tester.pumpWidget(
      host(
        LoginScreen(
          onLogin: (e, p) async =>
              throw StorytelAuthException(null, isLoginFailure: true),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'a@b.pl');
    await tester.enterText(find.byType(TextField).last, 'pw');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.text('Nieprawidłowy e-mail lub hasło'), findsOneWidget);
  });

  testWidgets('login shows generic failure message', (tester) async {
    await tester.pumpWidget(
      host(LoginScreen(onLogin: (e, p) async => throw Exception('x'))),
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(
      find.text('Nie udało się zalogować. Spróbuj ponownie.'),
      findsOneWidget,
    );
  });

  testWidgets('login focus moves email, password, button with D-pad', (
    tester,
  ) async {
    String? sent;
    await tester.pumpWidget(
      host(LoginScreen(onLogin: (e, p) async => sent = '$e|$p')),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'a@b.pl');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'pw');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(sent, 'a@b.pl|pw');
  });
}
