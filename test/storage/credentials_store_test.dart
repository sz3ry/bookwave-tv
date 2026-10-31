import 'package:bookwave_tv/storage/credentials_store.dart';
import 'package:bookwave_tv/storytel/models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('credentials round-trip and clear', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = CredentialsStore(const FlutterSecureStorage());
    expect(await store.read(), isNull);

    await store.write(
      StorytelCredentials(email: 'a@b.pl', encryptedPassword: 'ABCDEF'),
    );
    final read = await store.read();
    expect(read?.email, 'a@b.pl');
    expect(read?.encryptedPassword, 'ABCDEF');

    await store.clear();
    expect(await store.read(), isNull);
  });
}
