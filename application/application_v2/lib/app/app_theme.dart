import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// CHARGE LINK design tokens.
///
/// Direction: an instrument panel, not a consumer app skin. Telemetry is
/// the content, so numbers get a dedicated monospace voice with tabular
/// figures, set apart from the plain-language UI chrome around them.
///
///   Background   #0F1214  near-black graphite, not pure black
///   Surface      #171B1F  card surface
///   Hairline     #262B30  dividers / borders
///   Text primary #EDEFF1
///   Text muted   #8A9199
///   Copper       #E8A33D  actively drawing current (the "hot" state)
///   Teal         #4FB7B0  path enabled, standing by (the "cool" state)
///   Danger       #E5484D  errors, disconnects, limit-hit stop
class AppColors {
  const AppColors._();

  static const background = Color(0xFF0F1214);
  static const surface = Color(0xFF171B1F);
  static const surfaceRaised = Color(0xFF1D2226);
  static const hairline = Color(0xFF262B30);
  static const textPrimary = Color(0xFFEDEFF1);
  static const textMuted = Color(0xFF8A9199);
  static const copper = Color(0xFFE8A33D);
  static const teal = Color(0xFF4FB7B0);
  static const danger = Color(0xFFE5484D);
}

class AppTheme {
  const AppTheme._();

  static TextStyle get _display => GoogleFonts.inter(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get _body => GoogleFonts.inter(
        color: AppColors.textPrimary,
      );

  /// Telemetry / readout voice — used for every live number in the app.
  static TextStyle telemetry({
    double size = 28,
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w500,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        color: color,
        fontWeight: weight,
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: -0.5,
      );

  static ThemeData get dark {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.background,
        primary: AppColors.copper,
        secondary: AppColors.teal,
        error: AppColors.danger,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineSmall: _display.copyWith(fontSize: 22),
        titleMedium: _display.copyWith(fontSize: 16),
        bodyMedium: _body.copyWith(fontSize: 14, color: AppColors.textMuted),
        labelSmall: _body.copyWith(
          fontSize: 11,
          color: AppColors.textMuted,
          letterSpacing: 1.1,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: AppColors.hairline),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.copper,
          foregroundColor: const Color(0xFF1A1204),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: _display.copyWith(fontSize: 15, color: null),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.hairline),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.hairline),
    );
  }
}
