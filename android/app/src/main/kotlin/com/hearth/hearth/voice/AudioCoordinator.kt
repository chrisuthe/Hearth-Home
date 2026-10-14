package com.hearth.hearth.voice

import com.example.ava.esphome.voiceassistant.VoiceOutput

/**
 * Whether the voice satellite wants Hearth's own playback out of the way.
 *
 * Driven by Ava's `duck` and `unDuck`, not by the voice state: Ava ducks
 * before the wake sound and for a timer ring, and the state is still idle
 * for both. Dart hears it as the `duck` event and lowers the media_kit
 * players; native outputs register a mute and get it with no round trip.
 *
 * Main thread only, as Ava's voice output is.
 */
class AudioCoordinator {
    private val mutes = mutableListOf<(Boolean) -> Unit>()

    var active = false
        private set

    /**
     * Local outputs muted while the satellite is active. Sendspin's
     * `engine.setMuted(VOICE, …)` registers here when the engine joins this
     * service; the mute is local, so other rooms in a group do not dim.
     */
    fun addMute(mute: (Boolean) -> Unit) {
        mutes += mute
        if (active) mute(true)
    }

    fun set(active: Boolean) {
        if (this.active == active) return
        this.active = active
        mutes.forEach { it(active) }
        VoiceEvents.duck(active)
    }

    /** For every path where Ava stops without calling `unDuck`. */
    fun release() = set(false)
}

/** Ava's voice output, reporting its duck and unDuck to [coordinator]. */
class CoordinatedVoiceOutput(
    private val inner: VoiceOutput,
    private val coordinator: AudioCoordinator,
) : VoiceOutput by inner {
    override fun duck() {
        inner.duck()
        coordinator.set(true)
    }

    override fun unDuck() {
        inner.unDuck()
        coordinator.set(false)
    }
}
