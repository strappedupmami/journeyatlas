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

public sealed class AtlasSessionState : ObservableObject
{
    private bool _isSignedIn;
    private AuthProvider _provider = AuthProvider.Guest;
    private string _accountLabel = "Guest Operator";
    private AccountTier _tier = AccountTier.LocalCore;
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

    public bool IsSignedIn { get => _isSignedIn; set => SetProperty(ref _isSignedIn, value); }
    public AuthProvider Provider { get => _provider; set => SetProperty(ref _provider, value); }
    public string AccountLabel { get => _accountLabel; set => SetProperty(ref _accountLabel, value); }
    public AccountTier Tier { get => _tier; set => SetProperty(ref _tier, value); }
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

    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Prompt { get; set; } = string.Empty;
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
    public DateTimeOffset LastSavedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class LocalReasoningOutput
{
    public string Model { get; set; } = "atlas-windows-local-reasoner-v1";
    public string Summary { get; set; } = string.Empty;
    public string NextAction { get; set; } = string.Empty;
    public double Confidence { get; set; }
    public DateTimeOffset GeneratedAt { get; set; } = DateTimeOffset.UtcNow;
}
