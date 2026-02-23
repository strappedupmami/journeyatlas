package com.atlasmasa.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Note
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle

private enum class RootTab(val title: String) {
    HOME("Command"),
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
                            Text("Atlas", fontWeight = FontWeight.SemiBold)
                            Text("Travel Design OS", style = MaterialTheme.typography.labelMedium)
                        }
                    },
                )
            },
            bottomBar = {
                NavigationBar {
                    listOf(RootTab.HOME, RootTab.SURVEY, RootTab.QUEUE, RootTab.FEED, RootTab.ACCESS).forEach { item ->
                        NavigationBarItem(
                            selected = tab == item,
                            onClick = { tab = item },
                            icon = {
                                Icon(
                                    imageVector = when (item) {
                                        RootTab.HOME -> Icons.Default.Home
                                        RootTab.SURVEY -> Icons.Default.Menu
                                        RootTab.QUEUE -> Icons.Default.PlayArrow
                                        RootTab.FEED -> Icons.Default.Bolt
                                        RootTab.ACCESS -> Icons.Default.AccountCircle
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
                RootTab.SURVEY -> SurveyScreen(Modifier.padding(padding), ui, viewModel)
                RootTab.QUEUE -> QueueScreen(Modifier.padding(padding), ui, viewModel)
                RootTab.FEED -> FeedScreen(Modifier.padding(padding), ui, viewModel)
                RootTab.WORKSPACES -> WorkspacesScreen(Modifier.padding(padding), ui)
                RootTab.NOTES -> NotesScreen(Modifier.padding(padding), ui, viewModel)
                RootTab.ACCESS -> AccessScreen(Modifier.padding(padding), ui, viewModel)
                RootTab.GUIDE -> GuideScreen(Modifier.padding(padding))
                RootTab.MOBILITY -> MobilityScreen(Modifier.padding(padding), ui)
                RootTab.PLANS -> PlansScreen(Modifier.padding(padding), ui)
                RootTab.OUTPUT -> OutputScreen(Modifier.padding(padding), ui)
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
                    Text("Queue local reasoning", style = MaterialTheme.typography.titleMedium)
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
                        enabled = prompt.isNotBlank(),
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
    LazyColumn(
        modifier = modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text("Adaptive deep survey", style = MaterialTheme.typography.titleLarge)
            Text("Answers shape execution stream and workspace intelligence.")
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
    LazyColumn(
        modifier = modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("Prompt queue", style = MaterialTheme.typography.titleLarge)
                TextButton(onClick = { viewModel.refreshFeed() }) { Text("Refresh") }
            }
            Text("Queue uses local reasoning and survives reboot via persistent DB + WorkManager.")
        }

        item {
            TransparencySnippet(
                heading = "How queue reasoning works",
                bullets = listOf(
                    "Queued prompts are processed by local Atlas reasoning workers.",
                    "Outputs are tuned for next actions, not generic chat responses.",
                    "Processing state is persisted so execution can resume after restart."
                )
            )
        }

        items(ui.queue, key = { it.id }) { item ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(item.prompt, style = MaterialTheme.typography.titleSmall)
                    Text("Status: ${item.status.name} · Progress ${(item.progress * 100).toInt()}%")
                    item.outputSummary?.let { Text("Summary: $it") }
                    item.nextAction?.let { Text("Next: $it") }
                    item.errorMessage?.let { Text("Error: $it", color = MaterialTheme.colorScheme.error) }
                }
            }
        }
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
            Text("Daily, mid-term, and long-term orchestration from your memory + check-ins.")
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
    LazyColumn(
        modifier = modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Account access", style = MaterialTheme.typography.titleLarge)
                    Text("Provider: ${ui.session.accountProvider} · ${if (ui.session.isSignedIn) ui.session.accountLabel else "Guest"}")
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
private fun GuideScreen(modifier: Modifier) {
    LazyColumn(
        modifier = modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
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
                    Text("Local core is free and local-only. Pro cloud adds server reasoning + premium orchestration.")
                    Text("Billing button should appear after sign in and only when cloud billing is enabled.")
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
