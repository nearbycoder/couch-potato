# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class com.nearbycoder.couchpotato.**$$serializer { *; }
-keepclassmembers class com.nearbycoder.couchpotato.** { *** Companion; }
-keepclasseswithmembers class com.nearbycoder.couchpotato.** { kotlinx.serialization.KSerializer serializer(...); }
