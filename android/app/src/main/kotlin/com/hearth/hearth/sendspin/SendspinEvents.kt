package com.hearth.hearth.sendspin

import android.os.Handler
import android.os.Looper

/**
 * Native-to-Dart events on `com.hearth/sendspin/events`. A process-wide relay
 * for the same reason as `VoiceEvents`: the service outlives any one Flutter
 * engine.
 */
object SendspinEvents {
    const val STATE = "state"
    const val OUTPUT_DELAY = "outputDelay"
    const val LAST_PLAYBACK_SERVER = "lastPlaybackServer"
    const val HEALTH = "health"

    const val LISTENER_FAILED = "listenerFailed"
    const val ADVERTISE_FAILED = "advertiseFailed"
    const val SERVER_LACKS_ENCRYPTION = "serverLacksEncryption"
    const val DIALLED_UNSUPPORTED = "dialledUnsupported"
    const val SECRETS_UNREADABLE = "secretsUnreadable"

    private val main = Handler(Looper.getMainLooper())
    private var owner: Any? = null
    private var sink: ((Map<String, Any?>) -> Unit)? = null
    private var lastState: Map<String, Any?>? = null

    /** Main thread only. A new listener is caught up with the current state. */
    fun attach(owner: Any, sink: (Map<String, Any?>) -> Unit) {
        this.owner = owner
        this.sink = sink
        lastState?.let { sink(it) }
    }

    /** Main thread only. A no-op unless [owner] attached the current listener. */
    fun detach(owner: Any) {
        if (this.owner !== owner) return
        this.owner = null
        sink = null
    }

    fun state(state: Map<String, Any?>) = emit(state + ("event" to STATE))

    fun outputDelay(ms: Int) = emit(mapOf("event" to OUTPUT_DELAY, "ms" to ms))

    fun lastPlaybackServer(serverId: String) =
        emit(mapOf("event" to LAST_PLAYBACK_SERVER, "serverId" to serverId))

    fun health(code: String, message: String) =
        emit(mapOf("event" to HEALTH, "code" to code, "message" to message))

    private fun emit(event: Map<String, Any?>) {
        main.post {
            if (event["event"] == STATE) lastState = event
            sink?.invoke(event)
        }
    }
}
