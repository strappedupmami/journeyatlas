package com.atlasmasa.android.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.atlasmasa.android.domain.PromptOutputType
import com.atlasmasa.android.domain.PromptQueueStatus
import com.atlasmasa.android.domain.QuizDifficulty
import com.atlasmasa.android.domain.WorkspaceLane

@Entity(
    tableName = "notes",
    indices = [Index(value = ["createdAtEpochMs"])],
)
data class NoteEntity(
    @PrimaryKey val id: String,
    val title: String,
    val content: String,
    val createdAtEpochMs: Long,
)

@Entity(
    tableName = "prompt_queue",
    indices = [
        Index(value = ["status", "createdAtEpochMs"]),
        Index(value = ["completedAtEpochMs"]),
    ],
)
data class PromptQueueEntity(
    @PrimaryKey val id: String,
    val prompt: String,
    val outputType: PromptOutputType,
    val quizDifficulty: QuizDifficulty?,
    val status: PromptQueueStatus,
    val createdAtEpochMs: Long,
    val startedAtEpochMs: Long?,
    val completedAtEpochMs: Long?,
    val progress: Double,
    val checkpointNote: String?,
    val outputSummary: String?,
    val nextAction: String?,
    val outputContent: String?,
    val outputModel: String?,
    val podcastAudioPath: String?,
    val podcastMimeType: String?,
    val podcastVoiceName: String?,
    val podcastDurationSeconds: Double?,
    val podcastBytes: Int?,
    val confidence: Double?,
    val errorMessage: String?,
)

@Entity(
    tableName = "memory_records",
    indices = [Index(value = ["recency", "weight"])],
)
data class MemoryEntity(
    @PrimaryKey val id: String,
    val type: String,
    val source: String,
    val weight: Double,
    val recency: Long,
    val tagsCsv: String,
    val value: String,
)

@Entity(
    tableName = "workspace_sessions",
    indices = [Index(value = ["updatedAtEpochMs"])],
)
data class WorkspaceSessionEntity(
    @PrimaryKey val id: String,
    val lane: WorkspaceLane,
    val title: String,
    val summary: String,
    val updatedAtEpochMs: Long,
)
