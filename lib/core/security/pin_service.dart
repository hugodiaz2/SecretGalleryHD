import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PinService {
  static const _key = 'secret_gallery_pin';
  final _storage = const FlutterSecureStorage();

  Future<bool> hasPin() async {
    final pin = await _storage.read(key: _key);
    return pin != null && pin.isNotEmpty;
  }

  Future<void> savePin(String pin) async {
    await _storage.write(key: _key, value: pin);
  }

  Future<bool> validatePin(String pin) async {
    final stored = await _storage.read(key: _key);
    return stored == pin;
  }

  Future<void> deletePin() async {
    await _storage.delete(key: _key);
  }
}