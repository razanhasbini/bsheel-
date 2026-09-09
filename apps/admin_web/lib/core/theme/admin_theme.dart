import 'package:flutter/material.dart';

import 'bsheel_design.dart';

/// Arcade Pop light theme for the admin console — cream ground, 2px ink
/// outlines, hard offset shadows, Syne / DM Sans / JetBrains Mono.
///
/// The `AdminTheme.light` getter name is unchanged so
/// `MaterialApp(theme: AdminTheme.light)` keeps working.
///
/// Material's own components can't draw a hard offset shadow, so anything
/// that needs one uses the primitives in `shared/widgets/bsheel_widgets.dart`.
/// This theme covers the defaults: colours, type, borders and radii.
abstract final class AdminTheme {
  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(BsheelRadii.md),
        borderSide: BorderSide(color: color, width: BsheelBorders.thick),
      );

  static ThemeData get light {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: BsheelColors.bg,
      canvasColor: BsheelColors.bg,
      colorScheme: const ColorScheme.light(
        primary: BsheelColors.primary,
        onPrimary: BsheelColors.pureWhite,
        secondary: BsheelColors.accent,
        // Gold takes ink, never white — see the contrast rule.
        onSecondary: BsheelColors.accentInk,
        tertiary: BsheelColors.cool,
        onTertiary: BsheelColors.ink,
        error: BsheelColors.danger,
        onError: BsheelColors.ink,
        surface: BsheelColors.card,
        onSurface: BsheelColors.ink,
        surfaceContainer: BsheelColors.surface,
        outline: BsheelColors.ink,
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
        titleMedium: BsheelType.titleMd,
        titleSmall: BsheelType.titleSm,
        bodyLarge: BsheelType.bodyLg,
        bodyMedium: BsheelType.bodyMd,
        bodySmall: BsheelType.bodySm,
        labelLarge: BsheelType.labelLg,
        labelMedium: BsheelType.labelMd,
        labelSmall: BsheelType.labelSm,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: BsheelColors.surface,
        foregroundColor: BsheelColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: BsheelType.displayMd,
        iconTheme: IconThemeData(color: BsheelColors.ink),
      ),
      cardTheme: CardThemeData(
        color: BsheelColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.lg),
          side: BsheelBorders.inkSide,
        ),
        margin: EdgeInsets.zero,
      ),
      // Primary action: violet fill, white label, ink outline. The hard
      // shadow comes from BsheelButton, which pages should prefer.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BsheelColors.primary,
          foregroundColor: BsheelColors.pureWhite,
          disabledBackgroundColor: BsheelColors.surface,
          disabledForegroundColor: BsheelColors.inkMuted,
          textStyle: BsheelType.buttonMd,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          minimumSize: const Size(0, BsheelLayout.minTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BsheelRadii.md),
            side: BsheelBorders.inkSide,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: BsheelColors.surface,
          foregroundColor: BsheelColors.ink,
          textStyle: BsheelType.buttonSm,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          minimumSize: const Size(0, BsheelLayout.minTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BsheelRadii.md),
          ),
          side: BsheelBorders.inkSide,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: BsheelColors.primary,
          textStyle: BsheelType.labelMd.copyWith(color: BsheelColors.primary),
          minimumSize: const Size(0, BsheelLayout.minTarget),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: BsheelColors.ink,
          minimumSize: const Size(
            BsheelLayout.minTarget,
            BsheelLayout.minTarget,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BsheelColors.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 14,
        ),
        border: _border(BsheelColors.ink),
        enabledBorder: _border(BsheelColors.ink),
        // Focus recolours the border to violet; the matching coloured
        // shadow is drawn by BsheelTextField.
        focusedBorder: _border(BsheelColors.primary),
        errorBorder: _border(BsheelColors.danger),
        focusedErrorBorder: _border(BsheelColors.danger),
        disabledBorder: _border(BsheelColors.inkMuted),
        hintStyle: BsheelType.bodySm.copyWith(color: BsheelColors.inkMuted),
        labelStyle: BsheelType.labelMd,
        floatingLabelStyle: BsheelType.labelMd.copyWith(
          color: BsheelColors.primary,
        ),
        // One line beneath the field, never a tooltip.
        errorStyle: BsheelType.bodyXs.copyWith(
          color: BsheelColors.dangerText,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: BsheelColors.rowLine,
        thickness: BsheelBorders.hairline,
        space: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: BsheelColors.ink,
        contentTextStyle: BsheelType.bodySm.copyWith(
          color: BsheelColors.inkPanelTextStrong,
        ),
        actionTextColor: BsheelColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          side: BsheelBorders.inkSide,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: BsheelColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.lg),
          side: BsheelBorders.inkSide,
        ),
        titleTextStyle: BsheelType.displaySm,
        contentTextStyle: BsheelType.bodySm.copyWith(
          color: BsheelColors.inkSoft,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: BsheelColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          side: BsheelBorders.inkSide,
        ),
        textStyle: BsheelType.bodySm,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: BsheelColors.ink,
          borderRadius: BorderRadius.circular(BsheelRadii.sm),
        ),
        textStyle: BsheelType.labelSm.copyWith(
          color: BsheelColors.inkPanelTextStrong,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: BsheelColors.primary,
        linearTrackColor: BsheelColors.skeleton,
        circularTrackColor: BsheelColors.skeleton,
      ),
      iconTheme: const IconThemeData(color: BsheelColors.ink, size: 20),
      tabBarTheme: const TabBarThemeData(
        labelColor: BsheelColors.ink,
        unselectedLabelColor: BsheelColors.inkSoft,
        indicatorColor: BsheelColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: BsheelColors.rowLine,
        labelStyle: BsheelType.labelLg,
        unselectedLabelStyle: BsheelType.labelLg,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: BsheelColors.card,
        selectedColor: BsheelColors.ink,
        labelStyle: BsheelType.labelSm.copyWith(color: BsheelColors.ink),
        secondaryLabelStyle: BsheelType.labelSm.copyWith(
          color: BsheelColors.pureWhite,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        side: BsheelBorders.inkSide,
        shape: const StadiumBorder(),
        showCheckmark: false,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(BsheelColors.bg),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BsheelColors.success
              : BsheelColors.lavender,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(BsheelColors.ink),
        trackOutlineWidth: const WidgetStatePropertyAll(BsheelBorders.thick),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BsheelColors.primary
              : BsheelColors.card,
        ),
        checkColor: const WidgetStatePropertyAll(BsheelColors.pureWhite),
        side: BsheelBorders.inkSide,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.fill),
        ),
      ),
      radioTheme: const RadioThemeData(
        fillColor: WidgetStatePropertyAll(BsheelColors.ink),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: BsheelColors.ink,
        textColor: BsheelColors.ink,
        titleTextStyle: BsheelType.bodySmMedium,
        subtitleTextStyle: BsheelType.bodyXs,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          BsheelColors.ink.withValues(alpha: 0.35),
        ),
        radius: const Radius.circular(BsheelRadii.full),
        thickness: const WidgetStatePropertyAll(8),
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
  }
}
