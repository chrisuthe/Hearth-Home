# Nothing calls the Sendspin player yet, so R8 would drop all of it. Keep the
# two entry points and everything their public API reaches, so the release APK
# carries the player as phase 4 will use it. Remove once HearthAudioService
# references them.
-keep class com.sendspindroid.playback.SendSpinEngine { public *; }
-keep class com.sendspindroid.sendspin.SendSpin { public *; }
