import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'prefs_service.dart';

/// Estado de tema global (modo oscuro/claro + color de acento).
/// `main.dart` escucha este ChangeNotifier y reconstruye el MaterialApp
/// cuando cambia; las pantallas leen los colores vía `context.colors`
/// y `Theme.of(context).colorScheme.primary`, así que se actualizan solas.
class ThemeService extends ChangeNotifier {
  static final ThemeService instance = ThemeService._();
  ThemeService._();

  bool _darkMode = true;
  Color _accentColor = const Color(0xFF1565C0);

  bool get darkMode => _darkMode;
  Color get accentColor => _accentColor;

  Future<void> load() async {
    _darkMode = await PrefsService.instance.getDarkMode();
    _accentColor = await PrefsService.instance.getAccentColor();
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    if (_darkMode == value) return;
    _darkMode = value;
    await PrefsService.instance.saveDarkMode(value);
    notifyListeners();
  }

  Future<void> setAccentColor(Color color) async {
    if (_accentColor.toARGB32() == color.toARGB32()) return;
    _accentColor = color;
    await PrefsService.instance.saveAccentColor(color);
    notifyListeners();
  }

  ThemeData get themeData {
    final tokens = _darkMode ? AppColors.dark : AppColors.light;
    final brightness = _darkMode ? Brightness.dark : Brightness.light;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accentColor,
        brightness: brightness,
      ).copyWith(primary: _accentColor),
      scaffoldBackgroundColor: tokens.bg,
      extensions: [tokens],
    );
  }
}
