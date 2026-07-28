import 'package:flutter/material.dart';

/// Tokens semánticos de color (fondo, superficies, texto) que reemplazan
/// los `Color(0xFF...)` fijos que había en cada pantalla. Se leen con
/// `Theme.of(context).extension<AppColors>()!` y cambian solo/en vivo
/// cuando el usuario alterna modo oscuro/claro.
class AppColors extends ThemeExtension<AppColors> {
  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textFaint;
  final Color textGhost;

  const AppColors({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textFaint,
    required this.textGhost,
  });

  static const dark = AppColors(
    bg: Color(0xFF121212),
    surface: Color(0xFF1A1A1A),
    surfaceHigh: Color(0xFF2A2A2A),
    border: Colors.white12,
    textPrimary: Colors.white,
    textSecondary: Colors.white70,
    textMuted: Colors.white38,
    textFaint: Colors.white24,
    textGhost: Colors.white12,
  );

  static const light = AppColors(
    bg: Color(0xFFF2F2F5),
    surface: Colors.white,
    surfaceHigh: Color(0xFFEAEAEF),
    border: Color(0xFFDCDCE2),
    textPrimary: Color(0xFF17171C),
    textSecondary: Color(0xB317171C),
    textMuted: Color(0x7317171C),
    textFaint: Color(0x4917171C),
    textGhost: Color(0x2417171C),
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceHigh,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textFaint,
    Color? textGhost,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      textGhost: textGhost ?? this.textGhost,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      textGhost: Color.lerp(textGhost, other.textGhost, t)!,
    );
  }
}

/// Atajo: `context.colors.bg` en vez de
/// `Theme.of(context).extension<AppColors>()!.bg`.
extension AppColorsX on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.dark;
}
