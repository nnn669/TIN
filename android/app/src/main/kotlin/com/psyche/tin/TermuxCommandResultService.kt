package com.psyche.tin

import android.app.Service
import android.content.Intent
import android.os.IBinder

class TermuxCommandResultService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val requestId = intent?.getIntExtra(TermuxCommandHandler.EXTRA_REQUEST_ID, -1) ?: -1
        if (requestId >= 0) {
            TermuxCommandResultRegistry.complete(
                requestId,
                intent?.getBundleExtra(TermuxCommandHandler.EXTRA_COMMAND_RESULT),
            )
        }
        stopSelf(startId)
        return START_NOT_STICKY
    }
}
