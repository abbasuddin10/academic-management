import 'package:academy_management/controllers/app_state_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Small, always-available AppBar button that flips Day/Night mode instantly.
/// Persistence is handled by AppStateController; failures are swallowed so the
/// current screen can never be broken by a toggle tap.
class ThemeModeToggle extends StatelessWidget {
  final Color? color;
  final String? tooltip;
  final bool showSystemOptionOnLongPress;

  const ThemeModeToggle({
    super.key,
    this.color,
    this.tooltip,
    this.showSystemOptionOnLongPress = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: tooltip ?? (isDark ? 'Day mode' : 'Night mode'),
      color: color ?? Theme.of(context).iconTheme.color,
      icon: Icon(isDark ? Icons.wb_sunny_rounded : Icons.dark_mode_rounded),
      onPressed: () => _toggle(isDark),
      onLongPress: showSystemOptionOnLongPress ? _useSystem : null,
    );
  }

  Future<void> _toggle(bool isDark) async {
    if (!Get.isRegistered<AppStateController>()) return;
    try {
      await AppStateController.to.setThemePreference(isDark ? 'light' : 'dark');
    } catch (_) {
      // The reactive value is already updated in the controller; a storage
      // failure must not surface as an unhandled async exception.
    }
  }

  Future<void> _useSystem() async {
    if (!Get.isRegistered<AppStateController>()) return;
    try {
      await AppStateController.to.setThemePreference('system');
    } catch (_) {
      // Ignore best-effort persistence failures.
    }
  }
}
