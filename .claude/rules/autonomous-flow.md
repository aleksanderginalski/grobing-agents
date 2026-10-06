# Autonomous Flow — auto-flow with a closed list of stop-points

> Decyzja z kick-offu (Meta-decyzja 3f): **auto-flow domyślnie**. Autor wybiera zadanie raz; agenci
> przekazują sobie pracę sami i zatrzymują się **wyłącznie** w miejscach z tej listy. Przełącznik
> zdaniem naturalnym, per sesja: **„krok po kroku"** (manual) / **„auto-flow"**.

## The chain

`pm` → (`ui`, gdy pozycja dodaje albo zmienia ekran) → `planning` → `dev` → `qa` → (stop #2, stop #3) →
`docs` → `pm` proponuje następne zadanie.

- **`ui` przed `planning`** (decyzja autora 2026-10-06, [[ISSUE-013-setup-ui-agent]]): plan wynika z projektu
  ekranu. Specyfikacja ekranu (`{vault}/05_DESIGN/`) idzie na stop #1 razem z planem — **bez nowego
  punktu stopu**. Pozycja z ekranem bez specyfikacji → `planning` zatrzymuje się i odsyła do `ui`.
- **Przegląd ekranu:** przy pozycji z ekranem `qa` przed stopem #2 woła `ui` w trybie przeglądu jako
  **subagenta** (bramka wewnętrzna, nie stop). Usterki wracają do `dev`, zanim autor dostanie kroki.

## Stop-points — the closed list (only these)

1. **Intencja przed budową — lekko** (`planning`, przed `dev`): zwięzły diff zakresu + scenariusz
   akceptacji; przy pozycji z ekranem także link do specyfikacji i — przy nowym ekranie — do makiety od
   `ui`. Czekaj na „tak" albo poprawki.
2. **Ręczna weryfikacja — dokładnie** (`qa`, po testach): kroki **po polsku**, które może sprawdzić
   tylko człowiek — dla autora to **UI/UX, przepływ, który czuje użytkownik**; pozycję bez nowego ekranu
   agent sprawdza na emulatorze sam i zapisuje „kroki oddane agentowi” (decyzja autora 2026-10-06,
   `DEFINITION_OF_DONE.md`). **Do MVP na emulatorze**; na telefonie tylko wyjątki z `DEFINITION_OF_DONE.md` (GPS
   na miejscu, słońce, offline na cmentarzu), wyłącznie w buildzie release (decyzja autora
   2026-10-05). Kroki pogrupowane **według miejsca**: terminal VS Code · plik w edytorze · emulator albo
   telefon · „napisz tutaj". Trzy odpowiedzi: **„ok"** · **„pomiń"** (zapisane, nie blokuje) ·
   **opis błędu**. **Cisza ≠ pomiń.** (Rytuał WZ-024: format → analiza → testy → kroki ręczne →
   czekaj.)
3. **„go" przed commitem/pushem** (`qa` → commit): paczka zmian (kod + vault), nigdy częściowa.
   Podłoga z `git-autonomy-boundary.md` — **tryb auto nigdy jej nie znosi.**

## Hard stops — independent of mode, cannot be removed

- powód BLOCK z listy krytyka (gdy powstanie — ISSUE-003); do tego czasu: ryzyko utraty danych
  rodziny, dane rodziny w repo, fakt o rodzinie bez źródła, niespełnione AC, zmiana bez odbicia w vaulcie;
- każda operacja git zmieniająca stan;
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
