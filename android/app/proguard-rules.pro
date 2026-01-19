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

# Keep the model classes for serialization (JNI/JSON)
# Replace with your app's package if needed
-keep class com.play101.app.models.** { *; }

# Basic shrinking rules
-dontwarn io.flutter.embedding.**
-ignorewarnings
