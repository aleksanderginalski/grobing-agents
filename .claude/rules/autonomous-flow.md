# Autonomous Flow — auto-flow with a closed list of stop-points

> Decyzja z kick-offu (Meta-decyzja 3f): **auto-flow domyślnie**. Autor wybiera zadanie raz; agenci
> przekazują sobie pracę sami i zatrzymują się **wyłącznie** w miejscach z tej listy. Przełącznik
> zdaniem naturalnym, per sesja: **„krok po kroku"** (manual) / **„auto-flow"**.

## The chain

`pm` → (`ui`, gdy pozycja dodaje albo zmienia ekran) → `planning` → `dev` → `qa` → (stop #2) → `docs`
(zamknięcie, **commit i push paczki** po checkliście z `git-autonomy-boundary.md`) → `pm` proponuje następne
zadanie.

- **Commit i push bez pytania** (decyzje autora: commit 2026-10-06, retro 1 — R1; push 2026-10-07).
Zamknięcie `docs` idzie **przed** commitem, więc jedna pozycja to jeden commit na repo, razem ze stanem w vaulcie, i zaraz potem jest na GitHubie (warunki: `git-autonomy-boundary.md` → *push*).

- **`ui` przed `planning`** (decyzja autora 2026-10-06, [[ISSUE-013-setup-ui-agent]]): plan wynika z projektu
  ekranu. Specyfikacja ekranu (`{vault}/05_DESIGN/`) idzie na stop #1 razem z planem — **bez nowego
  punktu stopu**. Pozycja z ekranem bez specyfikacji → `planning` zatrzymuje się i odsyła do `ui`.
- **Przegląd ekranu:** przy pozycji z ekranem `qa` przed stopem #2 woła `ui` w trybie przeglądu jako
  **subagenta** (bramka wewnętrzna, nie stop). Usterki wracają do `dev`, zanim autor dostanie kroki.

## Stop-points — the closed list (only these)

1. **Intencja przed budową** (`planning`, przed `dev`): **lekko** — zwięzły diff zakresu + scenariusz
   akceptacji. **Przy pozycji z ekranem — dokładnie** (retro 1, R5): także specyfikacja i, przy nowym
   ekranie, makieta od `ui`, bo to na makiecie autor zmienia strukturę ekranów taniej niż w kodzie.
   Czekaj na „tak" albo poprawki.
2. **Ręczna weryfikacja — dokładnie** (`qa`, po testach): kroki **po polsku**, które może sprawdzić
   tylko człowiek — dla autora to **UI/UX, przepływ, który czuje użytkownik**; pozycję bez nowego ekranu
   agent sprawdza na emulatorze sam i zapisuje „kroki oddane agentowi” (decyzja autora 2026-10-06,
   `DEFINITION_OF_DONE.md`). **Do MVP na emulatorze**; na telefonie tylko wyjątki z `DEFINITION_OF_DONE.md` (GPS
   na miejscu, słońce, offline na cmentarzu), wyłącznie w buildzie release (decyzja autora
   2026-10-05). Kroki pogrupowane **według miejsca**: terminal VS Code · plik w edytorze · emulator albo
   telefon · „napisz tutaj". Trzy odpowiedzi: **„ok"** · **„pomiń"** (zapisane, nie blokuje) ·
   **opis błędu**. **Cisza ≠ pomiń.** (Rytuał WZ-024: format → analiza → testy → kroki ręczne →
   czekaj.)
3. **„go” tylko poza zwykłym pushem** (decyzja autora 2026-10-07). Commit i push commitów łańcucha robi
   `docs` sam, po checkliście. „go” jest potrzebne, gdy wychodzi commit spoza łańcucha, push został
   odrzucony albo operacja na zdalnym repo nie jest pushem (nowe repo, remote, ustawienia GitHuba) —
   `git-autonomy-boundary.md`. **Tryb auto nie znosi tego „go”.**

## Hard stops — independent of mode, cannot be removed

- powód BLOCK z listy krytyka (gdy powstanie — ISSUE-003); do tego czasu: ryzyko utraty danych
  rodziny, dane rodziny w repo, fakt o rodzinie bez źródła, niespełnione AC, zmiana bez odbicia w vaulcie;
- każda operacja git zmieniająca stan **poza commitem i pushem po checkliście** (force push, pull, rebase,
  merge — zawsze stop);
- odmowa strażnika danych rodziny przy `git add` albo `git commit`;
- zmiana zakresu odkryta w trakcie — nigdy nie poszerzaj po cichu;
- prawdziwe rozwidlenie decyzji, które należy do autora;
- problem, którego agent nie umie naprawić.

Błędy mechaniczne (lint, analiza, testy) **nie są stopem** — napraw i jedź dalej.

## Third state — parked, not blocked

Sprawy czekające na kogoś spoza sesji: **babcia** („kim był X?" → budzi się przy następnej wizycie u
niej) i **cmentarz** („czy pinezka X jest dobra?" → budzi się przy następnej wizycie na tym
cmentarzu, np. 1 listopada). Parkowanie zatrzymuje **pozycję, nie łańcuch**. Wpis w
`{vault}/00_START_HERE/CURRENT_STATE.md` §Parked: źródło · pytanie **bez danych rodziny** · warunek
obudzenia (zdarzenie) · data. `pm` liczy je na starcie sesji.

## Mechanism — why the chain does not stall

- **Wewnętrzna bramka → wywołaj jako SUBAGENTA** (narzędzie Agent): werdykt wraca jako wynik
  narzędzia i tura trwa dalej.
- **Punkt stopu → skill ŚWIADOMIE kończy turę** i czeka.
- Każdy skill łańcucha kończy się warunkowo: *w auto-flow — wywołaj następny sam; w trybie
  ręcznym — zakończ „Następny: uruchom /X" i czekaj.*

## Running summary (SC-14)

W auto-flow każdy krok dopisuje jedną linię do widocznego **dziennika łańcucha** w odpowiedzi
(co zrobił · co zdecydował · co zostawił) — żeby po powrocie dało się odtworzyć drogę bez
powtarzania jej. **Granica:** dziennik pisany przez agenta o własnej pracy ma tę samą ślepą plamkę co
self-check — zapisuje to, co agent *myślał*, że robi.

## Loop policy

Prawdziwy produkt → po zamknięciu pozycji `pm` **aktywnie proponuje następną**, wyprowadzoną ze stanu
w `CURRENT_STATE.md` i backlogu — nie z grzeczności.

**Koniec sesji** (decyzja autora 2026-10-06, retro 1 — R2): ostatnia odpowiedź sesji zawsze ma dwie
rzeczy:
1. **co dalej** — jedna pozycja i dlaczego ona;
2. **jasne „możesz kończyć sesję”** — wszystko zapisane w vaulcie i zacommitowane. Albo wprost: co jeszcze
   nie jest zapisane i co z tym zrobić.
