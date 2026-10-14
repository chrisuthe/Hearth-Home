package com.hearth.hearth.voice

import com.example.ava.esphome.wakeword.WakeWord
import com.example.ava.wakewords.microwakeword.MicroWakeWordDetector
import com.example.ava.wakewords.microwakeword.MicroWakeWordModel
import com.example.ava.wakewords.models.WakeWordWithId
import java.nio.ByteBuffer

/**
 * The library's MicroWakeWord, except that a model which fails to load is
 * reported instead of only logged.
 */
class HearthWakeWord(
    private val onLoadFailed: (id: String, error: Throwable) -> Unit,
) : WakeWord {
    private var detector: MicroWakeWordDetector? = null

    override suspend fun setWakeWords(wakeWords: List<WakeWordWithId>) {
        clearWakeWords()
        detector = MicroWakeWordDetector(wakeWords.mapNotNull { it.toModelOrNull() })
    }

    override fun clearWakeWords() {
        detector?.close()
        detector = null
    }

    override fun detect(audio: ByteBuffer): List<String> =
        detector?.detect(audio)?.map { it.id }?.toList() ?: emptyList()

    override fun close() = clearWakeWords()

    private suspend fun WakeWordWithId.toModelOrNull() = runCatching {
        MicroWakeWordModel(
            id = id,
            model = load(),
            probabilityCutoff = wakeWord.micro.probability_cutoff,
            slidingWindowSize = wakeWord.micro.sliding_window_size,
        )
    }.onFailure { onLoadFailed(id, it) }.getOrNull()
}
