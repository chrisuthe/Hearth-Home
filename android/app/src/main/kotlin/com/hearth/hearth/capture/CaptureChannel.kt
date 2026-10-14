package com.hearth.hearth.capture

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import timber.log.Timber

/**
 * Host side of `com.hearth/capture`. A capture without a projection opens
 * the consent dialog and fails at once with the reason, rather than holding
 * a portal request open until someone reaches the tablet.
 */
class CaptureChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, NAME)
    private val main = Handler(Looper.getMainLooper())
    private val listener: (String, Map<String, Any?>) -> Unit =
        { method, args -> channel.invokeMethod(method, args) }

    init {
        channel.setMethodCallHandler(this)
        CaptureState.listener = listener
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        // A relaunched activity may already have installed its own.
        if (CaptureState.listener === listener) CaptureState.listener = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(CaptureState.granted)
            "requestConsent" -> {
                if (CaptureState.granted) {
                    result.success(true)
                } else {
                    askConsent { result.success(it) }
                }
            }
            "screenshot" -> withSession(result) { svc ->
                svc.screenshot(call.argument<String>("path")!!, reply(result))
            }
            "startRecording" -> withSession(result) { svc ->
                svc.startRecording(call.argument<String>("path")!!, reply(result))
            }
            "stopRecording" -> {
                val svc = ScreenCaptureService.instance
                if (svc == null) {
                    result.error(ScreenCaptureService.ERROR_NOT_RECORDING, "No recording is running", null)
                } else {
                    svc.stopRecording(reply(result))
                }
            }
            "release" -> {
                activity.stopService(Intent(activity, ScreenCaptureService::class.java))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun withSession(result: MethodChannel.Result, block: (ScreenCaptureService) -> Unit) {
        val svc = ScreenCaptureService.instance
        if (svc != null) {
            block(svc)
            return
        }
        val reason = if (CaptureState.dialogOpen) CaptureState.CONSENT_PENDING else CaptureState.lost
        askConsent(null)
        result.error(reason, null, null)
    }

    private fun reply(result: MethodChannel.Result): (String?, String?) -> Unit = { code, message ->
        main.post {
            if (code == null) result.success(null) else result.error(code, message, null)
        }
    }

    private fun askConsent(waiter: ((Boolean) -> Unit)?) {
        if (CaptureState.dialogOpen) {
            waiter?.let { CaptureState.addWaiter(it) }
            return
        }
        val manager = activity.getSystemService(MediaProjectionManager::class.java)
        // Without a config, Android 14+ offers "share one app", which would
        // capture Hearth's window without the system bars or dialogs.
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
        } else {
            manager.createScreenCaptureIntent()
        }
        try {
            activity.startActivityForResult(intent, CONSENT_REQUEST)
            CaptureState.dialogShown(waiter)
        } catch (e: Exception) {
            Timber.e(e, "Consent dialog failed to open")
            waiter?.invoke(false)
        }
    }

    /** True when [requestCode] was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != CONSENT_REQUEST) return false
        if (resultCode != Activity.RESULT_OK || data == null) {
            CaptureState.onRefused(CaptureState.CONSENT_DENIED)
            return true
        }
        try {
            ContextCompat.startForegroundService(
                activity,
                ScreenCaptureService.intent(activity, resultCode, data),
            )
        } catch (e: Exception) {
            Timber.e(e, "Screen capture service start refused")
            CaptureState.onRefused(CaptureState.CONSENT_DENIED)
        }
        return true
    }

    private companion object {
        const val NAME = "com.hearth/capture"
        const val CONSENT_REQUEST = 6054
    }
}
