package com.hearth.hearth.sendspin

import android.content.Context
import android.media.AudioManager
import kotlin.math.roundToInt

/**
 * The device's media volume, `STREAM_MUSIC`, as 0.0–1.0. Sendspin plays on
 * it, and so does media_kit (assumed), so it is the one volume the system
 * slider and a Sendspin server both move.
 */
class MediaVolume(context: Context) {
    private val audio = context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    val max: Int get() = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)

    val index: Int get() = audio.getStreamVolume(AudioManager.STREAM_MUSIC)

    fun get(): Float = max.takeIf { it > 0 }?.let { index.toFloat() / it } ?: 0f

    /** Sets the volume with no system UI. Returns the index set. */
    fun set(volume: Float): Int {
        val index = (volume.coerceIn(0f, 1f) * max).roundToInt()
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
        return index
    }
}
