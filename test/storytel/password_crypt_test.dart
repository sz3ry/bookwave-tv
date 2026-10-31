import 'package:bookwave_tv/storytel/password_crypt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encrypts known vectors', () {
    expect(encryptPassword('secret'), 'EA28CEC50BCD4410067D143BA5FC8885');
    expect(encryptPassword('zażółć123'), '2FE57A0B786DDC959C9702FA7F2BC52C');
  });

  test('trims input', () {
    expect(encryptPassword('  secret '), 'EA28CEC50BCD4410067D143BA5FC8885');
  });
}
