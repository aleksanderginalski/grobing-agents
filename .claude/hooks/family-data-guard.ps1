<#
    family-data-guard.ps1 -- PreToolUse hook: refuses family-data FILES in any Grobing repo.

    WHY IT EXISTS. ISSUE-006 (T-05 from the kick-off, MD3h). The one irreversible action in Grobing
    is pushing family data to a public repo: git history and search indexes keep it. The rule
    (.claude/rules/family-data.md) is prose a model can skip; this hook is run by the harness, always.

    WHAT IT DOES
      Write | Edit | MultiEdit | NotebookEdit
        refuses a file inside grobing-agents, grobing-vault or grobing-code whose TYPE or ROOT
        FOLDER marks family data (THE LIST below). Files outside the three repos pass (scratchpad,
        _throwaway/).
      Bash | PowerShell -- only commands that run `git add` or `git commit`
        refuses `git add -f/--force` outright. Otherwise looks at what could land in a commit in each
        of the three repos (the index + changed and untracked files that .gitignore does not hide)
        and refuses if any of them is on THE LIST. It does not parse pathspecs on purpose: `.`, `-A`,
        `-u`, `-C`, `commit -am` all end up in the same place.

    WHAT IT DOES NOT CATCH
      - content: a real name typed into code or a document (ISSUE-003, the critic);
      - a file written by a shell command (cp, >, adb pull) at the moment it is written -- only at
        the next git add/commit;
      - the author's own commit from VS Code -- there only .gitignore protects (same list);
      - an edit to this script or to .gitignore -- visible in the diff at stop #3.

    THE LIST -- keep identical to the family-data block in .gitignore of all three repos
      databases  *.db *.db-journal *.db-wal *.db-shm *.sqlite *.sqlite3 *.sqlite-*
      backup     *.age *.tar                                                  (ADR-004)
      export     *.html *.pdf                                                 (ADR-004)
      media      *.jpg *.jpeg *.png *.heic *.heif *.webp *.gif *.bmp *.tif *.tiff *.dng *.mp4 *.mov
                 the only exception: png/jpg/jpeg/gif/webp under grobing-code/android/app/src/main/res/
      folders    /exports/ /backups/ /family-data/ /real-data/ at a repo root

    PATHS. No absolute path anywhere: grobing-agents is two levels above this script; the vault and
    the code come from .claude/rules/project-config.md (vault_local_path, code_local_path).

    EXIT CODES: 0 = allow, 2 = refuse (stderr is fed back to Claude). FAIL-CLOSED: any error, a
    missing config or a missing repo folder is also 2 -- Claude Code treats exit 1 as non-blocking,
    so an unhandled exception would be a silent pass. Messages are ASCII on purpose: Windows
    PowerShell 5.1 reads a BOM-less .ps1 as ANSI.
#>

[CmdletBinding()]
param(
    # Tests only. Default: .claude/rules/project-config.md of the repo this script lives in.
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

$Tag = 'family-data-guard (ISSUE-006)'
$RuleRef = 'grobing-agents/.claude/rules/family-data.md'
$AgentsRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

$WriteTools = @('Write', 'Edit', 'MultiEdit', 'NotebookEdit')
$ShellTools = @('Bash', 'PowerShell')
$MediaExt = @('jpg', 'jpeg', 'png', 'heic', 'heif', 'webp', 'gif', 'bmp', 'tif', 'tiff', 'dng', 'mp4', 'mov')
$UiImageExt = @('png', 'jpg', 'jpeg', 'gif', 'webp')
$UiImageDir = 'android/app/src/main/res/'
$RootFolders = @('exports', 'backups', 'family-data', 'real-data')

# `git [-C dir | -c k=v | --option]... add|commit` -- also /usr/bin/git and git.exe
$GitAddOrCommit = '(?i)(?<![\w.-])git(?:\.exe)?(?:\s+(?:-C|-c)\s+(?:"[^"]*"|''[^'']*''|\S+)|\s+--?[a-z][\w-]*(?:=\S+)?)*\s+(add|commit)(?![\w-])'

function Write-Refusal([string]$Text) {
    # UTF-8 bytes, so a path with Polish letters reaches Claude intact.
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text + "`n")
    $err = [Console]::OpenStandardError()
    $err.Write($bytes, 0, $bytes.Length)
    $err.Flush()
}

function Stop-Refuse([string]$Text) {
    Write-Refusal $Text
    exit 2
}

function Stop-Config([string]$Detail) {
    Stop-Refuse ($Tag + ': nie znam sciezek repo -- ' + $Detail + '.' + "`n" +
        'Autor: skopiuj grobing-agents/.claude/rules/project-config.example.md do project-config.md ' +
        'i uzupelnij sciezki (recznie). Do tego czasu zapis plikow i git add/commit sa zablokowane.')
}

function Read-Stdin {
    $in = [Console]::OpenStandardInput()
    $ms = New-Object System.IO.MemoryStream
    $in.CopyTo($ms)
    return [System.Text.Encoding]::UTF8.GetString($ms.ToArray()).TrimStart([char]0xFEFF)
}

# Forward slashes, Git Bash drive paths (/c/...) to drive-letter form, relative -> against $Base,
# . and .. collapsed.
# Case is preserved for messages; callers compare in lower case.
function ConvertTo-GuardPath([string]$Path, [string]$Base) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $p = $Path.Trim().Trim('"').Trim("'") -replace '\\', '/'
    if ($p -match '^/([a-zA-Z])(/.*)?$') { $p = $Matches[1] + ':' + $Matches[2] }
    if ($p -notmatch '^[a-zA-Z]:') {
        # Not a Windows path and nothing to resolve it against: outside every repo.
        if ($p.StartsWith('/') -or [string]::IsNullOrWhiteSpace($Base)) { return $p }
        $p = (ConvertTo-GuardPath $Base $null) + '/' + $p
    }
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($seg in $p.Split('/')) {
        if ($seg -eq '' -or $seg -eq '.') { continue }
        if ($seg -eq '..') {
            if ($parts.Count -gt 1) { $parts.RemoveAt($parts.Count - 1) }
            continue
        }
        $parts.Add($seg)
    }
    return ($parts -join '/')
}

function Get-ConfigValue([string]$Text, [string]$Key) {
    $m = [regex]::Match($Text, '(?m)^\s*' + [regex]::Escape($Key) +
        '\s*:\s*(?:"((?:[^"\\]|\\.)*)"|''([^'']*)''|([^\s#]+))')
    if (-not $m.Success) { return $null }
    if ($m.Groups[1].Success) { return ($m.Groups[1].Value -replace '\\\\', '\') }
    if ($m.Groups[2].Success) { return $m.Groups[2].Value }
    return $m.Groups[3].Value
}

function Get-Repos {
    $cfg = if ($ConfigPath) { $ConfigPath } else { Join-Path $AgentsRoot '.claude/rules/project-config.md' }
    if (-not (Test-Path -LiteralPath $cfg -PathType Leaf)) { Stop-Config "brak pliku $cfg" }
    $text = [System.IO.File]::ReadAllText($cfg, [System.Text.Encoding]::UTF8)

    $roots = [ordered]@{ 'grobing-agents' = $AgentsRoot }
    foreach ($pair in @(@('grobing-vault', 'vault_local_path'), @('grobing-code', 'code_local_path'))) {
        $value = Get-ConfigValue $text $pair[1]
        if ([string]::IsNullOrWhiteSpace($value)) { Stop-Config "brak wartosci $($pair[1]) w $cfg" }
        if (-not (Test-Path -LiteralPath $value -PathType Container)) {
            Stop-Config "$($pair[1]) wskazuje katalog, ktorego nie ma: $value"
        }
        $roots[$pair[0]] = $value
    }

    $repos = @()
    foreach ($name in $roots.Keys) {
        $root = ([string]$roots[$name]).TrimEnd('\', '/')
        $repos += [pscustomobject]@{ Name = $name; Root = $root; Norm = (ConvertTo-GuardPath $root $null).ToLowerInvariant() }
    }
    return $repos
}

function Find-Repo($Repos, [string]$GuardPath) {
    $lower = $GuardPath.ToLowerInvariant()
    foreach ($r in $Repos) {
        if ($lower.StartsWith($r.Norm + '/')) {
            return [pscustomobject]@{ Repo = $r; Rel = $GuardPath.Substring($r.Norm.Length + 1) }
        }
    }
    return $null
}

# $Rel: path relative to the repo root, forward slashes. Returns the category or $null.
function Get-FamilyCategory([string]$RepoName, [string]$Rel) {
    $rel = $Rel.ToLowerInvariant()
    $segs = $rel.Split('/')
    if ($segs.Count -gt 1 -and $RootFolders -contains $segs[0]) { return "katalog danych rodziny /$($segs[0])/" }

    $name = $segs[-1]
    if ($name -match '\.(db|db-journal|db-wal|db-shm|sqlite|sqlite3)$' -or $name -match '\.sqlite-') { return 'baza danych' }
    if ($name -match '\.(age|tar)$') { return 'kopia (age/tar, ADR-004)' }
    if ($name -match '\.(html|pdf)$') { return 'eksport (HTML/PDF, ADR-004)' }

    $ext = if ($name.Contains('.')) { $name.Substring($name.LastIndexOf('.') + 1) } else { '' }
    if ($MediaExt -contains $ext) {
        if ($RepoName -eq 'grobing-code' -and $rel.StartsWith($UiImageDir) -and $UiImageExt -contains $ext) { return $null }
        return 'zdjecie albo film'
    }
    return $null
}

function Invoke-Git([string]$Root, [string]$Arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $psi.Arguments = "-C `"$Root`" $Arguments"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $proc = [System.Diagnostics.Process]::Start($psi)
    $out = $proc.StandardOutput.ReadToEnd()
    $err = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) { throw "git $Arguments w $Root zwrocil $($proc.ExitCode): $err" }
    return $out
}

# Everything that could land in the next commit: the index (deletions excluded -- removing a family
# file is the cure, not the disease) + changed and untracked files .gitignore does not hide.
function Get-CommitCandidates([string]$Root) {
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($t in (Invoke-Git $Root 'diff --cached --name-only -z --diff-filter=d').Split([char]0)) {
        if ($t) { $paths.Add($t) }
    }
    foreach ($t in (Invoke-Git $Root 'status --porcelain=v1 -z --untracked-files=all').Split([char]0)) {
        if (-not $t) { continue }
        if ($t.Length -gt 3 -and $t[2] -eq ' ' -and $t.Substring(0, 2) -match '^[ MTADRCU?!]{2}$') {
            if ($t.Substring(0, 2).Contains('D')) { continue }
            $paths.Add($t.Substring(3))
        } else {
            # the source path of a rename (porcelain -z puts it in its own field)
            $paths.Add($t)
        }
    }
    return $paths
}

try {
    $raw = Read-Stdin
    if ([string]::IsNullOrWhiteSpace($raw)) { throw 'puste wejscie -- brak JSON-a na stdin' }
    $hook = $raw | ConvertFrom-Json
    $tool = [string]$hook.tool_name
    $toolInput = $hook.tool_input

    if ($WriteTools -contains $tool) {
        $path = [string]$toolInput.file_path
        if (-not $path) { $path = [string]$toolInput.notebook_path }
        if (-not $path) { throw "brak file_path/notebook_path w wejsciu narzedzia $tool -- nie wiem, co sprawdzic" }

        $repos = Get-Repos
        $guardPath = ConvertTo-GuardPath $path ([string]$hook.cwd)
        $hit = Find-Repo $repos $guardPath
        if ($hit) {
            $category = Get-FamilyCategory $hit.Repo.Name $hit.Rel
            if ($category) {
                Stop-Refuse (@(
                    "${Tag}: ODMOWA zapisu $($hit.Repo.Name)/$($hit.Rel)",
                    "Powod: $category -- plik tego typu wyglada na dane rodziny, a dane rodziny nigdy nie trafiaja do zadnego repo Grobing ($RuleRef).",
                    'Zamiast tego: dane testowe tylko z wymyslonymi osobami; baza w pamieci albo plik w katalogu tymczasowym POZA trzema repo.',
                    'Jesli to naprawde nie sa dane rodziny (np. grafika UI), wyjatek dopisuje sie swiadomie -- w tym skrypcie i w .gitignore trzech repo -- po decyzji autora.'
                ) -join "`n")
            }
        }
        exit 0
    }

    if ($ShellTools -contains $tool) {
        $command = [string]$toolInput.command
        $gitCalls = [regex]::Matches($command, $GitAddOrCommit)
        if ($gitCalls.Count -eq 0) { exit 0 }

        foreach ($call in $gitCalls) {
            if ($call.Groups[1].Value.ToLowerInvariant() -ne 'add') { continue }
            $rest = $command.Substring($call.Index + $call.Length)
            $cut = $rest.IndexOfAny([char[]]";&|`r`n")
            if ($cut -ge 0) { $rest = $rest.Substring(0, $cut) }
            if ($rest -match '(?i)(^|\s)(--force|-[a-z]*f[a-z]*)(?=\s|$)') {
                Stop-Refuse ("${Tag}: ODMOWA 'git add -f/--force' -- wymuszone dodanie omija .gitignore, ktory chroni dane rodziny ($RuleRef)." + "`n" +
                    'Jesli plik naprawde musi wejsc do repo, autor dodaje go sam, po sprawdzeniu.')
            }
        }

        $found = @()
        foreach ($r in Get-Repos) {
            foreach ($p in Get-CommitCandidates $r.Root) {
                $rel = $p -replace '\\', '/'
                $category = Get-FamilyCategory $r.Name $rel
                if ($category) { $found += "  - $($r.Name)/$rel ($category)" }
            }
        }
        if ($found.Count -gt 0) {
            Stop-Refuse (@(
                "${Tag}: ODMOWA 'git add/commit' -- w repo leza pliki, ktore wygladaja na dane rodziny i moglyby wejsc do commita:"
            ) + $found + @(
                "Przenies je poza repo albo usun -- dane rodziny zyja tylko w telefonie, w zaszyfrowanej kopii i w eksporcie u rodziny ($RuleRef).",
                'Plik juz w indeksie wyjmuje sie z niego (git restore --staged) -- to zmiana stanu git, wiec agent najpierw pyta autora. Wyjatkow nie dopisuj bez decyzji autora.'
            ) -join "`n")
        }
        exit 0
    }

    exit 0
}
catch {
    Write-Refusal ("${Tag}: blad straznika -- $($_.Exception.Message)" + "`n" +
        'Straznik blokuje, gdy nie umie sprawdzic (fail-closed). Napraw .claude/hooks/family-data-guard.ps1 albo jego wejscie.')
    exit 2
}
