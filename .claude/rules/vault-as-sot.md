# Vault as Source of Truth

> **Dokumentacja w `grobing-vault` jest jedynym źródłem prawdy o tym, co budujemy i dlaczego.** Chat,
> pamięć sesji i notatki w głowie są pochodne — po kompresji kontekstu albo przerwie prawdą jest to,
> co zapisane. (Prawdą o **danych rodziny** jest baza w telefonie — to inna rzecz i nigdy nie trafia do
> vaulta, patrz `family-data.md`.)

## Hard requirements

1. **Read-first:** przed pracą agent czyta `{vault}/00_START_HERE/CURRENT_STATE.md` i pozycję, której
   dotyczy praca; przy decyzjach — `kickoff/PROJECT_BRIEF.md`.
2. **Write-as-you-go:** decyzja podjęta w sesji trafia do pliku w tej samej sesji (pozycja backlogu,
   ADR, wiersz w macierzy). Decyzja tylko w chacie nie istnieje.
3. **Vault-Doc-Sync:** zmiana dowieziona w kodzie, której nie odzwierciedla vault, **nie jest
   skończona** (DoD; powód BLOCK krytyka).
4. **Jedna liczba, jeden dom:** stan produktu wyłącznie w `CURRENT_STATE.md`; reszta linkuje.
5. **Status jako mikro-stan:** pozycje backlogu niosą `status:` we frontmatterze; edycja pozycji
   `done` wymaga najpierw cofnięcia statusu na `in-progress`.

## Ownership — one writer per file/section

| Co | Pisarz |
|---|---|
| `CURRENT_STATE.md` · `DOC_MAP.md` · foldery vaulta · kolumny EPIC/US/Story Status w `TRACEABILITY.md` · zamknięcie pozycji (`status: done`) | `docs` |
| sekcja *Implementation plan* w pozycji · `status: in-progress` · kolumny Issue(s)/Issue Status | `planning` |
| sekcja *Verification* w pozycji · `quality-verdict` (do czasu krytyka: `verdict-reviewer: self-check`) · kolumna Quality Verdict w `TRACEABILITY.md` (do czasu krytyka) | `qa` |
| `kickoff/` (brief, profil, manifest) | nikt z agentów — zapis sesji kick-off; zmiana = decyzja autora |
| kod aplikacji | `dev` (bez testów) · testy: `qa` |
| — (nic) | `pm` — router tylko czyta; jego wynik żyje w odpowiedzi, nie na dysku |

> **Jedno pole, dwóch pisarzy rozdzielonych przejściem:** `status:` w pozycji backlogu zmienia
> `planning` (`ready` → `in-progress`) i `docs` (`in-progress` → `done`). Nikt inny; `qa` nie zmienia
> statusu. Przejścia są sekwencyjne w łańcuchu, więc nie konkurują — ale to jest jawny wyjątek od
> „jeden plik = jeden pisarz", nie przeoczenie.
