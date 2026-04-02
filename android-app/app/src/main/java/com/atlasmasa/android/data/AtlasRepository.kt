package com.atlasmasa.android.data

import android.content.Context
import android.util.Base64
import com.atlasmasa.android.BuildConfig
import com.atlasmasa.android.domain.AccountTier
import com.atlasmasa.android.domain.AdaptiveBusinessQuestion
import com.atlasmasa.android.domain.AdaptiveBusinessQuestionResponse
import com.atlasmasa.android.domain.AtlasSessionState
import com.atlasmasa.android.domain.AuthProvider
import com.atlasmasa.android.domain.FeedItem
import com.atlasmasa.android.domain.LocalReasoningEngine
import com.atlasmasa.android.domain.MemoryRecord
import com.atlasmasa.android.domain.PromptOutputType
import com.atlasmasa.android.domain.PromptQueueItem
import com.atlasmasa.android.domain.PromptQueueStatus
import com.atlasmasa.android.domain.QuizDifficulty
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
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import okhttp3.ConnectionPool
import okhttp3.Dispatcher
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import java.util.UUID
import java.util.concurrent.TimeUnit

class AtlasRepository private constructor(
    private val appContext: Context,
    private val sessionPrefs: SessionPreferences,
) {
    private val dao = AtlasDatabase.get(appContext).dao()
    private val crypto = DeviceCrypto("persistence_fields")
    private val localReasoningEngine = LocalReasoningEngine()
    private val onDeviceLlmClient = OnDeviceLlmClient(
        endpoint = BuildConfig.LOCAL_LLM_ENDPOINT,
        model = BuildConfig.LOCAL_LLM_MODEL,
        enabled = BuildConfig.LOCAL_LLM_ENABLED,
    )
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val frontierHttp = OkHttpClient.Builder()
        .connectionPool(ConnectionPool(3, 5, TimeUnit.MINUTES))
        .dispatcher(Dispatcher().apply {
            maxRequests = 12
            maxRequestsPerHost = 6
        })
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(55, TimeUnit.SECONDS)
        .writeTimeout(25, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()
    private val availableCores = Runtime.getRuntime().availableProcessors().coerceAtLeast(1)
    private val highPerfDevice = availableCores >= 8

    private val geminiReasoningModel = "gemini-3-flash-preview"
    private val geminiPodcastTtsModel = "gemini-2.5-pro-preview-tts"
    private val defaultPodcastVoice = "Kore"

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
    private val adaptiveQuestionHistoryCap = 24
    private val adaptiveQuestionPendingCap = 3
    private val adaptiveQuestionGenerationCadenceMs = 3L * 60L * 1000L
    private val businessAutopilotCadenceMs = 4L * 60L * 1000L
    @Volatile
    private var cachedApiBaseUrl: String? = null
    @Volatile
    private var cachedApiClient: ApiClient? = null

    private fun apiClientForBase(rawBaseUrl: String): ApiClient {
        val sanitized = ApiClient.sanitizeBaseUrl(rawBaseUrl)
        val existing = cachedApiClient
        if (existing != null && cachedApiBaseUrl == sanitized) {
            return existing
        }
        synchronized(this) {
            val recheck = cachedApiClient
            if (recheck != null && cachedApiBaseUrl == sanitized) {
                return recheck
            }
            val created = ApiClient(sanitized)
            cachedApiBaseUrl = sanitized
            cachedApiClient = created
            return created
        }
    }

    private fun backendHostFrom(baseUrl: String): String {
        return ApiClient.sanitizeBaseUrl(baseUrl)
            .toHttpUrlOrNull()
            ?.host
            ?: "api.atlasmasa.com"
    }

    private fun sanitizeRemoteDesktopBaseUrl(rawBaseUrl: String): String? {
        val trimmed = rawBaseUrl.trim()
        val parsed = trimmed.toHttpUrlOrNull() ?: return null
        val host = parsed.host.lowercase(Locale.getDefault())
        return when (parsed.scheme.lowercase(Locale.getDefault())) {
            "https" -> parsed.toString().removeSuffix("/")
            "http" -> if (isPrivateNetworkHost(host)) parsed.toString().removeSuffix("/") else null
            else -> null
        }
    }

    private fun isPrivateNetworkHost(host: String): Boolean {
        return host == "localhost" ||
            host == "127.0.0.1" ||
            host.startsWith("10.") ||
            host.startsWith("192.168.") ||
            (host.startsWith("172.") && runCatching { host.split(".").getOrNull(1)?.toInt() }.getOrNull() in 16..31)
    }

    fun observeSessionState(): Flow<AtlasSessionState> = sessionPrefs.observeState()

    fun observeNotes(): Flow<List<UserNote>> = dao.observeNotes().map { list -> list.map { decryptNoteEntity(it) } }

    fun observePromptQueue(): Flow<List<PromptQueueItem>> = dao.observeQueue().map { list -> list.map { decryptQueueEntity(it) } }

    fun observeMemoryRecords(): Flow<List<MemoryRecord>> = dao.observeMemory().map { list -> list.map { decryptMemoryEntity(it) } }

    fun observeWorkspaceSessions(): Flow<List<WorkspaceSession>> = dao.observeWorkspaceSessions().map { list -> list.map { decryptWorkspaceEntity(it) } }

    suspend fun addSystemOutput(line: String) {
        val current = sessionPrefs.observeState().first()
        val next = current.copy(systemOutput = (current.systemOutput + line).takeLast(80))
        sessionPrefs.saveState(next)
    }

    fun localLlmStatusLine(): String = onDeviceLlmClient.statusLine()

    suspend fun refreshHealth() {
        val state = sessionPrefs.observeState().first()
        val apiClient = apiClientForBase(state.apiBaseUrl)
        val result = apiClient.healthCapabilities()
        val line = result.fold(
            onSuccess = { caps ->
                "API health ok (${apiClient.resolvedHost}): google=${caps.googleOAuth} apple=${caps.appleOAuth} passkey=${caps.passkey} billing=${caps.billing}"
            },
            onFailure = {
                "API health unavailable on ${backendHostFrom(state.apiBaseUrl)}. Local-first mode remains active."
            }
        )
        sessionPrefs.saveState(state.copy(systemOutput = (state.systemOutput + line).takeLast(80)))
    }

    suspend fun signIn(provider: AuthProvider, label: String) {
        val state = sessionPrefs.observeState().first()
        val apiClient = apiClientForBase(state.apiBaseUrl)
        val remoteSession = apiClient.authMe().getOrNull()
        val remoteProvider = remoteSession?.provider
            ?.trim()
            ?.lowercase(Locale.getDefault())
        val resolvedProvider = when (remoteProvider) {
            "apple" -> AuthProvider.APPLE
            "google" -> AuthProvider.GOOGLE
            "passkey" -> AuthProvider.PASSKEY
            else -> provider
        }
        val resolvedLabel = remoteSession?.name
            ?.takeIf { it.isNotBlank() }
            ?: remoteSession?.email?.takeIf { it.isNotBlank() }
            ?: label
        val prepaidCreditsActive = remoteSession?.prepaidCreditsActive == true
        val resolvedTier = if (prepaidCreditsActive) AccountTier.PRO_CLOUD else AccountTier.LOCAL_CORE
        val statusLine = if (remoteSession != null) {
            if (prepaidCreditsActive) {
                "Signed in with ${resolvedProvider.name.lowercase()} via shared backend ${apiClient.resolvedHost}. Prepaid credits active."
            } else {
                "Signed in with ${resolvedProvider.name.lowercase()} via shared backend ${apiClient.resolvedHost}. Prepaid credits required for AI command center."
            }
        } else {
            "Signed in with ${provider.name.lowercase()} (local core tier active). Backend session pending."
        }
        sessionPrefs.saveState(
            state.copy(
                isSignedIn = true,
                accountProvider = resolvedProvider,
                accountLabel = resolvedLabel,
                accountTier = resolvedTier,
                prepaidCreditsActive = prepaidCreditsActive,
                apiBaseUrl = apiClient.resolvedBaseUrl,
                systemOutput = (state.systemOutput + statusLine).takeLast(80),
            )
        )
    }

    suspend fun signOut() {
        val state = sessionPrefs.observeState().first()
        val apiClient = apiClientForBase(state.apiBaseUrl)
        apiClient.logout()
        sessionPrefs.saveState(
            state.copy(
                isSignedIn = false,
                accountProvider = AuthProvider.GUEST,
                accountLabel = "Guest Operator",
                accountTier = AccountTier.LOCAL_CORE,
                prepaidCreditsActive = false,
                systemOutput = (state.systemOutput + "Signed out. Session retained locally. Shared backend session cleared if available.").takeLast(80),
            )
        )
    }

    suspend fun setLanguage(languageCode: String) {
        val state = sessionPrefs.observeState().first()
        sessionPrefs.saveState(state.copy(languageCode = languageCode))
    }

    suspend fun updateBackendRuntime(apiBaseUrl: String) {
        val state = sessionPrefs.observeState().first()
        val client = apiClientForBase(apiBaseUrl)
        val health = client.healthCapabilities().isSuccess
        val healthStatus = if (health) "reachable" else "unreachable"
        val next = state.copy(
            apiBaseUrl = client.resolvedBaseUrl,
            systemOutput = (
                state.systemOutput +
                    "Shared backend set to ${client.resolvedBaseUrl} ($healthStatus)."
                ).takeLast(80),
        )
        sessionPrefs.saveState(next)
    }

    suspend fun updateInferenceRuntime(
        openAiEndpoint: String,
        openAiApiKey: String,
        geminiApiKey: String,
        podcastVoiceName: String,
    ) {
        val state = sessionPrefs.observeState().first()
        val cleanedEndpoint = openAiEndpoint.trim()
        val cleanedVoice = podcastVoiceName.trim().ifEmpty { defaultPodcastVoice }
        val next = state.copy(
            openAiCompatibleEndpoint = if (cleanedEndpoint.isEmpty()) state.openAiCompatibleEndpoint else cleanedEndpoint,
            openAiCompatibleApiKey = openAiApiKey.trim(),
            geminiApiKey = geminiApiKey.trim(),
            podcastVoiceName = cleanedVoice,
            systemOutput = (
                state.systemOutput +
                    "Inference runtime updated: Gemini 3 Flash + Gemini 2.5 Pro TTS pipeline configured."
                ).takeLast(80),
        )
        sessionPrefs.saveState(next)
    }

    suspend fun updateRemoteDesktopConfig(baseUrl: String, token: String) {
        val state = sessionPrefs.observeState().first()
        val sanitized = sanitizeRemoteDesktopBaseUrl(baseUrl) ?: state.remoteDesktopBaseUrl
        sessionPrefs.saveState(
            state.copy(
                remoteDesktopBaseUrl = sanitized,
                remoteDesktopToken = token.trim(),
                remoteDesktopStatus = "Desktop remote config updated."
            )
        )
    }

    suspend fun refreshRemoteDesktopStatus() {
        val state = sessionPrefs.observeState().first()
        val baseUrl = sanitizeRemoteDesktopBaseUrl(state.remoteDesktopBaseUrl)
        if (baseUrl == null) {
            sessionPrefs.saveState(state.copy(remoteDesktopStatus = "Desktop URL is invalid. Use http://<desktop-ip>:8765 or https://..."))
            return
        }

        val request = Request.Builder()
            .url("$baseUrl/api/remote/status")
            .get()
            .apply {
                val token = state.remoteDesktopToken.trim()
                if (token.isNotEmpty()) {
                    header("Authorization", "Bearer $token")
                }
            }
            .build()

        val next = runCatching {
            frontierHttp.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    return@use state.copy(remoteDesktopStatus = "Desktop rejected the request (${response.code}). Check the pairing token.")
                }

                val payload = json.decodeFromString(RemoteDesktopStatusPayload.serializer(), response.body?.string().orEmpty())
                state.copy(
                    remoteDesktopBaseUrl = baseUrl,
                    remoteDesktopStatus = payload.runtimeDetail,
                    remoteDesktopName = "${payload.appName} on ${payload.deviceName}",
                    remoteDesktopLocalModel = payload.localModel,
                    remoteDesktopQueueDepth = payload.queueDepth,
                    remoteDesktopLastAction = payload.lastAction,
                )
            }
        }.getOrElse { error ->
            state.copy(remoteDesktopStatus = "Could not reach desktop remote control: ${error.localizedMessage}")
        }

        sessionPrefs.saveState(next)
    }

    suspend fun dispatchRemoteDesktopPrompt(prompt: String, target: String, route: String?) {
        val state = sessionPrefs.observeState().first()
        val cleanedPrompt = prompt.trim()
        val baseUrl = sanitizeRemoteDesktopBaseUrl(state.remoteDesktopBaseUrl)
        if (cleanedPrompt.isEmpty() || baseUrl == null) {
            sessionPrefs.saveState(state.copy(remoteDesktopStatus = "Desktop URL or prompt is invalid."))
            return
        }

        val payload = RemoteDesktopDispatchPayload(prompt = cleanedPrompt, target = target, route = route)
        val request = Request.Builder()
            .url("$baseUrl/api/remote/dispatch")
            .post(json.encodeToString(RemoteDesktopDispatchPayload.serializer(), payload).toRequestBody("application/json".toMediaType()))
            .apply {
                val token = state.remoteDesktopToken.trim()
                if (token.isNotEmpty()) {
                    header("Authorization", "Bearer $token")
                }
            }
            .build()

        val next = runCatching {
            frontierHttp.newCall(request).execute().use { response ->
                val decoded = json.decodeFromString(RemoteDesktopDispatchResult.serializer(), response.body?.string().orEmpty())
                state.copy(
                    remoteDesktopBaseUrl = baseUrl,
                    remoteDesktopStatus = decoded.message,
                    remoteDesktopQueueDepth = decoded.queueDepth,
                    remoteDesktopLastAction = decoded.message,
                )
            }
        }.getOrElse { error ->
            state.copy(remoteDesktopStatus = "Could not send prompt to desktop: ${error.localizedMessage}")
        }

        sessionPrefs.saveState(next)
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
                value = encryptField("daily=$daily | mid=$mid | long=$long | blocker=$blockers"),
            )
        )

        dao.upsertWorkspaceSession(
            WorkspaceSessionEntity(
                id = UUID.randomUUID().toString(),
                lane = WorkspaceLane.COMMAND,
                title = encryptField(if (daily.isBlank()) "Daily check-in" else daily.take(60)),
                summary = encryptField("Mood=$mood Energy=$energy Gym=$gymToday Money=$moneyToday"),
                updatedAtEpochMs = System.currentTimeMillis(),
            )
        )
    }

    data class AdaptiveRuntimeTickResult(
        val generatedQuestion: Boolean = false,
        val ranAutopilot: Boolean = false,
        val enqueuedPrompt: Boolean = false,
        val statusLine: String = "",
    )

    suspend fun submitSurveyAnswer(questionId: String, answer: String) {
        val cleanQuestionId = questionId.trim().ifEmpty { return }
        val cleanAnswer = answer.trim().take(180)
        if (cleanAnswer.isEmpty()) return

        val state = sessionPrefs.observeState().first()
        val nextAnswers = state.surveyAnswers.toMutableMap().apply {
            this[cleanQuestionId] = cleanAnswer
        }
        val questionSet = surveyQuestions(state.languageCode)
        val requiredQuestions = questionSet.map { it.id }
        val completed = requiredQuestions.isNotEmpty() &&
            requiredQuestions.all { id -> !nextAnswers[id].isNullOrBlank() }

        var next = state.copy(
            surveyAnswers = nextAnswers,
            systemOutput = (state.systemOutput + "Survey answer recorded: $cleanQuestionId=$cleanAnswer").takeLast(80),
        )
        if (completed && !state.guidedLearningRuntimeActive) {
            next = next.copy(
                adaptiveBusinessRuntimeStatusLine = "Survey complete. Activate guided learning when you are ready to start using the app.",
                systemOutput = (next.systemOutput + "Initialization survey complete. Activate guided learning to start adaptive runtime.").takeLast(80),
            )
        }
        sessionPrefs.saveState(next)

        if (next.memoryOptIn) {
            val questionTitle = questionSet.firstOrNull { it.id == cleanQuestionId }?.title ?: cleanQuestionId
            dao.upsertMemory(
                MemoryEntity(
                    id = UUID.randomUUID().toString(),
                    type = "survey_answer",
                    source = "android_survey",
                    weight = 0.72,
                    recency = System.currentTimeMillis(),
                    tagsCsv = "survey,$cleanQuestionId",
                    value = encryptField("$questionTitle => $cleanAnswer"),
                )
            )
        }
    }

    suspend fun activateGuidedLearningAfterSurvey(): Boolean {
        val state = sessionPrefs.observeState().first()
        val requiredQuestions = surveyQuestions(state.languageCode).map { it.id }
        val completed = requiredQuestions.isNotEmpty() &&
            requiredQuestions.all { id -> !state.surveyAnswers[id].isNullOrBlank() }

        if (!completed) {
            sessionPrefs.saveState(
                state.copy(
                    adaptiveBusinessRuntimeStatusLine = "Finish the initialization survey first.",
                    systemOutput = (
                        state.systemOutput +
                            "Guided learning activation blocked: complete all survey questions first."
                        ).takeLast(80),
                )
            )
            return false
        }

        if (!state.guidedLearningRuntimeActive) {
            sessionPrefs.saveState(
                state.copy(
                    guidedLearningRuntimeActive = true,
                    adaptiveBusinessRuntimeStatusLine = "Guided learning active. Adaptive runtime is running.",
                    systemOutput = (
                        state.systemOutput +
                            "Guided learning activated after survey completion."
                        ).takeLast(80),
                )
            )
        }
        runAdaptiveBusinessRuntimeTick(
            trigger = "activation",
            forceQuestion = true,
            forceAutopilot = true,
        )
        return true
    }

    suspend fun saveAdaptiveBusinessRuntimeSettings(
        questionEngineEnabled: Boolean,
        businessAutopilotEnabled: Boolean,
    ) {
        val state = sessionPrefs.observeState().first()
        val next = state.copy(
            adaptiveBusinessQuestionEngineEnabled = questionEngineEnabled,
            businessAutopilotEnabled = businessAutopilotEnabled,
            adaptiveBusinessRuntimeStatusLine = "Adaptive runtime updated. Questions: ${if (questionEngineEnabled) "on" else "off"}, autopilot: ${if (businessAutopilotEnabled) "on" else "off"}.",
        )
        sessionPrefs.saveState(next)
    }

    suspend fun answerAdaptiveBusinessQuestion(
        questionId: String,
        selectedOptions: List<String>,
        freeformText: String,
    ): Boolean {
        val cleanQuestionId = questionId.trim().ifEmpty { return false }
        val state = sessionPrefs.observeState().first()
        val existingIndex = state.adaptiveBusinessQuestions.indexOfFirst { it.id == cleanQuestionId }
        if (existingIndex < 0) {
            sessionPrefs.saveState(
                state.copy(adaptiveBusinessRuntimeStatusLine = "Question not found. Generate a new one.")
            )
            return false
        }

        val targetQuestion = state.adaptiveBusinessQuestions[existingIndex]
        if (targetQuestion.response != null) {
            sessionPrefs.saveState(
                state.copy(adaptiveBusinessRuntimeStatusLine = "This question was already answered.")
            )
            return false
        }

        val available = targetQuestion.options.toSet()
        val normalizedSelections = selectedOptions
            .map { sanitizeText(it, 80) }
            .filter { it in available }
            .distinct()
        val cleanFreeform = sanitizeText(freeformText, 360)
        if (normalizedSelections.isEmpty() && cleanFreeform.isEmpty()) {
            sessionPrefs.saveState(
                state.copy(adaptiveBusinessRuntimeStatusLine = "Choose at least one option or add a freeform response.")
            )
            return false
        }

        val response = AdaptiveBusinessQuestionResponse(
            selectedOptions = normalizedSelections,
            freeformText = cleanFreeform,
            answeredAtEpochMs = System.currentTimeMillis(),
        )
        val updatedQuestions = state.adaptiveBusinessQuestions.toMutableList().apply {
            this[existingIndex] = this[existingIndex].copy(response = response)
        }
        val answerSummary = buildString {
            append("Q: ${targetQuestion.prompt}\n")
            append("Selected: ${if (normalizedSelections.isEmpty()) "none" else normalizedSelections.joinToString(", ")}\n")
            append("Notes: ${if (cleanFreeform.isEmpty()) "none" else cleanFreeform}")
        }

        if (state.memoryOptIn) {
            dao.upsertMemory(
                MemoryEntity(
                    id = UUID.randomUUID().toString(),
                    type = "adaptive_business_question",
                    source = "android_ollama",
                    weight = 0.82,
                    recency = System.currentTimeMillis(),
                    tagsCsv = "adaptive,business,questionnaire,ollama",
                    value = encryptField(answerSummary),
                )
            )
        }

        sessionPrefs.saveState(
            state.copy(
                adaptiveBusinessQuestions = updatedQuestions,
                adaptiveBusinessRuntimeStatusLine = "Response captured and added to memory.",
                systemOutput = (state.systemOutput + "Adaptive business response captured.").takeLast(80),
            )
        )

        runAdaptiveBusinessRuntimeTick(
            trigger = "answer",
            forceQuestion = true,
            forceAutopilot = false,
        )
        return true
    }

    suspend fun requestNextAdaptiveBusinessQuestionNow() {
        runAdaptiveBusinessRuntimeTick(
            trigger = "manual",
            forceQuestion = true,
            forceAutopilot = false,
        )
    }

    suspend fun runAdaptiveBusinessRuntimeTick(
        trigger: String = "worker",
        forceQuestion: Boolean = false,
        forceAutopilot: Boolean = false,
    ): AdaptiveRuntimeTickResult = withContext(Dispatchers.IO) {
        var state = sessionPrefs.observeState().first()
        if (!state.guidedLearningRuntimeActive) {
            if (forceQuestion || forceAutopilot) {
                val locked = state.copy(
                    adaptiveBusinessRuntimeStatusLine = "Adaptive questions are locked until guided learning is active.",
                )
                if (locked != state) {
                    sessionPrefs.saveState(locked)
                }
                state = locked
            }
            return@withContext AdaptiveRuntimeTickResult(statusLine = state.adaptiveBusinessRuntimeStatusLine)
        }

        val now = System.currentTimeMillis()
        var generatedQuestion = false
        var ranAutopilot = false
        var statusLine = state.adaptiveBusinessRuntimeStatusLine
        var questions = state.adaptiveBusinessQuestions
            .sortedByDescending { it.generatedAtEpochMs }
            .take(adaptiveQuestionHistoryCap)
            .toMutableList()

        val shouldGenerateQuestion = (state.adaptiveBusinessQuestionEngineEnabled || forceQuestion) &&
            (forceQuestion ||
                (questions.count { it.response == null } < adaptiveQuestionPendingCap &&
                    (now - state.lastAdaptiveBusinessQuestionAtEpochMs >= adaptiveQuestionGenerationCadenceMs)))
        var lastQuestionAt = state.lastAdaptiveBusinessQuestionAtEpochMs
        if (shouldGenerateQuestion) {
            val generated = buildAdaptiveBusinessQuestion(state)
            questions.add(0, generated)
            if (questions.size > adaptiveQuestionHistoryCap) {
                questions = questions.take(adaptiveQuestionHistoryCap).toMutableList()
            }
            generatedQuestion = true
            lastQuestionAt = now
            statusLine = "Adaptive question generated ($trigger)."
        }

        val shouldRunAutopilot = (state.businessAutopilotEnabled || forceAutopilot) &&
            (forceAutopilot || now - state.lastBusinessAutopilotAtEpochMs >= businessAutopilotCadenceMs)
        var lastAutopilotAt = state.lastBusinessAutopilotAtEpochMs
        var cursor = state.adaptiveBusinessAutopilotCursor
        if (shouldRunAutopilot) {
            val prompt = businessAutopilotPrompt(cursor)
            val autopilotStatus = runBusinessAutopilotCycle(prompt, state)
            cursor = (cursor + 1) % 3
            lastAutopilotAt = now
            ranAutopilot = true
            statusLine = autopilotStatus
        }

        val next = state.copy(
            adaptiveBusinessQuestions = questions,
            adaptiveBusinessRuntimeStatusLine = statusLine,
            lastAdaptiveBusinessQuestionAtEpochMs = lastQuestionAt,
            lastBusinessAutopilotAtEpochMs = lastAutopilotAt,
            adaptiveBusinessAutopilotCursor = cursor,
            systemOutput = buildList {
                addAll(state.systemOutput)
                if (generatedQuestion) add("Adaptive question generated from memory context.")
                if (ranAutopilot) add("Business autopilot cycle completed in background.")
            }.takeLast(80),
        )
        if (next != state) {
            sessionPrefs.saveState(next)
        }
        AdaptiveRuntimeTickResult(
            generatedQuestion = generatedQuestion,
            ranAutopilot = ranAutopilot,
            enqueuedPrompt = false,
            statusLine = next.adaptiveBusinessRuntimeStatusLine,
        )
    }

    suspend fun shouldKeepAdaptiveRuntimeAlive(): Boolean {
        val state = sessionPrefs.observeState().first()
        return state.guidedLearningRuntimeActive &&
            (state.adaptiveBusinessQuestionEngineEnabled || state.businessAutopilotEnabled)
    }

    suspend fun upsertNote(title: String, content: String) {
        val cleanTitle = title.ifBlank { "Untitled note" }.take(100)
        val cleanContent = content.trim().take(12_000)
        if (cleanContent.isBlank()) return

        val note = NoteEntity(
            id = UUID.randomUUID().toString(),
            title = encryptField(cleanTitle),
            content = encryptField(cleanContent),
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
                value = encryptField("$cleanTitle: ${cleanContent.take(220)}"),
            )
        )
    }

    suspend fun enqueuePrompt(
        prompt: String,
        outputType: PromptOutputType = PromptOutputType.STANDARD,
        quizDifficulty: QuizDifficulty? = null,
    ): Boolean {
        val trimmedPrompt = prompt.trim()
        if (trimmedPrompt.isEmpty()) return false
        val currentState = sessionPrefs.observeState().first()
        if (!currentState.prepaidCreditsActive) {
            val remote = apiClientForBase(currentState.apiBaseUrl).authMe().getOrNull()
            if (remote?.prepaidCreditsActive == true) {
                sessionPrefs.saveState(
                    currentState.copy(
                        prepaidCreditsActive = true,
                        accountTier = AccountTier.PRO_CLOUD,
                        systemOutput = (currentState.systemOutput + "Prepaid credits verified. AI command center unlocked.").takeLast(80),
                    )
                )
            } else {
                addSystemOutput("AI command center is locked. Prepay credits in Billing before queueing prompts.")
                return false
            }
        }

        val currentQueueSize = dao.totalQueueCount()
        if (currentQueueSize >= maxQueueItems) {
            addSystemOutput("Queue limit reached ($maxQueueItems). Clear completed items to continue.")
            return false
        }

        dao.upsertQueueItem(
            PromptQueueEntity(
                id = UUID.randomUUID().toString(),
                prompt = encryptField(trimmedPrompt.take(2_000)),
                outputType = outputType,
                quizDifficulty = quizDifficulty,
                status = PromptQueueStatus.QUEUED,
                createdAtEpochMs = System.currentTimeMillis(),
                startedAtEpochMs = null,
                completedAtEpochMs = null,
                progress = 0.0,
                checkpointNote = encryptField("Queued"),
                outputSummary = null,
                nextAction = null,
                outputContent = null,
                outputModel = null,
                podcastAudioPath = null,
                podcastMimeType = null,
                podcastVoiceName = null,
                podcastDurationSeconds = null,
                podcastBytes = null,
                confidence = null,
                errorMessage = null,
            )
        )
        return true
    }

    suspend fun processNextQueuedPrompt(): Boolean = withContext(Dispatchers.IO) {
        val state = sessionPrefs.observeState().first()
        if (!state.prepaidCreditsActive) {
            val remote = apiClientForBase(state.apiBaseUrl).authMe().getOrNull()
            if (remote?.prepaidCreditsActive == true) {
                sessionPrefs.saveState(
                    state.copy(
                        prepaidCreditsActive = true,
                        accountTier = AccountTier.PRO_CLOUD,
                        systemOutput = (state.systemOutput + "Prepaid credits verified. Resuming queued AI prompts.").takeLast(80),
                    )
                )
            } else {
                return@withContext false
            }
        }
        val queued = dao.nextQueuedItem() ?: return@withContext false
        val decryptedPrompt = decryptField(queued.prompt)
        dao.upsertQueueItem(
            queued.copy(
                status = PromptQueueStatus.RUNNING,
                startedAtEpochMs = System.currentTimeMillis(),
                progress = 0.2,
                checkpointNote = encryptField("Model running"),
                outputSummary = null,
                nextAction = null,
                outputContent = null,
                outputModel = null,
                podcastAudioPath = null,
                podcastMimeType = null,
                podcastVoiceName = null,
                podcastDurationSeconds = null,
                podcastBytes = null,
                errorMessage = null,
            )
        )

        return@withContext runCatching {
            val notes = dao.listRecentNotes(4).map { decryptNoteEntity(it) }
            val priorSummaries = dao.observeQueue().first()
                .mapNotNull { decryptOptionalField(it.outputSummary) }
                .takeLast(8)
            val generation = when (queued.outputType) {
                PromptOutputType.PODCAST -> {
                    generatePodcastOutput(
                        prompt = decryptedPrompt,
                        notes = notes,
                        priorSummaries = priorSummaries,
                        state = state,
                    )
                }
                PromptOutputType.QUIZ -> {
                    generateQuizOutput(
                        prompt = decryptedPrompt,
                        notes = notes,
                        priorSummaries = priorSummaries,
                        state = state,
                    )
                }
                PromptOutputType.STANDARD -> {
                    generateStandardOutput(
                        prompt = decryptedPrompt,
                        notes = notes,
                        priorSummaries = priorSummaries,
                        state = state,
                    )
                }
            }

            when (generation) {
                is QueueGenerationResult.Success -> {
                    val result = generation.payload
                    dao.upsertQueueItem(
                        queued.copy(
                            status = PromptQueueStatus.DONE,
                            progress = 1.0,
                            completedAtEpochMs = System.currentTimeMillis(),
                            checkpointNote = encryptField(result.checkpoint),
                            outputSummary = encryptField(result.summary),
                            nextAction = encryptField(result.nextAction),
                            outputContent = encryptOptionalField(result.content),
                            outputModel = encryptOptionalField(result.model),
                            podcastAudioPath = encryptOptionalField(result.podcastAudioPath),
                            podcastMimeType = encryptOptionalField(result.podcastMimeType),
                            podcastVoiceName = encryptOptionalField(result.podcastVoiceName),
                            podcastDurationSeconds = result.podcastDurationSeconds,
                            podcastBytes = result.podcastBytes,
                            confidence = result.confidence,
                            errorMessage = null,
                        )
                    )
                    dao.upsertMemory(
                        MemoryEntity(
                            id = UUID.randomUUID().toString(),
                            type = "queue_output",
                            source = result.memorySource,
                            weight = result.confidence,
                            recency = System.currentTimeMillis(),
                            tagsCsv = result.memoryTags.joinToString(","),
                            value = encryptField("${result.summary} | ${result.nextAction}"),
                        )
                    )
                }
                is QueueGenerationResult.Failure -> {
                    dao.upsertQueueItem(
                        queued.copy(
                            status = PromptQueueStatus.FAILED,
                            completedAtEpochMs = System.currentTimeMillis(),
                            progress = 1.0,
                            checkpointNote = encryptField(generation.checkpoint),
                            errorMessage = encryptField(generation.message),
                        )
                    )
                }
            }
            true
        }.getOrElse { err ->
            dao.upsertQueueItem(
                queued.copy(
                    status = PromptQueueStatus.FAILED,
                    completedAtEpochMs = System.currentTimeMillis(),
                    progress = 1.0,
                    checkpointNote = encryptField("Failed"),
                    errorMessage = encryptField(err.message ?: "Unknown queue error"),
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
        val memory = dao.listRecentMemory(8).map { decryptMemoryEntity(it) }
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

    private suspend fun buildAdaptiveBusinessQuestion(state: AtlasSessionState): AdaptiveBusinessQuestion {
        val answeredSnapshot = state.adaptiveBusinessQuestions
            .mapNotNull { question ->
                val response = question.response ?: return@mapNotNull null
                val selected = response.selectedOptions.joinToString(", ").ifBlank { "none" }
                val notes = response.freeformText.ifBlank { "none" }
                "- Q: ${question.prompt}\n  A: $selected\n  Notes: $notes"
            }
            .take(4)
            .joinToString("\n")
            .ifBlank { "- none yet" }

        val recentNotes = dao.listRecentNotes(8).map { decryptNoteEntity(it) }
        val recentMemory = dao.listRecentMemory(12).map { decryptMemoryEntity(it) }
        val contextDigest = buildAdaptiveContextDigest(
            state = state,
            notes = recentNotes,
            memory = recentMemory,
        )
        val generated = onDeviceLlmClient.adaptiveBusinessQuestion(
            answeredSnapshot = answeredSnapshot,
            globalUserContext = contextDigest,
        )
        if (generated != null) {
            val questionText = sanitizeText(generated.question, 180)
            val options = generated.options
                .map { sanitizeText(it, 72) }
                .filter { it.isNotEmpty() }
                .distinct()
            if (questionText.isNotEmpty() && options.size >= 3) {
                return AdaptiveBusinessQuestion(
                    prompt = questionText,
                    options = options.take(5),
                    allowsMultipleSelection = true,
                    generatedAtEpochMs = System.currentTimeMillis(),
                    source = "ollama",
                    response = null,
                )
            }
        }

        return AdaptiveBusinessQuestion(
            prompt = "What is the highest-leverage growth bottleneck right now?",
            options = listOf(
                "Top-of-funnel lead flow is too weak",
                "Offer/value proposition is unclear",
                "Conversion calls close too slowly",
                "Retention/expansion is underperforming",
            ),
            allowsMultipleSelection = true,
            generatedAtEpochMs = System.currentTimeMillis(),
            source = "fallback",
            response = null,
        )
    }

    private suspend fun runBusinessAutopilotCycle(
        prompt: String,
        state: AtlasSessionState,
    ): String {
        val notes = dao.listRecentNotes(6).map { decryptNoteEntity(it) }
        val priorSummaries = dao.observeQueue().first()
            .mapNotNull { decryptOptionalField(it.outputSummary) }
            .takeLast(8)
        return when (val generation = generateStandardOutput(prompt, notes, priorSummaries, state)) {
            is QueueGenerationResult.Success -> {
                val payload = generation.payload
                val now = System.currentTimeMillis()
                if (state.memoryOptIn) {
                    dao.upsertMemory(
                        MemoryEntity(
                            id = UUID.randomUUID().toString(),
                            type = "adaptive_business_autopilot",
                            source = payload.memorySource,
                            weight = payload.confidence.coerceIn(0.0, 1.0),
                            recency = now,
                            tagsCsv = "adaptive,business,autopilot",
                            value = encryptField("${payload.summary} | ${payload.nextAction}"),
                        )
                    )
                }
                dao.upsertWorkspaceSession(
                    WorkspaceSessionEntity(
                        id = UUID.randomUUID().toString(),
                        lane = WorkspaceLane.GUIDE,
                        title = encryptField("Autopilot: ${payload.summary.take(52)}"),
                        summary = encryptField(payload.nextAction.take(220)),
                        updatedAtEpochMs = now,
                    )
                )
                "Business autopilot generated a growth action cycle."
            }
            is QueueGenerationResult.Failure -> {
                "Business autopilot failed: ${generation.message.take(120)}"
            }
        }
    }

    private fun businessAutopilotPrompt(cursor: Int): String {
        val base = """
            Use all available user context and produce one concise business execution brief.
            Include:
            1) immediate action
            2) 7-day sequence
            3) KPI checkpoint
            4) risk + mitigation
        """.trimIndent()
        return when (cursor % 3) {
            0 -> "$base\nDeliverable: Weekly growth operating brief with north-star focus and experiment cadence."
            1 -> "$base\nDeliverable: Retention + expansion plan with churn diagnosis and onboarding fixes."
            else -> "$base\nDeliverable: Distribution leverage plan with channel sequencing and conversion architecture."
        }
    }

    private fun buildAdaptiveContextDigest(
        state: AtlasSessionState,
        notes: List<UserNote>,
        memory: List<MemoryRecord>,
    ): String {
        val noteSnapshot = notes
            .take(6)
            .joinToString("\n") { "- ${sanitizeText(it.title, 80)}: ${sanitizeText(it.content, 160)}" }
            .ifBlank { "- none yet" }
        val memorySnapshot = memory
            .take(8)
            .joinToString("\n") { "- [${sanitizeText(it.type, 22)}] ${sanitizeText(it.value, 180)}" }
            .ifBlank { "- none yet" }
        return """
            Account tier: ${state.accountTier}
            Language: ${state.languageCode}
            Daily priority: ${sanitizeText(state.dailyPriority, 180)}
            Mid-term goal: ${sanitizeText(state.midTermGoal, 180)}
            Long-term vision: ${sanitizeText(state.longTermVision, 180)}
            Current blockers: ${sanitizeText(state.blockers, 180)}
            Mood/Energy: ${sanitizeText(state.mood, 80)} / ${state.energy}
            Survey answers: ${state.surveyAnswers.entries.joinToString("; ") { "${it.key}=${sanitizeText(it.value, 48)}" }.ifBlank { "none yet" }}

            Notes
            $noteSnapshot

            Memory
            $memorySnapshot
        """.trimIndent().take(2_400)
    }

    private fun sanitizeText(raw: String, maxLength: Int): String {
        return raw
            .replace(Regex("\\s+"), " ")
            .trim()
            .take(maxLength)
    }

    private sealed class QueueGenerationResult {
        data class Success(val payload: GeneratedQueuePayload) : QueueGenerationResult()
        data class Failure(
            val message: String,
            val checkpoint: String = "Failed",
        ) : QueueGenerationResult()
    }

    private data class GeneratedQueuePayload(
        val summary: String,
        val nextAction: String,
        val confidence: Double,
        val checkpoint: String,
        val memorySource: String,
        val memoryTags: List<String>,
        val content: String? = null,
        val model: String? = null,
        val podcastAudioPath: String? = null,
        val podcastMimeType: String? = null,
        val podcastVoiceName: String? = null,
        val podcastDurationSeconds: Double? = null,
        val podcastBytes: Int? = null,
    )

    @Serializable
    private data class PodcastScriptPlan(
        @SerialName("output_type") val outputType: String = "podcast",
        val summary: String,
        @SerialName("next_action") val nextAction: String,
        val confidence: Double? = null,
        val title: String? = null,
        val script: String,
        @SerialName("voice_name") val voiceName: String? = null,
    )

    private data class RenderedPodcastAudio(
        val data: ByteArray,
        val mimeType: String,
        val rawPcmByteCount: Int,
    )

    private data class StoredPodcastAudio(
        val path: String,
        val mimeType: String,
        val voiceName: String,
        val durationSeconds: Double,
        val bytes: Int,
    )

    private suspend fun generateStandardOutput(
        prompt: String,
        notes: List<UserNote>,
        priorSummaries: List<String>,
        state: AtlasSessionState,
    ): QueueGenerationResult {
        val backendReply = apiClientForBase(state.apiBaseUrl)
            .chatReply(text = prompt, locale = state.languageCode)
            .getOrNull()
            ?.trim()

        if (!backendReply.isNullOrEmpty()) {
            val summary = backendReply
                .lineSequence()
                .map { it.trim() }
                .firstOrNull { it.isNotEmpty() }
                ?.take(420)
                ?: backendReply.take(420)
            return QueueGenerationResult.Success(
                GeneratedQueuePayload(
                    summary = summary,
                    nextAction = deriveBackendNextAction(backendReply),
                    confidence = 0.84,
                    checkpoint = "Completed via shared backend chat",
                    memorySource = "android_shared_backend",
                    memoryTags = listOf("queue", "reasoning", "backend"),
                    content = backendReply.take(4_000),
                    model = "atlas-cloud-backend/v1-chat",
                )
            )
        }

        val llmResult = onDeviceLlmClient.queueReason(
            prompt = prompt,
            notes = notes,
            priorSummaries = priorSummaries,
        )
        val result = llmResult ?: localReasoningEngine.reason(prompt, notes)
        val source = if (llmResult != null) "android_local_llm" else "android_local_model"
        return QueueGenerationResult.Success(
            GeneratedQueuePayload(
                summary = result.summary.take(420),
                nextAction = result.nextAction.take(220),
                confidence = result.confidence.coerceIn(0.0, 1.0),
                checkpoint = if (llmResult != null) {
                    "Completed via local LLM"
                } else {
                    "Completed via deterministic fallback"
                },
                memorySource = source,
                memoryTags = listOf("queue", "reasoning", "standard"),
                model = result.model,
            )
        )
    }

    private suspend fun generateQuizOutput(
        prompt: String,
        notes: List<UserNote>,
        priorSummaries: List<String>,
        state: AtlasSessionState,
    ): QueueGenerationResult {
        val base = when (val generated = generateStandardOutput(prompt, notes, priorSummaries, state)) {
            is QueueGenerationResult.Success -> generated.payload
            is QueueGenerationResult.Failure -> return generated
        }
        val quizContent = buildQuizContent(prompt, notes)
        return QueueGenerationResult.Success(
            base.copy(
                checkpoint = "Quiz generated",
                memorySource = "android_local_quiz",
                memoryTags = listOf("queue", "reasoning", "quiz"),
                content = quizContent,
            )
        )
    }

    private suspend fun generatePodcastOutput(
        prompt: String,
        notes: List<UserNote>,
        priorSummaries: List<String>,
        state: AtlasSessionState,
    ): QueueGenerationResult {
        val geminiKey = state.geminiApiKey.trim()
        if (geminiKey.isEmpty()) {
            return QueueGenerationResult.Failure(
                message = "Podcast requires a Gemini API key for Stage 1 and Stage 2 audio rendering.",
                checkpoint = "Podcast config missing",
            )
        }

        val notesSnapshot = notes
            .take(10)
            .joinToString("\n") { "- ${it.title.take(80)}: ${it.content.take(180)}" }
        val historySnapshot = priorSummaries
            .takeLast(8)
            .joinToString("\n") { "- ${it.take(180)}" }
        val instruction = """
            You are Atlas Podcast Planning Engine.
            Return ONLY valid JSON:
            {"output_type":"podcast","summary":"...","next_action":"...","confidence":0.0,"title":"...","voice_name":"Kore","script":"..."}
            Rules:
            - output_type must be "podcast"
            - summary <= 280 chars
            - next_action <= 180 chars
            - script sections must be titled: Opening, Main Brief, Action Drill, Closing
            - script should sound like a concise NotebookLM-level tactical podcast
            - no markdown fences

            Prompt:
            $prompt

            Notes:
            $notesSnapshot

            Prior outputs:
            $historySnapshot
        """.trimIndent()

        var stageOneModel = geminiReasoningModel
        val stageOnePlan = generatePodcastScriptViaGemini(
            instruction = instruction,
            geminiApiKey = geminiKey,
        ) ?: run {
            val fallback = generatePodcastScriptViaOpenAiCompatible(
                instruction = instruction,
                state = state,
            )
            if (fallback != null) {
                stageOneModel = "gpt-5.2"
            }
            fallback
        } ?: return QueueGenerationResult.Failure(
            message = "Podcast script stage failed (Gemini 3 and GPT fallback unavailable).",
            checkpoint = "Podcast stage 1 failed",
        )

        val selectedVoice = stageOnePlan.voiceName
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: state.podcastVoiceName.trim().takeIf { it.isNotEmpty() }
            ?: defaultPodcastVoice
        val renderedAudio = renderPodcastAudioViaGemini(
            script = stageOnePlan.script,
            voiceName = selectedVoice,
            geminiApiKey = geminiKey,
        ) ?: return QueueGenerationResult.Failure(
            message = "Podcast audio stage failed on $geminiPodcastTtsModel. No text fallback was generated.",
            checkpoint = "Podcast stage 2 failed",
        )

        val storedAudio = persistPodcastAudioArtifact(
            audio = renderedAudio,
            voiceName = selectedVoice,
        ) ?: return QueueGenerationResult.Failure(
            message = "Podcast audio render succeeded but artifact could not be stored.",
            checkpoint = "Podcast storage failed",
        )

        return QueueGenerationResult.Success(
            GeneratedQueuePayload(
                summary = stageOnePlan.summary.take(420),
                nextAction = stageOnePlan.nextAction.take(220),
                confidence = (stageOnePlan.confidence ?: 0.72).coerceIn(0.0, 1.0),
                checkpoint = "Podcast ready",
                memorySource = "android_podcast_pipeline",
                memoryTags = listOf("queue", "podcast", "audio"),
                model = "podcast_pipeline[$stageOneModel->$geminiPodcastTtsModel]",
                podcastAudioPath = storedAudio.path,
                podcastMimeType = storedAudio.mimeType,
                podcastVoiceName = storedAudio.voiceName,
                podcastDurationSeconds = storedAudio.durationSeconds,
                podcastBytes = storedAudio.bytes,
            )
        )
    }

    private fun generatePodcastScriptViaGemini(
        instruction: String,
        geminiApiKey: String,
    ): PodcastScriptPlan? {
        val endpoint = buildGeminiGenerateContentUrl(geminiReasoningModel) ?: return null
        val payload = buildJsonObject {
            put("contents", buildJsonArray {
                add(
                    buildJsonObject {
                        put("role", JsonPrimitive("user"))
                        put("parts", buildJsonArray {
                            add(
                                buildJsonObject {
                                    put("text", JsonPrimitive(instruction))
                                }
                            )
                        })
                    }
                )
            })
            put(
                "generationConfig",
                buildJsonObject {
                    put(
                        "thinkingConfig",
                        buildJsonObject {
                            put("thinkingLevel", JsonPrimitive("medium"))
                        }
                    )
                }
            )
        }
        val (status, body) = executeJsonRequest(
            url = endpoint,
            headers = mapOf(
                "x-goog-api-key" to geminiApiKey,
                "Content-Type" to "application/json",
                "Accept" to "application/json",
                "Cache-Control" to "no-store",
            ),
            payload = payload.toString(),
        )
        if (status !in 200..299 || body.isNullOrBlank()) return null
        val text = extractGeminiText(body) ?: return null
        return decodePodcastPlan(text)
    }

    private fun generatePodcastScriptViaOpenAiCompatible(
        instruction: String,
        state: AtlasSessionState,
    ): PodcastScriptPlan? {
        val endpoint = state.openAiCompatibleEndpoint.trim()
        val parsed = endpoint.toHttpUrlOrNull() ?: return null
        val scheme = parsed.scheme.lowercase(Locale.getDefault())
        val host = parsed.host.lowercase(Locale.getDefault())
        if (scheme != "https" && !(scheme == "http" && (host == "localhost" || host == "127.0.0.1"))) {
            return null
        }
        val payload = buildJsonObject {
            put("model", JsonPrimitive("gpt-5.2"))
            put("messages", buildJsonArray {
                add(
                    buildJsonObject {
                        put("role", JsonPrimitive("system"))
                        put("content", JsonPrimitive("Return only final output. Do not include markdown fences."))
                    }
                )
                add(
                    buildJsonObject {
                        put("role", JsonPrimitive("user"))
                        put("content", JsonPrimitive(instruction))
                    }
                )
            })
            put("temperature", JsonPrimitive(0.2))
            put("max_tokens", JsonPrimitive(1500))
            put("stream", JsonPrimitive(false))
        }
        val headers = mutableMapOf(
            "Content-Type" to "application/json",
            "Accept" to "application/json",
            "Cache-Control" to "no-store",
        )
        val apiKey = state.openAiCompatibleApiKey.trim()
        if (apiKey.isNotEmpty()) {
            headers["Authorization"] = "Bearer $apiKey"
        }
        val (status, body) = executeJsonRequest(
            url = endpoint,
            headers = headers,
            payload = payload.toString(),
        )
        if (status !in 200..299 || body.isNullOrBlank()) return null
        val text = extractOpenAiText(body) ?: return null
        return decodePodcastPlan(text)
    }

    private fun renderPodcastAudioViaGemini(
        script: String,
        voiceName: String,
        geminiApiKey: String,
    ): RenderedPodcastAudio? {
        val endpoint = buildGeminiGenerateContentUrl(geminiPodcastTtsModel) ?: return null
        val payload = buildJsonObject {
            put("contents", buildJsonArray {
                add(
                    buildJsonObject {
                        put("role", JsonPrimitive("user"))
                        put("parts", buildJsonArray {
                            add(buildJsonObject {
                                put("text", JsonPrimitive(script))
                            })
                        })
                    }
                )
            })
            put(
                "generationConfig",
                buildJsonObject {
                    put("responseModalities", buildJsonArray { add(JsonPrimitive("AUDIO")) })
                    put(
                        "speechConfig",
                        buildJsonObject {
                            put(
                                "voiceConfig",
                                buildJsonObject {
                                    put(
                                        "prebuiltVoiceConfig",
                                        buildJsonObject {
                                            put("voiceName", JsonPrimitive(voiceName))
                                        }
                                    )
                                }
                            )
                        }
                    )
                }
            )
        }
        val (status, body) = executeJsonRequest(
            url = endpoint,
            headers = mapOf(
                "x-goog-api-key" to geminiApiKey,
                "Content-Type" to "application/json",
                "Accept" to "application/json",
                "Cache-Control" to "no-store",
            ),
            payload = payload.toString(),
        )
        if (status !in 200..299 || body.isNullOrBlank()) return null
        val parsed = runCatching { json.parseToJsonElement(body) }.getOrNull() as? JsonObject ?: return null
        val candidates = parsed["candidates"] as? JsonArray ?: return null
        val firstCandidate = candidates.firstOrNull() as? JsonObject ?: return null
        val content = firstCandidate["content"] as? JsonObject ?: return null
        val parts = content["parts"] as? JsonArray ?: return null
        for (partElement in parts) {
            val part = partElement as? JsonObject ?: continue
            val inlineData = part["inlineData"] as? JsonObject ?: continue
            val mimeType = (inlineData["mimeType"] as? JsonPrimitive)?.contentOrNull ?: continue
            val encodedAudio = (inlineData["data"] as? JsonPrimitive)?.contentOrNull ?: continue
            val decoded = runCatching { Base64.decode(encodedAudio, Base64.DEFAULT) }.getOrNull() ?: continue
            if (decoded.isEmpty()) continue
            val lowerMime = mimeType.lowercase(Locale.getDefault())
            if (lowerMime.contains("l16") || lowerMime.contains("pcm")) {
                val wavData = wrapPcm16MonoAsWav(decoded, sampleRate = 24_000)
                return RenderedPodcastAudio(
                    data = wavData,
                    mimeType = "audio/wav",
                    rawPcmByteCount = decoded.size,
                )
            }
            return RenderedPodcastAudio(
                data = decoded,
                mimeType = mimeType,
                rawPcmByteCount = 0,
            )
        }
        return null
    }

    private fun persistPodcastAudioArtifact(
        audio: RenderedPodcastAudio,
        voiceName: String,
    ): StoredPodcastAudio? {
        val dir = File(appContext.filesDir, "podcast_artifacts")
        if (!dir.exists() && !dir.mkdirs()) {
            return null
        }
        val extension = mimeToExtension(audio.mimeType)
        val file = File(dir, "podcast-${UUID.randomUUID()}.$extension")
        return runCatching {
            file.writeBytes(audio.data)
            val durationSeconds = if (audio.rawPcmByteCount > 0) {
                (audio.rawPcmByteCount.toDouble() / (24_000.0 * 2.0)).coerceAtLeast(1.0)
            } else {
                (audio.data.size.toDouble() / (24_000.0 * 2.0)).coerceAtLeast(1.0)
            }
            StoredPodcastAudio(
                path = file.absolutePath,
                mimeType = audio.mimeType,
                voiceName = voiceName,
                durationSeconds = durationSeconds,
                bytes = audio.data.size,
            )
        }.getOrNull()
    }

    private fun executeJsonRequest(
        url: String,
        headers: Map<String, String>,
        payload: String,
    ): Pair<Int, String?> {
        val requestBuilder = Request.Builder()
            .url(url)
            .post(payload.toRequestBody("application/json".toMediaType()))
        headers.forEach { (k, v) ->
            requestBuilder.addHeader(k, v)
        }
        val request = requestBuilder.build()
        return runCatching {
            frontierHttp.newCall(request).execute().use { rsp ->
                rsp.code to rsp.body?.string()
            }
        }.getOrElse { -1 to null }
    }

    private fun buildGeminiGenerateContentUrl(model: String): String? {
        val normalized = model.trim().removePrefix("models/").trim()
        if (normalized.isEmpty()) return null
        val encoded = normalized.replace(" ", "")
        return "https://generativelanguage.googleapis.com/v1beta/models/$encoded:generateContent"
    }

    private fun decodePodcastPlan(raw: String): PodcastScriptPlan? {
        for (candidate in extractJsonCandidates(raw)) {
            val parsed = runCatching {
                json.decodeFromString(PodcastScriptPlan.serializer(), candidate)
            }.getOrNull() ?: continue
            val normalizedType = parsed.outputType.trim().lowercase(Locale.getDefault())
            if (normalizedType != "podcast") continue
            if (parsed.summary.trim().isEmpty()) continue
            if (parsed.nextAction.trim().isEmpty()) continue
            if (parsed.script.trim().isEmpty()) continue
            return parsed
        }
        return null
    }

    private fun extractGeminiText(raw: String): String? {
        val root = runCatching { json.parseToJsonElement(raw) }.getOrNull() as? JsonObject ?: return null
        val candidates = root["candidates"] as? JsonArray ?: return null
        val first = candidates.firstOrNull() as? JsonObject ?: return null
        val content = first["content"] as? JsonObject ?: return null
        val parts = content["parts"] as? JsonArray ?: return null
        val text = parts.mapNotNull { part ->
            ((part as? JsonObject)?.get("text") as? JsonPrimitive)?.contentOrNull
        }.joinToString("\n").trim()
        return text.ifEmpty { null }
    }

    private fun extractOpenAiText(raw: String): String? {
        val root = runCatching { json.parseToJsonElement(raw) }.getOrNull() as? JsonObject ?: return null
        val choices = root["choices"] as? JsonArray ?: return null
        val first = choices.firstOrNull() as? JsonObject ?: return null
        val message = first["message"] as? JsonObject
        val fromMessage = (message?.get("content") as? JsonPrimitive)?.contentOrNull?.trim()
        if (!fromMessage.isNullOrEmpty()) return fromMessage
        return (first["text"] as? JsonPrimitive)?.contentOrNull?.trim()?.ifEmpty { null }
    }

    private fun extractJsonCandidates(raw: String): List<String> {
        val trimmed = raw.trim()
        val candidates = mutableListOf<String>()
        if (trimmed.isNotEmpty()) {
            candidates += trimmed
        }
        val firstFence = trimmed.indexOf("```")
        if (firstFence >= 0) {
            val secondFence = trimmed.indexOf("```", startIndex = firstFence + 3)
            if (secondFence > firstFence) {
                var fenced = trimmed.substring(firstFence + 3, secondFence).trim()
                if (fenced.startsWith("json", ignoreCase = true)) {
                    fenced = fenced.removePrefix("json").removePrefix("JSON").trim()
                }
                if (fenced.isNotEmpty()) {
                    candidates += fenced
                }
            }
        }
        extractBalanced(trimmed, '{', '}')?.let { candidates += it }
        extractBalanced(trimmed, '[', ']')?.let { candidates += it }
        return candidates.distinct()
    }

    private fun extractBalanced(text: String, open: Char, close: Char): String? {
        var depth = 0
        var start = -1
        var inString = false
        var escaped = false
        text.forEachIndexed { idx, ch ->
            if (inString) {
                if (escaped) {
                    escaped = false
                    return@forEachIndexed
                }
                if (ch == '\\') {
                    escaped = true
                    return@forEachIndexed
                }
                if (ch == '"') {
                    inString = false
                }
                return@forEachIndexed
            }
            if (ch == '"') {
                inString = true
                return@forEachIndexed
            }
            if (ch == open) {
                if (depth == 0) start = idx
                depth += 1
                return@forEachIndexed
            }
            if (ch == close && depth > 0) {
                depth -= 1
                if (depth == 0 && start >= 0) {
                    return text.substring(start, idx + 1)
                }
            }
        }
        return null
    }

    private fun deriveBackendNextAction(reply: String): String {
        val candidate = reply
            .lineSequence()
            .map { it.trim().trimStart('-', '*', '•', ' ') }
            .firstOrNull { line ->
                line.length >= 12 &&
                    (line.contains("next", ignoreCase = true) ||
                        line.contains("action", ignoreCase = true) ||
                        line.contains("step", ignoreCase = true))
            }
        return (candidate ?: "Execute the first concrete action from the backend response now.")
            .take(220)
    }

    private fun buildQuizContent(prompt: String, notes: List<UserNote>): String {
        val anchor = prompt.trim().ifEmpty { "your current mission" }.take(180)
        val noteHints = notes.take(3).map { it.title.take(48) }
        val noteLine = if (noteHints.isEmpty()) {
            "Use your latest queue context."
        } else {
            "Integrate note anchors: ${noteHints.joinToString(", ")}."
        }
        return """
            Q1: What is the highest-leverage move from "$anchor" right now?
            Choices: A) Wait for clarity | B) Execute one measurable step | C) Switch goals | D) Ignore blockers
            Correct: B
            Why it matters: Immediate execution compounds faster than passive planning.

            Q2: Which metric should you review in 24 hours?
            Choices: A) Vanity likes | B) Revenue/action KPI | C) Random mood | D) None
            Correct: B
            Why it matters: KPI-based reviews prevent drift.

            Q3: What should happen before adding a new task?
            Choices: A) Add three more tasks | B) Re-check mission fit | C) Archive everything | D) Stop all work
            Correct: B
            Why it matters: Mission fit keeps the queue coherent.

            Q4: Which fallback is strongest when blocked?
            Choices: A) Do nothing | B) Decompose into smaller step | C) Delete plan | D) Restart app
            Correct: B
            Why it matters: Smaller executable steps preserve momentum.

            Q5: How should memory/context be used?
            Choices: A) Ignore memory | B) Use memory as execution evidence | C) Replace prompt entirely | D) Never update memory
            Correct: B
            Why it matters: Context-aware decisions increase precision.

            Q6: Which behavior improves consistency most?
            Choices: A) Sporadic bursts | B) Daily checkpoint + action | C) Over-planning only | D) Constant goal changes
            Correct: B
            Why it matters: Repeated cadence drives durable progress.

            Notes:
            $noteLine
        """.trimIndent()
    }

    private fun wrapPcm16MonoAsWav(rawPcm: ByteArray, sampleRate: Int): ByteArray {
        val channels: Short = 1
        val bitsPerSample: Short = 16
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val blockAlign: Short = (channels * bitsPerSample / 8).toShort()
        val dataSize = rawPcm.size
        val chunkSize = 36 + dataSize

        val buffer = ByteBuffer.allocate(44 + dataSize).order(ByteOrder.LITTLE_ENDIAN)
        buffer.put("RIFF".toByteArray(Charsets.US_ASCII))
        buffer.putInt(chunkSize)
        buffer.put("WAVE".toByteArray(Charsets.US_ASCII))
        buffer.put("fmt ".toByteArray(Charsets.US_ASCII))
        buffer.putInt(16)
        buffer.putShort(1) // PCM format
        buffer.putShort(channels)
        buffer.putInt(sampleRate)
        buffer.putInt(byteRate)
        buffer.putShort(blockAlign)
        buffer.putShort(bitsPerSample)
        buffer.put("data".toByteArray(Charsets.US_ASCII))
        buffer.putInt(dataSize)
        buffer.put(rawPcm)
        return buffer.array()
    }

    private fun mimeToExtension(mimeType: String): String {
        val lower = mimeType.lowercase(Locale.getDefault())
        return when {
            lower.contains("wav") -> "wav"
            lower.contains("mpeg") || lower.contains("mp3") -> "mp3"
            lower.contains("ogg") -> "ogg"
            lower.contains("aac") -> "aac"
            else -> "bin"
        }
    }

    private suspend fun trimOldOperationalData() {
        val now = System.currentTimeMillis()
        val queueCutoff = now - queueRetentionMs
        val memoryCutoff = now - memoryRetentionMs
        dao.trimCompletedQueue(queueCutoff)
        dao.trimMemory(memoryCutoff)
    }

    private fun encryptField(value: String): String {
        if (value.isEmpty()) return value
        return crypto.encrypt(value)
    }

    private fun encryptOptionalField(value: String?): String? {
        if (value.isNullOrEmpty()) return value
        return crypto.encrypt(value)
    }

    private fun decryptField(value: String): String {
        if (value.isEmpty()) return value
        return crypto.decrypt(value) ?: ""
    }

    private fun decryptOptionalField(value: String?): String? {
        if (value.isNullOrEmpty()) return value
        return crypto.decrypt(value)
    }

    private fun decryptNoteEntity(entity: NoteEntity): UserNote = UserNote(
        id = entity.id,
        title = decryptField(entity.title),
        content = decryptField(entity.content),
        createdAtEpochMs = entity.createdAtEpochMs,
    )

    private fun decryptQueueEntity(entity: PromptQueueEntity): PromptQueueItem = PromptQueueItem(
        id = entity.id,
        prompt = decryptField(entity.prompt),
        outputType = entity.outputType,
        quizDifficulty = entity.quizDifficulty,
        status = entity.status,
        createdAtEpochMs = entity.createdAtEpochMs,
        startedAtEpochMs = entity.startedAtEpochMs,
        completedAtEpochMs = entity.completedAtEpochMs,
        progress = entity.progress,
        checkpointNote = decryptOptionalField(entity.checkpointNote),
        outputSummary = decryptOptionalField(entity.outputSummary),
        nextAction = decryptOptionalField(entity.nextAction),
        outputContent = decryptOptionalField(entity.outputContent),
        outputModel = decryptOptionalField(entity.outputModel),
        podcastAudioPath = decryptOptionalField(entity.podcastAudioPath),
        podcastMimeType = decryptOptionalField(entity.podcastMimeType),
        podcastVoiceName = decryptOptionalField(entity.podcastVoiceName),
        podcastDurationSeconds = entity.podcastDurationSeconds,
        podcastBytes = entity.podcastBytes,
        confidence = entity.confidence,
        errorMessage = decryptOptionalField(entity.errorMessage),
    )

    private fun decryptMemoryEntity(entity: MemoryEntity): MemoryRecord = MemoryRecord(
        id = entity.id,
        type = entity.type,
        source = entity.source,
        weight = entity.weight,
        recency = entity.recency,
        tags = entity.tagsCsv.split(',').filter { it.isNotBlank() },
        value = decryptField(entity.value),
    )

    private fun decryptWorkspaceEntity(entity: WorkspaceSessionEntity): WorkspaceSession = WorkspaceSession(
        id = entity.id,
        lane = entity.lane,
        title = decryptField(entity.title),
        summary = decryptField(entity.summary),
        updatedAtEpochMs = entity.updatedAtEpochMs,
    )

    companion object {
        @Volatile
        private var INSTANCE: AtlasRepository? = null

        fun get(context: Context): AtlasRepository {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: AtlasRepository(
                    appContext = context.applicationContext,
                    sessionPrefs = SessionPreferences(context.applicationContext),
                ).also {
                    INSTANCE = it
                }
            }
        }
    }
}
