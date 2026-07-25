import 'dart:io';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CryptoService {
  static const _keyName = 'sg_aes_key';
  final _storage = const FlutterSecureStorage();
  Key? _key;

  Future<Key> _getKey() async {
    if (_key != null) return _key!;
    String? stored = await _storage.read(key: _keyName);
    if (stored == null) {
      final newKey = Key.fromSecureRandom(32);
      await _storage.write(key: _keyName, value: newKey.base64);
      _key = newKey;
    } else {
      _key = Key.fromBase64(stored);
    }
    return _key!;
  }

  Future<String> encryptAndSave(File sourceFile, String originalName) async {
    final key = await _getKey();
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key));

    final bytes = await sourceFile.readAsBytes();
    final encrypted = encrypter.encryptBytes(bytes, iv: iv);

    final dir = await _getSecureDir();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_$originalName.enc';
    final destPath = p.join(dir.path, fileName);

    // Guardamos IV (16 bytes) + datos encriptados
    final combined = Uint8List(16 + encrypted.bytes.length);
    combined.setRange(0, 16, iv.bytes);
    combined.setRange(16, combined.length, encrypted.bytes);

    await File(destPath).writeAsBytes(combined);
    return destPath;
  }

  Future<Uint8List> decryptFile(String encryptedPath) async {
    final key = await _getKey();
    final combined = await File(encryptedPath).readAsBytes();

    final iv = IV(combined.sublist(0, 16));
    final encryptedBytes = combined.sublist(16);

    final encrypter = Encrypter(AES(key));
    final encrypted = Encrypted(encryptedBytes);
    return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
  }

  Future<Directory> _getSecureDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, '.sg_vault'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> deleteEncryptedFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}