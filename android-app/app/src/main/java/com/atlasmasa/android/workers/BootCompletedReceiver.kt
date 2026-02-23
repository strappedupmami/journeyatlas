package com.atlasmasa.android.workers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED || intent?.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            PromptQueueWorker.enqueueImmediate(context)
            PromptQueueWorker.ensurePeriodic(context)
        }
    }
}
