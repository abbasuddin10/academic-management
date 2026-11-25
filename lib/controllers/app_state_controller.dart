import 'dart:async';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/notice_repository.dart';
import '../repositories/notification_repository.dart';

/// Single source of truth for app-wide language, theme, session metadata and
/// the live unread-notice badge count.
///
/// Individual screens can still keep a local `bool _isEnglish` for their own
/// rebuilds, but they initialise it from this controller and write back on
/// change, so the choice survives navigation and restarts.
class AppStateController extends GetxController {
  static AppStateController get to => Get.find<AppStateController>();

  static const String _languageKey = 'app_language_en';
  static const String _themeKey = 'app_theme_dark';
  static const String _themeModeKey = 'app_theme_mode';
  static const String _pushKey = 'pref_push_notifications';
  static const String _absenceKey = 'pref_absence_alerts';
  static const String _feeKey = 'pref_fee_alerts';

  final RxBool isEnglish = false.obs;
  final RxBool isDarkMode = false.obs;

  /// 'light' | 'dark' | 'system'. Single source of truth for ThemeMode.
  final RxString themePreference = 'light'.obs;

  // Notification preferences (persisted locally; surfaced in Settings).
  final RxBool pushNotificationsEnabled = true.obs;
  final RxBool absenceAlertsEnabled = true.obs;
  final RxBool feeAlertsEnabled = true.obs;

  final RxnString academyId = RxnString();
  final RxnString role = RxnString();

  /// Messenger-style badge shown on every notification bell. Any screen can
  /// wrap its bell in `Obx` and it updates without manual setState hacks.
  final RxInt unreadNoticeCount = 0.obs;

  /// Unread academic/fee events from `app_notifications` (migration 0003).
  final RxInt unreadActivityCount = 0.obs;

  /// Badge shown on notification bells: notices + academic events.
  int get unreadTotalCount =>
      unreadNoticeCount.value + unreadActivityCount.value;

  /// `auth.uid()` for admins, `teacher:<id>` / `student:<id>` otherwise.
  final RxnString readerKey = RxnString();

  NoticeUnreadWatch? _noticeWatch;
  StreamSubscription<int>? _unreadSub;
  String? _watchKey;
  String? _watchClassName;

  NotificationWatch? _activityWatch;
  StreamSubscription<int>? _activitySub;
  String? _activityKey;

  @override
  void onInit() {
    super.onInit();
    _loadPreferences();
  }

  /// Preference I/O is best-effort: a missing plugin or a locked storage must
  /// never bubble up as an unhandled async exception into the UI.
  Future<void> _persist(
    Future<void> Function(SharedPreferences prefs) write,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await write(prefs);
    } catch (_) {
      // In-memory reactive state stays authoritative for this session.
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isEnglish.value = prefs.getBool(_languageKey) ?? false;

      final storedMode = prefs.getString(_themeModeKey);
      final legacyDark = prefs.getBool(_themeKey) ?? false;
      themePreference.value = storedMode ?? (legacyDark ? 'dark' : 'light');
      isDarkMode.value = themePreference.value == 'dark';

      pushNotificationsEnabled.value = prefs.getBool(_pushKey) ?? true;
      absenceAlertsEnabled.value = prefs.getBool(_absenceKey) ?? true;
      feeAlertsEnabled.value = prefs.getBool(_feeKey) ?? true;
    } catch (_) {
      // Defaults are already set on the reactive fields; nothing to do.
    }
  }

  Future<void> setEnglish(bool value) async {
    isEnglish.value = value;
    await _persist((prefs) => prefs.setBool(_languageKey, value));
  }

  /// Immediately flips the reactive theme and persists the choice.
  Future<void> setThemePreference(String value) async {
    final preference = <String>{'light', 'dark', 'system'}.contains(value)
        ? value
        : 'light';
    themePreference.value = preference;
    isDarkMode.value = preference == 'dark';
    await _persist((prefs) async {
      await prefs.setString(_themeModeKey, preference);
      await prefs.setBool(_themeKey, preference == 'dark');
    });
  }

  /// Backward-compatible helper used by older call sites.
  Future<void> setDarkMode(bool value) =>
      setThemePreference(value ? 'dark' : 'light');

  Future<void> setPushNotifications(bool value) async {
    pushNotificationsEnabled.value = value;
    await _persist((prefs) => prefs.setBool(_pushKey, value));
  }

  Future<void> setAbsenceAlerts(bool value) async {
    absenceAlertsEnabled.value = value;
    await _persist((prefs) => prefs.setBool(_absenceKey, value));
  }

  Future<void> setFeeAlerts(bool value) async {
    feeAlertsEnabled.value = value;
    await _persist((prefs) => prefs.setBool(_feeKey, value));
  }

  void setSession({
    required String? academyId,
    required String? role,
    String? readerKey,
  }) {
    this.academyId.value = academyId;
    this.role.value = role;
    setReaderKey(readerKey);
  }

  void clearSession() {
    academyId.value = null;
    role.value = null;
    readerKey.value = null;
    setUnreadNoticeCount(0);
    unreadActivityCount.value = 0;
    stopNoticeWatch();
    stopActivityWatch();
  }

  void setReaderKey(String? key) {
    readerKey.value = (key == null || key.trim().isEmpty) ? null : key.trim();
  }

  void setUnreadNoticeCount(int count) {
    unreadNoticeCount.value = count < 0 ? 0 : count;
  }

  void incrementUnreadNoticeCount([int by = 1]) {
    if (by <= 0) return;
    setUnreadNoticeCount(unreadNoticeCount.value + by);
  }

  void decrementUnreadNoticeCount([int by = 1]) {
    if (by <= 0) return;
    setUnreadNoticeCount(unreadNoticeCount.value - by);
  }

  /// (Re)starts the realtime unread counter. Calling again with the same
  /// tenant/recipient is a no-op, so every home screen can call it safely.
  void startNoticeWatch({
    required String academyId,
    required String role,
    required String readerKey,
    String? className,
  }) {
    if (academyId.isEmpty || readerKey.isEmpty) return;
    final key = '$academyId|$readerKey|$role|${className ?? ''}';
    if (_watchKey == key && _noticeWatch != null) return;

    stopNoticeWatch();
    _watchKey = key;
    _watchClassName = className;
    _noticeWatch = NoticeRepository().watchUnreadCount(
      academyId: academyId,
      readerKey: readerKey,
      role: role,
      className: className,
    );
    _unreadSub = _noticeWatch!.stream.listen(
      setUnreadNoticeCount,
      onError: (Object _) {
        // Keep the last known count when a transient realtime error occurs;
        // the next database event will refresh it.
      },
    );
  }

  /// Recomputes the badge on demand (e.g. when an FCM foreground message or a
  /// screen refresh signals that a new notice may have arrived).
  Future<void> refreshUnreadNoticeCount() async {
    final tenant = academyId.value;
    final key = readerKey.value;
    if (tenant == null || tenant.isEmpty || key == null || key.isEmpty) return;
    try {
      final count = await NoticeRepository().getUnreadCount(
        tenant,
        readerKey: key,
        role: role.value,
        className: _watchClassName,
      );
      setUnreadNoticeCount(count);
    } catch (_) {
      // Keep the last known badge value on a transient backend failure.
    }
  }

  /// (Re)starts the realtime activity counter for student academic events.
  void startActivityWatch({
    required String academyId,
    required String readerKey,
  }) {
    if (academyId.isEmpty || readerKey.isEmpty) return;
    final key = '$academyId|$readerKey';
    if (_activityKey == key && _activityWatch != null) return;

    stopActivityWatch();
    _activityKey = key;
    _activityWatch = NotificationRepository().watchUnreadCount(
      academyId: academyId,
      readerKey: readerKey,
    );
    _activitySub = _activityWatch!.stream.listen(
      (count) => unreadActivityCount.value = count < 0 ? 0 : count,
      onError: (Object _) {
        // Keep the last known value on transient realtime errors.
      },
    );
  }

  Future<void> refreshUnreadActivityCount() async {
    final tenant = academyId.value;
    final key = readerKey.value;
    if (tenant == null || tenant.isEmpty || key == null || key.isEmpty) return;
    try {
      final count = await NotificationRepository().getUnreadCount(
        tenant,
        readerKey: key,
      );
      unreadActivityCount.value = count < 0 ? 0 : count;
    } catch (_) {
      // Keep last known badge.
    }
  }

  void stopActivityWatch() {
    _activitySub?.cancel();
    _activitySub = null;
    _activityWatch?.dispose();
    _activityWatch = null;
    _activityKey = null;
  }

  void stopNoticeWatch() {
    _unreadSub?.cancel();
    _unreadSub = null;
    _noticeWatch?.dispose();
    _noticeWatch = null;
    _watchKey = null;
    _watchClassName = null;
  }

  @override
  void onClose() {
    stopNoticeWatch();
    stopActivityWatch();
    super.onClose();
  }

  /// Small helper to remove inline `condition ? bangla : english` ternaries.
  String tr(String bangla, String english) =>
      isEnglish.value ? english : bangla;
}
