package com.atlasmasa.android.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import java.util.concurrent.Executors

@Database(
    entities = [NoteEntity::class, PromptQueueEntity::class, MemoryEntity::class, WorkspaceSessionEntity::class],
    version = 2,
    exportSchema = false,
)
@TypeConverters(AtlasTypeConverters::class)
abstract class AtlasDatabase : RoomDatabase() {
    abstract fun dao(): AtlasDao

    companion object {
        @Volatile
        private var INSTANCE: AtlasDatabase? = null

        fun get(context: Context): AtlasDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    AtlasDatabase::class.java,
                    "atlas_android.db"
                )
                    .setQueryExecutor(Executors.newFixedThreadPool(2))
                    // TRUNCATE limits residual WAL snapshots on disk for sensitive local AI state.
                    .setJournalMode(RoomDatabase.JournalMode.TRUNCATE)
                    .fallbackToDestructiveMigration()
                    .build().also {
                    INSTANCE = it
                }
            }
        }
    }
}
