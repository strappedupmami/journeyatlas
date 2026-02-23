package com.atlasmasa.android.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.atlasmasa.android.data.AtlasRepository
import com.atlasmasa.android.domain.AtlasSessionState
import com.atlasmasa.android.domain.AuthProvider
import com.atlasmasa.android.domain.FeedItem
import com.atlasmasa.android.domain.MemoryRecord
import com.atlasmasa.android.domain.PromptQueueItem
import com.atlasmasa.android.domain.SurveyQuestion
import com.atlasmasa.android.domain.UserNote
import com.atlasmasa.android.domain.WorkspaceSession
import com.atlasmasa.android.workers.PromptQueueWorker
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

data class DashboardUiState(
    val session: AtlasSessionState = AtlasSessionState(),
    val notes: List<UserNote> = emptyList(),
    val queue: List<PromptQueueItem> = emptyList(),
    val memory: List<MemoryRecord> = emptyList(),
    val workspaces: List<WorkspaceSession> = emptyList(),
    val surveyQuestions: List<SurveyQuestion> = emptyList(),
    val surveyAnswers: Map<String, String> = emptyMap(),
    val feed: List<FeedItem> = emptyList(),
)

class MainViewModel(app: Application) : AndroidViewModel(app) {
    private val repository = AtlasRepository.get(app)
    private val _uiState = MutableStateFlow(DashboardUiState())
    val uiState: StateFlow<DashboardUiState> = _uiState.asStateFlow()
    private var lastSurveyLanguage: String? = null

    init {
        repository.observeSessionState().onEach { state ->
            _uiState.value = _uiState.value.copy(session = state)
            if (lastSurveyLanguage != state.languageCode) {
                lastSurveyLanguage = state.languageCode
                loadSurveyForLanguage(state.languageCode)
            }
        }.launchIn(viewModelScope)

        repository.observeNotes().onEach { notes ->
            _uiState.value = _uiState.value.copy(notes = notes)
        }.launchIn(viewModelScope)

        repository.observePromptQueue().onEach { queue ->
            _uiState.value = _uiState.value.copy(queue = queue)
        }.launchIn(viewModelScope)

        repository.observeMemoryRecords().onEach { records ->
            _uiState.value = _uiState.value.copy(memory = records)
        }.launchIn(viewModelScope)

        repository.observeWorkspaceSessions().onEach { sessions ->
            _uiState.value = _uiState.value.copy(workspaces = sessions)
        }.launchIn(viewModelScope)

        viewModelScope.launch {
            repository.refreshHealth()
            refreshFeed()
            PromptQueueWorker.enqueueImmediate(getApplication())
            PromptQueueWorker.ensurePeriodic(getApplication())
        }
    }

    fun signInApple() = signIn(AuthProvider.APPLE, "Apple account")
    fun signInGoogle() = signIn(AuthProvider.GOOGLE, "Google account")
    fun signInPasskey() = signIn(AuthProvider.PASSKEY, "Passkey operator")

    private fun signIn(provider: AuthProvider, label: String) {
        viewModelScope.launch {
            repository.signIn(provider, label)
            refreshFeed()
        }
    }

    fun signOut() {
        viewModelScope.launch {
            repository.signOut()
            refreshFeed()
        }
    }

    fun setLanguage(language: String) {
        viewModelScope.launch {
            repository.setLanguage(language)
            lastSurveyLanguage = language
            loadSurveyForLanguage(language)
        }
    }

    fun submitCheckIn(
        daily: String,
        mid: String,
        long: String,
        blockers: String,
        mood: String,
        energy: Int,
        gymToday: Boolean,
        moneyToday: Boolean,
    ) {
        viewModelScope.launch {
            repository.submitCheckIn(daily, mid, long, blockers, mood, energy, gymToday, moneyToday)
            refreshFeed()
        }
    }

    fun addNote(title: String, content: String) {
        viewModelScope.launch {
            repository.upsertNote(title, content)
            refreshFeed()
        }
    }

    fun enqueuePrompt(prompt: String) {
        viewModelScope.launch {
            val queued = repository.enqueuePrompt(prompt)
            if (queued) {
                PromptQueueWorker.enqueueImmediate(getApplication())
            }
        }
    }

    fun refreshFeed() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(feed = repository.generateFeed())
        }
    }

    fun answerSurvey(questionId: String, answer: String) {
        val map = _uiState.value.surveyAnswers.toMutableMap()
        map[questionId] = answer
        _uiState.value = _uiState.value.copy(surveyAnswers = map)
        viewModelScope.launch {
            repository.addSystemOutput("Survey answer recorded: $questionId=$answer")
            refreshFeed()
        }
    }

    private fun loadSurveyForLanguage(language: String) {
        viewModelScope.launch {
            val questions = repository.surveyQuestions(language)
            _uiState.value = _uiState.value.copy(surveyQuestions = questions)
        }
    }
}
