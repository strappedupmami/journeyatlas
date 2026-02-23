using AtlasMasaWindows.Models;
using AtlasMasaWindows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AtlasMasaWindows;

public sealed partial class MainWindow : Window
{
    public MainViewModel ViewModel { get; }

    public MainWindow()
    {
        this.InitializeComponent();
        ViewModel = ((App)Application.Current).ViewModel ?? throw new InvalidOperationException("Main view model was not initialized.");
        DataContext = ViewModel;
    }

    private void SurveyChoiceButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: SurveyChoice choice })
        {
            ViewModel.AnswerSurveyChoiceCommand.Execute(choice);
        }
    }

}
