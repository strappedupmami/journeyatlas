using AtlasMasaWindows.Infrastructure;
using AtlasMasaWindows.Models;
using AtlasMasaWindows.Services;
using Microsoft.UI.Dispatching;
using System.Collections.ObjectModel;
using System.Net;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace AtlasMasaWindows.ViewModels;

public sealed class MainViewModel : ObservableObject, IAsyncDisposable
{
    private const string HostedWorldMonitorUrl = "https://worldmonitor.app";
    private const string LocalWorldMonitorUrl = "http://127.0.0.1:5173";
    private static readonly TimeSpan AdaptiveRuntimeLoopInterval = TimeSpan.FromSeconds(45);
    private static readonly TimeSpan AdaptiveQuestionCadence = TimeSpan.FromMinutes(3);
    private static readonly TimeSpan BusinessAutopilotCadence = TimeSpan.FromMinutes(4);
    private static readonly TimeSpan NatureSignalRefreshCadence = TimeSpan.FromMinutes(20);
    private static readonly TimeSpan NatureAlertNotificationCooldown = TimeSpan.FromMinutes(90);
    private static readonly TimeSpan WealthReminderNotificationCadence = TimeSpan.FromHours(4);
    private const int AuthSessionProbeRetryAttempts = 6;
    private static readonly TimeSpan AuthSessionProbeRetryDelay = TimeSpan.FromMilliseconds(350);
    private const int AdaptiveQuestionHistoryCap = 24;
    private const int AdaptiveQuestionPendingCap = 3;

    private readonly DispatcherQueue _dispatcher;
    private readonly AppStateStore _stateStore;
    private readonly LocalReasoningEngine _reasoning;
    private readonly OnDeviceLlmClient _llmClient;
    private readonly AcademicResearchService _academicResearch;
    private readonly LocalSyncBlueprintService _localSyncBlueprint;
    private readonly RecoverySupportService _recoverySupport;
    private readonly QuantumLearningPlanner _quantumPlanner;
    private readonly AuthBrowserFlowService _authBrowserFlow;
    private readonly NatureSignalMonitorService _natureSignalMonitor;
    private readonly DesktopNotificationService _notifications;
    private readonly SystemPerformanceProfile _performance;
    private AtlasApiClient _apiClient;
    private readonly HttpClient _youtubeHttpClient = new() { Timeout = TimeSpan.FromSeconds(16) };
    private List<AuthCookieRecord> _persistedAuthCookies = [];
    private readonly SemaphoreSlim _saveLock = new(1, 1);
    private readonly HashSet<string> _activeQueueIds = [];
    private readonly Dictionary<string, string> _surveyAnswers = [];
    private readonly List<SurveyQuestion> _surveyQuestions;
    private readonly CancellationTokenSource _queueCts = new();
    private readonly SemaphoreSlim _adaptiveRuntimeLock = new(1, 1);
    private Task? _queueLoopTask;
    private bool _isInitialized;
    private int _surveyQuestionIndex;
    private string _newPrompt = string.Empty;
    private string _newNoteTitle = string.Empty;
    private string _newNoteContent = string.Empty;
    private string _newWorkspaceTitle = string.Empty;
    private string _newWorkspaceSummary = string.Empty;
    private string _backendApiBaseDraft = AtlasBackendConfig.DefaultApiBase;
    private string _worldMonitorUrlDraft = HostedWorldMonitorUrl;
    private Uri _worldMonitorUri = new(HostedWorldMonitorUrl);
    private string _worldMonitorStatusLine = "World Monitor hosted endpoint active.";
    private SurveyQuestion? _currentSurveyQuestion;
    private string _surveyProgressText = "0 / 0";
    private bool _isSurveyCompleted;
    private bool _canAccessExecution;
    private string _selectedSurveyAnswerLabel = string.Empty;
    private readonly HashSet<string> _surveyMultiSelections = [];
    private string? _activeSurveyMultiQuestionId;
    private readonly HashSet<string> _adaptiveSelectedOptions = [];
    private string _adaptiveFreeformResponseDraft = string.Empty;
    private string? _adaptiveDraftQuestionId;
    private string _codePromptDraft = string.Empty;
    private string _selectedCodeAgentMode = "auto";
    private bool _showClassicCodeTools;
    private string _classicCodeScratchpad = string.Empty;
    private string _classicCodeCommandDraft = "git status";
    private string _classicCodeCommandOutput = "Classic tools are hidden by default.";
    private bool _isClassicCodeCommandRunning;
    private bool _isAuthFlowInProgress;
    private string _authFlowStatusLine = "Signed out.";
    private DateTimeOffset _lastAdaptiveRuntimeHeartbeatUtc = DateTimeOffset.MinValue;
    private DateTimeOffset _lastNatureSignalRefreshAtUtc = DateTimeOffset.MinValue;
    private DateTimeOffset _lastNatureAlertNotificationAtUtc = DateTimeOffset.MinValue;
    private DateTimeOffset _lastWealthReminderNotificationAtUtc = DateTimeOffset.MinValue;
    private int _natureRiskScore;
    private string _natureRiskBand = "low";
    private string _natureAlertSummary = "Nature signal stack pending first refresh.";
    private int _natureElevatedThreshold = 45;
    private int _natureCriticalThreshold = 70;

    public AtlasSessionState Session { get; } = new();
    public ObservableCollection<SystemLogLine> SystemOutput { get; } = [];
    public ObservableCollection<NoteRecord> Notes { get; } = [];
    public ObservableCollection<QueueRecord> Queue { get; } = [];
    public ObservableCollection<MemoryRecord> Memory { get; } = [];
    public ObservableCollection<WorkspaceSession> Workspaces { get; } = [];
    public ObservableCollection<FeedItem> ExecutionFeed { get; } = [];
    public ObservableCollection<SurveyChoice> CurrentSurveyChoices { get; } = [];
    public ObservableCollection<AdaptiveBusinessQuestion> AdaptiveBusinessQuestions { get; } = [];
    public ObservableCollection<NatureSignalTile> NatureSignalTiles { get; } = [];

    public string AppTitle => "Atlas Travel Design OS - Windows";
    public string PerformanceSummary => $"Mode: {_performance.Label} | Cores: {_performance.CpuCores} | RAM≈{_performance.PhysicalMemoryGb}GB | Queue workers: {_performance.MaxQueueWorkers} | LLM: {_llmClient.RuntimeModel}";

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

    public string BackendApiBaseDraft
    {
        get => _backendApiBaseDraft;
        set
        {
            if (SetProperty(ref _backendApiBaseDraft, value))
            {
                SaveBackendConfigCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public string WorldMonitorUrlDraft
    {
        get => _worldMonitorUrlDraft;
        set
        {
            if (SetProperty(ref _worldMonitorUrlDraft, value))
            {
                ApplyWorldMonitorUrlCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public Uri WorldMonitorUri
    {
        get => _worldMonitorUri;
        private set => SetProperty(ref _worldMonitorUri, value);
    }

    public string WorldMonitorStatusLine
    {
        get => _worldMonitorStatusLine;
        private set => SetProperty(ref _worldMonitorStatusLine, value);
    }

    public int NatureRiskScore
    {
        get => _natureRiskScore;
        private set
        {
            if (SetProperty(ref _natureRiskScore, Math.Clamp(value, 0, 100)))
            {
                RaisePropertyChanged(nameof(NatureRiskLine));
            }
        }
    }

    public string NatureRiskBand
    {
        get => _natureRiskBand;
        private set
        {
            if (SetProperty(ref _natureRiskBand, value))
            {
                RaisePropertyChanged(nameof(NatureRiskLine));
            }
        }
    }

    public string NatureAlertSummary
    {
        get => _natureAlertSummary;
        private set => SetProperty(ref _natureAlertSummary, value);
    }

    public int NatureElevatedThreshold
    {
        get => _natureElevatedThreshold;
        private set
        {
            if (SetProperty(ref _natureElevatedThreshold, Math.Clamp(value, 20, 95)))
            {
                RaisePropertyChanged(nameof(NatureThresholdLine));
            }
        }
    }

    public int NatureCriticalThreshold
    {
        get => _natureCriticalThreshold;
        private set
        {
            if (SetProperty(ref _natureCriticalThreshold, Math.Clamp(value, 25, 99)))
            {
                RaisePropertyChanged(nameof(NatureThresholdLine));
            }
        }
    }

    public string NatureThresholdLine => $"Alert thresholds: elevated >= {NatureElevatedThreshold}, critical >= {NatureCriticalThreshold}";
    public string NatureRiskLine => $"Nature risk: {NatureRiskScore}/100 ({NatureRiskBand})";

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

    public bool IsCurrentSurveyQuestionMulti =>
        string.Equals(CurrentSurveyQuestion?.Kind, "multi_choice", StringComparison.OrdinalIgnoreCase);

    public string SurveyMultiSelectionLine => _surveyMultiSelections.Count == 0
        ? "Select one or more options, then continue."
        : $"Selected: {string.Join(", ", ResolveSurveyChoiceLabels(CurrentSurveyQuestion, _surveyMultiSelections))}";

    public AdaptiveBusinessQuestion? PendingAdaptiveBusinessQuestion => AdaptiveBusinessQuestions.FirstOrDefault(question => question.Response is null);

    public int AnsweredAdaptiveBusinessQuestionCount => AdaptiveBusinessQuestions.Count(question => question.Response is not null);

    public string AdaptiveQuestionProgressLine => $"Answered: {AnsweredAdaptiveBusinessQuestionCount} · Pending: {AdaptiveBusinessQuestions.Count(question => question.Response is null)}";

    public string AdaptiveSelectedOptionsLine => _adaptiveSelectedOptions.Count == 0
        ? "Selected options: none yet."
        : $"Selected options: {string.Join(", ", _adaptiveSelectedOptions.OrderBy(item => item))}";

    public string AdaptiveFreeformResponseDraft
    {
        get => _adaptiveFreeformResponseDraft;
        set
        {
            if (SetProperty(ref _adaptiveFreeformResponseDraft, value))
            {
                SubmitAdaptiveQuestionResponseCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public string CodePromptDraft
    {
        get => _codePromptDraft;
        set
        {
            if (SetProperty(ref _codePromptDraft, value))
            {
                RunCodeAgentTaskCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public string SelectedCodeAgentMode
    {
        get => _selectedCodeAgentMode;
        set => SetProperty(ref _selectedCodeAgentMode, value);
    }

    public bool ShowClassicCodeTools
    {
        get => _showClassicCodeTools;
        set => SetProperty(ref _showClassicCodeTools, value);
    }

    public string ClassicCodeScratchpad
    {
        get => _classicCodeScratchpad;
        set => SetProperty(ref _classicCodeScratchpad, value);
    }

    public string ClassicCodeCommandDraft
    {
        get => _classicCodeCommandDraft;
        set
        {
            if (SetProperty(ref _classicCodeCommandDraft, value))
            {
                RunClassicCodeCommandCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public string ClassicCodeCommandOutput
    {
        get => _classicCodeCommandOutput;
        private set => SetProperty(ref _classicCodeCommandOutput, value);
    }

    public bool IsClassicCodeCommandRunning
    {
        get => _isClassicCodeCommandRunning;
        private set
        {
            if (SetProperty(ref _isClassicCodeCommandRunning, value))
            {
                RunClassicCodeCommandCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public string AuthFlowStatusLine
    {
        get => _authFlowStatusLine;
        private set => SetProperty(ref _authFlowStatusLine, value);
    }

    public AsyncRelayCommand SubmitCheckInCommand { get; }
    public AsyncRelayCommand AddNoteCommand { get; }
    public AsyncRelayCommand EnqueuePromptCommand { get; }
    public AsyncRelayCommand RunCodeAgentTaskCommand { get; }
    public AsyncRelayCommand RunClassicCodeCommandCommand { get; }
    public AsyncRelayCommand RefreshExecutionCommand { get; }
    public AsyncRelayCommand AddWorkspaceSessionCommand { get; }
    public AsyncRelayCommand SignInAppleCommand { get; }
    public AsyncRelayCommand SignInGoogleCommand { get; }
    public AsyncRelayCommand SignInPasskeyCommand { get; }
    public AsyncRelayCommand SignUpPasskeyCommand { get; }
    public AsyncRelayCommand SignOutCommand { get; }
    public AsyncRelayCommand SaveBackendConfigCommand { get; }
    public AsyncRelayCommand ApplyWorldMonitorUrlCommand { get; }
    public AsyncRelayCommand UseHostedWorldMonitorCommand { get; }
    public AsyncRelayCommand UseLocalWorldMonitorCommand { get; }
    public AsyncRelayCommand ToggleLanguageCommand { get; }
    public RelayCommand<SurveyChoice> AnswerSurveyChoiceCommand { get; }
    public AsyncRelayCommand ActivateGuidedLearningCommand { get; }
    public AsyncRelayCommand SubmitSurveyMultiChoiceCommand { get; }
    public AsyncRelayCommand SaveAdaptiveRuntimeSettingsCommand { get; }
    public AsyncRelayCommand RequestAdaptiveQuestionNowCommand { get; }
    public AsyncRelayCommand SubmitAdaptiveQuestionResponseCommand { get; }
    public AsyncRelayCommand RefreshNatureSignalStackCommand { get; }

    public MainViewModel(DispatcherQueue dispatcherQueue)
    {
        _dispatcher = dispatcherQueue;
        _stateStore = new AppStateStore();
        _reasoning = new LocalReasoningEngine();
        _performance = SystemPerformanceProfile.Detect();
        _llmClient = new OnDeviceLlmClient(_performance);
        _academicResearch = new AcademicResearchService();
        _localSyncBlueprint = new LocalSyncBlueprintService();
        _recoverySupport = new RecoverySupportService();
        _quantumPlanner = new QuantumLearningPlanner();
        _authBrowserFlow = new AuthBrowserFlowService();
        _natureSignalMonitor = new NatureSignalMonitorService();
        _notifications = new DesktopNotificationService();
        _notifications.EnsureRegistered();
        _apiClient = new AtlasApiClient(AtlasBackendConfig.DefaultApiBase);
        _surveyQuestions = BuildSurveyQuestions();
        AdaptiveBusinessQuestions.CollectionChanged += (_, _) => NotifyAdaptiveQuestionStateChanged();

        SubmitCheckInCommand = new AsyncRelayCommand(SubmitCheckInAsync);
        AddNoteCommand = new AsyncRelayCommand(AddNoteAsync, () => !string.IsNullOrWhiteSpace(NewNoteContent));
        EnqueuePromptCommand = new AsyncRelayCommand(EnqueuePromptAsync, () => !string.IsNullOrWhiteSpace(NewPrompt));
        RunCodeAgentTaskCommand = new AsyncRelayCommand(RunCodeAgentTaskAsync, () => !string.IsNullOrWhiteSpace(CodePromptDraft));
        RunClassicCodeCommandCommand = new AsyncRelayCommand(
            RunClassicCodeCommandAsync,
            () => !string.IsNullOrWhiteSpace(ClassicCodeCommandDraft) && !IsClassicCodeCommandRunning
        );
        RefreshExecutionCommand = new AsyncRelayCommand(RefreshExecutionAsync);
        AddWorkspaceSessionCommand = new AsyncRelayCommand(AddWorkspaceSessionAsync, () => !string.IsNullOrWhiteSpace(NewWorkspaceTitle));
        SignInAppleCommand = new AsyncRelayCommand(() => RunInteractiveAuthAsync(AuthBrowserAction.AppleSignIn), () => !_isAuthFlowInProgress);
        SignInGoogleCommand = new AsyncRelayCommand(() => RunInteractiveAuthAsync(AuthBrowserAction.GoogleSignIn), () => !_isAuthFlowInProgress);
        SignInPasskeyCommand = new AsyncRelayCommand(() => RunInteractiveAuthAsync(AuthBrowserAction.PasskeySignIn), () => !_isAuthFlowInProgress);
        SignUpPasskeyCommand = new AsyncRelayCommand(() => RunInteractiveAuthAsync(AuthBrowserAction.PasskeySignUp), () => !_isAuthFlowInProgress);
        SignOutCommand = new AsyncRelayCommand(SignOutAsync, () => !_isAuthFlowInProgress);
        SaveBackendConfigCommand = new AsyncRelayCommand(SaveBackendConfigAsync, () => !string.IsNullOrWhiteSpace(BackendApiBaseDraft));
        ApplyWorldMonitorUrlCommand = new AsyncRelayCommand(ApplyWorldMonitorUrlAsync, () => !string.IsNullOrWhiteSpace(WorldMonitorUrlDraft));
        UseHostedWorldMonitorCommand = new AsyncRelayCommand(() => SetWorldMonitorEndpointAsync(HostedWorldMonitorUrl, "World Monitor switched to hosted endpoint."));
        UseLocalWorldMonitorCommand = new AsyncRelayCommand(() => SetWorldMonitorEndpointAsync(LocalWorldMonitorUrl, "World Monitor switched to local dev endpoint. Run npm run dev in worldmonitor-main."));
        ToggleLanguageCommand = new AsyncRelayCommand(ToggleLanguageAsync);
        ActivateGuidedLearningCommand = new AsyncRelayCommand(ActivateGuidedLearningAfterSurveyAsync, () => IsSurveyCompleted && !Session.GuidedLearningRuntimeActive);
        SubmitSurveyMultiChoiceCommand = new AsyncRelayCommand(SubmitSurveyMultiChoiceAsync, CanSubmitSurveyMultiChoice);
        SaveAdaptiveRuntimeSettingsCommand = new AsyncRelayCommand(SaveAdaptiveRuntimeSettingsAsync);
        RequestAdaptiveQuestionNowCommand = new AsyncRelayCommand(RequestAdaptiveQuestionNowAsync, () => Session.GuidedLearningRuntimeActive);
        SubmitAdaptiveQuestionResponseCommand = new AsyncRelayCommand(SubmitAdaptiveQuestionResponseAsync, () => CanSubmitAdaptiveQuestionResponse());
        RefreshNatureSignalStackCommand = new AsyncRelayCommand(() => RefreshNatureSignalStackAsync(sendAlertNotifications: true));
        AnswerSurveyChoiceCommand = new RelayCommand<SurveyChoice>(choice =>
        {
            if (choice is not null && !IsCurrentSurveyQuestionMulti)
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
        Session.ApiBaseUrl = AtlasBackendConfig.ResolveStartupApiBase(Session.ApiBaseUrl);
        BackendApiBaseDraft = Session.ApiBaseUrl;
        InitializeWorldMonitorEndpoint();
        RebuildApiClient(_persistedAuthCookies);
        AddSystemOutput("Atlas Windows local core booted.");
        AddSystemOutput(PerformanceSummary);
        AddSystemOutput($"Shared backend target: {_apiClient.BaseUrl}");
        AddSystemOutput(await _apiClient.HealthStatusLineAsync());
        await RestoreAuthSessionAsync();
        AddSystemOutput(_llmClient.StatusLine);
        AddSystemOutput(_llmClient.RuntimePolicyStatus);
        AddSystemOutput("Academic discovery mode ready: OpenAlex search + abstract scoring + DOI/PDF linking.");
        AddSystemOutput("Local sync blueprint mode ready: USB-C/LAN discovery + mTLS pairing workflow.");
        AddSystemOutput("Recovery support mode ready: long-term relapse prevention guardrails.");
        AddSystemOutput($"Active memory management: {ResolveActiveMemoryDepth()} (ATLAS_MEMORY_DEPTH=lean|balanced|deep).");
        AddSystemOutput(_reasoning.RuntimeStatusLine);
        AddSystemOutput("Prompt queue is resumable and survives app restart.");
        AddSystemOutput($"World Monitor endpoint: {WorldMonitorUri}");
        AddSystemOutput(NatureThresholdLine);
        RefreshSurveyCursor();
        NotifyAdaptiveQuestionStateChanged();
        await RefreshQuantumLearningSnapshotFromCurrentStateAsync("startup");
        AddSystemOutput(Session.QuantumLearningStatusLine);
        await RefreshNatureSignalStackAsync(sendAlertNotifications: false);
        await RefreshExecutionAsync();
        StartQueueRuntime();
        await RunAdaptiveBusinessRuntimeTickAsync("startup", forceQuestion: false, forceAutopilot: false, _queueCts.Token);
        await PersistAsync();
    }

    public async Task PersistOnExitAsync()
    {
        await PersistAsync();
    }

    private async Task RunInteractiveAuthAsync(AuthBrowserAction action)
    {
        if (_isAuthFlowInProgress)
        {
            return;
        }

        SetAuthFlowInProgress(true);
        try
        {
            var authPortalUri = BuildAuthPortalUri(action);
            var apiBaseUri = new Uri(Session.ApiBaseUrl, UriKind.Absolute);
            AuthFlowStatusLine = "Waiting for secure authentication...";
            AddSystemOutput($"Opening secure auth window via {_apiClient.Host}.");

            var browserResult = await _authBrowserFlow.RunAsync(authPortalUri, apiBaseUri, action, _queueCts.Token);
            if (browserResult.WasCancelled)
            {
                AuthFlowStatusLine = "Authentication cancelled.";
                AddSystemOutput(browserResult.StatusMessage);
                return;
            }
            if (!browserResult.IsAuthenticated)
            {
                AuthFlowStatusLine = "Authentication failed.";
                AddSystemOutput(browserResult.StatusMessage);
                return;
            }

            _persistedAuthCookies = browserResult.Cookies.ToList();
            RebuildApiClient(_persistedAuthCookies);
            var probe = await ProbeAuthSessionWithRetryAsync(_queueCts.Token);
            if (probe.State == AtlasApiClient.AuthProbeState.Unreachable)
            {
                AuthFlowStatusLine = "Authentication completed. Waiting for server verification.";
                AddSystemOutput("Auth completed in secure browser, but backend verification is temporarily unreachable. Session cookies were saved and will retry automatically.");
                await PersistAsync();
                return;
            }

            if (probe.State != AtlasApiClient.AuthProbeState.Authenticated || probe.User is null)
            {
                ResetToGuestAuthState();
                _persistedAuthCookies = [];
                RebuildApiClient();
                AuthFlowStatusLine = "Authentication did not complete in app session.";
                AddSystemOutput("Auth completed in browser, but app session verification failed.");
                await PersistAsync();
                return;
            }

            ApplyRemoteAuthSession(
                probe.User,
                fallbackProvider: action switch
                {
                    AuthBrowserAction.AppleSignIn => AuthProvider.Apple,
                    AuthBrowserAction.GoogleSignIn => AuthProvider.Google,
                    _ => AuthProvider.Passkey
                });
            AuthFlowStatusLine = $"Signed in as {Session.AccountLabel}.";
            AddSystemOutput(browserResult.StatusMessage);
            await PersistAsync();
        }
        catch (OperationCanceledException)
        {
            AuthFlowStatusLine = "Authentication cancelled.";
            AddSystemOutput("Authentication flow was cancelled.");
        }
        catch (Exception ex)
        {
            AuthFlowStatusLine = "Authentication failed.";
            AddSystemOutput($"Authentication flow error: {ex.Message}");
        }
        finally
        {
            SetAuthFlowInProgress(false);
        }
    }

    private async Task SignOutAsync()
    {
        if (_isAuthFlowInProgress)
        {
            return;
        }

        await _apiClient.LogoutAsync();
        ResetToGuestAuthState();
        _persistedAuthCookies = [];
        RebuildApiClient();
        AuthFlowStatusLine = "Signed out.";
        AddSystemOutput("Signed out. Local data remains on this device unless manually cleared. Shared backend session cleared if available.");
        await PersistAsync();
    }

    private async Task SaveBackendConfigAsync()
    {
        var previous = Session.ApiBaseUrl;
        var sanitized = AtlasBackendConfig.SanitizeApiBase(BackendApiBaseDraft);
        BackendApiBaseDraft = sanitized;
        Session.ApiBaseUrl = sanitized;
        var backendChanged = !string.Equals(previous, sanitized, StringComparison.OrdinalIgnoreCase);
        if (backendChanged)
        {
            _persistedAuthCookies = [];
            ResetToGuestAuthState();
            AuthFlowStatusLine = "Backend changed. Sign in again.";
        }
        RebuildApiClient();
        AddSystemOutput($"Shared backend updated: {sanitized}");
        AddSystemOutput(await _apiClient.HealthStatusLineAsync());
        await PersistAsync();
    }

    private void InitializeWorldMonitorEndpoint()
    {
        var candidate = string.IsNullOrWhiteSpace(Session.WorldMonitorUrl)
            ? HostedWorldMonitorUrl
            : Session.WorldMonitorUrl;
        if (!TryBuildWorldMonitorUri(candidate, out var normalized, out var uri))
        {
            normalized = HostedWorldMonitorUrl;
            uri = new Uri(normalized);
        }

        Session.WorldMonitorUrl = normalized;
        WorldMonitorUrlDraft = normalized;
        WorldMonitorUri = uri;
        WorldMonitorStatusLine = IsLocalWorldMonitorEndpoint(normalized)
            ? "Local World Monitor endpoint active. Start worldmonitor-main with npm run dev."
            : "World Monitor hosted endpoint active.";
    }

    private async Task ApplyWorldMonitorUrlAsync()
    {
        if (!TryBuildWorldMonitorUri(WorldMonitorUrlDraft, out var normalized, out _))
        {
            WorldMonitorStatusLine = "Invalid URL. Use an http:// or https:// endpoint.";
            AddSystemOutput("World Monitor URL rejected: invalid format.");
            return;
        }

        await SetWorldMonitorEndpointAsync(normalized, $"World Monitor endpoint updated: {normalized}");
    }

    private async Task SetWorldMonitorEndpointAsync(string rawUrl, string statusMessage)
    {
        if (!TryBuildWorldMonitorUri(rawUrl, out var normalized, out var uri))
        {
            WorldMonitorStatusLine = "Invalid URL. Use an http:// or https:// endpoint.";
            AddSystemOutput("World Monitor URL rejected: invalid format.");
            return;
        }

        Session.WorldMonitorUrl = normalized;
        WorldMonitorUrlDraft = normalized;
        WorldMonitorUri = uri;
        WorldMonitorStatusLine = statusMessage;
        AddSystemOutput(statusMessage);
        await PersistAsync();
    }

    private static bool TryBuildWorldMonitorUri(string? rawInput, out string normalized, out Uri uri)
    {
        normalized = HostedWorldMonitorUrl;
        uri = new Uri(HostedWorldMonitorUrl);

        var trimmed = (rawInput ?? string.Empty).Trim();
        if (trimmed.Length == 0)
        {
            return false;
        }

        if (!trimmed.Contains("://", StringComparison.Ordinal))
        {
            trimmed = $"https://{trimmed}";
        }

        if (!Uri.TryCreate(trimmed, UriKind.Absolute, out var parsed))
        {
            return false;
        }

        if (parsed.Scheme != Uri.UriSchemeHttp && parsed.Scheme != Uri.UriSchemeHttps)
        {
            return false;
        }

        normalized = parsed.ToString();
        uri = parsed;
        return true;
    }

    private static bool IsLocalWorldMonitorEndpoint(string? url)
    {
        var normalized = (url ?? string.Empty).ToLowerInvariant();
        return normalized.Contains("localhost", StringComparison.Ordinal)
            || normalized.Contains("127.0.0.1", StringComparison.Ordinal);
    }

    private async Task RefreshNatureSignalStackAsync(
        bool sendAlertNotifications,
        CancellationToken cancellationToken = default)
    {
        NatureSignalSnapshot snapshot;
        try
        {
            snapshot = await _natureSignalMonitor.CaptureSnapshotAsync(
                elevatedThreshold: NatureElevatedThreshold,
                criticalThreshold: NatureCriticalThreshold,
                cancellationToken: cancellationToken);
        }
        catch (Exception ex)
        {
            AddSystemOutput($"Nature Signal Stack refresh failed: {ex.Message}");
            return;
        }

        _lastNatureSignalRefreshAtUtc = snapshot.RefreshedAt;
        Session.LastNatureSignalRefreshAtUtc = snapshot.RefreshedAt;
        Session.NatureRiskScore = snapshot.RiskScore;
        Session.NatureRiskBand = snapshot.RiskBand;
        Session.NatureAlertSummary = snapshot.AlertSummary;

        await _dispatcher.EnqueueAsync(() =>
        {
            NatureSignalTiles.Clear();
            foreach (var tile in snapshot.Tiles.Take(5))
            {
                NatureSignalTiles.Add(tile);
            }
            NatureRiskScore = snapshot.RiskScore;
            NatureRiskBand = snapshot.RiskBand;
            NatureAlertSummary = snapshot.AlertSummary;
        });

        AddSystemOutput($"Nature Signal Stack v2 refreshed: {NatureRiskLine}.");

        if (sendAlertNotifications)
        {
            TriggerNatureRiskNotificationIfNeeded(snapshot);
            TriggerWealthExecutionReminderIfNeeded(snapshot);
        }
    }

    private void TriggerNatureRiskNotificationIfNeeded(NatureSignalSnapshot snapshot)
    {
        if (snapshot.RiskScore < NatureElevatedThreshold)
        {
            return;
        }

        var now = DateTimeOffset.UtcNow;
        if (now - _lastNatureAlertNotificationAtUtc < NatureAlertNotificationCooldown)
        {
            return;
        }

        _lastNatureAlertNotificationAtUtc = now;
        Session.LastNatureAlertNotificationAtUtc = now;
        var title = snapshot.RiskScore >= NatureCriticalThreshold
            ? "Atlas Nature Alert: Critical"
            : "Atlas Nature Alert: Elevated";
        var body = $"{snapshot.AlertSummary} Keep execution momentum so donation capacity for frontline climate and biodiversity orgs keeps rising.";
        _notifications.Show(title, body);
        AddSystemOutput($"Desktop alert sent: {title}.");
    }

    private void TriggerWealthExecutionReminderIfNeeded(NatureSignalSnapshot snapshot)
    {
        var reminders = new List<string>();
        if (string.IsNullOrWhiteSpace(Session.DailyPriority))
        {
            reminders.Add("set your daily priority");
        }
        if (!Session.MoneyToday)
        {
            reminders.Add("run one direct income action");
        }
        if (!string.IsNullOrWhiteSpace(Session.Blockers))
        {
            reminders.Add("clear one major blocker");
        }
        if (reminders.Count == 0)
        {
            return;
        }

        var now = DateTimeOffset.UtcNow;
        if (now - _lastWealthReminderNotificationAtUtc < WealthReminderNotificationCadence)
        {
            return;
        }

        _lastWealthReminderNotificationAtUtc = now;
        Session.LastWealthReminderNotificationAtUtc = now;
        var reminder = $"Action needed: {string.Join(", ", reminders)}. Build compounding income so you can increase donations when nature risk is {snapshot.RiskBand}.";
        _notifications.Show("Atlas Wealth Execution Reminder", reminder);
        AddSystemOutput("Desktop alert sent: Atlas Wealth Execution Reminder.");
    }

    private void SetAuthFlowInProgress(bool isRunning)
    {
        if (_isAuthFlowInProgress == isRunning)
        {
            return;
        }

        _isAuthFlowInProgress = isRunning;
        SignInAppleCommand.NotifyCanExecuteChanged();
        SignInGoogleCommand.NotifyCanExecuteChanged();
        SignInPasskeyCommand.NotifyCanExecuteChanged();
        SignUpPasskeyCommand.NotifyCanExecuteChanged();
        SignOutCommand.NotifyCanExecuteChanged();
    }

    private void RebuildApiClient(IEnumerable<AuthCookieRecord>? cookies = null)
    {
        _apiClient = new AtlasApiClient(Session.ApiBaseUrl, cookies);
    }

    private async Task RestoreAuthSessionAsync()
    {
        var probe = await ProbeAuthSessionWithRetryAsync();
        switch (probe.State)
        {
            case AtlasApiClient.AuthProbeState.Authenticated when probe.User is not null:
                ApplyRemoteAuthSession(probe.User, AuthProvider.Passkey);
                AuthFlowStatusLine = $"Signed in as {Session.AccountLabel}.";
                AddSystemOutput($"Restored account session for {Session.AccountLabel}.");
                break;

            case AtlasApiClient.AuthProbeState.Unauthenticated:
                if (Session.IsSignedIn || _persistedAuthCookies.Count > 0)
                {
                    ResetToGuestAuthState();
                    _persistedAuthCookies = [];
                    RebuildApiClient();
                    AddSystemOutput("Saved auth session expired. Sign in again to restore account sync.");
                }
                AuthFlowStatusLine = "Signed out.";
                break;

            case AtlasApiClient.AuthProbeState.Unreachable:
                if (Session.IsSignedIn)
                {
                    AuthFlowStatusLine = "Auth server unreachable. Using cached account state.";
                    AddSystemOutput("Auth service unreachable. Keeping cached account state until connectivity returns.");
                }
                else if (_persistedAuthCookies.Count > 0)
                {
                    AuthFlowStatusLine = "Auth server unreachable. Pending saved session verification.";
                    AddSystemOutput("Saved auth cookies loaded, but auth server is currently unreachable. Verification will retry when connectivity returns.");
                }
                else
                {
                    AuthFlowStatusLine = "Signed out.";
                }
                break;
        }
    }

    private async Task<AtlasApiClient.AuthSessionProbeResult> ProbeAuthSessionWithRetryAsync(CancellationToken cancellationToken = default)
    {
        AtlasApiClient.AuthSessionProbeResult? lastProbe = null;
        for (var attempt = 1; attempt <= AuthSessionProbeRetryAttempts; attempt += 1)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var probe = await _apiClient.ProbeAuthSessionAsync(cancellationToken);
            lastProbe = probe;
            if (probe.State != AtlasApiClient.AuthProbeState.Unreachable)
            {
                return probe;
            }

            if (attempt < AuthSessionProbeRetryAttempts)
            {
                await Task.Delay(AuthSessionProbeRetryDelay, cancellationToken);
            }
        }

        return lastProbe ?? new AtlasApiClient.AuthSessionProbeResult
        {
            State = AtlasApiClient.AuthProbeState.Unreachable,
            StatusCode = 0,
            Error = "Auth probe retry did not produce a result."
        };
    }

    private void ApplyRemoteAuthSession(AtlasApiClient.AuthSessionUser remoteSession, AuthProvider fallbackProvider)
    {
        Session.IsSignedIn = true;
        Session.Provider = ParseProvider(remoteSession.Provider, fallbackProvider);
        Session.AccountLabel = string.IsNullOrWhiteSpace(remoteSession.Name)
            ? string.IsNullOrWhiteSpace(remoteSession.Email)
                ? "Atlas account"
                : remoteSession.Email
            : remoteSession.Name;
        Session.PrepaidCreditsActive = remoteSession.PrepaidCreditsActive;
        Session.Tier = remoteSession.PrepaidCreditsActive ? AccountTier.ProCloud : AccountTier.LocalCore;

        if (remoteSession.PrepaidCreditsActive)
        {
            AddSystemOutput($"Signed in with {Session.Provider} via shared backend {_apiClient.Host}. Prepaid credits active.");
        }
        else
        {
            AddSystemOutput($"Signed in with {Session.Provider} via shared backend {_apiClient.Host}. On-device AI remains active; prepaid credits unlock optional cloud add-on.");
        }
    }

    private void ResetToGuestAuthState()
    {
        Session.IsSignedIn = false;
        Session.Provider = AuthProvider.Guest;
        Session.AccountLabel = "Guest Operator";
        Session.Tier = AccountTier.LocalCore;
        Session.PrepaidCreditsActive = false;
    }

    private Uri BuildAuthPortalUri(AuthBrowserAction action)
    {
        var apiBase = AtlasBackendConfig.SanitizeApiBase(Session.ApiBaseUrl);
        var apiUri = new Uri(apiBase, UriKind.Absolute);
        var authOrigin = ResolveAuthWebOrigin(apiUri);
        var page = action == AuthBrowserAction.PasskeySignUp ? "signup.html" : "signin.html";
        var builder = new UriBuilder(new Uri(authOrigin, page))
        {
            Query = $"api_base={Uri.EscapeDataString(apiBase)}&stay_auth=1&client=atlas_windows"
        };
        return builder.Uri;
    }

    private static Uri ResolveAuthWebOrigin(Uri apiUri)
    {
        var envOverride = Environment.GetEnvironmentVariable("ATLAS_AUTH_WEB_BASE");
        if (TryParseAuthWebOrigin(envOverride, out var parsed))
        {
            return parsed;
        }

        var host = apiUri.Host.ToLowerInvariant();
        if ((host == "localhost" || host == "127.0.0.1") && apiUri.Scheme == Uri.UriSchemeHttp)
        {
            return new Uri($"{apiUri.Scheme}://{apiUri.Host}:5500/", UriKind.Absolute);
        }

        return new Uri("https://atlasmasa.com/", UriKind.Absolute);
    }

    private static bool TryParseAuthWebOrigin(string? rawValue, out Uri result)
    {
        result = new Uri("https://atlasmasa.com/", UriKind.Absolute);
        var trimmed = (rawValue ?? string.Empty).Trim();
        if (trimmed.Length == 0)
        {
            return false;
        }

        if (!trimmed.Contains("://", StringComparison.Ordinal))
        {
            trimmed = $"https://{trimmed}";
        }

        if (!Uri.TryCreate(trimmed, UriKind.Absolute, out var parsed))
        {
            return false;
        }

        var host = parsed.Host.ToLowerInvariant();
        var isLocalHost = host == "localhost" || host == "127.0.0.1";
        if (parsed.Scheme != Uri.UriSchemeHttps && !(parsed.Scheme == Uri.UriSchemeHttp && isLocalHost))
        {
            return false;
        }

        var normalized = parsed.GetLeftPart(UriPartial.Authority).TrimEnd('/') + "/";
        result = new Uri(normalized, UriKind.Absolute);
        return true;
    }

    private static AuthProvider ParseProvider(string rawProvider, AuthProvider fallback)
    {
        var normalized = (rawProvider ?? string.Empty).Trim().ToLowerInvariant();
        return normalized switch
        {
            "apple" => AuthProvider.Apple,
            "google" => AuthProvider.Google,
            "passkey" => AuthProvider.Passkey,
            _ => fallback
        };
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

        var youtubeImported = await IngestYouTubeLinksFromTextAsync($"{title}\n{content}", title);
        if (youtubeImported > 0)
        {
            AddSystemOutput($"Indexed {youtubeImported} YouTube link(s) into AI memory context.");
        }

        NewNoteTitle = string.Empty;
        NewNoteContent = string.Empty;
        AddSystemOutput("Note captured and indexed.");
        await RefreshExecutionAsync();
        await PersistAsync();
    }

    private readonly record struct YouTubeCandidate(string VideoId, string CanonicalUrl);

    private sealed class YouTubeMetadata
    {
        public string Title { get; init; } = "YouTube Video";
        public string Channel { get; init; } = "Unknown channel";
        public string Description { get; init; } = "No description extracted.";
    }

    private async Task<int> IngestYouTubeLinksFromTextAsync(string text, string noteTitle)
    {
        if (!Session.MemoryOptIn)
        {
            return 0;
        }

        var candidates = ExtractYouTubeCandidates(text).Take(3).ToList();
        if (candidates.Count == 0)
        {
            return 0;
        }

        var imported = 0;
        foreach (var candidate in candidates)
        {
            var metadata = await FetchYouTubeMetadataAsync(candidate, _queueCts.Token);
            if (metadata is null)
            {
                continue;
            }

            Memory.Insert(0, new MemoryRecord
            {
                Type = "youtube_video",
                Source = "windows_youtube_scrape",
                Weight = 0.78,
                Recency = DateTimeOffset.UtcNow,
                Tags = ["youtube", "video", "context", "scraped"],
                Value = $"{CleanText(noteTitle, 60)} | {CleanText(metadata.Title, 120)} by {CleanText(metadata.Channel, 80)} | {CleanText(metadata.Description, 180)} | {candidate.CanonicalUrl}"
            });
            imported += 1;
        }

        if (imported > 0)
        {
            TrimMemory();
        }
        return imported;
    }

    private static List<YouTubeCandidate> ExtractYouTubeCandidates(string text)
    {
        var regex = new Regex(@"https?://(?:www\.)?(?:youtube\.com|m\.youtube\.com|youtu\.be)/[^\s)\]]+", RegexOptions.IgnoreCase);
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var output = new List<YouTubeCandidate>();

        foreach (Match match in regex.Matches(text))
        {
            if (!Uri.TryCreate(match.Value, UriKind.Absolute, out var parsed))
            {
                continue;
            }
            var videoId = ExtractYouTubeVideoId(parsed);
            if (string.IsNullOrWhiteSpace(videoId) || !seen.Add(videoId))
            {
                continue;
            }

            output.Add(new YouTubeCandidate(videoId, $"https://www.youtube.com/watch?v={videoId}"));
        }

        return output;
    }

    private static string? ExtractYouTubeVideoId(Uri url)
    {
        static string? NormalizeId(string? raw)
        {
            if (string.IsNullOrWhiteSpace(raw))
            {
                return null;
            }
            var trimmed = raw.Trim();
            var cleaned = new string(trimmed.TakeWhile(ch => char.IsLetterOrDigit(ch) || ch is '_' or '-').ToArray());
            if (cleaned.Length < 6)
            {
                return null;
            }
            return cleaned.Length > 11 ? cleaned[..11] : cleaned;
        }

        var host = (url.Host ?? string.Empty).ToLowerInvariant();
        if (host.Contains("youtu.be", StringComparison.Ordinal))
        {
            var firstPath = url.AbsolutePath.Trim('/').Split('/').FirstOrDefault();
            return NormalizeId(firstPath);
        }

        if (url.AbsolutePath.Equals("/watch", StringComparison.OrdinalIgnoreCase))
        {
            var rawQuery = url.Query.TrimStart('?');
            foreach (var pair in rawQuery.Split('&', StringSplitOptions.RemoveEmptyEntries))
            {
                var split = pair.Split('=', 2);
                if (split.Length != 2 || !split[0].Equals("v", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                return NormalizeId(Uri.UnescapeDataString(split[1]));
            }
        }

        if (url.AbsolutePath.StartsWith("/shorts/", StringComparison.OrdinalIgnoreCase) ||
            url.AbsolutePath.StartsWith("/embed/", StringComparison.OrdinalIgnoreCase))
        {
            var parts = url.AbsolutePath.Trim('/').Split('/');
            if (parts.Length >= 2)
            {
                return NormalizeId(parts[1]);
            }
        }

        return null;
    }

    private async Task<YouTubeMetadata?> FetchYouTubeMetadataAsync(YouTubeCandidate candidate, CancellationToken cancellationToken)
    {
        try
        {
            var oembedUrl = $"https://www.youtube.com/oembed?url={Uri.EscapeDataString(candidate.CanonicalUrl)}&format=json";
            using var oembedResponse = await _youtubeHttpClient.GetAsync(oembedUrl, cancellationToken);
            if (!oembedResponse.IsSuccessStatusCode)
            {
                return null;
            }

            var oembedBody = await oembedResponse.Content.ReadAsStringAsync(cancellationToken);
            using var doc = JsonDocument.Parse(oembedBody);
            var title = doc.RootElement.TryGetProperty("title", out var titleNode)
                ? titleNode.GetString() ?? "YouTube Video"
                : "YouTube Video";
            var channel = doc.RootElement.TryGetProperty("author_name", out var authorNode)
                ? authorNode.GetString() ?? "Unknown channel"
                : "Unknown channel";
            var description = await FetchYouTubeDescriptionAsync(candidate.VideoId, cancellationToken)
                ?? "No description extracted.";

            return new YouTubeMetadata
            {
                Title = title,
                Channel = channel,
                Description = description
            };
        }
        catch
        {
            return null;
        }
    }

    private async Task<string?> FetchYouTubeDescriptionAsync(string videoId, CancellationToken cancellationToken)
    {
        try
        {
            var watchUrl = $"https://www.youtube.com/watch?v={Uri.EscapeDataString(videoId)}";
            using var response = await _youtubeHttpClient.GetAsync(watchUrl, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return null;
            }

            var html = await response.Content.ReadAsStringAsync(cancellationToken);
            var patterns = new[]
            {
                "\"shortDescription\":\"([^\"]+)\"",
                "<meta name=\"description\" content=\"([^\"]+)\""
            };
            foreach (var pattern in patterns)
            {
                var regex = new Regex(pattern, RegexOptions.IgnoreCase);
                var match = regex.Match(html);
                if (!match.Success || match.Groups.Count < 2)
                {
                    continue;
                }

                var raw = match.Groups[1].Value;
                var decoded = DecodeEscapedYouTubeString(raw);
                if (!string.IsNullOrWhiteSpace(decoded))
                {
                    return decoded;
                }
            }
        }
        catch
        {
            // ignore
        }

        return null;
    }

    private static string DecodeEscapedYouTubeString(string raw)
    {
        var decoded = raw
            .Replace("\\n", " ", StringComparison.Ordinal)
            .Replace("\\r", " ", StringComparison.Ordinal)
            .Replace("\\t", " ", StringComparison.Ordinal)
            .Replace("\\/", "/", StringComparison.Ordinal)
            .Replace("\\\"", "\"", StringComparison.Ordinal)
            .Replace("\\u0026", "&", StringComparison.Ordinal)
            .Replace("\\u003d", "=", StringComparison.Ordinal)
            .Replace("\\u003c", "<", StringComparison.Ordinal)
            .Replace("\\u003e", ">", StringComparison.Ordinal);
        decoded = WebUtility.HtmlDecode(decoded);
        return CleanText(decoded, 260);
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
        if (Session.PrepaidCreditsActive)
        {
            AddSystemOutput("Prompt queued. Cloud add-on is active, with on-device fallback if needed.");
        }
        else
        {
            AddSystemOutput("Prompt queued for on-device AI processing.");
        }
        await PersistAsync();
    }

    private async Task RunCodeAgentTaskAsync()
    {
        var prompt = CodePromptDraft.Trim();
        if (prompt.Length == 0)
        {
            return;
        }
        if (!Session.PrepaidCreditsActive)
        {
            AddSystemOutput("Code Agent is locked. Prepaid credits are required for coding tasks.");
            return;
        }
        if (Queue.Count >= 400)
        {
            AddSystemOutput("Queue limit reached (400). Clear older completed items before adding more.");
            return;
        }

        var route = ResolveCodeAgentRoute(SelectedCodeAgentMode, prompt);
        var enrichedPrompt = BuildCodeAgentPrompt(prompt, route);
        Queue.Insert(0, new QueueRecord
        {
            Prompt = enrichedPrompt[..Math.Min(enrichedPrompt.Length, 2200)],
            CodeAgentRoute = route,
            Status = PromptQueueStatus.Queued,
            Progress = 0.0,
            CheckpointNote = $"Agentic route: {CodeRouteLabel(route)}"
        });

        CodePromptDraft = string.Empty;
        AddSystemOutput($"Code Agent task queued ({CodeRouteLabel(route)}).");
        await PersistAsync();
    }

    private async Task RunClassicCodeCommandAsync()
    {
        var command = ClassicCodeCommandDraft.Trim();
        if (command.Length == 0)
        {
            return;
        }
        if (!Session.PrepaidCreditsActive)
        {
            AddSystemOutput("Classic code tools are locked. Prepaid credits are required.");
            return;
        }
        if (IsClassicCodeCommandRunning)
        {
            return;
        }

        IsClassicCodeCommandRunning = true;
        ClassicCodeCommandOutput = $"Running: {command}";
        try
        {
            var result = await ExecuteShellCommandAsync(command, CancellationToken.None);
            ClassicCodeCommandOutput =
                $"Exit {result.StatusCode}\n{result.Output}";
            AddSystemOutput($"Classic command finished: {command}");
        }
        catch (Exception ex)
        {
            ClassicCodeCommandOutput = $"Command failed: {ex.Message}";
            AddSystemOutput($"Classic command failed: {ex.Message}");
        }
        finally
        {
            IsClassicCodeCommandRunning = false;
            await PersistAsync();
        }
    }

    private static string ResolveCodeAgentRoute(string? selectedMode, string prompt)
    {
        var normalized = (selectedMode ?? string.Empty).Trim().ToLowerInvariant();
        return normalized switch
        {
            "frontend_design" => "frontend_design",
            "backend_ops" => "backend_ops",
            _ => InferCodeAgentRouteFromPrompt(prompt)
        };
    }

    private static string InferCodeAgentRouteFromPrompt(string prompt)
    {
        var lower = prompt.ToLowerInvariant();
        var frontendHints = new[]
        {
            "frontend", "front-end", "ui", "ux", "css", "tailwind", "layout", "responsive",
            "design system", "animation", "typography", "visual polish"
        };
        return frontendHints.Any(hint => lower.Contains(hint, StringComparison.Ordinal))
            ? "frontend_design"
            : "backend_ops";
    }

    private static string CodeRouteLabel(string route)
    {
        return route switch
        {
            "frontend_design" => "Gemini 3.1 Pro · frontend design",
            "backend_ops" => "GPT-5.3 Codex · backend/debug/build",
            _ => "Auto route"
        };
    }

    private static string BuildCodeAgentPrompt(string prompt, string route)
    {
        var routeInstruction = route == "frontend_design"
            ? "Route this to frontend design execution: prioritize UI system architecture, responsive layout, accessibility, and polished visual implementation."
            : "Route this to backend/troubleshooting/build execution: prioritize root-cause isolation, minimal safe patches, and explicit verification commands/tests.";
        return
            $"{routeInstruction}\n\nUser task:\n{prompt}\n\nRequired output:\n1) Diagnosis\n2) Exact implementation steps\n3) Verification checklist\n4) Risk/fallback notes";
    }

    private static async Task<(int StatusCode, string Output)> ExecuteShellCommandAsync(
        string command,
        CancellationToken cancellationToken)
    {
        var fileName = OperatingSystem.IsWindows() ? "cmd.exe" : "/bin/zsh";
        var arguments = OperatingSystem.IsWindows()
            ? $"/c {command}"
            : $"-lc \"{command.Replace("\"", "\\\"")}\"";
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = fileName,
                Arguments = arguments,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            }
        };

        process.Start();
        var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        var stdout = await stdoutTask;
        var stderr = await stderrTask;
        var combined = $"{stdout}\n{stderr}".Trim();
        if (combined.Length > 12_000)
        {
            combined = combined[..12_000];
        }
        if (combined.Length == 0)
        {
            combined = "(no output)";
        }
        return (process.ExitCode, combined);
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
        if (current is null || IsCurrentSurveyQuestionMulti)
        {
            return;
        }

        await RecordSurveyAnswerAsync(current, choice.Value, choice.Label);
    }

    public void SetSurveyMultiSelection(SurveyChoice? choice, bool isSelected)
    {
        var current = CurrentSurveyQuestion;
        if (choice is null || current is null || !IsCurrentSurveyQuestionMulti)
        {
            return;
        }

        var value = (choice.Value ?? string.Empty).Trim();
        if (value.Length == 0 || current.Choices.All(item => !string.Equals(item.Value, value, StringComparison.Ordinal)))
        {
            return;
        }

        if (string.Equals(value, "not_sure", StringComparison.Ordinal))
        {
            if (isSelected)
            {
                _surveyMultiSelections.Clear();
                _surveyMultiSelections.Add(value);
            }
            else
            {
                _surveyMultiSelections.Remove(value);
            }
        }
        else
        {
            if (isSelected)
            {
                _surveyMultiSelections.Add(value);
                _surveyMultiSelections.Remove("not_sure");
            }
            else
            {
                _surveyMultiSelections.Remove(value);
            }
        }

        RaisePropertyChanged(nameof(SurveyMultiSelectionLine));
        SubmitSurveyMultiChoiceCommand.NotifyCanExecuteChanged();
    }

    private bool CanSubmitSurveyMultiChoice()
    {
        return IsCurrentSurveyQuestionMulti && CurrentSurveyQuestion is not null && _surveyMultiSelections.Count > 0;
    }

    private async Task SubmitSurveyMultiChoiceAsync()
    {
        var current = CurrentSurveyQuestion;
        if (current is null || !IsCurrentSurveyQuestionMulti || _surveyMultiSelections.Count == 0)
        {
            return;
        }

        var selectedValues = current.Choices
            .Select(choice => choice.Value)
            .Where(value => _surveyMultiSelections.Contains(value))
            .Distinct(StringComparer.Ordinal)
            .ToList();
        if (selectedValues.Count == 0)
        {
            return;
        }

        var selectedLabels = ResolveSurveyChoiceLabels(current, selectedValues);
        var answerValue = string.Join("|", selectedValues);
        var answerLabel = string.Join(", ", selectedLabels);
        await RecordSurveyAnswerAsync(current, answerValue, answerLabel);
    }

    private async Task RecordSurveyAnswerAsync(SurveyQuestion question, string answerValue, string answerLabel)
    {
        _surveyAnswers[question.Id] = answerValue;
        SelectedSurveyAnswerLabel = answerLabel;
        var answeredCount = CountAnsweredSurveyQuestions();
        IsSurveyCompleted = answeredCount >= _surveyQuestions.Count;
        CanAccessExecution = IsSurveyCompleted;
        if (IsSurveyCompleted && !Session.GuidedLearningRuntimeActive)
        {
            Session.AdaptiveBusinessRuntimeStatusLine = "Survey complete. Activate guided learning when you are ready to start using the app.";
        }
        RaisePropertyChanged(nameof(SurveyCompletionLine));
        RaisePropertyChanged(nameof(ExecutionAccessLine));
        SurveyProgressText = $"{answeredCount} / {_surveyQuestions.Count}";
        ActivateGuidedLearningCommand.NotifyCanExecuteChanged();

        if (Session.MemoryOptIn)
        {
            Memory.Insert(0, new MemoryRecord
            {
                Type = "survey_answer",
                Source = "windows_survey",
                Weight = 0.72,
                Recency = DateTimeOffset.UtcNow,
                Tags = ["survey", question.Id],
                Value = $"{question.Title} => {answerLabel}"
            });
            TrimMemory();
        }

        RefreshSurveyCursor();
        AddSystemOutput($"Survey captured: {question.Id} = {answerValue}");
        await RefreshExecutionAsync();
        await PersistAsync();
    }

    public void SetAdaptiveOptionSelection(string? option, bool isSelected)
    {
        if (string.IsNullOrWhiteSpace(option))
        {
            return;
        }

        var trimmed = option.Trim();
        if (isSelected)
        {
            _adaptiveSelectedOptions.Add(trimmed);
        }
        else
        {
            _adaptiveSelectedOptions.Remove(trimmed);
        }
        RaisePropertyChanged(nameof(AdaptiveSelectedOptionsLine));
        SubmitAdaptiveQuestionResponseCommand.NotifyCanExecuteChanged();
    }

    private bool CanSubmitAdaptiveQuestionResponse()
    {
        return PendingAdaptiveBusinessQuestion is not null &&
            (_adaptiveSelectedOptions.Count > 0 || !string.IsNullOrWhiteSpace(AdaptiveFreeformResponseDraft));
    }

    private async Task ActivateGuidedLearningAfterSurveyAsync()
    {
        if (!IsSurveyCompleted)
        {
            Session.AdaptiveBusinessRuntimeStatusLine = "Finish the initialization survey first.";
            AddSystemOutput("Guided learning activation blocked: complete all survey questions first.");
            await PersistAsync();
            return;
        }

        if (!Session.GuidedLearningRuntimeActive)
        {
            Session.GuidedLearningRuntimeActive = true;
            Session.AdaptiveBusinessRuntimeStatusLine = "Guided learning active. Adaptive runtime is running.";
            AddSystemOutput("Guided learning activated after survey completion.");
            await PersistAsync();
        }

        NotifyAdaptiveQuestionStateChanged();
        await RunAdaptiveBusinessRuntimeTickAsync("activation", forceQuestion: true, forceAutopilot: true, _queueCts.Token);
        await RefreshExecutionAsync();
    }

    private async Task SaveAdaptiveRuntimeSettingsAsync()
    {
        Session.AdaptiveBusinessRuntimeStatusLine =
            $"Adaptive runtime updated. Questions: {(Session.AdaptiveBusinessQuestionEngineEnabled ? "on" : "off")}, autopilot: {(Session.BusinessAutopilotEnabled ? "on" : "off")}.";
        NotifyAdaptiveQuestionStateChanged();
        await PersistAsync();
        await RunAdaptiveBusinessRuntimeTickAsync("settings", forceQuestion: false, forceAutopilot: false, _queueCts.Token);
    }

    private async Task RequestAdaptiveQuestionNowAsync()
    {
        await RunAdaptiveBusinessRuntimeTickAsync("manual", forceQuestion: true, forceAutopilot: false, _queueCts.Token);
    }

    private async Task SubmitAdaptiveQuestionResponseAsync()
    {
        var pending = PendingAdaptiveBusinessQuestion;
        if (pending is null)
        {
            Session.AdaptiveBusinessRuntimeStatusLine = "No pending adaptive question. Generate one first.";
            await PersistAsync();
            return;
        }

        var validOptions = pending.Options
            .Where(option => _adaptiveSelectedOptions.Contains(option))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        var freeform = CleanText(AdaptiveFreeformResponseDraft, 360);
        if (validOptions.Count == 0 && freeform.Length == 0)
        {
            Session.AdaptiveBusinessRuntimeStatusLine = "Choose at least one option or add a freeform response.";
            await PersistAsync();
            return;
        }

        pending.Response = new AdaptiveBusinessQuestionResponse
        {
            SelectedOptions = validOptions,
            FreeformText = freeform,
            AnsweredAt = DateTimeOffset.UtcNow
        };

        if (Session.MemoryOptIn)
        {
            Memory.Insert(0, new MemoryRecord
            {
                Type = "adaptive_business_question",
                Source = "windows_ollama",
                Weight = 0.82,
                Recency = DateTimeOffset.UtcNow,
                Tags = ["adaptive", "business", "questionnaire", "ollama"],
                Value = $"Q: {pending.Prompt} | Selected: {(validOptions.Count == 0 ? "none" : string.Join(", ", validOptions))} | Notes: {(freeform.Length == 0 ? "none" : freeform)}"
            });
            TrimMemory();
        }

        Session.AdaptiveBusinessRuntimeStatusLine = "Response captured and added to memory.";
        AddSystemOutput("Adaptive business response captured.");
        NotifyAdaptiveQuestionStateChanged();
        await RefreshQuantumLearningSnapshotFromCurrentStateAsync("adaptive_response");
        await PersistAsync();
        await RefreshExecutionAsync();
        await RunAdaptiveBusinessRuntimeTickAsync("answer", forceQuestion: true, forceAutopilot: false, _queueCts.Token);
    }

    private async Task RunAdaptiveBusinessRuntimeTickAsync(
        string trigger,
        bool forceQuestion,
        bool forceAutopilot,
        CancellationToken cancellationToken)
    {
        if (!_isInitialized)
        {
            return;
        }

        var lockTaken = false;
        try
        {
            lockTaken = await _adaptiveRuntimeLock.WaitAsync(0, cancellationToken);
            if (!lockTaken)
            {
                return;
            }

            AtlasSessionState snapshotSession = new();
            List<AdaptiveBusinessQuestion> snapshotQuestions = [];
            List<NoteRecord> snapshotNotes = [];
            List<MemoryRecord> snapshotMemory = [];
            Dictionary<string, string> snapshotSurveyAnswers = [];

            await _dispatcher.EnqueueAsync(() =>
            {
                snapshotSession = CloneSession();
                snapshotQuestions = AdaptiveBusinessQuestions
                    .OrderByDescending(question => question.GeneratedAt)
                    .Take(AdaptiveQuestionHistoryCap)
                    .Select(CloneAdaptiveQuestion)
                    .ToList();
                snapshotNotes = Notes.Take(8).Select(CloneNote).ToList();
                snapshotMemory = Memory.Take(12).Select(CloneMemory).ToList();
                snapshotSurveyAnswers = new Dictionary<string, string>(_surveyAnswers);
            });

            if (!snapshotSession.GuidedLearningRuntimeActive)
            {
                if (forceQuestion || forceAutopilot)
                {
                    await _dispatcher.EnqueueAsync(() =>
                    {
                        Session.AdaptiveBusinessRuntimeStatusLine = "Adaptive questions are locked until guided learning is active.";
                    });
                    await PersistAsync();
                }
                return;
            }

            var now = DateTimeOffset.UtcNow;
            var quantumSnapshot = await RefreshQuantumLearningSnapshotAsync(
                trigger,
                snapshotSession,
                snapshotNotes,
                snapshotMemory,
                snapshotSurveyAnswers);
            AdaptiveBusinessQuestion? generatedQuestion = null;
            var pendingCount = snapshotQuestions.Count(question => question.Response is null);
            var shouldGenerateQuestion = (snapshotSession.AdaptiveBusinessQuestionEngineEnabled || forceQuestion) &&
                (forceQuestion ||
                    (pendingCount < AdaptiveQuestionPendingCap &&
                        (now - snapshotSession.LastAdaptiveBusinessQuestionAtUtc) >= AdaptiveQuestionCadence));
            if (shouldGenerateQuestion)
            {
                generatedQuestion = await BuildAdaptiveBusinessQuestionAsync(
                    snapshotSession,
                    snapshotQuestions,
                    snapshotNotes,
                    snapshotMemory,
                    snapshotSurveyAnswers,
                    quantumSnapshot,
                    cancellationToken);
            }

            AutopilotCycleResult? autopilotResult = null;
            var nextCursor = snapshotSession.AdaptiveBusinessAutopilotCursor;
            var shouldRunAutopilot = (snapshotSession.BusinessAutopilotEnabled || forceAutopilot) &&
                (forceAutopilot ||
                    (now - snapshotSession.LastBusinessAutopilotAtUtc) >= BusinessAutopilotCadence);
            if (shouldRunAutopilot)
            {
                autopilotResult = await GenerateAutopilotCycleAsync(
                    prompt: BusinessAutopilotPrompt(nextCursor, quantumSnapshot),
                    notes: snapshotNotes,
                    sessionSnapshot: snapshotSession,
                    surveyAnswers: snapshotSurveyAnswers,
                    cancellationToken: cancellationToken);
                nextCursor = (nextCursor + 1) % 3;
            }

            if (generatedQuestion is null && autopilotResult is null)
            {
                return;
            }

            await _dispatcher.EnqueueAsync(() =>
            {
                if (generatedQuestion is not null)
                {
                    AdaptiveBusinessQuestions.Insert(0, generatedQuestion);
                    while (AdaptiveBusinessQuestions.Count > AdaptiveQuestionHistoryCap)
                    {
                        AdaptiveBusinessQuestions.RemoveAt(AdaptiveBusinessQuestions.Count - 1);
                    }
                    Session.LastAdaptiveBusinessQuestionAtUtc = now;
                    Session.AdaptiveBusinessRuntimeStatusLine = $"Adaptive question generated ({trigger}).";
                    AddSystemOutput("Adaptive question generated from memory context.");
                }

                if (autopilotResult is not null)
                {
                    Session.LastBusinessAutopilotAtUtc = now;
                    Session.AdaptiveBusinessAutopilotCursor = nextCursor;
                    Session.AdaptiveBusinessRuntimeStatusLine = autopilotResult.StatusLine;
                    if (autopilotResult.Success)
                    {
                        if (Session.MemoryOptIn)
                        {
                            Memory.Insert(0, new MemoryRecord
                            {
                                Type = "adaptive_business_autopilot",
                                Source = autopilotResult.MemorySource,
                                Weight = autopilotResult.Confidence,
                                Recency = now,
                                Tags = ["adaptive", "business", "autopilot"],
                                Value = $"{autopilotResult.Summary} | {autopilotResult.NextAction}"
                            });
                            TrimMemory();
                        }

                        Workspaces.Insert(0, new WorkspaceSession
                        {
                            Lane = WorkspaceLane.Guide,
                            Title = $"Autopilot: {autopilotResult.Summary[..Math.Min(autopilotResult.Summary.Length, 52)]}",
                            Summary = autopilotResult.NextAction[..Math.Min(autopilotResult.NextAction.Length, 220)],
                            UpdatedAt = now
                        });
                        TrimWorkspaces();
                        AddSystemOutput("Business autopilot cycle completed in background.");
                    }
                    else
                    {
                        AddSystemOutput(autopilotResult.StatusLine);
                    }
                }

                NotifyAdaptiveQuestionStateChanged();
            });

            await PersistAsync();
        }
        catch (OperationCanceledException)
        {
            // Expected during app shutdown.
        }
        catch (Exception ex)
        {
            AddSystemOutput($"Adaptive runtime error: {ex.Message}");
        }
        finally
        {
            if (lockTaken)
            {
                _adaptiveRuntimeLock.Release();
            }
        }
    }

    private async Task<AdaptiveBusinessQuestion> BuildAdaptiveBusinessQuestionAsync(
        AtlasSessionState sessionSnapshot,
        IReadOnlyList<AdaptiveBusinessQuestion> questions,
        IReadOnlyList<NoteRecord> notes,
        IReadOnlyList<MemoryRecord> memory,
        IReadOnlyDictionary<string, string> surveyAnswers,
        QuantumLearningSnapshot? quantumSnapshot,
        CancellationToken cancellationToken)
    {
        var answeredSnapshot = string.Join(
            "\n",
            questions
                .Where(question => question.Response is not null)
                .Take(4)
                .Select(question =>
                {
                    var response = question.Response!;
                    var selected = response.SelectedOptions.Count == 0 ? "none" : string.Join(", ", response.SelectedOptions);
                    var notesText = string.IsNullOrWhiteSpace(response.FreeformText) ? "none" : response.FreeformText;
                    return $"- Q: {question.Prompt}\n  A: {selected}\n  Notes: {notesText}";
                }));
        if (string.IsNullOrWhiteSpace(answeredSnapshot))
        {
            answeredSnapshot = "- none yet";
        }

        var contextDigest = BuildAdaptiveContextDigest(sessionSnapshot, notes, memory, surveyAnswers, quantumSnapshot);
        var generated = await _llmClient.TryAdaptiveBusinessQuestionAsync(
            answeredSnapshot,
            contextDigest,
            cancellationToken);
        if (generated is not null && !string.IsNullOrWhiteSpace(generated.Question))
        {
            var normalizedOptions = generated.Options
                .Select(option => CleanText(option, 72))
                .Where(option => option.Length > 0)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Take(5)
                .ToList();
            if (normalizedOptions.Count >= 3)
            {
                return new AdaptiveBusinessQuestion
                {
                    Prompt = CleanText(generated.Question, 180),
                    Options = normalizedOptions,
                    AllowsMultipleSelection = true,
                    Source = "ollama",
                    GeneratedAt = DateTimeOffset.UtcNow
                };
            }
        }

        if (quantumSnapshot is not null && quantumSnapshot.RecommendedOptions.Count >= 3)
        {
            return new AdaptiveBusinessQuestion
            {
                Prompt = CleanText(quantumSnapshot.RecommendedQuestion, 180),
                Options = quantumSnapshot.RecommendedOptions
                    .Select(option => CleanText(option, 72))
                    .Where(option => option.Length > 0)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .Take(5)
                    .ToList(),
                AllowsMultipleSelection = true,
                Source = "quantum_fallback",
                GeneratedAt = DateTimeOffset.UtcNow
            };
        }

        return new AdaptiveBusinessQuestion
        {
            Prompt = "What is the highest-leverage growth bottleneck right now?",
            Options =
            [
                "Top-of-funnel lead flow is too weak",
                "Offer/value proposition is unclear",
                "Conversion calls close too slowly",
                "Retention/expansion is underperforming"
            ],
            AllowsMultipleSelection = true,
            Source = "fallback",
            GeneratedAt = DateTimeOffset.UtcNow
        };
    }

    private async Task<AutopilotCycleResult> GenerateAutopilotCycleAsync(
        string prompt,
        IReadOnlyList<NoteRecord> notes,
        AtlasSessionState sessionSnapshot,
        IReadOnlyDictionary<string, string> surveyAnswers,
        CancellationToken cancellationToken)
    {
        if (sessionSnapshot.PrepaidCreditsActive)
        {
            var backendReply = await _apiClient.ChatReplyAsync(
                prompt,
                sessionSnapshot.LanguageCode,
                cancellationToken: cancellationToken);
            if (!string.IsNullOrWhiteSpace(backendReply))
            {
                return new AutopilotCycleResult(
                    Success: true,
                    StatusLine: "Business autopilot generated a growth action cycle.",
                    Summary: FirstNonEmptyLine(backendReply, 420),
                    NextAction: DeriveBackendNextAction(backendReply, 220),
                    Confidence: 0.84,
                    MemorySource: "windows_shared_backend");
            }
        }

        var llmOutput = await _llmClient.TryReasonAsync(prompt, notes, sessionSnapshot, surveyAnswers, cancellationToken);
        if (llmOutput is not null)
        {
            return new AutopilotCycleResult(
                Success: true,
                StatusLine: "Business autopilot generated a growth action cycle.",
                Summary: CleanText(llmOutput.Summary, 420),
                NextAction: CleanText(llmOutput.NextAction, 220),
                Confidence: Math.Clamp(llmOutput.Confidence, 0.0, 1.0),
                MemorySource: "windows_local_llm");
        }

        var fallback = await _reasoning.ReasonAsync(
            prompt,
            notes,
            _performance,
            (_, _) => { },
            cancellationToken);
        if (fallback is null)
        {
            return new AutopilotCycleResult(
                Success: false,
                StatusLine: "Business autopilot failed to generate output.",
                Summary: string.Empty,
                NextAction: string.Empty,
                Confidence: 0.0,
                MemorySource: "windows_local_model");
        }

        return new AutopilotCycleResult(
            Success: true,
            StatusLine: "Business autopilot generated a growth action cycle.",
            Summary: CleanText(fallback.Summary, 420),
            NextAction: CleanText(fallback.NextAction, 220),
            Confidence: Math.Clamp(fallback.Confidence, 0.0, 1.0),
            MemorySource: fallback.Model.Contains("rust", StringComparison.OrdinalIgnoreCase)
                ? "windows_rust_reasoner"
                : "windows_local_model");
    }

    private static string BusinessAutopilotPrompt(int cursor, QuantumLearningSnapshot? quantumSnapshot)
    {
        const string basePrompt = """
            Use all available user context and produce one concise business execution brief.
            Include:
            1) immediate action
            2) 7-day sequence
            3) KPI checkpoint
            4) risk + mitigation
            """;
        var quantumDirective = BuildQuantumAutopilotDirective(quantumSnapshot);

        return cursor % 3 switch
        {
            0 => $"{basePrompt}\nDeliverable: Weekly growth operating brief with north-star focus and experiment cadence.\n{quantumDirective}",
            1 => $"{basePrompt}\nDeliverable: Retention + expansion plan with churn diagnosis and onboarding fixes.\n{quantumDirective}",
            _ => $"{basePrompt}\nDeliverable: Distribution leverage plan with channel sequencing and conversion architecture.\n{quantumDirective}"
        };
    }

    private async Task<QuantumLearningSnapshot?> RefreshQuantumLearningSnapshotFromCurrentStateAsync(string trigger)
    {
        AtlasSessionState sessionSnapshot = new();
        List<NoteRecord> noteSnapshot = [];
        List<MemoryRecord> memorySnapshot = [];
        Dictionary<string, string> surveySnapshot = [];

        await _dispatcher.EnqueueAsync(() =>
        {
            sessionSnapshot = CloneSession();
            noteSnapshot = Notes.Take(8).Select(CloneNote).ToList();
            memorySnapshot = Memory.Take(16).Select(CloneMemory).ToList();
            surveySnapshot = new Dictionary<string, string>(_surveyAnswers, StringComparer.Ordinal);
        });

        return await RefreshQuantumLearningSnapshotAsync(
            trigger,
            sessionSnapshot,
            noteSnapshot,
            memorySnapshot,
            surveySnapshot);
    }

    private async Task<QuantumLearningSnapshot?> RefreshQuantumLearningSnapshotAsync(
        string trigger,
        AtlasSessionState sessionSnapshot,
        IReadOnlyList<NoteRecord> notes,
        IReadOnlyList<MemoryRecord> memory,
        IReadOnlyDictionary<string, string> surveyAnswers)
    {
        if (!sessionSnapshot.QuantumLearningEnabled)
        {
            await _dispatcher.EnqueueAsync(() =>
            {
                Session.QuantumLearningSnapshot = null;
                Session.QuantumLearningStatusLine = "Quantum learning simulator disabled.";
            });
            return null;
        }

        var snapshot = _quantumPlanner.BuildSnapshot(sessionSnapshot, surveyAnswers, notes, memory);
        var dominantLabel = QuantumLearningPlanner.TrackLabel(snapshot.DominantTrack);
        var confidencePct = Math.Clamp((int)Math.Round(snapshot.DominantProbability * 100.0), 0, 100);
        await _dispatcher.EnqueueAsync(() =>
        {
            Session.QuantumLearningSnapshot = snapshot;
            Session.QuantumLearningStatusLine = $"Quantum profile refreshed ({trigger}): {dominantLabel} {confidencePct}%.";
        });
        return snapshot;
    }

    private static string BuildAdaptiveContextDigest(
        AtlasSessionState session,
        IReadOnlyList<NoteRecord> notes,
        IReadOnlyList<MemoryRecord> memory,
        IReadOnlyDictionary<string, string> surveyAnswers,
        QuantumLearningSnapshot? quantumSnapshot)
    {
        var noteSnapshot = notes.Count == 0
            ? "- none yet"
            : string.Join("\n", notes.Take(6).Select(note => $"- {CleanText(note.Title, 80)}: {CleanText(note.Content, 160)}"));
        var memorySnapshot = memory.Count == 0
            ? "- none yet"
            : string.Join("\n", memory.Take(8).Select(item => $"- [{CleanText(item.Type, 22)}] {CleanText(item.Value, 180)}"));
        var surveySnapshot = surveyAnswers.Count == 0
            ? "none yet"
            : string.Join("; ", surveyAnswers.Select(entry => $"{entry.Key}={CleanText(entry.Value, 48)}"));
        var quantumSnapshotDigest = BuildQuantumDigest(quantumSnapshot, 820);

        var digest = $"""
            Account tier: {session.Tier}
            Language: {session.LanguageCode}
            Daily priority: {CleanText(session.DailyPriority, 180)}
            Mid-term goal: {CleanText(session.MidTermGoal, 180)}
            Long-term vision: {CleanText(session.LongTermVision, 180)}
            Current blockers: {CleanText(session.Blockers, 180)}
            Mood/Energy: {CleanText(session.Mood, 80)} / {session.Energy}
            Survey answers: {surveySnapshot}

            Notes
            {noteSnapshot}

            Memory
            {memorySnapshot}

            Quantum priority profile
            {quantumSnapshotDigest}
            """;
        return digest.Length <= 2400 ? digest : digest[..2400];
    }

    private static string BuildQuantumDigest(QuantumLearningSnapshot? snapshot, int maxChars)
    {
        if (snapshot is null)
        {
            return "Quantum simulator has no snapshot yet.";
        }

        var priorities = string.Join(
            " | ",
            snapshot.TrackProbabilities
                .Take(3)
                .Select(entry =>
                    $"{QuantumLearningPlanner.TrackLabel(entry.Track)} {Math.Clamp((int)Math.Round(entry.Probability * 100.0), 0, 100)}%"));
        var options = snapshot.RecommendedOptions.Count == 0
            ? "none"
            : string.Join(" ; ", snapshot.RecommendedOptions.Take(5).Select(option => CleanText(option, 72)));
        var digest = $"""
            Dominant track: {QuantumLearningPlanner.TrackLabel(snapshot.DominantTrack)} ({Math.Clamp((int)Math.Round(snapshot.DominantProbability * 100.0), 0, 100)}%).
            Priority distribution: {priorities}
            Recommended question: {CleanText(snapshot.RecommendedQuestion, 180)}
            Recommended options: {options}
            Rationale: {CleanText(snapshot.Rationale, 220)}
            """;
        return digest.Length <= maxChars ? digest : digest[..Math.Max(0, maxChars)];
    }

    private static string BuildQuantumAutopilotDirective(QuantumLearningSnapshot? snapshot)
    {
        if (snapshot is null)
        {
            return "If uncertain, prioritize one bottleneck with highest expected 14-day compounding impact.";
        }

        var topTracks = string.Join(
            " -> ",
            snapshot.TrackProbabilities
                .Take(2)
                .Select(entry =>
                    $"{QuantumLearningPlanner.TrackLabel(entry.Track)} {Math.Clamp((int)Math.Round(entry.Probability * 100.0), 0, 100)}%"));
        return $"Quantum directive: weight actions by current probabilities ({topTracks}). Do not split effort across more than two tracks.";
    }

    private static string InjectQuantumPromptDirective(string prompt, QuantumLearningSnapshot? snapshot)
    {
        if (snapshot is null)
        {
            return prompt;
        }

        return $"""
            {prompt}

            QUANTUM PRIORITY PROFILE
            {BuildQuantumDigest(snapshot, 720)}
            """;
    }

    private enum ActiveMemoryDepth
    {
        Lean,
        Balanced,
        Deep
    }

    private static string InjectActiveMemoryDirective(
        string prompt,
        IReadOnlyList<NoteRecord> notes,
        IReadOnlyList<MemoryRecord> memory)
    {
        var depth = ResolveActiveMemoryDepth();
        var digest = BuildActiveMemoryDigest(notes, memory, depth);
        if (string.IsNullOrWhiteSpace(digest))
        {
            return prompt;
        }

        return $"""
            {prompt}

            ACTIVE MEMORY MANAGEMENT
            {digest}
            """;
    }

    private static ActiveMemoryDepth ResolveActiveMemoryDepth()
    {
        var raw = (Environment.GetEnvironmentVariable("ATLAS_MEMORY_DEPTH") ?? "balanced")
            .Trim()
            .ToLowerInvariant();
        return raw switch
        {
            "lean" => ActiveMemoryDepth.Lean,
            "deep" => ActiveMemoryDepth.Deep,
            _ => ActiveMemoryDepth.Balanced
        };
    }

    private static string BuildActiveMemoryDigest(
        IReadOnlyList<NoteRecord> notes,
        IReadOnlyList<MemoryRecord> memory,
        ActiveMemoryDepth depth)
    {
        var (l1Count, l2Count, maxChars) = depth switch
        {
            ActiveMemoryDepth.Lean => (4, 8, 720),
            ActiveMemoryDepth.Deep => (10, 24, 2200),
            _ => (6, 14, 1300)
        };

        var working = memory
            .OrderByDescending(item => item.Recency)
            .Take(l1Count)
            .Select(item => $"- [{CleanText(item.Type, 20)}] {CleanText(item.Value, 120)}")
            .ToList();
        var episodic = memory
            .OrderByDescending(item => item.Weight)
            .ThenByDescending(item => item.Recency)
            .Take(l2Count)
            .Select(item => $"- [{CleanText(item.Source, 20)}:{CleanText(string.Join(",", item.Tags), 28)}] {CleanText(item.Value, 130)}")
            .ToList();
        var noteSignals = notes
            .Take(Math.Max(3, l1Count - 1))
            .Select(note => $"- {CleanText(note.Title, 60)}: {CleanText(note.Content, 120)}")
            .ToList();

        var archiveCount = memory.Count;
        var digest = $"""
            Memory depth: {depth} (set `ATLAS_MEMORY_DEPTH=lean|balanced|deep`).
            L1 Working Memory (recent):
            {(working.Count == 0 ? "- none" : string.Join("\n", working))}

            L2 Episodic Memory (high-signal durable):
            {(episodic.Count == 0 ? "- none" : string.Join("\n", episodic))}

            L2 Notes Context:
            {(noteSignals.Count == 0 ? "- none" : string.Join("\n", noteSignals))}

            L3 Archive:
            - Persistent records available: {archiveCount}
            - If detail is missing, retrieve from archive by tags/source/recency before final answer.
            """;

        return digest.Length <= maxChars ? digest : digest[..Math.Max(0, maxChars)];
    }

    private static string CleanText(string? value, int maxChars)
    {
        var source = value ?? string.Empty;
        var collapsed = string.Join(" ", source.Split(new[] { '\r', '\n', '\t', ' ' }, StringSplitOptions.RemoveEmptyEntries));
        if (collapsed.Length <= maxChars)
        {
            return collapsed;
        }
        return collapsed[..Math.Max(0, maxChars)].Trim();
    }

    private static AdaptiveBusinessQuestion CloneAdaptiveQuestion(AdaptiveBusinessQuestion question)
    {
        return new AdaptiveBusinessQuestion
        {
            Id = question.Id,
            Prompt = question.Prompt,
            Options = question.Options.ToList(),
            AllowsMultipleSelection = question.AllowsMultipleSelection,
            Source = question.Source,
            GeneratedAt = question.GeneratedAt,
            Response = question.Response is null
                ? null
                : new AdaptiveBusinessQuestionResponse
                {
                    SelectedOptions = question.Response.SelectedOptions.ToList(),
                    FreeformText = question.Response.FreeformText,
                    AnsweredAt = question.Response.AnsweredAt
                }
        };
    }

    private static QuantumLearningSnapshot CloneQuantumSnapshot(QuantumLearningSnapshot snapshot)
    {
        return new QuantumLearningSnapshot
        {
            GeneratedAt = snapshot.GeneratedAt,
            DominantTrack = snapshot.DominantTrack,
            DominantProbability = snapshot.DominantProbability,
            TrackProbabilities = snapshot.TrackProbabilities
                .Select(score => new QuantumTrackScore
                {
                    Track = score.Track,
                    Probability = score.Probability
                })
                .ToList(),
            RecommendedQuestion = snapshot.RecommendedQuestion,
            RecommendedOptions = snapshot.RecommendedOptions.ToList(),
            Rationale = snapshot.Rationale,
            Source = snapshot.Source
        };
    }

    private static NoteRecord CloneNote(NoteRecord note)
    {
        return new NoteRecord
        {
            Id = note.Id,
            Title = note.Title,
            Content = note.Content,
            CreatedAt = note.CreatedAt
        };
    }

    private static MemoryRecord CloneMemory(MemoryRecord record)
    {
        return new MemoryRecord
        {
            Id = record.Id,
            Type = record.Type,
            Source = record.Source,
            Weight = record.Weight,
            Recency = record.Recency,
            Tags = record.Tags.ToList(),
            Value = record.Value
        };
    }

    private void NotifyAdaptiveQuestionStateChanged()
    {
        SyncAdaptiveDraftWithPendingQuestion();
        RaisePropertyChanged(nameof(PendingAdaptiveBusinessQuestion));
        RaisePropertyChanged(nameof(AnsweredAdaptiveBusinessQuestionCount));
        RaisePropertyChanged(nameof(AdaptiveQuestionProgressLine));
        RaisePropertyChanged(nameof(AdaptiveSelectedOptionsLine));
        RequestAdaptiveQuestionNowCommand.NotifyCanExecuteChanged();
        SubmitAdaptiveQuestionResponseCommand.NotifyCanExecuteChanged();
        ActivateGuidedLearningCommand.NotifyCanExecuteChanged();
    }

    private void SyncAdaptiveDraftWithPendingQuestion()
    {
        var pendingId = PendingAdaptiveBusinessQuestion?.Id;
        if (string.Equals(_adaptiveDraftQuestionId, pendingId, StringComparison.Ordinal))
        {
            return;
        }

        _adaptiveDraftQuestionId = pendingId;
        _adaptiveSelectedOptions.Clear();
        AdaptiveFreeformResponseDraft = string.Empty;
        RaisePropertyChanged(nameof(AdaptiveSelectedOptionsLine));
    }

    private sealed record AutopilotCycleResult(
        bool Success,
        string StatusLine,
        string Summary,
        string NextAction,
        double Confidence,
        string MemorySource);

    private void RefreshSurveyCursor()
    {
        if (_surveyQuestions.Count == 0)
        {
            CurrentSurveyQuestion = null;
            CurrentSurveyChoices.Clear();
            SurveyProgressText = "0 / 0";
            IsSurveyCompleted = true;
            CanAccessExecution = true;
            _surveyMultiSelections.Clear();
            _activeSurveyMultiQuestionId = null;
            SelectedSurveyAnswerLabel = string.Empty;
            RaisePropertyChanged(nameof(IsCurrentSurveyQuestionMulti));
            RaisePropertyChanged(nameof(SurveyMultiSelectionLine));
            SubmitSurveyMultiChoiceCommand.NotifyCanExecuteChanged();
            return;
        }

        var next = _surveyQuestions.FirstOrDefault(q => !_surveyAnswers.ContainsKey(q.Id));
        var answeredCount = CountAnsweredSurveyQuestions();
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
            IsSurveyCompleted = false;
            CanAccessExecution = false;
            RaisePropertyChanged(nameof(SurveyCompletionLine));
            RaisePropertyChanged(nameof(ExecutionAccessLine));
        }

        SurveyProgressText = $"{answeredCount} / {_surveyQuestions.Count}";
        SyncSurveySelectionDraftForCurrentQuestion();
        SelectedSurveyAnswerLabel = ResolveSelectedSurveyAnswerLabel(CurrentSurveyQuestion);
        if (IsSurveyCompleted && !Session.GuidedLearningRuntimeActive && Session.AdaptiveBusinessRuntimeStatusLine == "Adaptive business runtime idle.")
        {
            Session.AdaptiveBusinessRuntimeStatusLine = "Survey complete. Activate guided learning when you are ready to start using the app.";
        }
        RaisePropertyChanged(nameof(IsCurrentSurveyQuestionMulti));
        RaisePropertyChanged(nameof(SurveyMultiSelectionLine));
        ActivateGuidedLearningCommand.NotifyCanExecuteChanged();
        SubmitSurveyMultiChoiceCommand.NotifyCanExecuteChanged();
    }

    private void SyncSurveySelectionDraftForCurrentQuestion()
    {
        var current = CurrentSurveyQuestion;
        if (current is null || !IsCurrentSurveyQuestionMulti)
        {
            _surveyMultiSelections.Clear();
            _activeSurveyMultiQuestionId = null;
            return;
        }

        if (string.Equals(_activeSurveyMultiQuestionId, current.Id, StringComparison.Ordinal) &&
            _surveyMultiSelections.Count > 0)
        {
            return;
        }

        _activeSurveyMultiQuestionId = current.Id;
        _surveyMultiSelections.Clear();
        if (_surveyAnswers.TryGetValue(current.Id, out var encoded))
        {
            var validValues = new HashSet<string>(current.Choices.Select(choice => choice.Value), StringComparer.Ordinal);
            foreach (var value in DecodeSurveyMultiValue(encoded))
            {
                if (validValues.Contains(value))
                {
                    _surveyMultiSelections.Add(value);
                }
            }
        }
    }

    private string ResolveSelectedSurveyAnswerLabel(SurveyQuestion? question)
    {
        if (question is null || !_surveyAnswers.TryGetValue(question.Id, out var answer))
        {
            return string.Empty;
        }

        if (string.Equals(question.Kind, "multi_choice", StringComparison.OrdinalIgnoreCase))
        {
            var labels = ResolveSurveyChoiceLabels(question, DecodeSurveyMultiValue(answer));
            return labels.Count == 0 ? string.Empty : string.Join(", ", labels);
        }

        return question.Choices.FirstOrDefault(choice => string.Equals(choice.Value, answer, StringComparison.Ordinal))?.Label ?? answer;
    }

    private static HashSet<string> DecodeSurveyMultiValue(string? encoded)
    {
        if (string.IsNullOrWhiteSpace(encoded))
        {
            return [];
        }

        return encoded
            .Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(value => value.Length > 0)
            .ToHashSet(StringComparer.Ordinal);
    }

    private static List<string> ResolveSurveyChoiceLabels(SurveyQuestion? question, IEnumerable<string> selectedValues)
    {
        if (question is null)
        {
            return [];
        }

        var lookup = question.Choices.ToDictionary(choice => choice.Value, choice => choice.Label, StringComparer.Ordinal);
        var labels = new List<string>();
        foreach (var value in selectedValues)
        {
            if (lookup.TryGetValue(value, out var label))
            {
                labels.Add(label);
            }
        }
        return labels;
    }

    private int CountAnsweredSurveyQuestions()
    {
        return _surveyQuestions.Count(question =>
            _surveyAnswers.TryGetValue(question.Id, out var answerValue) &&
            !string.IsNullOrWhiteSpace(answerValue));
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

                if (DateTimeOffset.UtcNow - _lastAdaptiveRuntimeHeartbeatUtc >= AdaptiveRuntimeLoopInterval)
                {
                    _lastAdaptiveRuntimeHeartbeatUtc = DateTimeOffset.UtcNow;
                    _ = RunAdaptiveBusinessRuntimeTickAsync("loop", forceQuestion: false, forceAutopilot: false, cancellationToken);
                }

                if (DateTimeOffset.UtcNow - _lastNatureSignalRefreshAtUtc >= NatureSignalRefreshCadence)
                {
                    _ = RefreshNatureSignalStackAsync(sendAlertNotifications: true, cancellationToken: cancellationToken);
                }
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
            var notesContext = new List<NoteRecord>();
            var memoryContext = new List<MemoryRecord>();
            var surveyContext = new Dictionary<string, string>(StringComparer.Ordinal);
            AtlasSessionState sessionSnapshot = new();
            await _dispatcher.EnqueueAsync(() =>
            {
                notesContext = Notes
                    .Take(8)
                    .Select(CloneNote)
                    .ToList();
                memoryContext = Memory
                    .Take(16)
                    .Select(CloneMemory)
                    .ToList();
                surveyContext = new Dictionary<string, string>(_surveyAnswers, StringComparer.Ordinal);
                sessionSnapshot = CloneSession();
            });
            var quantumSnapshot = await RefreshQuantumLearningSnapshotAsync(
                "queue_reasoning",
                sessionSnapshot,
                notesContext,
                memoryContext,
                surveyContext);
            var promptWithQuantum = InjectQuantumPromptDirective(prompt, quantumSnapshot);
            var promptWithActiveMemory = InjectActiveMemoryDirective(promptWithQuantum, notesContext, memoryContext);
            var route = string.IsNullOrWhiteSpace(queueRecord.CodeAgentRoute)
                ? null
                : ResolveCodeAgentRoute(queueRecord.CodeAgentRoute, prompt);
            var isCodeAgentTask = route is not null;
            LocalReasoningOutput? output = null;
            LocalReasoningOutput? llmOutput = null;
            var inferenceSource = "windows_local_model";
            var usedSharedBackend = false;

            await _dispatcher.EnqueueAsync(() =>
            {
                var record = Queue.FirstOrDefault(q => q.Id == queueId);
                if (record is null)
                {
                    return;
                }
                record.Progress = Math.Max(record.Progress, 0.30);
                record.CheckpointNote = isCodeAgentTask
                    ? $"Agentic coding route: {CodeRouteLabel(route!)}"
                    : sessionSnapshot.PrepaidCreditsActive
                        ? "Optional cloud add-on reasoning"
                        : "On-device reasoning";
            });

            if (!isCodeAgentTask && output is null && _localSyncBlueprint.LooksLikeSyncPrompt(prompt))
            {
                await _dispatcher.EnqueueAsync(() =>
                {
                    var record = Queue.FirstOrDefault(q => q.Id == queueId);
                    if (record is null)
                    {
                        return;
                    }
                    record.Progress = Math.Max(record.Progress, 0.36);
                    record.CheckpointNote = "Local-first sync blueprint planner";
                });

                output = _localSyncBlueprint.TryBuildPlan(prompt);
                if (output is not null)
                {
                    inferenceSource = "windows_local_sync_blueprint";
                }
            }

            if (!isCodeAgentTask && output is null && _recoverySupport.LooksLikeRecoveryPrompt(prompt))
            {
                await _dispatcher.EnqueueAsync(() =>
                {
                    var record = Queue.FirstOrDefault(q => q.Id == queueId);
                    if (record is null)
                    {
                        return;
                    }
                    record.Progress = Math.Max(record.Progress, 0.37);
                    record.CheckpointNote = "Recovery support planning";
                });

                output = _recoverySupport.TryBuildRecoveryPlan(prompt);
                if (output is not null)
                {
                    inferenceSource = "windows_recovery_support";
                }
            }

            if (!isCodeAgentTask && output is null && _academicResearch.LooksLikeResearchPrompt(prompt))
            {
                await _dispatcher.EnqueueAsync(() =>
                {
                    var record = Queue.FirstOrDefault(q => q.Id == queueId);
                    if (record is null)
                    {
                        return;
                    }
                    record.Progress = Math.Max(record.Progress, 0.38);
                    record.CheckpointNote = "Academic discovery scan (OpenAlex)";
                });

                var research = await _academicResearch.TryDiscoverAsync(prompt, cancellationToken);
                if (research is not null)
                {
                    output = new LocalReasoningOutput
                    {
                        Model = "atlas-openalex-research-v1",
                        Summary = research.Summary,
                        NextAction = research.NextAction,
                        Confidence = research.Confidence,
                        GeneratedAt = DateTimeOffset.UtcNow
                    };
                    inferenceSource = "windows_academic_discovery";
                }
            }

            if (isCodeAgentTask)
            {
                if (!sessionSnapshot.PrepaidCreditsActive)
                {
                    throw new InvalidOperationException("Code Agent requires prepaid credits. Top up credits and retry.");
                }

                var backendReply = await _apiClient.ChatReplyAsync(
                    prompt,
                    sessionSnapshot.LanguageCode,
                    preferredFormat: "step_by_step",
                    responseDepth: "deep",
                    responseTone: "direct",
                    includeProactive: false,
                    codeAgentRoute: route,
                    cancellationToken: cancellationToken);
                if (string.IsNullOrWhiteSpace(backendReply))
                {
                    throw new InvalidOperationException("Code Agent cloud response unavailable. Retry once backend is reachable.");
                }

                output = new LocalReasoningOutput
                {
                    Model = "atlas-cloud-backend/v1-code-agent",
                    Summary = FirstNonEmptyLine(backendReply, 420),
                    NextAction = DeriveBackendNextAction(backendReply, 220),
                    Confidence = 0.87,
                    GeneratedAt = DateTimeOffset.UtcNow
                };
                inferenceSource = route == "frontend_design"
                    ? "windows_code_agent_frontend"
                    : "windows_code_agent_backend";
                usedSharedBackend = true;
            }
            else if (sessionSnapshot.PrepaidCreditsActive)
            {
                var backendReply = await _apiClient.ChatReplyAsync(
                    promptWithActiveMemory,
                    sessionSnapshot.LanguageCode,
                    cancellationToken: cancellationToken);
                if (!string.IsNullOrWhiteSpace(backendReply))
                {
                    output = new LocalReasoningOutput
                    {
                        Model = "atlas-cloud-backend/v1-chat",
                        Summary = FirstNonEmptyLine(backendReply, 420),
                        NextAction = DeriveBackendNextAction(backendReply, 220),
                        Confidence = 0.84,
                        GeneratedAt = DateTimeOffset.UtcNow
                    };
                    inferenceSource = "windows_shared_backend";
                    usedSharedBackend = true;
                }
            }

            if (!isCodeAgentTask && output is null && _llmClient.Enabled)
            {
                await _dispatcher.EnqueueAsync(() =>
                {
                    var record = Queue.FirstOrDefault(q => q.Id == queueId);
                    if (record is null)
                    {
                        return;
                    }
                    record.Progress = Math.Max(record.Progress, 0.42);
                    record.CheckpointNote = "Local LLM inference";
                });
                llmOutput = await _llmClient.TryReasonAsync(
                    promptWithActiveMemory,
                    notesContext,
                    sessionSnapshot,
                    surveyContext,
                    cancellationToken);
            }

            if (!isCodeAgentTask && output is null)
            {
                output = llmOutput ?? await _reasoning.ReasonAsync(
                    promptWithActiveMemory,
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
                if (llmOutput is null)
                {
                    inferenceSource = output.Model.Contains("rust", StringComparison.OrdinalIgnoreCase)
                        ? "windows_rust_reasoner"
                        : "windows_local_model";
                }
                else
                {
                    inferenceSource = "windows_local_llm";
                }
            }

            if (output is null)
            {
                throw new InvalidOperationException("No reasoning output was generated.");
            }

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
                var usedRustReasoner = !isCodeAgentTask &&
                    !usedSharedBackend &&
                    llmOutput is null &&
                    output.Model.Contains("rust", StringComparison.OrdinalIgnoreCase);
                var deterministicRouteLabel = output.Model switch
                {
                    "atlas-openalex-research-v1" => "Completed via academic discovery engine",
                    "atlas-local-sync-v1" => "Completed via local sync blueprint engine",
                    "atlas-recovery-support-v1" => "Completed via recovery support engine",
                    _ => "Completed via deterministic fallback"
                };
                record.CheckpointNote = isCodeAgentTask
                    ? $"Completed via Code Agent ({CodeRouteLabel(route!)})"
                    : usedSharedBackend
                        ? "Completed via shared backend chat"
                        : usedRustReasoner
                            ? "Completed via Rust local reasoner"
                            : llmOutput is null
                                ? deterministicRouteLabel
                            : "Completed via local LLM";
                record.OutputSummary = output.Summary;
                record.NextAction = output.NextAction;
                record.Confidence = output.Confidence;
                record.ErrorMessage = null;

                if (sessionSnapshot.MemoryOptIn)
                {
                    var memoryTags = isCodeAgentTask
                        ? new List<string> { "queue", "reasoning", "code_agent", route! }
                        : new List<string> { "queue", "reasoning" };
                    Memory.Insert(0, new MemoryRecord
                    {
                        Type = "queue_output",
                        Source = inferenceSource,
                        Weight = output.Confidence,
                        Recency = DateTimeOffset.UtcNow,
                        Tags = memoryTags,
                        Value = $"{output.Summary} | {output.NextAction}"
                    });
                    TrimMemory();
                }
                var isSpecialDeterministicRoute = output.Model is "atlas-openalex-research-v1" or "atlas-local-sync-v1" or "atlas-recovery-support-v1";
                if (!isCodeAgentTask && !usedSharedBackend && llmOutput is null && _llmClient.Enabled && !isSpecialDeterministicRoute)
                {
                    var fallbackLabel = output.Model.Contains("rust", StringComparison.OrdinalIgnoreCase)
                        ? "Rust local reasoner fallback"
                        : "deterministic managed fallback";
                    AddSystemOutput($"Local LLM unavailable for this prompt. {fallbackLabel} was used. {_llmClient.RuntimeFailureHint()}");
                }
                if (output.Model == "atlas-openalex-research-v1")
                {
                    AddSystemOutput("Academic discovery completed. Open top DOI/PDF sources and run citation expansion.");
                }
                else if (output.Model == "atlas-local-sync-v1")
                {
                    AddSystemOutput("Local sync blueprint generated. Start with device pairing and certificate trust setup.");
                }
                else if (output.Model == "atlas-recovery-support-v1")
                {
                    AddSystemOutput("Recovery support plan generated. Execute the first guardrail immediately.");
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

    private static string FirstNonEmptyLine(string text, int maxChars)
    {
        var first = text
            .Split('\n')
            .Select(line => line.Trim())
            .FirstOrDefault(line => line.Length > 0);
        var resolved = string.IsNullOrWhiteSpace(first) ? text.Trim() : first;
        if (resolved.Length <= maxChars)
        {
            return resolved;
        }
        return resolved[..Math.Max(0, maxChars)].Trim();
    }

    private static string DeriveBackendNextAction(string reply, int maxChars)
    {
        var candidate = reply
            .Split('\n')
            .Select(line => line.Trim().TrimStart('-', '*', '•', ' '))
            .FirstOrDefault(line =>
                line.Length >= 12 &&
                (line.Contains("next", StringComparison.OrdinalIgnoreCase)
                    || line.Contains("action", StringComparison.OrdinalIgnoreCase)
                    || line.Contains("step", StringComparison.OrdinalIgnoreCase)));
        var resolved = string.IsNullOrWhiteSpace(candidate)
            ? "Execute the first concrete action from the backend response now."
            : candidate;
        if (resolved.Length <= maxChars)
        {
            return resolved;
        }
        return resolved[..Math.Max(0, maxChars)].Trim();
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

        if (NatureRiskScore >= NatureElevatedThreshold)
        {
            feed.Add(new FeedItem
            {
                Title = "Climate + biodiversity response readiness",
                Summary = "Nature risk is elevated. Keep income execution disciplined so donation capacity for frontline organizations can compound.",
                WhyNow = "Wealth creation and stewardship are linked when environmental risk trends higher.",
                Priority = NatureRiskScore >= NatureCriticalThreshold ? "critical" : "high"
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
        _persistedAuthCookies = _apiClient.ExportAuthCookies().ToList();
        return new AtlasDataEnvelope
        {
            Session = CloneSession(),
            SystemOutput = SystemOutput.ToList(),
            Notes = Notes.ToList(),
            Queue = Queue.ToList(),
            Memory = Memory.ToList(),
            Workspaces = Workspaces.ToList(),
            SurveyAnswers = _surveyAnswers.Select(x => new SurveyAnswer { QuestionId = x.Key, Value = x.Value }).ToList(),
            AdaptiveBusinessQuestions = AdaptiveBusinessQuestions.Select(CloneAdaptiveQuestion).ToList(),
            NatureSignalTiles = NatureSignalTiles.ToList(),
            ApiAuthCookies = _persistedAuthCookies.ToList(),
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
            PrepaidCreditsActive = Session.PrepaidCreditsActive,
            ApiBaseUrl = Session.ApiBaseUrl,
            WorldMonitorUrl = Session.WorldMonitorUrl,
            LanguageCode = Session.LanguageCode,
            DailyPriority = Session.DailyPriority,
            MidTermGoal = Session.MidTermGoal,
            LongTermVision = Session.LongTermVision,
            Blockers = Session.Blockers,
            Mood = Session.Mood,
            Energy = Session.Energy,
            GymToday = Session.GymToday,
            MoneyToday = Session.MoneyToday,
            MemoryOptIn = Session.MemoryOptIn,
            GuidedLearningRuntimeActive = Session.GuidedLearningRuntimeActive,
            AdaptiveBusinessQuestionEngineEnabled = Session.AdaptiveBusinessQuestionEngineEnabled,
            BusinessAutopilotEnabled = Session.BusinessAutopilotEnabled,
            AdaptiveBusinessRuntimeStatusLine = Session.AdaptiveBusinessRuntimeStatusLine,
            QuantumLearningEnabled = Session.QuantumLearningEnabled,
            QuantumLearningStatusLine = Session.QuantumLearningStatusLine,
            QuantumLearningSnapshot = Session.QuantumLearningSnapshot is null
                ? null
                : CloneQuantumSnapshot(Session.QuantumLearningSnapshot),
            LastAdaptiveBusinessQuestionAtUtc = Session.LastAdaptiveBusinessQuestionAtUtc,
            LastBusinessAutopilotAtUtc = Session.LastBusinessAutopilotAtUtc,
            AdaptiveBusinessAutopilotCursor = Session.AdaptiveBusinessAutopilotCursor,
            NatureRiskScore = Session.NatureRiskScore,
            NatureRiskBand = Session.NatureRiskBand,
            NatureAlertSummary = Session.NatureAlertSummary,
            NatureElevatedThreshold = Session.NatureElevatedThreshold,
            NatureCriticalThreshold = Session.NatureCriticalThreshold,
            LastNatureSignalRefreshAtUtc = Session.LastNatureSignalRefreshAtUtc,
            LastNatureAlertNotificationAtUtc = Session.LastNatureAlertNotificationAtUtc,
            LastWealthReminderNotificationAtUtc = Session.LastWealthReminderNotificationAtUtc
        };
    }

    private void HydrateFromEnvelope(AtlasDataEnvelope envelope)
    {
        Session.IsSignedIn = envelope.Session.IsSignedIn;
        Session.Provider = envelope.Session.Provider;
        Session.AccountLabel = envelope.Session.AccountLabel;
        Session.Tier = envelope.Session.Tier;
        Session.PrepaidCreditsActive = envelope.Session.PrepaidCreditsActive;
        Session.ApiBaseUrl = AtlasBackendConfig.ResolveStartupApiBase(envelope.Session.ApiBaseUrl);
        Session.WorldMonitorUrl = string.IsNullOrWhiteSpace(envelope.Session.WorldMonitorUrl)
            ? HostedWorldMonitorUrl
            : envelope.Session.WorldMonitorUrl;
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
        Session.GuidedLearningRuntimeActive = envelope.Session.GuidedLearningRuntimeActive;
        Session.AdaptiveBusinessQuestionEngineEnabled = envelope.Session.AdaptiveBusinessQuestionEngineEnabled;
        Session.BusinessAutopilotEnabled = envelope.Session.BusinessAutopilotEnabled;
        Session.AdaptiveBusinessRuntimeStatusLine = string.IsNullOrWhiteSpace(envelope.Session.AdaptiveBusinessRuntimeStatusLine)
            ? "Adaptive business runtime idle."
            : envelope.Session.AdaptiveBusinessRuntimeStatusLine;
        Session.QuantumLearningEnabled = envelope.Session.QuantumLearningEnabled;
        Session.QuantumLearningStatusLine = string.IsNullOrWhiteSpace(envelope.Session.QuantumLearningStatusLine)
            ? "Quantum learning simulator idle."
            : envelope.Session.QuantumLearningStatusLine;
        Session.QuantumLearningSnapshot = envelope.Session.QuantumLearningSnapshot is null
            ? null
            : CloneQuantumSnapshot(envelope.Session.QuantumLearningSnapshot);
        Session.LastAdaptiveBusinessQuestionAtUtc = envelope.Session.LastAdaptiveBusinessQuestionAtUtc;
        Session.LastBusinessAutopilotAtUtc = envelope.Session.LastBusinessAutopilotAtUtc;
        Session.AdaptiveBusinessAutopilotCursor = Math.Max(0, envelope.Session.AdaptiveBusinessAutopilotCursor);
        Session.NatureRiskScore = envelope.Session.NatureRiskScore;
        Session.NatureRiskBand = string.IsNullOrWhiteSpace(envelope.Session.NatureRiskBand)
            ? "low"
            : envelope.Session.NatureRiskBand;
        Session.NatureAlertSummary = string.IsNullOrWhiteSpace(envelope.Session.NatureAlertSummary)
            ? "Nature monitor initializing."
            : envelope.Session.NatureAlertSummary;
        Session.NatureElevatedThreshold = envelope.Session.NatureElevatedThreshold <= 0 ? 45 : envelope.Session.NatureElevatedThreshold;
        Session.NatureCriticalThreshold = envelope.Session.NatureCriticalThreshold <= 0 ? 70 : envelope.Session.NatureCriticalThreshold;
        if (Session.NatureCriticalThreshold <= Session.NatureElevatedThreshold)
        {
            Session.NatureCriticalThreshold = Math.Min(99, Session.NatureElevatedThreshold + 10);
        }
        Session.LastNatureSignalRefreshAtUtc = envelope.Session.LastNatureSignalRefreshAtUtc;
        Session.LastNatureAlertNotificationAtUtc = envelope.Session.LastNatureAlertNotificationAtUtc;
        Session.LastWealthReminderNotificationAtUtc = envelope.Session.LastWealthReminderNotificationAtUtc;
        NatureRiskScore = Session.NatureRiskScore;
        NatureRiskBand = Session.NatureRiskBand;
        NatureAlertSummary = Session.NatureAlertSummary;
        NatureElevatedThreshold = Session.NatureElevatedThreshold;
        NatureCriticalThreshold = Session.NatureCriticalThreshold;
        _lastNatureSignalRefreshAtUtc = Session.LastNatureSignalRefreshAtUtc;
        _lastNatureAlertNotificationAtUtc = Session.LastNatureAlertNotificationAtUtc;
        _lastWealthReminderNotificationAtUtc = Session.LastWealthReminderNotificationAtUtc;
        var nowUtc = DateTimeOffset.UtcNow;
        _persistedAuthCookies = (envelope.ApiAuthCookies ?? [])
            .Where(cookie =>
                !string.IsNullOrWhiteSpace(cookie.Name)
                && !string.IsNullOrWhiteSpace(cookie.Domain)
                && (cookie.ExpiresAtUtc is null || cookie.ExpiresAtUtc > nowUtc))
            .ToList();

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
        var validQuestionIds = _surveyQuestions
            .Select(question => question.Id)
            .ToHashSet(StringComparer.Ordinal);
        foreach (var answer in envelope.SurveyAnswers ?? [])
        {
            if (string.IsNullOrWhiteSpace(answer.QuestionId) ||
                string.IsNullOrWhiteSpace(answer.Value) ||
                !validQuestionIds.Contains(answer.QuestionId))
            {
                continue;
            }
            _surveyAnswers[answer.QuestionId] = answer.Value;
        }

        AdaptiveBusinessQuestions.Clear();
        foreach (var question in (envelope.AdaptiveBusinessQuestions ?? [])
                     .OrderByDescending(item => item.GeneratedAt)
                     .Take(AdaptiveQuestionHistoryCap))
        {
            AdaptiveBusinessQuestions.Add(CloneAdaptiveQuestion(question));
        }
        NotifyAdaptiveQuestionStateChanged();

        NatureSignalTiles.Clear();
        foreach (var tile in (envelope.NatureSignalTiles ?? [])
                     .OrderByDescending(item => item.UpdatedAt)
                     .Take(8))
        {
            NatureSignalTiles.Add(tile);
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
        var globalRegions = new[]
        {
            Choice("north_america", "North America"),
            Choice("south_america", "South America"),
            Choice("europe", "Europe"),
            Choice("middle_east", "Middle East"),
            Choice("africa", "Africa"),
            Choice("south_asia", "South Asia"),
            Choice("east_asia", "East Asia"),
            Choice("southeast_asia", "Southeast Asia"),
            Choice("oceania", "Oceania")
        };

        return
        [
            ChoiceQuestion("daily_pressure", "How intense is your current day-to-day pressure?", "Current state (what is).",
                Choice("low", "Low"),
                Choice("medium", "Medium"),
                Choice("high", "High")),
            ChoiceQuestion("work_hours", "How many hours do you typically work per day?", "Current state (what is).",
                Choice("under_6", "Under 6"),
                Choice("6_8", "6-8"),
                Choice("8_10", "8-10"),
                Choice("10_plus", "10+")),
            ChoiceQuestion("stress_trigger", "What most often triggers stress in your routine?", "Current state (what is).",
                Choice("uncertainty", "Uncertainty"),
                Choice("money", "Money pressure"),
                Choice("time_overload", "Time overload"),
                Choice("interpersonal", "Interpersonal conflict"),
                Choice("health", "Health load")),
            ChoiceQuestion("drive_now", "Do you currently drive?", "Current state (what is).",
                Choice("yes", "Yes"),
                Choice("no", "No")),
            ChoiceQuestion("drive_frequency", "How often do you drive?", "Current state (what is).",
                Choice("daily", "Daily"),
                Choice("several_weekly", "Several times per week"),
                Choice("weekly", "About weekly"),
                Choice("monthly", "A few times per month"),
                Choice("rarely", "Rarely")),
            ChoiceQuestion("drive_distance_yearly", "About how far do you drive per year?", "Current state (what is).",
                Choice("under_5000_km", "Under 5,000 km"),
                Choice("5000_15000_km", "5,000-15,000 km"),
                Choice("15000_30000_km", "15,000-30,000 km"),
                Choice("30000_50000_km", "30,000-50,000 km"),
                Choice("50000_plus_km", "50,000+ km")),
            ChoiceQuestion("public_transport_usage", "Do you use public transportation?", "Current state (what is).",
                Choice("yes", "Yes"),
                Choice("no", "No")),
            ChoiceQuestion("public_transport_frequency", "How often do you use public transportation?", "Current state (what is).",
                Choice("daily", "Daily"),
                Choice("several_weekly", "Several times per week"),
                Choice("weekly", "About weekly"),
                Choice("monthly", "A few times per month"),
                Choice("rarely", "Rarely")),
            ChoiceQuestion("public_transport_affordability", "Do you ever have difficulty affording public transportation?", "Current state (what is).",
                Choice("often", "Often"),
                Choice("sometimes", "Sometimes"),
                Choice("rarely", "Rarely"),
                Choice("never", "Never")),
            ChoiceQuestion("financial_struggle_self", "Are you currently facing financial struggles in your own life?", "Current state (what is).",
                Choice("yes", "Yes"),
                Choice("no", "No")),
            ChoiceQuestion("financial_struggle_family", "Are close family members currently facing financial struggles?", "Current state (what is).",
                Choice("yes", "Yes"),
                Choice("no", "No")),
            ChoiceQuestion("financial_state_wanted", "What financial state do you want to reach over the next 12 months?", "Target state (what is wanted).",
                Choice("stability", "Basic stability"),
                Choice("debt_reduction", "Debt reduction"),
                Choice("emergency_buffer", "Emergency buffer"),
                Choice("income_growth", "Stronger income growth"),
                Choice("family_support", "Support family finances better")),
            ChoiceQuestion("travel_state_wanted", "What travel state do you want over the next 12 months?", "Target state (what is wanted).",
                Choice("more_flexible", "More flexibility"),
                Choice("lower_cost", "Lower travel cost"),
                Choice("higher_reliability", "Higher reliability"),
                Choice("less_stress", "Less stress"),
                Choice("broader_access", "Broader regional access")),
            MultiQuestion("rv_intent_multi", "For RV/van, what is wanted?", "Select all that apply (wanted state).",
                Choice("buy", "Buy"),
                Choice("rent", "Rent")),
            MultiQuestion("car_intent_multi", "For cars, what is wanted?", "Select all that apply (wanted state).",
                Choice("buy", "Buy"),
                Choice("rent", "Rent")),
            MultiQuestion("home_intent_multi", "For homes, what is wanted?", "Select all that apply (wanted state).",
                Choice("buy", "Buy"),
                Choice("rent", "Rent")),
            MultiQuestion("apartment_intent_multi", "For apartments, what is wanted?", "Select all that apply (wanted state).",
                Choice("buy", "Buy"),
                Choice("rent", "Rent")),
            MultiQuestion("hotel_intent_multi", "For hotels, what is wanted?", "Select all that apply (wanted state).",
                Choice("buy", "Buy"),
                Choice("rent", "Rent")),
            MultiQuestion("rv_regions_multi", "Which regions matter for RV/van travel?", "Select all that apply.", globalRegions),
            MultiQuestion("car_regions_multi", "Which regions matter for car travel?", "Select all that apply.", globalRegions),
            MultiQuestion("accommodation_regions_multi", "Which regions matter for homes/apartments/hotels?", "Select all that apply.", globalRegions),
            ChoiceQuestion("income_cadence", "How regular is your income right now?", "Current state (what is).",
                Choice("none", "No regular income"),
                Choice("sometimes", "Sometimes"),
                Choice("regularly", "Regularly")),
            ChoiceQuestion("income_gap_primary", "What most explains why your income is below what you need or want?", "Primary economic blocker diagnosis.",
                Choice("pipeline_volume", "Not enough qualified opportunities"),
                Choice("conversion_close", "Closing/conversion is weak"),
                Choice("pricing_positioning", "Pricing/positioning is too low"),
                Choice("skill_capital_gap", "Skills or credibility gap"),
                Choice("execution_consistency", "Inconsistent execution"),
                Choice("cognitive_drain", "Mental overload and low cognitive energy"),
                Choice("money_leak", "Spending/leakage destroys progress"),
                Choice("unclear_strategy", "No clear strategy or route")),
            ChoiceQuestion("brain_sleep_quality", "How has your sleep quality been over the last 14 days?", "Current state (what is).",
                Choice("restorative", "Restorative most nights"),
                Choice("inconsistent", "Inconsistent"),
                Choice("poor", "Poor"),
                Choice("broken", "Fragmented / broken")),
            ChoiceQuestion("brain_focus_stability", "How stable is your focus during high-value work blocks?", "Current state (what is).",
                Choice("stable_90_plus", "Stable for 90+ minutes"),
                Choice("stable_45_90", "Stable for 45-90 minutes"),
                Choice("variable", "Variable day to day"),
                Choice("fragile", "Breaks quickly")),
            ChoiceQuestion("brain_stress_regulation", "After a stress spike, how quickly do you return to effective execution?", "Current state (what is).",
                Choice("fast_recovery", "Within 10-20 minutes"),
                Choice("moderate_recovery", "Within 1-2 hours"),
                Choice("slow_recovery", "Most of the day"),
                Choice("rollover", "Carries into the next day")),
            ChoiceQuestion("employment_state", "Which option best describes your current employment status?", "Current state (what is).",
                Choice("employed_full_time", "Employed full-time"),
                Choice("employed_part_time", "Employed part-time"),
                Choice("freelance_consultant", "Freelance/consulting"),
                Choice("between_roles", "Between roles"),
                Choice("student_transition", "Student/transition"),
                Choice("both_employee_and_business", "Employee + business owner")),
            ChoiceQuestion("business_state", "Which option best describes your current business status?", "Current state (what is).",
                Choice("no_business", "No business now"),
                Choice("idea_stage", "Idea stage"),
                Choice("pre_revenue", "Built but pre-revenue"),
                Choice("early_revenue", "Early revenue"),
                Choice("recurring_revenue", "Recurring revenue"),
                Choice("scaling_team", "Scaling team")),
            ChoiceQuestion("growth_priority", "What should Atlas prioritize first for your wealth growth?", "Target state (what is wanted).",
                Choice("climb_job_ladder", "Promotion and salary growth"),
                Choice("grow_business_customer_base", "Customer growth in business"),
                Choice("hybrid_growth", "Both in parallel"),
                Choice("stabilize_income", "Stabilize income first")),
            ChoiceQuestion("high_paying_job_track", "If job ladder is in play, choose your high-paying track", "Target state (what is wanted).",
                Choice("engineering", "Engineering"),
                Choice("product", "Product"),
                Choice("ai_software", "AI / Software"),
                Choice("sales", "Sales"),
                Choice("finance", "Finance"),
                Choice("healthcare", "Healthcare"),
                Choice("logistics", "Logistics"),
                Choice("real_estate", "Real estate"),
                Choice("trades", "Skilled trades"),
                Choice("media_revenue", "Media/creator economy"),
                Choice("none", "Not focused on jobs now")),
            ChoiceQuestion("business_model_focus", "If building a business, which model should Atlas optimize?", "Target state (what is wanted).",
                Choice("agency", "Agency"),
                Choice("saas", "B2B SaaS"),
                Choice("ecommerce", "E-commerce"),
                Choice("local_service", "Local service business"),
                Choice("education_products", "Education products"),
                Choice("marketplace", "Marketplace"),
                Choice("not_now", "Not now")),
            ChoiceQuestion("monetizable_skill_stack", "Which monetizable skill stack should Atlas train most aggressively?", "Target state (what is wanted).",
                Choice("ai_automation", "AI automation"),
                Choice("problem_solving", "Problem-solving systems"),
                Choice("copywriting", "Copywriting/positioning"),
                Choice("operations_systems", "Operations systems"),
                Choice("analytics", "Analytics")),
            ChoiceQuestion("weekly_revenue_reps", "How many direct revenue actions do you run each week?", "Current state (what is).",
                Choice("0", "0"),
                Choice("1_2", "1-2"),
                Choice("3_5", "3-5"),
                Choice("6_plus", "6+")),
            ChoiceQuestion("charity_goal", "Include a giving target in planning?", "Target state (what is wanted).",
                Choice("yes", "Yes"),
                Choice("later", "Later"),
                Choice("no", "No")),
            ChoiceQuestion("feedback_optin", "Allow anonymized product feedback suggestions?", "Team improvement loop control.",
                Choice("yes", "Yes"),
                Choice("ask_each", "Ask each time"),
                Choice("no", "No")),
            ChoiceQuestion("cloud_tier_interest", "Interested in future cloud compute tier?", "Upgrade readiness.",
                Choice("yes", "Yes"),
                Choice("maybe", "Maybe"),
                Choice("no", "No")),
            ChoiceQuestion("execution_commitment", "Can you commit to one daily action cadence?", "Final readiness gate.",
                Choice("yes", "Yes, daily"),
                Choice("weekly", "Weekly only"),
                Choice("not_ready", "Not ready")),
        ];
    }

    private static SurveyQuestion ChoiceQuestion(string id, string title, string description, params SurveyChoice[] choices)
    {
        return new SurveyQuestion
        {
            Id = id,
            Title = title,
            Description = description,
            Kind = "choice",
            Choices = EnsureUnsureChoice(choices)
        };
    }

    private static SurveyQuestion MultiQuestion(string id, string title, string description, params SurveyChoice[] choices)
    {
        return new SurveyQuestion
        {
            Id = id,
            Title = title,
            Description = description,
            Kind = "multi_choice",
            Choices = EnsureUnsureChoice(choices)
        };
    }

    private static List<SurveyChoice> EnsureUnsureChoice(IEnumerable<SurveyChoice> choices)
    {
        var normalized = choices.ToList();
        if (normalized.All(choice => !string.Equals(choice.Value, "not_sure", StringComparison.Ordinal)))
        {
            normalized.Add(Choice("not_sure", "I don't know / I'm not sure"));
        }
        return normalized;
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
        _adaptiveRuntimeLock.Dispose();
    }
}
