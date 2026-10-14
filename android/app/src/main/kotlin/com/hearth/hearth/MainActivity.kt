package com.hearth.hearth

import android.content.Intent
import com.hearth.hearth.voice.HearthAudioService
import com.hearth.hearth.voice.VoiceChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var voice: VoiceChannel? = null
    private var appUpdate: AppUpdateChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        voice = VoiceChannel(this, messenger)
        appUpdate = AppUpdateChannel(this, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        voice?.dispose()
        voice = null
        appUpdate?.dispose()
        appUpdate = null
        // Dart owns the satellite; without it nothing could mute or stop it.
        if (isFinishing) stopService(Intent(this, HearthAudioService::class.java))
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        voice?.onRequestPermissionsResult(requestCode)
    }
}
