---
name: planning
description: 'Zamienia jedną pozycję backlogu Grobing (ISSUE / SPIKE) w konkretny plan dla dev — zakres, pliki, mapowanie AC, kroki ręcznej weryfikacji — i zatrzymuje się na punkcie stopu #1 (intencja przed budową). Używaj, gdy autor mówi „zaplanuj ISSUE-NNN", „/planning", albo gdy pm startuje łańcuch.'
updated: 2026-10-05
---

# Planning — pozycja → plan dla dev

Czyta jedną pozycję i pisze plan wykonania **w samej pozycji** (sekcja *Implementation plan* —
Meta-decyzja 2: plan wewnątrz issue, nie osobny plik).

## Scope

- Zakres jednego komponentu (`delivery-style: task-level`), pliki prawdopodobnie dotknięte, mapowanie
  na AC, kroki ręcznej weryfikacji **po polsku** dla punktu stopu #2.
- Przy pozycji dotykającej warstwy danych dopisuje do planu: **test migracji** (jeśli zmienia się
  schemat), **próbne odtworzenie z kopii**, zapis **źródła i statusu** dla faktów o rodzinie.
- **Does NOT:** pisze kodu ani testów, nie zmienia zakresu po cichu, nie zamyka pozycji.

## On invocation

1. Przeczytaj pozycję, `{vault}/00_START_HERE/DEFINITION_OF_DONE.md`, `glossary.md` i — jeśli pozycja
   wskazuje — powiązany fragment `kickoff/PROJECT_BRIEF.md` (FR, model danych, §Security).
2. Sprawdź DoR. Niespełniony → nie planuj, powiedz, czego brakuje.
3. Napisz *Implementation plan*, ustaw `status: in-progress`, uzupełnij kolumny Issue(s)/Issue Status
   w `TRACEABILITY.md`.
4. **Punkt stopu #1 (lekko):** zwięzły diff zakresu + scenariusz akceptacji → czekaj na „tak".

## Output

- Sekcja *Implementation plan* w pliku pozycji · `status: in-progress` · kolumny Issue(s), Issue
  Status w `{vault}/00_START_HERE/TRACEABILITY.md`.

## Constraints

- Bez kodu. Bez decyzji produktowych spoza briefu — luka → `⚠️ OPEN` i pytanie do autora.
- Dane przykładowe w planie: **wyłącznie wymyślone osoby** (`family-data.md`).
- **Hand-off:** po „tak" → auto-flow: wywołaj `dev`; ręcznie: „Następny: uruchom /dev".

## Conflict Check

1. **Sprzeczności** — pozycja vs brief (np. AC sprzeczne z FR albo z §Security); pozycja vs to, co
   autor mówi teraz.
2. **Reality check** — pliki i moduły, które plan zakłada, istnieją w `{code}`? Przed ISSUE-002 kodu
   nie ma.
3. **Blokujące luki** — `⚠️ OPEN`, niezamknięty spike, od którego pozycja zależy (np. widok mapy przed
   SPIKE-001).

Trafienie → **STOP**, opcje, czekaj.

## Self-check

1. **Kompletność** — zakres, pliki, AC, kroki ręczne, sekcja *Out of Scope* niepusta.
2. **Spójność** — plan wynika z pozycji i briefu; nic nie dopisane, żeby zapchać lukę.
3. **Własność** — pisałeś tylko swoją sekcję, `status: in-progress` i swoje kolumny macierzy.
4. **Warstwa danych** — jeśli pozycja jej dotyka: migracja, odtworzenie i źródło faktu są w planie.
   To jedyne, czego potem nikt nie dopisze.
5. **Wystarczalność** — czego jeszcze ta pozycja potrzebuje, a czego nie ma w planie? Powiedz na głos.
6. **Pass** → punkt stopu #1. **Fail** → zostaw `ready`, wypisz braki.
