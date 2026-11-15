@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',                       # these are interactive installer scripts
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSingularNouns',
        'PSAvoidUsingPositionalParameters',
        'PSAvoidUsingEmptyCatchBlock',                 # the empty catches are deliberate (best-effort logging, parsing)
        'PSUseDeclaredVarsMoreThanAssignments'         # $LauncherVersion and Pester's BeforeEach variables are used elsewhere
    )
}
