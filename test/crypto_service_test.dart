import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_gallery/core/security/crypto_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'concurrent services encrypt with the single persisted key and unique paths',
      () async {
    final root = await Directory.systemTemp.createTemp('sg_crypto_test_');
    FlutterSecureStorage.setMockInitialValues({});
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async => root.path);
    try {
      final input = File('${root.path}/photo.jpg');
      final bytes = List<int>.generate(1024, (i) => i % 256);
      await input.writeAsBytes(bytes);
      final outputs = await Future.wait(List.generate(
          10, (_) => CryptoService().encryptAndSave(input, 'photo.jpg')));
      expect(outputs.toSet(), hasLength(10));
      final stored = await const FlutterSecureStorage().read(key: 'sg_aes_key');
      expect(stored, isNotNull);
      final cipher = Encrypter(AES(Key.fromBase64(stored!)));
      for (final path in outputs) {
        final encrypted = await File(path).readAsBytes();
        final clear = cipher.decryptBytes(Encrypted(encrypted.sublist(16)),
            iv: IV(encrypted.sublist(0, 16)));
        expect(clear, bytes);
      }
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
      await root.delete(recursive: true);
    }
  });
}
