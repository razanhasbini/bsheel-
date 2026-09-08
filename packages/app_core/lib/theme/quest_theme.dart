import 'package:flutter/material.dart';
import 'quest_colors.dart';
import 'quest_typography.dart';
import 'quest_spacing.dart';

/// Arcade Pop theme — light (cream bg, ink outlines, violet/gold accents).
/// This is the app's only theme; reskin via quest_colors.dart /
/// quest_typography.dart / quest_spacing.dart.
/// All fonts are bundled locally; do NOT wrap text themes with google_fonts.
abstract final class QuestTheme {
  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: QuestColors.osBg,
        colorScheme: const ColorScheme.light(
          primary: QuestColors.osPrimary,
          onPrimary: QuestColors.osTextOnPrimary,
          secondary: QuestColors.osAccent,
          onSecondary: QuestColors.osAccentInk,
          tertiary: QuestColors.osCool,
          error: QuestColors.osRed,
          surface: QuestColors.osCard,
          onSurface: QuestColors.osTextPrimary,
          outline: QuestColors.osBorderStrong,
        ),
        textTheme: TextTheme(
          displayLarge: QuestTypography.osDisplayLarge,
          displayMedium: QuestTypography.osDisplayMedium,
          displaySmall: QuestTypography.osDisplaySmall,
          headlineLarge: QuestTypography.osHeadlineLarge,
          headlineMedium: QuestTypography.osHeadlineMedium,
          headlineSmall: QuestTypography.osHeadlineSmall,
          bodyLarge: QuestTypography.osBodyLarge,
          bodyMedium: QuestTypography.osBodyMedium,
          bodySmall: QuestTypography.osBodySmall,
          labelLarge: QuestTypography.osLabelLarge,
          labelMedium: QuestTypography.osLabelMedium,
          labelSmall: QuestTypography.osLabelSmall,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: QuestColors.osBg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: QuestTypography.osHeadlineMedium,
          iconTheme: const IconThemeData(color: QuestColors.osTextPrimary),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: QuestColors.osCard,
          selectedItemColor: QuestColors.osPrimary,
          unselectedItemColor: QuestColors.osTextMuted,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: QuestColors.osCard,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
            side: const BorderSide(color: QuestColors.osBorderStrong, width: 2),
          ),
          margin: EdgeInsets.zero,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: QuestColors.osAccent,
            foregroundColor: QuestColors.osAccentInk,
            textStyle: QuestTypography.osButtonText.copyWith(
              color: QuestColors.osAccentInk,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: QuestSpacing.lg,
              vertical: QuestSpacing.md,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
              side: const BorderSide(
                color: QuestColors.osBorderStrong,
                width: 2,
              ),
            ),
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: QuestColors.osTextPrimary,
            textStyle: QuestTypography.osButtonText,
            padding: const EdgeInsets.symmetric(
              horizontal: QuestSpacing.lg,
              vertical: QuestSpacing.md,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
            ),
            side: const BorderSide(
              color: QuestColors.osBorderStrong,
              width: 2,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: QuestColors.osPrimary),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: QuestColors.osCard,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: QuestSpacing.md,
            vertical: QuestSpacing.md,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
            borderSide: const BorderSide(
              color: QuestColors.osBorderStrong,
              width: 2,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
            borderSide: const BorderSide(
              color: QuestColors.osBorderStrong,
              width: 2,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
            borderSide: const BorderSide(
              color: QuestColors.osPrimary,
              width: 2.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
            borderSide: const BorderSide(color: QuestColors.osRed, width: 2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
            borderSide: const BorderSide(color: QuestColors.osRed, width: 2.5),
          ),
          hintStyle: QuestTypography.osBodyMedium.copyWith(
            color: QuestColors.osTextMuted,
          ),
          labelStyle: QuestTypography.osLabelMedium,
          errorStyle:
              QuestTypography.osBodySmall.copyWith(color: QuestColors.osRed),
        ),
        dividerTheme: const DividerThemeData(
          color: QuestColors.osBorder,
          thickness: 1,
          space: 0,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: QuestColors.osTextPrimary,
          contentTextStyle: QuestTypography.osBodyMedium.copyWith(
            color: QuestColors.pureWhite,
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
          ),
        ),
      );
}
