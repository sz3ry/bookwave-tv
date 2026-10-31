import 'dart:io';

import 'package:bookwave_tv/app.dart';
import 'package:bookwave_tv/app_state.dart';
import 'package:bookwave_tv/storage/credentials_store.dart';
import 'package:bookwave_tv/storage/local_store.dart';
import 'package:bookwave_tv/ui/library_screen.dart';
import 'package:bookwave_tv/ui/no_connection.dart';
import 'package:bookwave_tv/ui/player_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('offline at launch shows no connection on the player route', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'storytel_email': 'a@b.pl',
      'storytel_encrypted_password': 'ENC',
    });
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.setLastBook(shelfBook('c1'));
    final controller = FakeController()
      ..openError = const SocketException('offline');
    final state = AppState(
      client: FakeClient(),
      credentials: CredentialsStore(const FlutterSecureStorage()),
      store: store,
      controller: controller,
    );
    await state.start();
    await tester.pumpWidget(BookwaveTvApp(state));
    await tester.pump();
    expect(state.route, AppRoute.player);
    expect(find.byType(NoConnection), findsOneWidget);
    expect(find.text('Brak połączenia. Ponawiam…'), findsOneWidget);
    expect(find.byType(PlayerScreen), findsNothing);
    state.dispose();
  });

  testWidgets(
    'offline screen library button opens the library and stops retrying',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'storytel_email': 'a@b.pl',
        'storytel_encrypted_password': 'ENC',
      });
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      await store.setLastBook(shelfBook('c1'));
      final controller = FakeController()
        ..openError = const SocketException('offline');
      final state = AppState(
        client: FakeClient(),
        credentials: CredentialsStore(const FlutterSecureStorage()),
        store: store,
        controller: controller,
      );
      await state.start();
      await tester.pumpWidget(BookwaveTvApp(state));
      await tester.pump();
      expect(find.text('Biblioteka'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(state.route, AppRoute.library);
      await tester.pump(const Duration(seconds: 30));
      expect(controller.opened, ['c1']);
      expect(find.byType(LibraryScreen), findsOneWidget);
      state.dispose();
    },
  );
}
