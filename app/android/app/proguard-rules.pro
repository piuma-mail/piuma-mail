# ML Kit (Gemini Nano, Model.kt) finds its parts by reflection: without
# these, release builds strip their constructors and the model never starts.
-keep class com.google.mlkit.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
