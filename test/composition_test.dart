import 'package:bookwave_tv/app_state.dart';
import 'package:bookwave_tv/composition.dart';
import 'package:bookwave_tv/storage/credentials_store.dart';
import 'package:bookwave_tv/storage/local_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_audio_engine.dart';
import 'support/fakes.dart';

/// Storytel stand-in: login answers [loginStatus], bookmarks always 401,
/// the stream URL redirects to a CDN.
Future<(AppState, CredentialsStore)> build({required int loginStatus}) async {
  FlutterSecureStorage.setMockInitialValues({
    'storytel_email': 'a@b.pl',
    'storytel_encrypted_password': 'ENC',
  });
  SharedPreferences.setMockInitialValues({});
  final credentials = CredentialsStore(const FlutterSecureStorage());
  final state = buildAppState(
    httpClient: MockClient((req) async {
      final path = req.url.path;
      if (path.endsWith('login.action')) {
        return loginStatus == 200
            ? http.Response('{"accountInfo":{"jwt":"header.payload"}}', 200)
            : http.Response('', loginStatus);
      }
      if (path.contains('/assets/')) {
        return http.Response(
          '',
          302,
          headers: {'location': 'https://cdn.example/c1.mp3'},
        );
      }
      return http.Response('{}', 401);
    }),
    engine: FakeAudioEngine(),
    store: await LocalStore.open(),
    credentials: credentials,
  );
  return (state, credentials);
}

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a 401 that survives a successful re-login keeps the login', () async {
    final (state, credentials) = await build(loginStatus: 200);
    await state.start();
    await state.pickBook(shelfBook('c1'));
    await settle();
    expect(state.controller.book?.consumableId, 'c1');
    expect(state.route, AppRoute.player);
    expect(await credentials.read(), isNotNull);
  });

  test('a rejected re-login forgets the login', () async {
    final (state, credentials) = await build(loginStatus: 401);
    await state.start();
    await expectLater(state.loadShelf(), throwsA(anything));
    await settle();
    expect(state.route, AppRoute.login);
    expect(await credentials.read(), isNull);
  });
}
