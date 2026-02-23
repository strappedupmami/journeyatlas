using Microsoft.UI.Xaml;
using AtlasMasaWindows.ViewModels;

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
}
