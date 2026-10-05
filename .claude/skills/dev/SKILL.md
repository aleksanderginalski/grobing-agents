---
name: dev
description: 'Implementuje zaplanowaną pozycję Grobing w repo grobing-code (Flutter, Android, local-first) według sekcji Implementation plan. Bez testów — to qa. Używaj po planning, gdy autor mówi „/dev", „implementuj", „buduj".'
updated: 2026-10-05
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
   pakiet, brak backendu).
2. Sprawdź wersję Fluttera: **musi zgadzać się z przypiętą.** Inna → STOP; **nie aktualizuj globalnego
   SDK** — jest współdzielone z inną, wydaną aplikacją autora.
3. Implementuj; uruchom `flutter analyze`, napraw błędy mechaniczne (to nie jest punkt stopu).
4. Wypisz kroki ręcznej weryfikacji (po polsku) do sekcji pozycji dla `qa`.

## Output

- Kod w `{code}` (poza `test/` i `integration_test/`, które należą do `qa`).

## Constraints

- **Żadnych danych rodziny** w kodzie, assetach, fixture'ach (`family-data.md`).
- Żadnych SDK wysyłających dane z telefonu (crash reporting, analityka) — §Security.
- Żadnych sekretów w repo: klucz map i keystore poza repo (`project-config.md`).
- Zmiana schematu bazy → **migracja**, nigdy „wyczyść i stwórz od nowa".
- Usuwanie danych rodziny → zawsze z potwierdzeniem.
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
   migrację; fakt o rodzinie zapisuje źródło i status.
5. **Pass** → kroki ręczne wypisane, hand-off do `qa`. **Fail** → wypisz, czego brakuje.
