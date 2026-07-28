import 'package:flutter/services.dart';

/// Puente hacia el flag nativo FLAG_SECURE de Android, que sí bloquea
/// screenshots y grabación de pantalla (a diferencia del modo inmersivo
/// de SystemChrome, que solo oculta las barras del sistema).
class SecurityChannel {
  static const _channel = MethodChannel('secret_gallery/security');

  static Future<void> setSecure(bool enabled) async {
    try {
      await _channel.invokeMethod('setSecure', {'enabled': enabled});
    } catch (_) {
      // Plataforma sin soporte nativo (iOS, web, desktop): no interrumpe la app.
    }
  }
}
