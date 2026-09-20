import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CryptoService {
  static const _keyName = 'sg_aes_key';
  static const _native = MethodChannel('secret_gallery/crypto');
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );
  static Key? _key;
  static Future<Key>? _loadingKey;

  Future<Key> _getKey() async {
    if (_key != null) return _key!;
    return _loadingKey ??= _loadKey();
  }

  Future<Key> _loadKey() async {
    try {
      return await _readOrCreateKey();
    } finally {
      _loadingKey = null;
    }
  }

  Future<Key> _readOrCreateKey() async {
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
    final dir = await _getSecureDir();
    final fileName =
        '${DateTime.now().microsecondsSinceEpoch}_${iv.base16}_${p.basename(originalName)}.enc';
    if (Platform.isAndroid) {
      final destination = p.join(dir.path, fileName);
      final saved = await _native.invokeMethod<String>('encryptFile', {
        'source': sourceFile.path,
        'destination': destination,
        'key': key.bytes,
        'iv': iv.bytes,
      });
      if (saved == null)
        throw StateError('No se pudo guardar el archivo privado.');
      return saved;
    }
    return compute(_encryptOnWorker, (
      source: sourceFile.path,
      destination: p.join(dir.path, fileName),
      key: key.bytes,
      iv: iv.bytes,
    ));
  }

  Future<Uint8List> decryptFile(String encryptedPath) async {
    final key = await _getKey();
    if (Platform.isAndroid) {
      final bytes = await _native.invokeMethod<Uint8List>('decryptBytes', {
        'source': encryptedPath,
        'key': key.bytes,
      });
      if (bytes == null) {
        throw StateError('No se pudo leer el archivo privado.');
      }
      return bytes;
    }
    return compute(_decryptOnWorker, (path: encryptedPath, key: key.bytes));
  }

  /// Decrypt, hash and optionally stage an export in one worker. Only the
  /// digest returns to the UI isolate, never the full plaintext image.
  Future<String> prepareExportFile(String encryptedPath,
      {String? destinationPath}) async {
    final key = await _getKey();
    if (Platform.isAndroid) {
      final digest = await _native.invokeMethod<String>('prepareExport', {
        'source': encryptedPath,
        'destination': destinationPath,
        'key': key.bytes,
      });
      if (digest == null)
        throw StateError('No se pudo verificar el archivo privado.');
      return digest;
    }
    return compute(_prepareExportOnWorker,
        (path: encryptedPath, destination: destinationPath, key: key.bytes));
  }

  static Future<String> hashFile(File file) async {
    if (Platform.isAndroid) {
      final digest =
          await _native.invokeMethod<String>('hashFile', {'source': file.path});
      if (digest == null) throw StateError('No se pudo verificar el archivo.');
      return digest;
    }
    return compute(_hashFileOnWorker, file.path);
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

  /// Solo para empaquetar/restaurar respaldos: la clave AES que protege
  /// todas las fotos. Sin ella, los archivos ".enc" son irrecuperables.
  Future<String> rawKeyBase64() async {
    final key = await _getKey();
    return key.base64;
  }

  /// Reemplaza la clave AES actual por una restaurada de un respaldo.
  Future<void> setRawKeyBase64(String base64Key) async {
    final restoredKey = Key.fromBase64(base64Key);
    if (restoredKey.bytes.length != 32) throw ArgumentError('Invalid AES key');
    if (_loadingKey != null) await _loadingKey;
    await _storage.write(key: _keyName, value: base64Key);
    _key = Key.fromBase64(base64Key);
  }
}

// These workers receive only paths and key bytes. Platform plugins remain on
// the main isolate; file IO and CPU-heavy AES run away from animation frames.
String _encryptOnWorker(
    ({String source, String destination, Uint8List key, Uint8List iv}) job) {
  final bytes = File(job.source).readAsBytesSync();
  final encrypted =
      Encrypter(AES(Key(job.key))).encryptBytes(bytes, iv: IV(job.iv));
  final combined = Uint8List(16 + encrypted.bytes.length);
  combined.setRange(0, 16, job.iv);
  combined.setRange(16, combined.length, encrypted.bytes);
  final output = File(job.destination);
  try {
    output.writeAsBytesSync(combined, flush: true);
    return job.destination;
  } catch (_) {
    try {
      if (output.existsSync()) output.deleteSync();
    } catch (_) {}
    rethrow;
  }
}

Uint8List _decryptOnWorker(({String path, Uint8List key}) job) {
  final combined = File(job.path).readAsBytesSync();
  if (combined.length < 16)
    throw const FormatException('Invalid encrypted file');
  final cipher = Encrypter(AES(Key(job.key)));
  return Uint8List.fromList(cipher.decryptBytes(
    Encrypted(Uint8List.sublistView(combined, 16)),
    iv: IV(Uint8List.sublistView(combined, 0, 16)),
  ));
}

String _prepareExportOnWorker(
    ({String path, String? destination, Uint8List key}) job) {
  final bytes = _decryptOnWorker((path: job.path, key: job.key));
  if (bytes.isEmpty) throw StateError('El archivo privado está vacío.');
  final digest = SHA256Digest()
      .process(bytes)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  if (job.destination != null) {
    File(job.destination!).writeAsBytesSync(bytes, flush: true);
  }
  return digest;
}

String _hashFileOnWorker(String path) {
  final digest = SHA256Digest();
  final input = File(path).openSync();
  final buffer = Uint8List(128 * 1024);
  try {
    var count = input.readIntoSync(buffer);
    while (count > 0) {
      digest.update(buffer, 0, count);
      count = input.readIntoSync(buffer);
    }
  } finally {
    input.closeSync();
  }
  final output = Uint8List(digest.digestSize);
  digest.doFinal(output, 0);
  return output.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
