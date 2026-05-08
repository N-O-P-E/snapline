using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using static Snapline.NativeMethods;

namespace Snapline;

public sealed record TargetAppCandidate(string DisplayName, string ExePath);

public static class TargetAppPicker
{
    public static List<TargetAppCandidate> ListRunning()
    {
        var byExe = new Dictionary<string, TargetAppCandidate>(StringComparer.OrdinalIgnoreCase);
        EnumWindows((hwnd, _) =>
        {
            if (!IsWindowVisible(hwnd)) return true;
            var len = GetWindowTextLength(hwnd);
            if (len == 0) return true;

            var title = new StringBuilder(len + 1);
            GetWindowText(hwnd, title, title.Capacity);
            var titleText = title.ToString();
            if (string.IsNullOrWhiteSpace(titleText)) return true;

            GetWindowThreadProcessId(hwnd, out var pid);
            if (pid == 0) return true;

            try
            {
                using var proc = Process.GetProcessById((int)pid);
                var path = proc.MainModule?.FileName;
                if (string.IsNullOrEmpty(path)) return true;
                if (path.StartsWith(Environment.GetFolderPath(Environment.SpecialFolder.Windows), StringComparison.OrdinalIgnoreCase)
                    && path.IndexOf("explorer.exe", StringComparison.OrdinalIgnoreCase) >= 0) return true;

                if (!byExe.ContainsKey(path))
                {
                    var name = string.IsNullOrEmpty(proc.ProcessName) ? System.IO.Path.GetFileNameWithoutExtension(path) : proc.ProcessName;
                    byExe[path] = new TargetAppCandidate(name, path);
                }
            }
            catch { }
            return true;
        }, IntPtr.Zero);

        return byExe.Values.OrderBy(c => c.DisplayName, StringComparer.OrdinalIgnoreCase).ToList();
    }
}
