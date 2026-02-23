using AtlasMasaWindows.Infrastructure;
using AtlasMasaWindows.Models;
using AtlasMasaWindows.Services;
using Microsoft.UI.Dispatching;
using System.Collections.ObjectModel;

namespace AtlasMasaWindows.ViewModels;

public sealed class MainViewModel : ObservableObject, IAsyncDisposable
{
    private readonly DispatcherQueue _dispatcher;
    private readonly AppStateStore _stateStore;
    private readonly LocalReasoningEngine _reasoning;
    private readonly SystemPerformanceProfile _performance;
    private readonly SemaphoreSlim _saveLock = new(1, 1);
    private readonly HashSet<string> _activeQueueIds = [];
    private readonly Dictionary<string, string> _surveyAnswers = [];
    private readonly List<SurveyQuestion> _surveyQuestions;
    private readonly CancellationTokenSource _queueCts = new();
    private Task? _queueLoopTask;
    private bool _isInitialized;
    private int _surveyQuestionIndex;
    private string _newPrompt = string.Empty;
    private string _newNoteTitle = string.Empty;
    private string _newNoteContent = string.Empty;
    private string _newWorkspaceTitle = string.Empty;
    private string _newWorkspaceSummary = string.Empty;
    private SurveyQuestion? _currentSurveyQuestion;
    private string _surveyProgressText = "0 / 0";
    private bool _isSurveyCompleted;
    private bool _canAccessExecution;
    private string _selectedSurveyAnswerLabel = string.Empty;

    public AtlasSessionState Session { get; } = new();
    public ObservableCollection<SystemLogLine> SystemOutput { get; } = [];
    public ObservableCollection<NoteRecord> Notes { get; } = [];
    public ObservableCollection<QueueRecord> Queue { get; } = [];
    public ObservableCollection<MemoryRecord> Memory { get; } = [];
    public ObservableCollection<WorkspaceSession> Workspaces { get; } = [];
    public ObservableCollection<FeedItem> ExecutionFeed { get; } = [];
    public ObservableCollection<SurveyChoice> CurrentSurveyChoices { get; } = [];

    public string AppTitle => "Atlas Travel Design OS - Windows";
    public string PerformanceSummary => $"Mode: {_performance.Label} | Cores: {_performance.CpuCores} | RAM≈{_performance.PhysicalMemoryGb}GB | Queue workers: {_performance.MaxQueueWorkers}";

    public string NewPrompt
    {
        get => _newPrompt;
        set
        {
            if (SetProperty(ref _newPrompt, value))
            {
                EnqueuePromptCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public string NewNoteTitle
    {
        get => _newNoteTitle;
        set
        {
            if (SetProperty(ref _newNoteTitle, value))
            {
                AddNoteCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public string NewNoteContent
    {
        get => _newNoteContent;
        set
        {
            if (SetProperty(ref _newNoteContent, value))
            {
                AddNoteCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public string NewWorkspaceTitle
    {
        get => _newWorkspaceTitle;
        set
        {
            if (SetProperty(ref _newWorkspaceTitle, value))
            {
                AddWorkspaceSessionCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public string NewWorkspaceSummary
    {
        get => _newWorkspaceSummary;
        set => SetProperty(ref _newWorkspaceSummary, value);
    }

    public SurveyQuestion? CurrentSurveyQuestion
    {
        get => _currentSurveyQuestion;
        private set => SetProperty(ref _currentSurveyQuestion, value);
    }

    public string SurveyProgressText
    {
        get => _surveyProgressText;
        private set => SetProperty(ref _surveyProgressText, value);
    }

    public bool IsSurveyCompleted
    {
        get => _isSurveyCompleted;
        private set => SetProperty(ref _isSurveyCompleted, value);
    }

    public bool CanAccessExecution
    {
        get => _canAccessExecution;
        private set => SetProperty(ref _canAccessExecution, value);
    }

    public string SurveyCompletionLine => IsSurveyCompleted
        ? "Survey complete. Execution stream unlocked."
        : "Survey in progress. Complete all questions to unlock full execution stream.";

    public string ExecutionAccessLine => CanAccessExecution
        ? "Execution stream: unlocked."
        : "Execution stream: locked until survey completion.";

    public string SelectedSurveyAnswerLabel
    {
        get => _selectedSurveyAnswerLabel;
        private set => SetProperty(ref _selectedSurveyAnswerLabel, value);
    }

    public AsyncRelayCommand SubmitCheckInCommand { get; }
    public AsyncRelayCommand AddNoteCommand { get; }
    public AsyncRelayCommand EnqueuePromptCommand { get; }
    public AsyncRelayCommand RefreshExecutionCommand { get; }
    public AsyncRelayCommand AddWorkspaceSessionCommand { get; }
    public AsyncRelayCommand SignInAppleCommand { get; }
    public AsyncRelayCommand SignInGoogleCommand { get; }
    public AsyncRelayCommand SignInPasskeyCommand { get; }
    public AsyncRelayCommand SignOutCommand { get; }
    public AsyncRelayCommand ToggleLanguageCommand { get; }
    public RelayCommand<SurveyChoice> AnswerSurveyChoiceCommand { get; }

    public MainViewModel(DispatcherQueue dispatcherQueue)
    {
        _dispatcher = dispatcherQueue;
        _stateStore = new AppStateStore();
        _reasoning = new LocalReasoningEngine();
        _performance = SystemPerformanceProfile.Detect();
        _surveyQuestions = BuildSurveyQuestions();

        SubmitCheckInCommand = new AsyncRelayCommand(SubmitCheckInAsync);
        AddNoteCommand = new AsyncRelayCommand(AddNoteAsync, () => !string.IsNullOrWhiteSpace(NewNoteContent));
        EnqueuePromptCommand = new AsyncRelayCommand(EnqueuePromptAsync, () => !string.IsNullOrWhiteSpace(NewPrompt));
        RefreshExecutionCommand = new AsyncRelayCommand(RefreshExecutionAsync);
        AddWorkspaceSessionCommand = new AsyncRelayCommand(AddWorkspaceSessionAsync, () => !string.IsNullOrWhiteSpace(NewWorkspaceTitle));
        SignInAppleCommand = new AsyncRelayCommand(() => SignInAsync(AuthProvider.Apple, "Apple account"));
        SignInGoogleCommand = new AsyncRelayCommand(() => SignInAsync(AuthProvider.Google, "Google account"));
        SignInPasskeyCommand = new AsyncRelayCommand(() => SignInAsync(AuthProvider.Passkey, "Passwordless passkey"));
        SignOutCommand = new AsyncRelayCommand(SignOutAsync);
        ToggleLanguageCommand = new AsyncRelayCommand(ToggleLanguageAsync);
        AnswerSurveyChoiceCommand = new RelayCommand<SurveyChoice>(choice =>
        {
            if (choice is not null)
            {
                _ = AnswerSurveyChoiceAsync(choice);
            }
        });
    }

    public async Task InitializeAsync()
    {
        if (_isInitialized)
        {
            return;
        }
        _isInitialized = true;

        var loaded = await _stateStore.LoadAsync();
        HydrateFromEnvelope(loaded);
        AddSystemOutput("Atlas Windows local core booted.");
        AddSystemOutput(PerformanceSummary);
        AddSystemOutput("Prompt queue is resumable and survives app restart.");
        RefreshSurveyCursor();
        await RefreshExecutionAsync();
        StartQueueRuntime();
        await PersistAsync();
    }

    public async Task PersistOnExitAsync()
    {
        await PersistAsync();
    }

    private async Task SignInAsync(AuthProvider provider, string label)
    {
        Session.IsSignedIn = true;
        Session.Provider = provider;
        Session.AccountLabel = label;
        Session.Tier = AccountTier.LocalCore;
        AddSystemOutput($"Signed in with {provider} (local compute tier active).");
        await PersistAsync();
    }

    private async Task SignOutAsync()
    {
        Session.IsSignedIn = false;
        Session.Provider = AuthProvider.Guest;
        Session.AccountLabel = "Guest Operator";
        Session.Tier = AccountTier.LocalCore;
        AddSystemOutput("Signed out. Local data remains on this device unless manually cleared.");
        await PersistAsync();
    }

    private async Task ToggleLanguageAsync()
    {
        Session.LanguageCode = Session.LanguageCode.StartsWith("he", StringComparison.OrdinalIgnoreCase) ? "en" : "he";
        AddSystemOutput($"Language switched to {Session.LanguageCode}.");
        await PersistAsync();
    }

    private async Task SubmitCheckInAsync()
    {
        if (string.IsNullOrWhiteSpace(Session.DailyPriority))
        {
            AddSystemOutput("Check-in skipped: add daily priority first.");
            return;
        }

        var recency = DateTimeOffset.UtcNow;
        Memory.Insert(0, new MemoryRecord
        {
            Type = "execution_checkin",
            Source = "windows",
            Weight = Session.MoneyToday ? 0.92 : 0.74,
            Recency = recency,
            Tags = BuildCheckinTags(),
            Value = $"daily={Session.DailyPriority} | mid={Session.MidTermGoal} | long={Session.LongTermVision} | blockers={Session.Blockers}"
        });
        TrimMemory();

        Workspaces.Insert(0, new WorkspaceSession
        {
            Lane = WorkspaceLane.Command,
            Title = Session.DailyPriority[..Math.Min(Session.DailyPriority.Length, 72)],
            Summary = $"Mood={Session.Mood}; Energy={Session.Energy}; Gym={Session.GymToday}; Money={Session.MoneyToday}",
            UpdatedAt = recency
        });
        TrimWorkspaces();

        AddSystemOutput("Check-in recorded. Execution stream refreshed.");
        await RefreshExecutionAsync();
        await PersistAsync();
    }

    private async Task AddNoteAsync()
    {
        var title = string.IsNullOrWhiteSpace(NewNoteTitle) ? "Untitled note" : NewNoteTitle.Trim();
        var content = NewNoteContent.Trim();
        if (content.Length == 0)
        {
            return;
        }

        Notes.Insert(0, new NoteRecord
        {
            Title = title[..Math.Min(title.Length, 100)],
            Content = content[..Math.Min(content.Length, 12000)],
            CreatedAt = DateTimeOffset.UtcNow
        });
        if (Notes.Count > 2000)
        {
            while (Notes.Count > 2000)
            {
                Notes.RemoveAt(Notes.Count - 1);
            }
        }

        if (Session.MemoryOptIn)
        {
            Memory.Insert(0, new MemoryRecord
            {
                Type = "note",
                Source = "windows",
                Weight = 0.62,
                Recency = DateTimeOffset.UtcNow,
                Tags = ["notes", "manual_capture"],
                Value = $"{title}: {content[..Math.Min(content.Length, 220)]}"
            });
            TrimMemory();
        }

        NewNoteTitle = string.Empty;
        NewNoteContent = string.Empty;
        AddSystemOutput("Note captured and indexed.");
        await RefreshExecutionAsync();
        await PersistAsync();
    }

    private async Task EnqueuePromptAsync()
    {
        var prompt = NewPrompt.Trim();
        if (prompt.Length == 0)
        {
            return;
        }
        if (Queue.Count >= 400)
        {
            AddSystemOutput("Queue limit reached (400). Clear older completed items before adding more.");
            return;
        }

        Queue.Insert(0, new QueueRecord
        {
            Prompt = prompt[..Math.Min(prompt.Length, 2200)],
            Status = PromptQueueStatus.Queued,
            Progress = 0.0,
            CheckpointNote = "Queued"
        });
        NewPrompt = string.Empty;
        AddSystemOutput("Prompt queued for local reasoning.");
        await PersistAsync();
    }

    private async Task RefreshExecutionAsync()
    {
        await _dispatcher.EnqueueAsync(() =>
        {
            var feed = BuildExecutionFeed();
            ExecutionFeed.Clear();
            foreach (var item in feed)
            {
                ExecutionFeed.Add(item);
            }
        });
        await PersistAsync();
    }

    private async Task AddWorkspaceSessionAsync()
    {
        var title = NewWorkspaceTitle.Trim();
        if (title.Length == 0)
        {
            return;
        }

        var summary = NewWorkspaceSummary.Trim();
        Workspaces.Insert(0, new WorkspaceSession
        {
            Lane = WorkspaceLane.Workspaces,
            Title = title[..Math.Min(title.Length, 90)],
            Summary = summary.Length == 0 ? "Session created from Windows dashboard." : summary[..Math.Min(summary.Length, 220)],
            UpdatedAt = DateTimeOffset.UtcNow
        });
        TrimWorkspaces();
        NewWorkspaceTitle = string.Empty;
        NewWorkspaceSummary = string.Empty;
        AddSystemOutput("Workspace notebook session created.");
        await PersistAsync();
    }

    private async Task AnswerSurveyChoiceAsync(SurveyChoice choice)
    {
        var current = CurrentSurveyQuestion;
        if (current is null)
        {
            return;
        }

        _surveyAnswers[current.Id] = choice.Value;
        SelectedSurveyAnswerLabel = choice.Label;
        IsSurveyCompleted = _surveyAnswers.Count >= _surveyQuestions.Count;
        CanAccessExecution = IsSurveyCompleted;
        RaisePropertyChanged(nameof(SurveyCompletionLine));
        RaisePropertyChanged(nameof(ExecutionAccessLine));
        SurveyProgressText = $"{_surveyAnswers.Count} / {_surveyQuestions.Count}";

        if (Session.MemoryOptIn)
        {
            Memory.Insert(0, new MemoryRecord
            {
                Type = "survey_answer",
                Source = "windows_survey",
                Weight = 0.72,
                Recency = DateTimeOffset.UtcNow,
                Tags = ["survey", current.Id],
                Value = $"{current.Title} => {choice.Label}"
            });
            TrimMemory();
        }

        RefreshSurveyCursor();
        AddSystemOutput($"Survey captured: {current.Id} = {choice.Value}");
        await RefreshExecutionAsync();
        await PersistAsync();
    }

    private void RefreshSurveyCursor()
    {
        if (_surveyQuestions.Count == 0)
        {
            CurrentSurveyQuestion = null;
            CurrentSurveyChoices.Clear();
            SurveyProgressText = "0 / 0";
            IsSurveyCompleted = true;
            CanAccessExecution = true;
            return;
        }

        var next = _surveyQuestions.FirstOrDefault(q => !_surveyAnswers.ContainsKey(q.Id));
        if (next is null)
        {
            _surveyQuestionIndex = _surveyQuestions.Count - 1;
            CurrentSurveyQuestion = _surveyQuestions[^1];
            CurrentSurveyChoices.Clear();
            foreach (var choice in _surveyQuestions[^1].Choices)
            {
                CurrentSurveyChoices.Add(choice);
            }
            IsSurveyCompleted = true;
            CanAccessExecution = true;
            RaisePropertyChanged(nameof(SurveyCompletionLine));
            RaisePropertyChanged(nameof(ExecutionAccessLine));
        }
        else
        {
            _surveyQuestionIndex = _surveyQuestions.IndexOf(next);
            CurrentSurveyQuestion = next;
            CurrentSurveyChoices.Clear();
            foreach (var choice in next.Choices)
            {
                CurrentSurveyChoices.Add(choice);
            }
            IsSurveyCompleted = _surveyAnswers.Count >= _surveyQuestions.Count;
            CanAccessExecution = IsSurveyCompleted;
            RaisePropertyChanged(nameof(SurveyCompletionLine));
            RaisePropertyChanged(nameof(ExecutionAccessLine));
        }

        SurveyProgressText = $"{_surveyAnswers.Count} / {_surveyQuestions.Count}";
        SelectedSurveyAnswerLabel = CurrentSurveyQuestion is null
            ? string.Empty
            : _surveyAnswers.TryGetValue(CurrentSurveyQuestion.Id, out var answer)
                ? CurrentSurveyQuestion.Choices.FirstOrDefault(x => x.Value == answer)?.Label ?? answer
                : string.Empty;
    }

    private void StartQueueRuntime()
    {
        _queueLoopTask ??= Task.Run(() => QueueLoopAsync(_queueCts.Token));
    }

    private async Task QueueLoopAsync(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(350));
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await timer.WaitForNextTickAsync(cancellationToken);
                await _dispatcher.EnqueueAsync(() =>
                {
                    var availableSlots = _performance.MaxQueueWorkers - _activeQueueIds.Count;
                    if (availableSlots <= 0)
                    {
                        return;
                    }
                    foreach (var item in Queue.Where(q => q.Status == PromptQueueStatus.Queued && !_activeQueueIds.Contains(q.Id)).Take(availableSlots).ToList())
                    {
                        _activeQueueIds.Add(item.Id);
                        _ = ProcessQueueItemAsync(item.Id, cancellationToken);
                    }
                });
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                AddSystemOutput($"Queue runtime error: {ex.Message}");
            }
        }
    }

    private async Task ProcessQueueItemAsync(string queueId, CancellationToken cancellationToken)
    {
        QueueRecord? queueRecord = null;
        await _dispatcher.EnqueueAsync(() =>
        {
            queueRecord = Queue.FirstOrDefault(q => q.Id == queueId);
            if (queueRecord is null)
            {
                _activeQueueIds.Remove(queueId);
                return;
            }
            queueRecord.Status = PromptQueueStatus.Running;
            queueRecord.StartedAt = DateTimeOffset.UtcNow;
            queueRecord.Progress = 0.12;
            queueRecord.CheckpointNote = "Model bootstrapping";
        });

        if (queueRecord is null)
        {
            return;
        }

        try
        {
            var prompt = queueRecord.Prompt;
            var notesContext = Notes.Take(4).ToList();

            var output = await _reasoning.ReasonAsync(
                prompt,
                notesContext,
                _performance,
                (progress, checkpoint) =>
                {
                    _ = _dispatcher.EnqueueAsync(() =>
                    {
                        var record = Queue.FirstOrDefault(q => q.Id == queueId);
                        if (record is null)
                        {
                            return;
                        }
                        record.Progress = progress;
                        record.CheckpointNote = checkpoint;
                    });
                },
                cancellationToken);

            await _dispatcher.EnqueueAsync(() =>
            {
                var record = Queue.FirstOrDefault(q => q.Id == queueId);
                if (record is null)
                {
                    return;
                }
                record.Status = PromptQueueStatus.Done;
                record.Progress = 1.0;
                record.CompletedAt = DateTimeOffset.UtcNow;
                record.CheckpointNote = "Completed";
                record.OutputSummary = output.Summary;
                record.NextAction = output.NextAction;
                record.Confidence = output.Confidence;
                record.ErrorMessage = null;

                if (Session.MemoryOptIn)
                {
                    Memory.Insert(0, new MemoryRecord
                    {
                        Type = "queue_output",
                        Source = "windows_local_model",
                        Weight = output.Confidence,
                        Recency = DateTimeOffset.UtcNow,
                        Tags = ["queue", "reasoning"],
                        Value = $"{output.Summary} | {output.NextAction}"
                    });
                    TrimMemory();
                }
                AddSystemOutput($"Queue complete: {record.Prompt[..Math.Min(record.Prompt.Length, 72)]}");
            });
        }
        catch (OperationCanceledException)
        {
            // expected on shutdown
        }
        catch (Exception ex)
        {
            await _dispatcher.EnqueueAsync(() =>
            {
                var record = Queue.FirstOrDefault(q => q.Id == queueId);
                if (record is null)
                {
                    return;
                }
                record.Status = PromptQueueStatus.Failed;
                record.Progress = 1.0;
                record.CompletedAt = DateTimeOffset.UtcNow;
                record.CheckpointNote = "Failed";
                record.ErrorMessage = ex.Message;
                AddSystemOutput($"Queue failed: {ex.Message}");
            });
        }
        finally
        {
            await _dispatcher.EnqueueAsync(() => _activeQueueIds.Remove(queueId));
            await RefreshExecutionAsync();
            await PersistAsync();
        }
    }

    private List<FeedItem> BuildExecutionFeed()
    {
        var feed = new List<FeedItem>();

        if (!CanAccessExecution)
        {
            feed.Add(new FeedItem
            {
                Title = "Complete adaptive survey",
                Summary = "Execution stream unlocks after full survey coverage.",
                WhyNow = "Deep personalization quality depends on complete baseline signals.",
                Priority = "high"
            });
            return feed;
        }

        if (!string.IsNullOrWhiteSpace(Session.DailyPriority))
        {
            feed.Add(new FeedItem
            {
                Title = "Execute daily priority",
                Summary = Session.DailyPriority,
                WhyNow = "Daily compounding is the strongest predictor of long-term outcomes.",
                Priority = "high"
            });
        }

        if (!Session.GymToday)
        {
            feed.Add(new FeedItem
            {
                Title = "Protect problem-solving biology",
                Summary = "Do 20-30 minutes of movement to sharpen cognition and emotional regulation.",
                WhyNow = "Executive function and stress control materially impact economic execution.",
                Priority = "high"
            });
        }

        if (!Session.MoneyToday)
        {
            feed.Add(new FeedItem
            {
                Title = "Run one direct income action now",
                Summary = "Choose one: outreach, offer refinement, or close-follow-up.",
                WhyNow = "Daily revenue contact improves weekly conversion odds.",
                Priority = "critical"
            });
        }

        foreach (var memory in Memory.Take(3))
        {
            feed.Add(new FeedItem
            {
                Title = "Memory-backed recommendation",
                Summary = memory.Value[..Math.Min(memory.Value.Length, 180)],
                WhyNow = "Generated from your long-term local memory graph.",
                Priority = memory.Weight >= 0.85 ? "high" : "normal"
            });
        }

        if (feed.Count == 0)
        {
            feed.Add(new FeedItem
            {
                Title = "Begin your operating cycle",
                Summary = "Submit check-in, capture notes, and queue one prompt.",
                WhyNow = "Atlas can only orchestrate once baseline telemetry exists.",
                Priority = "normal"
            });
        }

        return feed.Take(10).ToList();
    }

    private List<string> BuildCheckinTags()
    {
        var tags = new List<string> { "checkin", Session.Mood.ToLowerInvariant() };
        tags.Add(Session.GymToday ? "gym_yes" : "gym_no");
        tags.Add(Session.MoneyToday ? "money_yes" : "money_no");
        return tags;
    }

    private void AddSystemOutput(string line)
    {
        if (!_dispatcher.HasThreadAccess)
        {
            _ = _dispatcher.EnqueueAsync(() => AddSystemOutput(line));
            return;
        }

        SystemOutput.Insert(0, new SystemLogLine
        {
            Text = line,
            CreatedAt = DateTimeOffset.UtcNow
        });
        while (SystemOutput.Count > 240)
        {
            SystemOutput.RemoveAt(SystemOutput.Count - 1);
        }
    }

    private void TrimMemory()
    {
        while (Memory.Count > 4000)
        {
            Memory.RemoveAt(Memory.Count - 1);
        }
    }

    private void TrimWorkspaces()
    {
        while (Workspaces.Count > 1200)
        {
            Workspaces.RemoveAt(Workspaces.Count - 1);
        }
    }

    private AtlasDataEnvelope ToEnvelope()
    {
        return new AtlasDataEnvelope
        {
            Session = CloneSession(),
            SystemOutput = SystemOutput.ToList(),
            Notes = Notes.ToList(),
            Queue = Queue.ToList(),
            Memory = Memory.ToList(),
            Workspaces = Workspaces.ToList(),
            SurveyAnswers = _surveyAnswers.Select(x => new SurveyAnswer { QuestionId = x.Key, Value = x.Value }).ToList(),
            LastSavedAt = DateTimeOffset.UtcNow
        };
    }

    private AtlasSessionState CloneSession()
    {
        return new AtlasSessionState
        {
            IsSignedIn = Session.IsSignedIn,
            Provider = Session.Provider,
            AccountLabel = Session.AccountLabel,
            Tier = Session.Tier,
            LanguageCode = Session.LanguageCode,
            DailyPriority = Session.DailyPriority,
            MidTermGoal = Session.MidTermGoal,
            LongTermVision = Session.LongTermVision,
            Blockers = Session.Blockers,
            Mood = Session.Mood,
            Energy = Session.Energy,
            GymToday = Session.GymToday,
            MoneyToday = Session.MoneyToday,
            MemoryOptIn = Session.MemoryOptIn
        };
    }

    private void HydrateFromEnvelope(AtlasDataEnvelope envelope)
    {
        Session.IsSignedIn = envelope.Session.IsSignedIn;
        Session.Provider = envelope.Session.Provider;
        Session.AccountLabel = envelope.Session.AccountLabel;
        Session.Tier = envelope.Session.Tier;
        Session.LanguageCode = envelope.Session.LanguageCode;
        Session.DailyPriority = envelope.Session.DailyPriority;
        Session.MidTermGoal = envelope.Session.MidTermGoal;
        Session.LongTermVision = envelope.Session.LongTermVision;
        Session.Blockers = envelope.Session.Blockers;
        Session.Mood = envelope.Session.Mood;
        Session.Energy = envelope.Session.Energy;
        Session.GymToday = envelope.Session.GymToday;
        Session.MoneyToday = envelope.Session.MoneyToday;
        Session.MemoryOptIn = envelope.Session.MemoryOptIn;

        SystemOutput.Clear();
        foreach (var line in envelope.SystemOutput.OrderByDescending(x => x.CreatedAt).Take(240))
        {
            SystemOutput.Add(line);
        }

        Notes.Clear();
        foreach (var note in envelope.Notes.OrderByDescending(x => x.CreatedAt).Take(2000))
        {
            Notes.Add(note);
        }

        Queue.Clear();
        foreach (var queue in envelope.Queue.OrderByDescending(x => x.CreatedAt).Take(400))
        {
            if (queue.Status == PromptQueueStatus.Running)
            {
                queue.Status = PromptQueueStatus.Queued;
                queue.Progress = 0.0;
                queue.CheckpointNote = "Recovered after app restart";
            }
            Queue.Add(queue);
        }

        Memory.Clear();
        foreach (var memory in envelope.Memory.OrderByDescending(x => x.Recency).Take(4000))
        {
            Memory.Add(memory);
        }

        Workspaces.Clear();
        foreach (var ws in envelope.Workspaces.OrderByDescending(x => x.UpdatedAt).Take(1200))
        {
            Workspaces.Add(ws);
        }

        _surveyAnswers.Clear();
        foreach (var answer in envelope.SurveyAnswers)
        {
            _surveyAnswers[answer.QuestionId] = answer.Value;
        }
    }

    private async Task PersistAsync()
    {
        AtlasDataEnvelope snapshot;
        if (_dispatcher.HasThreadAccess)
        {
            snapshot = ToEnvelope();
        }
        else
        {
            AtlasDataEnvelope? onUi = null;
            await _dispatcher.EnqueueAsync(() => onUi = ToEnvelope());
            snapshot = onUi ?? new AtlasDataEnvelope();
        }

        await _saveLock.WaitAsync();
        try
        {
            await _stateStore.SaveAsync(snapshot);
        }
        finally
        {
            _saveLock.Release();
        }
    }

    private static List<SurveyQuestion> BuildSurveyQuestions()
    {
        return
        [
            Question("income_mode", "How do you currently generate income?", "Define current economic baseline.",
                Choice("salary", "Salary"),
                Choice("business", "Business income"),
                Choice("mixed", "Both"),
                Choice("none", "Not yet")),
            Question("income_stability", "How stable is your income right now?", "Helps prioritize risk buffers.",
                Choice("stable", "Stable"),
                Choice("unstable", "Unstable"),
                Choice("volatile", "Highly volatile")),
            Question("work_mode", "Primary work style?", "Used for execution architecture.",
                Choice("employee", "Employee"),
                Choice("founder", "Founder / operator"),
                Choice("hybrid", "Hybrid")),
            Question("main_blocker", "Main blocker to higher income?", "Root-cause targeting.",
                Choice("skills", "Skills gap"),
                Choice("sales", "Sales/client pipeline"),
                Choice("consistency", "Execution consistency"),
                Choice("network", "Network/opportunity access")),
            Question("daily_focus_capacity", "How many focused hours/day can you protect?", "Drives realistic action load.",
                Choice("1", "1 hour"),
                Choice("2_3", "2-3 hours"),
                Choice("4_plus", "4+ hours")),
            Question("sleep_quality", "Sleep quality most nights?", "Critical to cognition and stress control.",
                Choice("poor", "Poor"),
                Choice("average", "Average"),
                Choice("good", "Good")),
            Question("movement_habit", "How often do you train or move intentionally?", "Cognitive performance factor.",
                Choice("rare", "Rarely"),
                Choice("few", "Few times/week"),
                Choice("daily", "Daily")),
            Question("stress_load", "Current stress load level?", "Sets resilience thresholds.",
                Choice("low", "Low"),
                Choice("medium", "Medium"),
                Choice("high", "High")),
            Question("travel_intensity", "How mobile is your lifestyle/work?", "Impacts travel design recommendations.",
                Choice("local", "Mostly local"),
                Choice("regional", "Regional travel"),
                Choice("heavy", "Heavy mobile lifestyle")),
            Question("annual_distance", "Estimated annual travel distance?", "Supports mobility operations planning.",
                Choice("lt20", "<20k km"),
                Choice("20_60", "20k-60k km"),
                Choice("gt60", ">60k km")),
            Question("risk_prep", "Emergency readiness level today?", "Continuity baseline.",
                Choice("low", "Low"),
                Choice("medium", "Medium"),
                Choice("high", "High")),
            Question("comms_redundancy", "Do you have redundant communications?", "Safety and uptime factor.",
                Choice("none", "No"),
                Choice("partial", "Partial"),
                Choice("full", "Yes")),
            Question("power_redundancy", "Do you have backup power strategy?", "Field operations continuity.",
                Choice("none", "No"),
                Choice("basic", "Basic"),
                Choice("robust", "Robust")),
            Question("career_goal", "Next 12-month target?", "Used for roadmap generation.",
                Choice("promotion", "Promotion"),
                Choice("higher_pay", "Higher-paying role"),
                Choice("business_growth", "Business growth"),
                Choice("new_business", "Start a business")),
            Question("industry_track", "Primary industry track?", "Loads relevant income ladders.",
                Choice("ai_software", "AI / Software"),
                Choice("sales", "Sales"),
                Choice("finance", "Finance"),
                Choice("trades", "Skilled trades"),
                Choice("healthcare", "Healthcare"),
                Choice("logistics", "Logistics"),
                Choice("real_estate", "Real estate"),
                Choice("media", "Media")),
            Question("offer_positioning", "Can you articulate your offer/value in 1 sentence?", "Sales readiness measure.",
                Choice("yes", "Yes"),
                Choice("partial", "Partially"),
                Choice("no", "No")),
            Question("pipeline_quality", "Current client/job pipeline health?", "Near-term income signal.",
                Choice("empty", "Empty"),
                Choice("weak", "Weak"),
                Choice("solid", "Solid")),
            Question("tooling", "Current tooling maturity?", "Execution system maturity.",
                Choice("manual", "Mostly manual"),
                Choice("mixed", "Mixed"),
                Choice("automated", "Automated")),
            Question("learning_mode", "Preferred learning mode?", "Shapes adaptive learning outputs.",
                Choice("briefs", "Executive briefs"),
                Choice("checklists", "Checklists"),
                Choice("audio", "Audio/podcast"),
                Choice("interactive", "Interactive exercises")),
            Question("language_pref", "Primary operating language?", "Localization preference.",
                Choice("en", "English"),
                Choice("he", "Hebrew"),
                Choice("mixed", "Mixed")),
            Question("charity_goal", "Include a giving target in planning?", "Values alignment signal.",
                Choice("yes", "Yes"),
                Choice("later", "Later"),
                Choice("no", "No")),
            Question("feedback_optin", "Allow anonymized product feedback suggestions?", "Team improvement loop control.",
                Choice("yes", "Yes"),
                Choice("ask_each", "Ask each time"),
                Choice("no", "No")),
            Question("cloud_tier_interest", "Interested in future cloud compute tier?", "Upgrade readiness.",
                Choice("yes", "Yes"),
                Choice("maybe", "Maybe"),
                Choice("no", "No")),
            Question("execution_commitment", "Can you commit to one daily action cadence?", "Final readiness gate.",
                Choice("yes", "Yes, daily"),
                Choice("weekly", "Weekly only"),
                Choice("not_ready", "Not ready")),
        ];
    }

    private static SurveyQuestion Question(string id, string title, string description, params SurveyChoice[] choices)
    {
        return new SurveyQuestion
        {
            Id = id,
            Title = title,
            Description = description,
            Choices = choices.ToList()
        };
    }

    private static SurveyChoice Choice(string value, string label) => new() { Value = value, Label = label };

    public async ValueTask DisposeAsync()
    {
        _queueCts.Cancel();
        if (_queueLoopTask is not null)
        {
            try
            {
                await _queueLoopTask;
            }
            catch
            {
                // ignored on shutdown
            }
        }
        await PersistOnExitAsync();
        _queueCts.Dispose();
        _saveLock.Dispose();
    }
}
