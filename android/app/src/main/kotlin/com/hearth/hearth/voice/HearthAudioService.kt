package com.hearth.hearth.voice

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.example.ava.esphome.Connected
import com.example.ava.esphome.EspHomeDevice
import com.example.ava.esphome.EspHomeState
import com.example.ava.esphome.ServerError
import com.example.ava.esphome.voiceassistant.Listening
import com.example.ava.esphome.voiceassistant.Processing
import com.example.ava.esphome.voiceassistant.Responding
import com.example.ava.esphome.voiceassistant.VoiceError
import com.example.ava.nsd.NsdRegistration
import com.example.ava.nsd.registerVoiceSatelliteNsd
import com.hearth.hearth.MainActivity
import com.hearth.hearth.R
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.plus
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import timber.log.Timber

/**
 * Runs the voice satellite: the ESPHome server Home Assistant connects to,
 * wake-word capture and voice output. Started and stopped only by Dart
 * through `com.hearth/voice`, always while the activity is visible, which
 * Android 14+ requires for a microphone foreground service.
 *
 * Each start command carries the full configuration and rebuilds the device,
 * so a settings change is just another start.
 */
class HearthAudioService : LifecycleService() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    private val lifecycleMutex = Mutex()
    private var device: EspHomeDevice? = null
    private var deviceJob: Job? = null
    private var settings: SatelliteSettings? = null
    private var nsd: NsdRegistration? = null
    private val audio = AudioCoordinator()

    override fun onCreate() {
        super.onCreate()
        instance = this
        val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (debuggable && Timber.forest().isEmpty()) Timber.plant(Timber.DebugTree())
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        val config = intent?.let(VoiceConfig::fromIntent)
        val micGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

        // startForegroundService() obliges us to go foreground even on the way
        // out, and the microphone type is refused without RECORD_AUDIO.
        val type = if (micGranted) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        } else {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        }
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification("Starting"), type)
        } catch (e: Exception) {
            Timber.e(e, "Foreground start refused")
            VoiceEvents.health(
                VoiceEvents.MIC_OPEN_FAILED,
                "Foreground service start refused: ${e.message}",
            )
            stopSelf()
            return START_NOT_STICKY
        }

        if (config == null || !micGranted) {
            if (!micGranted) {
                VoiceEvents.health(VoiceEvents.PERMISSION_MISSING, "RECORD_AUDIO is not granted")
            }
            shutDown()
            return START_NOT_STICKY
        }

        lifecycleScope.launch {
            lifecycleMutex.withLock {
                tearDown()
                bringUp(config)
            }
        }
        // A restart without the activity could not open the microphone. The
        // bridge starts the service again the next time Hearth launches.
        return START_NOT_STICKY
    }

    @SuppressLint("MissingPermission")
    private fun bringUp(config: VoiceConfig) {
        val failed = CoroutineExceptionHandler { _, error -> onDeviceFailed(error) }
        val job = SupervisorJob(lifecycleScope.coroutineContext.job)
        val context = lifecycleScope.coroutineContext + job + failed
        val settings = SatelliteSettings(config)

        val device = SatelliteBuilder(this).build(context, config, settings, audio) { id, error ->
            Timber.e(error, "Wake word model failed to load: $id")
            VoiceEvents.health(VoiceEvents.MODEL_LOAD_FAILED, "$id: ${error.message}")
        }
        this.device = device
        this.deviceJob = job
        this.settings = settings

        acquireLocks()
        device.start()
        nsd = registerVoiceSatelliteNsd(this, config.nodeName, config.port, config.mac)

        combine(device.state, device.voiceAssistant.state, settings.muted) { server, voice, muted ->
            Triple(server, voice, muted)
        }.onEach { (server, voice, muted) -> report(server, voice, muted) }
            .launchIn(lifecycleScope + job)
    }

    private fun report(server: EspHomeState, voice: EspHomeState, muted: Boolean) {
        // Outlives the device, so a rebuild keeps a mute made from Home Assistant.
        Companion.muted = muted
        if (server is ServerError) {
            // Nothing can connect, so do not keep the locks and the mDNS record.
            VoiceEvents.health(VoiceEvents.PORT_IN_USE, server.message)
            stopAfterFailure()
            return
        }
        val (state, connected) = when (voice) {
            is Connected -> "idle" to true
            is Listening -> "listening" to true
            is Processing -> "processing" to true
            is Responding -> "responding" to true
            is VoiceError -> "error" to true
            else -> "idle" to false
        }
        // Ava resets without unDuck when Home Assistant drops mid-exchange.
        if (!connected) audio.release()
        VoiceEvents.state(state, connected)
        notify(
            when {
                muted -> "Microphone muted"
                !connected -> "Waiting for Home Assistant"
                state == "idle" -> "Listening for the wake word"
                else -> state.replaceFirstChar(Char::uppercase)
            },
        )
    }

    private fun onDeviceFailed(error: Throwable) {
        Timber.e(error, "Voice satellite failed")
        if (error is MicException) {
            VoiceEvents.health(VoiceEvents.MIC_OPEN_FAILED, error.message.orEmpty())
        }
        stopAfterFailure()
    }

    private fun stopAfterFailure() {
        lifecycleScope.launch {
            lifecycleMutex.withLock { tearDown() }
            shutDown()
        }
    }

    private fun tearDown() {
        nsd?.unregister(this)
        nsd = null
        deviceJob?.cancel()
        deviceJob = null
        device?.close()
        device = null
        settings = null
        // A closed device never calls unDuck.
        audio.release()
        releaseLocks()
    }

    private fun shutDown() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun applyMuted(muted: Boolean) {
        settings?.muted?.value = muted
    }

    fun wake() {
        device?.voiceAssistant?.wakeAssistant()
    }

    override fun onDestroy() {
        tearDown()
        VoiceEvents.state("idle", connected = false, running = false)
        if (instance === this) instance = null
        super.onDestroy()
    }

    @SuppressLint("WakelockTimeout")
    private fun acquireLocks() {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$TAG::WakeLock")
            .apply { acquire() }
        // HIGH_PERF keeps Wi-Fi up with the screen off; from API 34 only
        // LOW_LATENCY is offered.
        @Suppress("DEPRECATION")
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            WifiManager.WIFI_MODE_FULL_LOW_LATENCY
        } else {
            WifiManager.WIFI_MODE_FULL_HIGH_PERF
        }
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        wifiLock = wifi.createWifiLock(mode, "$TAG::WifiLock").apply { acquire() }
    }

    private fun releaseLocks() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        wifiLock?.takeIf { it.isHeld }?.release()
        wifiLock = null
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Voice satellite",
            NotificationManager.IMPORTANCE_LOW,
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun notification(text: String): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setOngoing(true)
            .setSmallIcon(R.drawable.ic_voice_satellite)
            .setContentTitle("Hearth voice satellite")
            .setContentText(text)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(open)
            .build()
    }

    private fun notify(text: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification(text))
    }

    companion object {
        private const val TAG = "HearthAudioService"
        private const val CHANNEL_ID = "voice_satellite"
        private const val NOTIFICATION_ID = 1

        /** The running service, for calls from the channel in the same process. */
        @Volatile
        var instance: HearthAudioService? = null
            private set

        /**
         * The microphone mute, whoever set it last: Dart or the Home Assistant
         * switch. Kept for the life of the process so each start applies it.
         */
        @Volatile
        var muted = false
            private set

        fun setMuted(muted: Boolean) {
            this.muted = muted
            instance?.applyMuted(muted)
        }

        fun intent(context: Context, config: VoiceConfig): Intent =
            config.putInto(Intent(context, HearthAudioService::class.java))
    }
}
