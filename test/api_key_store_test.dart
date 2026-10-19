import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_tracker_mobile/services/api_key_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureValues = <String, String>{};
  var failWrites = false;

  setUp(() {
    secureValues.clear();
    failWrites = false;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String;
          switch (call.method) {
            case 'read':
              return secureValues[key];
            case 'write':
              if (failWrites) throw PlatformException(code: 'write_failed');
              secureValues[key] = args['value'] as String;
              return null;
            case 'delete':
              secureValues.remove(key);
              return null;
          }
          throw MissingPluginException(call.method);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('migrates plaintext keys and keeps accounts separate', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('usda_api_key_alice', 'old-key');
    expect(await ApiKeyStore.read('alice', 'usda'), 'old-key');
    expect(prefs.containsKey('usda_api_key_alice'), isFalse);
    expect(secureValues['usda_api_key_alice'], 'old-key');
    expect(await ApiKeyStore.read('bob', 'usda'), isEmpty);
  });

  test('writes replace secure values and remove old plaintext copies', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key_alice', 'stale-key');
    await ApiKeyStore.write('alice', 'gemini', 'new-key');
    expect(await ApiKeyStore.read('alice', 'gemini'), 'new-key');
    expect(prefs.containsKey('gemini_api_key_alice'), isFalse);
    await ApiKeyStore.write('alice', 'gemini', '');
    expect(await ApiKeyStore.read('alice', 'gemini'), isEmpty);
  });

  test('failed secure migration leaves the old key available', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('usda_api_key_alice', 'old-key');
    failWrites = true;
    await expectLater(
      ApiKeyStore.read('alice', 'usda'),
      throwsA(isA<PlatformException>()),
    );
    expect(prefs.getString('usda_api_key_alice'), 'old-key');
  });
}
