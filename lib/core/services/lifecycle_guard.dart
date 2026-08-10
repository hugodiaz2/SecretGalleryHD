/// Evita que "cerrar al minimizar" y el re-bloqueo automático se disparen
/// cuando la propia app abre algo externo a propósito (compartir una
/// foto, elegir un archivo de respaldo, etc.). Sin esto, Android manda la
/// app a segundo plano al abrir Drive/WhatsApp y AppEntry lo trata igual
/// que si el usuario hubiera salido de verdad — cerrando la app o
/// pidiendo el PIN de nuevo en medio de una acción que la misma app
/// inició.
class LifecycleGuard {
  static int _suppressCount = 0;

  static bool get isSuppressed => _suppressCount > 0;

  static void _begin() => _suppressCount++;

  static void _end() {
    if (_suppressCount > 0) _suppressCount--;
  }

  /// Envuelve una acción que abre algo externo (compartir, seleccionar
  /// archivo, etc.). Mientras esté en curso —y un breve margen después,
  /// porque el evento "paused" a veces llega ya vuelto a foreground—
  /// se ignoran el cierre y el re-bloqueo automáticos.
  static Future<T> run<T>(Future<T> Function() action) async {
    _begin();
    try {
      return await action();
    } finally {
      Future.delayed(const Duration(milliseconds: 800), _end);
    }
  }
}
