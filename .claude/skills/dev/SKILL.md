---
name: dev
description: 'Implementuje zaplanowaną pozycję Grobing w repo grobing-code (Flutter, Android, local-first) według sekcji Implementation plan. Bez testów — to qa. Używaj po planning, gdy autor mówi „/dev", „implementuj", „buduj".'
updated: 2026-10-16
---

# Dev — implementacja

Pisze kod aplikacji Flutter w `{code}` według planu z pozycji. Lokalna baza jest źródłem prawdy,
sieć jest opcjonalna (ADR-001 local-first, kanon z kick-offu).

## Scope

- Kod aplikacji w `{code}`; zgodnie z konwencjami repo (`analysis_options.yaml`, lints).
- Model danych zgodny z briefem: Person · Family (1-2 partnerów + dzieci) · Event (data + dopisek) ·
  Cemetery · Grave (kwatera/rząd/miejsce, pinezka ze źródłem) · Burial (wiele na grób) · Assertion
  (źródło + status) · Media · „ja".
- **Does NOT:** pisze testów (to `qa`), nie aktualizuje vaulta (to `docs`), nie commituje, nie zmienia
  zakresu.

## On invocation

1. Przeczytaj pozycję z planem, `project-config.example.md` (niezmienniki: przypięta wersja Fluttera,
   pakiet, brak backendu). Pozycja z ekranem → także jego specyfikację w `{vault}/05_DESIGN/` i
   wytyczne `05_DESIGN/brand/style-b.md` (`ui`).
2. Sprawdź wersję Fluttera: **musi zgadzać się z przypiętą.** Inna → STOP; **nie aktualizuj globalnego
   SDK** — jest współdzielone z inną, wydaną aplikacją autora.
3. Implementuj; uruchom `flutter analyze`, napraw błędy mechaniczne (to nie jest punkt stopu).
3a. **Pozycja z ekranem → przejście AC na emulatorze, zanim oddasz `qa`** (retro 2, R5): zainstaluj build,
   przejdź każde AC (`uiautomator dump`, `input tap`, `screencap` do katalogu tymczasowego sesji, nigdy do repo).
   W ISSUE-019 to przejście znalazło dwa błędy przy zielonych testach. Znalezione błędy poprawiasz i wpisujesz w
   *Dev report*. **Stała lista przejścia** (retro 3, R3 — przegląd `ui` znalazł MAJOR po zielonych testach w 7 z 7
   pozycji z ekranem, bo przejście szło główną drogą):
   - **każdy stan z *States*** specyfikacji, nie tylko główna droga — każdy ze zrzutem (ISSUE-029: 3 MAJOR w stanach
     bez kropki, bez mapy, bez sieci);
   - **przy zdjęciach — zdjęcie w sepii** (ISSUE-024: 4 MAJOR). **Tekstu 200% nie sprawdzasz** (decyzja autora 2026-10-23:
     *„tak na prawdę możemy ignorować te teksty 200%”*; do tego dnia `font_scale 2.0` na 360 dp — retro 3, R3);
   - **semantyka i cel dotyku** w `uiautomator dump`: przycisk jest `clickable`, a granice węzła to granice
     elementu, nie całego arkusza (ISSUE-023, ISSUE-027, ISSUE-028);
   - **nowa warstwa mapy albo duże dane → pomiar czasu klatki w buildzie profile**, zanim padnie słowo „emulator”
     (ISSUE-023: wolne klatki uznane za winę emulatora, a był to błąd ok. 600× i ANR przy starcie). **Zawsze naprzemiennie z
     buildem odniesienia** (APK sprzed zmiany, `adb shell pm path` + `adb pull` przed instalacją nowego) — retro 4, R3: w ISSUE-037
     szum hosta wyglądał na regres, dopiero build odniesienia go nazwał;
   - **„mieści się / kadr / nie mieści się” = liczba i najgorszy przypadek** (retro 4, R3): skala, szerokość, położenie z pomiaru —
     nie opis; na **najgorszym** przypadku z pomiaru, nie na przykładzie (tekst 100%; 200% — nie od 2026-10-23). W ISSUE-038
     „drzewo szersze niż ekran” było błędem zaokrąglenia, a w ISSUE-039 przejście szło krótką ścieżką i MAJOR był na najszerszej.
3b. **Przenikanie grupy = jedna warstwa** (retro 4, R3): wiele elementów, które pojawiają się albo znikają razem, dostaje jedną
   wspólną warstwę przezroczystości, nie `Opacity`/`AnimatedOpacity` na każdym. Lekcja z ISSUE-033 wróciła w ISSUE-037 (14,6% wolnych
   klatek przy ▶), choć cytował ją komentarz w kodzie.
4. Wypisz kroki ręcznej weryfikacji (po polsku) do sekcji pozycji dla `qa`.

## Output

- Kod w `{code}` (poza `test/` i `integration_test/`, które należą do `qa`).

## Constraints

- **Żadnych danych rodziny** w kodzie, assetach, fixture'ach (`family-data.md`).
- Żadnych SDK wysyłających dane z telefonu (crash reporting, analityka) — §Security.
- Żadnych sekretów w repo: klucz map i keystore poza repo (`project-config.md`). Plików z sekretami
  (`key.properties`) **nie tworzy agent**: harness pokazałby mu hasła wpisane potem przez autora.
- Zmiana schematu bazy → **migracja**, nigdy „wyczyść i stwórz od nowa".
- Usuwanie danych rodziny → zawsze z potwierdzeniem.
- **Ekrany według specyfikacji `ui`.** Kolory wyłącznie przez tokeny z `lib/app/theme.dart` (bez literałów
  `Color(0x…)` w ekranach); nowy token ze specyfikacji wpisujesz do `theme.dart`. Odstępstwo od
  specyfikacji albo decyzja projektowa, której specyfikacja nie rozstrzyga → w raporcie *Dev report* →
  *Deviations*, nigdy po cichu (to falsyfikator agenta `ui`, ISSUE-013).
- **Hand-off:** auto-flow → wywołaj `qa`; ręcznie: „Następny: uruchom /qa".

## Conflict Check

1. **Sprzeczności** — plan vs FR/model danych z briefu; plan vs istniejący kod.
2. **Reality check** — wersja Fluttera, ścieżki, pakiety zgadzają się z tym środowiskiem.
3. **Blokujące luki** — `⚠️ OPEN` w planie albo niezamknięty spike, od którego zależy implementacja.

Trafienie → **STOP**, opcje, czekaj.

## Self-check

1. **Kompletność** — każdy punkt planu zrobiony albo jawnie nie; `flutter analyze` czyste.
2. **Spójność** — kod robi to, co plan, i nic poza nim.
3. **Własność** — nie dotknąłeś testów, vaulta ani `kickoff/`.
4. **Dane rodziny i warstwa danych** — zero prawdziwych danych w zmianach; zmiana schematu ma
   migrację. ~~Fakt o rodzinie zapisuje źródło i status~~ — wycofane po SPIKE-004 D28 (retro 3, R6): formularz
   wpisuje domyślne źródło, schemat zostaje.
5. **Pass** → kroki ręczne wypisane, hand-off do `qa`. **Fail** → wypisz, czego brakuje.
