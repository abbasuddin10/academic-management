import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/controllers/app_state_controller.dart';
import 'package:academy_management/models/academy.dart';
import 'package:academy_management/repositories/academy_repository.dart';
import 'package:academy_management/services/app_actions.dart';
import 'package:academy_management/services/session_service.dart';
import 'package:academy_management/views/auth/login_view.dart';
import 'package:academy_management/views/privacy_policy_view.dart';
import 'package:academy_management/views/admin/developer_profile_view.dart';
import 'package:academy_management/widgets/theme_mode_toggle.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Modern, responsive control hub for appearance, language, notifications,
/// security and app information. Every value is driven by AppStateController so
/// changes apply instantly and survive restarts.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final AppStateController _appState;
  final AcademyRepository _academyRepository = AcademyRepository();

  Future<Academy?>? _academyFuture;
  PackageInfo? _packageInfo;

  bool get _english => _appState.isEnglish.value;

  @override
  void initState() {
    super.initState();
    // Never assume the controller was registered by a previous screen.
    _appState = Get.isRegistered<AppStateController>()
        ? Get.find<AppStateController>()
        : Get.put(AppStateController(), permanent: true);
    _academyFuture = _loadAcademy();
    _loadPackageInfo();
  }

  /// Runs an async action without ever letting an exception escape into the
  /// Flutter framework. User gets a friendly message instead of a crash.
  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      _showError(
        _english
            ? 'That action could not be completed. Please try again.'
            : 'এই কাজটি সম্পন্ন করা যায়নি। আবার চেষ্টা করুন।',
      );
    }
  }

  /// Same guard for synchronous route/dialog pushes.
  void _safeTap(void Function() action) {
    try {
      action();
    } catch (_) {
      _showError(
        _english
            ? 'This option is not available right now.'
            : 'এই অপশনটি এখন উপলব্ধ নয়।',
      );
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    Get.snackbar(
      _english ? 'Notice' : 'তথ্য',
      message,
      backgroundColor: Colors.orange.shade700,
      colorText: Colors.white,
    );
  }

  Future<Academy?> _loadAcademy() async {
    final tenant = _appState.academyId.value;
    if (tenant == null || tenant.isEmpty) return null;
    try {
      return await _academyRepository.fetchById(tenant);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _packageInfo = info);
    } catch (_) {
      // Keep the fallback version label if platform info is unavailable.
    }
  }

  Future<void> _refresh() => _safe(() async {
    await _appState.refreshUnreadNoticeCount();
    if (!mounted) return;
    setState(() => _academyFuture = _loadAcademy());
    Get.snackbar(
      _english ? 'Refreshed' : 'রিফ্রেশ সম্পন্ন',
      _english
          ? 'Settings and live notification status are up to date.'
          : 'সেটিংস ও লাইভ নোটিফিকেশন স্ট্যাটাস আপ টু ডেট।',
    );
  });

  Future<void> _logout() => _safe(() async {
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: Text(_english ? 'Sign out?' : 'লগআউট করবেন?'),
        content: Text(
          _english
              ? 'You will need to sign in again to access this account.'
              : 'এই অ্যাকাউন্টে প্রবেশ করতে আবার লগইন করতে হবে।',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text(_english ? 'Cancel' : 'বাতিল'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Get.back(result: true),
            child: Text(_english ? 'Sign out' : 'লগআউট'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await SessionService.signOut();
    if (mounted) Get.offAll(() => const LoginView());
  });

  @override
  Widget build(BuildContext context) => Obx(() => _buildScaffold(context));

  Widget _buildScaffold(BuildContext context) {
    final theme = Theme.of(context);
    final sections = <Widget>[
      _appearanceSection(theme),
      _languageSection(theme),
      _instituteSection(theme),
      _notificationSection(theme),
      _securitySection(theme),
      _appInfoSection(theme),
    ];

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        title: Text(
          _english ? 'Settings' : 'সেটিংস',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          const ThemeModeToggle(),
          IconButton(
            tooltip: _english ? 'Refresh' : 'রিফ্রেশ',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          if (wide) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: sections.take(3).map(_withSpacing).toList(),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      children: sections.skip(3).map(_withSpacing).toList(),
                    ),
                  ),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: sections.map(_withSpacing).toList()),
          );
        },
      ),
    );
  }

  Widget _withSpacing(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 16), child: child);

  Widget _section({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: AppTheme.tileOf(context, AppTheme.brandOf(context)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: AppTheme.brandOf(context)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppTheme.borderOf(context)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _appearanceSection(ThemeData theme) => Obx(() {
    final current = _appState.themePreference.value;
    return _section(
      context: context,
      icon: Icons.brightness_6_rounded,
      title: _english ? 'Appearance & Theme' : 'অ্যাপের চেহারা ও থিম',
      subtitle: _english
          ? 'Choose a high-contrast theme that suits your workspace.'
          : 'আপনার কাজের জন্য উপযোগী হাই-কন্ট্রাস্ট থিম বেছে নিন।',
      children: [
        _choiceTile(
          icon: Icons.wb_sunny_rounded,
          title: _english ? 'Day Mode' : 'লাইট / দিন',
          subtitle: _english
              ? 'Bright, soft white surfaces'
              : 'উজ্জ্বল, নরম সাদা পৃষ্ঠা',
          selected: current == 'light',
          accent: const Color(0xFFF59E0B),
          onTap: () => _safe(() => _appState.setThemePreference('light')),
        ),
        _choiceTile(
          icon: Icons.nightlight_round,
          title: _english ? 'Night Mode' : 'ডার্ক / রাত',
          subtitle: _english
              ? 'Deep slate with crisp light text'
              : 'গাঢ় স্লেট with পরিষ্কার উজ্জ্বল টেক্সট',
          selected: current == 'dark',
          accent: const Color(0xFF6366F1),
          onTap: () => _safe(() => _appState.setThemePreference('dark')),
        ),
        _choiceTile(
          icon: Icons.brightness_auto_rounded,
          title: _english ? 'Use system theme' : 'সিস্টেম থিম ব্যবহার করুন',
          subtitle: _english
              ? 'Follow your device appearance setting'
              : 'আপনার ডিভাইসের সেটিং অনুসরণ করবে',
          selected: current == 'system',
          accent: const Color(0xFF0EA5E9),
          onTap: () => _safe(() => _appState.setThemePreference('system')),
        ),
      ],
    );
  });

  Widget _languageSection(ThemeData theme) => Obx(() {
    final english = _appState.isEnglish.value;
    return _section(
      context: context,
      icon: Icons.language_rounded,
      title: _english ? 'Language' : 'ভাষা',
      subtitle: _english
          ? 'Applies instantly across the whole app.'
          : 'পুরো অ্যাপে তাৎক্ষণিকভাবে প্রয়োগ হয়।',
      children: [
        _choiceTile(
          icon: Icons.translate_rounded,
          title: 'বাংলা',
          subtitle: _english ? 'Bengali interface' : 'বাংলা ইন্টারফেস',
          selected: !english,
          accent: const Color(0xFF0D9488),
          badge: english ? null : 'ACTIVE',
          onTap: () => _safe(() => _appState.setEnglish(false)),
        ),
        _choiceTile(
          icon: Icons.abc_rounded,
          title: 'English',
          subtitle: _english ? 'English interface' : 'ইংরেজি ইন্টারফেস',
          selected: english,
          accent: const Color(0xFF2563EB),
          badge: english ? 'ACTIVE' : null,
          onTap: () => _safe(() => _appState.setEnglish(true)),
        ),
      ],
    );
  });

  Widget _instituteSection(ThemeData theme) => _section(
    context: context,
    icon: Icons.apartment_rounded,
    title: _english ? 'Institute Profile' : 'প্রতিষ্ঠানের প্রোফাইল',
    subtitle: _english
        ? 'Academic identity and contact details.'
        : 'শিক্ষাপ্রতিষ্ঠানের পরিচয় ও যোগাযোগের তথ্য।',
    children: [
      FutureBuilder<Academy?>(
        future: _academyFuture,
        builder: (context, snapshot) {
          final academy = snapshot.data;
          return Column(
            children: [
              _infoRow(
                icon: Icons.business_rounded,
                label: _english ? 'Institute name' : 'প্রতিষ্ঠানের নাম',
                value: (academy?.name ?? '').isNotEmpty
                    ? academy!.name
                    : (_english ? 'Not available' : 'পাওয়া যায়নি'),
              ),
              _infoRow(
                icon: Icons.phone_rounded,
                label: _english ? 'Phone' : 'ফোন নম্বর',
                value: (academy?.phone ?? '').isNotEmpty
                    ? academy!.phone!
                    : (_english ? 'Not available' : 'পাওয়া যায়নি'),
              ),
              _infoRow(
                icon: Icons.location_on_outlined,
                label: _english ? 'Address' : 'ঠিকানা',
                value: (academy?.address ?? '').isNotEmpty
                    ? academy!.address!
                    : (_english ? 'Not available' : 'পাওয়া যায়নি'),
              ),
              _infoRow(
                icon: Icons.calendar_today_rounded,
                label: _english ? 'Academic session' : 'শিক্ষাবর্ষ',
                value: '${DateTime.now().year} – ${DateTime.now().year + 1}',
              ),
            ],
          );
        },
      ),
      ListTile(
        leading: Icon(Icons.refresh_rounded, color: AppTheme.brandOf(context)),
        title: Text(
          _english ? 'Reload institute info' : 'প্রতিষ্ঠানের তথ্য রিলোড',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        onTap: _refresh,
      ),
    ],
  );

  Widget _notificationSection(ThemeData theme) => Obx(
    () => _section(
      context: context,
      icon: Icons.notifications_active_rounded,
      title: _english ? 'Notifications & Alerts' : 'নোটিফিকেশন ও অ্যালার্ট',
      subtitle: _english
          ? 'Control what reaches your device and how you are notified.'
          : 'আপনার ডিভাইসে কী যাবে এবং কীভাবে জানানো হবে তা নিয়ন্ত্রণ করুন।',
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.notifications_rounded),
          title: Text(
            _english ? 'Push notifications' : 'পুশ নোটিফিকেশন',
            style: theme.textTheme.bodyLarge,
          ),
          subtitle: Text(
            _english
                ? 'Receive notice and attendance alerts'
                : 'নোটিশ ও হাজিরার অ্যালার্ট পান',
            style: theme.textTheme.bodySmall,
          ),
          value: _appState.pushNotificationsEnabled.value,
          onChanged: (value) =>
              _safe(() => _appState.setPushNotifications(value)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.person_off_outlined),
          title: Text(
            _english ? 'Absence alerts' : 'অনুপস্থিতির অ্যালার্ট',
            style: theme.textTheme.bodyLarge,
          ),
          value: _appState.absenceAlertsEnabled.value,
          onChanged: (value) => _safe(() => _appState.setAbsenceAlerts(value)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.payments_outlined),
          title: Text(
            _english ? 'Fee reminders' : 'ফি রিমাইন্ডার',
            style: theme.textTheme.bodyLarge,
          ),
          value: _appState.feeAlertsEnabled.value,
          onChanged: (value) => _safe(() => _appState.setFeeAlerts(value)),
        ),
        _infoRow(
          icon: Icons.notifications_none_rounded,
          label: _english ? 'Unread notice badge' : 'অপঠিত নোটিশ ব্যাজ',
          value: _appState.unreadNoticeCount.value > 9
              ? '9+'
              : '${_appState.unreadNoticeCount.value}',
        ),
        _infoRow(
          icon: Icons.volume_up_outlined,
          label: _english ? 'Notification sound' : 'নোটিফিকেশন সাউন্ড',
          value: _english
              ? 'High importance channel'
              : 'হাই ইম্পোর্টেন্স চ্যানেল',
        ),
      ],
    ),
  );

  Widget _securitySection(ThemeData theme) {
    final role = _appState.role.value ?? 'super_admin';
    final roleLabel = role == 'super_admin'
        ? (_english ? 'Super Admin' : 'সুপার অ্যাডমিন')
        : role;
    return _section(
      context: context,
      icon: Icons.shield_rounded,
      title: _english ? 'Security & Session' : 'নিরাপত্তা ও সেশন',
      subtitle: _english
          ? 'Your active identity and sign-out controls.'
          : 'আপনার সক্রিয় পরিচয় ও লগআউট নিয়ন্ত্রণ।',
      children: [
        _infoRow(
          icon: Icons.badge_outlined,
          label: _english ? 'Active role' : 'সক্রিয় রোল',
          value: roleLabel,
        ),
        _infoRow(
          icon: Icons.domain_outlined,
          label: _english ? 'Tenant ID' : 'টেন্যান্ট আইডি',
          value: _shortId(_appState.academyId.value),
        ),
        _infoRow(
          icon: Icons.lock_outline_rounded,
          label: _english ? 'Password' : 'পাসওয়ার্ড',
          value: _english
              ? 'Managed by institute administrator'
              : 'প্রতিষ্ঠানের অ্যাডমিন দ্বারা পরিচালিত',
        ),
        ListTile(
          leading: Icon(Icons.logout_rounded, color: Colors.red.shade600),
          title: Text(
            _english ? 'Sign out safely' : 'নিরাপদে লগআউট',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.red.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: _logout,
        ),
      ],
    );
  }

  Widget _appInfoSection(ThemeData theme) {
    final version = _packageInfo?.version ?? '1.0.5';
    final build = _packageInfo?.buildNumber ?? '6';
    return _section(
      context: context,
      icon: Icons.info_outline_rounded,
      title: _english ? 'App & Data' : 'অ্যাপ ও ডাটা',
      subtitle: _english
          ? 'Build details, refresh status and support.'
          : 'বিল্ড তথ্য, রিফ্রেশ স্ট্যাটাস ও সহায়তা।',
      children: [
        _infoRow(
          icon: Icons.numbers_rounded,
          label: _english ? 'Version' : 'ভার্সন',
          value: '$version ($build)',
        ),
        _infoRow(
          icon: Icons.cloud_sync_outlined,
          label: _english ? 'Live sync' : 'লাইভ সিঙ্ক',
          value: _english
              ? 'Supabase Realtime connected'
              : 'সুপাবেস রিয়েলটাইম সংযুক্ত',
        ),
        ListTile(
          leading: Icon(
            Icons.refresh_rounded,
            color: AppTheme.brandOf(context),
          ),
          title: Text(
            _english ? 'Refresh now' : 'এখনই রিফ্রেশ',
            style: theme.textTheme.bodyLarge,
          ),
          onTap: _refresh,
        ),
        ListTile(
          leading: Icon(
            Icons.feedback_outlined,
            color: AppTheme.brandOf(context),
          ),
          title: Text(
            _english ? 'Send feedback' : 'ফিডব্যাক পাঠান',
            style: theme.textTheme.bodyLarge,
          ),
          onTap: () => _safeTap(AppActions.showFeedbackDialog),
        ),
        ListTile(
          leading: Icon(
            Icons.privacy_tip_outlined,
            color: AppTheme.brandOf(context),
          ),
          title: Text(
            _english ? 'Privacy policy' : 'প্রাইভেসি পলিসি',
            style: theme.textTheme.bodyLarge,
          ),
          onTap: () => _safeTap(() => Get.to(() => const PrivacyPolicyView())),
        ),
        ListTile(
          leading: Icon(
            Icons.support_agent_rounded,
            color: AppTheme.brandOf(context),
          ),
          title: Text(
            _english ? 'Contact developer' : 'ডেভেলপারের সাথে যোগাযোগ',
            style: theme.textTheme.bodyLarge,
          ),
          onTap: () =>
              _safeTap(() => Get.to(() => const DeveloperProfileView())),
        ),
      ],
    );
  }

  Widget _choiceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
    String? badge,
  }) {
    final theme = Theme.of(context);
    final borderColor = selected
        ? AppTheme.brandOf(context)
        : AppTheme.borderOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _safeTap(onTap),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.tileOf(context, AppTheme.brandOf(context))
                : AppTheme.altSurfaceOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: selected ? 1.6 : 1),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 21,
                color: selected ? accent : AppTheme.mutedOf(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: fontWeight(selected),
                        color: AppTheme.inkOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (badge != null)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.tileOf(context, accent),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.tileInkOf(context, accent),
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected
                    ? AppTheme.brandOf(context)
                    : AppTheme.mutedOf(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.mutedOf(context)),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.inkOf(context),
                fontFeatures: AppTheme.numericFeatures,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _shortId(String? id) {
    if (id == null || id.isEmpty) return '—';
    return id.length <= 12
        ? id
        : '${id.substring(0, 8)}…${id.substring(id.length - 4)}';
  }

  FontWeight fontWeight(bool selected) =>
      selected ? FontWeight.w700 : FontWeight.w500;
}
