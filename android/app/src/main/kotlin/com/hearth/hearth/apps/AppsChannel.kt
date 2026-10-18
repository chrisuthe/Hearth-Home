package com.hearth.hearth.apps

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.provider.Settings
import android.util.Log
import com.hearth.hearth.MainActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Host side of `com.hearth/apps`: lists launchable apps, launches one beside
 * (or over) Hearth, and brings Hearth back to the front.
 */
class AppsChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.hearth/apps")

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listApps" -> result.success(listApps())
            "icon" -> result.success(icon(call.argument<String>("packageName")))
            "launch" -> result.success(
                launch(
                    call.argument<String>("packageName"),
                    call.argument<String>("layout"),
                ),
            )
            "overlayGranted" -> result.success(Settings.canDrawOverlays(activity))
            "openOverlaySettings" -> {
                activity.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:${activity.packageName}"),
                    ),
                )
                result.success(null)
            }
            "bringToFront" -> {
                bringToFront()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun listApps(): List<Map<String, String>> {
        val pm = activity.packageManager
        val query = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(query, 0)
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { it.first != activity.packageName }
            .distinctBy { it.first }
            .sortedBy { it.second.lowercase() }
            .map { mapOf("packageName" to it.first, "label" to it.second) }
    }

    private fun icon(pkg: String?): ByteArray? {
        if (pkg == null) return null
        return try {
            val drawable = activity.packageManager.getApplicationIcon(pkg)
            // Adaptive icons have no intrinsic size; draw into a fixed one.
            val size = 192
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            ByteArrayOutputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                it.toByteArray()
            }
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }
    }

    private fun launch(pkg: String?, layout: String?): Boolean {
        if (pkg == null) return false
        val intent = activity.packageManager.getLaunchIntentForPackage(pkg) ?: return false
        val smallScreen = activity.resources.configuration.smallestScreenWidthDp < 600
        if (layout == "split" && !smallScreen) {
            launchSplitAdjacent(intent)
        } else {
            launchFullscreen(intent)
        }
        // The app is open either way; a refused session only costs the button
        // and the keep-alive, so it must not report the launch as failed.
        try {
            AppSessionService.start(activity)
        } catch (e: Exception) {
            Log.e(TAG, "App session start refused", e)
        }
        return true
    }

    private fun launchFullscreen(intent: Intent) {
        activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /**
     * The app opens adjacent to Hearth, so Hearth stays top/left. Relaunching
     * Hearth adjacent to the app instead only re-fronted Hearth's task on
     * hardware (T901, Android 15), with no split.
     */
    private fun launchSplitAdjacent(intent: Intent) {
        activity.startActivity(
            intent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT,
            ),
        )
    }

    private fun bringToFront() {
        // Already on screen (in a split half too), or no app was launched, so
        // there is nothing to come forward over.
        if (MainActivity.visible || !AppSessionService.active) return
        if (!Settings.canDrawOverlays(activity)) {
            Log.w(TAG, "bringToFront skipped: overlay permission not granted")
            return
        }
        activity.startActivity(AppSessionService.frontIntent(activity))
    }

    private companion object {
        const val TAG = "AppsChannel"
    }
}
