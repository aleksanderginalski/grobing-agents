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
| każdy | przed `git add`: w zmianach nie ma baz (`*.db`, `*.sqlite*`), kopii (`*.age`, `*.tar`), eksportów (`*.html`, `*.pdf`) ani zdjęć i filmów spoza zasobów aplikacji (ikony w `android/app/src/main/res/`). Odmowę strażnika traktuj jak stop, nie jak przeszkodę do obejścia |
| każdy | **commit tylko plików, które ta pozycja zapisała** (`git-autonomy-boundary.md` → R1). Plik w repo, którego agent nie stworzył — notatki, zdjęcia, adresy wrzucone przez autora — **nie wchodzi do commita**: przenieś go do `family_data_dir` za zgodą autora albo zgłoś |

## Family data on this PC — `family_data_dir` (retro 1, R3, 2026-10-06)

**Skąd ta sekcja:** 2026-10-06 autor położył w `grobing-vault/01_INBOX/Notatki/` zdjęcia notatek (33) i
plik `.md` z adresami cmentarzy. Zdjęcia `.gitignore` pomijał, ale **plik `.md` git widział**, a strażnik
rozpoznaje typ pliku, nie treść. Commit z VS Code wpuściłby adresy do historii publicznego repo.
`pm` przeniósł folder poza repo, zanim cokolwiek trafiło do historii.

- **Miejsce na dane rodziny na PC:** `family_data_dir` z `project-config.md`. To folder **poza wszystkimi
  trzema repo i poza workspace'em**. To przystanek roboczy (notatki do przepisania, zdjęcia stron), a nie
  trwały dom: trwały dom to aplikacja, zaszyfrowana kopia i eksport u rodziny, a zdjęcia notatek trafiają
  do zaszyfrowanego miejsca ([[NT-001-photograph-the-notes]]).
- **Agenci nie czytają `family_data_dir` bez wyraźnej prośby autora w tej sesji.** Gdy autor o to prosi
  (np. żeby `ui` dopasował formularz do układu notatek), do vaulta trafia **tylko struktura** (jakie pola,
  jak zapisane daty), nigdy dane.
- **Agent, który zobaczy dane rodziny w którymś z trzech repo** (także nieśledzone albo ignorowane),
  zgłasza to na początku odpowiedzi i proponuje przeniesienie do `family_data_dir`.

## Before the first push — the repos are PUBLIC (decision 2026-10-05)

Autor chce publicznych repo na GitHubie jako portfolio. **Żadne repo Grobing nie idzie na zdalne repo,
dopóki nie są zamknięte [[ISSUE-006-setup-family-data-guard]] i [[NT-008-publication-review]].**
Push do publicznego repo jest nieodwracalny. Agent, który zobaczy prośbę o pierwszy push przy
otwartej którejś z tych pozycji, **zatrzymuje się i to mówi** — to twardy stop, nie sugestia.

## Mechanisms — and what each does NOT catch

| Mechanizm | Status | Czego NIE łapie |
|---|---|---|
| `.gitignore` w **trzech** repo — ten sam blok: bazy, kopie `*.age`/`*.tar`, eksporty `*.html`/`*.pdf`, zdjęcia i filmy, katalogi `/exports/` `/backups/` `/family-data/` `/real-data/` w korzeniu; w `grobing-code` wyjątek tylko dla obrazów w `android/app/src/main/res/` | **działa** (od dnia 1; lista z [[ISSUE-006-setup-family-data-guard]], 2026-10-05) | treści: nazwiska wpisanego w kod źródłowy albo w dokumentację · pliku dodanego siłą (`git add -f`) poza Claude'em. **To jedyna ochrona commitów autora z VS Code** |
| hook `PreToolUse` — `.claude/hooks/family-data-guard.ps1` (T-05): odmawia zapisu plików z tej samej listy narzędziami Claude'a w trzech repo; odmawia `git add`/`git commit`, gdy taki plik mógłby wejść do commita; `git add -f` zawsze; **przy własnym błędzie, braku skryptu albo `project-config.md` blokuje** | **działa** — [[ISSUE-006-setup-family-data-guard]] | treści (rozpoznaje plik po typie i miejscu, nie po treści) · zapisu komendą powłoki (`cp`, `>`, `adb pull`) w chwili zapisu — łapie go dopiero przy `git add`/`commit` · commita autora z VS Code (tam działa tylko `.gitignore`) · edycji samego skryptu albo `.gitignore` (widać ją w `git diff --cached --stat` w odpowiedzi przed commitem, R1) |
| commit agenta tylko z jawnej listy plików, które pozycja zapisała (R1) | **działa** od 2026-10-06 (`git-autonomy-boundary.md`) | pliku, który agent sam napisał z danymi w treści · commita autora z VS Code |
| krytyk jakości — powód BLOCK „dane rodziny w repo" | **plan** — [[ISSUE-003-setup-quality-critic]] | tego, czego nie przeczyta |
| ta reguła | **działa od dnia 1** (ładowana z `CLAUDE.md`) | czegokolwiek, czego agent nie zauważy — dlatego istnieją dwa powyższe |
