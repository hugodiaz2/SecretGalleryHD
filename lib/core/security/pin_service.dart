import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PinService {
  static const _key = 'secret_gallery_pin';
  // resetOnError: si la clave de Android Keystore que cifra el storage
  // queda inválida (p. ej. tras borrar datos de la app parcialmente),
  // una lectura tira BadPaddingException. Con esto el plugin se
  // autorepara borrando lo corrupto en vez de lanzar la excepción y
  // dejar la app trabada en el splash para siempre.
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
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
}