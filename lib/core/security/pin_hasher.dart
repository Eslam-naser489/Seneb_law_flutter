import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class PinHasher {
  const PinHasher();
  static const algorithm = 'ARGON2ID';
  static const parameters =
      '{"memoryKiB":19456,"iterations":2,"parallelism":1,"bytes":32}';

  static String normalize(String pin) => String.fromCharCodes(
    pin.runes.map((c) {
      if (c >= 0x660 && c <= 0x669) return c - 0x660 + 48;
      if (c >= 0x6f0 && c <= 0x6f9) return c - 0x6f0 + 48;
      return c;
    }),
  );

  static bool valid(String pin) =>
      RegExp(r'^[0-9]{6,12}$').hasMatch(normalize(pin));

  Future<String> hash(String pin) async {
    if (!valid(pin)) {
      throw const FormatException('الرقم السري من ٦ إلى ١٢ رقمًا.');
    }
    final random = Random.secure();
    final salt = List.generate(16, (_) => random.nextInt(256));
    final hash = await _derive(normalize(pin), salt);
    return '${base64Encode(salt)}:${base64Encode(hash)}';
  }

  Future<bool> verify(String pin, String verifier) async {
    if (!valid(pin)) return false;
    final parts = verifier.split(':');
    if (parts.length != 2) return false;
    try {
      final salt = base64Decode(parts[0]);
      final expected = base64Decode(parts[1]);
      if (salt.length != 16 || expected.length != 32) return false;
      final actual = await _derive(normalize(pin), salt);
      var difference = 0;
      for (var i = 0; i < expected.length; i++) {
        difference |= expected[i] ^ actual[i];
      }
      return difference == 0;
    } on FormatException {
      return false;
    }
  }

  static Future<List<int>> _derive(String pin, List<int> salt) =>
      Isolate.run(() async {
        final result = await Argon2id(
          memory: 19456,
          iterations: 2,
          parallelism: 1,
          hashLength: 32,
        ).deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt);
        return result.extractBytes();
      });
}
