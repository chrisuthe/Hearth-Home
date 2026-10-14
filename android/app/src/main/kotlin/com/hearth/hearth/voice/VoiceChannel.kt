package com.hearth.hearth.voice

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.example.ava.wakewords.providers.AssetWakeWordProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import timber.log.Timber

/**
 * Host side of `com.hearth/voice`. Dart is the only caller.
 *
 * Events travel on `com.hearth/voice/events`: a MethodChannel and an
 * EventChannel cannot share one name, because each claims the name's single
 * message handler.
 */
class VoiceChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, NAME)
    private val events = EventChannel(messenger, "$NAME/events")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private var pendingStart: Pair<VoiceConfig, MethodChannel.Result>? = null

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(
                VoiceConfig.fromArguments(
                    call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(),
                    HearthAudioService.muted,
                ),
                result,
            )
            "stop" -> {
                // Sendspin may be keeping the service.
                HearthAudioService.stopVoice(activity)
                result.success(null)
            }
            "setMuted" -> {
                HearthAudioService.setMuted(call.arguments as? Boolean ?: false)
                result.success(null)
            }
            "wake" -> {
                HearthAudioService.instance?.wake()
                result.success(null)
            }
            "listWakeWords" -> scope.launch {
                val words = runCatching { AssetWakeWordProvider(activity.assets).get() }
                    .getOrDefault(emptyList())
                result.success(words.map { mapOf("id" to it.id, "name" to it.wakeWord.wake_word) })
            }
            "startTimerRing" -> result.success(HearthAudioService.instance?.startTimerRing() ?: false)
            "stopTimerRing" -> {
                HearthAudioService.instance?.stopTimerRing()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Replies true once the service has been asked to start. */
    private fun start(config: VoiceConfig, result: MethodChannel.Result) {
        if (granted(Manifest.permission.RECORD_AUDIO)) {
            result.success(startService(config))
            return
        }
        pendingStart?.second?.success(false)
        pendingStart = config to result
        val wanted = buildList {
            add(Manifest.permission.RECORD_AUDIO)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                !granted(Manifest.permission.POST_NOTIFICATIONS)
            ) {
                add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        ActivityCompat.requestPermissions(activity, wanted.toTypedArray(), PERMISSION_REQUEST)
    }

    fun onRequestPermissionsResult(requestCode: Int) {
        if (requestCode != PERMISSION_REQUEST) return
        val (config, result) = pendingStart ?: return
        pendingStart = null
        // The service runs without POST_NOTIFICATIONS; only the mic gates it.
        if (granted(Manifest.permission.RECORD_AUDIO)) {
            result.success(startService(config))
        } else {
            VoiceEvents.health(VoiceEvents.PERMISSION_MISSING, "Microphone permission was denied")
            result.success(false)
        }
    }

    private fun startService(config: VoiceConfig): Boolean = try {
        HearthAudioService.startVoice(activity, config)
        true
    } catch (e: Exception) {
        // Android refuses a microphone service start while Hearth is not visible.
        Timber.e(e, "Voice service start refused")
        VoiceEvents.health(VoiceEvents.MIC_OPEN_FAILED, "Service start refused: ${e.message}")
        false
    }

    private fun granted(permission: String) =
        ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        VoiceEvents.attach(this) { sink.success(it) }
    }

    override fun onCancel(arguments: Any?) {
        VoiceEvents.detach(this)
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        VoiceEvents.detach(this)
        pendingStart = null
        scope.cancel()
    }

    private companion object {
        const val NAME = "com.hearth/voice"
        const val PERMISSION_REQUEST = 6053
    }
}
