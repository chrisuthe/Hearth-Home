package com.hearth.hearth.sendspin

import android.app.Activity
import com.hearth.hearth.voice.HearthAudioService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber

/**
 * Host side of `com.hearth/sendspin`, separate from `com.hearth/voice` so
 * neither feature's Dart side depends on the other. Events travel on
 * `com.hearth/sendspin/events`.
 */
class SendspinChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, NAME)
    private val events = EventChannel(messenger, "$NAME/events")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val volume = MediaVolume(activity)

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> result.success(
                configure(SendspinConfig.fromArguments(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())),
            )
            "setVolume" -> {
                val value = (call.arguments as? Number)?.toFloat() ?: 0f
                // Through the player when there is one, so the server hears it.
                HearthAudioService.instance?.sendspinPlayer?.setVolume(value) ?: volume.set(value)
                result.success(null)
            }
            "getVolume" -> result.success(volume.get().toDouble())
            "pairingInfo" -> scope.launch {
                // May mint the identity: file I/O.
                val info = withContext(Dispatchers.IO) {
                    runCatching {
                        val secrets = SendspinSecrets.get(activity)
                        mapOf(
                            "clientId" to secrets.identity.clientId,
                            "pairingToken" to secrets.pairingToken(),
                            "pairedServers" to secrets.trustStore.listRecords().size,
                        )
                    }.onFailure { Timber.e(it, "Sendspin pairing info unavailable") }.getOrNull()
                }
                result.success(info)
            }
            // A backup's copy of the secrets, and a restore's writing them back.
            "exportSecrets" -> scope.launch {
                val files = withContext(Dispatchers.IO) {
                    runCatching { SendspinSecrets.exportFiles(activity) }
                        .onFailure { Timber.e(it, "Sendspin secrets export failed") }
                        .getOrNull()
                }
                result.success(files)
            }
            "importSecrets" -> {
                val files = (call.arguments as? Map<*, *>).orEmpty().entries
                    .mapNotNull { (k, v) -> if (k is String && v is String) k to v else null }
                    .toMap()
                scope.launch {
                    val error = withContext(Dispatchers.IO) {
                        runCatching { SendspinSecrets.importFiles(activity, files) }.exceptionOrNull()
                    }
                    if (error == null) {
                        result.success(null)
                    } else {
                        Timber.e(error, "Sendspin secrets import failed")
                        result.error("import_failed", error.toString(), null)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    /** True once the service has the request. */
    private fun configure(config: SendspinConfig): Boolean = try {
        HearthAudioService.configureSendspin(activity, config)
        true
    } catch (e: Exception) {
        // Android refuses a foreground service start while Hearth is not visible.
        Timber.e(e, "Sendspin service start refused")
        SendspinEvents.health(SendspinEvents.LISTENER_FAILED, "Service start refused: ${e.message}")
        false
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        SendspinEvents.attach(this) { sink.success(it) }
    }

    override fun onCancel(arguments: Any?) {
        SendspinEvents.detach(this)
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        SendspinEvents.detach(this)
        scope.cancel()
    }

    private companion object {
        const val NAME = "com.hearth/sendspin"
    }
}
