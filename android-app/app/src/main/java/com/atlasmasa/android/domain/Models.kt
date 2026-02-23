package com.atlasmasa.android.domain

import kotlinx.serialization.Serializable
import java.util.UUID

enum class AuthProvider { APPLE, GOOGLE, PASSKEY, GUEST }
enum class AccountTier { LOCAL_CORE, PRO_CLOUD }
enum class PromptQueueStatus { QUEUED, RUNNING, DONE, FAILED }
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
    val status: PromptQueueStatus = PromptQueueStatus.QUEUED,
    val createdAtEpochMs: Long = System.currentTimeMillis(),
    val startedAtEpochMs: Long? = null,
    val completedAtEpochMs: Long? = null,
    val progress: Double = 0.0,
    val checkpointNote: String? = null,
    val outputSummary: String? = null,
    val nextAction: String? = null,
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
data class AtlasSessionState(
    val isSignedIn: Boolean = false,
    val accountProvider: AuthProvider = AuthProvider.GUEST,
    val accountLabel: String = "Guest Operator",
    val accountTier: AccountTier = AccountTier.LOCAL_CORE,
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
    val systemOutput: List<String> = listOf("Booting Atlas Android local core..."),
)
