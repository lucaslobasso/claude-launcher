# Pester 5:  Invoke-Pester tests
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\launcher-lib.ps1')
}

Describe 'Split-ClaudeArgs' {
    It 'splits on spaces' {
        @(Split-ClaudeArgs 'agents --permission-mode plan') | Should -Be @('agents', '--permission-mode', 'plan')
    }
    It 'keeps quoted phrases together' {
        @(Split-ClaudeArgs 'agents --append-system-prompt "be brief" --x ''a b''') |
            Should -Be @('agents', '--append-system-prompt', 'be brief', '--x', 'a b')
    }
    It 'keeps backslashes in paths' {
        Split-ClaudeArgs '--add-dir "C:\My Code\repo" D:\x' | Should -Be @('--add-dir', 'C:\My Code\repo', 'D:\x')
    }
    It 'gives nothing for an empty line' {
        @(Split-ClaudeArgs '').Count | Should -Be 0
        @(Split-ClaudeArgs '   ').Count | Should -Be 0
    }
}

Describe 'Read-LauncherSettings' {
    BeforeEach { $file = Join-Path $TestDrive 'launcher.json' }

    It 'gives the defaults without a file' {
        $s = Read-LauncherSettings (Join-Path $TestDrive 'none.json')
        $s.claudeArgs | Should -Be 'agents'
        $s.folder | Should -Be '%USERPROFILE%'
        $s.keepShellOpen | Should -BeFalse
    }
    It 'keeps an empty claudeArgs (a plain claude session)' {
        Set-Content $file '{ "claudeArgs": "" }'
        (Read-LauncherSettings $file).claudeArgs | Should -Be ''
    }
    It 'fills in keys the file leaves out' {
        Set-Content $file '{ "folder": "D:\\code" }'
        $s = Read-LauncherSettings $file
        $s.folder | Should -Be 'D:\code'
        $s.claudeArgs | Should -Be 'agents'
    }
    It 'falls back to the defaults when the file does not parse' {
        Set-Content $file '{ not json'
        (Read-LauncherSettings $file -WarningAction SilentlyContinue).claudeArgs | Should -Be 'agents'
    }
    It 'round-trips through Write-LauncherSettings' {
        $s = Read-LauncherSettings $file
        $s.claudeArgs = 'agents --permission-mode plan'
        $s.keepShellOpen = $true
        Write-LauncherSettings $file $s
        $back = Read-LauncherSettings $file
        $back.claudeArgs | Should -Be 'agents --permission-mode plan'
        $back.keepShellOpen | Should -BeTrue
    }
}

Describe 'Update-TerminalProfileEntries' {
    BeforeAll {
        $guid = $LauncherProfileGuid
        function New-WtSettings([bool]$Elevate, [object[]]$List) {
            @{ profiles = @{ defaults = @{ elevate = $Elevate }; list = $List } }
        }
    }

    It 'keeps the GUID in sync with ClaudeLauncher.cs' {
        Get-Content -Raw (Join-Path $PSScriptRoot '..\src\ClaudeLauncher.cs') | Should -Match ([regex]::Escape("ProfileGuid = `"$guid`""))
    }
    It 'adds "elevate": false when every profile runs as admin' {
        $s = New-WtSettings $true @(@{ guid = '{other}'; name = 'PowerShell' })
        Update-TerminalProfileEntries $s $guid 'Claude' | Should -BeTrue
        $mine = $s.profiles.list | Where-Object { $_.guid -eq $guid }
        $mine.elevate | Should -BeFalse
        $s.profiles.list.Count | Should -Be 2
    }
    It 'fixes an existing entry: elevate, and a name from an earlier -ShortcutName' {
        $s = New-WtSettings $true @(@{ guid = $guid; source = 'ClaudeLauncher'; name = 'Claude' })
        Update-TerminalProfileEntries $s $guid 'Claude (launcher)' | Should -BeTrue
        $s.profiles.list[0].elevate | Should -BeFalse
        $s.profiles.list[0].name | Should -Be 'Claude (launcher)'
    }
    It 'drops entries left from the profile under another GUID' {
        $s = New-WtSettings $false @(
            @{ guid = '{old}'; source = 'ClaudeLauncher'; name = 'Claude (launcher)' },
            @{ guid = '{other}'; name = 'PowerShell' })
        Update-TerminalProfileEntries $s $guid 'Claude (launcher)' | Should -BeTrue
        @($s.profiles.list).Count | Should -Be 1
        $s.profiles.list[0].guid | Should -Be '{other}'
    }
    It 'changes nothing when nothing overrides the fragment' {
        $s = New-WtSettings $false @(@{ guid = $guid; source = 'ClaudeLauncher'; name = 'Claude'; hidden = $false })
        Update-TerminalProfileEntries $s $guid 'Claude' | Should -BeFalse
        $s.profiles.list[0].Contains('elevate') | Should -BeFalse
    }
    It 'leaves the old array form of "profiles" alone' {
        Update-TerminalProfileEntries @{ profiles = @(@{ name = 'x' }) } $guid 'Claude' | Should -BeFalse
    }
}

Describe 'Find-Tool' {
    It 'prefers an existing path' {
        $f = Join-Path $TestDrive 'tool.exe'; Set-Content $f ''
        Find-Tool @('Z:\nope.exe', $f) @('definitely-not-a-command') | Should -Be $f
    }
    It 'falls back to PATH, then $null' {
        Find-Tool @('Z:\nope.exe') @('pwsh') | Should -Not -BeNullOrEmpty
        Find-Tool @('Z:\nope.exe') @('definitely-not-a-command') | Should -BeNullOrEmpty
    }
}
