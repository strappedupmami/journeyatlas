using AtlasMasaWindows.Models;
using AtlasMasaWindows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using System.Collections;
using Windows.System;

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
        if (sender is FrameworkElement { DataContext: SurveyChoice choice })
        {
            ViewModel.AnswerSurveyChoiceCommand.Execute(choice);
        }
    }

    private void SurveyMultiChoice_Checked(object sender, RoutedEventArgs e)
    {
        if (sender is CheckBox checkBox && checkBox.DataContext is SurveyChoice choice)
        {
            if (string.Equals(choice.Value, "not_sure", StringComparison.Ordinal))
            {
                UpdateSiblingSurveyChoiceSelection(checkBox, sibling =>
                    !string.Equals(sibling.Value, "not_sure", StringComparison.Ordinal), false);
            }
            else
            {
                UpdateSiblingSurveyChoiceSelection(checkBox, sibling =>
                    string.Equals(sibling.Value, "not_sure", StringComparison.Ordinal), false);
            }
            ViewModel.SetSurveyMultiSelection(choice, isSelected: true);
        }
    }

    private void SurveyMultiChoice_Unchecked(object sender, RoutedEventArgs e)
    {
        if (sender is CheckBox checkBox && checkBox.DataContext is SurveyChoice choice)
        {
            ViewModel.SetSurveyMultiSelection(choice, isSelected: false);
        }
    }

    private void AdaptiveOption_Checked(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: string option })
        {
            ViewModel.SetAdaptiveOptionSelection(option, isSelected: true);
        }
    }

    private void AdaptiveOption_Unchecked(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: string option })
        {
            ViewModel.SetAdaptiveOptionSelection(option, isSelected: false);
        }
    }

    private void LocalAiPackButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: LocalAIModelPack pack })
        {
            ViewModel.SelectLocalAiPackCommand.Execute(pack);
        }
    }

    private void LocalAiInstallOption_Checked(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: LocalAIModelInstallOption option })
        {
            ViewModel.SetLocalAiInstallOptionSelection(option.Id, isSelected: true);
        }
    }

    private void LocalAiInstallOption_Unchecked(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: LocalAIModelInstallOption option })
        {
            ViewModel.SetLocalAiInstallOptionSelection(option.Id, isSelected: false);
        }
    }

    private void ConciergePrompt_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != VirtualKey.Enter)
        {
            return;
        }

        if ((InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift) & Windows.UI.Core.CoreVirtualKeyStates.Down) != 0)
        {
            return;
        }

        if (ViewModel.EnqueuePromptCommand.CanExecute(null))
        {
            ViewModel.EnqueuePromptCommand.Execute(null);
            e.Handled = true;
        }
    }

    public Visibility PrepaidLockedVisibility(bool prepaidCreditsActive)
    {
        return prepaidCreditsActive ? Visibility.Collapsed : Visibility.Visible;
    }

    public Visibility ClassicToolsVisibility(bool showClassicCodeTools)
    {
        return showClassicCodeTools ? Visibility.Visible : Visibility.Collapsed;
    }

    public Visibility SurveySingleVisibility(bool isCurrentSurveyQuestionMulti)
    {
        return isCurrentSurveyQuestionMulti ? Visibility.Collapsed : Visibility.Visible;
    }

    public Visibility SurveyMultiVisibility(bool isCurrentSurveyQuestionMulti)
    {
        return isCurrentSurveyQuestionMulti ? Visibility.Visible : Visibility.Collapsed;
    }

    public Visibility RuntimeStripVisibility(bool showRuntimeProgressStrip)
    {
        return showRuntimeProgressStrip ? Visibility.Visible : Visibility.Collapsed;
    }

    public Visibility BoolVisibility(bool value)
    {
        return value ? Visibility.Visible : Visibility.Collapsed;
    }

    public Visibility InverseBoolVisibility(bool value)
    {
        return value ? Visibility.Collapsed : Visibility.Visible;
    }

    public Visibility TextVisibility(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? Visibility.Collapsed : Visibility.Visible;
    }

    public Visibility ListVisibility(IEnumerable? values)
    {
        if (values is null)
        {
            return Visibility.Collapsed;
        }

        foreach (var _ in values)
        {
            return Visibility.Visible;
        }

        return Visibility.Collapsed;
    }

    public Visibility ReasoningVisibility(bool hasReasoningDetails)
    {
        return hasReasoningDetails ? Visibility.Visible : Visibility.Collapsed;
    }

    private static void UpdateSiblingSurveyChoiceSelection(
        CheckBox source,
        Func<SurveyChoice, bool> predicate,
        bool isChecked)
    {
        var itemsControl = FindAncestor<ItemsControl>(source);
        if (itemsControl is null)
        {
            return;
        }

        foreach (var box in EnumerateDescendants<CheckBox>(itemsControl))
        {
            if (ReferenceEquals(box, source))
            {
                continue;
            }
            if (box.DataContext is not SurveyChoice sibling || !predicate(sibling))
            {
                continue;
            }
            box.IsChecked = isChecked;
        }
    }

    private static T? FindAncestor<T>(DependencyObject start) where T : DependencyObject
    {
        DependencyObject? current = start;
        while (current is not null)
        {
            if (current is T typed)
            {
                return typed;
            }
            current = VisualTreeHelper.GetParent(current);
        }
        return null;
    }

    private static IEnumerable<T> EnumerateDescendants<T>(DependencyObject root) where T : DependencyObject
    {
        var childCount = VisualTreeHelper.GetChildrenCount(root);
        for (var i = 0; i < childCount; i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is T typed)
            {
                yield return typed;
            }

            foreach (var nested in EnumerateDescendants<T>(child))
            {
                yield return nested;
            }
        }
    }

}
