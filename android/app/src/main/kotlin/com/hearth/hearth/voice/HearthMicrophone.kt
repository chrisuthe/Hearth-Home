package com.hearth.hearth.voice

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AudioEffect
import android.media.audiofx.NoiseSuppressor
import com.example.ava.esphome.microphone.Microphone
import timber.log.Timber
import java.nio.ByteBuffer

/** The microphone could not be opened, or stopped delivering audio. */
class MicException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * 16 kHz mono capture for the wake word and the pipeline. Differs from the
 * library's AudioRecordMicrophone in two ways: it attaches the platform echo
 * canceller and noise suppressor where the device has them, and it leaves the
 * audio mode and speakerphone routing alone, which belong to Hearth's players.
 */
class HearthMicrophone(private val audioSource: Int) : Microphone {
    private val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL, ENCODING)
    private val buffer = ByteBuffer.allocateDirect(bufferSize.coerceAtLeast(1))
    private var audioRecord: AudioRecord? = null
    private var effects: List<AudioEffect> = emptyList()

    // The service only builds a device once RECORD_AUDIO is granted.
    @SuppressLint("MissingPermission")
    override fun start() {
        if (bufferSize <= 0) throw MicException("16 kHz mono capture is not supported")
        val record = try {
            AudioRecord(audioSource, SAMPLE_RATE, CHANNEL, ENCODING, bufferSize * 2)
        } catch (e: Exception) {
            throw MicException(e.message ?: "AudioRecord could not be created", e)
        }
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            throw MicException("AudioRecord failed to initialize")
        }
        effects = attachEffects(record.audioSessionId)
        try {
            record.startRecording()
        } catch (e: Exception) {
            release(record)
            throw MicException(e.message ?: "Recording could not start", e)
        }
        audioRecord = record
    }

    // Many tablets route capture through a vendor pipeline and expose no
    // attachable effects. That is a normal configuration, not a fault.
    private fun attachEffects(sessionId: Int): List<AudioEffect> = buildList {
        if (AcousticEchoCanceler.isAvailable()) {
            runCatching { AcousticEchoCanceler.create(sessionId) }.getOrNull()?.let(::add)
        }
        if (NoiseSuppressor.isAvailable()) {
            runCatching { NoiseSuppressor.create(sessionId) }.getOrNull()?.let(::add)
        }
        forEach { runCatching { it.enabled = true } }
        Timber.d("Platform audio effects attached: ${map { it.javaClass.simpleName }}")
    }

    override fun read(): ByteBuffer {
        val record = audioRecord ?: error("Microphone not started")
        val read = record.read(buffer, bufferSize)
        if (read < 0) throw MicException("Reading audio failed ($read)")
        // AudioRecord.read ignores the buffer's position and limit.
        buffer.position(0)
        buffer.limit(read)
        return buffer
    }

    override fun stop() {
        audioRecord?.let(::release)
        audioRecord = null
    }

    override fun close() = stop()

    private fun release(record: AudioRecord) {
        effects.forEach { runCatching { it.release() } }
        effects = emptyList()
        record.release()
    }

    private companion object {
        const val SAMPLE_RATE = 16000
        const val CHANNEL = AudioFormat.CHANNEL_IN_MONO
        const val ENCODING = AudioFormat.ENCODING_PCM_16BIT
    }
}
