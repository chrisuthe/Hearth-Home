package com.hearth.hearth.voice

import android.os.Handler
import android.os.Looper

/**
 * Native-to-Dart events on `com.hearth/voice/events`. The service outlives
 * any one Flutter engine, so events go through this process-wide relay and
 * the channel attaches a sink while Dart is listening.
 *
 * `timer`, `duck` and `ringStopped` are part of the channel contract and are
 * never sent yet: timers and the audio coordinator arrive in later phases.
 */
object VoiceEvents {
    const val STATE = "state"
    const val HEALTH = "health"
    const val SETTING_CHANGED = "settingChanged"
    const val TIMER = "timer"
    const val DUCK = "duck"
    const val RING_STOPPED = "ringStopped"

    const val PERMISSION_MISSING = "permissionMissing"
    const val PORT_IN_USE = "portInUse"
    const val MIC_OPEN_FAILED = "micOpenFailed"
    const val MODEL_LOAD_FAILED = "modelLoadFailed"

    private val main = Handler(Looper.getMainLooper())
    private var sink: ((Map<String, Any?>) -> Unit)? = null
    private var lastState: Map<String, Any?>? = null

    /** Main thread only. A new listener is caught up with the current state. */
    fun attach(sink: ((Map<String, Any?>) -> Unit)?) {
        this.sink = sink
        lastState?.let { sink?.invoke(it) }
    }

    /** [running] is false only in the service's last event before it is gone. */
    fun state(state: String, connected: Boolean, running: Boolean = true) = emit(
        mapOf("event" to STATE, "state" to state, "connected" to connected, "running" to running),
    )

    fun health(code: String, message: String) =
        emit(mapOf("event" to HEALTH, "code" to code, "message" to message))

    fun settingChanged(setting: String, value: Any) =
        emit(mapOf("event" to SETTING_CHANGED, "setting" to setting, "value" to value))

    private fun emit(event: Map<String, Any?>) {
        main.post {
            if (event["event"] == STATE) lastState = event
            sink?.invoke(event)
        }
    }
}
