# Git Autonomy Boundary — ABSOLUTE RULE

**Naruszenie = krytyczny błąd. STOP i zapytaj najpierw.** Obowiązuje każdego agenta w tym repo i
wszystkie trzy repozytoria Grobing (`grobing-agents`, `grobing-vault`, `grobing-code`).

## Forbidden autonomously

`git commit`, `git push`, `git pull`, `git rebase`, `git reset`, `git checkout`, `git merge`,
`git branch -D`, `git init`, `gh`, i każda inna operacja zmieniająca stan VCS.

## Forbidden to propose

W planach i „następnych krokach": otwieranie PR, issues, komentarzy, release'ów, uruchamianie CI —
jakakolwiek akcja zmieniająca stan na GitHubie. Drafty są OK, jako „autor kopiuje/commituje ręcznie".

## Always allowed (read-only)

`git status`, `git diff`, `git log`, `git branch -l`, `git branch --show-current`,
`git remote get-url <name>` — i każda komenda, która wyłącznie **czyta** stan repo.

## Allowed after explicit approval — the "go" stop-point

Punkt stopu #3 z `autonomous-flow.md`: po checkliście zamknięcia agent pokazuje paczkę (commit
kodu + commit vaulta + ewentualny push) i czeka na wyraźne **„go"**. „Zacommituj" bez treści nie
jest jeszcze zgodą — potwierdź: *„Commit teraz z messagem X?"*. Procedura: `git add` konkretnych
plików → `git diff --cached` → czekaj → wykonaj. **Nigdy commit częściowy** — wszystkie wygenerowane
i sformatowane pliki razem (rytuał WZ-024).

## Family data — part of this boundary

Przed każdym `git add` sprawdź, że w zmianach **nie ma danych rodziny** (`family-data.md`). To jedyna
nieodwracalna rzecz w tym projekcie: repo może dostać remote, a dane wypchnięte raz zostają w
historii.

## Pre-commit hook failure

Zbadaj przyczynę, napraw, czekaj na zgodę przed ponowieniem. **Nigdy `--no-verify`.**

## Self-catch

Zaraz naruszysz: STOP, zapytaj, czekaj na „tak". Już naruszyłeś: zgłoś natychmiast, zaproponuj cofnięcie.
