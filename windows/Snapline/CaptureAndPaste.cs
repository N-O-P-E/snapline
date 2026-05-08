using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media.Imaging;
using static Snapline.NativeMethods;
using WpfClipboard = System.Windows.Clipboard;
using WinFormsClipboard = System.Windows.Forms.Clipboard;
using WinFormsDataObject = System.Windows.Forms.DataObject;
using WinFormsDataFormats = System.Windows.Forms.DataFormats;
using SDImage = System.Drawing.Image;
using SDBitmap = System.Drawing.Bitmap;
using SDImageFormat = System.Drawing.Imaging.ImageFormat;

namespace Snapline;

public static class CaptureAndPaste
{
    private static readonly string[] SnipHostProcesses = new[]
    {
        "ScreenClippingHost",
        "SnippingTool",
        "ScreenSketch",
        "Snip & Sketch",
    };

    private static int _busy;
    private static volatile bool _multiShotActive;
    private static volatile bool _cancelMultiShot;

    private static LowLevelKeyboardProc? _keyboardHookProc;
    private static IntPtr _keyboardHookHandle = IntPtr.Zero;

    private static readonly object _logLock = new();
    private static readonly string _logPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "Snapline",
        "snapline.log");

    public static void RunSingleShot(Settings s)
    {
        if (Interlocked.Exchange(ref _busy, 1) == 1) { Log("RunSingleShot: busy, ignoring"); return; }
        if (string.IsNullOrEmpty(s.TargetAppPath))
        {
            Interlocked.Exchange(ref _busy, 0);
            ((App)Application.Current).ShowOnboarding();
            return;
        }
        var prev = GetForegroundWindow();
        Log($"RunSingleShot: prev={prev:X}, target={s.TargetAppPath}");
        Task.Run(async () =>
        {
            try { await SingleShotAsync(s, prev).ConfigureAwait(false); }
            catch (Exception ex) { Log($"SingleShot exception: {ex}"); }
            finally { Interlocked.Exchange(ref _busy, 0); }
        });
    }

    public static void RunMultiShot(Settings s)
    {
        if (_multiShotActive)
        {
            Log("RunMultiShot: hotkey re-press during active session => cancel");
            _cancelMultiShot = true;
            KillSnipHosts();
            return;
        }

        if (Interlocked.Exchange(ref _busy, 1) == 1) { Log("RunMultiShot: busy, ignoring"); return; }
        if (string.IsNullOrEmpty(s.TargetAppPath))
        {
            Interlocked.Exchange(ref _busy, 0);
            ((App)Application.Current).ShowOnboarding();
            return;
        }
        var prev = GetForegroundWindow();
        Log($"RunMultiShot: prev={prev:X}, target={s.TargetAppPath}");
        Task.Run(async () =>
        {
            _multiShotActive = true;
            _cancelMultiShot = false;
            try { await MultiShotAsync(s, prev).ConfigureAwait(false); }
            catch (Exception ex) { Log($"MultiShot exception: {ex}"); }
            finally
            {
                _multiShotActive = false;
                _cancelMultiShot = false;
                Interlocked.Exchange(ref _busy, 0);
            }
        });
    }

    // ---------- single shot ----------

    private static async Task SingleShotAsync(Settings s, IntPtr prevForeground)
    {
        await ClearClipboardAsync().ConfigureAwait(false);
        Log("Single: launching ms-screenclip");
        LaunchSnippingTool();

        if (!await PollForClipboardImageAsync(TimeSpan.FromSeconds(60)).ConfigureAwait(false))
        {
            Log("Single: no image captured (timeout or cancelled)");
            return;
        }
        Log("Single: image captured");

        // Materialize the image into PNG bytes BEFORE the snip-tool process exits
        // (modern Snipping Tool can use delayed clipboard rendering).
        var png = await ReadClipboardImageAsPngAsync().ConfigureAwait(false);
        if (png == null) { Log("Single: failed to materialize image"); return; }
        Log($"Single: materialized {png.Length} png bytes");

        // Now safe to kill any snip-tool processes so they don't fight the target for focus.
        KillSnipHosts();
        await Task.Delay(120).ConfigureAwait(false);

        var target = FindOrLaunchTarget(s.TargetAppPath!);
        if (target == IntPtr.Zero) { Log("Single: target not found"); return; }
        Log($"Single: target hwnd={target:X}");

        ActivateWindow(target);
        await Task.Delay(250).ConfigureAwait(false);
        Log($"Single: after activate, fg={GetForegroundWindow():X}");

        // Re-publish the image with full multi-format data so target apps reliably accept it.
        await SetClipboardImageMultiFormatAsync(png).ConfigureAwait(false);
        await Task.Delay(120).ConfigureAwait(false);

        // Click at the input area so Electron / Chromium / etc. focus the actual <textarea>.
        // SetForegroundWindow only focuses the HWND, not the inner HTML element.
        FocusInputArea(target);
        await Task.Delay(80).ConfigureAwait(false);

        SendPaste(ResolvePasteShortcut(s, target));
        Log("Single: Ctrl+V dispatched");
        _ = prevForeground;
    }

    // ---------- multi shot ----------

    private static async Task MultiShotAsync(Settings s, IntPtr prevForeground)
    {
        var pngImages = new List<byte[]>();
        MultiShotOverlay? overlay = null;

        await Application.Current.Dispatcher.InvokeAsync(() =>
        {
            overlay = new MultiShotOverlay();
            overlay.Show();
            overlay.SetCount(0);
            overlay.SetHint("Drag to snip. Esc or Enter to finish.");
        });

        InstallCancelHook();

        try
        {
            while (!_cancelMultiShot)
            {
                await ClearClipboardAsync().ConfigureAwait(false);

                await WaitForHostExitedAsync(TimeSpan.FromSeconds(2)).ConfigureAwait(false);
                if (_cancelMultiShot) break;

                Log("Multi: launching ms-screenclip");
                LaunchSnippingTool();

                var result = await WaitForSnipResultAsync(TimeSpan.FromSeconds(30)).ConfigureAwait(false);
                Log($"Multi: snip result = {result}, cancel={_cancelMultiShot}");
                if (_cancelMultiShot) { KillSnipHosts(); break; }
                if (result != SnipResult.Captured) break;

                var png = await ReadClipboardImageAsPngAsync().ConfigureAwait(false);
                if (png == null) { Log("Multi: failed to materialize"); break; }
                pngImages.Add(png);
                Log($"Multi: collected #{pngImages.Count} ({png.Length} bytes)");

                var localOverlay = overlay;
                var count = pngImages.Count;
                await Application.Current.Dispatcher.InvokeAsync(() => localOverlay?.SetCount(count));
            }
        }
        finally
        {
            UninstallCancelHook();
            await Application.Current.Dispatcher.InvokeAsync(() => overlay?.Close());
        }

        if (pngImages.Count == 0) { Log("Multi: no images collected, nothing to paste"); return; }

        // Make sure the snip tool is gone before we activate the target.
        KillSnipHosts();
        await Task.Delay(150).ConfigureAwait(false);

        await PasteCollectedAsync(s, pngImages, prevForeground).ConfigureAwait(false);
    }

    private static async Task PasteCollectedAsync(Settings s, IReadOnlyList<byte[]> pngs, IntPtr prevForeground)
    {
        Log($"PasteCollected: starting with {pngs.Count} image(s)");
        var target = FindOrLaunchTarget(s.TargetAppPath!);
        if (target == IntPtr.Zero) { Log("PasteCollected: target not found"); return; }

        ActivateWindow(target);
        await Task.Delay(250).ConfigureAwait(false);
        Log($"PasteCollected: target hwnd={target:X}, fg after activate={GetForegroundWindow():X}");

        var paste = ResolvePasteShortcut(s, target);
        for (var i = 0; i < pngs.Count; i++)
        {
            // Mirror single-shot's exact per-paste sequence:
            //   clipboard set -> focus click -> paste
            // Re-focusing per image is necessary because Claude / Slack / Discord shift
            // focus while ingesting each pasted attachment, so paste #2+ would otherwise
            // land outside the textarea.
            await SetClipboardImageMultiFormatAsync(pngs[i]).ConfigureAwait(false);
            await Task.Delay(120).ConfigureAwait(false);

            FocusInputArea(target);
            await Task.Delay(80).ConfigureAwait(false);

            SendPaste(paste);
            Log($"PasteCollected: pasted image #{i + 1}/{pngs.Count}");

            if (i < pngs.Count - 1)
                await Task.Delay(800).ConfigureAwait(false); // give Claude time to ingest
        }

        if (prevForeground != IntPtr.Zero && prevForeground != target)
        {
            await Task.Delay(200).ConfigureAwait(false);
            ActivateWindow(prevForeground);
        }
        Log("PasteCollected: done");
    }

    // ---------- snip lifecycle ----------

    private enum SnipResult { Captured, Cancelled, TimedOut }

    private static async Task<bool> PollForClipboardImageAsync(TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            if (await ClipboardHasImageAsync().ConfigureAwait(false)) return true;
            await Task.Delay(120).ConfigureAwait(false);
        }
        return false;
    }

    private static async Task WaitForHostExitedAsync(TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            if (!HostRunning()) return;
            await Task.Delay(80).ConfigureAwait(false);
        }
    }

    private static async Task<SnipResult> WaitForSnipResultAsync(TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        var sawHost = false;

        while (DateTime.UtcNow < deadline && !_cancelMultiShot)
        {
            if (await ClipboardHasImageAsync().ConfigureAwait(false))
                return SnipResult.Captured;

            var hostRunning = HostRunning();
            if (hostRunning) sawHost = true;
            else if (sawHost)
            {
                await Task.Delay(220).ConfigureAwait(false);
                if (await ClipboardHasImageAsync().ConfigureAwait(false))
                    return SnipResult.Captured;
                return SnipResult.Cancelled;
            }

            await Task.Delay(120).ConfigureAwait(false);
        }
        return _cancelMultiShot ? SnipResult.Cancelled : SnipResult.TimedOut;
    }

    private static bool HostRunning()
    {
        foreach (var name in SnipHostProcesses)
        {
            try { if (Process.GetProcessesByName(name).Length > 0) return true; }
            catch { }
        }
        return false;
    }

    private static void KillSnipHosts()
    {
        foreach (var name in SnipHostProcesses)
        {
            try
            {
                foreach (var p in Process.GetProcessesByName(name))
                {
                    try { p.Kill(true); } catch { }
                    p.Dispose();
                }
            }
            catch { }
        }
    }

    private static void LaunchSnippingTool()
    {
        var psi = new ProcessStartInfo { FileName = "ms-screenclip:", UseShellExecute = true };
        try { Process.Start(psi); }
        catch
        {
            try { Process.Start(new ProcessStartInfo("explorer.exe", "ms-screenclip:") { UseShellExecute = true }); }
            catch { }
        }
    }

    // ---------- clipboard helpers ----------

    private static Task ClearClipboardAsync() => Application.Current.Dispatcher.InvokeAsync(() =>
    {
        try { WpfClipboard.Clear(); } catch { }
    }).Task;

    private static async Task<bool> ClipboardHasImageAsync()
    {
        var has = false;
        await Application.Current.Dispatcher.InvokeAsync(() =>
        {
            try { has = WpfClipboard.ContainsImage(); } catch { has = false; }
        });
        return has;
    }

    private static async Task<byte[]?> ReadClipboardImageAsPngAsync()
    {
        byte[]? bytes = null;
        await Application.Current.Dispatcher.InvokeAsync(() =>
        {
            try
            {
                if (!WpfClipboard.ContainsImage()) return;
                var src = WpfClipboard.GetImage();
                if (src == null) return;
                var encoder = new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(src));
                using var ms = new MemoryStream();
                encoder.Save(ms);
                bytes = ms.ToArray();
            }
            catch (Exception ex) { Log($"ReadClipboard: {ex.Message}"); }
        });
        return bytes;
    }

    private static Task SetClipboardImageMultiFormatAsync(byte[] pngBytes) =>
        Application.Current.Dispatcher.InvokeAsync(() =>
        {
            try
            {
                using var pngSrc = new MemoryStream(pngBytes);
                using var bmp = (SDBitmap)SDImage.FromStream(pngSrc);

                var data = new WinFormsDataObject();
                // CF_BITMAP — covers the most apps.
                data.SetData(WinFormsDataFormats.Bitmap, true, bmp);
                // PNG — what modern apps and browsers prefer.
                data.SetData("PNG", false, new MemoryStream(pngBytes));
                // CF_DIB — fallback for legacy paste targets.
                var dib = ConvertBitmapToDib(bmp);
                if (dib != null) data.SetData(WinFormsDataFormats.Dib, false, new MemoryStream(dib));

                WinFormsClipboard.SetDataObject(data, copy: true);
                Log($"Clipboard set: {pngBytes.Length}b PNG + Bitmap + DIB");
            }
            catch (Exception ex) { Log($"SetClipboard: {ex.Message}"); }
        }).Task;

    private static byte[]? ConvertBitmapToDib(SDBitmap bmp)
    {
        try
        {
            using var ms = new MemoryStream();
            bmp.Save(ms, SDImageFormat.Bmp);
            var bmpBytes = ms.ToArray();
            // BMP file = 14-byte BITMAPFILEHEADER + DIB.
            if (bmpBytes.Length <= 14) return null;
            var dib = new byte[bmpBytes.Length - 14];
            Array.Copy(bmpBytes, 14, dib, 0, dib.Length);
            return dib;
        }
        catch { return null; }
    }

    // ---------- target activation + paste ----------

    private static IntPtr FindOrLaunchTarget(string exePath)
    {
        var found = FindTargetWindow(exePath);
        return found != IntPtr.Zero ? found : LaunchTarget(exePath);
    }

    private static IntPtr FindTargetWindow(string exePath)
    {
        var name = Path.GetFileNameWithoutExtension(exePath);
        try
        {
            foreach (var p in Process.GetProcessesByName(name))
            {
                var hwnd = p.MainWindowHandle;
                if (hwnd != IntPtr.Zero && IsWindowVisible(hwnd)) return hwnd;
            }
        }
        catch { }
        return IntPtr.Zero;
    }

    private static IntPtr LaunchTarget(string exePath)
    {
        try
        {
            var p = Process.Start(new ProcessStartInfo(exePath) { UseShellExecute = true });
            if (p == null) return IntPtr.Zero;
            for (var i = 0; i < 60; i++)
            {
                p.Refresh();
                if (p.MainWindowHandle != IntPtr.Zero) return p.MainWindowHandle;
                Thread.Sleep(100);
            }
        }
        catch { }
        return IntPtr.Zero;
    }

    private static void ActivateWindow(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return;
        if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);

        // Try simple activation first — works when our process still has foreground privilege.
        SetForegroundWindow(hwnd);
        if (GetForegroundWindow() == hwnd) return;

        // Fallback: AttachThreadInput trick.
        var fg = GetForegroundWindow();
        var fgThreadId = fg != IntPtr.Zero ? GetWindowThreadProcessId(fg, out _) : 0u;
        var ourThreadId = GetCurrentThreadId();

        var attached = false;
        if (fgThreadId != 0 && fgThreadId != ourThreadId)
            attached = AttachThreadInput(ourThreadId, fgThreadId, true);

        try
        {
            BringWindowToTop(hwnd);
            SetForegroundWindow(hwnd);
            ShowWindow(hwnd, SW_SHOW);
        }
        finally
        {
            if (attached) AttachThreadInput(ourThreadId, fgThreadId, false);
        }

        if (GetForegroundWindow() != hwnd)
            SwitchToThisWindow(hwnd, true);
    }

    private static void FocusInputArea(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return;
        if (!GetWindowRect(hwnd, out var rect)) return;

        var width = rect.Right - rect.Left;
        var height = rect.Bottom - rect.Top;
        if (width <= 0 || height <= 0) return;

        // Click at horizontal center, 90% of the way down. That's where chat-style apps
        // (Claude desktop, Slack, Discord, etc.) host their textarea.
        var clickX = rect.Left + width / 2;
        var clickY = rect.Top + (int)(height * 0.90);

        var hadCursor = GetCursorPos(out var origCursor);
        SetCursorPos(clickX, clickY);

        var inputs = new[]
        {
            new INPUT { type = INPUT_MOUSE, U = new InputUnion { mi = new MOUSEINPUT { dwFlags = MOUSEEVENTF_LEFTDOWN } } },
            new INPUT { type = INPUT_MOUSE, U = new InputUnion { mi = new MOUSEINPUT { dwFlags = MOUSEEVENTF_LEFTUP   } } },
        };
        SendInput((uint)inputs.Length, inputs, INPUT.Size);

        if (hadCursor) SetCursorPos(origCursor.X, origCursor.Y);
        Log($"FocusInputArea: clicked ({clickX},{clickY}) within ({rect.Left},{rect.Top})-({rect.Right},{rect.Bottom})");
    }

    private static PasteKind ResolvePasteShortcut(Settings s, IntPtr hwnd) => s.PasteShortcut switch
    {
        PasteShortcutMode.AlwaysCtrlV => PasteKind.CtrlV,
        PasteShortcutMode.AlwaysCtrlShiftV => PasteKind.CtrlShiftV,
        _ => PasteKind.CtrlV,
    };

    private enum PasteKind { CtrlV, CtrlShiftV }

    private static void SendPaste(PasteKind kind)
    {
        var inputs = kind == PasteKind.CtrlShiftV
            ? new[]
            {
                Key(VK_CONTROL, down: true),
                Key(VK_SHIFT, down: true),
                Key(VK_V, down: true),
                Key(VK_V, down: false),
                Key(VK_SHIFT, down: false),
                Key(VK_CONTROL, down: false),
            }
            : new[]
            {
                Key(VK_CONTROL, down: true),
                Key(VK_V, down: true),
                Key(VK_V, down: false),
                Key(VK_CONTROL, down: false),
            };
        SendInput((uint)inputs.Length, inputs, INPUT.Size);
    }

    private static INPUT Key(ushort vk, bool down)
    {
        var scan = (ushort)MapVirtualKey(vk, MAPVK_VK_TO_VSC);
        return new INPUT
        {
            type = INPUT_KEYBOARD,
            U = new InputUnion
            {
                ki = new KEYBDINPUT
                {
                    wVk = vk,
                    wScan = scan,
                    dwFlags = down ? 0u : KEYEVENTF_KEYUP,
                    time = 0,
                    dwExtraInfo = IntPtr.Zero,
                },
            },
        };
    }

    // ---------- global Esc/Enter hook ----------

    private static void InstallCancelHook()
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            if (_keyboardHookHandle != IntPtr.Zero) return;
            _keyboardHookProc = OnKeyboardHook;
            using var module = Process.GetCurrentProcess().MainModule;
            var hMod = GetModuleHandle(module?.ModuleName);
            _keyboardHookHandle = SetWindowsHookEx(WH_KEYBOARD_LL, _keyboardHookProc, hMod, 0);
            Log($"Cancel hook installed: handle={_keyboardHookHandle:X}");
        });
    }

    private static void UninstallCancelHook()
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            if (_keyboardHookHandle != IntPtr.Zero)
            {
                UnhookWindowsHookEx(_keyboardHookHandle);
                _keyboardHookHandle = IntPtr.Zero;
            }
            _keyboardHookProc = null;
        });
    }

    private static IntPtr OnKeyboardHook(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var msg = wParam.ToInt32();
            if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
            {
                var info = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
                if (info.vkCode == VK_ESCAPE || info.vkCode == VK_RETURN)
                {
                    _cancelMultiShot = true;
                    Task.Run(KillSnipHosts);
                }
            }
        }
        return CallNextHookEx(_keyboardHookHandle, nCode, wParam, lParam);
    }

    // ---------- diagnostic logging ----------

    private static void Log(string msg)
    {
        try
        {
            var dir = Path.GetDirectoryName(_logPath)!;
            Directory.CreateDirectory(dir);
            lock (_logLock)
            {
                // Keep the log small — truncate if it grows past ~512 KB.
                var fi = new FileInfo(_logPath);
                if (fi.Exists && fi.Length > 512 * 1024)
                {
                    var lines = File.ReadAllLines(_logPath);
                    File.WriteAllLines(_logPath, lines[(lines.Length / 2)..]);
                }
                File.AppendAllText(_logPath, $"{DateTime.Now:HH:mm:ss.fff} {msg}\n");
            }
        }
        catch { }
    }
}
