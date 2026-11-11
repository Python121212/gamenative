# ---- Pixel 9a size tuning (applied on top of proguard-android-optimize.txt) ----
# R8 removes debug/verbose logging calls and their string building from release DEX.
# -dontobfuscate is kept in proguard-rules.pro because JNI symbol names are hard-coded
# in the Rust/native libraries; R8 still shrinks, optimises and merges classes.
-assumenosideeffects class timber.log.Timber {
    public static void v(...);
    public static void d(...);
}
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
}

# Hide original source file names while keeping retrace-able stack traces.
-renamesourcefileattribute SourceFile

# Keep the bootstrap plan models (read through kotlinx.serialization reflection).
-keep class app.gamenative.utils.BootstrapPlan { *; }
-keep class app.gamenative.utils.BootstrapPack { *; }
-keep class app.gamenative.utils.BootstrapFile { *; }
-keep class app.gamenative.utils.Pixel9aRuntime { *; }
-keep class app.gamenative.utils.Pixel9aAssets { *; }
