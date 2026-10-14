package com.hearth.hearth.capture

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.util.DisplayMetrics
import android.view.Display
import android.view.Surface
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.hearth.hearth.MainActivity
import com.hearth.hearth.R
import timber.log.Timber
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Holds the one MediaProjection a consent grant buys, for the rest of the
 * session. Android 14 allows a single createVirtualDisplay per token, so the
 * display lives as long as the projection and only its Surface moves: the
 * ImageReader between captures, the MediaRecorder while recording.
 *
 * Everything that touches the display, reader or recorder runs on [handler].
 */
class ScreenCaptureService : Service() {
    private val thread = HandlerThread("hearth-capture").apply { start() }
    private val handler = Handler(thread.looper)
    private val encoder = Executors.newSingleThreadExecutor()

    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var latest: Image? = null
    private var recorder: MediaRecorder? = null
    private var recordingPath: String? = null
    private var panel = Panel(0, 0, 0)
    private val frameWaiters = mutableListOf<(Image?) -> Unit>()

    private data class Panel(val width: Int, val height: Int, val dpi: Int)

    private val projectionCallback = object : MediaProjection.Callback() {
        // System "stop sharing", or another app taking the projection.
        override fun onStop() = end(CaptureState.CONSENT_REVOKED)
    }

    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayChanged(displayId: Int) {
            if (displayId == Display.DEFAULT_DISPLAY) fitPanel()
        }
        override fun onDisplayAdded(displayId: Int) {}
        override fun onDisplayRemoved(displayId: Int) {}
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val channel = NotificationChannel(CHANNEL_ID, "Screen capture", NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android 14 refuses getMediaProjection until the typed FGS is running.
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } catch (e: Exception) {
            Timber.e(e, "Screen capture foreground start refused")
            refuse()
            return START_NOT_STICKY
        }
        if (projection != null) {
            // A second grant while one is held; the first still serves.
            if (instance != null) CaptureState.onGranted()
            return START_NOT_STICKY
        }

        val code = intent?.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
            ?: Activity.RESULT_CANCELED
        val data = intent?.let {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                it.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
            } else {
                @Suppress("DEPRECATION")
                it.getParcelableExtra(EXTRA_RESULT_DATA)
            }
        }
        val mp = data?.let {
            runCatching {
                getSystemService(MediaProjectionManager::class.java).getMediaProjection(code, it)
            }.onFailure { e -> Timber.e(e, "getMediaProjection failed") }.getOrNull()
        }
        if (mp == null) {
            refuse()
            return START_NOT_STICKY
        }
        // Android 14 requires the callback before createVirtualDisplay.
        mp.registerCallback(projectionCallback, handler)
        projection = mp
        handler.post {
            try {
                panel = readPanel()
                val r = newReader(panel)
                reader = r
                display = mp.createVirtualDisplay(
                    "hearth-capture",
                    panel.width,
                    panel.height,
                    panel.dpi,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    r.surface,
                    null,
                    handler,
                )
                getSystemService(DisplayManager::class.java).registerDisplayListener(displayListener, handler)
                instance = this
                CaptureState.onGranted()
            } catch (e: Exception) {
                Timber.e(e, "Virtual display creation failed")
                end(CaptureState.CONSENT_DENIED)
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        // Unpublish now: calls posted after quitSafely would never reply.
        if (instance === this) instance = null
        handler.post { end(null) }
        thread.quitSafely()
        encoder.shutdown()
        super.onDestroy()
    }

    /** Writes the current frame to [path] as a PNG. Replies with null, or an error code. */
    fun screenshot(path: String, reply: (String?, String?) -> Unit) = handler.post {
        if (recorder != null) {
            reply(ERROR_RECORDING_ACTIVE, "Screenshots are unavailable while a recording is running")
            return@post
        }
        // A static screen produces no frames, so the latest one is the screen.
        val image = latest
        if (image != null) {
            write(image, path, reply)
            return@post
        }
        lateinit var waiter: (Image?) -> Unit
        val timeout = Runnable {
            if (frameWaiters.remove(waiter)) reply(ERROR_NO_FRAME, "No frame arrived from the screen")
        }
        waiter = { img ->
            handler.removeCallbacks(timeout)
            if (img == null) {
                reply(CaptureState.CONSENT_REVOKED, "Screen capture ended")
            } else {
                write(img, path, reply)
            }
        }
        frameWaiters += waiter
        handler.postDelayed(timeout, FRAME_TIMEOUT_MS)
    }

    fun startRecording(path: String, reply: (String?, String?) -> Unit) = handler.post {
        val d = display
        if (d == null) {
            reply(CaptureState.CONSENT_REVOKED, "Screen capture ended")
            return@post
        }
        if (recorder != null) {
            reply(ERROR_RECORDING_ACTIVE, "A recording is already running")
            return@post
        }
        val (w, h) = encoderSize(panel.width, panel.height)
        val r = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(this) else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
        try {
            r.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            r.setVideoSize(w, h)
            r.setVideoFrameRate(FRAME_RATE)
            r.setVideoEncodingBitRate(BIT_RATE)
            r.setOutputFile(path)
            r.prepare()
            // Same aspect as the panel, so the mirror fills it without bars.
            swap(d, r.surface, w, h)
            r.start()
        } catch (e: Exception) {
            Timber.e(e, "Recorder start failed")
            r.release()
            swap(d, reader?.surface, panel.width, panel.height)
            File(path).delete()
            reply(ERROR_RECORDER, "Recorder failed to start: ${e.message}")
            return@post
        }
        dropLatest()
        recorder = r
        recordingPath = path
        reply(null, null)
    }

    fun stopRecording(reply: (String?, String?) -> Unit) = handler.post {
        if (recorder == null) {
            reply(ERROR_NOT_RECORDING, "No recording is running")
            return@post
        }
        val saved = finishRecording()
        // The rotation may have changed while recording.
        fitPanel()
        if (saved) reply(null, null) else reply(ERROR_EMPTY_RECORDING, "The recording captured no frames")
    }

    /** Detaches and finalizes the recorder. False when the file was discarded. */
    private fun finishRecording(): Boolean {
        val r = recorder ?: return false
        val path = recordingPath
        recorder = null
        recordingPath = null
        display?.surface = null
        val saved = try {
            r.stop()
            true
        } catch (e: RuntimeException) {
            // stop() throws when no frame reached the encoder; the file is unplayable.
            Timber.w(e, "Recorder stop failed")
            path?.let { File(it).delete() }
            false
        } finally {
            r.release()
        }
        display?.let { swap(it, reader?.surface, panel.width, panel.height) }
        return saved
    }

    private fun write(image: Image, path: String, reply: (String?, String?) -> Unit) {
        val bitmap = try {
            toBitmap(image)
        } catch (e: Exception) {
            Timber.e(e, "Frame copy failed")
            reply(ERROR_WRITE, "Could not read the frame: ${e.message}")
            return
        }
        // PNG encoding a panel-sized frame takes long enough to starve frames.
        encoder.execute {
            try {
                FileOutputStream(path).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                reply(null, null)
            } catch (e: Exception) {
                Timber.e(e, "Screenshot write failed")
                File(path).delete()
                reply(ERROR_WRITE, "Could not write the screenshot: ${e.message}")
            } finally {
                bitmap.recycle()
            }
        }
    }

    private fun toBitmap(image: Image): Bitmap {
        val plane = image.planes[0]
        val buffer = plane.buffer.rewind()
        // Rows carry padding past the visible width.
        val padded = Bitmap.createBitmap(
            plane.rowStride / plane.pixelStride,
            image.height,
            Bitmap.Config.ARGB_8888,
        )
        padded.copyPixelsFromBuffer(buffer)
        if (padded.width == image.width) return padded
        return Bitmap.createBitmap(padded, 0, 0, image.width, image.height).also { padded.recycle() }
    }

    private fun newReader(p: Panel): ImageReader =
        // Three buffers: one held as [latest], room for acquireLatestImage to drain.
        ImageReader.newInstance(p.width, p.height, PixelFormat.RGBA_8888, 3).apply {
            setOnImageAvailableListener({ r ->
                val image = try {
                    r.acquireLatestImage()
                } catch (e: IllegalStateException) {
                    null
                } ?: return@setOnImageAvailableListener
                if (r !== reader) {
                    image.close()
                    return@setOnImageAvailableListener
                }
                latest?.close()
                latest = image
                val waiting = frameWaiters.toList()
                frameWaiters.clear()
                waiting.forEach { it(image) }
            }, handler)
        }

    /** Follows a rotation by matching the display and reader to the panel. */
    private fun fitPanel() {
        val d = display ?: return
        // A recording keeps its size; the mirror letterboxes until it stops.
        if (recorder != null) return
        val now = readPanel()
        if (now == panel && reader != null) return
        panel = now
        val old = reader
        dropLatest()
        val r = newReader(now)
        reader = r
        swap(d, r.surface, now.width, now.height)
        old?.close()
    }

    /**
     * Surface first, then size. The mirror's scale is computed from the
     * consuming Surface's size when the display's configuration changes, and
     * a Surface swap alone does not change it: resizing first scales the
     * mirror for the old Surface and leaves the new one letterboxed.
     */
    private fun swap(d: VirtualDisplay, surface: Surface?, width: Int, height: Int) {
        d.surface = surface
        d.resize(width, height, panel.dpi)
    }

    private fun readPanel(): Panel {
        val metrics = DisplayMetrics()
        val d = getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
        // Real metrics follow the current rotation and include the system bars.
        @Suppress("DEPRECATION")
        d.getRealMetrics(metrics)
        return Panel(metrics.widthPixels, metrics.heightPixels, metrics.densityDpi)
    }

    private fun dropLatest() {
        latest?.close()
        latest = null
    }

    /** Ends the session; [reason] is what the next capture reports. */
    private fun end(reason: String?) {
        if (projection == null && display == null) return
        recordingPath?.let { path ->
            val saved = finishRecording()
            CaptureState.onRecordingEnded(path, saved)
        }
        val waiting = frameWaiters.toList()
        frameWaiters.clear()
        waiting.forEach { it(null) }
        runCatching { getSystemService(DisplayManager::class.java).unregisterDisplayListener(displayListener) }
        dropLatest()
        display?.release()
        display = null
        reader?.close()
        reader = null
        projection?.let {
            it.unregisterCallback(projectionCallback)
            it.stop()
        }
        projection = null
        if (instance === this) instance = null
        CaptureState.onRefused(reason ?: CaptureState.CONSENT_REQUIRED)
        if (reason != null) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun refuse() {
        CaptureState.onRefused(CaptureState.CONSENT_DENIED)
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setOngoing(true)
            .setSmallIcon(R.drawable.ic_screen_capture)
            .setContentTitle("Hearth screen capture")
            .setContentText("Screenshots and recordings are allowed")
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(open)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "screen_capture"
        // HearthAudioService holds 1.
        private const val NOTIFICATION_ID = 2
        private const val EXTRA_RESULT_CODE = "resultCode"
        private const val EXTRA_RESULT_DATA = "resultData"
        private const val FRAME_TIMEOUT_MS = 3000L
        private const val FRAME_RATE = 30
        // Matches the Pi's ffmpeg -b:v 4000k.
        private const val BIT_RATE = 4_000_000

        const val ERROR_RECORDING_ACTIVE = "recording_active"
        const val ERROR_NOT_RECORDING = "not_recording"
        const val ERROR_EMPTY_RECORDING = "empty_recording"
        const val ERROR_NO_FRAME = "no_frame"
        const val ERROR_RECORDER = "recorder_failed"
        const val ERROR_WRITE = "write_failed"

        /** The live session, for calls from the channel in the same process. */
        @Volatile
        var instance: ScreenCaptureService? = null
            private set

        fun intent(context: Context, resultCode: Int, data: Intent): Intent =
            Intent(context, ScreenCaptureService::class.java)
                .putExtra(EXTRA_RESULT_CODE, resultCode)
                .putExtra(EXTRA_RESULT_DATA, data)

        /**
         * The panel size, or the largest smaller size with the same aspect that
         * an H.264 encoder on this device accepts. Kiosk panels often exceed
         * what a tablet's encoder level allows.
         */
        fun encoderSize(width: Int, height: Int): Pair<Int, Int> {
            val caps = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .filter { it.isEncoder && it.supportedTypes.any { t -> t.equals(MediaFormat.MIMETYPE_VIDEO_AVC, true) } }
                .mapNotNull { runCatching { it.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC).videoCapabilities }.getOrNull() }
            fun even(v: Double) = (v.toInt() / 2) * 2
            var scale = 1.0
            while (scale >= 0.25) {
                val w = even(width * scale)
                val h = even(height * scale)
                if (caps.any { it.isSizeSupported(w, h) }) return w to h
                scale -= 0.05
            }
            return even(width / 2.0) to even(height / 2.0)
        }
    }
}
