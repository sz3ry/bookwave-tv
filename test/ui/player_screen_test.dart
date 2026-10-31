import 'package:bookwave_tv/l10n/app_localizations.dart';
import 'package:bookwave_tv/playback/player_controller.dart';
import 'package:bookwave_tv/storytel/models.dart';
import 'package:bookwave_tv/ui/library_screen.dart';
import 'package:bookwave_tv/ui/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

class FakePlayerController extends ChangeNotifier implements PlayerController {
  int toggles = 0;

  @override
  ShelfBook? book = ShelfBook(
    consumableId: 'b1',
    title: 'Kajko i Kokosz',
    authors: 'Janusz Christa',
    kidsBook: true,
    durationMs: 10265000,
  );
  @override
  bool isPlaying = false;
  @override
  bool isFinished = false;
  @override
  Duration position = const Duration(seconds: 4360);
  @override
  Duration get duration => const Duration(seconds: 10265);

  @override
  Future<void> togglePlayPause() async {
    toggles++;
    isPlaying = !isPlaying;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Host extends StatefulWidget {
  const _Host(this.controller, this.wakelock);

  final PlayerController controller;
  final Future<void> Function(bool) wakelock;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool library = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('pl'),
    supportedLocales: const [Locale('pl')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: library
        ? LibraryScreen(
            loadShelf: () async => [shelfBook('x')],
            onPick: (_) {},
            onBack: () => setState(() => library = false),
            canGoBack: true,
          )
        : PlayerScreen(
            controller: widget.controller,
            onOpenLibrary: () => setState(() => library = true),
            setWakelock: widget.wakelock,
          ),
  );
}

Future<FakePlayerController> pump(
  WidgetTester tester, {
  List<bool>? wakelock,
}) async {
  final c = FakePlayerController();
  await tester.pumpWidget(_Host(c, (on) async => wakelock?.add(on)));
  await tester.pump();
  return c;
}

bool playFocused(WidgetTester tester) {
  final icon = find.byWidgetPredicate(
    (w) => w is Icon && (w.icon == Icons.play_arrow || w.icon == Icons.pause),
  );
  return Focus.of(tester.element(icon)).hasFocus;
}

void main() {
  testWidgets('play button focused on start', (tester) async {
    await pump(tester);
    expect(playFocused(tester), isTrue);
    expect(
      tester.getSize(find.byType(AnimatedContainer)).width,
      greaterThanOrEqualTo(120),
    );
  });

  testWidgets('OK toggles play and pause', (tester) async {
    final c = await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(c.toggles, 2);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('media play-pause key toggles', (tester) async {
    final c = await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    expect(c.toggles, 1);
  });

  testWidgets('up focuses library and OK opens it', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(playFocused(tester), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.byType(LibraryScreen), findsOneWidget);
  });

  testWidgets('arrows and back on library button return to play', (
    tester,
  ) async {
    await pump(tester);
    for (final k in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.escape,
    ]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(playFocused(tester), isFalse);
      await tester.sendKeyEvent(k);
      await tester.pump();
      expect(playFocused(tester), isTrue, reason: '$k');
    }
  });

  testWidgets('focus returns to play after library', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(playFocused(tester), isTrue);
  });

  testWidgets('shows elapsed and total time', (tester) async {
    await pump(tester);
    expect(find.text('1:12:40 / 2:51:05'), findsOneWidget);
  });

  testWidgets('shows the finished label', (tester) async {
    final c = await pump(tester);
    c.isFinished = true;
    c.notifyListeners();
    await tester.pump();
    expect(find.text('Koniec książki'), findsOneWidget);
  });

  testWidgets('wakelock enabled while shown', (tester) async {
    final calls = <bool>[];
    await pump(tester, wakelock: calls);
    expect(calls, [true]);
    await tester.pumpWidget(const SizedBox());
    expect(calls, [true, false]);
  });
}
