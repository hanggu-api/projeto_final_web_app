# Flutter ProGuard Rules
# https://flutter.dev/docs/deployment/android#obfuscating-dart-code

# Keep the classes used by Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep the Firebase classes
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.crashlytics.** { *; }

# Notifications / reflection-heavy plugins
-keep class me.carda.awesome_notifications.** { *; }
-keep class me.carda.awesome_notifications_fcm.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# WebView / JS bridge / URL launching
-keep class io.flutter.plugins.webviewflutter.** { *; }
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Map and location plugins used in release builds
-keep class com.mapbox.** { *; }
-keep class com.baseflow.** { *; }

# Optional ML Kit language packs referenced by the text recognizer plugin.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# Keep the model classes for serialization (JNI/JSON)
# Replace with your app's package if needed
-keep class br.com.play101.serviceapp.models.** { *; }

# Avoid warnings from transitive Flutter/plugin metadata
-dontwarn io.flutter.embedding.**
-dontwarn com.google.errorprone.annotations.**
