import 'package:flutter/material.dart';

import 'bsheel_design.dart';

/// "Port" light theme — strict black & white, light grotesque type,
/// hairline rules. Same `AdminTheme.light` getter name as before so
/// `MaterialApp(theme: AdminTheme.light)` keeps working without edits.
abstract final class AdminTheme {
  static ThemeData get light {
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(BsheelRadii.md),
      borderSide: const BorderSide(
          color: BsheelColors.line, width: BsheelBorders.thin,),
    );

    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: BsheelColors.bg,
      canvasColor: BsheelColors.bg,
      colorScheme: const ColorScheme.light(
        primary: BsheelColors.ink,
        onPrimary: BsheelColors.pureWhite,
        secondary: BsheelColors.inkSoft,
        onSecondary: BsheelColors.pureWhite,
        tertiary: BsheelColors.inkMuted,
        error: BsheelColors.error,
        onError: BsheelColors.pureWhite,
        surface: BsheelColors.paper,
        onSurface: BsheelColors.ink,
        outline: BsheelColors.line,
      ),
      fontFamily: BsheelFonts.body,
      textTheme: const TextTheme(
        displayLarge: BsheelType.displayXl,
        displayMedium: BsheelType.displayLg,
        displaySmall: BsheelType.displayMd,
        headlineLarge: BsheelType.displayLg,
        headlineMedium: BsheelType.displayMd,
        headlineSmall: BsheelType.displaySm,
        titleLarge: BsheelType.displaySm,
        titleMedium: BsheelType.bodyMdBold,
        titleSmall: BsheelType.bodyMdBold,
        bodyLarge: BsheelType.bodyLg,
        bodyMedium: BsheelType.bodyMd,
        bodySmall: BsheelType.bodySm,
        labelLarge: BsheelType.labelLg,
        labelMedium: BsheelType.labelMd,
        labelSmall: BsheelType.labelSm,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: BsheelColors.bg,
        foregroundColor: BsheelColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: BsheelType.displaySm,
        iconTheme: IconThemeData(color: BsheelColors.ink),
      ),
      cardTheme: CardThemeData(
        color: BsheelColors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.lg),
          side: const BorderSide(
              color: BsheelColors.line, width: BsheelBorders.thin,),
        ),
        margin: EdgeInsets.zero,
      ),
      // Primary action: solid black pill, white text — inversion is the accent.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BsheelColors.ink,
          foregroundColor: BsheelColors.pureWhite,
          textStyle: const TextStyle(
            fontFamily: BsheelFonts.body,
            fontWeight: FontWeight.w400,
            fontSize: 13,
            letterSpacing: 1.0,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BsheelRadii.full),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BsheelColors.ink,
          textStyle: const TextStyle(
            fontFamily: BsheelFonts.body,
            fontWeight: FontWeight.w400,
            fontSize: 13,
            letterSpacing: 1.0,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BsheelRadii.full),
          ),
          side: const BorderSide(
              color: BsheelColors.ink, width: BsheelBorders.thin,),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: BsheelColors.ink),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: BsheelColors.ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BsheelColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          borderSide: const BorderSide(color: BsheelColors.ink, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          borderSide: const BorderSide(color: BsheelColors.hot, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          borderSide: const BorderSide(color: BsheelColors.hot, width: 1),
        ),
        hintStyle: BsheelType.bodyMd.copyWith(color: BsheelColors.inkMuted),
        labelStyle: BsheelType.labelMd.copyWith(color: BsheelColors.inkSoft),
        errorStyle: BsheelType.bodySm.copyWith(color: BsheelColors.hot),
      ),
      dividerTheme: const DividerThemeData(
        color: BsheelColors.line,
        thickness: 1,
        space: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: BsheelColors.ink,
        contentTextStyle:
            BsheelType.bodyMd.copyWith(color: BsheelColors.pureWhite),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: BsheelColors.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.xl),
          side: const BorderSide(
              color: BsheelColors.line, width: BsheelBorders.thin,),
        ),
        titleTextStyle: BsheelType.displaySm,
        contentTextStyle: BsheelType.bodyMd,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: BsheelColors.ink,
      ),
      iconTheme: const IconThemeData(color: BsheelColors.ink),
      tabBarTheme: const TabBarThemeData(
        labelColor: BsheelColors.ink,
        unselectedLabelColor: BsheelColors.inkMuted,
        indicatorColor: BsheelColors.ink,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: BsheelColors.line,
        labelStyle: BsheelType.labelLg,
        unselectedLabelStyle: BsheelType.labelLg,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: BsheelColors.surface,
        selectedColor: BsheelColors.ink,
        labelStyle: BsheelType.labelMd,
        side: const BorderSide(
            color: BsheelColors.line, width: BsheelBorders.thin,),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.full),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: BsheelColors.ink,
        textColor: BsheelColors.ink,
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}
