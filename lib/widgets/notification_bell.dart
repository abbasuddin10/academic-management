import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/controllers/app_state_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Messenger-style notification bell driven entirely by the shared reactive
/// unread counter, so every screen stays in sync without manual setState.
class NotificationBell extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final Color? color;
  final Color badgeColor;
  final String? tooltip;

  const NotificationBell({
    super.key,
    required this.onTap,
    this.icon = Icons.notifications,
    this.color,
    this.badgeColor = Colors.red,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final count = AppStateController.to.unreadTotalCount;
      return Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          IconButton(
            icon: Icon(icon, color: color, size: 26),
            tooltip: tooltip ?? 'Notifications',
            onPressed: onTap,
          ),
          Positioned(
            right: 5,
            top: 5,
            child: AnimatedSwitcher(
              duration: Duration(milliseconds: 220),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: count > 0
                  ? Container(
                      key: ValueKey<int>(count),
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.surfaceOf(context),
                          width: 1.5,
                        ),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        count > 9 ? '9+' : '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey<String>('hidden')),
            ),
          ),
        ],
      );
    });
  }
}
