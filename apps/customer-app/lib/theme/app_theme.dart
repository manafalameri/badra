import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Brand Colors ──────────────────────────────────────────
  static const Color backgroundDeep = Color(0xFF060D0A);
  static const Color backgroundMid = Color(0xFF0A1510);
  static const Color surfaceDark = Color(0xFF0D1F18);
  static const Color surfaceCard = Color(0xFF112318);
  static const Color surfaceGlass = Color(0x33142B22);

  static const Color emeraldPrimary = Color(0xFF00C853);
  static const Color emeraldDark = Color(0xFF1A4731);
  static const Color emeraldMuted = Color(0xFF2E5C3E);
  static const Color emeraldGlow = Color(0x4400C853);

  static const Color goldAccent = Color(0xFFFFD700);
  static const Color goldMuted = Color(0xFFB8960C);
  static const Color silverAccent = Color(0xFFB0BEC5);

  static const Color textPrimary = Color(0xFFF0F7F4);
  static const Color textSecondary = Color(0xFF8BA898);
  static const Color textMuted = Color(0xFF4A6741);

  static const Color success = Color(0xFF00C853);
  static const Color warning = Color(0xFFFFB300);
  static const Color error = Color(0xFFEF5350);
  static const Color incoming = Color(0xFF00E676);
  static const Color outgoing = Color(0xFFECEFF1);

  static const Color borderGlass = Color(0x2200C853);
  static const Color borderGlow = Color(0x8800C853);

  // ── Light Theme (required by framework) ───────────────────
  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  // ── Dark Theme (primary) ──────────────────────────────────
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = isDark
        ? const ColorScheme.dark(
            primary: emeraldPrimary,
            primaryContainer: emeraldDark,
            secondary: goldAccent,
            secondaryContainer: Color(0xFF2A2000),
            surface: surfaceCard,
            error: error,
            onPrimary: backgroundDeep,
            onSecondary: backgroundDeep,
            onSurface: textPrimary,
            onError: textPrimary,
            outline: emeraldMuted,
            outlineVariant: Color(0xFF1E3D2A),
            inverseSurface: textPrimary,
            onInverseSurface: backgroundDeep,
            surfaceContainerHighest: Color(0xFF142B22),
          )
        : ColorScheme.fromSeed(
            seedColor: emeraldPrimary,
            brightness: Brightness.light,
          );

    final textTheme = GoogleFonts.soraTextTheme(
      TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: isDark ? textPrimary : Colors.black87,
          letterSpacing: -0.5,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: isDark ? textPrimary : Colors.black87,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: isDark ? textPrimary : Colors.black87,
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: isDark ? textPrimary : Colors.black87,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: isDark ? textPrimary : Colors.black87,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? textPrimary : Colors.black87,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: isDark ? textPrimary : Colors.black87,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isDark ? textPrimary : Colors.black87,
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? textSecondary : Colors.black54,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: isDark ? textPrimary : Colors.black87,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: isDark ? textSecondary : Colors.black54,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: isDark ? textMuted : Colors.black38,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark ? textPrimary : Colors.black87,
          letterSpacing: 0.5,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isDark ? textSecondary : Colors.black54,
          letterSpacing: 0.3,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: isDark ? textMuted : Colors.black38,
          letterSpacing: 0.4,
        ),
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: isDark
          ? backgroundDeep
          : const Color(0xFFF5F5F5),
      appBarTheme: AppBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: isDark ? textPrimary : Colors.black87),
      ),
      cardTheme: CardThemeData(
        color: isDark ? surfaceCard : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: isDark ? surfaceGlass : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: emeraldMuted, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: emeraldMuted.withAlpha(128), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: emeraldPrimary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 1.5),
        ),
        labelStyle: TextStyle(
          color: isDark ? textSecondary : Colors.black54,
          fontFamily: GoogleFonts.sora().fontFamily,
          fontSize: 13,
        ),
        hintStyle: TextStyle(
          color: isDark ? textMuted : Colors.black38,
          fontFamily: GoogleFonts.sora().fontFamily,
          fontSize: 13,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: emeraldPrimary,
          foregroundColor: backgroundDeep,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: TextStyle(
            fontFamily: GoogleFonts.sora().fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: emeraldPrimary,
        unselectedItemColor: textMuted,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? borderGlass : Colors.black12,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? surfaceGlass : Colors.white,
        selectedColor: emeraldDark,
        labelStyle: TextStyle(
          fontFamily: GoogleFonts.sora().fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        side: BorderSide(color: isDark ? emeraldMuted : Colors.black12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
