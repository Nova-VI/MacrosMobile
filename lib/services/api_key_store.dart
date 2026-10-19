import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps user-scoped API keys out of ordinary app preferences.
class ApiKeyStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String _name(String uid, String provider) => '${provider}_api_key_$uid';

  static Future<String> read(String uid, String provider) async {
    final name = _name(uid, provider);
    final prefs = await SharedPreferences.getInstance();
    final secureValue = await _storage.read(key: name);
    if (secureValue != null) {
      if (prefs.containsKey(name)) await prefs.remove(name);
      return secureValue;
    }

    final legacyValue = prefs.getString(name);
    if (legacyValue == null) return '';
    // Move keys saved by older versions before clearing their plaintext copies.
    await _storage.write(key: name, value: legacyValue);
    await prefs.remove(name);
    return legacyValue;
  }

  static Future<void> write(String uid, String provider, String value) async {
    final name = _name(uid, provider);
    if (value.isEmpty) {
      await _storage.delete(key: name);
    } else {
      await _storage.write(key: name, value: value);
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(name)) await prefs.remove(name);
  }
}
