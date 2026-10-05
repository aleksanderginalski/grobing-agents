# Doc Growth — how the vault grows without becoming a dump

> **Dlaczego ta reguła istnieje w tym repo.** NPG uczy zasady *grow-as-you-go*, a jego szablon
> `DOC_MAP.md` każe „patrzeć na reguły tworzenia folderów" — ale sama tabela tych reguł żyła wyłącznie
> w bazie wiedzy NPG i **nigdy nie trafiała do produktu**. Agenci mieliby obowiązek bez reguły, KIEDY
> go stosować. Autor zapytał o to wprost w kick-offie (*„czy będą wiedzieć, jak to rozbudowywać, żeby
> nie zrobił się śmietnik?"*) — stąd ta reguła, ładowana z `CLAUDE.md`. Reguła nieładowana jest notatką.

## Fixed philosophy

Vault **nigdy nie ma pustych folderów**. Folder powstaje dokładnie wtedy, gdy praca go potrzebuje — i
**w tej samej zmianie** dostaje wiersz w `{vault}/00_START_HERE/DOC_MAP.md` z powodem. Folder bez
wiersza i wiersz bez folderu to dwa pierwsze objawy śmietnika.

## Triggers — signal → folder → what goes there

| Sygnał w pracy | Folder (konwencja numerowana) | Co tam trafia |
|---|---|---|
| Pierwsza decyzja architektoniczna | `04_ARCHITECTURE/decisions/` | ADR-NNN (≥3 opcje, append-only po akceptacji) |
| Pierwsza persona zapisana poza briefem | `02_PRODUCT/personas/` | persony |
| Wizja / canvas wychodzi poza brief | `02_PRODUCT/vision/` | wizja, canvas |
| Pierwsze wymaganie do spisania | `03_REQUIREMENTS/` | UJ / EPIC / US / AC / FR / NFR |
| Pierwszy kontrakt danych / model danych | `04_ARCHITECTURE/` | model danych, format kopii i eksportu |
| Pierwszy ekran do zaprojektowania | `05_DESIGN/` | wireframe'y, specyfikacje ekranów |
| Pierwsza warstwa wizualna (styl B) | `05_DESIGN/brand/` | wytyczne, system wizualny |
| Pierwszy temat prawny / kosztowy | `06_NON_TECH/` | weryfikacje prawne, rejestr kosztów `external-costs.md` |
| Pierwsze retro | `07_RETRO/` | retro co 10 zamkniętych pozycji |

> Numery są etykietą, nie obietnicą — **folder z numerem powstaje dopiero na sygnał**. Wstawiając
> nowy, nie przenumerowuj istniejących; dopisz kolejny wolny numer i wiersz w DOC_MAP.

## Rules

1. **Nowy folder = nowy wiersz w DOC_MAP w tej samej zmianie.** Kolumny: Folder · Purpose · Added
   (sygnał, który go wywołał).
2. **Najpierw szukaj, potem twórz.** Zanim powstanie nowy plik, sprawdź, czy ta rzecz już gdzieś nie
   jest (DOC_MAP + grep). Duplikat jest przyszłą sprzecznością.
3. **Jedna liczba, jeden dom.** Stan produktu tylko w `CURRENT_STATE.md`; inne pliki linkują.
4. **Żadnych danych rodziny** w żadnym folderze (`family-data.md`).
5. **Właściciel:** foldery i DOC_MAP aktualizuje `docs`. Inny agent, który potrzebuje folderu,
   **prosi `docs`** albo zostawia to jako punkt checklisty zamknięcia — nie tworzy folderu po cichu.

## What catches a violation

| Mechanizm | Status |
|---|---|
| ta reguła + self-check `docs` | **działa od dnia 1** |
| check DOC_MAP ↔ dysk przy zapisie i na starcie sesji (Meta-dec. 3g) | **plan** — [[ISSUE-004-setup-freshness-gate]] |
| pytanie o nośne fakty co 10 zamkniętych pozycji | **działa od dnia 1** (licznik w `CURRENT_STATE.md`, pilnuje `pm`) |

**Czego nic tu nie złapie:** dokumentu we właściwym folderze z nieaktualną treścią i decyzji, której
nikt nie zapisał. Na to jest pytanie o fakty, nie check.
