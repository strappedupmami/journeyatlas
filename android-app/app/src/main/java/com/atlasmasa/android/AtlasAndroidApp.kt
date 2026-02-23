package com.atlasmasa.android

import android.app.Application
import android.os.StrictMode
import androidx.work.Configuration
import com.atlasmasa.android.workers.PromptQueueWorker

class AtlasAndroidApp : Application(), Configuration.Provider {
    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) {
            StrictMode.setThreadPolicy(
                StrictMode.ThreadPolicy.Builder()
                    .detectDiskReads()
                    .detectDiskWrites()
                    .detectNetwork()
                    .penaltyLog()
                    .build()
            )
            StrictMode.setVmPolicy(
                StrictMode.VmPolicy.Builder()
                    .detectLeakedClosableObjects()
                    .detectActivityLeaks()
                    .penaltyLog()
                    .build()
            )
        }
        // Resume persisted queue and keep a watchdog for process death/reboots.
        PromptQueueWorker.enqueueImmediate(this)
        PromptQueueWorker.ensurePeriodic(this)
    }

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder().setMinimumLoggingLevel(android.util.Log.INFO).build()
}
