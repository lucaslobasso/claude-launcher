// ClaudeLauncher.exe: opens Claude Code in Windows Terminal with Claude's own taskbar icon and button.
// It starts `wt.exe -w new -p <profile>`, watches for the new Terminal window being created and labels it
// (own AppUserModelID + claude.exe icon) before it is shown, so no Terminal button flashes on the taskbar.
// Usage: ClaudeLauncher.exe [Terminal profile name, default "Claude"]. Built and installed by install.ps1.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

static class ClaudeLauncher
{
    const string Aumid = "ClaudeLauncher.WindowsTerminal"; // keep in sync with install.ps1
    const string TerminalClass = "CASCADIA_HOSTING_WINDOW_CLASS";
    const uint EVENT_OBJECT_CREATE = 0x8000, EVENT_OBJECT_SHOW = 0x8002;
    const uint WINEVENT_OUTOFCONTEXT = 0, WINEVENT_SKIPOWNPROCESS = 2;
    const uint WM_SETICON = 0x80, WM_QUIT = 0x12;
    const int TimeoutMs = 10000;

    static readonly string Home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    static readonly string ClaudeExe = Path.Combine(Home, @".local\bin\claude.exe");
    static readonly string SelfExe = Process.GetCurrentProcess().MainModule.FileName;
    static string IconFile; // claude.exe when installed in the usual place, otherwise this launcher
    static string Profile = "Claude";

    static readonly HashSet<IntPtr> existing = new HashSet<IntPtr>();
    static IntPtr target = IntPtr.Zero;
    static WinEventProc callback; // kept alive for the hook's lifetime
    static uint mainThread;
    static Log log;

    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length > 0 && args[0].Trim().Length > 0) Profile = args[0].Trim();
        IconFile = File.Exists(ClaudeExe) ? ClaudeExe : SelfExe;
        log = new Log(Path.Combine(Path.GetDirectoryName(SelfExe), "ClaudeLauncher.log"));
        mainThread = GetCurrentThreadId();

        IntPtr h = IntPtr.Zero;
        while ((h = FindWindowEx(IntPtr.Zero, h, TerminalClass, null)) != IntPtr.Zero) existing.Add(h);

        callback = OnWinEvent;
        IntPtr hook = SetWinEventHook(EVENT_OBJECT_CREATE, EVENT_OBJECT_SHOW, IntPtr.Zero, callback, 0, 0,
            WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);

        string wt = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\WindowsApps\wt.exe");
        try
        {
            Process.Start(new ProcessStartInfo(wt, "-w new -p \"" + Profile + "\"") { UseShellExecute = true, WorkingDirectory = Home });
        }
        catch (Exception e)
        {
            log.Write("failed to start wt: " + e.Message);
            return 1;
        }

        SetTimer(IntPtr.Zero, IntPtr.Zero, TimeoutMs, null);
        MSG msg;
        while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0)
        {
            if (msg.message == 0x113 && msg.hwnd == IntPtr.Zero) // WM_TIMER (thread timer)
            {
                if (target == IntPtr.Zero) log.Write("timeout: no new Terminal window seen");
                break;
            }
            TranslateMessage(ref msg);
            DispatchMessage(ref msg);
        }
        UnhookWinEvent(hook);
        return target == IntPtr.Zero ? 2 : 0;
    }

    static void OnWinEvent(IntPtr hook, uint evt, IntPtr hwnd, int idObject, int idChild, uint thread, uint time)
    {
        if (hwnd == IntPtr.Zero || idObject != 0 || idChild != 0) return; // OBJID_WINDOW, CHILDID_SELF
        if (target == IntPtr.Zero)
        {
            if (existing.Contains(hwnd) || GetAncestor(hwnd, 2) != hwnd || ClassOf(hwnd) != TerminalClass) return;
            target = hwnd;
            Label(hwnd, evt == EVENT_OBJECT_CREATE ? "create" : "show");
        }
        if (hwnd == target && evt == EVENT_OBJECT_SHOW)
        {
            SetIcon(hwnd); // Terminal may set its own icon while starting up; set ours again once visible
            PostThreadMessage(mainThread, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
        }
    }

    static void Label(IntPtr hwnd, string when)
    {
        try
        {
            IPropertyStore store;
            Marshal.ThrowExceptionForHR(SHGetPropertyStoreForWindow(hwnd, ref IID_IPropertyStore, out store));
            try
            {
                SetString(store, 5, Aumid);                      // System.AppUserModel.ID
                SetString(store, 2, "\"" + SelfExe + "\" \"" + Profile + "\""); // RelaunchCommand
                SetString(store, 4, "Claude");                   // RelaunchDisplayNameResource
                SetString(store, 3, IconFile + ",0");            // RelaunchIconResource
            }
            finally { Marshal.ReleaseComObject(store); }
            SetIcon(hwnd);
            log.Write("labelled window 0x" + hwnd.ToInt64().ToString("X") + " at " + when);
        }
        catch (Exception e) { log.Write("label failed: " + e.Message); }
    }

    static void SetIcon(IntPtr hwnd)
    {
        IntPtr large, small;
        ExtractIconEx(IconFile, 0, out large, out small, 1);
        if (large != IntPtr.Zero) SendMessage(hwnd, WM_SETICON, (IntPtr)1, large);
        if (small != IntPtr.Zero) SendMessage(hwnd, WM_SETICON, (IntPtr)0, small);
    }

    static string ClassOf(IntPtr hwnd)
    {
        var sb = new StringBuilder(256);
        GetClassName(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    static void SetString(IPropertyStore store, uint pid, string value)
    {
        var key = new PROPERTYKEY { fmtid = AppUserModel, pid = pid };
        var pv = new PROPVARIANT { vt = 31, p = Marshal.StringToCoTaskMemUni(value) }; // VT_LPWSTR
        try { Marshal.ThrowExceptionForHR(store.SetValue(ref key, ref pv)); }
        finally { PropVariantClear(ref pv); }
    }

    // Small rolling log next to the exe (kept under ~20 KB), only for diagnosing launches.
    class Log
    {
        readonly string path;
        public Log(string path) { this.path = path; }
        public void Write(string line)
        {
            try
            {
                if (File.Exists(path) && new FileInfo(path).Length > 20000) File.Delete(path);
                File.AppendAllText(path, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + " " + line + Environment.NewLine);
            }
            catch { }
        }
    }

    // ---- interop ----
    delegate void WinEventProc(IntPtr hook, uint evt, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);
    delegate void TimerProc(IntPtr hwnd, uint msg, IntPtr id, uint time);

    [StructLayout(LayoutKind.Sequential)]
    struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int x; public int y; }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct PROPERTYKEY { public Guid fmtid; public uint pid; }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    struct PROPVARIANT { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore
    {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint index, out PROPERTYKEY key);
        [PreserveSig] int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
        [PreserveSig] int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
        [PreserveSig] int Commit();
    }

    static Guid IID_IPropertyStore = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
    static Guid AppUserModel = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");

    [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr module, WinEventProc proc, uint pid, uint tid, uint flags);
    [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("user32.dll")] static extern IntPtr SetTimer(IntPtr hwnd, IntPtr id, uint ms, TimerProc proc);
    [DllImport("user32.dll")] static extern int GetMessage(out MSG msg, IntPtr hwnd, uint min, uint max);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG msg);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref MSG msg);
    [DllImport("user32.dll")] static extern bool PostThreadMessage(uint thread, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder name, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid riid, out IPropertyStore store);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern uint ExtractIconEx(string file, int index, out IntPtr large, out IntPtr small, uint count);
    [DllImport("ole32.dll")] static extern int PropVariantClear(ref PROPVARIANT value);
}
