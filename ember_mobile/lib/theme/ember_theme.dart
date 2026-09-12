import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EmberColors {
  EmberColors._();

  // Surface & Foundations
  static const Color obsidianBase = Color(0xFF0B0907);
  static const Color surface = Color(0xFF151310);
  static const Color surfaceContainerLow = Color(0xFF1E1B18);
  static const Color surfaceContainer = Color(0xFF221F1C);
  static const Color surfaceContainerHigh = Color(0xFF2C2927);
  static const Color surfaceContainerHighest = Color(0xFF373431);

  // Warm Amber & Gold Accents
  static const Color primaryAmber = Color(0xFFF59E0B);
  static const Color primaryAmberHi = Color(0xFFFFC174);
  static const Color secondaryHoney = Color(0xFFD97706);
  static const Color tertiaryGold = Color(0xFFFBBF24);

  // Text & Content Hierarchy
  static const Color textPrimary = Color(0xFFFFFBEB);
  static const Color textSecondary = Color(0xFFD5C7B5);
  static const Color textMuted = Color(0xFF7C6E5F);

  // System & Borders
  static const Color outline = Color(0xFF534434);
  static const Color outlineVariant = Color(0xFF3E3326);
  static const Color error = Color(0xFFE05252);
}

class EmberTheme {
  EmberTheme._();

  static ThemeData get darkTheme => buildTheme(useGoogleFonts: true);

  static ThemeData buildTheme({bool useGoogleFonts = true}) {
    TextTheme mergedTextTheme;
    if (useGoogleFonts) {
      try {
        final baseTextTheme = Typography.material2021().white;

        final headlineFont = GoogleFonts.soraTextTheme(baseTextTheme);
        final bodyFont = GoogleFonts.plusJakartaSansTextTheme(baseTextTheme);
        final labelFont = GoogleFonts.spaceGroteskTextTheme(baseTextTheme);

        mergedTextTheme = bodyFont.copyWith(
          displayLarge: headlineFont.displayLarge?.copyWith(color: EmberColors.textPrimary, fontWeight: FontWeight.bold),
          displayMedium: headlineFont.displayMedium?.copyWith(color: EmberColors.textPrimary, fontWeight: FontWeight.bold),
          displaySmall: headlineFont.displaySmall?.copyWith(color: EmberColors.textPrimary, fontWeight: FontWeight.bold),
          headlineLarge: headlineFont.headlineLarge?.copyWith(color: EmberColors.textPrimary, fontWeight: FontWeight.w700),
          headlineMedium: headlineFont.headlineMedium?.copyWith(color: EmberColors.textPrimary, fontWeight: FontWeight.w700),
          headlineSmall: headlineFont.headlineSmall?.copyWith(color: EmberColors.textPrimary, fontWeight: FontWeight.w600),
          titleLarge: headlineFont.titleLarge?.copyWith(color: EmberColors.textPrimary, fontWeight: FontWeight.w600),
          titleMedium: headlineFont.titleMedium?.copyWith(color: EmberColors.textPrimary, fontWeight: FontWeight.w500),
          titleSmall: headlineFont.titleSmall?.copyWith(color: EmberColors.textSecondary, fontWeight: FontWeight.w500),
          bodyLarge: bodyFont.bodyLarge?.copyWith(color: EmberColors.textPrimary),
          bodyMedium: bodyFont.bodyMedium?.copyWith(color: EmberColors.textSecondary),
          bodySmall: bodyFont.bodySmall?.copyWith(color: EmberColors.textMuted),
          labelLarge: labelFont.labelLarge?.copyWith(color: EmberColors.textPrimary, fontWeight: FontWeight.w600),
          labelMedium: labelFont.labelMedium?.copyWith(color: EmberColors.textSecondary),
          labelSmall: labelFont.labelSmall?.copyWith(color: EmberColors.textMuted, letterSpacing: 0.5),
        );
      } catch (_) {
        mergedTextTheme = const TextTheme();
      }
    } else {
      mergedTextTheme = const TextTheme();
    }

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: EmberColors.obsidianBase,
      canvasColor: EmberColors.surface,
      cardColor: EmberColors.surfaceContainerLow,
      dividerColor: EmberColors.outlineVariant,
      colorScheme: const ColorScheme.dark(
        surface: EmberColors.surface,
        primary: EmberColors.primaryAmber,
        secondary: EmberColors.secondaryHoney,
        tertiary: EmberColors.tertiaryGold,
        error: EmberColors.error,
        onSurface: EmberColors.textPrimary,
        onPrimary: EmberColors.obsidianBase,
      ),
      textTheme: mergedTextTheme,
      iconTheme: const IconThemeData(color: EmberColors.textSecondary, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: mergedTextTheme.titleMedium?.copyWith(
          color: EmberColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: EmberColors.textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: EmberColors.primaryAmber,
          foregroundColor: EmberColors.obsidianBase,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: mergedTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
