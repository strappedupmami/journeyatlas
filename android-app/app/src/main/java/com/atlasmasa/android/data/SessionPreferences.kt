package com.atlasmasa.android.data

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.atlasmasa.android.domain.AtlasSessionState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json

private val Context.dataStore by preferencesDataStore(name = "atlas_session")

class SessionPreferences(private val context: Context) {
    private val stateKey: Preferences.Key<String> = stringPreferencesKey("session_state_json")
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun observeState(): Flow<AtlasSessionState> {
        return context.dataStore.data.map { prefs ->
            prefs[stateKey]?.let {
                runCatching { json.decodeFromString(AtlasSessionState.serializer(), it) }.getOrNull()
            } ?: AtlasSessionState()
        }
    }

    suspend fun saveState(state: AtlasSessionState) {
        context.dataStore.edit { prefs ->
            prefs[stateKey] = json.encodeToString(AtlasSessionState.serializer(), state)
        }
    }
}
