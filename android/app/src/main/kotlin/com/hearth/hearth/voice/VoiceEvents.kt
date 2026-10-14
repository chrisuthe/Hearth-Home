package com.hearth.hearth.voice

import android.os.Handler
import android.os.Looper

/**
 * Native-to-Dart events on `com.hearth/voice/events`. The service outlives
 * any one Flutter engine, so events go through this process-wide relay and
 * the channel attaches a sink while Dart is listening.
 *
 * `timer` and `ringStopped` are part of the channel contract and are never
 * sent yet: timers arrive in a later phase.
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
    private var owner: Any? = null
    private var sink: ((Map<String, Any?>) -> Unit)? = null
    private var lastState: Map<String, Any?>? = null
    private var lastDuck: Map<String, Any?>? = null

    /** Main thread only. A new listener is caught up with the current state. */
    fun attach(owner: Any, sink: (Map<String, Any?>) -> Unit) {
        this.owner = owner
        this.sink = sink
        lastState?.let { sink(it) }
        lastDuck?.let { sink(it) }
    }

    /**
     * Main thread only. A no-op unless [owner] attached the current listener:
     * a recreated activity's engine attaches before the old one is torn down.
     */
    fun detach(owner: Any) {
        if (this.owner !== owner) return
        this.owner = null
        sink = null
    }

    /** [running] is false only in the service's last event before it is gone. */
    fun state(state: String, connected: Boolean, running: Boolean = true) = emit(
        mapOf("event" to STATE, "state" to state, "connected" to connected, "running" to running),
    )

    fun health(code: String, message: String) =
        emit(mapOf("event" to HEALTH, "code" to code, "message" to message))

    fun duck(active: Boolean) = emit(mapOf("event" to DUCK, "active" to active))

    fun settingChanged(setting: String, value: Any) =
        emit(mapOf("event" to SETTING_CHANGED, "setting" to setting, "value" to value))

    private fun emit(event: Map<String, Any?>) {
        main.post {
            when (event["event"]) {
                STATE -> lastState = event
                DUCK -> lastDuck = event
            }
            sink?.invoke(event)
        }
    }
}
