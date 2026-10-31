import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../storytel/models.dart';

/// Keeps the Storytel login (email + encrypted password) in secure storage.
class CredentialsStore {
  CredentialsStore(this._storage);

  static const _emailKey = 'storytel_email';
  static const _passwordKey = 'storytel_encrypted_password';

  final FlutterSecureStorage _storage;

  Future<StorytelCredentials?> read() async {
    final email = await _storage.read(key: _emailKey);
    final password = await _storage.read(key: _passwordKey);
    if (email == null || password == null) return null;
    return StorytelCredentials(email: email, encryptedPassword: password);
  }

  Future<void> write(StorytelCredentials c) async {
    await _storage.write(key: _emailKey, value: c.email);
    await _storage.write(key: _passwordKey, value: c.encryptedPassword);
  }

  Future<void> clear() async {
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _passwordKey);
  }
}
