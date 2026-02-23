package com.atlasmasa.android.data

import android.content.Context
import com.atlasmasa.android.BuildConfig
import com.atlasmasa.android.domain.AccountTier
import com.atlasmasa.android.domain.AtlasSessionState
import com.atlasmasa.android.domain.AuthProvider
import com.atlasmasa.android.domain.FeedItem
import com.atlasmasa.android.domain.LocalReasoningEngine
import com.atlasmasa.android.domain.MemoryRecord
import com.atlasmasa.android.domain.PromptQueueItem
import com.atlasmasa.android.domain.PromptQueueStatus
import com.atlasmasa.android.domain.SurveyChoice
import com.atlasmasa.android.domain.SurveyQuestion
import com.atlasmasa.android.domain.UserNote
import com.atlasmasa.android.domain.WorkspaceLane
import com.atlasmasa.android.domain.WorkspaceSession
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import java.util.UUID

class AtlasRepository private constructor(
    context: Context,
    private val sessionPrefs: SessionPreferences,
    private val apiClient: ApiClient,
) {
    private val dao = AtlasDatabase.get(context).dao()
    private val localReasoningEngine = LocalReasoningEngine()
    private val availableCores = Runtime.getRuntime().availableProcessors().coerceAtLeast(1)
    private val highPerfDevice = availableCores >= 8

    private val maxQueueItems = 200
    private val maxQueueBatch = when {
        highPerfDevice && BuildConfig.ENABLE_HIGH_PERF_BURST -> BuildConfig.LOCAL_QUEUE_MAX_BATCH_BASE + 2
        else -> BuildConfig.LOCAL_QUEUE_MAX_BATCH_BASE
    }
    private val maxQueueRuntimeMs = when {
        highPerfDevice && BuildConfig.ENABLE_HIGH_PERF_BURST -> (BuildConfig.LOCAL_QUEUE_MAX_RUNTIME_MS_BASE + 1500).toLong()
        else -> BuildConfig.LOCAL_QUEUE_MAX_RUNTIME_MS_BASE.toLong()
    }
    private val queueRetentionMs = 7L * 24L * 60L * 60L * 1000L
    private val memoryRetentionMs = 120L * 24L * 60L * 60L * 1000L

    fun observeSessionState(): Flow<AtlasSessionState> = sessionPrefs.observeState()

    fun observeNotes(): Flow<List<UserNote>> = dao.observeNotes().map { list -> list.map { it.toDomain() } }

    fun observePromptQueue(): Flow<List<PromptQueueItem>> = dao.observeQueue().map { list -> list.map { it.toDomain() } }

    fun observeMemoryRecords(): Flow<List<MemoryRecord>> = dao.observeMemory().map { list -> list.map { it.toDomain() } }

    fun observeWorkspaceSessions(): Flow<List<WorkspaceSession>> = dao.observeWorkspaceSessions().map { list -> list.map { it.toDomain() } }

    suspend fun addSystemOutput(line: String) {
        val current = sessionPrefs.observeState().first()
        val next = current.copy(systemOutput = (current.systemOutput + line).takeLast(80))
        sessionPrefs.saveState(next)
    }

    suspend fun refreshHealth() {
        val state = sessionPrefs.observeState().first()
        val result = apiClient.healthCapabilities()
        val line = result.fold(
            onSuccess = { caps ->
                "API health ok: google=${caps.googleOAuth} apple=${caps.appleOAuth} passkey=${caps.passkey} billing=${caps.billing}"
            },
            onFailure = {
                "API health unavailable. Local-first mode remains active."
            }
        )
        sessionPrefs.saveState(state.copy(systemOutput = (state.systemOutput + line).takeLast(80)))
    }

    suspend fun signIn(provider: AuthProvider, label: String) {
        val state = sessionPrefs.observeState().first()
        sessionPrefs.saveState(
            state.copy(
                isSignedIn = true,
                accountProvider = provider,
                accountLabel = label,
                accountTier = AccountTier.LOCAL_CORE,
                systemOutput = (state.systemOutput + "Signed in with ${provider.name.lowercase()} (local core tier active)").takeLast(80),
            )
        )
    }

    suspend fun signOut() {
        val state = sessionPrefs.observeState().first()
        sessionPrefs.saveState(
            state.copy(
                isSignedIn = false,
                accountProvider = AuthProvider.GUEST,
                accountLabel = "Guest Operator",
                accountTier = AccountTier.LOCAL_CORE,
                systemOutput = (state.systemOutput + "Signed out. Session retained locally.").takeLast(80),
            )
        )
    }

    suspend fun setLanguage(languageCode: String) {
        val state = sessionPrefs.observeState().first()
        sessionPrefs.saveState(state.copy(languageCode = languageCode))
    }

    suspend fun submitCheckIn(
        daily: String,
        mid: String,
        long: String,
        blockers: String,
        mood: String,
        energy: Int,
        gymToday: Boolean,
        moneyToday: Boolean,
    ) {
        val state = sessionPrefs.observeState().first()
        val next = state.copy(
            dailyPriority = daily,
            midTermGoal = mid,
            longTermVision = long,
            blockers = blockers,
            mood = mood,
            energy = energy,
            gymToday = gymToday,
            moneyToday = moneyToday,
        )
        sessionPrefs.saveState(next)

        val tags = mutableListOf("checkin", mood.lowercase())
        if (gymToday) tags += "gym_yes" else tags += "gym_no"
        if (moneyToday) tags += "money_yes" else tags += "money_no"

        dao.upsertMemory(
            MemoryEntity(
                id = UUID.randomUUID().toString(),
                type = "execution_checkin",
                source = "android",
                weight = if (moneyToday) 0.92 else 0.7,
                recency = System.currentTimeMillis(),
                tagsCsv = tags.joinToString(","),
                value = "daily=$daily | mid=$mid | long=$long | blocker=$blockers",
            )
        )

        dao.upsertWorkspaceSession(
            WorkspaceSessionEntity(
                id = UUID.randomUUID().toString(),
                lane = WorkspaceLane.COMMAND,
                title = if (daily.isBlank()) "Daily check-in" else daily.take(60),
                summary = "Mood=$mood Energy=$energy Gym=$gymToday Money=$moneyToday",
                updatedAtEpochMs = System.currentTimeMillis(),
            )
        )
    }

    suspend fun upsertNote(title: String, content: String) {
        val cleanTitle = title.ifBlank { "Untitled note" }.take(100)
        val cleanContent = content.trim().take(12_000)
        if (cleanContent.isBlank()) return

        val note = NoteEntity(
            id = UUID.randomUUID().toString(),
            title = cleanTitle,
            content = cleanContent,
            createdAtEpochMs = System.currentTimeMillis(),
        )
        dao.upsertNote(note)
        dao.upsertMemory(
            MemoryEntity(
                id = UUID.randomUUID().toString(),
                type = "note",
                source = "android",
                weight = 0.64,
                recency = System.currentTimeMillis(),
                tagsCsv = "notes,manual",
                value = "${note.title}: ${note.content.take(220)}",
            )
        )
    }

    suspend fun enqueuePrompt(prompt: String): Boolean {
        val trimmedPrompt = prompt.trim()
        if (trimmedPrompt.isEmpty()) return false

        val currentQueueSize = dao.totalQueueCount()
        if (currentQueueSize >= maxQueueItems) {
            addSystemOutput("Queue limit reached ($maxQueueItems). Clear completed items to continue.")
            return false
        }

        dao.upsertQueueItem(
            PromptQueueEntity(
                id = UUID.randomUUID().toString(),
                prompt = trimmedPrompt.take(2_000),
                status = PromptQueueStatus.QUEUED,
                createdAtEpochMs = System.currentTimeMillis(),
                startedAtEpochMs = null,
                completedAtEpochMs = null,
                progress = 0.0,
                checkpointNote = "Queued",
                outputSummary = null,
                nextAction = null,
                confidence = null,
                errorMessage = null,
            )
        )
        return true
    }

    suspend fun processNextQueuedPrompt(): Boolean = withContext(Dispatchers.IO) {
        val queued = dao.nextQueuedItem() ?: return@withContext false
        dao.upsertQueueItem(
            queued.copy(
                status = PromptQueueStatus.RUNNING,
                startedAtEpochMs = System.currentTimeMillis(),
                progress = 0.2,
                checkpointNote = "Model running",
                errorMessage = null,
            )
        )

        return@withContext runCatching {
            val notes = dao.listRecentNotes(4).map { it.toDomain() }
            val result = localReasoningEngine.reason(queued.prompt, notes)
            dao.upsertQueueItem(
                queued.copy(
                    status = PromptQueueStatus.DONE,
                    progress = 1.0,
                    completedAtEpochMs = System.currentTimeMillis(),
                    checkpointNote = "Completed",
                    outputSummary = result.summary,
                    nextAction = result.nextAction,
                    confidence = result.confidence,
                    errorMessage = null,
                )
            )
            dao.upsertMemory(
                MemoryEntity(
                    id = UUID.randomUUID().toString(),
                    type = "queue_output",
                    source = "android_local_model",
                    weight = result.confidence,
                    recency = System.currentTimeMillis(),
                    tagsCsv = "queue,reasoning",
                    value = "${result.summary} | ${result.nextAction}",
                )
            )
            true
        }.getOrElse { err ->
            dao.upsertQueueItem(
                queued.copy(
                    status = PromptQueueStatus.FAILED,
                    completedAtEpochMs = System.currentTimeMillis(),
                    progress = 1.0,
                    checkpointNote = "Failed",
                    errorMessage = err.message ?: "Unknown queue error",
                )
            )
            true
        }
    }

    suspend fun processQueuedPromptsBatch(): Int = withContext(Dispatchers.IO) {
        val startedAt = System.currentTimeMillis()
        var processed = 0
        while (processed < maxQueueBatch && (System.currentTimeMillis() - startedAt) < maxQueueRuntimeMs) {
            val didProcess = processNextQueuedPrompt()
            if (!didProcess) break
            processed += 1
        }
        if (processed > 0) {
            trimOldOperationalData()
            addSystemOutput(
                "Queue batch processed=$processed; cores=$availableCores; mode=" +
                    if (highPerfDevice) "high_performance" else "balanced"
            )
        }
        processed
    }

    suspend fun hasQueuedItems(): Boolean = withContext(Dispatchers.IO) {
        dao.queuedCount() > 0
    }

    suspend fun generateFeed(): List<FeedItem> {
        val state = sessionPrefs.observeState().first()
        val memory = dao.listRecentMemory(8)
        val feed = mutableListOf<FeedItem>()

        if (state.dailyPriority.isNotBlank()) {
            feed += FeedItem(
                title = "Execute daily focus",
                summary = state.dailyPriority,
                whyNow = "Daily priority drives compounding momentum.",
                priority = "high"
            )
        }

        if (!state.gymToday) {
            feed += FeedItem(
                title = "Protect cognitive performance",
                summary = "Move your body for 20-30 minutes to improve decision quality and stress control.",
                whyNow = "Energy and emotional regulation strongly impact income execution quality.",
                priority = "high"
            )
        }

        if (!state.moneyToday) {
            feed += FeedItem(
                title = "Income trigger",
                summary = "Run one direct revenue action now (offer outreach, close follow-up, or pricing action).",
                whyNow = "Daily revenue contact increases weekly conversion odds.",
                priority = "critical"
            )
        }

        memory.take(3).forEachIndexed { idx, m ->
            val clean = m.value.replace('\n', ' ')
            feed += FeedItem(
                title = "Memory-backed action ${idx + 1}",
                summary = clean.take(140),
                whyNow = "Derived from your long-term Atlas memory graph.",
                priority = if (m.weight > 0.85) "high" else "normal"
            )
        }

        if (feed.isEmpty()) {
            feed += FeedItem(
                title = "Start your first execution cycle",
                summary = "Complete check-in, add one note, and enqueue one prompt.",
                whyNow = "The system unlocks proactive orchestration after base telemetry is available.",
                priority = "normal"
            )
        }

        return feed.take(8)
    }

    suspend fun surveyQuestions(languageCode: String): List<SurveyQuestion> {
        val english = languageCode.lowercase().startsWith("en")
        return listOf(
            SurveyQuestion(
                id = "income_mode",
                title = if (english) "How do you currently make money?" else "איך אתה מייצר הכנסה כרגע?",
                choices = listOf(
                    SurveyChoice("salary", if (english) "Salary" else "משכורת"),
                    SurveyChoice("business", if (english) "Business income" else "הכנסה מעסק"),
                    SurveyChoice("mixed", if (english) "Both" else "גם וגם"),
                    SurveyChoice("none", if (english) "Not yet" else "עדיין לא"),
                )
            ),
            SurveyQuestion(
                id = "mobility_pattern",
                title = if (english) "How mobile is your lifestyle?" else "כמה נייד אורח החיים שלך?",
                choices = listOf(
                    SurveyChoice("local", if (english) "Mostly local" else "בעיקר מקומי"),
                    SurveyChoice("regional", if (english) "Regional travel" else "נסיעות אזוריות"),
                    SurveyChoice("rolling", if (english) "Rolling / road-based" else "על הדרך רוב הזמן"),
                )
            ),
            SurveyQuestion(
                id = "execution_blocker",
                title = if (english) "Main blocker this month" else "החסם העיקרי החודש",
                choices = listOf(
                    SurveyChoice("focus", if (english) "Focus / consistency" else "פוקוס / עקביות"),
                    SurveyChoice("skills", if (english) "Skills gap" else "פער מיומנויות"),
                    SurveyChoice("cash", if (english) "Cash pressure" else "לחץ מזומנים"),
                    SurveyChoice("network", if (english) "Network / opportunities" else "רשת קשרים / הזדמנויות"),
                )
            ),
        )
    }

    private suspend fun trimOldOperationalData() {
        val now = System.currentTimeMillis()
        val queueCutoff = now - queueRetentionMs
        val memoryCutoff = now - memoryRetentionMs
        dao.trimCompletedQueue(queueCutoff)
        dao.trimMemory(memoryCutoff)
    }

    companion object {
        @Volatile
        private var INSTANCE: AtlasRepository? = null

        fun get(context: Context): AtlasRepository {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: AtlasRepository(
                    context = context.applicationContext,
                    sessionPrefs = SessionPreferences(context.applicationContext),
                    apiClient = ApiClient("https://api.atlasmasa.com"),
                ).also {
                    INSTANCE = it
                }
            }
        }
    }
}

private fun NoteEntity.toDomain(): UserNote = UserNote(
    id = id,
    title = title,
    content = content,
    createdAtEpochMs = createdAtEpochMs,
)

private fun PromptQueueEntity.toDomain(): PromptQueueItem = PromptQueueItem(
    id = id,
    prompt = prompt,
    status = status,
    createdAtEpochMs = createdAtEpochMs,
    startedAtEpochMs = startedAtEpochMs,
    completedAtEpochMs = completedAtEpochMs,
    progress = progress,
    checkpointNote = checkpointNote,
    outputSummary = outputSummary,
    nextAction = nextAction,
    confidence = confidence,
    errorMessage = errorMessage,
)

private fun MemoryEntity.toDomain(): MemoryRecord = MemoryRecord(
    id = id,
    type = type,
    source = source,
    weight = weight,
    recency = recency,
    tags = tagsCsv.split(',').filter { it.isNotBlank() },
    value = value,
)

private fun WorkspaceSessionEntity.toDomain(): WorkspaceSession = WorkspaceSession(
    id = id,
    lane = lane,
    title = title,
    summary = summary,
    updatedAtEpochMs = updatedAtEpochMs,
)
