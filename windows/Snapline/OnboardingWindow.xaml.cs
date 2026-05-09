using System;
using System.IO;
using System.Linq;
using System.Windows;
using Microsoft.Win32;

namespace Snapline;

public partial class OnboardingWindow : Window
{
    private int _step = 1;
    private string? _selectedExePath;
    private string? _selectedExeName;

    public OnboardingWindow()
    {
        InitializeComponent();

        var current = Settings.Current;
        _selectedExePath = current.TargetAppPath;
        _selectedExeName = current.TargetAppName;
        SingleShotBox.Hotkey = current.SingleShotHotkey;
        MultiShotBox.Hotkey = current.MultiShotHotkey;
        if (!current.SingleShotHotkey.IsBound)
        {
            SingleShotBox.Hotkey = new HotkeyDef
            {
                Modifiers = (uint)(HotkeyManager.Mod.Control | HotkeyManager.Mod.Shift),
                VirtualKey = 0x39, // '9'
            };
        }
        if (!current.MultiShotHotkey.IsBound)
        {
            MultiShotBox.Hotkey = new HotkeyDef
            {
                Modifiers = (uint)(HotkeyManager.Mod.Control | HotkeyManager.Mod.Alt | HotkeyManager.Mod.Shift),
                VirtualKey = 0x39,
            };
        }

        PopulateRunningApps();
        UpdateTargetLabel();
    }

    private void PopulateRunningApps()
    {
        var candidates = TargetAppPicker.ListRunning();
        TargetCombo.ItemsSource = candidates;
        TargetCombo.DisplayMemberPath = nameof(TargetAppCandidate.DisplayName);
        TargetCombo.SelectionChanged += (_, _) =>
        {
            if (TargetCombo.SelectedItem is TargetAppCandidate c)
            {
                _selectedExePath = c.ExePath;
                _selectedExeName = c.DisplayName;
                UpdateTargetLabel();
            }
        };
        if (!string.IsNullOrEmpty(_selectedExePath))
        {
            var match = candidates.FirstOrDefault(c => string.Equals(c.ExePath, _selectedExePath, StringComparison.OrdinalIgnoreCase));
            if (match != null) TargetCombo.SelectedItem = match;
        }
    }

    private void BrowseButton_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Title = "Pick target app",
            Filter = "Applications (*.exe)|*.exe",
            InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
        };
        if (dlg.ShowDialog() == true)
        {
            _selectedExePath = dlg.FileName;
            _selectedExeName = Path.GetFileNameWithoutExtension(dlg.FileName);
            UpdateTargetLabel();
        }
    }

    private void UpdateTargetLabel()
    {
        TargetSelectedLabel.Text = string.IsNullOrEmpty(_selectedExePath)
            ? "No target app selected."
            : $"Selected: {_selectedExeName}  ({_selectedExePath})";
    }

    private void BackButton_Click(object sender, RoutedEventArgs e)
    {
        if (_step > 1) ShowStep(_step - 1);
    }

    private void NextButton_Click(object sender, RoutedEventArgs e)
    {
        if (_step == 2 && string.IsNullOrEmpty(_selectedExePath))
        {
            MessageBox.Show(this, "Pick a target app or browse for an .exe to continue.", "Snapline", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (_step == 3)
        {
            if (!SingleShotBox.Hotkey.IsBound || !MultiShotBox.Hotkey.IsBound)
            {
                MessageBox.Show(this, "Bind both hotkeys to continue. Click each box and press a key combination.", "Snapline", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            Finish();
            return;
        }
        ShowStep(_step + 1);
    }

    private void ShowStep(int step)
    {
        _step = step;
        Step1Welcome.Visibility = step == 1 ? Visibility.Visible : Visibility.Collapsed;
        Step2Target.Visibility = step == 2 ? Visibility.Visible : Visibility.Collapsed;
        Step3Hotkeys.Visibility = step == 3 ? Visibility.Visible : Visibility.Collapsed;
        StepIndicator.Text = $"Step {step} of 3";
        BackButton.IsEnabled = step > 1;
        NextButton.Content = step == 3 ? "Done" : "Next";
    }

    private void Finish()
    {
        var s = new Settings
        {
            TargetAppPath = _selectedExePath,
            TargetAppName = _selectedExeName,
            SingleShotHotkey = SingleShotBox.Hotkey,
            MultiShotHotkey = MultiShotBox.Hotkey,
            PasteShortcut = Settings.Current.PasteShortcut,
            HasOnboarded = true,
        };
        s.Save();
        Close();
    }
}
