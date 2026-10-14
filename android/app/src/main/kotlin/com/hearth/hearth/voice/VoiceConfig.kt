package com.hearth.hearth.voice

import android.content.Intent
import android.media.MediaRecorder

/**
 * What Dart hands over on `start`. Hearth's `hub_config.json` is the only
 * store; nothing here is persisted on the native side.
 */
data class VoiceConfig(
    val name: String,
    val mac: String,
    val port: Int,
    val wakeWords: List<String>,
    val sensitivity: String,
    val audioSource: String,
    val wakeSound: Boolean,
    /** Media player volume, 0.0–1.0, as Home Assistant last set it. */
    val volume: Float,
    // Not part of the `start` payload: the last `setMuted` value.
    val muted: Boolean,
) {
    /** ESPHome node name: lowercase letters, digits and hyphens. */
    val nodeName: String
        get() = name.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-').ifEmpty { "hearth" }

    val audioSourceId: Int
        get() = when (audioSource) {
            "mic" -> MediaRecorder.AudioSource.MIC
            "voiceCommunication" -> MediaRecorder.AudioSource.VOICE_COMMUNICATION
            "unprocessed" -> MediaRecorder.AudioSource.UNPROCESSED
            else -> MediaRecorder.AudioSource.VOICE_RECOGNITION
        }

    /**
     * Scale applied to a wake-word model's own probability cutoff. The steps
     * approximate the three levels Home Assistant Voice PE offers for
     * okay_nabu; they have not been tuned on hardware.
     */
    val cutoffScale: Float
        get() = when (sensitivity) {
            "moderately" -> 0.8f
            "very" -> 0.65f
            else -> 1.0f
        }

    fun putInto(intent: Intent): Intent = intent
        .putExtra("name", name)
        .putExtra("mac", mac)
        .putExtra("port", port)
        .putStringArrayListExtra("wakeWords", ArrayList(wakeWords))
        .putExtra("sensitivity", sensitivity)
        .putExtra("audioSource", audioSource)
        .putExtra("wakeSound", wakeSound)
        .putExtra("volume", volume)
        .putExtra("muted", muted)

    companion object {
        const val DEFAULT_PORT = 6053

        fun fromArguments(args: Map<*, *>, muted: Boolean) = VoiceConfig(
            name = args["name"] as? String ?: "",
            mac = args["mac"] as? String ?: "",
            port = (args["port"] as? Number)?.toInt() ?: DEFAULT_PORT,
            wakeWords = (args["wakeWords"] as? List<*>)?.filterIsInstance<String>().orEmpty(),
            sensitivity = args["sensitivity"] as? String ?: "",
            audioSource = args["audioSource"] as? String ?: "",
            wakeSound = args["wakeSound"] as? Boolean ?: true,
            volume = ((args["volume"] as? Number)?.toFloat() ?: 1.0f).coerceIn(0f, 1f),
            muted = muted,
        )

        fun fromIntent(intent: Intent): VoiceConfig? {
            val mac = intent.getStringExtra("mac") ?: return null
            return VoiceConfig(
                name = intent.getStringExtra("name") ?: "",
                mac = mac,
                port = intent.getIntExtra("port", DEFAULT_PORT),
                wakeWords = intent.getStringArrayListExtra("wakeWords").orEmpty(),
                sensitivity = intent.getStringExtra("sensitivity") ?: "",
                audioSource = intent.getStringExtra("audioSource") ?: "",
                wakeSound = intent.getBooleanExtra("wakeSound", true),
                volume = intent.getFloatExtra("volume", 1.0f),
                muted = intent.getBooleanExtra("muted", false),
            )
        }
    }
}
