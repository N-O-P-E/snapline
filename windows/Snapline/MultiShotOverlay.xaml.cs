using System.Windows;

namespace Snapline;

public partial class MultiShotOverlay : Window
{
    public MultiShotOverlay()
    {
        InitializeComponent();
        Loaded += (_, _) => PositionTopRight();
    }

    public void SetCount(int count)
    {
        TitleText.Text = count == 1
            ? "Multi-shot — 1 captured"
            : $"Multi-shot — {count} captured";
    }

    public void SetHint(string text) => HintText.Text = text;

    private void PositionTopRight()
    {
        var work = SystemParameters.WorkArea;
        Left = work.Right - ActualWidth - 24;
        Top = work.Top + 24;
    }
}
