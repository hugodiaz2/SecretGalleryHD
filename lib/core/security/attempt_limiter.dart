import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Limita los intentos fallidos de PIN/contraseña para que no se pueda
/// probar todas las combinaciones. Tras [freeAttempts] fallos seguidos,
/// cada fallo nuevo obliga a esperar el doble que el anterior (30 s, 1 min,
/// 2 min… hasta 15 min). El contador se guarda en el almacenamiento seguro,
/// así que cerrar y abrir la app no lo reinicia.
class AttemptLimiter {
  static final AttemptLimiter instance = AttemptLimiter._();
  AttemptLimiter._();

  static const freeAttempts = 5;
  static const _baseWait = Duration(seconds: 30);
  static const _maxWait = Duration(minutes: 15);
  static const _keyFailures = 'auth_failed_attempts';
  static const _keyLockedUntil = 'auth_locked_until';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );

  int? _failures;
  int? _lockedUntil;

  Future<void> _load() async {
    if (_failures != null) return;
    try {
      _failures =
          int.tryParse(await _storage.read(key: _keyFailures) ?? '') ?? 0;
      _lockedUntil =
          int.tryParse(await _storage.read(key: _keyLockedUntil) ?? '') ?? 0;
    } catch (_) {
      _failures = 0;
      _lockedUntil = 0;
    }
  }

  /// Tiempo que falta para poder intentarlo de nuevo (cero si ya se puede).
  Future<Duration> remaining() async {
    await _load();
    final ms = _lockedUntil! - DateTime.now().millisecondsSinceEpoch;
    // Un reloj atrasado a propósito no debe dejar una espera mayor al máximo.
    return Duration(milliseconds: ms.clamp(0, _maxWait.inMilliseconds));
  }

  /// Registra un intento fallido y devuelve la espera que se impone.
  Future<Duration> recordFailure() async {
    await _load();
    _failures = _failures! + 1;
    var wait = Duration.zero;
    if (_failures! >= freeAttempts) {
      final steps = min(_failures! - freeAttempts, 10);
      final ms = _baseWait.inMilliseconds * pow(2, steps).toInt();
      wait = Duration(milliseconds: min(ms, _maxWait.inMilliseconds));
      _lockedUntil = DateTime.now().millisecondsSinceEpoch + wait.inMilliseconds;
    }
    try {
      await _storage.write(key: _keyFailures, value: '$_failures');
      await _storage.write(key: _keyLockedUntil, value: '$_lockedUntil');
    } catch (_) {}
    return wait;
  }

  Future<void> reset() async {
    if (_failures == 0 && _lockedUntil == 0) return;
    _failures = 0;
    _lockedUntil = 0;
    try {
      await _storage.delete(key: _keyFailures);
      await _storage.delete(key: _keyLockedUntil);
    } catch (_) {}
  }

  static String format(Duration d) {
    final s = d.inSeconds + (d.inMilliseconds % 1000 > 0 ? 1 : 0);
    if (s < 60) return '$s s';
    final m = s ~/ 60;
    final r = s % 60;
    return r == 0 ? '$m min' : '$m min $r s';
  }
}
