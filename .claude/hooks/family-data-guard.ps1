<#
    family-data-guard.ps1 -- PreToolUse hook: refuses family-data FILES (ISSUE-006) and family-data
    CONTENT from the author's stem list (ISSUE-020) in any Grobing repo.

    WHY IT EXISTS. ISSUE-006 (T-05 from the kick-off, MD3h). The one irreversible action in Grobing
    is pushing family data to a public repo: git history and search indexes keep it. The rule
    (.claude/rules/family-data.md) is prose a model can skip; this hook is run by the harness, always.
    ISSUE-020 (retro 2, R1): push runs on its own right after the package commit, and the agent may
    not read the author's notes, so the content check has to live here, where no agent reads the list.

    WHAT IT DOES
      Write | Edit | MultiEdit | NotebookEdit
        refuses a file inside grobing-agents, grobing-vault or grobing-code whose TYPE or ROOT
        FOLDER marks family data (THE LIST below). Files outside the three repos pass (scratchpad,
        _throwaway/).
      Bash | PowerShell -- only commands that run `git add` or `git commit`
        1. refuses `git add -f/--force` outright;
        2. FILES: looks at what could land in a commit in each of the three repos (the index +
           changed and untracked files that .gitignore does not hide) and refuses if any of them is
           on THE LIST. It does not parse pathspecs on purpose: `.`, `-A`, `-u`, `-C`, `commit -am`
           all end up in the same place;
        3. CONTENT (ISSUE-020): refuses if a stem from THE STEMS starts a word in: lines added in
           `git diff --cached` and `git diff`, untracked files .gitignore does not hide, the paths
           of all of these, the command text itself (a message in -m or in a heredoc for -F -) and a
           message file given with -F <file>. The refusal names repo, file, line and the line
           number IN THE LIST -- never the word and never the line: stderr goes back into the chat.
      -ScanTracked (run by hand, never by the harness)
        the same content check over every tracked file of the three repos, read from the working
        tree (equal to HEAD when the repos are clean). Prints counts and repo/file:line, never the
        word. Exit 0 = no hit, 1 = hits, 2 = error.

    WHAT IT DOES NOT CATCH
      - first names, codes and numbers, words that are not on the list, typos, an inflection that
        changes the stem;
      - lines removed by earlier commits (history) and anything already pushed;
      - a file written by a shell command (cp, >, adb pull) at the moment it is written -- only at
        the next git add/commit;
      - binary files -- THE LIST covers the family-data types; other binaries are not read;
      - the author's own commit from VS Code -- there only .gitignore protects (types, not content);
      - an edit to this script or to .gitignore -- visible in `git diff --cached --stat` in the
        reply before the commit (R1).

    THE LIST -- keep identical to the family-data block in .gitignore of all three repos
      databases  *.db *.db-journal *.db-wal *.db-shm *.sqlite *.sqlite3 *.sqlite-*
      backup     *.age *.tar                                                  (ADR-004)
      export     *.html *.pdf                                                 (ADR-004)
      media      *.jpg *.jpeg *.png *.heic *.heif *.webp *.gif *.bmp *.tif *.tiff *.dng *.mp4 *.mov
                 the only exception: png/jpg/jpeg/gif/webp under grobing-code/android/app/src/main/res/
      folders    /exports/ /backups/ /family-data/ /real-data/ at a repo root

    THE STEMS (ISSUE-020)
      file       {family_data_dir}/rdzenie-straznika.txt, family_data_dir from project-config.md.
                 Written by the author, or by an agent at the author's request in the session
                 (author's decision 2026-10-08: names in the chat are fine; what must not happen is
                 publishing who is buried where on GitHub).
      format     one stem per line; a line starting with # is a comment; empty lines are skipped.
                 UTF-8 (with or without BOM), UTF-16 with BOM, or Windows-1250 ("ANSI" in Notepad).
      matching   diacritics folded on both sides (a-ogonek -> a, l-stroke -> l, ...), case ignored.
                 A stem matches at the START of a word: after a non-letter, or where a lower-case
                 letter is followed by an upper-case one (someSurname). Whitespace inside a stem
                 matches any run of whitespace.
      refused    no list, an unreadable list, a list without stems, or a stem with fewer than 3
                 letters/digits -> every git add/commit is refused (fail-closed).

    PATHS. No absolute path anywhere: grobing-agents is two levels above this script; the vault, the
    code and family_data_dir come from .claude/rules/project-config.md.

    EXIT CODES: 0 = allow, 2 = refuse (stderr is fed back to Claude). FAIL-CLOSED: any error, a
    missing config or a missing repo folder is also 2 -- Claude Code treats exit 1 as non-blocking,
    so an unhandled exception would be a silent pass. Messages are ASCII on purpose: Windows
    PowerShell 5.1 reads a BOM-less .ps1 as ANSI. For the same reason the folding map is built from
    code points, not typed letters.
#>

[CmdletBinding()]
param(
    # Tests only. Default: .claude/rules/project-config.md of the repo this script lives in.
    [string]$ConfigPath,
    # By hand: content check over all tracked files of the three repos (ISSUE-020, D7).
    [switch]$ScanTracked
)

$ErrorActionPreference = 'Stop'

$Tag = 'family-data-guard (ISSUE-006)'
$ContentTag = 'family-data-guard (ISSUE-020)'
$RuleRef = 'grobing-agents/.claude/rules/family-data.md'
$AgentsRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

$WriteTools = @('Write', 'Edit', 'MultiEdit', 'NotebookEdit')
$ShellTools = @('Bash', 'PowerShell')
$MediaExt = @('jpg', 'jpeg', 'png', 'heic', 'heif', 'webp', 'gif', 'bmp', 'tif', 'tiff', 'dng', 'mp4', 'mov')
$UiImageExt = @('png', 'jpg', 'jpeg', 'gif', 'webp')
$UiImageDir = 'android/app/src/main/res/'
$RootFolders = @('exports', 'backups', 'family-data', 'real-data')

$StemsFileName = 'rdzenie-straznika.txt'
$MinStemChars = 3
$MaxScanBytes = 20MB
$MaxReported = 20
$GitOpts = '-c core.quotepath=off -c color.ui=never -c core.safecrlf=false'
$DiffOpts = '-U0 --no-renames --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/'

$script:ConfigText = $null
$script:ConfigFile = $null
$script:HitLines = New-Object System.Collections.Generic.List[string]
$script:HitCount = 0

# `git [-C dir | -c k=v | --option]... add|commit` -- also /usr/bin/git and git.exe
$GitAddOrCommit = '(?i)(?<![\w.-])git(?:\.exe)?(?:\s+(?:-C|-c)\s+(?:"[^"]*"|''[^'']*''|\S+)|\s+--?[a-z][\w-]*(?:=\S+)?)*\s+(add|commit)(?![\w-])'

function Write-Utf8([System.IO.Stream]$Stream, [string]$Text) {
    # UTF-8 bytes, so a path with Polish letters reaches Claude intact.
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text + "`n")
    $Stream.Write($bytes, 0, $bytes.Length)
    $Stream.Flush()
}

function Write-Refusal([string]$Text) {
    Write-Utf8 ([Console]::OpenStandardError()) $Text
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

function Stop-Stems([string]$Detail) {
    Stop-Refuse ($ContentTag + ': ' + $Detail + '.' + "`n" +
        "Lista rdzeni to $StemsFileName w family_data_dir (project-config.md) -- jeden rdzen w linii; " +
        'pisze ja autor albo agent na prosbe autora (family-data.md). ' +
        'Do tego czasu git add/commit sa zablokowane (fail-closed).')
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
    $script:ConfigText = $text
    $script:ConfigFile = $cfg

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
    # stderr read in the background: a full stderr pipe (CRLF warnings for many files) must not
    # block git while this script waits on stdout.
    $errTask = $proc.StandardError.ReadToEndAsync()
    $out = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) { throw "git $Arguments w $Root zwrocil $($proc.ExitCode): $($errTask.Result)" }
    return $out
}

# Everything that could land in the next commit: the index (deletions excluded -- removing a family
# file is the cure, not the disease) + changed and untracked files .gitignore does not hide.
# Also tells the content check which diffs are worth running.
function Get-CommitCandidates([string]$Root) {
    $paths = New-Object System.Collections.Generic.List[string]
    $untracked = New-Object System.Collections.Generic.List[string]
    $staged = $false
    $worktree = $false
    foreach ($t in (Invoke-Git $Root 'diff --cached --name-only -z --diff-filter=d').Split([char]0)) {
        if ($t) { $paths.Add($t); $staged = $true }
    }
    $fields = (Invoke-Git $Root 'status --porcelain=v1 -z --untracked-files=all').Split([char]0)
    for ($i = 0; $i -lt $fields.Count; $i++) {
        $t = $fields[$i]
        if (-not $t) { continue }
        if ($t.Length -lt 4 -or $t[2] -ne ' ' -or $t.Substring(0, 2) -cnotmatch '^[ MTADRCU?!]{2}$') {
            throw "nieznany wpis git status w ${Root}: $t"
        }
        $xy = $t.Substring(0, 2)
        $path = $t.Substring(3)
        if ($xy -eq '??') { $untracked.Add($path) }
        else {
            if ($xy[0] -ne ' ') { $staged = $true }
            if ($xy[1] -ne ' ') { $worktree = $true }
        }
        if (-not $xy.Contains('D')) { $paths.Add($path) }
        # a rename or copy puts its source path in the next field (porcelain -z)
        if ($xy -cmatch '[RC]' -and $i + 1 -lt $fields.Count) {
            $i++
            if ($fields[$i]) { $paths.Add($fields[$i]) }
        }
    }
    $unique = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($p in $paths) { if ($seen.Add($p)) { $unique.Add($p) } }
    return [pscustomobject]@{ Paths = $unique; Untracked = $untracked; Staged = $staged; Worktree = $worktree }
}

# --- content check (ISSUE-020) ------------------------------------------------------------------

# Folding map (D4): every Latin letter with a diacritic in U+00C0..U+017F -> its ASCII base, plus
# the letters NFD does not decompose (l-stroke, d-stroke, o-slash). Built from code points, so this
# file stays ASCII.
function New-FoldMap {
    $toBase = @{}
    foreach ($cp in 0x00C0..0x017F) {
        $d = ([string][char]$cp).Normalize([System.Text.NormalizationForm]::FormD)
        if ($d.Length -gt 1 -and $d[0] -cmatch '^[A-Za-z]$') { $toBase[[int]$cp] = ([string]$d[0]).ToLowerInvariant() }
    }
    foreach ($pair in @(@(0x0141, 'l'), @(0x0142, 'l'), @(0x0110, 'd'), @(0x0111, 'd'), @(0x00D8, 'o'), @(0x00F8, 'o'))) {
        $toBase[[int]$pair[0]] = $pair[1]
    }
    $classes = @{}
    foreach ($c in 97..122) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append([char]$c).Append([char]($c - 32))
        $classes[[string][char]$c] = $sb
    }
    foreach ($cp in $toBase.Keys) { [void]$classes[$toBase[$cp]].Append([char]$cp) }
    return [pscustomobject]@{ ToBase = $toBase; Classes = $classes }
}

function ConvertTo-FoldedStem([string]$Stem, $Fold) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Stem.ToCharArray()) {
        $cp = [int]$ch
        if ($Fold.ToBase.ContainsKey($cp)) { [void]$sb.Append($Fold.ToBase[$cp]) }
        else { [void]$sb.Append(([string]$ch).ToLowerInvariant()) }
    }
    return $sb.ToString()
}

# A folded stem -> a regex that matches it with any diacritic and any case, without IgnoreCase (so
# \p{Lu} and \p{Ll} in the word-start test keep their meaning).
function ConvertTo-StemPattern([string]$Folded, $Fold) {
    $sb = New-Object System.Text.StringBuilder
    $prevSpace = $false
    foreach ($ch in $Folded.ToCharArray()) {
        if ([char]::IsWhiteSpace($ch)) {
            if (-not $prevSpace) { [void]$sb.Append('\s+') }
            $prevSpace = $true
            continue
        }
        $prevSpace = $false
        $s = [string]$ch
        if ($s -cmatch '^[a-z]$') { [void]$sb.Append('[').Append($Fold.Classes[$s].ToString()).Append(']') }
        elseif ([char]::IsLetter($ch)) {
            [void]$sb.Append('[').Append([regex]::Escape($s.ToLowerInvariant())).Append([regex]::Escape($s.ToUpperInvariant())).Append(']')
        }
        else { [void]$sb.Append([regex]::Escape($s)) }
    }
    return $sb.ToString()
}

function ConvertFrom-ListBytes([byte[]]$Bytes) {
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }
    $start = 0
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { $start = 3 }
    try {
        return (New-Object System.Text.UTF8Encoding($false, $true)).GetString($Bytes, $start, $Bytes.Length - $start)
    }
    catch {
        # not valid UTF-8: Notepad "ANSI" on a Polish Windows
        return [System.Text.Encoding]::GetEncoding(1250).GetString($Bytes)
    }
}

# The author's list -> one regex. Each stem is a named group, so a hit can name its LINE IN THE LIST
# without naming the stem.
function Get-Stems {
    $dir = Get-ConfigValue $script:ConfigText 'family_data_dir'
    if ([string]::IsNullOrWhiteSpace($dir)) { Stop-Stems "brak wartosci family_data_dir w $($script:ConfigFile)" }
    $file = Join-Path $dir $StemsFileName
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Stop-Stems "brak listy rdzeni $file" }

    $text = ConvertFrom-ListBytes ([System.IO.File]::ReadAllBytes($file))
    $fold = New-FoldMap
    $stems = @()
    $lines = $text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $folded = ConvertTo-FoldedStem $t $fold
        if (($folded -replace '[^\p{L}\p{N}]', '').Length -lt $MinStemChars) {
            Stop-Stems "linia $($i + 1) listy ma mniej niz $MinStemChars litery albo cyfry -- popraw ja w $file"
        }
        $stems += [pscustomobject]@{ ListLine = $i + 1; Pattern = (ConvertTo-StemPattern $folded $fold) }
    }
    if ($stems.Count -eq 0) { Stop-Stems "lista $file nie ma zadnego rdzenia" }

    $alts = for ($k = 0; $k -lt $stems.Count; $k++) { "(?<s$k>" + $stems[$k].Pattern + ')' }
    # word start: no letter before, or a lower-case letter followed by an upper-case one (camelCase);
    # the trailing \p{L}* takes the whole word, so masking hides all of it
    $pattern = '(?:(?<!\p{L})|(?<=\p{Ll})(?=\p{Lu}))(?:' + ($alts -join '|') + ')\p{L}*'
    $regex = New-Object System.Text.RegularExpressions.Regex($pattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
    return [pscustomobject]@{ Regex = $regex; Stems = $stems }
}

function Get-ListLine($Matcher, $Match) {
    for ($k = 0; $k -lt $Matcher.Stems.Count; $k++) {
        if ($Match.Groups["s$k"].Success) { return $Matcher.Stems[$k].ListLine }
    }
    return 0
}

function Get-Masked($Matcher, [string]$Text) {
    return $Matcher.Regex.Replace($Text, '***')
}

function Add-HitLine([string]$Line) {
    $script:HitCount++
    if ($script:HitLines.Count -lt $MaxReported) { $script:HitLines.Add($Line) }
}

function Add-Hit([string]$Where, $Line, [int]$ListLine) {
    $at = if ($Line) { "${Where}:$Line" } else { $Where }
    Add-HitLine "  - $at (linia $ListLine listy)"
}

# Every hit in $Text with its 1-based line number. $Where is already masked.
function Add-TextHits($Matcher, [string]$Where, [string]$Text) {
    if (-not $Text) { return }
    $m = $Matcher.Regex.Match($Text)
    $line = 1
    $pos = 0
    while ($m.Success) {
        if ($script:HitLines.Count -ge $MaxReported) { $script:HitCount++; $m = $m.NextMatch(); continue }
        $nl = $Text.IndexOf([char]10, $pos)
        while ($nl -ge 0 -and $nl -lt $m.Index) { $line++; $nl = $Text.IndexOf([char]10, $nl + 1) }
        $pos = $m.Index
        Add-Hit $Where $line (Get-ListLine $Matcher $m)
        $m = $m.NextMatch()
    }
}

function Add-PathHit($Matcher, $Repo, [string]$Rel) {
    $m = $Matcher.Regex.Match($Rel)
    if ($m.Success) { Add-Hit ("nazwa pliku $($Repo.Name)/" + (Get-Masked $Matcher $Rel)) $null (Get-ListLine $Matcher $m) }
}

# A text file from disk; binary (a zero byte in the first 8000 bytes) is skipped, a file too big to
# read is a hit (fail-closed).
function Add-FileHits($Matcher, [string]$Where, [string]$FullPath) {
    $info = Get-Item -LiteralPath $FullPath -Force -ErrorAction SilentlyContinue
    if (-not $info -or $info.PSIsContainer) { return }
    if ($info.Length -gt $MaxScanBytes) {
        Add-HitLine "  - $Where (plik wiekszy niz $($MaxScanBytes / 1MB) MB -- tresci nie sprawdzono)"
        return
    }
    $bytes = [System.IO.File]::ReadAllBytes($FullPath)
    if ([Array]::IndexOf($bytes, [byte]0, 0, [Math]::Min($bytes.Length, 8000)) -ge 0) { return }
    Add-TextHits $Matcher $Where ([System.Text.Encoding]::UTF8.GetString($bytes))
}

function ConvertFrom-DiffPath([string]$Text) {
    $t = $Text.TrimEnd([char]9)
    if ($t.StartsWith('"') -and $t.EndsWith('"') -and $t.Length -ge 2) {
        $t = $t.Substring(1, $t.Length - 2) -replace '\\t', "`t" -replace '\\"', '"' -replace '\\\\', '\'
    }
    if ($t -eq '/dev/null') { return $null }
    if ($t.StartsWith('b/')) { return $t.Substring(2) }
    return $t
}

# Lines added in a `git diff -U0` output, with line numbers of the new side. The whole output is
# matched once first; the line-by-line walk runs only when something matched.
function Add-DiffHits($Matcher, $Repo, [string]$DiffText) {
    if (-not $DiffText -or -not $Matcher.Regex.IsMatch($DiffText)) { return }
    $file = $null
    $inHunk = $false
    $newLine = 0
    foreach ($raw in $DiffText.Split([char]10)) {
        $l = $raw.TrimEnd([char]13)
        if ($l.StartsWith('diff --git ')) { $file = $null; $inHunk = $false; continue }
        if ($l -match '^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@') { $inHunk = $true; $newLine = [int]$Matches[1]; continue }
        if (-not $inHunk) {
            if ($l.StartsWith('+++ ')) { $file = ConvertFrom-DiffPath $l.Substring(4) }
            continue
        }
        if ($l.Length -eq 0) { continue }
        $c = $l[0]
        if ($c -eq '+') {
            if ($file) {
                $m = $Matcher.Regex.Match($l.Substring(1))
                if ($m.Success) { Add-Hit ("$($Repo.Name)/" + (Get-Masked $Matcher $file)) $newLine (Get-ListLine $Matcher $m) }
            }
            $newLine++
        }
        elseif ($c -eq ' ') { $newLine++ }
    }
}

function Add-RepoContentHits($Matcher, $Repo, $State) {
    foreach ($p in $State.Paths) { Add-PathHit $Matcher $Repo ($p -replace '\\', '/') }
    if ($State.Staged) { Add-DiffHits $Matcher $Repo (Invoke-Git $Repo.Root "$GitOpts diff --cached $DiffOpts") }
    if ($State.Worktree) { Add-DiffHits $Matcher $Repo (Invoke-Git $Repo.Root "$GitOpts diff $DiffOpts") }
    foreach ($u in $State.Untracked) {
        $rel = $u -replace '\\', '/'
        Add-FileHits $Matcher ("$($Repo.Name)/" + (Get-Masked $Matcher $rel)) (Join-Path $Repo.Root $rel)
    }
}

# The command text (commit message in -m or in a heredoc) and a message file given with -F <file>.
function Add-CommandHits($Matcher, [string]$Command, $GitCalls, [string]$Cwd) {
    $m = $Matcher.Regex.Match($Command)
    if ($m.Success) { Add-Hit 'tekst komendy (opis commita albo inny tekst w komendzie)' $null (Get-ListLine $Matcher $m) }
    foreach ($call in $GitCalls) {
        if ($call.Groups[1].Value.ToLowerInvariant() -ne 'commit') { continue }
        $rest = $Command.Substring($call.Index + $call.Length)
        $cut = $rest.IndexOfAny([char[]]";&|`r`n")
        if ($cut -ge 0) { $rest = $rest.Substring(0, $cut) }
        foreach ($f in [regex]::Matches($rest, '(?:^|\s)(?:-F|--file)(?:\s+|=)("[^"]*"|''[^'']*''|\S+)')) {
            $value = $f.Groups[1].Value.Trim('"').Trim("'")
            if ($value -eq '-') { continue }
            $path = ConvertTo-GuardPath $value $Cwd
            if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
                Stop-Refuse ("${ContentTag}: ODMOWA 'git commit -F' -- nie znalazlem pliku opisu commita '$value', wiec nie umiem go sprawdzic." + "`n" +
                    'Uzyj -m albo -F - z heredoc w tej samej komendzie (tekst komendy jest sprawdzany).')
            }
            $where = 'plik opisu commita ' + (Get-Masked $Matcher $value)
            Add-FileHits $Matcher $where $path
        }
    }
}

function Get-ContentRefusal {
    $more = $script:HitCount - $script:HitLines.Count
    $lines = @("${ContentTag}: ODMOWA 'git add/commit' -- tresc pasuje do listy rdzeni autora ($StemsFileName w family_data_dir):") + $script:HitLines
    if ($more -gt 0) { $lines += "  ... i jeszcze $more" }
    $lines += @(
        'Straznik nie pokazuje slowa ani linii (ISSUE-020, D5): lista nie trafia do rozmowy.',
        "Popraw te miejsca -- dane testowe i przyklady tylko z wymyslonymi osobami i miejscami ($RuleRef).",
        'Plik, ktorego nie zapisala ta pozycja, albo podejrzenie falszywego trafienia: zglos autorowi "plik:linia, linia N listy" -- autor sprawdzi i moze zawezic rdzen (D6). Nie obchodz straznika.'
    )
    return ($lines -join "`n")
}

try {
    if ($ScanTracked) {
        $repos = Get-Repos
        $matcher = Get-Stems
        $files = 0
        foreach ($r in $repos) {
            foreach ($rel in (Invoke-Git $r.Root 'ls-files -z').Split([char]0)) {
                if (-not $rel) { continue }
                $files++
                Add-PathHit $matcher $r $rel
                Add-FileHits $matcher ("$($r.Name)/" + (Get-Masked $matcher $rel)) (Join-Path $r.Root $rel)
            }
        }
        $out = @("${ContentTag} -ScanTracked: $files sledzonych plikow w $($repos.Count) repo, rdzeni na liscie: $($matcher.Stems.Count), trafien: $($script:HitCount)") + $script:HitLines
        if ($script:HitCount -gt $script:HitLines.Count) { $out += "  ... i jeszcze $($script:HitCount - $script:HitLines.Count)" }
        Write-Utf8 ([Console]::OpenStandardOutput()) ($out -join "`n")
        if ($script:HitCount -gt 0) { exit 1 }
        exit 0
    }

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

        # FILES (ISSUE-006) first: a quicker and more exact refusal than the content check.
        $found = @()
        $states = @()
        foreach ($r in Get-Repos) {
            $state = Get-CommitCandidates $r.Root
            $states += [pscustomobject]@{ Repo = $r; State = $state }
            foreach ($p in $state.Paths) {
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

        # CONTENT (ISSUE-020)
        $matcher = Get-Stems
        Add-CommandHits $matcher $command $gitCalls ([string]$hook.cwd)
        foreach ($s in $states) { Add-RepoContentHits $matcher $s.Repo $s.State }
        if ($script:HitCount -gt 0) { Stop-Refuse (Get-ContentRefusal) }
        exit 0
    }

    exit 0
}
catch {
    Write-Refusal ("${Tag}: blad straznika -- $($_.Exception.Message)" + "`n" +
        'Straznik blokuje, gdy nie umie sprawdzic (fail-closed). Napraw .claude/hooks/family-data-guard.ps1 albo jego wejscie.')
    exit 2
}
