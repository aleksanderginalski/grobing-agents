# Git Autonomy Boundary — ABSOLUTE RULE

**Naruszenie = krytyczny błąd. STOP i zapytaj najpierw.** Obowiązuje każdego agenta w tym repo i
wszystkie trzy repozytoria Grobing (`grobing-agents`, `grobing-vault`, `grobing-code`).

> **Zmiana 2026-10-06 (decyzja autora, retro 1 — R1):** commit lokalny agent robi **sam**, po checkliście
> niżej. Powód autora: przy commitach zawsze akceptował, więc stop nic nie wnosił.
>
> **Zmiana 2026-10-07 (decyzja autora, po pierwszym pushu):** **push też idzie sam**, zaraz po commicie
> paczki, na warunkach niżej. Powód autora: na „go” zawsze odpowie „tak”, a w retro 1 chciał automatu dla
> obu kroków. Zapis R1 („push tylko po „go””) tego nie oddał. Push do publicznego repo jest nieodwracalny,
> dlatego jego warunki są ostrzejsze niż przy commicie, a kontrola treści musi się odbyć **przed `git add`**.

## Forbidden autonomously

`git push` poza sekcją *push* niżej · `git push --force` / `-f` / `--force-with-lease`, push gałęzi innej niż
`main` i tagów — zawsze · `git pull`, `git fetch` z zapisem, `git rebase`, `git reset`, `git checkout`,
`git merge`, `git commit --amend`, `git branch -D`, `git init`, `git remote add/set-url/remove`, `git rm` (także
`--cached`), `git restore` (także `--staged`), `git stash`, `gh` i każda inna operacja zmieniająca stan VCS albo
indeks, **poza commitem i pushem z sekcji niżej** (`git rm`/`restore`/`stash` wprost: retro 2, R2 — `dev` zmienił
indeks `git rm --cached` w ISSUE-014).

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

## Allowed autonomously — push right after the package commit (2026-10-07)

Push robi `docs` w tym samym kroku, zaraz po commicie paczki, w każdym repo, które dostało commit. Wolno
tylko wtedy, gdy **wszystkie** warunki są spełnione:

1. **Commit paczki przeszedł checklistę wyżej** — w tym strażnik i kontrola danych rodziny przed `git add`.
2. **Wychodzą tylko commity łańcucha:** `git log --oneline origin/main..main` jest w odpowiedzi i każdy hash
   jest w dzienniku łańcucha tej sesji. **Commit spoza łańcucha** (np. autora z VS Code, który chroni tylko
   `.gitignore`) → STOP: pokaż go i czekaj na „go”.
3. **Wyłącznie `git push origin main`** na istniejący `origin`, jako fast-forward. Push odrzucony (na
   GitHubie jest coś, czego nie ma lokalnie) → STOP. Nigdy `pull`, `rebase`, `merge` ani `--force`, żeby
   push przeszedł.
4. **Po pushu** w dzienniku łańcucha: hash i „wypchnięte”. `git revert <hash>` z kolejnym pushem cofa
   zmianę w kodzie, ale **treść zostaje w publicznej historii**. Dane rodziny w wypchniętym commicie to
   incydent: STOP i natychmiast zgłoś autorowi.

Którykolwiek warunek niespełniony → **nie pushuj**. Commit zostaje lokalnie, wypisz, czego brakuje.

## Allowed after explicit approval — the "go" stop-point

Punkt stopu #3 z `autonomous-flow.md` obejmuje wszystko na zdalnym repo, co **nie jest** pushem z sekcji
wyżej: commit spoza łańcucha w `origin/main..main`, odrzucony push, nowe repo, zmiana remote'a, ustawienia
repo na GitHubie. Agent pokazuje, co i dlaczego, i czeka na wyraźne **„go”**.

## Family data — part of this boundary

Przed każdym `git add` sprawdź, że w zmianach **nie ma danych rodziny** (`family-data.md`). To jedyna
nieodwracalna rzecz w tym projekcie: repo są publiczne, push idzie sam zaraz po commicie, a dane wypchnięte
raz zostają w historii. **Ostatnia kontrola treści jest przed `git add`, nie przed pushem.**

## Pre-commit hook failure

- **Odmowa strażnika danych rodziny** → STOP i zgłoś. Nie poprawiaj „żeby przeszło”.
- **Inny błąd hooka** (format, analiza) → napraw mechanicznie i ponów **raz**; drugi błąd → STOP.
- **Nigdy `--no-verify`.**

## Self-catch

Zaraz naruszysz: STOP, zapytaj, czekaj na „tak”. Już naruszyłeś: zgłoś natychmiast, zaproponuj cofnięcie.
