# Pester 5:  Invoke-Pester tests
BeforeAll {
    $env:CLAUDE_BUNDLE_TEST = '1'
    . (Join-Path $PSScriptRoot '..\bundle.ps1')
}
AfterAll { Remove-Item Env:CLAUDE_BUNDLE_TEST -ErrorAction SilentlyContinue }

Describe 'Resolve-BundleSelection' {
    It 'gives every tool, apps first, without options' {
        Resolve-BundleSelection | Should -Be @('launcher', 'taskbar', 'boxed-messages', 'statusline', 'limit-revive', 'context-handoff', 'subagentify', 'language-spinner')
    }
    It 'takes -Only as a comma list, keeping install order' {
        Resolve-BundleSelection -Only 'limit-revive,statusline' | Should -Be @('statusline', 'limit-revive')
    }
    It 'takes -Only as an array' {
        Resolve-BundleSelection -Only @('taskbar', 'launcher') | Should -Be @('launcher', 'taskbar')
    }
    It 'drops -Skip names' {
        Resolve-BundleSelection -Skip 'launcher, taskbar' | Should -Be @('boxed-messages', 'statusline', 'limit-revive', 'context-handoff', 'subagentify', 'language-spinner')
    }
    It 'ignores case' {
        Resolve-BundleSelection -Only 'StatusLine' | Should -Be @('statusline')
    }
    It 'refuses unknown names and lists the valid ones' {
        { Resolve-BundleSelection -Only 'statusbar' } | Should -Throw '*Unknown tool: statusbar*launcher*'
    }
}

Describe 'Get-PluginId' {
    It 'is name@repo, as the READMEs install it' {
        Get-PluginId 'statusline' | Should -Be 'statusline@claude-statusline'
        Get-PluginId 'language-spinner' | Should -Be 'language-spinner@claude-language-spinner'
    }
    It 'installs the three claude-sessions plugins from that one marketplace' {
        Get-PluginId 'limit-revive' | Should -Be 'limit-revive@claude-sessions'
        Get-PluginId 'context-handoff' | Should -Be 'context-handoff@claude-sessions'
        Get-PluginId 'subagentify' | Should -Be 'subagentify@claude-sessions'
    }
}

Describe 'Uninstall-BundlePlugin' {
    BeforeEach {
        $script:calls = [Collections.Generic.List[string]]::new()
        Mock Invoke-Claude { $script:calls.Add($args -join ' '); 0 }
    }
    It 'keeps a shared marketplace while another of its plugins is installed' {
        Mock Get-InstalledPlugins { @([pscustomobject]@{ id = 'subagentify@claude-sessions' }) }
        Uninstall-BundlePlugin 'limit-revive' @([pscustomobject]@{ id = 'limit-revive@claude-sessions' }) | Should -BeTrue
        $script:calls | Should -Be @('plugin uninstall limit-revive@claude-sessions')
    }
    It 'removes the marketplace with its last plugin' {
        Mock Get-InstalledPlugins { @() }
        Uninstall-BundlePlugin 'subagentify' @([pscustomobject]@{ id = 'subagentify@claude-sessions' }) | Should -BeTrue
        $script:calls | Should -Be @('plugin uninstall subagentify@claude-sessions', 'plugin marketplace remove claude-sessions')
    }
}