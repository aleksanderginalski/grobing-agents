# Family Data — never in any repo

> Decyzja z kick-offu (Meta-decyzja 1, wzmocniona w §Security do siły twardego minimum). **Nie da się
> jej obniżyć etapem ani wyjątkiem.**

## The rule

**Żadne repozytorium Grobing nie zawiera danych rodziny — nigdy.** Ani `grobing-code`, ani
`grobing-vault`, ani `grobing-agents`.

**Dane rodziny** = cokolwiek o prawdziwych osobach: imiona i nazwiska, daty, relacje, „kim była",
zdjęcia (osób, nagrobków, starych fotografii), pozycje grobów, adresy kwater, pliki bazy danych,
kopie zapasowe, eksporty.

**Gdzie dane żyją:** wyłącznie w aplikacji na telefonie (baza = źródło prawdy) · w **zaszyfrowanej**
kopii w chmurze autora · w **eksporcie** przechowywanym fizycznie u rodziny.

## What this means for each agent

| Agent | Konkretnie |
|---|---|
| `dev` · `qa` | dane testowe i fixture'y wyłącznie z **wymyślonymi** osobami; żadnych prawdziwych zrzutów bazy do testów |
| `docs` | sprawa „zapytać babcię o X" może być w vaulcie jako **pytanie bez danych**; odpowiedź trafia do aplikacji |
| każdy | przed `git add`: w zmianach nie ma plików `*.db`, `*.sqlite*`, eksportów, kopii ani zdjęć spoza zasobów aplikacji (ikony, grafiki UI) |

## Before the first push — the repos are PUBLIC (decision 2026-10-05)

Autor chce publicznych repo na GitHubie jako portfolio. **Żadne repo Grobing nie idzie na zdalne repo,
dopóki nie są zamknięte [[ISSUE-006-setup-family-data-guard]] i [[NT-008-publication-review]].**
Push do publicznego repo jest nieodwracalny. Agent, który zobaczy prośbę o pierwszy push przy
otwartej którejś z tych pozycji, **zatrzymuje się i to mówi** — to twardy stop, nie sugestia.

## Mechanisms — and what each does NOT catch

| Mechanizm | Status | Czego NIE łapie |
|---|---|---|
| `.gitignore` w `grobing-code` (bazy, kopie, eksporty, katalogi zdjęć) | **działa od dnia 1** | nazwiska wpisanego w kod źródłowy albo w dokumentację |
| hook `PreToolUse` odmawiający zapisu/commitu takich plików (T-05) | **plan** — [[ISSUE-006-setup-family-data-guard]] | jak wyżej: rozpoznaje po typie i miejscu pliku, nie po treści |
| krytyk jakości — powód BLOCK „dane rodziny w repo" | **plan** — [[ISSUE-003-setup-quality-critic]] | tego, czego nie przeczyta |
| ta reguła | **działa od dnia 1** (ładowana z `CLAUDE.md`) | czegokolwiek, czego agent nie zauważy — dlatego istnieją dwa powyższe |
