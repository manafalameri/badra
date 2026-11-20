# Flutter obfuscation rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Play Core classes (required for Flutter deferred components)
-keep class com.google.android.play.core.** { *; }

# Keep native method names
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep enum values
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep annotations
-keepattributes *Annotation*

# Supabase/PostgREST client
-keep class com.supabase.** { *; }
-keep class io.flutter.plugins.supabase.** { *; }

# Keep JSON serialization
-keep class com.google.gson.** { *; }

# Local auth
-keep class com.linusu.flutter_local_auth.** { *; }
-keep class io.flutter.plugins.locallocalauth.** { *; }

# Secure storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class io.flutter.plugins.fluttersecurestorage.** { *; }

# Device info
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class io.flutter.plugins.device_info.** { *; }

# Crypto
-keep class javax.crypto.** { *; }
-keep class java.security.** { *; }

# HTTP client
-keep class okhttp3.** { *; }
-keep class okio.** { *; }