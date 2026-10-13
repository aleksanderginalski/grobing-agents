<#
    command-guard.tests.ps1 -- tests for the command guard (ISSUE-031; written by qa).

    RUN (from the grobing-agents root):
        powershell -NoProfile -File .claude/hooks/tests/command-guard.tests.ps1
    Exit code 0 = all passed, 1 = at least one failure (listed at the end).

    WHAT IT DOES
      - feeds PreToolUse JSON to the guard, one powershell process per case, as the harness does;
      - AC-1: every refused form (git outside the allow-list, gh, python reading stdin) in Bash and
        PowerShell, also behind -C/-c, a path to git.exe, &&/;/|/newline, $( ), backticks, bash -c,
        powershell -Command/-EncodedCommand, wrappers and keywords;
      - AC-2: every allowed form, text in quotes/heredocs/here-strings, today's docs commit commands;
      - git add with a directory: a throwaway folder in %TEMP% (by cwd, by -C, after cd);
      - AC-3: fail-closed input, the exact wrapper command from .claude/settings.json (script present,
        missing, broken), onFailure "block" on both hook handlers;
      - KNOWN GAPS: the forms the guard documents it does not catch pass -- a change shows up here.
    It never runs git or python itself and never writes into a Grobing repo. ASCII only (PowerShell 5.1).
#>

$ErrorActionPreference = 'Stop'

$TestsDir = Split-Path -Parent $PSCommandPath
$HooksDir = Split-Path -Parent $TestsDir
$RealAgents = Split-Path -Parent (Split-Path -Parent $HooksDir)
$Guard = Join-Path $HooksDir 'command-guard.ps1'
$SettingsPath = Join-Path $RealAgents '.claude/settings.json'

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

function New-ShellPayload([string]$Command, [string]$Tool = 'Bash') {
    return @{ hook_event_name = 'PreToolUse'; tool_name = $Tool; tool_input = @{ command = $Command }; cwd = $Tmp }
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

function Show([string]$Command) {
    $s = $Command -replace "`r?`n", '\n'
    if ($s.Length -gt 90) { $s = $s.Substring(0, 87) + '...' }
    return $s
}

function Test-Cases([string]$Title, [string]$Tool, [int]$Code, $Commands, [string]$ErrLike = '') {
    Write-Host "`n[$Title] $Tool -> exit $Code"
    foreach ($c in $Commands) {
        Assert-Guard "$Tool  $(Show $c)" (Invoke-Guard (New-ShellPayload $c $Tool)) $Code $ErrLike
    }
}

$Tmp = Join-Path $env:TEMP ('command-guard-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $Tmp 'sub') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $Tmp 'a.md'), "x`n")
    [System.IO.File]::WriteAllText((Join-Path $Tmp 'sub\b.md'), "x`n")
    # the same folder in Git Bash form: C:\Users\... -> /c/Users/...
    $TmpBash = '/' + $Tmp.Substring(0, 1).ToLowerInvariant() + ($Tmp.Substring(2) -replace '\\', '/')

    # ------------------------------------------------------------ AC-1: refused
    Test-Cases 'AC-1 git outside the allow-list' 'Bash' 2 @(
        'git reset', 'git reset --hard HEAD~1', 'git reset -q', 'git restore a.md', 'git restore --staged a.md',
        'git stash', 'git stash list', 'git rm a.md', 'git rm --cached a.md', 'git checkout -- a.md', 'git checkout main',
        'git switch main', 'git rebase main', 'git merge main', 'git pull', 'git fetch', 'git fetch --dry-run',
        'git clean -fd', 'git mv a.md b.md', 'git cherry-pick abc123', 'git revert abc123', 'git init',
        'git remote add origin https://example.invalid/x.git', 'git remote set-url origin https://example.invalid/y.git',
        'git remote remove origin', 'git update-index --assume-unchanged a.md', 'git apply --index x.patch',
        'git worktree add ../w', 'git notes add -m x', 'git gc', 'git -x status', 'git --exec-path=/x reset'
    ) 'ODMOWA'
    Test-Cases 'AC-1 git add -- not an explicit file list' 'Bash' 2 @(
        'git add .', 'git add ./', 'git add -A', 'git add --all', 'git add -u', 'git add --update', 'git add -N .',
        'git add --intent-to-add a.md', 'git add -f a.md', 'git add --force a.md', 'git add -p a.md', 'git add -i',
        'git add -e a.md', 'git add -Av', 'git add --al', 'git add *.md', "git add 'lib/*.dart'", 'git add a?.md',
        'git add :/', "git add ':(glob)**/*.md'", 'git add sub', 'git add -- sub', 'git add sub/', 'git add a.md sub',
        "git -C $TmpBash add sub", "git -C '$Tmp' add sub", "cd $TmpBash && git add sub", 'git add --renormalize .',
        'git add --pathspec-from-file=list.txt'
    ) 'ODMOWA'
    Test-Cases 'AC-1 git commit / push / branch / tag / config outside the allow-list' 'Bash' 2 @(
        'git commit --amend', 'git commit --amend --no-edit', 'git commit --amen', 'git commit -a -m x', 'git commit -am x',
        'git commit --all -m x', 'git commit -p', 'git commit --patch', 'git commit --interactive', 'git commit -n -m x',
        'git commit --no-verify -m x', 'git commit -q --no-verify -F m.txt',
        'git push', 'git push origin', 'git push origin dev', 'git push origin main:main', 'git push origin +main',
        'git push --force origin main', 'git push -f origin main', 'git push --force-with-lease origin main',
        'git push --tags origin main', 'git push -u origin main', 'git push --no-verify origin main', 'git push upstream main',
        'git branch nowa', 'git branch -d stara', 'git branch -D stara', 'git branch -m a b', 'git branch -c a b',
        'git branch -u origin/main', 'git branch --set-upstream-to=origin/main',
        'git tag v1', 'git tag -a v1 -m x', 'git tag -d v1', 'git tag -f v1',
        'git config core.autocrlf false', 'git config --unset core.autocrlf', 'git config --add a.b c', 'git config -e',
        'git config set core.x y'
    ) 'ODMOWA'
    Test-Cases 'AC-1 the same verb in other shapes' 'Bash' 2 @(
        'git -C /c/x reset', 'git -C . reset', 'git -c core.x=1 reset', 'git --no-pager -C x stash',
        'git --git-dir=.git reset', '/usr/bin/git reset', '/mingw64/bin/git.exe reset', 'git.exe reset',
        '"C:/Program Files/Git/cmd/git.exe" stash', '\git reset', "'git' reset", "git 'reset'",
        'echo x && git reset', 'echo x; git reset', 'echo x || git reset', 'cat a | git rm a.md', "echo x`ngit reset",
        'git status && git reset', '( git reset )', '{ git reset; }', 'echo $(git reset)', 'echo "$(git reset)"',
        'echo "before $(echo x; git stash) after"', 'echo `git reset`', 'echo "`git reset`"', 'diff <(git stash show) a',
        "bash -c 'git reset'", 'bash -c "git fetch"', "sh -lc 'git reset'", "bash -c `"bash -c 'git reset'`"",
        'powershell -NoProfile -Command "git reset"', "pwsh -c 'git stash'",
        'if true; then git reset; fi', 'for f in a b; do git rm $f; done', 'while false; do git stash; done', '! git reset',
        'time git reset', 'timeout 5 git reset', 'timeout -s KILL 5 git reset', 'nice -n 5 git reset', 'nohup git reset',
        'env X=1 git reset', 'X=1 Y=2 git reset', 'command git reset', 'exec git reset', 'sudo git reset',
        'xargs git rm < list.txt', 'xargs -n 1 git rm < list.txt', 'git status 2>&1 | grep x; git reset'
    ) 'ODMOWA'
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes('git reset --hard'))
    Test-Cases 'AC-1 PowerShell' 'PowerShell' 2 @(
        'git reset --hard', 'git stash', 'git -C C:\x checkout main', "& 'C:\Program Files\Git\cmd\git.exe' stash",
        '& git reset', 'if ($true) { git checkout main }', 'Get-ChildItem | ForEach-Object { git rm $_ }',
        'Write-Output $(git reset)', 'Write-Output "x $(git stash) y"', 'Write-Output @(git reset)',
        "git status; git reset", "git status`ngit reset", 'git add .', 'git add -A', 'git push --force origin main',
        "powershell -NoProfile -EncodedCommand $encoded", 'gh repo view', 'python -I -', 'py'
    ) 'ODMOWA'
    Test-Cases 'AC-1 gh' 'Bash' 2 @('gh pr list', 'gh repo create x --public', 'gh api repos/x/y', '/usr/bin/gh auth status') 'gh zmienia stan'
    Test-Cases 'AC-1 python reading its script from stdin (or REPL)' 'Bash' 2 @(
        'python -', 'python -I -', 'python3 -', 'python3.12 -', 'pythonw -', 'py -', 'py -3 -', 'py -3.12 -I -',
        'python -u -', 'python -Iu -', 'python -X utf8 -', 'python -W ignore -', 'python -- -', 'python',
        'py', 'python -I', 'winpty python', 'echo "print(1)" | python', 'cat x.py | python -I -',
        "python - <<'EOF'`nprint(1)`nEOF", "python -I - <<EOF`nimport os`nEOF", 'timeout 5 python -I - </dev/null',
        '/c/Python312/python.exe -', '"C:/Program Files/Python312/python.exe" -I -', 'python.exe -',
        'MSYS_NO_PATHCONV=1 python -I -', 'cd /c/x && python -', "bash -c 'python -'"
    ) 'zapisz skrypt'

    # ------------------------------------------------------------ AC-2: allowed
    Test-Cases 'AC-2 git read-only' 'Bash' 0 @(
        'git status', 'git status --short', 'git status --short --ignored', 'git diff', 'git diff --cached --stat',
        'git diff --stat', 'git log --oneline -5', 'git log --oneline origin/main..main', 'git show HEAD --stat',
        'git rev-parse HEAD', 'git rev-list --count HEAD', 'git ls-files -z', 'git ls-tree HEAD', 'git cat-file -p HEAD',
        'git check-ignore -v a.db', 'git check-ignore -q --no-index probe/x.db', 'git blame a.md', 'git shortlog -sn',
        'git describe --tags', 'git grep -n reset', 'git merge-base HEAD main', 'git show-ref', 'git for-each-ref',
        'git count-objects -v', 'git version', 'git help status', 'git var GIT_AUTHOR_IDENT', 'git', 'git --version',
        'git branch', 'git branch -l', 'git branch --list', "git branch --list 'feat*'", 'git branch --show-current',
        'git branch -a', 'git branch -r', 'git branch -v', 'git branch --contains HEAD',
        'git remote', 'git remote -v', 'git remote get-url origin', 'git remote get-url --push origin',
        'git config core.autocrlf', 'git config --get user.name', 'git config --get-regexp alias', 'git config --list',
        'git config -l', 'git config get core.autocrlf', 'git config --show-origin --get core.x',
        'git tag', 'git tag -l', "git tag --list 'v*'",
        'git -C /c/Programowanie/Grobing/grobing-vault log --oneline origin/main..main',
        'git -c core.quotepath=off -c color.ui=never diff --cached --name-only -z', 'git --no-pager log -1',
        'git log --grep=reset --oneline', 'git log --oneline -- .claude/hooks/command-guard.ps1'
    )
    Test-Cases 'AC-2 git add / commit / push in the docs package form' 'Bash' 0 @(
        'git add -- a.md', 'git add a.md', 'git add -- a.md sub/b.md', 'git add -v -- a.md', 'git add -n -- a.md',
        "git -C $TmpBash add -- a.md sub/b.md", "cd $TmpBash && git add -- sub/b.md", 'git add -- deleted-file.md',
        'git commit -q -F "C:/Users/user/AppData/Local/Temp/claude/x/scratchpad/msg.txt"', 'git commit -m "Retro 3: x"',
        'git commit -m "-a fix: reset and stash words"', 'git commit -qm "x"', 'git commit -q -m x --author="A <a@b.c>"',
        'git commit -m "x" --allow-empty',
        'git push origin main', 'git push -q origin main', 'git push --dry-run origin main', 'git push -n origin main',
        'git push --porcelain origin main', 'git -C /c/Programowanie/Grobing/grobing-vault push origin main 2>&1 | tail -2',
        'echo dry-run: git add -- a.md sub/b.md'
    )
    Test-Cases 'AC-2 forbidden words as TEXT' 'Bash' 0 @(
        'echo "git reset --hard"', "echo 'git push --force'", "grep -n 'git reset' rules.md", 'grep -rn "git stash" .',
        "printf '%s\n' 'python -I -'", '# git reset in a comment', 'echo x # git reset', "rg 'gh pr'",
        "cat > /tmp/x.txt <<'EOF'`ngit reset --hard`npython -I -`ngh pr list`nEOF`nwc -l /tmp/x.txt",
        "cat <<-EOF > /tmp/y`n`tgit stash`n`tEOF", "cat > m.txt <<EOF`nRetro: git reset, python -`nEOF",
        'sed -n "1,5p" a.md', 'echo "$(date) git reset"', 'echo $(git status --short)', 'echo "$(git log -1)"',
        "bash -c 'git status'", 'powershell -NoProfile -Command "git log -1"', 'ls -la 2>/dev/null', 'ls > out.txt',
        'ls 2>&1 | head', 'MSYS_NO_PATHCONV=1 adb shell ls /sdcard', 'flutter test', 'dart format .', 'flutter analyze',
        'for r in a b; do echo "=== $r"; git -C /c/$r status --short; git -C /c/$r log --oneline origin/main..main; done',
        'cd /c/x && git status && git diff --stat', 'wc -l a.md b.md', 'python -I script.py', 'python -I script.py -',
        'python -c "print(1)"', 'python -Ic "print(1)"', 'python -m pytest -q', 'python --version', 'python -V',
        'py --list', 'py -3 script.py', '"C:/Python312/python.exe" -X utf8 tool.py -', 'python3 -u tool.py --in -',
        'timeout 5 python tool.py', 'echo "python -" > note.txt', 'gh-pages-helper --x', 'githubify x', 'gitk'
    )
    Test-Cases 'AC-2 PowerShell' 'PowerShell' 0 @(
        'git status', 'git -C C:\Programowanie\Grobing\grobing-agents log --oneline -1', 'git diff --cached --stat',
        "Select-String -Path x -Pattern 'git reset'", 'Write-Output "git reset --hard"', "git commit -m @'`nmulti`ngit reset text`n'@",
        "`$m = @`"`ngit stash`npython -`n`"@", '# git reset', '<# git reset #> Get-Date', 'Get-Content C:\x\y.txt -TotalCount 5',
        'Get-ChildItem | Where-Object { $_.Name -like "*.md" }', 'if ($true) { git status }', 'git status 2>$null',
        'flutter test 2>&1 | Select-Object -Last 5', '& flutter analyze', 'python -I C:\x\tool.py', 'git push origin main'
    )

    # ------------------------------------------------------------ messages
    Write-Host "`n[messages] what, why, what instead"
    $r = Invoke-Guard (New-ShellPayload 'git -C /c/x reset --hard')
    # .Contains, not -like: a backtick is the escape character of -like patterns
    Assert-True ($r.Err.Contains('ODMOWA `git -C /c/x reset --hard`') -and $r.Err.Contains('git-autonomy-boundary.md') -and $r.Err.Contains('autor w terminalu VS Code')) 'git refusal names the command, the rule and who does it' $r.Err
    $r = Invoke-Guard (New-ShellPayload 'python -I -')
    Assert-True ($r.Err.Contains('ODMOWA `python -I -`') -and $r.Err.Contains('zapisz skrypt w katalogu tymczasowym')) 'python refusal names the command and the way out' $r.Err
    $r = Invoke-Guard (New-ShellPayload 'git reset; git stash; git clean -fd; git mv a b; git gc')
    Assert-True ($r.Code -eq 2 -and $r.Err -like '*i jeszcze 2*') 'five refusals: three shown, the rest counted' $r.Err
    $long = 'git -C ' + ('/c/very/long/path' * 10) + ' reset'
    $r = Invoke-Guard (New-ShellPayload $long)
    Assert-True ($r.Err.Contains('...`')) 'a long command is shortened in the message' (($r.Err -split "`n")[0])

    # ------------------------------------------------------------ AC-3: fail-closed
    Write-Host "`n[AC-3] fail-closed input"
    Assert-Guard 'not JSON -> exit 2' (Invoke-GuardRaw '{not json') 2 'blad straznika komend'
    Assert-Guard 'empty stdin -> exit 2' (Invoke-GuardRaw '') 2 'puste wejscie'
    Assert-Guard 'no tool_input.command -> exit 2' (Invoke-GuardRaw '{"tool_name":"Bash","tool_input":{}}') 2 'brak tool_input.command'
    Assert-Guard 'heredoc without a delimiter -> exit 2' (Invoke-Guard (New-ShellPayload 'cat <<')) 2 'heredoc'
    Assert-Guard 'Write tool -> exit 0 (not a shell)' (Invoke-Guard @{ tool_name = 'Write'; tool_input = @{ file_path = 'x.md'; content = 'git reset' }; cwd = $Tmp }) 0
    Assert-Guard 'empty command -> exit 0' (Invoke-Guard (New-ShellPayload '')) 0
    $noCwd = @{ tool_name = 'Bash'; tool_input = @{ command = 'git reset' } } | ConvertTo-Json -Compress
    Assert-Guard 'no cwd in the payload: still refuses' (Invoke-GuardRaw $noCwd) 2 'ODMOWA'

    Write-Host "`n[AC-3] the wrapper from settings.json"
    $settingsText = [System.IO.File]::ReadAllText($SettingsPath)
    Assert-True ($settingsText -notmatch '[A-Za-z]:[\\/]') 'settings.json has no absolute path'
    $settings = $settingsText | ConvertFrom-Json
    $groups = @($settings.hooks.PreToolUse)
    $cgGroup = $groups | Where-Object { ($_.hooks | Where-Object { $_.command -like '*command-guard.ps1*' }) } | Select-Object -First 1
    Assert-True ($null -ne $cgGroup) 'settings.json has a PreToolUse entry for command-guard.ps1'
    $cg = $cgGroup.hooks | Where-Object { $_.command -like '*command-guard.ps1*' } | Select-Object -First 1
    $tools = $cgGroup.matcher -split '\|'
    Assert-True (($tools -contains 'Bash') -and ($tools -contains 'PowerShell')) 'matcher covers Bash and PowerShell' "matcher: $($cgGroup.matcher)"
    Assert-True ($cg.shell -eq 'powershell') 'command guard runs in powershell' "shell: $($cg.shell)"
    Assert-True ($cg.onFailure -eq 'block') 'command guard: onFailure block' "onFailure: $($cg.onFailure)"
    Assert-True ([int]$cg.timeout -ge 5) 'command guard: a timeout is set' "timeout: $($cg.timeout)"
    $fdg = $null
    foreach ($g in $groups) { foreach ($h in $g.hooks) { if ($h.command -like '*family-data-guard.ps1*') { $fdg = $h } } }
    Assert-True ($null -ne $fdg -and $fdg.onFailure -eq 'block') 'family-data guard: onFailure block (D6)' "onFailure: $($fdg.onFailure)"

    $encodedWrapper = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cg.command))
    function Invoke-Wrapper([string]$ProjectDir, $Payload) {
        return Invoke-Process 'powershell' ('-NoProfile -NonInteractive -EncodedCommand ' + $encodedWrapper) ($Payload | ConvertTo-Json -Depth 5 -Compress) @{ CLAUDE_PROJECT_DIR = $ProjectDir }
    }
    Assert-Guard 'wrapper + script: git reset refused' (Invoke-Wrapper $RealAgents (New-ShellPayload 'git reset')) 2 'ODMOWA'
    Assert-Guard 'wrapper + script: git status passes' (Invoke-Wrapper $RealAgents (New-ShellPayload 'git status')) 0
    $noScript = Join-Path $Tmp 'no-script'
    New-Item -ItemType Directory -Force -Path $noScript | Out-Null
    Assert-Guard 'wrapper, script missing: exit 2, never silence' (Invoke-Wrapper $noScript (New-ShellPayload 'git status')) 2 'BRAK SKRYPTU'
    $broken = Join-Path $Tmp 'broken'
    $brokenScript = Join-Path $broken '.claude/hooks/command-guard.ps1'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $brokenScript) | Out-Null
    foreach ($case in @(
            @{ Name = 'syntax error'; Body = "function { {{ (`n" },
            @{ Name = 'ends without exit'; Body = "`$x = 1`n" },
            @{ Name = 'throws'; Body = "throw 'boom'`n" })) {
        [System.IO.File]::WriteAllText($brokenScript, $case.Body)
        Assert-Guard "wrapper, script that $($case.Name): exit 2" (Invoke-Wrapper $broken (New-ShellPayload 'git status')) 2
    }

    # ------------------------------------------------------------ known gaps (documented in the script header)
    Test-Cases 'KNOWN GAPS -- pass today, as the header says' 'Bash' 0 @(
        'eval "git reset"', '"$GIT" reset', 'bash script.sh', 'cmd /c git reset', 'python tool.py',
        'for f in *; do git add "$f"; done'
    )
}
finally {
    if (Test-Path -LiteralPath $Tmp) { Remove-Item -LiteralPath $Tmp -Recurse -Force }
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) of $($script:Count)"
    $script:Failures | ForEach-Object { Write-Host "  - $_" }
    exit 1
}
Write-Host "PASSED: $($script:Count) of $($script:Count)"
exit 0
