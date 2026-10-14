package com.hearth.hearth.capture

import android.os.Handler
import android.os.Looper

/**
 * Process-wide consent bookkeeping shared by [CaptureChannel] and
 * [ScreenCaptureService]. Touched on the main thread only.
 */
object CaptureState {
    const val CONSENT_REQUIRED = "consent_required"
    const val CONSENT_PENDING = "consent_pending"
    const val CONSENT_DENIED = "consent_denied"
    const val CONSENT_REVOKED = "consent_revoked"

    private val main = Handler(Looper.getMainLooper())

    /** Why there is no projection right now; reported on the next capture. */
    var lost: String = CONSENT_REQUIRED
        private set

    /** The consent dialog is up, so a second request must not stack another. */
    var dialogOpen = false
        private set

    private val waiters = mutableListOf<(Boolean) -> Unit>()

    /** Receives `projection` and `recordingEnded` for Dart; set by the channel. */
    var listener: ((String, Map<String, Any?>) -> Unit)? = null

    val granted: Boolean get() = ScreenCaptureService.instance != null

    fun dialogShown(waiter: ((Boolean) -> Unit)?) {
        dialogOpen = true
        waiter?.let { waiters += it }
    }

    fun addWaiter(waiter: (Boolean) -> Unit) {
        waiters += waiter
    }

    fun onGranted() = onMain {
        dialogOpen = false
        lost = CONSENT_REQUIRED
        finish(true)
        listener?.invoke("projection", mapOf("granted" to true))
    }

    fun onRefused(reason: String) = onMain {
        dialogOpen = false
        lost = reason
        finish(false)
        listener?.invoke("projection", mapOf("granted" to false, "reason" to reason))
    }

    fun onRecordingEnded(path: String, saved: Boolean) = onMain {
        listener?.invoke("recordingEnded", mapOf("path" to path, "saved" to saved))
    }

    private fun finish(ok: Boolean) {
        val pending = waiters.toList()
        waiters.clear()
        pending.forEach { it(ok) }
    }

    private fun onMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else main.post(block)
    }
}
