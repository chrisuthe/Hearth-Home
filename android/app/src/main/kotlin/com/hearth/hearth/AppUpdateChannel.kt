package com.hearth.hearth

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Installs a downloaded Hearth APK over the running app through a
 * PackageInstaller session. Android shows its own "update this app?" prompt
 * for each install; the session's status comes back on "installStatus".
 */
class AppUpdateChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.hearth/app_update")
    private val main = Handler(Looper.getMainLooper())

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = onStatus(intent)
    }

    init {
        channel.setMethodCallHandler(this)
        val filter = IntentFilter(ACTION_STATUS)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(receiver, filter)
        }
    }

    fun dispose() {
        activity.unregisterReceiver(receiver)
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canInstall" -> result.success(activity.packageManager.canRequestPackageInstalls())
            "openInstallSettings" -> {
                activity.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${activity.packageName}"),
                    )
                )
                result.success(null)
            }
            "install" -> install(call.argument<String>("path")!!, result)
            else -> result.notImplemented()
        }
    }

    private fun install(path: String, result: MethodChannel.Result) {
        // Copying a large APK into the session would stall the UI thread.
        Thread {
            try {
                val file = File(path)
                val installer = activity.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(
                    PackageInstaller.SessionParams.MODE_FULL_INSTALL
                )
                params.setAppPackageName(activity.packageName)
                params.setSize(file.length())
                val sessionId = installer.createSession(params)
                installer.openSession(sessionId).use { session ->
                    file.inputStream().use { input ->
                        session.openWrite("hearth.apk", 0, file.length()).use { out ->
                            input.copyTo(out)
                            session.fsync(out)
                        }
                    }
                    // The system fills in the status extras, so the intent must
                    // be mutable; naming the package keeps it explicit.
                    val status = Intent(ACTION_STATUS).setPackage(activity.packageName)
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                        (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
                    val pending = PendingIntent.getBroadcast(activity, sessionId, status, flags)
                    session.commit(pending.intentSender)
                }
                main.post { result.success(null) }
            } catch (e: Exception) {
                main.post { result.error("install_failed", e.toString(), null) }
            }
        }.start()
    }

    private fun onStatus(intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_INTENT)
            }
            confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)?.let { activity.startActivity(it) }
        }
        channel.invokeMethod("installStatus", mapOf("status" to status, "message" to message))
    }

    companion object {
        private const val ACTION_STATUS = "com.hearth.hearth.INSTALL_STATUS"
    }
}
