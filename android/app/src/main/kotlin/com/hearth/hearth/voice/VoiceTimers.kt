package com.hearth.hearth.voice

import com.example.ava.esphome.voiceassistant.VoiceAssistant
import com.example.ava.esphome.voiceassistant.VoiceTimer
import com.example.ava.server.Server
import com.example.esphomeproto.api.VoiceAssistantTimerEvent
import com.example.esphomeproto.api.VoiceAssistantTimerEventResponse
import com.example.esphomeproto.api.voiceAssistantTimerEventResponse
import com.google.protobuf.MessageLite
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach

/**
 * Ava's server, with every timer event from Home Assistant also sent to Dart.
 * Ava still handles each one, so its ring, stop word and wake word work as
 * they do in the fork.
 */
class TimerEventTap(private val inner: Server) : Server by inner {
    override fun start(port: Int): Flow<MessageLite> = inner.start(port).onEach {
        if (it is VoiceAssistantTimerEventResponse) VoiceEvents.timer(it)
    }
}

/**
 * The timer ring, played by Ava. A Home Assistant timer rings on its own; a
 * local Hearth timer is handed to Ava as a finished timer of its own, so the
 * stop word and a wake word end either one the same way.
 */
class TimerRing(private val voiceAssistant: VoiceAssistant) {
    var ringing = false
        private set

    /** Emits `ringStopped` when Ava's ringing timer clears, whatever cleared it. */
    fun watch(): Flow<Boolean> = voiceAssistant.allTimers
        .map { timers -> timers.any { it is VoiceTimer.Ringing } }
        .distinctUntilChanged()
        .onEach {
            if (ringing && !it) VoiceEvents.ringStopped()
            ringing = it
        }

    suspend fun start() {
        voiceAssistant.handleMessage(
            voiceAssistantTimerEventResponse {
                eventType = VoiceAssistantTimerEvent.VOICE_ASSISTANT_TIMER_FINISHED
                timerId = LOCAL_TIMER_ID
            },
        )
    }

    fun stop() = voiceAssistant.stopTimer()

    /** The device is closing; its flows end without reporting the ring's end. */
    fun release() {
        if (ringing) VoiceEvents.ringStopped()
        ringing = false
    }

    private companion object {
        const val LOCAL_TIMER_ID = "hearth-local"
    }
}
