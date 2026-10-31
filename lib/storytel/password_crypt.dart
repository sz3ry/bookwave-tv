import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

const _key = 'VQZBJ6TD8M9WBUWT';
const _iv = 'joiwef08u23j341a';

/// Encrypts a Storytel password: AES-128-CBC, PKCS7, upper-case hex.
String encryptPassword(String password) {
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))..init(
        true,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV(
            KeyParameter(Uint8List.fromList(utf8.encode(_key))),
            Uint8List.fromList(utf8.encode(_iv)),
          ),
          null,
        ),
      );
  final out = cipher.process(Uint8List.fromList(utf8.encode(password.trim())));
  return out
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}
