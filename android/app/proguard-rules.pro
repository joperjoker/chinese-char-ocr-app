# Keep all ML Kit text recognition classes, including script-specific options
# accessed via reflection by the google_mlkit_text_recognition plugin.
-keep class com.google.mlkit.vision.text.** { *; }
-dontwarn com.google.mlkit.vision.text.**
