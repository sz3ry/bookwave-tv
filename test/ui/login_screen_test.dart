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

  bool hasFocus(WidgetTester tester, Finder field) => tester
      .widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      )
      .focusNode
      .hasFocus;

  testWidgets('arrows do not move focus out of a text field', (tester) async {
    await tester.pumpWidget(host(LoginScreen(onLogin: (e, p) async {})));
    await tester.pump();
    final email = find.byType(TextField).first;
    expect(hasFocus(tester, email), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(hasFocus(tester, email), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(hasFocus(tester, email), isTrue);
  });

  testWidgets('enter on email moves to password', (tester) async {
    await tester.pumpWidget(host(LoginScreen(onLogin: (e, p) async {})));
    await tester.pump();
    await tester.showKeyboard(find.byType(TextField).first);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(hasFocus(tester, find.byType(TextField).last), isTrue);
  });

  testWidgets('done on password submits login', (tester) async {
    String? sent;
    await tester.pumpWidget(
      host(LoginScreen(onLogin: (e, p) async => sent = '$e|$p')),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'a@b.pl');
    await tester.enterText(find.byType(TextField).last, 'pw');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(sent, 'a@b.pl|pw');
  });

  testWidgets('failed login refocuses email and keeps values', (tester) async {
    await tester.pumpWidget(
      host(
        LoginScreen(
          onLogin: (e, p) async =>
              throw StorytelAuthException(null, isLoginFailure: true),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'a@b.pl');
    await tester.enterText(find.byType(TextField).last, 'pw');
    expect(hasFocus(tester, find.byType(TextField).last), isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    expect(find.text('Nieprawidłowy e-mail lub hasło'), findsOneWidget);
    expect(hasFocus(tester, find.byType(TextField).first), isTrue);
    expect(find.text('a@b.pl'), findsOneWidget);
    final pw = tester.widget<TextField>(find.byType(TextField).last);
    expect(pw.controller!.text, 'pw');
  });
}
