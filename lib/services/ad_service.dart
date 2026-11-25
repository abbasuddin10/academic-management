import 'dart:async';

import 'package:academy_management/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  const AdService._();

  // Google's official test ad units — used in debug/profile builds only.
  static const String _testInterstitialId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testBannerId =
      'ca-app-pub-3940256099942544/6300978111';

  static InterstitialAd? _interstitialAd;

  static String get _interstitialUnitId =>
      kReleaseMode ? AppConfig.adInterstitialId : _testInterstitialId;

  static String get _bannerUnitId =>
      kReleaseMode ? AppConfig.adBannerId : _testBannerId;

  /// Master switch for the post-notification-tap interstitial. Flip this to
  /// `false` to disable that single placement without touching any call site.
  /// The daily cap and cooldown below still apply when it is enabled.
  static const bool enableNotificationTapAds = true;

  // Persisted cadence for the notification-tap placement (separate from the
  // general `ad_click_count` / `daily_ad_count` counters so it cannot starve
  // or be starved by other ad placements).
  static const String _notifTapLastKey = 'notification_tap_ad_last_at';
  static const String _notifTapCountKey = 'notification_tap_ad_count';
  static const String _notifTapDateKey = 'notification_tap_ad_date';
  static const String notifTapAdsPreferenceKey = 'pref_notification_tap_ad';
  static const int _notifTapMaxPerDay = 4;

  /// Best-effort interstitial shown when the user opens the app by tapping a
  /// push notification.
  ///
  /// Guarantees:
  ///   * never throws — any failure returns `false` immediately;
  ///   * never blocks navigation when no ad is cached (it simply reloads);
  ///   * at most once per [cooldown] (default 30 min) and
  ///     [_notifTapMaxPerDay] times per calendar day;
  ///   * a [showTimeout] guard settles the future even if the ad SDK never
  ///     fires a dismiss/error callback.
  ///
  /// Returns `true` only when an ad was actually displayed.
  static Future<bool> showNotificationTapAd({
    Duration cooldown = const Duration(minutes: 30),
    Duration showTimeout = const Duration(seconds: 8),
  }) async {
    if (!enableNotificationTapAds) return false;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Per-device opt-out (reserved for a future Settings toggle; defaults
      // to enabled when the key has never been written).
      if (prefs.getBool(notifTapAdsPreferenceKey) == false) return false;

      final now = DateTime.now();
      final today = _today;

      // 1. Time-based cooldown.
      final lastShownMs = prefs.getInt(_notifTapLastKey) ?? 0;
      if (now.millisecondsSinceEpoch - lastShownMs < cooldown.inMilliseconds) {
        return false;
      }

      // 2. Daily frequency cap.
      if (prefs.getString(_notifTapDateKey) != today) {
        await prefs.setString(_notifTapDateKey, today);
        await prefs.setInt(_notifTapCountKey, 0);
      }
      final shownToday = prefs.getInt(_notifTapCountKey) ?? 0;
      if (shownToday >= _notifTapMaxPerDay) return false;

      // 3. Ad availability — the critical "never block navigation" fallback.
      final ad = _interstitialAd;
      if (ad == null) {
        loadInterstitialAd();
        return false;
      }
      _interstitialAd = null;

      // Record the attempt up front so a failed show() cannot cause a retry
      // storm on every subsequent notification tap.
      await prefs.setInt(_notifTapLastKey, now.millisecondsSinceEpoch);
      await prefs.setInt(_notifTapCountKey, shownToday + 1);

      final completer = Completer<bool>();
      var settled = false;

      void settle(bool shown) {
        if (settled) return;
        settled = true;
        if (!completer.isCompleted) completer.complete(shown);
      }

      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          loadInterstitialAd();
          settle(true);
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          loadInterstitialAd();
          settle(false);
        },
      );

      final timeout = Timer(showTimeout, () => settle(false));
      try {
        await ad.show();
      } catch (_) {
        // onAdFailedToShow... normally handles disposal; do not double-dispose.
        settle(false);
      }

      try {
        return await completer.future;
      } finally {
        timeout.cancel();
      }
    } catch (_) {
      // Preferences / plugin failure: navigation proceeds immediately.
      return false;
    }
  }

  static void loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
        },
      ),
    );
  }

  static BannerAd createBannerAd() {
    return BannerAd(
      adUnitId: _bannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );
  }

  /// Shows an ad on every third tracked action, capped at five per day.
  /// The counter is persisted so restarting the app cannot reset the cadence.
  static Future<void> showAdWithTracking({required Function onComplete}) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _today;

    var clickCount = prefs.getInt('ad_click_count') ?? 0;
    final lastClickDate = prefs.getString('ad_click_date') ?? '';
    if (lastClickDate != today) {
      clickCount = 0;
      await prefs.setString('ad_click_date', today);
    }
    clickCount += 1;
    await prefs.setInt('ad_click_count', clickCount);

    if (clickCount % 3 == 0 && await _checkDailyLimit()) {
      final ad = _interstitialAd;
      if (ad != null) {
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            loadInterstitialAd();
            _incrementDailyCount();
            onComplete();
          },
          onAdFailedToShowFullScreenContent: (ad, error) {
            ad.dispose();
            loadInterstitialAd();
            onComplete();
          },
        );
        await ad.show();
        _interstitialAd = null;
        return;
      }
    }

    onComplete();
  }

  static void showForcedAd({required Function onComplete}) {
    final ad = _interstitialAd;
    if (ad != null) {
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          loadInterstitialAd();
          onComplete();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          loadInterstitialAd();
          onComplete();
        },
      );
      ad.show();
      _interstitialAd = null;
    } else {
      loadInterstitialAd();
      onComplete();
    }
  }

  static String get _today => DateTime.now().toIso8601String().substring(0, 10);

  static Future<bool> _checkDailyLimit() async {
    final prefs = await SharedPreferences.getInstance();

    final lastDate = prefs.getString('last_ad_date') ?? '';
    var shownCount = prefs.getInt('daily_ad_count') ?? 0;

    if (lastDate != _today) {
      await prefs.setString('last_ad_date', _today);
      await prefs.setInt('daily_ad_count', 0);
      shownCount = 0;
    }

    const int maxDailyLimit = 5;
    return shownCount < maxDailyLimit;
  }

  static Future<void> _incrementDailyCount() async {
    final prefs = await SharedPreferences.getInstance();
    final shownCount = prefs.getInt('daily_ad_count') ?? 0;
    await prefs.setInt('daily_ad_count', shownCount + 1);
  }
}
