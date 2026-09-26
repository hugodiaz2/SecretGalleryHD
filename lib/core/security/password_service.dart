import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PasswordService {
  static const _key = 'secret_gallery_password';
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );

  Future<bool> hasPassword() async {
    final pw = await _storage.read(key: _key);
    return pw != null && pw.isNotEmpty;
  }

  Future<void> savePassword(String password) async {
    await _storage.write(key: _key, value: password);
  }

  Future<bool> validatePassword(String password) async {
    final stored = await _storage.read(key: _key);
    return stored == password;
  }

  Future<void> deletePassword() async {
    await _storage.delete(key: _key);
  }

  /// Solo para empaquetar/restaurar respaldos.
  Future<String?> rawPassword() => _storage.read(key: _key);
}
