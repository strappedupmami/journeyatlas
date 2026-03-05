package com.atlasmasa.android.domain

import kotlinx.serialization.Serializable
import java.util.UUID

enum class AuthProvider { APPLE, GOOGLE, PASSKEY, GUEST }
enum class AccountTier { LOCAL_CORE, PRO_CLOUD }
enum class PromptQueueStatus { QUEUED, RUNNING, DONE, FAILED }
enum class PromptOutputType { STANDARD, PODCAST, QUIZ }
enum class QuizDifficulty { EASY, MEDIUM, HARD }
enum class WorkspaceLane { COMMAND, SURVEY, FEED, NOTES, WORKSPACES, MOBILITY, STATUS, ACCESS, PLANS, GUIDE }

@Serializable
data class HealthCapabilities(
    val googleOAuth: Boolean = false,
    val appleOAuth: Boolean = false,
    val passkey: Boolean = true,
    val billing: Boolean = false,
    val deepPersonalization: Boolean = true,
)

@Serializable
data class SurveyChoice(val value: String, val label: String)

@Serializable
data class SurveyQuestion(
    val id: String,
    val title: String,
    val description: String? = null,
    val required: Boolean = true,
    val choices: List<SurveyChoice> = emptyList(),
)

@Serializable
data class FeedItem(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val summary: String,
    val whyNow: String,
    val priority: String,
)

@Serializable
data class UserNote(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val content: String,
    val createdAtEpochMs: Long = System.currentTimeMillis(),
)

@Serializable
data class PromptQueueItem(
    val id: String = UUID.randomUUID().toString(),
    val prompt: String,
    val outputType: PromptOutputType = PromptOutputType.STANDARD,
    val quizDifficulty: QuizDifficulty? = null,
    val status: PromptQueueStatus = PromptQueueStatus.QUEUED,
    val createdAtEpochMs: Long = System.currentTimeMillis(),
    val startedAtEpochMs: Long? = null,
    val completedAtEpochMs: Long? = null,
    val progress: Double = 0.0,
    val checkpointNote: String? = null,
    val outputSummary: String? = null,
    val nextAction: String? = null,
    val outputContent: String? = null,
    val outputModel: String? = null,
    val podcastAudioPath: String? = null,
    val podcastMimeType: String? = null,
    val podcastVoiceName: String? = null,
    val podcastDurationSeconds: Double? = null,
    val podcastBytes: Int? = null,
    val confidence: Double? = null,
    val errorMessage: String? = null,
)

@Serializable
data class WorkspaceSession(
    val id: String = UUID.randomUUID().toString(),
    val lane: WorkspaceLane,
    val title: String,
    val summary: String,
    val updatedAtEpochMs: Long = System.currentTimeMillis(),
)

@Serializable
data class MemoryRecord(
    val id: String = UUID.randomUUID().toString(),
    val type: String,
    val source: String,
    val weight: Double,
    val recency: Long,
    val tags: List<String>,
    val value: String,
)

@Serializable
data class AdaptiveBusinessQuestionResponse(
    val selectedOptions: List<String> = emptyList(),
    val freeformText: String = "",
    val answeredAtEpochMs: Long = System.currentTimeMillis(),
)

@Serializable
data class AdaptiveBusinessQuestion(
    val id: String = UUID.randomUUID().toString(),
    val prompt: String,
    val options: List<String>,
    val allowsMultipleSelection: Boolean = true,
    val generatedAtEpochMs: Long = System.currentTimeMillis(),
    val source: String = "fallback",
    val response: AdaptiveBusinessQuestionResponse? = null,
)

@Serializable
data class AtlasSessionState(
    val isSignedIn: Boolean = false,
    val accountProvider: AuthProvider = AuthProvider.GUEST,
    val accountLabel: String = "Guest Operator",
    val accountTier: AccountTier = AccountTier.LOCAL_CORE,
    val prepaidCreditsActive: Boolean = false,
    val memoryOptIn: Boolean = true,
    val apiBaseUrl: String = "https://api.atlasmasa.com",
    val languageCode: String = "en",
    val dailyPriority: String = "",
    val midTermGoal: String = "",
    val longTermVision: String = "",
    val mood: String = "Focused",
    val energy: Int = 3,
    val blockers: String = "",
    val gymToday: Boolean = false,
    val moneyToday: Boolean = false,
    val surveyAnswers: Map<String, String> = emptyMap(),
    val guidedLearningRuntimeActive: Boolean = false,
    val adaptiveBusinessQuestionEngineEnabled: Boolean = true,
    val businessAutopilotEnabled: Boolean = true,
    val adaptiveBusinessQuestions: List<AdaptiveBusinessQuestion> = emptyList(),
    val adaptiveBusinessRuntimeStatusLine: String = "Adaptive business runtime idle.",
    val lastAdaptiveBusinessQuestionAtEpochMs: Long = 0L,
    val lastBusinessAutopilotAtEpochMs: Long = 0L,
    val adaptiveBusinessAutopilotCursor: Int = 0,
    val openAiCompatibleEndpoint: String = "http://127.0.0.1:8080/v1/chat/completions",
    val openAiCompatibleApiKey: String = "",
    val geminiApiKey: String = "",
    val podcastVoiceName: String = "Kore",
    val systemOutput: List<String> = listOf("Booting Atlas Android local core..."),
)
