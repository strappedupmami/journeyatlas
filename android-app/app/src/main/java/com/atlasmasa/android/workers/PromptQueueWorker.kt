package com.atlasmasa.android.workers

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.atlasmasa.android.data.AtlasRepository
import java.util.concurrent.TimeUnit

class PromptQueueWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val repo = AtlasRepository.get(applicationContext)
        val runtimeTick = repo.runAdaptiveBusinessRuntimeTick(trigger = "worker")
        val processedCount = repo.processQueuedPromptsBatch()
        val hasQueued = repo.hasQueuedItems()
        val keepAdaptiveRuntimeAlive = repo.shouldKeepAdaptiveRuntimeAlive()
        if ((processedCount > 0 || runtimeTick.enqueuedPrompt) && hasQueued) {
            enqueueImmediate(applicationContext, delayMs = 1_000)
        } else if (keepAdaptiveRuntimeAlive) {
            // Keep adaptive runtime progressing between periodic WorkManager windows.
            enqueueImmediate(applicationContext, delayMs = 90_000)
        }
        return Result.success()
    }

    companion object {
        private const val UNIQUE_IMMEDIATE = "atlas_prompt_queue_worker_immediate"
        private const val UNIQUE_PERIODIC = "atlas_prompt_queue_worker_periodic"

        fun enqueueImmediate(context: Context, delayMs: Long = 0) {
            val req = OneTimeWorkRequestBuilder<PromptQueueWorker>()
                .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
                .addTag(UNIQUE_IMMEDIATE)
                .build()
            WorkManager.getInstance(context)
                .enqueueUniqueWork(UNIQUE_IMMEDIATE, ExistingWorkPolicy.APPEND_OR_REPLACE, req)
        }

        fun ensurePeriodic(context: Context) {
            val req = PeriodicWorkRequestBuilder<PromptQueueWorker>(15, TimeUnit.MINUTES)
                .addTag(UNIQUE_PERIODIC)
                .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(UNIQUE_PERIODIC, ExistingWorkPolicy.KEEP, req)
        }
    }
}
