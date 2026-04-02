package com.atlasmasa.android.ui

import android.media.MediaPlayer
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Note
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Podcasts
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.atlasmasa.android.domain.PromptOutputType
import com.atlasmasa.android.domain.PromptQueueItem
import com.atlasmasa.android.domain.QuizDifficulty
import java.io.File

private enum class RootTab(val title: String) {
    HOME("Command"),
    REMOTE("Remote"),
    SURVEY("Survey"),
    QUEUE("Queue"),
    FEED("Execution"),
    WORKSPACES("Workspaces"),
    NOTES("Memory"),
    ACCESS("Access"),
    GUIDE("AI Guide"),
    MOBILITY("Mobility"),
    PLANS("Plans"),
    OUTPUT("Output"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AtlasApp(viewModel: MainViewModel) {
    val ui by viewModel.uiState.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableStateOf(RootTab.HOME) }

    AtlasTheme {
        Scaffold(
            topBar = {
                CenterAlignedTopAppBar(
                    title = {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("BlackHaven", fontWeight = FontWeight.SemiBold)
                            Text("Travel Design OS", style = MaterialTheme.typography.labelMedium)
                        }
                    },
                )
            },
            bottomBar = {
                NavigationBar {
                    listOf(RootTab.HOME, RootTab.REMOTE, RootTab.SURVEY, RootTab.QUEUE, RootTab.ACCESS, RootTab.GUIDE).forEach { item ->
                        NavigationBarItem(
                            selected = tab == item,
                            onClick = { tab = item },
                            icon = {
                                Icon(
                                    imageVector = when (item) {
                                        RootTab.HOME -> Icons.Default.Home
                                        RootTab.REMOTE -> Icons.Default.Settings
                                        RootTab.SURVEY -> Icons.Default.Menu
                                        RootTab.QUEUE -> Icons.Default.PlayArrow
                                        RootTab.FEED -> Icons.Default.Bolt
                                        RootTab.ACCESS -> Icons.Default.AccountCircle
                                        RootTab.GUIDE -> Icons.Default.Book
                                        else -> Icons.Default.Settings
                                    },
                                    contentDescription = item.title,
                                )
                            },
                            label = { Text(item.title) },
                        )
                    }
                }
            }
        ) { padding ->
            when (tab) {
                RootTab.HOME -> CommandScreen(Modifier.padding(padding), ui, viewModel)
                RootTab.REMOTE -> RemoteDesktopScreen(Modifier.padding(padding), ui, viewModel)
                RootTab.SURVEY -> SurveyScreen(Modifier.padding(padding), ui, viewModel)
                RootTab.QUEUE -> QueueScreen(Modifier.padding(padding), ui, viewModel)
                RootTab.FEED -> FeedScreen(Modifier.padding(padding), ui, viewModel)
                RootTab.WORKSPACES -> WorkspacesScreen(Modifier.padding(padding), ui)
                RootTab.NOTES -> NotesScreen(Modifier.padding(padding), ui, viewModel)
                RootTab.ACCESS -> AccessScreen(Modifier.padding(padding), ui, viewModel)
                RootTab.GUIDE -> GuideScreen(Modifier.padding(padding), ui, viewModel)
                RootTab.MOBILITY -> MobilityScreen(Modifier.padding(padding), ui)
                RootTab.PLANS -> PlansScreen(Modifier.padding(padding), ui)
                RootTab.OUTPUT -> OutputScreen(Modifier.padding(padding), ui)
            }
        }
    }
}

@Composable
private fun RemoteDesktopScreen(modifier: Modifier, ui: DashboardUiState, viewModel: MainViewModel) {
    var baseUrl by remember(ui.session.remoteDesktopBaseUrl) { mutableStateOf(ui.session.remoteDesktopBaseUrl) }
    var token by remember(ui.session.remoteDesktopToken) { mutableStateOf(ui.session.remoteDesktopToken) }
    var prompt by rememberSaveable { mutableStateOf("") }
    var target by rememberSaveable { mutableStateOf("local_qwen") }
    var route by rememberSaveable { mutableStateOf("auto") }

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Desktop remote", style = MaterialTheme.typography.titleLarge)
                    Text("Use BlackHaven on desktop for local Qwen or GPT-5.4 coding from Android.")
                    OutlinedTextField(value = baseUrl, onValueChange = { baseUrl = it }, label = { Text("Desktop URL") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(
                        value = token,
                        onValueChange = { token = it },
                        label = { Text("Pairing token") },
                        visualTransformation = PasswordVisualTransformation(),
                        modifier = Modifier.fillMaxWidth()
                    )
                    Text(ui.session.remoteDesktopName, fontWeight = FontWeight.SemiBold)
                    Text(ui.session.remoteDesktopStatus, style = MaterialTheme.typography.bodySmall)
                    Text("Local model: ${ui.session.remoteDesktopLocalModel} · queue: ${ui.session.remoteDesktopQueueDepth}")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = {
                            viewModel.updateRemoteDesktopConfig(baseUrl, token)
                            viewModel.refreshRemoteDesktopStatus()
                        }) {
                            Text("Save + refresh")
                        }
                        OutlinedButton(onClick = { viewModel.refreshRemoteDesktopStatus() }) {
                            Text("Refresh")
                        }
                    }
                }
            }
        }

        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Dispatch", style = MaterialTheme.typography.titleMedium)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AssistChip(onClick = { target = "local_qwen" }, label = { Text("Qwen") })
                        AssistChip(onClick = { target = "cloud_gpt5_4" }, label = { Text("GPT-5.4") })
                    }
                    if (target == "cloud_gpt5_4") {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            AssistChip(onClick = { route = "auto" }, label = { Text("Auto") })
                            AssistChip(onClick = { route = "frontend_design" }, label = { Text("Frontend") })
                            AssistChip(onClick = { route = "backend_ops" }, label = { Text("Backend") })
                        }
                    }
                    OutlinedTextField(
                        value = prompt,
                        onValueChange = { prompt = it },
                        label = { Text("Prompt for desktop") },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 6,
                    )
                    Button(
                        onClick = {
                            viewModel.updateRemoteDesktopConfig(baseUrl, token)
                            viewModel.dispatchRemoteDesktopPrompt(prompt, target, if (target == "cloud_gpt5_4") route else null)
                            prompt = ""
                        },
                        enabled = prompt.isNotBlank(),
                    ) {
                        Text("Send to desktop")
                    }
                    Text(ui.session.remoteDesktopLastAction, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

@Composable
private fun CommandScreen(modifier: Modifier, ui: DashboardUiState, viewModel: MainViewModel) {
    var daily by remember(ui.session.dailyPriority) { mutableStateOf(ui.session.dailyPriority) }
    var mid by remember(ui.session.midTermGoal) { mutableStateOf(ui.session.midTermGoal) }
    var long by remember(ui.session.longTermVision) { mutableStateOf(ui.session.longTermVision) }
    var blockers by remember(ui.session.blockers) { mutableStateOf(ui.session.blockers) }
    val commandCenterLocked = !ui.session.prepaidCreditsActive

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Daily command", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(value = daily, onValueChange = { daily = it }, label = { Text("Daily priority") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = mid, onValueChange = { mid = it }, label = { Text("Mid-term goal") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = long, onValueChange = { long = it }, label = { Text("Long-term vision") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = blockers, onValueChange = { blockers = it }, label = { Text("Current blockers") }, modifier = Modifier.fillMaxWidth())

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AssistChip(onClick = {}, label = { Text("Mood: ${ui.session.mood}") })
                        AssistChip(onClick = {}, label = { Text("Energy: ${ui.session.energy}") })
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = {
                            viewModel.submitCheckIn(
                                daily = daily,
                                mid = mid,
                                long = long,
                                blockers = blockers,
                                mood = ui.session.mood,
                                energy = ui.session.energy,
                                gymToday = ui.session.gymToday,
                                moneyToday = ui.session.moneyToday,
                            )
                        }) {
                            Icon(Icons.Default.CheckCircle, null)
                            Spacer(Modifier.height(2.dp))
                            Text("Submit check-in")
                        }
                        OutlinedButton(onClick = { viewModel.refreshFeed() }) {
                            Icon(Icons.Default.Refresh, null)
                            Text("Refresh execution")
                        }
                    }
                }
            }
        }

        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("AI command center queue", style = MaterialTheme.typography.titleMedium)
                    if (commandCenterLocked) {
                        Text(
                            "Prepaid credits required. Open Access -> Plans to unlock queueing.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                    var prompt by rememberSaveable { mutableStateOf("") }
                    OutlinedTextField(
                        value = prompt,
                        onValueChange = { prompt = it },
                        label = { Text("Prompt") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Button(
                        onClick = {
                            if (prompt.isNotBlank()) {
                                viewModel.enqueuePrompt(prompt)
                                prompt = ""
                            }
                        },
                        enabled = prompt.isNotBlank() && !commandCenterLocked,
                    ) {
                        Text("Add to queue")
                    }
                }
            }
        }

        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text("What this app does", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Local-first Life OS for execution, wealth route planning, and travel design. " +
                            "Data persists locally and queue resumes after app/device restart."
                    )
                }
            }
        }

        item {
            TransparencySnippet(
                heading = "AI transparency (quick)",
                bullets = listOf(
                    "Built for economic resilience, healthier execution habits, and travel-work operations.",
                    "Uses your survey + notes + check-ins + workspace history to personalize output.",
                    "See AI Guide for full training and privacy details."
                )
            )
        }
    }
}

@Composable
private fun SurveyScreen(modifier: Modifier, ui: DashboardUiState, viewModel: MainViewModel) {
    val totalQuestions = ui.surveyQuestions.size
    val answeredQuestions = ui.surveyQuestions.count { !ui.session.surveyAnswers[it.id].isNullOrBlank() }
    val surveyCompleted = totalQuestions > 0 && answeredQuestions >= totalQuestions

    LazyColumn(
        modifier = modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text("Adaptive deep survey", style = MaterialTheme.typography.titleLarge)
            Text("Answers shape execution stream and workspace intelligence.")
            Text(
                "Progress: $answeredQuestions / $totalQuestions",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        item {
            TransparencySnippet(
                heading = "Why these survey questions exist",
                bullets = listOf(
                    "They build your operating profile: blockers, behavior loops, and growth routes.",
                    "Atlas uses this profile for precise action plans instead of generic advice.",
                    "Retakes add depth without needing to duplicate prior signal."
                )
            )
        }

        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Guided learning activation", style = MaterialTheme.typography.titleMedium)
                    if (!surveyCompleted) {
                        Text("Finish all initialization survey questions first.")
                    } else if (ui.session.guidedLearningRuntimeActive) {
                        Text("Guided learning is active.")
                    } else {
                        Text("Survey complete. Activate guided learning when you are ready to start using the app.")
                    }
                    Button(
                        onClick = { viewModel.activateGuidedLearningAfterSurvey() },
                        enabled = surveyCompleted && !ui.session.guidedLearningRuntimeActive,
                    ) {
                        Text("I'm done with setup - start guided learning")
                    }
                }
            }
        }

        items(ui.surveyQuestions, key = { it.id }) { q ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(q.title, style = MaterialTheme.typography.titleMedium)
                    q.description?.let { Text(it) }
                    q.choices.forEach { choice ->
                        OutlinedButton(
                            onClick = { viewModel.answerSurvey(q.id, choice.value) },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(choice.label)
                        }
                    }
                    ui.surveyAnswers[q.id]?.let {
                        Text("Saved answer: $it", style = MaterialTheme.typography.labelLarge)
                    }
                }
            }
        }
    }
}

@Composable
private fun QueueScreen(modifier: Modifier, ui: DashboardUiState, viewModel: MainViewModel) {
    var promptDraft by rememberSaveable { mutableStateOf("") }
    var selectedOutputType by rememberSaveable { mutableStateOf(PromptOutputType.STANDARD.name) }
    var selectedQuizDifficulty by rememberSaveable { mutableStateOf(QuizDifficulty.MEDIUM.name) }
    var outputMenuOpen by remember { mutableStateOf(false) }
    var quizMenuOpen by remember { mutableStateOf(false) }
    val commandCenterLocked = !ui.session.prepaidCreditsActive

    val queue = remember(ui.queue) {
        ui.queue.sortedBy { it.createdAtEpochMs }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column {
                Text("Atlas Concierge", style = MaterialTheme.typography.titleLarge)
                Text(
                    "Queue-integrated chat with Podcast pipeline",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            TextButton(onClick = { viewModel.refreshFeed() }) { Text("Refresh") }
        }

        if (queue.isEmpty()) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        "Start with a mission prompt. Podcast mode runs Gemini 3 Flash planning plus Gemini 2.5 Pro TTS audio rendering.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    if (commandCenterLocked) {
                        Text(
                            "AI command center is locked until prepaid credits are active.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            }
        }

        LazyColumn(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(queue, key = { it.id }) { item ->
                QueueThreadItem(item = item)
            }
        }

        Surface(
            shape = MaterialTheme.shapes.large,
            tonalElevation = 2.dp,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                modifier = Modifier.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box {
                        AssistChip(
                            onClick = { outputMenuOpen = true },
                            label = { Text("Type: ${selectedOutputType.replace('_', ' ')}") },
                            leadingIcon = {
                                Icon(
                                    imageVector = when (PromptOutputType.valueOf(selectedOutputType)) {
                                        PromptOutputType.PODCAST -> Icons.Default.Podcasts
                                        PromptOutputType.QUIZ -> Icons.Default.CheckCircle
                                        PromptOutputType.STANDARD -> Icons.Default.GraphicEq
                                    },
                                    contentDescription = null,
                                )
                            },
                        )
                        DropdownMenu(
                            expanded = outputMenuOpen,
                            onDismissRequest = { outputMenuOpen = false },
                        ) {
                            PromptOutputType.values().forEach { type ->
                                DropdownMenuItem(
                                    text = { Text(type.name.replace('_', ' ')) },
                                    onClick = {
                                        selectedOutputType = type.name
                                        outputMenuOpen = false
                                    },
                                )
                            }
                        }
                    }

                    if (PromptOutputType.valueOf(selectedOutputType) == PromptOutputType.QUIZ) {
                        Box {
                            AssistChip(
                                onClick = { quizMenuOpen = true },
                                label = { Text("Quiz: ${selectedQuizDifficulty.lowercase()}") },
                            )
                            DropdownMenu(
                                expanded = quizMenuOpen,
                                onDismissRequest = { quizMenuOpen = false },
                            ) {
                                QuizDifficulty.values().forEach { difficulty ->
                                    DropdownMenuItem(
                                        text = { Text(difficulty.name.lowercase()) },
                                        onClick = {
                                            selectedQuizDifficulty = difficulty.name
                                            quizMenuOpen = false
                                        },
                                    )
                                }
                            }
                        }
                    }
                }

                OutlinedTextField(
                    value = promptDraft,
                    onValueChange = { promptDraft = it },
                    label = { Text("Message concierge…") },
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                ) {
                    Button(
                        onClick = {
                            val outputType = PromptOutputType.valueOf(selectedOutputType)
                            val quizDifficulty = if (outputType == PromptOutputType.QUIZ) {
                                QuizDifficulty.valueOf(selectedQuizDifficulty)
                            } else {
                                null
                            }
                            viewModel.enqueuePrompt(
                                prompt = promptDraft,
                                outputType = outputType,
                                quizDifficulty = quizDifficulty,
                            )
                            promptDraft = ""
                        },
                        enabled = promptDraft.isNotBlank() && !commandCenterLocked,
                    ) {
                        Icon(Icons.Default.PlayArrow, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text("Send")
                    }
                }
            }
        }
    }
}

@Composable
private fun QueueThreadItem(item: PromptQueueItem) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("You", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                Text(item.prompt, style = MaterialTheme.typography.bodyMedium)
            }
        }

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    "Atlas · ${item.outputType.name.replace('_', ' ')}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.secondary,
                )
                when {
                    item.status == com.atlasmasa.android.domain.PromptQueueStatus.DONE &&
                        item.outputType == PromptOutputType.PODCAST &&
                        !item.podcastAudioPath.isNullOrBlank() -> {
                        item.outputSummary?.let {
                            Text(it, style = MaterialTheme.typography.bodyMedium)
                        }
                        PodcastAudioPlayer(
                            audioPath = item.podcastAudioPath,
                            mimeType = item.podcastMimeType ?: "audio/wav",
                            voiceName = item.podcastVoiceName ?: "Kore",
                            durationSeconds = item.podcastDurationSeconds ?: 0.0,
                        )
                        item.nextAction?.let {
                            Text(
                                "Next: $it",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    item.status == com.atlasmasa.android.domain.PromptQueueStatus.DONE -> {
                        item.outputSummary?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                        item.outputContent?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                        item.nextAction?.let {
                            Text(
                                "Next: $it",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    item.status == com.atlasmasa.android.domain.PromptQueueStatus.FAILED -> {
                        Text(
                            item.errorMessage ?: "Generation failed.",
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    else -> {
                        Text(
                            queuePendingStatus(item),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PodcastAudioPlayer(
    audioPath: String?,
    mimeType: String,
    voiceName: String,
    durationSeconds: Double,
) {
    val path = audioPath?.trim().orEmpty()
    var player by remember(path) { mutableStateOf<MediaPlayer?>(null) }
    var isPlaying by remember(path) { mutableStateOf(false) }
    var loadError by remember(path) { mutableStateOf<String?>(null) }

    DisposableEffect(path) {
        if (path.isBlank()) {
            loadError = "Podcast audio path is empty."
        } else {
            val file = File(path)
            if (!file.exists()) {
                loadError = "Podcast audio file is missing."
            } else {
                runCatching {
                    MediaPlayer().apply {
                        setDataSource(path)
                        prepare()
                    }
                }.onSuccess {
                    player = it
                    loadError = null
                }.onFailure {
                    loadError = "Could not load podcast audio."
                }
            }
        }

        onDispose {
            runCatching {
                player?.stop()
                player?.release()
            }
            player = null
        }
    }

    if (loadError != null) {
        Text(
            loadError.orEmpty(),
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodySmall,
        )
        return
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        IconButton(
            onClick = {
                val current = player ?: return@IconButton
                if (current.isPlaying) {
                    current.pause()
                    isPlaying = false
                } else {
                    current.start()
                    isPlaying = true
                    current.setOnCompletionListener {
                        isPlaying = false
                    }
                }
            },
        ) {
            Icon(
                imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                contentDescription = if (isPlaying) "Pause podcast" else "Play podcast",
            )
        }
        Column {
            Text(
                "$voiceName · $mimeType",
                style = MaterialTheme.typography.bodySmall,
            )
            Text(
                "Duration ~ ${durationSeconds.toInt()}s",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

private fun queuePendingStatus(item: PromptQueueItem): String {
    return when (item.status) {
        com.atlasmasa.android.domain.PromptQueueStatus.RUNNING -> {
            if (item.outputType == PromptOutputType.PODCAST) {
                "Running Stage 1 (Gemini 3 Flash + GPT fallback) and Stage 2 (Gemini 2.5 Pro TTS)..."
            } else {
                "Model processing in progress..."
            }
        }
        com.atlasmasa.android.domain.PromptQueueStatus.QUEUED -> {
            if (item.outputType == PromptOutputType.PODCAST) {
                "Queued for podcast audio pipeline."
            } else {
                "Queued for processing."
            }
        }
        else -> "Pending..."
    }
}

@Composable
private fun FeedScreen(modifier: Modifier, ui: DashboardUiState, viewModel: MainViewModel) {
    LazyColumn(
        modifier = modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("Execution stream", style = MaterialTheme.typography.titleLarge)
                OutlinedButton(onClick = { viewModel.refreshFeed() }) { Text("Refresh") }
            }
            Text("Your productive-boredom stream: daily, mid-term, and long-term actions routed from memory, check-ins, and current energy.")
        }

        items(ui.feed, key = { it.id }) { item ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(item.title, style = MaterialTheme.typography.titleMedium)
                    Text(item.summary)
                    Text("Why now: ${item.whyNow}")
                    Text("Priority: ${item.priority}", style = MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
}

@Composable
private fun NotesScreen(modifier: Modifier, ui: DashboardUiState, viewModel: MainViewModel) {
    var title by rememberSaveable { mutableStateOf("") }
    var content by rememberSaveable { mutableStateOf("") }

    LazyColumn(
        modifier = modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Notes + memory", style = MaterialTheme.typography.titleLarge)
                    OutlinedTextField(title, { title = it }, label = { Text("Title") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(content, { content = it }, label = { Text("Content") }, modifier = Modifier.fillMaxWidth())
                    Button(onClick = {
                        if (content.isNotBlank()) {
                            viewModel.addNote(title, content)
                            title = ""
                            content = ""
                        }
                    }) { Text("Save note") }
                }
            }
        }
        items(ui.notes, key = { it.id }) { note ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(14.dp)) {
                    Text(note.title, style = MaterialTheme.typography.titleSmall)
                    Text(note.content)
                }
            }
        }
    }
}

@Composable
private fun WorkspacesScreen(modifier: Modifier, ui: DashboardUiState) {
    LazyColumn(
        modifier = modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Text("Workspace sessions", style = MaterialTheme.typography.titleLarge)
            Text("Notebook-like sessions with shared memory graph across workspaces.")
        }
        items(ui.workspaces, key = { it.id }) { ws ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(14.dp)) {
                    Text(ws.title, style = MaterialTheme.typography.titleSmall)
                    Text("Lane: ${ws.lane}")
                    Text(ws.summary)
                }
            }
        }
    }
}

@Composable
private fun AccessScreen(modifier: Modifier, ui: DashboardUiState, viewModel: MainViewModel) {
    var backendApiBase by remember(ui.session.apiBaseUrl) {
        mutableStateOf(ui.session.apiBaseUrl)
    }
    var openAiEndpoint by remember(ui.session.openAiCompatibleEndpoint) {
        mutableStateOf(ui.session.openAiCompatibleEndpoint)
    }
    var openAiApiKey by remember(ui.session.openAiCompatibleApiKey) {
        mutableStateOf(ui.session.openAiCompatibleApiKey)
    }
    var geminiApiKey by remember(ui.session.geminiApiKey) {
        mutableStateOf(ui.session.geminiApiKey)
    }
    var podcastVoice by remember(ui.session.podcastVoiceName) {
        mutableStateOf(ui.session.podcastVoiceName)
    }

    LazyColumn(
        modifier = modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Account access", style = MaterialTheme.typography.titleLarge)
                    Text("Provider: ${ui.session.accountProvider} · ${if (ui.session.isSignedIn) ui.session.accountLabel else "Guest"}")
                    Text(
                        if (ui.session.prepaidCreditsActive) {
                            "Prepaid credits active. AI command center unlocked."
                        } else {
                            "Prepaid credits required for AI command center."
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = if (ui.session.prepaidCreditsActive) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                    )
                    Text(
                        "Shared backend: ${ui.session.apiBaseUrl}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { viewModel.signInApple() }) { Text("Sign in with Apple") }
                        Button(onClick = { viewModel.signInGoogle() }) { Text("Sign in with Google") }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { viewModel.signInPasskey() }) { Text("Passwordless sign in") }
                        OutlinedButton(onClick = { viewModel.signOut() }) { Text("Sign out") }
                    }
                    Text("No email/password form. Provider auth + passkeys only.")
                }
            }
        }

        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Shared backend", style = MaterialTheme.typography.titleLarge)
                    Text(
                        "Matches web + iOS API routing. Use https://api.atlasmasa.com for production.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    OutlinedTextField(
                        value = backendApiBase,
                        onValueChange = { backendApiBase = it },
                        label = { Text("API base URL") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Button(
                        onClick = { viewModel.updateBackendRuntime(backendApiBase) },
                    ) {
                        Text("Save backend")
                    }
                }
            }
        }

        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Inference runtime", style = MaterialTheme.typography.titleLarge)
                    Text(
                        "Podcast pipeline: Stage 1 Gemini 3 Flash (GPT fallback) -> Stage 2 Gemini 2.5 Pro TTS.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    OutlinedTextField(
                        value = openAiEndpoint,
                        onValueChange = { openAiEndpoint = it },
                        label = { Text("OpenAI-compatible endpoint") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = openAiApiKey,
                        onValueChange = { openAiApiKey = it },
                        label = { Text("OpenAI-compatible API key") },
                        visualTransformation = PasswordVisualTransformation(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = geminiApiKey,
                        onValueChange = { geminiApiKey = it },
                        label = { Text("Gemini API key") },
                        visualTransformation = PasswordVisualTransformation(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = podcastVoice,
                        onValueChange = { podcastVoice = it },
                        label = { Text("Podcast voice (Kore, Aoede, Charon)") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = {
                                viewModel.updateInferenceRuntime(
                                    openAiEndpoint = openAiEndpoint,
                                    openAiApiKey = openAiApiKey,
                                    geminiApiKey = geminiApiKey,
                                    podcastVoiceName = podcastVoice,
                                )
                            },
                        ) {
                            Text("Save runtime")
                        }
                    }
                }
            }
        }

        item {
            TransparencySnippet(
                heading = "Why account state matters",
                bullets = listOf(
                    "Secure auth links your long-term memory graph to you.",
                    "Atlas uses signed-in data to build higher-precision planning.",
                    "Access layer exists for continuity and privacy, not friction."
                )
            )
        }
    }
}

@Composable
private fun GuideScreen(modifier: Modifier, ui: DashboardUiState, viewModel: MainViewModel) {
    val pendingQuestion = ui.session.adaptiveBusinessQuestions.firstOrNull { it.response == null }
    val answeredQuestions = ui.session.adaptiveBusinessQuestions.count { it.response != null }
    val pendingQuestions = ui.session.adaptiveBusinessQuestions.count { it.response == null }
    val surveyCompleted = ui.surveyQuestions.isNotEmpty() &&
        ui.surveyQuestions.all { !ui.session.surveyAnswers[it.id].isNullOrBlank() }

    var adaptiveQuestionEngineEnabled by remember(ui.session.adaptiveBusinessQuestionEngineEnabled) {
        mutableStateOf(ui.session.adaptiveBusinessQuestionEngineEnabled)
    }
    var adaptiveBusinessAutopilotEnabled by remember(ui.session.businessAutopilotEnabled) {
        mutableStateOf(ui.session.businessAutopilotEnabled)
    }
    var selectedOptions by remember(pendingQuestion?.id) { mutableStateOf(setOf<String>()) }
    var freeformResponse by remember(pendingQuestion?.id) { mutableStateOf("") }

    LazyColumn(
        modifier = modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Default.Book, contentDescription = null)
                        Text("How Atlas AI is trained and used", style = MaterialTheme.typography.titleLarge)
                    }
                    Text("Purpose: execution intelligence for life, work, mobility, and financial resilience.")
                    Text("Training stack: domain corpora + structured heuristics + safety rules + local reasoning runtime.")
                    Text("Privacy: local-first storage and queue processing on-device by default.")
                }
            }
        }

        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Continuous Adaptive Questionnaire", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Answered: $answeredQuestions · Pending: $pendingQuestions",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        ui.session.adaptiveBusinessRuntimeStatusLine,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )

                    if (!ui.session.guidedLearningRuntimeActive) {
                        Text(
                            if (surveyCompleted) {
                                "Survey is complete. Activate guided learning when you're ready to start using the app."
                            } else {
                                "Finish the initialization survey first, then activate guided learning."
                            },
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Button(
                            onClick = { viewModel.activateGuidedLearningAfterSurvey() },
                            enabled = surveyCompleted,
                        ) {
                            Text("Activate guided learning")
                        }
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = {
                                viewModel.saveAdaptiveBusinessRuntimeSettings(
                                    questionEngineEnabled = adaptiveQuestionEngineEnabled,
                                    businessAutopilotEnabled = adaptiveBusinessAutopilotEnabled,
                                )
                            },
                        ) {
                            Text("Save runtime settings")
                        }
                        OutlinedButton(onClick = { viewModel.requestNextAdaptiveBusinessQuestionNow() }) {
                            Text("Generate question now")
                        }
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AssistChip(
                            onClick = { adaptiveQuestionEngineEnabled = !adaptiveQuestionEngineEnabled },
                            label = { Text("Questions: ${if (adaptiveQuestionEngineEnabled) "On" else "Off"}") },
                        )
                        AssistChip(
                            onClick = { adaptiveBusinessAutopilotEnabled = !adaptiveBusinessAutopilotEnabled },
                            label = { Text("Autopilot: ${if (adaptiveBusinessAutopilotEnabled) "On" else "Off"}") },
                        )
                    }
                }
            }
        }

        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Pending adaptive question", style = MaterialTheme.typography.titleMedium)
                    if (pendingQuestion == null) {
                        Text("No pending question right now. Generate one now or wait for background runtime.")
                    } else {
                        Text(pendingQuestion.prompt, style = MaterialTheme.typography.bodyLarge)
                        pendingQuestion.options.forEach { option ->
                            OutlinedButton(
                                onClick = {
                                    selectedOptions = if (selectedOptions.contains(option)) {
                                        selectedOptions - option
                                    } else {
                                        selectedOptions + option
                                    }
                                },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(
                                    if (selectedOptions.contains(option)) {
                                        "[x] $option"
                                    } else {
                                        "[ ] $option"
                                    }
                                )
                            }
                        }
                        OutlinedTextField(
                            value = freeformResponse,
                            onValueChange = { freeformResponse = it },
                            label = { Text("Optional: add context") },
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Button(
                            onClick = {
                                viewModel.answerAdaptiveBusinessQuestion(
                                    questionId = pendingQuestion.id,
                                    selectedOptions = selectedOptions.toList(),
                                    freeformText = freeformResponse,
                                )
                                selectedOptions = emptySet()
                                freeformResponse = ""
                            },
                            enabled = selectedOptions.isNotEmpty() || freeformResponse.isNotBlank(),
                        ) {
                            Text("Submit response")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MobilityScreen(modifier: Modifier, ui: DashboardUiState) {
    LazyColumn(modifier = modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.DirectionsCar, null)
                        Text("Mobility operations", style = MaterialTheme.typography.titleLarge)
                    }
                    Text("Annual distance planning and continuity protocols for high-mileage users.")
                    Text("Current region: ${ui.session.languageCode.uppercase()} locale | Tier: ${ui.session.accountTier}")
                }
            }
        }
    }
}

@Composable
private fun PlansScreen(modifier: Modifier, ui: DashboardUiState) {
    LazyColumn(modifier = modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.CreditCard, null)
                        Text("Plans", style = MaterialTheme.typography.titleLarge)
                    }
                    Text("Current tier: ${ui.session.accountTier}")
                    Text("Local core is free and local-only. AI command center unlocks only after prepaid credits are active.")
                    Text(
                        if (ui.session.prepaidCreditsActive) {
                            "Status: Prepaid credits active."
                        } else {
                            "Status: Locked until prepaid credits are active."
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun OutputScreen(modifier: Modifier, ui: DashboardUiState) {
    LazyColumn(modifier = modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Default.Note, null)
                Text("System output", style = MaterialTheme.typography.titleLarge)
            }
        }
        items(ui.session.systemOutput.reversed()) { line ->
            Card(Modifier.fillMaxWidth()) {
                Text(line, modifier = Modifier.padding(12.dp))
            }
        }
    }
}

@Composable
private fun TransparencySnippet(heading: String, bullets: List<String>) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Default.Book, contentDescription = null)
                Text(heading, style = MaterialTheme.typography.titleMedium)
            }
            bullets.forEach { Text("• $it") }
        }
    }
}
