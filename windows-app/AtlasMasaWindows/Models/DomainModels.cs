using AtlasMasaWindows.Infrastructure;
using System.Text.Json.Serialization;

namespace AtlasMasaWindows.Models;

public enum AuthProvider { Guest, Apple, Google, Passkey }

public enum AccountTier { LocalCore, ProCloud }

public enum PromptQueueStatus { Queued, Running, Done, Failed }

public enum WorkspaceLane
{
    Command,
    Survey,
    Queue,
    Execution,
    Memory,
    Workspaces,
    Mobility,
    Access,
    Guide,
    Output
}

public enum LocalAIRuntimeStatusCode
{
    NotInstalled,
    InstallingRuntime,
    StartingRuntime,
    DownloadingModel,
    WarmingModel,
    Ready,
    Degraded,
    Error
}

public sealed class LocalAIModelPack
{
    public string Id { get; set; } = "starter";
    public string Title { get; set; } = string.Empty;
    public string Subtitle { get; set; } = string.Empty;
    public string PrimaryModel { get; set; } = "qwen2.5:7b";
    public List<string> SecondaryModels { get; set; } = [];
    public List<string> ModelOrder { get; set; } = [];
    public string ApproximateSize { get; set; } = string.Empty;
    public string MinimumHardwareTier { get; set; } = "balanced";
    public bool Recommended { get; set; }
}

public sealed class LocalAIModelInstallOption : ObservableObject
{
    private bool _isSelected;

    public string Id { get; set; } = "qwen2.5:7b";
    public string Title { get; set; } = string.Empty;
    public string Subtitle { get; set; } = string.Empty;
    public string ModelName { get; set; } = "qwen2.5:7b";
    public double ApproximateSizeGb { get; set; }
    public bool Recommended { get; set; }
    public bool IsSelected { get => _isSelected; set => SetProperty(ref _isSelected, value); }
    public string ApproximateSizeLabel => $"{ApproximateSizeGb:0.0} GB";
    public string RecommendedLabel => Recommended ? "Recommended" : string.Empty;
}

public sealed class AtlasSessionState : ObservableObject
{
    private bool _isSignedIn;
    private AuthProvider _provider = AuthProvider.Guest;
    private string _accountLabel = "Guest Operator";
    private AccountTier _tier = AccountTier.LocalCore;
    private bool _prepaidCreditsActive;
    private string _apiBaseUrl = "https://api.atlasmasa.com";
    private string _worldMonitorUrl = "https://worldmonitor.app";
    private string _languageCode = "en";
    private string _dailyPriority = string.Empty;
    private string _midTermGoal = string.Empty;
    private string _longTermVision = string.Empty;
    private string _blockers = string.Empty;
    private string _mood = "Focused";
    private int _energy = 3;
    private bool _gymToday;
    private bool _moneyToday;
    private bool _memoryOptIn = true;
    private bool _guidedLearningRuntimeActive;
    private bool _adaptiveBusinessQuestionEngineEnabled = true;
    private bool _businessAutopilotEnabled = true;
    private string _adaptiveBusinessRuntimeStatusLine = "Adaptive business runtime idle.";
    private bool _quantumLearningEnabled = true;
    private string _quantumLearningStatusLine = "Quantum learning simulator idle.";
    private QuantumLearningSnapshot? _quantumLearningSnapshot;
    private DateTimeOffset _lastAdaptiveBusinessQuestionAtUtc = DateTimeOffset.MinValue;
    private DateTimeOffset _lastBusinessAutopilotAtUtc = DateTimeOffset.MinValue;
    private int _adaptiveBusinessAutopilotCursor;
    private int _natureRiskScore = 0;
    private string _natureRiskBand = "low";
    private string _natureAlertSummary = "Nature monitor initializing.";
    private int _natureElevatedThreshold = 45;
    private int _natureCriticalThreshold = 70;
    private DateTimeOffset _lastNatureSignalRefreshAtUtc = DateTimeOffset.MinValue;
    private DateTimeOffset _lastNatureAlertNotificationAtUtc = DateTimeOffset.MinValue;
    private DateTimeOffset _lastWealthReminderNotificationAtUtc = DateTimeOffset.MinValue;
    private bool _localAiSetupCompleted;
    private bool _localAiSetupDeferred;
    private string _selectedLocalAiPackId = "starter";
    private string _selectedLocalAiModelIds = string.Empty;
    private string _localAiRuntimeStatusCode = nameof(LocalAIRuntimeStatusCode.NotInstalled);
    private string _localAiRuntimeLastError = string.Empty;
    private string _remoteControlToken = string.Empty;
    private bool _remoteTransferTutorialSeen;

    public bool IsSignedIn { get => _isSignedIn; set => SetProperty(ref _isSignedIn, value); }
    public AuthProvider Provider { get => _provider; set => SetProperty(ref _provider, value); }
    public string AccountLabel { get => _accountLabel; set => SetProperty(ref _accountLabel, value); }
    public AccountTier Tier { get => _tier; set => SetProperty(ref _tier, value); }
    public bool PrepaidCreditsActive { get => _prepaidCreditsActive; set => SetProperty(ref _prepaidCreditsActive, value); }
    public string ApiBaseUrl { get => _apiBaseUrl; set => SetProperty(ref _apiBaseUrl, value); }
    public string WorldMonitorUrl { get => _worldMonitorUrl; set => SetProperty(ref _worldMonitorUrl, value); }
    public string LanguageCode { get => _languageCode; set => SetProperty(ref _languageCode, value); }
    public string DailyPriority { get => _dailyPriority; set => SetProperty(ref _dailyPriority, value); }
    public string MidTermGoal { get => _midTermGoal; set => SetProperty(ref _midTermGoal, value); }
    public string LongTermVision { get => _longTermVision; set => SetProperty(ref _longTermVision, value); }
    public string Blockers { get => _blockers; set => SetProperty(ref _blockers, value); }
    public string Mood { get => _mood; set => SetProperty(ref _mood, value); }
    public int Energy { get => _energy; set => SetProperty(ref _energy, Math.Clamp(value, 1, 5)); }
    public bool GymToday { get => _gymToday; set => SetProperty(ref _gymToday, value); }
    public bool MoneyToday { get => _moneyToday; set => SetProperty(ref _moneyToday, value); }
    public bool MemoryOptIn { get => _memoryOptIn; set => SetProperty(ref _memoryOptIn, value); }
    public bool GuidedLearningRuntimeActive { get => _guidedLearningRuntimeActive; set => SetProperty(ref _guidedLearningRuntimeActive, value); }
    public bool AdaptiveBusinessQuestionEngineEnabled { get => _adaptiveBusinessQuestionEngineEnabled; set => SetProperty(ref _adaptiveBusinessQuestionEngineEnabled, value); }
    public bool BusinessAutopilotEnabled { get => _businessAutopilotEnabled; set => SetProperty(ref _businessAutopilotEnabled, value); }
    public string AdaptiveBusinessRuntimeStatusLine { get => _adaptiveBusinessRuntimeStatusLine; set => SetProperty(ref _adaptiveBusinessRuntimeStatusLine, value); }
    public bool QuantumLearningEnabled { get => _quantumLearningEnabled; set => SetProperty(ref _quantumLearningEnabled, value); }
    public string QuantumLearningStatusLine { get => _quantumLearningStatusLine; set => SetProperty(ref _quantumLearningStatusLine, value); }
    public QuantumLearningSnapshot? QuantumLearningSnapshot { get => _quantumLearningSnapshot; set => SetProperty(ref _quantumLearningSnapshot, value); }
    public DateTimeOffset LastAdaptiveBusinessQuestionAtUtc { get => _lastAdaptiveBusinessQuestionAtUtc; set => SetProperty(ref _lastAdaptiveBusinessQuestionAtUtc, value); }
    public DateTimeOffset LastBusinessAutopilotAtUtc { get => _lastBusinessAutopilotAtUtc; set => SetProperty(ref _lastBusinessAutopilotAtUtc, value); }
    public int AdaptiveBusinessAutopilotCursor { get => _adaptiveBusinessAutopilotCursor; set => SetProperty(ref _adaptiveBusinessAutopilotCursor, Math.Max(0, value)); }
    public int NatureRiskScore { get => _natureRiskScore; set => SetProperty(ref _natureRiskScore, Math.Clamp(value, 0, 100)); }
    public string NatureRiskBand { get => _natureRiskBand; set => SetProperty(ref _natureRiskBand, value); }
    public string NatureAlertSummary { get => _natureAlertSummary; set => SetProperty(ref _natureAlertSummary, value); }
    public int NatureElevatedThreshold { get => _natureElevatedThreshold; set => SetProperty(ref _natureElevatedThreshold, Math.Clamp(value, 20, 95)); }
    public int NatureCriticalThreshold { get => _natureCriticalThreshold; set => SetProperty(ref _natureCriticalThreshold, Math.Clamp(value, 25, 99)); }
    public DateTimeOffset LastNatureSignalRefreshAtUtc { get => _lastNatureSignalRefreshAtUtc; set => SetProperty(ref _lastNatureSignalRefreshAtUtc, value); }
    public DateTimeOffset LastNatureAlertNotificationAtUtc { get => _lastNatureAlertNotificationAtUtc; set => SetProperty(ref _lastNatureAlertNotificationAtUtc, value); }
    public DateTimeOffset LastWealthReminderNotificationAtUtc { get => _lastWealthReminderNotificationAtUtc; set => SetProperty(ref _lastWealthReminderNotificationAtUtc, value); }
    public bool LocalAiSetupCompleted { get => _localAiSetupCompleted; set => SetProperty(ref _localAiSetupCompleted, value); }
    public bool LocalAiSetupDeferred { get => _localAiSetupDeferred; set => SetProperty(ref _localAiSetupDeferred, value); }
    public string SelectedLocalAiPackId { get => _selectedLocalAiPackId; set => SetProperty(ref _selectedLocalAiPackId, value); }
    public string SelectedLocalAiModelIds { get => _selectedLocalAiModelIds; set => SetProperty(ref _selectedLocalAiModelIds, value); }
    public string LocalAiRuntimeStatusCode { get => _localAiRuntimeStatusCode; set => SetProperty(ref _localAiRuntimeStatusCode, value); }
    public string LocalAiRuntimeLastError { get => _localAiRuntimeLastError; set => SetProperty(ref _localAiRuntimeLastError, value); }
    public string RemoteControlToken { get => _remoteControlToken; set => SetProperty(ref _remoteControlToken, value); }
    public bool RemoteTransferTutorialSeen { get => _remoteTransferTutorialSeen; set => SetProperty(ref _remoteTransferTutorialSeen, value); }
}

public sealed class SystemLogLine
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Text { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class SurveyChoice
{
    public string Value { get; set; } = string.Empty;
    public string Label { get; set; } = string.Empty;
}

public sealed class SurveyQuestion
{
    public string Id { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Kind { get; set; } = "choice";
    public List<SurveyChoice> Choices { get; set; } = [];
}

public sealed class SurveyAnswer
{
    public string QuestionId { get; set; } = string.Empty;
    public string Value { get; set; } = string.Empty;
}

public sealed class NoteRecord
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Title { get; set; } = string.Empty;
    public string Content { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class QueueRecord : ObservableObject
{
    private PromptQueueStatus _status = PromptQueueStatus.Queued;
    private double _progress;
    private string? _checkpointNote;
    private string? _outputSummary;
    private string? _nextAction;
    private double? _confidence;
    private string? _errorMessage;
    private DateTimeOffset? _startedAt;
    private DateTimeOffset? _completedAt;
    private string? _reasoningSummary;
    private string? _confidenceLabel;

    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Prompt { get; set; } = string.Empty;
    public string? CodeAgentRoute { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public PromptQueueStatus Status { get => _status; set => SetProperty(ref _status, value); }
    public DateTimeOffset? StartedAt { get => _startedAt; set => SetProperty(ref _startedAt, value); }
    public DateTimeOffset? CompletedAt { get => _completedAt; set => SetProperty(ref _completedAt, value); }
    public double Progress { get => _progress; set => SetProperty(ref _progress, Math.Clamp(value, 0.0, 1.0)); }
    public string? CheckpointNote { get => _checkpointNote; set => SetProperty(ref _checkpointNote, value); }
    public string? OutputSummary { get => _outputSummary; set => SetProperty(ref _outputSummary, value); }
    public string? NextAction { get => _nextAction; set => SetProperty(ref _nextAction, value); }
    public double? Confidence { get => _confidence; set => SetProperty(ref _confidence, value); }
    public string? ErrorMessage { get => _errorMessage; set => SetProperty(ref _errorMessage, value); }
    public string? ReasoningSummary { get => _reasoningSummary; set => SetProperty(ref _reasoningSummary, value); }
    public string? ConfidenceLabel { get => _confidenceLabel; set => SetProperty(ref _confidenceLabel, value); }
    public List<string> AlternativesConsidered { get; set; } = [];
    public List<string> Assumptions { get; set; } = [];
    public bool HasReasoningDetails =>
        !string.IsNullOrWhiteSpace(ReasoningSummary) ||
        AlternativesConsidered.Count > 0 ||
        Assumptions.Count > 0 ||
        !string.IsNullOrWhiteSpace(ConfidenceLabel);
}

public sealed class MemoryRecord
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Type { get; set; } = string.Empty;
    public string Source { get; set; } = "windows";
    public double Weight { get; set; } = 0.5;
    public DateTimeOffset Recency { get; set; } = DateTimeOffset.UtcNow;
    public List<string> Tags { get; set; } = [];
    public string Value { get; set; } = string.Empty;
}

public sealed class AdaptiveBusinessQuestionResponse
{
    public List<string> SelectedOptions { get; set; } = [];
    public string FreeformText { get; set; } = string.Empty;
    public DateTimeOffset AnsweredAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class AdaptiveBusinessQuestion
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Prompt { get; set; } = string.Empty;
    public List<string> Options { get; set; } = [];
    public bool AllowsMultipleSelection { get; set; } = true;
    public string Source { get; set; } = "fallback";
    public DateTimeOffset GeneratedAt { get; set; } = DateTimeOffset.UtcNow;
    public AdaptiveBusinessQuestionResponse? Response { get; set; }
}

public sealed class QuantumTrackScore
{
    public string Track { get; set; } = string.Empty;
    public double Probability { get; set; }
}

public sealed class QuantumLearningSnapshot
{
    public DateTimeOffset GeneratedAt { get; set; } = DateTimeOffset.UtcNow;
    public string DominantTrack { get; set; } = "acquisition";
    public double DominantProbability { get; set; }
    public List<QuantumTrackScore> TrackProbabilities { get; set; } = [];
    public string RecommendedQuestion { get; set; } = string.Empty;
    public List<string> RecommendedOptions { get; set; } = [];
    public string Rationale { get; set; } = string.Empty;
    public string Source { get; set; } = "quantum_simulator_v1";
}

public sealed class WorkspaceSession
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public WorkspaceLane Lane { get; set; } = WorkspaceLane.Command;
    public string Title { get; set; } = string.Empty;
    public string Summary { get; set; } = string.Empty;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class FeedItem
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Title { get; set; } = string.Empty;
    public string Summary { get; set; } = string.Empty;
    [JsonPropertyName("why_now")]
    public string WhyNow { get; set; } = string.Empty;
    public string Priority { get; set; } = "normal";
    public string? SourceType { get; set; }
}

public sealed class OperatorStateSnapshot
{
    public string Id { get; set; } = "operator-state";
    public string Mode { get; set; } = "short_idle_window";
    public string Summary { get; set; } = string.Empty;
    public string NextAction { get; set; } = string.Empty;
    public string Rationale { get; set; } = string.Empty;
    public bool ContinuityRiskActive { get; set; }
    public int EnergyLevel { get; set; } = 3;
    public string Mood { get; set; } = "Focused";
    public string? BlockerSummary { get; set; }
    public DateTimeOffset GeneratedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class ChecklistStep : ObservableObject
{
    private bool _isCompleted;
    private string? _notes;

    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Title { get; set; } = string.Empty;
    public string Rationale { get; set; } = string.Empty;
    public string Instructions { get; set; } = string.Empty;
    public List<string> ExternalLinks { get; set; } = [];
    public List<string> FileReferences { get; set; } = [];
    public bool IsCompleted { get => _isCompleted; set => SetProperty(ref _isCompleted, value); }
    public string? Notes { get => _notes; set => SetProperty(ref _notes, value); }
}

public sealed class ChecklistPlan
{
    public string Id { get; set; } = "active-checklist-plan";
    public string Title { get; set; } = string.Empty;
    public string Summary { get; set; } = string.Empty;
    public string CreatedFrom { get; set; } = string.Empty;
    public List<ChecklistStep> Steps { get; set; } = [];
    public DateTimeOffset GeneratedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class ActivitySuggestion
{
    public string Id { get; set; } = "activity-suggestion";
    public string Title { get; set; } = string.Empty;
    public string Summary { get; set; } = string.Empty;
    public string DurationLabel { get; set; } = string.Empty;
    public string Reason { get; set; } = string.Empty;
    public DateTimeOffset GeneratedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class ItineraryStep
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string TimeLabel { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string Summary { get; set; } = string.Empty;
}

public sealed class ItineraryPlan
{
    public string Id { get; set; } = "itinerary-plan";
    public string Title { get; set; } = string.Empty;
    public string Summary { get; set; } = string.Empty;
    public string Kind { get; set; } = "workday";
    public List<ItineraryStep> Steps { get; set; } = [];
    public DateTimeOffset GeneratedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class SupportRecommendation
{
    public string Id { get; set; } = "support-recommendation";
    public string Title { get; set; } = string.Empty;
    public string Summary { get; set; } = string.Empty;
    public string? BodyDoublingPrompt { get; set; }
    public DateTimeOffset GeneratedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class NatureSignalTile
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Title { get; set; } = string.Empty;
    public string Metric { get; set; } = string.Empty;
    public string Trend { get; set; } = "stable";
    public string Severity { get; set; } = "info";
    public string SourceLabel { get; set; } = string.Empty;
    public string SourceUrl { get; set; } = string.Empty;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class NatureSignalSnapshot
{
    public List<NatureSignalTile> Tiles { get; set; } = [];
    public int RiskScore { get; set; }
    public string RiskBand { get; set; } = "low";
    public string AlertSummary { get; set; } = "Nature signals stable.";
    public DateTimeOffset RefreshedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class AuthCookieRecord
{
    public string Name { get; set; } = string.Empty;
    public string Value { get; set; } = string.Empty;
    public string Domain { get; set; } = string.Empty;
    public string Path { get; set; } = "/";
    public DateTimeOffset? ExpiresAtUtc { get; set; }
    public bool Secure { get; set; }
    public bool HttpOnly { get; set; }
    public string SameSite { get; set; } = string.Empty;
}

public sealed class AtlasDataEnvelope
{
    public AtlasSessionState Session { get; set; } = new();
    public List<SystemLogLine> SystemOutput { get; set; } = [];
    public List<NoteRecord> Notes { get; set; } = [];
    public List<QueueRecord> Queue { get; set; } = [];
    public List<MemoryRecord> Memory { get; set; } = [];
    public List<WorkspaceSession> Workspaces { get; set; } = [];
    public List<SurveyAnswer> SurveyAnswers { get; set; } = [];
    public List<AdaptiveBusinessQuestion> AdaptiveBusinessQuestions { get; set; } = [];
    public List<NatureSignalTile> NatureSignalTiles { get; set; } = [];
    public OperatorStateSnapshot? OperatorStateSnapshot { get; set; }
    public ChecklistPlan? ActiveChecklistPlan { get; set; }
    public ActivitySuggestion? CurrentActivitySuggestion { get; set; }
    public ItineraryPlan? CurrentItineraryPlan { get; set; }
    public SupportRecommendation? CurrentSupportRecommendation { get; set; }
    public List<AuthCookieRecord> ApiAuthCookies { get; set; } = [];
    public DateTimeOffset LastSavedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class MemoryVaultPolicy
{
    public string HardwareTier { get; set; } = "balanced";
    public int ContextBudgetTokens { get; set; } = 6000;
    public int CompactionThresholdTokens { get; set; } = 4800;
    public int RetrievalDepth { get; set; } = 4;
    public int ResponseBudgetTokens { get; set; } = 820;
    public string ArchiveSearchMode { get; set; } = "native_encrypted_local_index";
    public string ModelGuidance { get; set; } = "balanced_local_model";
}

public sealed class MemoryVaultRawRecord
{
    public string RecordId { get; set; } = Guid.NewGuid().ToString();
    public string SourceType { get; set; } = string.Empty;
    public string SourceLabel { get; set; } = string.Empty;
    public List<string> Tags { get; set; } = [];
    public string Content { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public bool DeepArchived { get; set; }
}

public sealed class MemoryVaultCompactedRecord
{
    public string RecordId { get; set; } = Guid.NewGuid().ToString();
    public string Title { get; set; } = string.Empty;
    public string Summary { get; set; } = string.Empty;
    public List<string> SourceRecordIds { get; set; } = [];
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public string TriggerReason { get; set; } = string.Empty;
}

public sealed class MemoryVaultArtifactRecord
{
    public string ArtifactId { get; set; } = Guid.NewGuid().ToString();
    public string ArtifactType { get; set; } = string.Empty;
    public string Summary { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class MemoryVaultSnapshot
{
    public int SchemaVersion { get; set; } = 1;
    public List<MemoryVaultRawRecord> RawRecords { get; set; } = [];
    public List<MemoryVaultCompactedRecord> CompactedRecords { get; set; } = [];
    public List<MemoryVaultArtifactRecord> ArtifactRecords { get; set; } = [];
    public MemoryVaultPolicy LastPolicy { get; set; } = new();
    public int LastTokenPressure { get; set; }
    public string LastCompactionReason { get; set; } = "none";
    public string LastArchiveMode { get; set; } = "raw";
    public string LastSyncReason { get; set; } = "startup";
    public DateTimeOffset? LastCompactedAt { get; set; }
    public DateTimeOffset LastSavedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class MemoryRecallHit
{
    public string Summary { get; set; } = string.Empty;
    public string SourceLabel { get; set; } = string.Empty;
    public DateTimeOffset Timestamp { get; set; } = DateTimeOffset.UtcNow;
    public string MatchReason { get; set; } = string.Empty;
}

public sealed class LocalReasoningOutput
{
    public string Model { get; set; } = "atlas-windows-local-reasoner-v1";
    public string Summary { get; set; } = string.Empty;
    public string NextAction { get; set; } = string.Empty;
    public double Confidence { get; set; }
    public DateTimeOffset GeneratedAt { get; set; } = DateTimeOffset.UtcNow;
    public string? ReasoningSummary { get; set; }
    public List<string> AlternativesConsidered { get; set; } = [];
    public List<string> Assumptions { get; set; } = [];
    public string? ConfidenceLabel { get; set; }
}
