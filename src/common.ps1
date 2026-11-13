# Shared by install.ps1 / uninstall.ps1: shortcut helpers, including the taskbar ID (AppUserModelID) that lets a
# pinned shortcut share one taskbar button with the window ClaudeLauncher.exe labels.

$LauncherAumid = 'ClaudeLauncher.WindowsTerminal'  # keep in sync with src/ClaudeLauncher.cs

if (-not ('ClaudeLauncherShortcut' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ClaudeLauncherShortcut
{
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

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHGetPropertyStoreFromParsingName(string path, IntPtr bindCtx, int flags, ref Guid riid, out IPropertyStore store);
    [DllImport("ole32.dll")] static extern int PropVariantClear(ref PROPVARIANT value);

    static Guid IID_IPropertyStore = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
    static PROPERTYKEY AumidKey = new PROPERTYKEY { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };

    public static void SetAumid(string lnkPath, string aumid)
    {
        IPropertyStore store;
        Marshal.ThrowExceptionForHR(SHGetPropertyStoreFromParsingName(lnkPath, IntPtr.Zero, 2, ref IID_IPropertyStore, out store)); // GPS_READWRITE
        try
        {
            var key = AumidKey;
            var pv = new PROPVARIANT { vt = 31, p = Marshal.StringToCoTaskMemUni(aumid) }; // VT_LPWSTR
            try { Marshal.ThrowExceptionForHR(store.SetValue(ref key, ref pv)); }
            finally { PropVariantClear(ref pv); }
            Marshal.ThrowExceptionForHR(store.Commit());
        }
        finally { Marshal.ReleaseComObject(store); }
    }

    public static string GetAumid(string lnkPath)
    {
        IPropertyStore store;
        if (SHGetPropertyStoreFromParsingName(lnkPath, IntPtr.Zero, 0, ref IID_IPropertyStore, out store) != 0) return null;
        try
        {
            var key = AumidKey;
            PROPVARIANT pv;
            if (store.GetValue(ref key, out pv) != 0) return null;
            try { return pv.vt == 31 ? Marshal.PtrToStringUni(pv.p) : null; }
            finally { PropVariantClear(ref pv); }
        }
        finally { Marshal.ReleaseComObject(store); }
    }
}
'@
}

function Set-ShortcutAumid([string]$Path, [string]$Aumid) { [ClaudeLauncherShortcut]::SetAumid($Path, $Aumid) }

function New-LauncherShortcut([string]$Path, [string]$Target, [string]$Icon) {
    $shell = New-Object -ComObject WScript.Shell
    $l = $shell.CreateShortcut($Path)
    $l.TargetPath = $Target
    $l.WorkingDirectory = $env:USERPROFILE
    $l.IconLocation = $Icon
    $l.Description = 'Claude Code in Windows Terminal'
    $l.Save()
    Set-ShortcutAumid $Path $LauncherAumid
}

# Shortcuts in a folder that point at the given launcher exe.
function Get-LauncherShortcuts([string]$Dir, [string]$Exe) {
    if (-not (Test-Path $Dir)) { return @() }
    $shell = New-Object -ComObject WScript.Shell
    @(Get-ChildItem $Dir -Filter *.lnk -File | Where-Object { $shell.CreateShortcut($_.FullName).TargetPath -ieq $Exe })
}

function Get-LauncherPins([string]$Exe) {
    Get-LauncherShortcuts (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar') $Exe
}
