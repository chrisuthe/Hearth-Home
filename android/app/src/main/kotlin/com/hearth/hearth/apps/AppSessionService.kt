package com.hearth.hearth.apps

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Outline
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.widget.ImageView
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.hearth.hearth.MainActivity
import com.hearth.hearth.R

/**
 * Keeps Hearth's process alive while another app is in front, so alarms,
 * timers, casts and notifications still reach Dart, and shows a floating
 * Hearth button over that app.
 *
 * Started on the first app launch and runs until Hearth's activity finishes:
 * Hearth cannot tell when the other app's task closes.
 */
class AppSessionService : Service() {
    private var button: ImageView? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        val channel = NotificationChannel(CHANNEL_ID, "App session", NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // startForegroundService() obliges a startForeground on every start.
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification(), type)
        } catch (e: Exception) {
            Log.e(TAG, "App session foreground start refused", e)
            stopSelf()
            return START_NOT_STICKY
        }
        updateButton()
        // Nothing to keep alive without the activity; the next launch starts it.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        hideButton()
        super.onDestroy()
    }

    /** Shows the button while Hearth is behind another app. Main thread. */
    private fun updateButton() {
        if (!MainActivity.resumed && Settings.canDrawOverlays(this)) showButton() else hideButton()
    }

    private fun showButton() {
        if (button != null) return
        val size = dp(BUTTON_DP)
        val view = ImageView(this).apply {
            setImageResource(R.mipmap.ic_launcher)
            scaleType = ImageView.ScaleType.CENTER_CROP
            contentDescription = "Back to Hearth"
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setOval(0, 0, view.width, view.height)
                }
            }
            clipToOutline = true
            setOnClickListener { startActivity(frontIntent(this@AppSessionService)) }
        }
        val params = WindowManager.LayoutParams(
            size,
            size,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            // Bottom-start: picture-in-picture defaults to bottom-end.
            gravity = Gravity.BOTTOM or Gravity.START
            x = dp(MARGIN_DP)
            y = dp(MARGIN_DP)
        }
        try {
            getSystemService(WindowManager::class.java).addView(view, params)
            button = view
        } catch (e: Exception) {
            // The permission can be revoked between the check and the add.
            Log.w(TAG, "Floating button refused", e)
        }
    }

    private fun hideButton() {
        val view = button ?: return
        button = null
        // Revoking the permission removes the window without telling us.
        if (view.isAttachedToWindow) getSystemService(WindowManager::class.java).removeView(view)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(this, 0, frontIntent(this), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setOngoing(true)
            .setSmallIcon(R.drawable.ic_app_session)
            .setContentTitle("Hearth")
            .setContentText("Hearth stays awake while another app is open.")
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(open)
            .build()
    }

    companion object {
        private const val TAG = "AppSessionService"
        private const val CHANNEL_ID = "app_session"
        // HearthAudioService holds 1, ScreenCaptureService 2.
        private const val NOTIFICATION_ID = 3
        private const val BUTTON_DP = 56
        private const val MARGIN_DP = 16

        @Volatile
        private var instance: AppSessionService? = null

        /** Brings Hearth back over whatever app is in front. */
        fun frontIntent(context: Context): Intent =
            Intent(context, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
            )

        /** Starts the session, or refreshes it when already running. From the visible activity. */
        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, AppSessionService::class.java))
        }

        /** Hearth came to the front or went behind; shows or hides the button. Main thread. */
        fun onHearthResumedChanged() {
            instance?.updateButton()
        }
    }
}
