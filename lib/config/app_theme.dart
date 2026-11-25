import 'package:flutter/material.dart';

/// High-contrast, production-grade light/dark themes.
///
/// Every colour used by the admin control centre and the settings hub is
/// resolved from here, so the same screen stays crisp and legible on web,
/// Windows and mobile in both Day and Night mode.
abstract final class AppTheme {
  // ---------------------------------------------------------------------------
  // Day palette — crisp soft light surfaces, high-contrast slate ink.
  // ---------------------------------------------------------------------------
  static const Color dayCanvas = Color(0xFFF8FAFC);
  static const Color daySurface = Color(0xFFFFFFFF);
  static const Color daySurfaceAlt = Color(0xFFF1F5F9);
  static const Color dayInk = Color(0xFF0F172A);
  static const Color dayMuted = Color(0xFF475569);
  static const Color dayBorder = Color(0xFFE2E8F0);
  static const Color dayBrand = Color(0xFF0F766E);
  static const Color daySuccess = Color(0xFF15803D);
  static const Color dayWarning = Color(0xFFB45309);
  static const Color dayError = Color(0xFFDC2626);
  static const Color dayInfo = Color(0xFF1D4ED8);

  // ---------------------------------------------------------------------------
  // Night palette — deep slate/navy canvas, elevated cards, crisp light ink.
  // ---------------------------------------------------------------------------
  static const Color nightCanvas = Color(0xFF0B1120);
  static const Color nightSurface = Color(0xFF1E293B);
  static const Color nightSurfaceAlt = Color(0xFF111827);
  static const Color nightInk = Color(0xFFF8FAFC);
  static const Color nightMuted = Color(0xFFCBD5E1);
  static const Color nightBorder = Color(0xFF334155);
  static const Color nightBrand = Color(0xFF2DD4BF);
  static const Color nightSuccess = Color(0xFF4ADE80);
  static const Color nightWarning = Color(0xFFFBBF24);
  static const Color nightError = Color(0xFFF87171);
  static const Color nightInfo = Color(0xFF60A5FA);

  static const List<FontFeature> numericFeatures = [
    FontFeature.tabularFigures(),
  ];

  static ThemeMode themeModeFor(String preference) => switch (preference) {
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => ThemeMode.light,
  };

  static ThemeData get light => _build(isDark: false);
  static ThemeData get dark => _build(isDark: true);

  static ThemeData _build({required bool isDark}) {
    final Color canvas = isDark ? nightCanvas : dayCanvas;
    final Color surface = isDark ? nightSurface : daySurface;
    final Color ink = isDark ? nightInk : dayInk;
    final Color muted = isDark ? nightMuted : dayMuted;
    final Color border = isDark ? nightBorder : dayBorder;
    final Color brand = isDark ? nightBrand : dayBrand;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D9488),
          brightness: isDark ? Brightness.dark : Brightness.light,
          primary: brand,
          surface: surface,
          onSurface: ink,
          outline: border,
        ).copyWith(
          surfaceTint: Colors.transparent,
          surfaceContainerLowest: canvas,
          surfaceContainerLow: surface,
          surfaceContainer: surface,
          surfaceContainerHigh: surface,
          surfaceContainerHighest: isDark ? nightSurfaceAlt : daySurfaceAlt,
        );

    final textTheme = TextTheme(
      displaySmall: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: -0.4,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: -0.2,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleSmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 14, color: ink, height: 1.35),
      bodyMedium: TextStyle(fontSize: 13, color: muted, height: 1.35),
      bodySmall: TextStyle(fontSize: 12, color: muted, height: 1.3),
      labelLarge: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      labelMedium: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      fontFamily: AppTypography.latinFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: ink),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: isDark ? nightSurfaceAlt : dayBrand,
        foregroundColor: isDark ? ink : Colors.white,
        iconTheme: IconThemeData(color: isDark ? ink : Colors.white),
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: isDark ? ink : Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: brand,
        textColor: ink,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
      chipTheme:
          ChipThemeData.fromDefaults(
            primaryColor: brand,
            secondaryColor: muted,
            labelStyle: textTheme.labelMedium!.copyWith(color: ink),
          ).copyWith(
            side: WidgetStateBorderSide.resolveWith(
              (_) => BorderSide(color: border),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? nightSurfaceAlt : daySurfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: brand, width: 1.6),
        ),
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: muted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? nightSurface : dayInk,
        contentTextStyle: TextStyle(
          color: isDark ? nightInk : Colors.white,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: brand),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brand,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: brand),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: brand,
        unselectedItemColor: muted,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: muted,
        indicatorColor: brand,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? brand : border,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        selectedIconTheme: IconThemeData(color: brand),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: brand),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? nightSurfaceAlt : dayInk,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(
          color: isDark ? nightInk : Colors.white,
          fontSize: 12,
        ),
      ),
    );
  }

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color canvasOf(BuildContext context) =>
      isDark(context) ? nightCanvas : dayCanvas;

  static Color surfaceOf(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  static Color altSurfaceOf(BuildContext context) =>
      isDark(context) ? nightSurfaceAlt : daySurfaceAlt;

  static Color inkOf(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color mutedOf(BuildContext context) =>
      isDark(context) ? nightMuted : dayMuted;

  static Color borderOf(BuildContext context) =>
      isDark(context) ? nightBorder : dayBorder;

  static Color brandOf(BuildContext context) =>
      isDark(context) ? nightBrand : dayBrand;

  /// Soft tinted tile background that keeps the accent recognisable in both
  /// modes without ever washing out the label.
  static Color tileOf(BuildContext context, Color seed) =>
      seed.withValues(alpha: isDark(context) ? 0.18 : 0.10);

  /// Accent foreground adjusted for the background brightness.
  static Color tileInkOf(BuildContext context, Color seed) => Color.lerp(
    seed,
    isDark(context) ? Colors.white : Colors.black,
    isDark(context) ? 0.42 : 0.28,
  )!;

  static Color onAccentOf(BuildContext context) =>
      isDark(context) ? nightCanvas : Colors.white;

  static Color successOf(BuildContext context) =>
      isDark(context) ? nightSuccess : daySuccess;

  static Color warningOf(BuildContext context) =>
      isDark(context) ? nightWarning : dayWarning;

  static Color errorOf(BuildContext context) =>
      isDark(context) ? nightError : dayError;

  static Color infoOf(BuildContext context) =>
      isDark(context) ? nightInfo : dayInfo;

  /// Convenience helper for code that needs an on-surface foreground for a
  /// filled status chip/badge in either mode.
  static Color onStatusOf(BuildContext context) =>
      isDark(context) ? nightCanvas : Colors.white;
}

/// Typography tokens. The Bengali and Latin family names are declared in one
/// place so colors always come from the active [TextTheme]; when the matching
/// font files are not bundled Flutter gracefully falls back to the platform
/// font, which still inherits the same high-contrast text colors.
abstract final class AppTypography {
  static const String bengaliFamily = 'HindSiliguri';
  static const String latinFamily = 'PlusJakartaSans';
}
