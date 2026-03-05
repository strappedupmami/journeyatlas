using Microsoft.UI.Xaml;
using Microsoft.UI.Windowing;
using AtlasMasaWindows.ViewModels;
using WinRT.Interop;

namespace AtlasMasaWindows;

public partial class App : Application
{
    private Window? _window;
    public MainViewModel? ViewModel { get; private set; }

    public App()
    {
        InitializeComponent();
    }

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        var dispatcher = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();
        ViewModel = new MainViewModel(dispatcher);
        await ViewModel.InitializeAsync();
        _window = new MainWindow();
        _window.Closed += Window_Closed;
        _window.Activate();
        DemandFullscreen(_window);
    }

    private async void Window_Closed(object sender, WindowEventArgs args)
    {
        if (_window is not null)
        {
            _window.Closed -= Window_Closed;
        }
        if (ViewModel is not null)
        {
            await ViewModel.DisposeAsync();
        }
    }

    private static void DemandFullscreen(Window window)
    {
        var windowHandle = WindowNative.GetWindowHandle(window);
        if (windowHandle == IntPtr.Zero)
        {
            return;
        }

        var windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(windowHandle);
        var appWindow = AppWindow.GetFromWindowId(windowId);
        if (appWindow is null)
        {
            return;
        }

        try
        {
            appWindow.SetPresenter(AppWindowPresenterKind.FullScreen);
        }
        catch
        {
            if (appWindow.Presenter is OverlappedPresenter overlapped)
            {
                overlapped.Maximize();
            }
        }
    }
}
