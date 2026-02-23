package com.atlasmasa.android.data

import androidx.room.TypeConverter
import com.atlasmasa.android.domain.PromptQueueStatus
import com.atlasmasa.android.domain.WorkspaceLane

class AtlasTypeConverters {
    @TypeConverter
    fun toPromptStatus(value: String): PromptQueueStatus = PromptQueueStatus.valueOf(value)

    @TypeConverter
    fun fromPromptStatus(value: PromptQueueStatus): String = value.name

    @TypeConverter
    fun toWorkspaceLane(value: String): WorkspaceLane = WorkspaceLane.valueOf(value)

    @TypeConverter
    fun fromWorkspaceLane(value: WorkspaceLane): String = value.name
}
