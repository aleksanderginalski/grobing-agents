---
screen: "<nazwa ekranu>"
items: ["[[ISSUE-NNN-…]]"]
us: "[[US-NNN-…]]"
journey-step: "<UJ-001 · N | n/a — M1 | widok 5>"
mockup: "<ścieżka w katalogu tymczasowym sesji i data | n/a — zmiana istniejącego ekranu>"
updated: YYYY-MM-DD
---

<!--
  Szablon specyfikacji ekranu — wypełnia agent `ui` (`.claude/skills/ui/SKILL.md`), zapis do
  `{vault}/05_DESIGN/<ekran>.md`. Usuń ten komentarz. Sekcja, która nie dotyczy ekranu, zostaje z
  wpisem „n/a — <powód>”, nie znika. Przykłady wyłącznie z wymyślonymi osobami (family-data.md).
-->

# <Ekran> — specyfikacja

> Żywy plik: `ui` aktualizuje go przy każdej pozycji, która ten ekran zmienia. Prawdą o ekranie jest ten
> plik; szkic i makieta to podgląd.

## Purpose
[Co Zbierający tu robi i po co, w jednym-dwóch zdaniach. US, krok ścieżki albo pozycja Must.]

## Navigation
[Skąd się wchodzi · dokąd ekran prowadzi · powrót · co dzieje się z niezapisanym wpisem.]

## Elements in order
| # | Element | Typ | Klawiatura / akcja | Domyślnie | Walidacja | Źródło |
|---|---|---|---|---|---|---|
| 1 | | pole tekstowe · wybór · przycisk · lista | `next` · `done` · … | | | AC-N · FR-NNN · decyzja projektowa |

## States
| Stan | Co widać |
|---|---|
| pusty | |
| błąd | |
| wypełniony | |
| wczytywanie | n/a albo opis |

## Sketch
```
[szkic ASCII, szerokość telefonu]
```

## Tempo
[Tylko ekrany do wpisywania. Akcje na jeden rekord (pola · dotknięcia · zmiany klawiatury) × liczba
rekordów (G6). Co skraca, co wydłuża. Inne ekrany: „n/a — ekran do oglądania”.]

## Style B rules applied
[Które reguły z `brand/style-b.md` dotyczą tego ekranu. Nowe tokeny: rola · proponowana wartość ·
pomiar kontrastu. Do `theme.dart` wpisuje je `dev`.]

## AC → element
| AC | Element(y) | Jak widać spełnienie |
|---|---|---|

## Decisions
[Decyzje projektowe spoza AC i FR, każda z jednym zdaniem „dlaczego” i tym, co ją obali.]

## Open
[`⚠️ OPEN` — pytania do autora. Brak → „brak”.]
