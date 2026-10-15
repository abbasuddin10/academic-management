import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  static InterstitialAd? _interstitialAd;
  static int _clickCount =
      0; // ইউজার কয়টি ক্লিক করল তা ট্র্যাক করার জন্য[cite: 9]

  // ১. ইন্টারস্টিশিয়াল অ্যাড লোড করা[cite: 9]
  static void loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/1033173712', // টেস্ট আইডি[cite: 9]
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

  // নতুন ব্যানার অ্যাড তৈরি করার ফাংশন[cite: 9]
  static BannerAd createBannerAd() {
    return BannerAd(
      adUnitId:
          'ca-app-pub-3940256099942544/6300978111', // টেস্ট ব্যানার আইডি[cite: 9]
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );
  }

  // ২. দৈনিক লিমিট (সর্বোচ্চ ৪-৫টি) এবং প্রতি ৩ ক্লিকে ১ বার অ্যাড দেখানোর ফাংশন[cite: 9]
  static Future<void> showAdWithTracking({required Function onComplete}) async {
    _clickCount++; // প্রতি ক্লিকে ১ বাড়বে[cite: 9]

    // প্রতি ৩ ক্লিকে ১ বার অ্যাড দেখানোর টার্গেট[cite: 9]
    if (_clickCount % 3 == 0) {
      bool canShow = await _checkDailyLimit();

      if (canShow && _interstitialAd != null) {
        _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            loadInterstitialAd();
            _incrementDailyCount(); // অ্যাড দেখা শেষ হলে দৈনিক কাউন্ট ১ বাড়বে[cite: 9]
            onComplete();
          },
          onAdFailedToShowFullScreenContent: (ad, error) {
            ad.dispose();
            loadInterstitialAd();
            onComplete();
          },
        );
        _interstitialAd!.show();
        _interstitialAd = null;
        return;
      }
    }

    // যদি শর্ত না মেলে, তবে সরাসরি নির্দিষ্ট পেজে চলে যাবে[cite: 9]
    onComplete();
  }

  // ৩. কোনো শর্ত বা কাউন্ট ছাড়াই সরাসরি (Forced) অ্যাড দেখানোর ফাংশন[cite: 9]
  static void showForcedAd({required Function onComplete}) {
    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
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
      _interstitialAd!.show();
      _interstitialAd = null;
    } else {
      loadInterstitialAd();
      onComplete();
    }
  }

  // ৪. দৈনিক লিমিট চেক করার প্রাইভেট ফাংশন (সর্বোচ্চ ৪-৫টি)[cite: 9]
  static Future<bool> _checkDailyLimit() async {
    final prefs = await SharedPreferences.getInstance();
    String todayDate = DateTime.now().toIso8601String().substring(0, 10);

    String lastDate = prefs.getString('last_ad_date') ?? '';
    int shownCount = prefs.getInt('daily_ad_count') ?? 0;

    if (lastDate != todayDate) {
      await prefs.setString('last_ad_date', todayDate);
      await prefs.setInt('daily_ad_count', 0);
      shownCount = 0;
    }

    int maxDailyLimit = 5; // দৈনিক সর্বোচ্চ ৫টি অ্যাড লিমিট[cite: 9]
    return shownCount < maxDailyLimit;
  }

  // ৫. অ্যাড দেখার পর দৈনিক কাউন্ট ১ বাড়িয়ে দেওয়া[cite: 9]
  static Future<void> _incrementDailyCount() async {
    final prefs = await SharedPreferences.getInstance();
    int shownCount = prefs.getInt('daily_ad_count') ?? 0;
    await prefs.setInt('daily_ad_count', shownCount + 1);
  }
}
