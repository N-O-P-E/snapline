// WPF + WinForms coexistence: alias every ambiguous type to its WPF counterpart.
// WinForms is only used for NotifyIcon (system tray) and access happens through
// fully-qualified `System.Windows.Forms.*` names in TrayIcon.cs.

global using Application = System.Windows.Application;
global using Clipboard = System.Windows.Clipboard;
global using MessageBox = System.Windows.MessageBox;
global using OpenFileDialog = Microsoft.Win32.OpenFileDialog;
global using Cursors = System.Windows.Input.Cursors;
global using KeyEventArgs = System.Windows.Input.KeyEventArgs;
global using KeyboardFocusChangedEventArgs = System.Windows.Input.KeyboardFocusChangedEventArgs;
global using TextBox = System.Windows.Controls.TextBox;
