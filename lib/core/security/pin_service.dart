import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PinService {
  static const _key = 'secret_gallery_pin';
  // Preserve stored credentials on Keystore failures; never silently reset them.
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );

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

  /// Solo para empaquetar/restaurar respaldos: el PIN se guarda en texto
  /// plano en el storage seguro, así que exponerlo crudo no cambia el
  /// modelo de seguridad existente.
  Future<String?> rawPin() => _storage.read(key: _key);
}
