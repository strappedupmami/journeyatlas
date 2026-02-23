package com.atlasmasa.android.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface AtlasDao {
    @Query("SELECT * FROM notes ORDER BY createdAtEpochMs DESC")
    fun observeNotes(): Flow<List<NoteEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertNote(note: NoteEntity)

    @Query("SELECT * FROM notes ORDER BY createdAtEpochMs DESC LIMIT :limit")
    suspend fun listRecentNotes(limit: Int): List<NoteEntity>

    @Query("SELECT * FROM prompt_queue ORDER BY createdAtEpochMs ASC")
    fun observeQueue(): Flow<List<PromptQueueEntity>>

    @Query("SELECT * FROM prompt_queue WHERE status = 'QUEUED' ORDER BY createdAtEpochMs ASC LIMIT 1")
    suspend fun nextQueuedItem(): PromptQueueEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertQueueItem(item: PromptQueueEntity)

    @Update
    suspend fun updateQueueItem(item: PromptQueueEntity)

    @Query("SELECT COUNT(*) FROM prompt_queue WHERE status = 'QUEUED'")
    suspend fun queuedCount(): Int

    @Query("SELECT COUNT(*) FROM prompt_queue")
    suspend fun totalQueueCount(): Int

    @Query("DELETE FROM prompt_queue WHERE status IN ('DONE', 'FAILED') AND completedAtEpochMs IS NOT NULL AND completedAtEpochMs < :beforeEpochMs")
    suspend fun trimCompletedQueue(beforeEpochMs: Long): Int

    @Query("SELECT * FROM memory_records ORDER BY recency DESC, weight DESC")
    fun observeMemory(): Flow<List<MemoryEntity>>

    @Query("SELECT * FROM memory_records ORDER BY recency DESC, weight DESC LIMIT :limit")
    suspend fun listRecentMemory(limit: Int): List<MemoryEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertMemory(record: MemoryEntity)

    @Query("DELETE FROM memory_records WHERE recency < :beforeEpochMs")
    suspend fun trimMemory(beforeEpochMs: Long): Int

    @Query("SELECT * FROM workspace_sessions ORDER BY updatedAtEpochMs DESC")
    fun observeWorkspaceSessions(): Flow<List<WorkspaceSessionEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertWorkspaceSession(session: WorkspaceSessionEntity)
}
