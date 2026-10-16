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
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Installs a downloaded Hearth APK over the running app through a
 * PackageInstaller session. Android shows its own "update this app?" prompt
 * for each install; the session's status comes back on "installStatus".
 * Also relaunches the app on "restartApp", which a restore uses.
 */
class AppUpdateChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.hearth/app_update")
    private val main = Handler(Looper.getMainLooper())

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = onStatus(intent)
    }

    /** The install session this channel committed, the only one it reports on. */
    @Volatile
    private var activeSessionId: Int? = null

    init {
        channel.setMethodCallHandler(this)
        // Not exported on every Android version, not only 13+: an exported
        // receiver would let any app send a "confirm this install" status, and
        // onStatus starts the activity that status names.
        ContextCompat.registerReceiver(
            activity,
            receiver,
            IntentFilter(ACTION_STATUS),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
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
            "restartApp" -> {
                result.success(true)
                // Let the reply reach Dart before the process goes.
                main.postDelayed({ RestartActivity.restart(activity) }, RESTART_DELAY_MS)
            }
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
                activeSessionId = sessionId
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
        // Belt and braces with the unexported receiver: only act on the
        // session this channel created.
        val sessionId = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)
        if (sessionId != activeSessionId) return
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
        private const val RESTART_DELAY_MS = 300L
    }
}
