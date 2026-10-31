import 'dart:io';

import 'package:bookwave_tv/l10n/app_localizations.dart';
import 'package:bookwave_tv/storytel/models.dart';
import 'package:bookwave_tv/ui/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

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

Widget screen(
  Future<List<ShelfBook>> Function() load, {
  void Function(ShelfBook)? onPick,
  VoidCallback? onBack,
  bool canGoBack = true,
}) => host(
  LibraryScreen(
    loadShelf: load,
    onPick: onPick ?? (_) {},
    onBack: onBack ?? () {},
    canGoBack: canGoBack,
  ),
);

List<String> tileIds(WidgetTester tester) => tester
    .widgetList<LibraryTile>(find.byType(LibraryTile))
    .map((t) => t.book.consumableId)
    .toList();

void main() {
  testWidgets('library sorts by most recent activity', (tester) async {
    final shelf = [
      shelfBook('none'),
      shelfBook('old', positionUpdated: DateTime.utc(2026, 1, 1)),
      shelfBook(
        'newState',
        positionUpdated: DateTime.utc(2026, 1, 2),
        stateUpdated: DateTime.utc(2026, 3, 1),
      ),
      shelfBook('mid', positionUpdated: DateTime.utc(2026, 2, 1)),
    ];
    await tester.pumpWidget(screen(() async => shelf));
    await tester.pump();
    expect(tileIds(tester), ['newState', 'mid', 'old', 'none']);
  });

  testWidgets('library shows only kids books', (tester) async {
    final shelf = [shelfBook('kid'), shelfBook('adult', kids: false)];
    await tester.pumpWidget(screen(() async => shelf));
    await tester.pump();
    expect(tileIds(tester), ['kid']);
  });

  testWidgets('library empty when shelf has no kids books', (tester) async {
    await tester.pumpWidget(
      screen(() async => [shelfBook('adult', kids: false)]),
    );
    await tester.pump();
    expect(find.byType(LibraryTile), findsNothing);
    expect(
      find.text(
        'Na półce nie ma audiobooków dla dzieci. Dodaj książkę w Bookwave '
        'albo w aplikacji Storytel.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('library OK picks the focused book', (tester) async {
    ShelfBook? picked;
    final shelf = [
      shelfBook('a', positionUpdated: DateTime.utc(2026, 2, 1)),
      shelfBook('b', positionUpdated: DateTime.utc(2026, 1, 1)),
    ];
    await tester.pumpWidget(
      screen(() async => shelf, onPick: (b) => picked = b),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(picked?.consumableId, 'a');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(picked?.consumableId, 'b');
  });

  testWidgets('library Back returns without changing the book', (tester) async {
    ShelfBook? picked;
    var backs = 0;
    await tester.pumpWidget(
      screen(
        () async => [shelfBook('a')],
        onPick: (b) => picked = b,
        onBack: () => backs++,
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(backs, 1);
    // The Android Back button arrives as a system pop.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(backs, 2);
    expect(picked, isNull);
  });

  testWidgets('library Back does nothing without a loaded book', (
    tester,
  ) async {
    var backs = 0;
    await tester.pumpWidget(
      screen(
        () async => [shelfBook('a')],
        onBack: () => backs++,
        canGoBack: false,
      ),
    );
    await tester.pump();
    // The key must stay unhandled so Android's Back can leave the app.
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isFalse);
    await tester.pump();
    expect(backs, 0);
  });

  testWidgets(
    'empty library Back returns to the player when a book is loaded',
    (tester) async {
      var backs = 0;
      await tester.pumpWidget(
        screen(
          () async => [shelfBook('adult', kids: false)],
          onBack: () => backs++,
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(backs, 1);
    },
  );

  testWidgets('empty library Back is not consumed without a loaded book', (
    tester,
  ) async {
    var backs = 0;
    await tester.pumpWidget(
      screen(
        () async => [shelfBook('adult', kids: false)],
        onBack: () => backs++,
        canGoBack: false,
      ),
    );
    await tester.pump();
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isFalse);
    expect(backs, 0);
  });

  testWidgets('autofocused first tile shows the outline without a key', (
    tester,
  ) async {
    await tester.pumpWidget(screen(() async => [shelfBook('a')]));
    await tester.pump();
    await tester.pump();
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(LibraryTile),
        matching: find.byType(DecoratedBox),
      ),
    );
    final border = (box.decoration as BoxDecoration).border! as Border;
    expect(border.top.color, Colors.orange);
  });

  testWidgets('library shows no-connection and retries', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      screen(() async {
        calls++;
        if (calls == 1) throw const SocketException('down');
        return [shelfBook('a')];
      }),
    );
    await tester.pump();
    expect(find.text('Brak połączenia. Ponawiam…'), findsOneWidget);
    expect(find.byType(LibraryTile), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(calls, 2);
    expect(find.text('Brak połączenia. Ponawiam…'), findsNothing);
    expect(tileIds(tester), ['a']);
  });
}
