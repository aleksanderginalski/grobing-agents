# Git Autonomy Boundary — ABSOLUTE RULE

**Naruszenie = krytyczny błąd. STOP i zapytaj najpierw.** Obowiązuje każdego agenta w tym repo i
wszystkie trzy repozytoria Grobing (`grobing-agents`, `grobing-vault`, `grobing-code`).

> **Zmiana 2026-10-06 (decyzja autora, retro 1 — R1):** commit lokalny agent robi **sam**, po checkliście
> niżej. **Push i każda operacja na zdalnym repo nadal wymagają „go”.** Powód autora: przy commitach
> zawsze akceptował, więc stop nic nie wnosił; commit lokalny cofa się jednym poleceniem, push do
> publicznego repo nie.

## Forbidden autonomously

`git push`, `git pull`, `git fetch` z zapisem, `git rebase`, `git reset`, `git checkout`, `git merge`,
`git commit --amend`, `git branch -D`, `git init`, `gh` i każda inna operacja zmieniająca stan VCS,
**poza commitem z sekcji niżej**.

## Forbidden to propose

W planach i „następnych krokach”: otwieranie PR, issues, komentarzy, release'ów, uruchamianie CI —
jakakolwiek akcja zmieniająca stan na GitHubie. Drafty są OK, jako „autor kopiuje/commituje ręcznie”.

## Always allowed (read-only)

`git status`, `git diff`, `git log`, `git branch -l`, `git branch --show-current`,
`git remote get-url <name>`, `git check-ignore` — i każda komenda, która wyłącznie **czyta** stan repo.

## Allowed autonomously — commit after the closing checklist (R1)

Commit paczki pozycji robi `docs` po zamknięciu (`autonomous-flow.md` → *The chain*). Commit wolno
zrobić tylko wtedy, gdy **wszystkie** warunki są spełnione:

1. **`git add` jawnej listy plików, które ta pozycja zapisała** (kod, testy, vault, reguły). Nigdy
   `git add -A`, `.`, `-u`, `-f` ani wzorca obejmującego katalog. **Plik, którego żaden agent tej
   pozycji nie stworzył** (np. wrzucony przez autora do vaulta), **nie wchodzi** — zgłoś go autorowi.
2. **Strażnik danych rodziny przechodzi** (hook przy `git add` i `git commit`). Odmowa = STOP, nie
   przeszkoda do obejścia.
3. **Testy i analiza zielone** dla pozycji z kodem (`flutter test`, `flutter analyze`, `dart format`).
4. **Paczka całości:** jedna pozycja = jeden commit na repo, razem z zamknięciem `docs` i wszystkimi
   wygenerowanymi i sformatowanymi plikami (rytuał WZ-024; **nigdy commit częściowy**).
5. **Przed commitem** `git diff --cached --stat` jest w odpowiedzi; **po commicie** w dzienniku łańcucha
   jest hash każdego commita i sposób cofnięcia (`git revert <hash>` — nowym commitem, bez przepisywania
   historii).

Którykolwiek warunek niespełniony → **nie commituj**, wypisz, czego brakuje, i czekaj.

## Allowed after explicit approval — the "go" stop-point

Punkt stopu #3 z `autonomous-flow.md` dotyczy teraz **wyłącznie pushu** (i każdej operacji na zdalnym
repo): agent pokazuje, co pójdzie (`git log origin/main..main`), i czeka na wyraźne **„go”**. Pierwszy
push wymaga dodatkowo zamkniętego [[NT-008-publication-review]] (`family-data.md`).

## Family data — part of this boundary

Przed każdym `git add` sprawdź, że w zmianach **nie ma danych rodziny** (`family-data.md`). To jedyna
nieodwracalna rzecz w tym projekcie: repo może dostać remote, a dane wypchnięte raz zostają w
historii.

## Pre-commit hook failure

- **Odmowa strażnika danych rodziny** → STOP i zgłoś. Nie poprawiaj „żeby przeszło”.
- **Inny błąd hooka** (format, analiza) → napraw mechanicznie i ponów **raz**; drugi błąd → STOP.
- **Nigdy `--no-verify`.**

## Self-catch

Zaraz naruszysz: STOP, zapytaj, czekaj na „tak”. Już naruszyłeś: zgłoś natychmiast, zaproponuj cofnięcie.
