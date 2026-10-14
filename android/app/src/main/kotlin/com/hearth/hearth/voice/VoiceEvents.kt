package com.hearth.hearth.voice

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.example.esphomeproto.api.VoiceAssistantTimerEvent
import com.example.esphomeproto.api.VoiceAssistantTimerEventResponse

/**
 * Native-to-Dart events on `com.hearth/voice/events`. The service outlives
 * any one Flutter engine, so events go through this process-wide relay and
 * the channel attaches a sink while Dart is listening.
 */
object VoiceEvents {
    const val STATE = "state"
    const val HEALTH = "health"
    const val SETTING_CHANGED = "settingChanged"
    const val TIMER = "timer"
    const val DUCK = "duck"
    const val RING_STOPPED = "ringStopped"
    private const val FINISHED = "finished"

    const val PERMISSION_MISSING = "permissionMissing"
    const val PORT_IN_USE = "portInUse"
    const val MIC_OPEN_FAILED = "micOpenFailed"
    const val MODEL_LOAD_FAILED = "modelLoadFailed"

    private val main = Handler(Looper.getMainLooper())
    private var owner: Any? = null
    private var sink: ((Map<String, Any?>) -> Unit)? = null
    private var lastState: Map<String, Any?>? = null
    private var lastDuck: Map<String, Any?>? = null

    /** Live timers by id, with when each event arrived, for a late listener. */
    private val timers = linkedMapOf<String, Pair<Map<String, Any?>, Long>>()

    /** Main thread only. A new listener is caught up with the current state. */
    fun attach(owner: Any, sink: (Map<String, Any?>) -> Unit) {
        this.owner = owner
        this.sink = sink
        lastState?.let { sink(it) }
        lastDuck?.let { sink(it) }
        val now = SystemClock.elapsedRealtime()
        timers.values.forEach { (event, at) -> sink(caughtUp(event, now - at)) }
    }

    /** [event] with its seconds left counted down by [elapsedMs], if it is running. */
    private fun caughtUp(event: Map<String, Any?>, elapsedMs: Long): Map<String, Any?> {
        if (event["type"] == FINISHED || event["active"] != true) return event
        val left = ((event["left"] as Int) - (elapsedMs / 1000).toInt()).coerceAtLeast(0)
        return event + ("left" to left)
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

    fun timer(response: VoiceAssistantTimerEventResponse) {
        val type = when (response.eventType) {
            VoiceAssistantTimerEvent.VOICE_ASSISTANT_TIMER_STARTED -> "started"
            VoiceAssistantTimerEvent.VOICE_ASSISTANT_TIMER_UPDATED -> "updated"
            VoiceAssistantTimerEvent.VOICE_ASSISTANT_TIMER_CANCELLED -> "cancelled"
            VoiceAssistantTimerEvent.VOICE_ASSISTANT_TIMER_FINISHED -> FINISHED
            else -> return
        }
        emit(
            mapOf(
                "event" to TIMER,
                "type" to type,
                "id" to response.timerId,
                "name" to response.name,
                "total" to response.totalSeconds,
                "left" to response.secondsLeft,
                "active" to response.isActive,
            ),
        )
    }

    fun ringStopped() = emit(mapOf("event" to RING_STOPPED))

    fun settingChanged(setting: String, value: Any) =
        emit(mapOf("event" to SETTING_CHANGED, "setting" to setting, "value" to value))

    private fun emit(event: Map<String, Any?>) {
        main.post {
            when (event["event"]) {
                STATE -> {
                    lastState = event
                    // A stopped service takes its timers with it.
                    if (event["running"] == false) timers.clear()
                }
                DUCK -> lastDuck = event
                TIMER -> {
                    val id = event["id"] as String
                    if (event["type"] == "cancelled") {
                        timers.remove(id)
                    } else {
                        timers[id] = event to SystemClock.elapsedRealtime()
                    }
                }
                // Ava rings one timer at a time, so a stop ends every finished one.
                RING_STOPPED -> timers.values.removeAll { it.first["type"] == FINISHED }
            }
            sink?.invoke(event)
        }
    }
}
