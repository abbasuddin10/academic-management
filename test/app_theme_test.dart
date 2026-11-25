import 'package:academy_management/config/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme mode mapping', () {
    test('maps stored preferences to ThemeMode', () {
      expect(AppTheme.themeModeFor('light'), ThemeMode.light);
      expect(AppTheme.themeModeFor('dark'), ThemeMode.dark);
      expect(AppTheme.themeModeFor('system'), ThemeMode.system);
      expect(AppTheme.themeModeFor('unknown'), ThemeMode.light);
    });
  });

  group('Day / Night contrast contract', () {
    test('light theme uses soft light surfaces with dark ink', () {
      final theme = AppTheme.light;
      expect(theme.scaffoldBackgroundColor, AppTheme.dayCanvas);
      expect(theme.colorScheme.surface, AppTheme.daySurface);
      expect(theme.colorScheme.onSurface, AppTheme.dayInk);
      expect(theme.appBarTheme.foregroundColor, Colors.white);
    });

    test('dark theme uses deep slate surfaces with crisp light ink', () {
      final theme = AppTheme.dark;
      expect(theme.scaffoldBackgroundColor, AppTheme.nightCanvas);
      expect(theme.colorScheme.surface, AppTheme.nightSurface);
      expect(theme.colorScheme.onSurface, AppTheme.nightInk);
      expect(theme.appBarTheme.foregroundColor, AppTheme.nightInk);
    });

    test('status tokens stay legible in both modes', () {
      expect(AppTheme.daySuccess, isNot(AppTheme.dayCanvas));
      expect(AppTheme.nightSuccess, isNot(AppTheme.nightCanvas));
      expect(AppTheme.dayError, isNot(AppTheme.daySurface));
      expect(AppTheme.nightError, isNot(AppTheme.nightSurface));
    });

    test('typography families are declared centrally', () {
      expect(AppTypography.bengaliFamily, 'HindSiliguri');
      expect(AppTypography.latinFamily, 'PlusJakartaSans');
    });

    test('tabular figure feature is available for numeric summaries', () {
      expect(AppTheme.numericFeatures, isNotEmpty);
      expect(AppTheme.numericFeatures.first.toString(), contains('tnum'));
    });
  });
}
