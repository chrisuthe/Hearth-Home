package com.hearth.hearth

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Process

/**
 * Relaunches Hearth from a process of its own (`:restart` in the manifest),
 * so a restore's settings are all read fresh, the ones read only at startup
 * included.
 *
 * Hearth cannot relaunch itself from a process it is about to kill: an
 * activity started after it has gone would be a background start, which
 * Android blocks. This one is started while Hearth is in front, ends the old
 * process, starts Hearth again, and then exits itself.
 */
class RestartActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val oldPid = intent.getIntExtra(EXTRA_PID, -1)
        if (oldPid > 0) Process.killProcess(oldPid)
        packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            ?.let(::startActivity)
        finish()
        Runtime.getRuntime().exit(0)
    }

    companion object {
        private const val EXTRA_PID = "pid"

        /** Ends this process; Hearth comes back through [RestartActivity]. */
        fun restart(activity: Activity) {
            activity.startActivity(
                Intent(activity, RestartActivity::class.java)
                    .putExtra(EXTRA_PID, Process.myPid())
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            Runtime.getRuntime().exit(0)
        }
    }
}
