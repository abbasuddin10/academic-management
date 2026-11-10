# 1. Flutter Core & Embeddings
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.common.** { *; }

# 2. Firebase & Google Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# 3. Your Main App Package (প্যাকেজ নাম অক্ষত রাখতে)
-keep class com.afrazstudio.academy_management.** { *; }

# 4. Multidex Support
-keep class androidx.multidex.** { *; }

# 5. JSON Serialization & Models (ডেটা মডেল এবং জেসন পার্সিং ঠিক রাখতে)
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-keepclassmembers public class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# 6. Kotlin & Coroutines
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.collections.**
-keep class kotlinx.coroutines.** { *; }

# 7. Local Storage & Preferences (SharedPreferences ও ফাইল পাথ ঠিক রাখতে)
-keep class android.content.SharedPreferences { *; }
-keep class android.content.Context { *; }
-dontwarn java.nio.file.**

# 8. Network & Dio / OkHttp (API কল ও Supabase ব্যাকএন্ডের জন্য)
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class retrofit2.** { *; }
-keep class com.google.common.** { *; }

# 9. Excel & PDF Generation (Syncfusion ও Excel/PDF প্লাগইনের জন্য)
-dontwarn com.syncfusion.**
-keep class com.syncfusion.** { *; }
-dontwarn org.apache.poi.**
-keep class org.apache.poi.** { *; }
# Google Play Core & Play Store Split Install Missing Classes Fix
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
-keep class io.flutter.embedding.android.FlutterPlayStoreSplitApplication { *; }
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }