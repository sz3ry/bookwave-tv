import 'package:bookwave_tv/app.dart';
import 'package:bookwave_tv/app_state.dart';
import 'package:bookwave_tv/storage/credentials_store.dart';
import 'package:bookwave_tv/storage/local_store.dart';
import 'package:bookwave_tv/ui/no_connection.dart';
import 'package:bookwave_tv/ui/player_screen.dart';
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
    final controller = FakeController()..openError = Exception('offline');
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
}
