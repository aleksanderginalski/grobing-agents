<#
    family-data-guard.tests.ps1 -- tests for the family-data guard (ISSUE-006, written by qa).

    RUN (from the grobing-agents root):
        powershell -NoProfile -File .claude/hooks/tests/family-data-guard.tests.ps1
    Exit code 0 = all passed, 1 = at least one failure (listed at the end).

    WHAT IT DOES
      - builds a throwaway copy of the setup in %TEMP%: three git repos -- agents (with a copy of the
        guard and its own project-config.md), vault, code -- with invented file names only;
      - feeds PreToolUse JSON to the guard, one powershell process per case, as the harness does;
      - runs the exact wrapper command from .claude/settings.json (AC-1);
      - checks THE LIST against .gitignore of the three REAL repos with read-only
        `git check-ignore --no-index`: a type added to the guard but not to .gitignore (or the other
        way round) fails here.
    It never writes into the real Grobing repos. ASCII only, like the guard (PowerShell 5.1).
#>

$ErrorActionPreference = 'Stop'

$TestsDir = Split-Path -Parent $PSCommandPath
$HooksDir = Split-Path -Parent $TestsDir
$RealAgents = Split-Path -Parent (Split-Path -Parent $HooksDir)
$GuardSource = Join-Path $HooksDir 'family-data-guard.ps1'
$SettingsPath = Join-Path $RealAgents '.claude/settings.json'
$RealConfig = Join-Path $RealAgents '.claude/rules/project-config.md'

# THE LIST -- the same as in family-data-guard.ps1 and in the .gitignore block of the three repos.
$DbNames = @('sample.db', 'sample.db-journal', 'sample.db-wal', 'sample.db-shm', 'sample.sqlite', 'sample.sqlite3', 'sample.sqlite-wal')
$BackupNames = @('sample.age', 'sample.tar')
$ExportNames = @('sample.html', 'sample.pdf')
$MediaNames = @('jpg', 'jpeg', 'png', 'heic', 'heif', 'webp', 'gif', 'bmp', 'tif', 'tiff', 'dng', 'mp4', 'mov') | ForEach-Object { "sample.$_" }
$UiImageNames = @('png', 'jpg', 'jpeg', 'gif', 'webp') | ForEach-Object { "ic_sample.$_" }
$RootFolders = @('exports', 'backups', 'family-data', 'real-data')
$AllListed = $DbNames + $BackupNames + $ExportNames + $MediaNames

$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Count = 0

function Assert-True([bool]$Condition, [string]$Name, [string]$Detail = '') {
    $script:Count++
    if ($Condition) { Write-Host "  ok    $Name" }
    else {
        Write-Host "  FAIL  $Name -- $Detail"
        $script:Failures.Add("$Name -- $Detail")
    }
}

function Invoke-Process([string]$File, [string]$Arguments, [string]$StdIn = '', [hashtable]$Env = @{}) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = $Env[$k] }
    $proc = [System.Diagnostics.Process]::Start($psi)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($StdIn)
    $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $proc.StandardInput.Close()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $out = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    return [pscustomobject]@{ Code = $proc.ExitCode; Err = $errTask.Result; Out = $out }
}

function Invoke-Git([string]$Repo, [string]$Arguments) {
    $r = Invoke-Process 'git' ('-C "' + $Repo + '" ' + $Arguments)
    if ($r.Code -ne 0) { throw "git $Arguments in $Repo failed: $($r.Err)" }
}

function Test-Ignored([string]$Repo, [string]$Rel) {
    $r = Invoke-Process 'git' ('-C "' + $Repo + '" check-ignore -q --no-index "' + $Rel + '"')
    if ($r.Code -gt 1) { throw "git check-ignore failed in ${Repo}: $($r.Err)" }
    return $r.Code -eq 0
}

function Get-ConfigValue([string]$Text, [string]$Key) {
    $m = [regex]::Match($Text, '(?m)^\s*' + [regex]::Escape($Key) + '\s*:\s*"((?:[^"\\]|\\.)*)"')
    if (-not $m.Success) { return $null }
    return ($m.Groups[1].Value -replace '\\\\', '\')
}

function New-Payload([string]$Path, [string]$Tool = 'Write', [string]$Cwd = $null, [string]$Key = 'file_path') {
    if (-not $Cwd) { $Cwd = $TmpAgents }
    $ti = @{ content = '' }
    $ti[$Key] = $Path
    return @{ hook_event_name = 'PreToolUse'; tool_name = $Tool; tool_input = $ti; cwd = $Cwd }
}

function New-ShellPayload([string]$Command, [string]$Tool = 'Bash') {
    return @{ hook_event_name = 'PreToolUse'; tool_name = $Tool; tool_input = @{ command = $Command }; cwd = $TmpAgents }
}

function Invoke-Guard($Payload) {
    $json = $Payload | ConvertTo-Json -Depth 5 -Compress
    return Invoke-Process 'powershell' ('-NoProfile -NonInteractive -File "' + $Guard + '"') $json
}

function Invoke-GuardRaw([string]$Raw) {
    return Invoke-Process 'powershell' ('-NoProfile -NonInteractive -File "' + $Guard + '"') $Raw
}

function Assert-Guard([string]$Name, $Result, [int]$Code, [string]$ErrLike = '') {
    $ok = $Result.Code -eq $Code
    if ($ok -and $ErrLike) { $ok = $Result.Err -like "*$ErrLike*" }
    $first = (($Result.Err -split "`n") | Select-Object -First 1)
    Assert-True $ok $Name "exit=$($Result.Code), want=$Code; stderr: $first"
}

function Write-TestConfig([string]$Vault, [string]$Code) {
    $lines = @(
        '# throwaway config for family-data-guard.tests.ps1',
        ('vault_local_path: "' + ($Vault -replace '\\', '\\') + '"'),
        ('code_local_path: "' + ($Code -replace '\\', '\\') + '"')
    )
    [System.IO.File]::WriteAllText($Config, ($lines -join "`n"))
}

function New-EmptyFile([string]$Path) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [System.IO.File]::WriteAllText($Path, '')
}

# --- throwaway setup -------------------------------------------------------------------------
$TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('grobing-guard-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$TmpAgents = Join-Path $TmpRoot 'grobing-agents'
$TmpVault = Join-Path $TmpRoot 'grobing-vault'
$TmpCode = Join-Path $TmpRoot 'grobing-code'
$Outside = Join-Path $TmpRoot 'outside'
$Guard = Join-Path $TmpAgents '.claude/hooks/family-data-guard.ps1'
$Config = Join-Path $TmpAgents '.claude/rules/project-config.md'

try {
    foreach ($d in @($TmpAgents, $TmpVault, $TmpCode, $Outside, (Join-Path $TmpAgents '.claude/hooks'), (Join-Path $TmpAgents '.claude/rules'))) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }
    foreach ($d in @($TmpAgents, $TmpVault, $TmpCode)) { Invoke-Git $d 'init -q' }
    Copy-Item -LiteralPath $GuardSource -Destination $Guard
    Write-TestConfig $TmpVault $TmpCode

    Write-Host "`n[AC-2] repos from project-config.md, no absolute paths"
    $settingsText = [System.IO.File]::ReadAllText($SettingsPath, [System.Text.Encoding]::UTF8)
    $guardText = [System.IO.File]::ReadAllText($GuardSource, [System.Text.Encoding]::UTF8)
    Assert-True ($settingsText -notmatch '[A-Za-z]:[\\/]') 'settings.json has no absolute path'
    Assert-True ($guardText -notmatch '[A-Za-z]:[\\/]') 'guard script has no absolute path'
    Assert-Guard 'repo from config: write inside temp code repo is refused' (Invoke-Guard (New-Payload (Join-Path $TmpCode 'x.db'))) 2 'grobing-code/x.db'
    Assert-Guard 'repo from config: same file outside the three repos passes' (Invoke-Guard (New-Payload (Join-Path $Outside 'x.db'))) 0
    Assert-Guard 'agents root from script location' (Invoke-Guard (New-Payload (Join-Path $TmpAgents 'x.db'))) 2 'grobing-agents/x.db'

    Write-Host "`n[D2] every type on THE LIST is refused (write)"
    foreach ($n in $DbNames + $BackupNames + $ExportNames) {
        Assert-Guard "code/lib/$n" (Invoke-Guard (New-Payload (Join-Path $TmpCode "lib\$n"))) 2 'ODMOWA zapisu'
    }
    foreach ($n in $MediaNames) {
        Assert-Guard "vault/01_INBOX/$n" (Invoke-Guard (New-Payload (Join-Path $TmpVault "01_INBOX\$n"))) 2 'zdjecie albo film'
    }
    Assert-Guard 'agents/notes.html' (Invoke-Guard (New-Payload (Join-Path $TmpAgents 'notes.html'))) 2 'eksport'
    Assert-Guard 'agents/photo.JPG (upper case)' (Invoke-Guard (New-Payload (Join-Path $TmpAgents 'photo.JPG'))) 2
    foreach ($f in $RootFolders) {
        Assert-Guard "code/$f/a.txt (root folder)" (Invoke-Guard (New-Payload (Join-Path $TmpCode "$f\a.txt"))) 2 'katalog danych rodziny'
        Assert-Guard "vault/$f/a.md (root folder)" (Invoke-Guard (New-Payload (Join-Path $TmpVault "$f\a.md"))) 2 'katalog danych rodziny'
    }

    Write-Host "`n[D2] what must pass"
    foreach ($n in $UiImageNames) {
        Assert-Guard "code res/mipmap-hdpi/$n (UI image)" (Invoke-Guard (New-Payload (Join-Path $TmpCode "android\app\src\main\res\mipmap-hdpi\$n"))) 0
    }
    Assert-Guard 'code res/raw/a.mp4 (not a UI image type)' (Invoke-Guard (New-Payload (Join-Path $TmpCode 'android\app\src\main\res\raw\a.mp4'))) 2
    Assert-Guard 'code res/raw/x.db (no exception for databases)' (Invoke-Guard (New-Payload (Join-Path $TmpCode 'android\app\src\main\res\raw\x.db'))) 2
    Assert-Guard 'code assets/x.png (no exception yet)' (Invoke-Guard (New-Payload (Join-Path $TmpCode 'assets\x.png'))) 2
    Assert-Guard 'code lib/x.dart' (Invoke-Guard (New-Payload (Join-Path $TmpCode 'lib\x.dart'))) 0
    Assert-Guard 'code lib/features/backups/b.dart (folder not at root)' (Invoke-Guard (New-Payload (Join-Path $TmpCode 'lib\features\backups\b.dart'))) 0
    Assert-Guard 'vault 03_REQUIREMENTS/x.md' (Invoke-Guard (New-Payload (Join-Path $TmpVault '03_REQUIREMENTS\x.md'))) 0
    Assert-Guard 'agents .gitignore (text that names *.db)' (Invoke-Guard (New-Payload (Join-Path $TmpAgents '.gitignore'))) 0

    Write-Host "`n[paths] one file, every spelling"
    $gitBash = '/' + $TmpCode.Substring(0, 1).ToLower() + ($TmpCode.Substring(2) -replace '\\', '/') + '/x.sqlite-wal'
    Assert-Guard "Git Bash form $gitBash" (Invoke-Guard (New-Payload $gitBash)) 2
    Assert-Guard 'upper-case path' (Invoke-Guard (New-Payload ((Join-Path $TmpCode 'Kopia.AGE').ToUpperInvariant()))) 2
    Assert-Guard 'relative path against cwd' (Invoke-Guard (New-Payload 'test.db' -Cwd $TmpCode)) 2
    Assert-Guard '..\ out of the repo' (Invoke-Guard (New-Payload (Join-Path $TmpCode '..\outside\x.db'))) 0

    Write-Host "`n[tools] write tools other than Write"
    Assert-Guard 'Edit' (Invoke-Guard (New-Payload (Join-Path $TmpCode 'x.db') -Tool 'Edit')) 2
    Assert-Guard 'MultiEdit' (Invoke-Guard (New-Payload (Join-Path $TmpCode 'x.db') -Tool 'MultiEdit')) 2
    Assert-Guard 'NotebookEdit (notebook_path)' (Invoke-Guard (New-Payload (Join-Path $TmpVault 'x.pdf') -Tool 'NotebookEdit' -Key 'notebook_path')) 2
    Assert-Guard 'unknown tool passes' (Invoke-Guard (New-Payload (Join-Path $TmpCode 'x.db') -Tool 'Read')) 0

    Write-Host "`n[D4] fail-closed"
    Assert-Guard 'Edit without file_path' (Invoke-Guard @{ tool_name = 'Edit'; tool_input = @{}; cwd = $TmpAgents }) 2 'blad straznika'
    Assert-Guard 'not JSON on stdin' (Invoke-GuardRaw 'not json') 2 'blad straznika'
    Assert-Guard 'empty stdin' (Invoke-GuardRaw '') 2 'puste wejscie'
    Move-Item -LiteralPath $Config -Destination "$Config.off"
    Assert-Guard 'no project-config.md: write refused' (Invoke-Guard (New-Payload (Join-Path $Outside 'x.txt'))) 2 'nie znam sciezek repo'
    Assert-Guard 'no project-config.md: other shell commands pass' (Invoke-Guard (New-ShellPayload 'ls -la')) 0
    Assert-Guard 'no project-config.md: git add refused' (Invoke-Guard (New-ShellPayload 'git add .')) 2 'nie znam sciezek repo'
    Move-Item -LiteralPath "$Config.off" -Destination $Config
    Write-TestConfig '' $TmpCode
    Assert-Guard 'empty vault_local_path' (Invoke-Guard (New-Payload (Join-Path $TmpCode 'lib\x.dart'))) 2 'brak wartosci vault_local_path'
    Write-TestConfig (Join-Path $TmpRoot 'no-such-vault') $TmpCode
    Assert-Guard 'vault_local_path to a missing folder' (Invoke-Guard (New-Payload (Join-Path $TmpCode 'lib\x.dart'))) 2 'ktorego nie ma'
    Write-TestConfig $TmpVault $TmpCode

    Write-Host "`n[D3] shell: only git add / git commit are looked at"
    Assert-Guard 'Bash ls' (Invoke-Guard (New-ShellPayload 'ls -la')) 0
    Assert-Guard 'Bash git status' (Invoke-Guard (New-ShellPayload 'git status --short')) 0
    Assert-Guard 'Bash git commit-tree (not commit)' (Invoke-Guard (New-ShellPayload 'git commit-tree abc')) 0
    Assert-Guard 'Bash git add . (clean repos)' (Invoke-Guard (New-ShellPayload 'git add .')) 0
    Assert-Guard 'Bash git add --dry-run (not force)' (Invoke-Guard (New-ShellPayload 'git add --dry-run .')) 0
    Assert-Guard 'Bash git add -f' (Invoke-Guard (New-ShellPayload 'git add -f x.db')) 2 'git add -f/--force'
    Assert-Guard 'Bash cd && git add --force' (Invoke-Guard (New-ShellPayload 'cd x && git add --force .')) 2 'git add -f/--force'
    Assert-Guard 'PowerShell git add -fA' (Invoke-Guard (New-ShellPayload 'git add -fA .' -Tool 'PowerShell')) 2 'git add -f/--force'
    Assert-Guard 'Bash git -C dir add -f' (Invoke-Guard (New-ShellPayload "git -C `"$TmpCode`" add -f x")) 2 'git add -f/--force'

    Write-Host "`n[D3] a family-type file sitting untracked in a repo (no .gitignore there)"
    $stray = Join-Path $TmpCode 'proba.age'
    New-EmptyFile $stray
    foreach ($cmd in @('git add .', "git -C `"$TmpCode`" add -A", 'cd x && git commit -am "m"', 'git add docs/notes.md')) {
        Assert-Guard "Bash: $cmd" (Invoke-Guard (New-ShellPayload $cmd)) 2 'grobing-code/proba.age'
    }
    Assert-Guard 'PowerShell: git add .' (Invoke-Guard (New-ShellPayload 'git add .' -Tool 'PowerShell')) 2 'grobing-code/proba.age'
    Assert-Guard 'Bash: git status with the stray file (not add/commit)' (Invoke-Guard (New-ShellPayload 'git status')) 0

    Write-Host "`n[D3] the same file hidden by the real .gitignore cannot land in a commit -> passes"
    Copy-Item -LiteralPath (Join-Path (Get-ConfigValue ([System.IO.File]::ReadAllText($RealConfig)) 'code_local_path') '.gitignore') -Destination (Join-Path $TmpCode '.gitignore')
    Assert-Guard 'Bash: git add . (proba.age ignored)' (Invoke-Guard (New-ShellPayload 'git add .')) 0
    Remove-Item -LiteralPath $stray

    Write-Host "`n[D3] a file force-staged earlier (e.g. from a GUI) blocks the commit"
    New-EmptyFile (Join-Path $TmpVault 'zapis.db')
    Invoke-Git $TmpVault 'add -f zapis.db'
    Assert-Guard 'Bash: git commit -m x (zapis.db in the index)' (Invoke-Guard (New-ShellPayload 'git commit -m x')) 2 'grobing-vault/zapis.db'
    Invoke-Git $TmpVault 'rm --cached -q zapis.db'
    Remove-Item -LiteralPath (Join-Path $TmpVault 'zapis.db')

    Write-Host "`n[AC-1] the wrapper from settings.json: script first, missing script -> exit 2"
    $settings = $settingsText | ConvertFrom-Json
    $group = $settings.hooks.PreToolUse | Select-Object -First 1
    $handler = $group.hooks | Select-Object -First 1
    $tools = $group.matcher -split '\|'
    foreach ($t in @('Write', 'Edit', 'MultiEdit', 'NotebookEdit', 'Bash', 'PowerShell')) {
        Assert-True ($tools -contains $t) "matcher covers $t" "matcher: $($group.matcher)"
    }
    Assert-True ($handler.shell -eq 'powershell') 'hook runs in powershell' "shell: $($handler.shell)"
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($handler.command))
    function Invoke-Wrapper([string]$ProjectDir, $Payload) {
        return Invoke-Process 'powershell' ('-NoProfile -NonInteractive -EncodedCommand ' + $encoded) ($Payload | ConvertTo-Json -Depth 5 -Compress) @{ CLAUDE_PROJECT_DIR = $ProjectDir }
    }
    Assert-Guard 'wrapper + script: test.db refused' (Invoke-Wrapper $TmpAgents (New-Payload (Join-Path $TmpCode 'test.db'))) 2 'ODMOWA zapisu grobing-code/test.db'
    Assert-Guard 'wrapper + script: lib/x.dart passes' (Invoke-Wrapper $TmpAgents (New-Payload (Join-Path $TmpCode 'lib\x.dart'))) 0
    $noScript = Join-Path $TmpRoot 'no-script'
    New-Item -ItemType Directory -Force -Path $noScript | Out-Null
    Assert-Guard 'wrapper, script missing: exit 2, never silence' (Invoke-Wrapper $noScript (New-Payload (Join-Path $TmpCode 'lib\x.dart'))) 2 'brak skryptu'
    $broken = Join-Path $TmpRoot 'broken'
    $brokenScript = Join-Path $broken '.claude/hooks/family-data-guard.ps1'
    New-EmptyFile $brokenScript
    foreach ($case in @(
            @{ Name = 'syntax error'; Body = "function { {{ (`n" },
            @{ Name = 'ends without exit'; Body = "`$x = 1`n" },
            @{ Name = 'throws'; Body = "throw 'boom'`n" })) {
        [System.IO.File]::WriteAllText($brokenScript, $case.Body)
        Assert-Guard "wrapper, script that $($case.Name): exit 2" (Invoke-Wrapper $broken (New-Payload (Join-Path $TmpCode 'lib\x.dart'))) 2
    }

    Write-Host "`n[.gitignore] THE LIST in the three REAL repos (read-only check-ignore)"
    $realText = [System.IO.File]::ReadAllText($RealConfig, [System.Text.Encoding]::UTF8)
    $realRepos = [ordered]@{
        'grobing-agents' = $RealAgents
        'grobing-vault'  = (Get-ConfigValue $realText 'vault_local_path')
        'grobing-code'   = (Get-ConfigValue $realText 'code_local_path')
    }
    foreach ($name in $realRepos.Keys) {
        $root = $realRepos[$name]
        $missing = @()
        foreach ($n in $AllListed) { if (-not (Test-Ignored $root "probe/$n")) { $missing += $n } }
        foreach ($f in $RootFolders) { if (-not (Test-Ignored $root "$f/a.md")) { $missing += "/$f/" } }
        Assert-True ($missing.Count -eq 0) "$name .gitignore covers THE LIST" ("not ignored: " + ($missing -join ', '))
        Assert-True (-not (Test-Ignored $root 'lib/features/backups/b.dart')) "$name does not hide lib/features/backups/ (folders anchored)"
    }
    $code = $realRepos['grobing-code']
    $hidden = @($UiImageNames | Where-Object { Test-Ignored $code "android/app/src/main/res/mipmap-hdpi/$_" })
    Assert-True ($hidden.Count -eq 0) 'grobing-code keeps UI images in res/' ("ignored: " + ($hidden -join ', '))
    Assert-True (Test-Ignored $code 'android/app/src/main/res/raw/x.db') 'grobing-code still hides *.db inside res/'
    Assert-True (Test-Ignored $code 'android/app/src/main/res/raw/a.mp4') 'grobing-code still hides video inside res/'
}
finally {
    if (Test-Path -LiteralPath $TmpRoot) { Remove-Item -LiteralPath $TmpRoot -Recurse -Force }
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) of $($script:Count)"
    $script:Failures | ForEach-Object { Write-Host "  - $_" }
    exit 1
}
Write-Host "PASSED: $($script:Count) of $($script:Count)"
exit 0
