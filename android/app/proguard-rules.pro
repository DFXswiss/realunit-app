# flutter_secure_storage — no consumer rules, uses reflection for
# EncryptedSharedPreferences + Tink
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Tink crypto key types (loaded via reflection by security-crypto)
-keep class com.google.crypto.tink.** { *; }

# AndroidX security-crypto
-keep class androidx.security.crypto.** { *; }

# Preserve native method bindings
-keepclasseswithmembernames class * {
    native <methods>;
}

# SumSub SDK requires Google Play Services Tasks                    
-keep class com.google.android.gms.tasks.** { *; }                                                                              

# SumSub SDK general keep rules                                     
-keep class com.sumsub.** { *; }                                    
-dontwarn com.sumsub.**

# Play Install Referrer (invite code across a fresh Android install)
-keep class com.android.installreferrer.** { *; }  
