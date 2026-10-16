package com.hearth.hearth

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Host side of `com.hearth/wifi`. Android does not let an ordinary app join
 * networks, so Hearth's Wi-Fi controls open the system page instead.
 */
class WifiChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.hearth/wifi")

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openSettings" -> try {
                activity.startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                result.success(null)
            } catch (e: ActivityNotFoundException) {
                // Some kiosk builds strip the Settings app.
                result.error("no_settings", e.toString(), null)
            }
            else -> result.notImplemented()
        }
    }
}
