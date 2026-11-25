/// Runtime configuration for the app.
///
/// All values can be overridden at build time with `--dart-define`, e.g.:
///
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://your-project.supabase.co \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx \
///   --dart-define=FIREBASE_API_KEY=xxx \
///   --dart-define=FIREBASE_AUTH_DOMAIN=xxx \
///   --dart-define=FIREBASE_PROJECT_ID=xxx \
///   --dart-define=FIREBASE_STORAGE_BUCKET=xxx \
///   --dart-define=FIREBASE_MESSAGING_SENDER_ID=xxx \
///   --dart-define=FIREBASE_APP_ID=xxx \
///   --dart-define=FIREBASE_MEASUREMENT_ID=xxx \
///   --dart-define=GEMINI_API_KEY=xxx
/// ```
///
/// The Supabase URL / publishable key and the Firebase *web* config are public
/// identifiers by design (they are shipped in every client build). They are
/// kept here as defaults so a default build still works, but should always be
/// supplied via `--dart-define` for a real deployment. Secrets that must never
/// be committed (such as the Gemini API key) have an empty default.
class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rtyrbxpvntfaetvynfvf.supabase.co',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_IBDoDckksGkwsImjXu8W9g_rR6rRpiI',
  );

  static const String firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyCzBC-yibWgIHzy5VTrV6p0qnRB-ExE18',
  );

  static const String firebaseAuthDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
    defaultValue: 'academy-manager-65b2a.firebaseapp.com',
  );

  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'academy-manager-65b2a',
  );

  static const String firebaseStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: 'academy-manager-65b2a.firebasestorage.app',
  );

  static const String firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '291092236875',
  );

  static const String firebaseAppId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '1:291092236875:web:31521e88aa4125ad705bce',
  );

  static const String firebaseMeasurementId = String.fromEnvironment(
    'FIREBASE_MEASUREMENT_ID',
    defaultValue: 'G-JJK4PTEWM',
  );

  /// Server-side AI key. Empty by default on purpose — it must be injected at
  /// build time and never committed to source control.
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  /// A currently valid Gemini model. Can be overridden if Google renames it.
  static const String geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.0-flash',
  );

  /// Production ad unit IDs. Debug/profile builds always use Google's official
  /// test IDs instead, so ad traffic is never billed during development.
  static const String adInterstitialId = String.fromEnvironment(
    'AD_INTERSTITIAL_ID',
    defaultValue: 'ca-app-pub-6885203373790979/9324785589',
  );

  static const String adBannerId = String.fromEnvironment(
    'AD_BANNER_ID',
    defaultValue: 'ca-app-pub-6885203373790979/6584118352',
  );

  static bool get hasGeminiApiKey => geminiApiKey.trim().isNotEmpty;
}
