import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_gallery/core/security/crypto_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('missing key never replaces the key of an existing vault', () async {
    final root = await Directory.systemTemp.createTemp('sg_missing_key_');
    FlutterSecureStorage.setMockInitialValues({});
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => root.path);
    try {
      final vault = await Directory('${root.path}/.sg_vault').create();
      await File('${vault.path}/existing.enc').writeAsBytes([1]);
      await expectLater(CryptoService().rawKeyBase64(), throwsStateError);
      expect(
          await const FlutterSecureStorage().read(key: 'sg_aes_key'), isNull);
      expect(await File('${vault.path}/existing.enc').readAsBytes(), [1]);
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
      await root.delete(recursive: true);
    }
  });
}
