import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Password hashing and verification using PBKDF2-HMAC-SHA256.
///
/// Stored format: `pbkdf2$<iterations>$<salt>$<base64-hash>`.
/// Any other format is treated as a *legacy plaintext* value so existing
/// installations keep working; those records are transparently upgraded to the
/// hashed format the next time their owner signs in successfully.
class PasswordService {
  const PasswordService._();

  static const int iterations = 120000;
  static const int _keyLength = 32;
  static const String _prefix = 'pbkdf2';
  static const String _separator = r'$';

  /// Creates a verifiable hash for [password] with a fresh random salt.
  static String hash(String password) {
    final salt = _generateSalt();
    final derived = _pbkdf2(password, salt, iterations, _keyLength);
    return '$_prefix$_separator$iterations$_separator$salt$_separator'
        '${base64.encode(derived)}';
  }

  /// Verifies [password] against a stored value produced by [hash] or a legacy
  /// plaintext value. Returns false for empty/invalid stored values.
  static bool verify(String password, String? stored) {
    if (stored == null || stored.isEmpty) return false;

    if (!stored.startsWith('$_prefix$_separator')) {
      // Legacy plaintext record — compare directly. Callers should call
      // [needsUpgrade] and rewrite the record after a successful comparison.
      return _constantTimeEquals(password, stored);
    }

    final parts = stored.split(_separator);
    if (parts.length != 4) return false;

    final parsedIterations = int.tryParse(parts[1]);
    if (parsedIterations == null || parsedIterations <= 0) return false;

    final salt = parts[2];
    final expected = base64.decode(parts[3]);
    final actual = _pbkdf2(password, salt, parsedIterations, expected.length);

    return _constantTimeEqualsList(actual, expected);
  }

  /// True when the stored value is a legacy plaintext password that should be
  /// replaced by [hash] after the next successful login.
  static bool needsUpgrade(String? stored) =>
      stored != null && stored.isNotEmpty && !stored.startsWith(
        '$_prefix$_separator',
      );

  static String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  static List<int> _pbkdf2(
    String password,
    String salt,
    int iterations,
    int keyLength,
  ) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final saltBytes = utf8.encode(salt);
    final blockCount = (keyLength / 32).ceil();
    final result = <int>[];

    for (var block = 1; block <= blockCount; block++) {
      final blockBytes = [
        ...saltBytes,
        (block >> 24) & 0xFF,
        (block >> 16) & 0xFF,
        (block >> 8) & 0xFF,
        block & 0xFF,
      ];

      var u = hmac.convert(blockBytes).bytes;
      final t = List<int>.from(u);

      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      result.addAll(t);
    }

    return result.sublist(0, keyLength);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    return _constantTimeEqualsList(a.codeUnits, b.codeUnits);
  }

  static bool _constantTimeEqualsList(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
