<#
    command-guard.ps1 -- PreToolUse hook (Bash | PowerShell): refuses the shell commands the agents
    keep running out of habit although the rules forbid them (ISSUE-031, retro 3 R1).

    WHY IT EXISTS. Retro 3: `python -` / `python -I -` (a script read from stdin -- the command hangs in
    this environment) ran 8 times since SPIKE-001 although the agent's memory says "never"; `git add -N .`
    and `git reset` ran in ISSUE-028 although git-autonomy-boundary.md forbids them. A rule is prose a
    model can skip; this hook is run by the harness, always. It guards against HABIT, not against an
    agent that wants to get round it -- a seat belt, not a sandbox.

    WHAT IT DOES
      Bash | PowerShell
        parses the command text into simple commands and checks each one:
        1. git -- an ALLOW-LIST (git-autonomy-boundary.md: "Always allowed" + the commit and push
           sections). Everything else is refused, including verbs nobody listed (clean, mv, revert...):
             read-only   status diff log show rev-parse rev-list ls-files ls-tree cat-file check-ignore
                         blame shortlog describe grep merge-base show-ref for-each-ref count-objects
                         version help var; branch/tag/remote/config only in their listing/reading forms
             add         explicit files only -- no -A/--all/./:/-u/-N/-f/-p/-i/-e, no wildcard, no
                         pathspec magic, no directory
             commit      no --amend, -a/--all, -p/--patch, --interactive, -n/--no-verify
             push        exactly `git push origin main` (+ -q/-v/--dry-run/--porcelain/--progress)
           global options -C -c --no-pager --git-dir --work-tree pass; an unknown one is refused.
           --no-verify is refused everywhere. gh is always refused.
        2. python / python3 / python3.N / pythonw / py (any path, .exe): refused when the first
           argument that is not an option is `-`, or when there is no script, -c or -m at all (REPL).
        Text in quotes is TEXT, not a command (`grep 'git reset'`, a commit message pass). Heredoc
        bodies and PowerShell here-strings are skipped. A command is split at && || ; | & newline
        ( ) { } $( and backticks; $( ) and backticks inside double quotes are parsed too. Leading
        VAR=x, keywords (if then do else elif while until !) and wrappers (time nice nohup command
        builtin exec env xargs timeout stdbuf sudo winpty) are skipped. bash/sh -c "..." and
        powershell/pwsh -Command "..." / -EncodedCommand are parsed once more (depth limit 3).
        `cd dir` earlier in the same command moves the base for the `git add` directory check.

    WHAT IT DOES NOT CATCH
      - a command built at run time: eval, a command name in a variable ("$GIT" reset), an alias;
      - a script FILE that runs a forbidden command itself (python x.py, bash x.sh, a .ps1);
      - cmd /c ..., Start-Process ..., runners such as uv/conda/npx run ...;
      - a loop or a variable as the `git add` pathspec (for f in *; do git add "$f"; done);
      - the author's own commands in VS Code.
      After "go" the commands this hook refuses (git init, git remote add/set-url, gh) are run by
      the author in the VS Code terminal -- the agent gives the exact command.

    EXIT CODES: 0 = allow, 2 = refuse (stderr is fed back to Claude). FAIL-CLOSED: any error is 2 --
    Claude Code treats exit 1 as non-blocking. settings.json adds "onFailure": "block" for a timeout.
    Messages are ASCII on purpose: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$Tag = 'command-guard (ISSUE-031)'
$RuleRef = 'grobing-agents/.claude/rules/git-autonomy-boundary.md'
$ShellTools = @('Bash', 'PowerShell')
$MaxDepth = 3

$Keywords = @('if', 'then', 'else', 'elif', 'do', 'while', 'until', '!')
$Wrappers = @('time', 'nice', 'nohup', 'command', 'builtin', 'exec', 'env', 'xargs', 'timeout', 'stdbuf', 'sudo', 'doas', 'winpty')
$CdCommands = @('cd', 'chdir', 'pushd', 'set-location', 'sl', 'push-location')
$PosixShells = @('bash', 'sh', 'zsh', 'dash', 'ksh')
$PsShells = @('powershell', 'pwsh')
$PythonName = '^(python(\d+(\.\d+)*)?|pythonw|py)$'

$GitReadOnly = @('status', 'diff', 'log', 'show', 'rev-parse', 'rev-list', 'ls-files', 'ls-tree', 'cat-file',
    'check-ignore', 'blame', 'shortlog', 'describe', 'grep', 'merge-base', 'show-ref', 'for-each-ref',
    'count-objects', 'version', 'help', 'var')

$script:Refusals = New-Object System.Collections.Generic.List[string]

function Write-Utf8([System.IO.Stream]$Stream, [string]$Text) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text + "`n")
    $Stream.Write($bytes, 0, $bytes.Length)
    $Stream.Flush()
}

function Stop-Refuse([string]$Text) {
    Write-Utf8 ([Console]::OpenStandardError()) $Text
    exit 2
}

function Read-Stdin {
    $in = [Console]::OpenStandardInput()
    $ms = New-Object System.IO.MemoryStream
    $in.CopyTo($ms)
    return [System.Text.Encoding]::UTF8.GetString($ms.ToArray()).TrimStart([char]0xFEFF)
}

# ---------------------------------------------------------------- tokenizer

function New-Tokens {
    return [pscustomobject]@{
        Sb       = New-Object System.Text.StringBuilder
        Words    = New-Object System.Collections.Generic.List[string]
        Segments = New-Object System.Collections.Generic.List[object]
        Nested   = New-Object System.Collections.Generic.List[string]
        InWord   = $false
        SkipNext = $false
    }
}

function Complete-Word($T) {
    if (-not $T.InWord) { return }
    $w = $T.Sb.ToString()
    [void]$T.Sb.Clear()
    $T.InWord = $false
    if ($T.SkipNext) { $T.SkipNext = $false } else { $T.Words.Add($w) }
}

function Complete-Segment($T) {
    Complete-Word $T
    if ($T.Words.Count -gt 0) {
        $T.Segments.Add($T.Words.ToArray())
        $T.Words.Clear()
    }
}

# Index of the `)` that closes the `(` at $Open; quotes skipped. Not found -> length of the text.
function Find-Close([string]$s, [int]$Open) {
    $depth = 0
    $i = $Open
    while ($i -lt $s.Length) {
        $c = $s[$i]
        if ($c -eq [char]"'") {
            $j = $s.IndexOf([char]"'", $i + 1)
            if ($j -lt 0) { return $s.Length }
            $i = $j + 1
            continue
        }
        if ($c -eq [char]'"') {
            $j = $i + 1
            while ($j -lt $s.Length -and $s[$j] -ne [char]'"') {
                if ($s[$j] -eq [char]'\' -or $s[$j] -eq [char]'`') { $j++ }
                $j++
            }
            $i = $j + 1
            continue
        }
        if ($c -eq [char]'(') { $depth++ }
        elseif ($c -eq [char]')') { $depth--; if ($depth -eq 0) { return $i } }
        $i++
    }
    return $s.Length
}

# Next unescaped backtick after $From (Bash command substitution). Not found -> length.
function Find-Backtick([string]$s, [int]$From) {
    $i = $From
    while ($i -lt $s.Length) {
        if ($s[$i] -eq [char]'\') { $i += 2; continue }
        if ($s[$i] -eq [char]'`') { return $i }
        $i++
    }
    return $s.Length
}

# Splits a command text into simple commands (arrays of unquoted words) and texts to parse again
# ($( ), backticks). $Mode: 'bash' or 'ps'.
function Split-Command([string]$Text, [string]$Mode) {
    $T = New-Tokens
    $isPs = ($Mode -eq 'ps')
    $heredocs = New-Object System.Collections.Generic.List[object]
    $n = $Text.Length
    $i = 0
    while ($i -lt $n) {
        $c = $Text[$i]

        if ($c -eq [char]"`n") {
            Complete-Segment $T
            $i++
            if ($heredocs.Count -gt 0) {
                foreach ($h in $heredocs) {
                    while ($i -lt $n) {
                        $end = $Text.IndexOf([char]"`n", $i)
                        if ($end -lt 0) { $end = $n }
                        $line = $Text.Substring($i, $end - $i).TrimEnd([char]"`r")
                        if ($h.StripTabs) { $line = $line.TrimStart([char]"`t") }
                        $i = [Math]::Min($end + 1, $n)
                        if ($line -ceq $h.Delim) { break }
                    }
                }
                $heredocs.Clear()
            }
            continue
        }
        if ($c -eq [char]' ' -or $c -eq [char]"`t" -or $c -eq [char]"`r") { Complete-Word $T; $i++; continue }

        # comments start only where a word starts
        if ($c -eq [char]'#' -and -not $T.InWord) {
            $end = $Text.IndexOf([char]"`n", $i)
            if ($end -lt 0) { $end = $n }
            $i = $end
            continue
        }
        if ($isPs -and $c -eq [char]'<' -and $i + 1 -lt $n -and $Text[$i + 1] -eq [char]'#') {
            $end = $Text.IndexOf('#>', $i + 2)
            if ($end -lt 0) { $i = $n } else { $i = $end + 2 }
            continue
        }

        # PowerShell here-string: @' or @" at the end of a line, closed by '@ / "@ at a line start
        if ($isPs -and $c -eq [char]'@' -and $i + 1 -lt $n -and ($Text[$i + 1] -eq [char]"'" -or $Text[$i + 1] -eq [char]'"')) {
            $q = $Text[$i + 1]
            $rest = $Text.Substring($i + 2)
            if ($rest -match '^[ \t]*\r?\n') {
                $close = [regex]::Match($rest, '(?m)^' + [regex]::Escape([string]$q) + '@')
                $T.InWord = $true
                if ($close.Success) { $i = $i + 2 + $close.Index + 2 } else { $i = $n }
                continue
            }
        }

        if ($c -eq [char]"'") {
            $T.InWord = $true
            $j = $i + 1
            while ($j -lt $n) {
                if ($Text[$j] -eq [char]"'") {
                    if ($isPs -and $j + 1 -lt $n -and $Text[$j + 1] -eq [char]"'") { [void]$T.Sb.Append("'"); $j += 2; continue }
                    break
                }
                [void]$T.Sb.Append($Text[$j])
                $j++
            }
            $i = $j + 1
            continue
        }

        if ($c -eq [char]'"') {
            $T.InWord = $true
            $j = $i + 1
            while ($j -lt $n) {
                $d = $Text[$j]
                if ($d -eq [char]'"') {
                    if ($isPs -and $j + 1 -lt $n -and $Text[$j + 1] -eq [char]'"') { [void]$T.Sb.Append('"'); $j += 2; continue }
                    break
                }
                if (-not $isPs -and $d -eq [char]'\' -and $j + 1 -lt $n) { [void]$T.Sb.Append($Text[$j + 1]); $j += 2; continue }
                if ($isPs -and $d -eq [char]'`' -and $j + 1 -lt $n) { [void]$T.Sb.Append($Text[$j + 1]); $j += 2; continue }
                if ($d -eq [char]'$' -and $j + 1 -lt $n -and $Text[$j + 1] -eq [char]'(') {
                    $close = Find-Close $Text ($j + 1)
                    $T.Nested.Add($Text.Substring($j + 2, [Math]::Max(0, $close - $j - 2)))
                    $j = $close + 1
                    continue
                }
                if (-not $isPs -and $d -eq [char]'`') {
                    $close = Find-Backtick $Text ($j + 1)
                    $T.Nested.Add($Text.Substring($j + 1, [Math]::Max(0, $close - $j - 1)))
                    $j = $close + 1
                    continue
                }
                [void]$T.Sb.Append($d)
                $j++
            }
            $i = $j + 1
            continue
        }

        if ($c -eq [char]'\' -and -not $isPs) {
            if ($i + 1 -lt $n -and $Text[$i + 1] -eq [char]"`n") { $i += 2; continue }
            if ($i + 2 -lt $n -and $Text[$i + 1] -eq [char]"`r" -and $Text[$i + 2] -eq [char]"`n") { $i += 3; continue }
            $T.InWord = $true
            if ($i + 1 -lt $n) { [void]$T.Sb.Append($Text[$i + 1]) }
            $i += 2
            continue
        }

        if ($c -eq [char]'`') {
            if ($isPs) {
                # escape; backtick + newline continues the line
                if ($i + 1 -lt $n -and ($Text[$i + 1] -eq [char]"`n" -or $Text[$i + 1] -eq [char]"`r")) {
                    $i += 2
                    if ($i -lt $n -and $Text[$i] -eq [char]"`n") { $i++ }
                    continue
                }
                $T.InWord = $true
                if ($i + 1 -lt $n) { [void]$T.Sb.Append($Text[$i + 1]) }
                $i += 2
                continue
            }
            $close = Find-Backtick $Text ($i + 1)
            $T.Nested.Add($Text.Substring($i + 1, [Math]::Max(0, $close - $i - 1)))
            $T.InWord = $true
            $i = $close + 1
            continue
        }

        if (($c -eq [char]'$' -or ($isPs -and $c -eq [char]'@')) -and $i + 1 -lt $n -and $Text[$i + 1] -eq [char]'(') {
            $close = Find-Close $Text ($i + 1)
            $T.Nested.Add($Text.Substring($i + 2, [Math]::Max(0, $close - $i - 2)))
            $T.InWord = $true
            $i = $close + 1
            continue
        }
        if ($c -eq [char]'$' -and $i + 1 -lt $n -and $Text[$i + 1] -eq [char]'{') {
            $end = $Text.IndexOf([char]'}', $i + 2)
            if ($end -lt 0) { $end = $n - 1 }
            [void]$T.Sb.Append($Text.Substring($i, $end - $i + 1))
            $T.InWord = $true
            $i = $end + 1
            continue
        }

        if ($c -eq [char]'(' -or $c -eq [char]')') { Complete-Segment $T; $i++; continue }
        if (($c -eq [char]'{' -or $c -eq [char]'}') -and -not $T.InWord) { Complete-Segment $T; $i++; continue }
        if ($c -eq [char]';') { Complete-Segment $T; $i++; continue }
        if ($c -eq [char]'|') {
            Complete-Segment $T
            if ($i + 1 -lt $n -and ($Text[$i + 1] -eq [char]'|' -or $Text[$i + 1] -eq [char]'&')) { $i += 2 } else { $i++ }
            continue
        }
        if ($c -eq [char]'&') {
            if ($i + 1 -lt $n -and $Text[$i + 1] -eq [char]'&') { Complete-Segment $T; $i += 2; continue }
            if (-not $isPs -and $i + 1 -lt $n -and $Text[$i + 1] -eq [char]'>') {
                # &> / &>> : redirect stdout and stderr to the next word
                Complete-Word $T
                $i += 2
                if ($i -lt $n -and $Text[$i] -eq [char]'>') { $i++ }
                $T.SkipNext = $true
                continue
            }
            Complete-Segment $T
            $i++
            continue
        }

        if ($c -eq [char]'<' -or $c -eq [char]'>') {
            # a file-descriptor number (2>) or PowerShell's *> belongs to the operator, not to the words
            $buf = $T.Sb.ToString()
            if ($T.InWord -and ($buf -match '^\d+$' -or ($isPs -and $buf -eq '*'))) {
                [void]$T.Sb.Clear()
                $T.InWord = $false
            }
            else { Complete-Word $T }

            if (-not $isPs -and $c -eq [char]'<' -and $i + 2 -lt $n -and $Text[$i + 1] -eq [char]'<' -and $Text[$i + 2] -eq [char]'<') {
                $i += 3
                $T.SkipNext = $true
                continue
            }
            if (-not $isPs -and $c -eq [char]'<' -and $i + 1 -lt $n -and $Text[$i + 1] -eq [char]'<') {
                $i += 2
                $strip = $false
                if ($i -lt $n -and $Text[$i] -eq [char]'-') { $strip = $true; $i++ }
                while ($i -lt $n -and ($Text[$i] -eq [char]' ' -or $Text[$i] -eq [char]"`t")) { $i++ }
                $m = [regex]::Match($Text.Substring($i), "^(?:'([^']*)'|`"([^`"]*)`"|\\?([^\s;&|<>()]+))")
                if (-not $m.Success) { throw 'heredoc bez znacznika konca -- nie umiem przeczytac komendy' }
                $delim = $m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value
                $heredocs.Add([pscustomobject]@{ Delim = $delim; StripTabs = $strip })
                $i += $m.Length
                continue
            }
            if (-not $isPs -and $i + 1 -lt $n -and $Text[$i + 1] -eq [char]'(') {
                # process substitution <( ) >( )
                $close = Find-Close $Text ($i + 1)
                $T.Nested.Add($Text.Substring($i + 2, [Math]::Max(0, $close - $i - 2)))
                $i = $close + 1
                continue
            }
            $i++
            while ($i -lt $n -and ($Text[$i] -eq [char]'>' -or $Text[$i] -eq [char]'|')) { $i++ }
            if ($i -lt $n -and $Text[$i] -eq [char]'&') {
                $i++
                if ($i -lt $n -and ($Text[$i] -match '[0-9-]')) {
                    while ($i -lt $n -and ($Text[$i] -match '[0-9-]')) { $i++ }
                    continue
                }
            }
            $T.SkipNext = $true
            continue
        }

        [void]$T.Sb.Append($c)
        $T.InWord = $true
        $i++
    }
    Complete-Segment $T
    return $T
}

# ---------------------------------------------------------------- helpers

function Get-BaseName([string]$Word) {
    $b = ($Word -split '[\\/]')[-1].ToLowerInvariant()
    return ($b -replace '\.(exe|cmd|bat)$', '')
}

function New-Slice($Arr, [int]$From) {
    $l = New-Object System.Collections.Generic.List[string]
    for ($k = $From; $k -lt $Arr.Count; $k++) { $l.Add([string]$Arr[$k]) }
    return , $l
}

function Format-Shown($Words) {
    $s = ($Words -join ' ')
    if ($s.Length -gt 100) { $s = $s.Substring(0, 97) + '...' }
    return $s
}

function Resolve-GuardPath([string]$Path, [string]$Base) {
    if (-not $Path) { return $Base }
    $p = $Path
    if ($p -match '^/([a-zA-Z])(/.*)?$') {
        $tail = $Matches[2]
        if (-not $tail) { $tail = '/' }
        $p = $Matches[1].ToUpperInvariant() + ':' + $tail
    }
    elseif ($p -match '^~([\\/].*)?$') {
        $p = $HOME + $Matches[1]
    }
    $p = $p -replace '/', '\'
    if (-not [System.IO.Path]::IsPathRooted($p) -and $Base) { $p = Join-Path $Base $p }
    try { return [System.IO.Path]::GetFullPath($p) } catch { return $p }
}

# Long option given (maybe abbreviated, as git allows) matches one of $List.
function Test-LongOpt([string]$Given, $List) {
    $name = ($Given -split '=', 2)[0]
    foreach ($f in $List) {
        if ($f -eq $name) { return $true }
        if ($name.Length -ge 4 -and $f.StartsWith($name)) { return $true }
    }
    return $false
}

# Walks options of a git subcommand. Returns the first forbidden option (or $null) and positionals.
function Find-GitOptions($Rest, [string]$ShortForbidden, [string]$ShortValue, $LongForbidden, $LongValue) {
    $pos = New-Object System.Collections.Generic.List[string]
    $opts = New-Object System.Collections.Generic.List[string]
    $i = 0
    $dashDash = $false
    while ($i -lt $Rest.Count) {
        $t = $Rest[$i]
        if ($dashDash) { $pos.Add($t); $i++; continue }
        if ($t -eq '--') { $dashDash = $true; $i++; continue }
        if ($t.StartsWith('--')) {
            if (Test-LongOpt $t $LongForbidden) { return [pscustomobject]@{ Hit = $t; Positionals = $pos; Options = $opts } }
            $opts.Add($t)
            if (-not $t.Contains('=') -and $LongValue -contains $t) { $i += 2 } else { $i++ }
            continue
        }
        if ($t.StartsWith('-') -and $t.Length -gt 1) {
            $opts.Add($t)
            $consumes = $false
            for ($k = 1; $k -lt $t.Length; $k++) {
                $ch = $t[$k]
                if ($ShortForbidden.IndexOf($ch) -ge 0) { return [pscustomobject]@{ Hit = $t; Positionals = $pos; Options = $opts } }
                if ($ShortValue.IndexOf($ch) -ge 0) { if ($k -eq $t.Length - 1) { $consumes = $true }; break }
            }
            if ($consumes) { $i += 2 } else { $i++ }
            continue
        }
        $pos.Add($t)
        $i++
    }
    return [pscustomobject]@{ Hit = $null; Positionals = $pos; Options = $opts }
}

# ---------------------------------------------------------------- checks

function Add-GitRefusal([string]$Shown, [string]$Why) {
    $script:Refusals.Add(@(
        "${Tag}: ODMOWA ``$Shown`` -- $Why ($RuleRef).",
        'Dozwolone: odczyt (status, diff, log, show, ...), git add <jawne pliki>, git commit (bez --amend, -a, --no-verify), git push origin main.',
        'Zmiane stanu repo poza paczka docs (reset, restore, stash, checkout, revert, fetch, init, remote...) wykonuje autor w terminalu VS Code po "go" -- podaj mu dokladna komende.'
    ) -join "`n")
}

function Test-Git($Words, [int]$Start, [string]$Base) {
    $shown = Format-Shown (New-Slice $Words $Start)
    $a = New-Slice $Words ($Start + 1)
    $i = 0
    $gitBase = $Base
    while ($i -lt $a.Count) {
        $t = $a[$i]
        if ($t -ceq '-C') { if ($i + 1 -lt $a.Count) { $gitBase = Resolve-GuardPath $a[$i + 1] $gitBase }; $i += 2; continue }
        if ($t -ceq '-c') { $i += 2; continue }
        if ($t -match '^--(git-dir|work-tree|namespace|config-env)=') { $i++; continue }
        if ($t -match '^--(git-dir|work-tree|namespace|config-env)$') { $i += 2; continue }
        if ($t -cmatch '^(-p|-P|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks|--no-lazy-fetch|--no-advice)$') { $i++; continue }
        if ($t -cmatch '^(--version|-v|--help|-h|--html-path|--man-path|--info-path|--exec-path)$') { return }
        if ($t.StartsWith('-')) { Add-GitRefusal $shown "nieznana opcja globalna git '$t'"; return }
        break
    }
    if ($i -ge $a.Count) { return }
    $sub = $a[$i].ToLowerInvariant()
    $rest = New-Slice $a ($i + 1)

    foreach ($t in $rest) {
        if ($t -ne '--' -and (Test-LongOpt $t @('--no-verify'))) { Add-GitRefusal $shown '--no-verify omija hooki -- nigdy (git-autonomy-boundary.md, Pre-commit hook failure)'; return }
    }

    if ($GitReadOnly -contains $sub) { return }

    switch ($sub) {
        'add' {
            $r = Find-GitOptions $rest 'AuNfpie' '' @('--all', '--no-ignore-removal', '--update', '--intent-to-add', '--force', '--patch', '--interactive', '--edit', '--renormalize', '--pathspec-from-file') @()
            if ($r.Hit) { Add-GitRefusal $shown "git add z '$($r.Hit)' -- commit tylko jawnej listy plikow pozycji (R1)"; return }
            foreach ($p in $r.Positionals) {
                if ($p -match '^\.([\\/])?$' -or $p.StartsWith(':') -or $p -match '[*?\[]' -or $p -match '[\\/]$') {
                    Add-GitRefusal $shown "git add z '$p' -- wzorzec albo katalog zamiast jawnej listy plikow (R1)"; return
                }
                $full = Resolve-GuardPath $p $gitBase
                if ($full -and (Test-Path -LiteralPath $full -PathType Container)) {
                    Add-GitRefusal $shown "git add z '$p' -- to katalog, a commit idzie tylko z jawnej listy plikow (R1)"; return
                }
            }
            return
        }
        'commit' {
            $r = Find-GitOptions $rest 'apn' 'mFCct' @('--amend', '--all', '--patch', '--interactive', '--no-verify') @('--message', '--file', '--reuse-message', '--reedit-message', '--fixup', '--squash', '--author', '--date', '--template', '--cleanup', '--trailer', '--pathspec-from-file')
            if ($r.Hit) { Add-GitRefusal $shown "git commit z '$($r.Hit)' -- poprawka historii, wszystko naraz albo bez hookow" }
            return
        }
        'push' {
            $allowed = @('-q', '--quiet', '-v', '--verbose', '--dry-run', '-n', '--porcelain', '--progress', '--no-progress')
            $pos = New-Object System.Collections.Generic.List[string]
            foreach ($t in $rest) {
                if ($t.StartsWith('-')) {
                    if ($allowed -notcontains $t) { Add-GitRefusal $shown "git push z '$t' -- wolno tylko git push origin main (nigdy force)"; return }
                }
                else { $pos.Add($t) }
            }
            if ($pos.Count -ne 2 -or $pos[0] -cne 'origin' -or $pos[1] -cne 'main') {
                Add-GitRefusal $shown 'git push inny niz dokladnie `git push origin main`'
            }
            return
        }
        'branch' {
            $r = Find-GitOptions $rest 'dDmMcCfut' '' @('--delete', '--move', '--copy', '--force', '--set-upstream-to', '--unset-upstream', '--edit-description', '--track', '--no-track', '--create-reflog', '--recurse-submodules') @('--contains', '--no-contains', '--merged', '--no-merged', '--points-at', '--sort', '--format')
            if ($r.Hit) { Add-GitRefusal $shown "git branch z '$($r.Hit)' -- zmiana galezi"; return }
            $listing = $false
            foreach ($o in $r.Options) { if ($o -ceq '-l' -or $o -eq '--list' -or $o -eq '--show-current') { $listing = $true } }
            if ($r.Positionals.Count -gt 0 -and -not $listing) { Add-GitRefusal $shown 'git branch <nazwa> tworzy galaz' }
            return
        }
        'tag' {
            $r = Find-GitOptions $rest 'adfsmFue' '' @('--annotate', '--sign', '--force', '--delete', '--message', '--file', '--local-user', '--edit', '--create-reflog') @('--contains', '--no-contains', '--merged', '--no-merged', '--points-at', '--sort', '--format')
            if ($r.Hit) { Add-GitRefusal $shown "git tag z '$($r.Hit)' -- tworzy albo usuwa tag"; return }
            $listing = $false
            foreach ($o in $r.Options) { if ($o -ceq '-l' -or $o -eq '--list' -or $o -ceq '-v' -or $o -eq '--verify') { $listing = $true } }
            if ($r.Positionals.Count -gt 0 -and -not $listing) { Add-GitRefusal $shown 'git tag <nazwa> tworzy tag' }
            return
        }
        'remote' {
            if ($rest.Count -eq 0) { return }
            $onlyVerbose = $true
            foreach ($t in $rest) { if ($t -ne '-v' -and $t -ne '--verbose') { $onlyVerbose = $false } }
            if ($onlyVerbose) { return }
            $first = $null
            foreach ($t in $rest) { if (-not $t.StartsWith('-')) { $first = $t; break } }
            if ($first -eq 'get-url') { return }
            Add-GitRefusal $shown 'git remote poza odczytem (bez argumentow, -v, get-url)'
            return
        }
        'config' {
            $r = Find-GitOptions $rest 'e' 'f' @('--add', '--unset', '--unset-all', '--replace-all', '--rename-section', '--remove-section', '--edit') @('--file', '--blob', '--type', '--default')
            if ($r.Hit) { Add-GitRefusal $shown "git config z '$($r.Hit)' -- zapis ustawien"; return }
            $reading = $false
            foreach ($o in $r.Options) { if ($o -match '^--(get|get-all|get-regexp|get-urlmatch|get-color|get-colorbool|list)(=|$)' -or $o -ceq '-l') { $reading = $true } }
            if ($r.Positionals.Count -gt 0 -and @('get', 'list') -contains $r.Positionals[0]) { $reading = $true }
            if ($r.Positionals.Count -gt 0 -and @('set', 'unset', 'rename-section', 'remove-section', 'edit') -contains $r.Positionals[0]) { $reading = $false; Add-GitRefusal $shown 'git config - zapis ustawien'; return }
            if (-not $reading -and $r.Positionals.Count -ge 2) { Add-GitRefusal $shown 'git config <klucz> <wartosc> zapisuje ustawienie' }
            return
        }
        default {
            Add-GitRefusal $shown "git $sub -- komenda spoza listy dozwolonych"
            return
        }
    }
}

function Test-Python($Words, [int]$Start) {
    $shown = Format-Shown (New-Slice $Words $Start)
    $a = New-Slice $Words ($Start + 1)
    $exits = @('--version', '-V', '-VV', '--help', '-h', '-?', '--list', '--list-paths', '-0', '-0p')
    foreach ($t in $a) { if ($exits -ccontains $t) { return } }
    $i = 0
    $why = $null
    while ($i -lt $a.Count) {
        $t = $a[$i]
        if ($t -eq '-') { $why = 'interpreter czyta skrypt z wejscia (-)'; break }
        if ($t -eq '--') {
            if ($i + 1 -lt $a.Count -and $a[$i + 1] -ne '-') { return }
            $why = 'interpreter czyta skrypt z wejscia (-)'
            break
        }
        if ($t.StartsWith('--')) {
            if ($t -eq '--check-hash-based-pycs') { $i += 2 } else { $i++ }
            continue
        }
        if ($t.StartsWith('-') -and $t.Length -gt 1) {
            $skipNext = $false
            for ($k = 1; $k -lt $t.Length; $k++) {
                $ch = $t[$k]
                if ($ch -ceq [char]'c' -or $ch -ceq [char]'m') { return }
                if ($ch -ceq [char]'X' -or $ch -ceq [char]'W') { if ($k -eq $t.Length - 1) { $skipNext = $true }; break }
            }
            if ($skipNext) { $i += 2 } else { $i++ }
            continue
        }
        return
    }
    if (-not $why) { $why = 'interpreter bez skryptu, -c i -m czyta wejscie (tryb interaktywny)' }
    $script:Refusals.Add(@(
        "${Tag}: ODMOWA ``$shown`` -- $why; w tym srodowisku taka komenda wisi (retro 3, R1: osiem razy od SPIKE-001).",
        'Zamiast tego: zapisz skrypt w katalogu tymczasowym sesji i uruchom plik (python -I <plik.py>), albo krotko: python -c "...".'
    ) -join "`n")
}

function Get-CommandStart($Words) {
    $i = 0
    while ($i -lt $Words.Count) {
        $t = $Words[$i]
        if ($t -match '^[A-Za-z_][A-Za-z0-9_]*=') { $i++; continue }
        if ($Keywords -contains $t.ToLowerInvariant()) { $i++; continue }
        $b = Get-BaseName $t
        if ($Wrappers -contains $b) {
            $i++
            while ($i -lt $Words.Count -and $Words[$i].StartsWith('-') -and $Words[$i].Length -gt 1) {
                $o = $Words[$i]
                $i++
                if (($b -eq 'nice' -and $o -ceq '-n') -or
                    ($b -eq 'xargs' -and $o -cmatch '^-[IndLPsEa]$') -or
                    ($b -eq 'env' -and $o -cmatch '^-[uCS]$') -or
                    ($b -eq 'timeout' -and $o -cmatch '^-[sk]$') -or
                    ($b -eq 'sudo' -and $o -cmatch '^-[ugCDhpRrTU]$')) { $i++ }
            }
            if ($b -eq 'env') { while ($i -lt $Words.Count -and $Words[$i] -match '^[A-Za-z_][A-Za-z0-9_]*=') { $i++ } }
            if ($b -eq 'timeout' -and $i -lt $Words.Count) { $i++ }
            continue
        }
        break
    }
    return $i
}

function Test-CommandText([string]$Text, [string]$Mode, $Ctx, [int]$Depth) {
    if ($Depth -gt $MaxDepth) { return }
    $T = Split-Command $Text $Mode
    foreach ($seg in $T.Segments) {
        $start = Get-CommandStart $seg
        if ($start -ge $seg.Count) { continue }
        $cmd = Get-BaseName $seg[$start]

        if ($cmd -eq 'git') { Test-Git $seg $start $Ctx.Base; continue }
        if ($cmd -eq 'gh') {
            $script:Refusals.Add(("${Tag}: ODMOWA ``$(Format-Shown (New-Slice $seg $start))`` -- gh zmienia stan na GitHubie; w Grobing robi to tylko autor ($RuleRef)." + "`n" +
                'Zamiast tego: opisz autorowi, co i dlaczego -- wykona to sam po "go".'))
            continue
        }
        if ($cmd -match $PythonName) { Test-Python $seg $start; continue }
        if ($CdCommands -contains $cmd) {
            for ($k = $start + 1; $k -lt $seg.Count; $k++) {
                if (-not $seg[$k].StartsWith('-')) { $Ctx.Base = Resolve-GuardPath $seg[$k] $Ctx.Base; break }
            }
            continue
        }
        if ($PosixShells -contains $cmd) {
            $hasC = $false
            for ($k = $start + 1; $k -lt $seg.Count; $k++) {
                $t = $seg[$k]
                if (-not $hasC -and $t -cmatch '^-[a-zA-Z]*c[a-zA-Z]*$') { $hasC = $true; continue }
                if ($t.StartsWith('-')) { continue }
                if ($hasC) { Test-CommandText $t 'bash' $Ctx ($Depth + 1) }
                break
            }
            continue
        }
        if ($PsShells -contains $cmd) {
            for ($k = $start + 1; $k -lt $seg.Count; $k++) {
                $t = $seg[$k]
                if ($t -match '^[-/](c|co|com|comm|comma|comman|command)$') {
                    $inner = (New-Slice $seg ($k + 1)) -join ' '
                    Test-CommandText $inner 'ps' $Ctx ($Depth + 1)
                    break
                }
                if ($t -match '^[-/](e|ec|en|enc|enco|encod|encode|encoded|encodedc|encodedco|encodedcom|encodedcomm|encodedcomma|encodedcomman|encodedcommand)$' -and $k + 1 -lt $seg.Count) {
                    $inner = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($seg[$k + 1]))
                    Test-CommandText $inner 'ps' $Ctx ($Depth + 1)
                    break
                }
            }
            continue
        }
    }
    foreach ($inner in $T.Nested) { Test-CommandText $inner $Mode $Ctx ($Depth + 1) }
}

# ---------------------------------------------------------------- main

try {
    $raw = Read-Stdin
    if ([string]::IsNullOrWhiteSpace($raw)) { throw 'puste wejscie -- brak JSON-a na stdin' }
    $hook = $raw | ConvertFrom-Json
    $tool = [string]$hook.tool_name
    if ($ShellTools -notcontains $tool) { exit 0 }
    if ($null -eq $hook.tool_input -or $null -eq $hook.tool_input.command) { throw "brak tool_input.command w wejsciu narzedzia $tool" }
    $command = [string]$hook.tool_input.command

    $base = [string]$hook.cwd
    if (-not $base) { $base = $env:CLAUDE_PROJECT_DIR }
    if (-not $base) { $base = (Get-Location).Path }
    $ctx = [pscustomobject]@{ Base = (Resolve-GuardPath $base $null) }
    $mode = 'bash'
    if ($tool -eq 'PowerShell') { $mode = 'ps' }

    Test-CommandText $command $mode $ctx 0

    if ($script:Refusals.Count -gt 0) {
        $shownRefusals = @($script:Refusals | Select-Object -First 3)
        $text = $shownRefusals -join "`n`n"
        if ($script:Refusals.Count -gt 3) { $text += "`n... i jeszcze $($script:Refusals.Count - 3)" }
        Stop-Refuse $text
    }
    exit 0
}
catch {
    Write-Utf8 ([Console]::OpenStandardError()) ("${Tag}: blad straznika komend -- $($_.Exception.Message)" + "`n" +
        'Straznik blokuje, gdy nie umie sprawdzic (fail-closed). Napraw .claude/hooks/command-guard.ps1 albo jego wejscie.')
    exit 2
}
