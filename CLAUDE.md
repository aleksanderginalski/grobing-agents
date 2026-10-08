# Grobing — Agents

> Repo agentów **Grobing**: prywatnej aplikacji na Androida, w której każdy grób rodziny prowadzi do
> pochowanych w nim osób i do tego, jak łączą się z autorem — zamiast papierowych notatek w jednym
> egzemplarzu, uzupełnianej, póki babcia może opowiedzieć, i trwalszej niż autor i sama aplikacja.
> Pełna wartość: `{vault}/00_START_HERE/kickoff/PROJECT_BRIEF.md` §2.

**Otwieraj `../Grobing.code-workspace`, nie sam folder** — i zaczynaj od **`/pm`**. Workspace stawia
`grobing-agents` jako pierwszy folder (tu startuje Claude Code i ładuje ten plik), a `grobing-vault` i
`grobing-code` dokłada jako katalogi dodatkowe — agenci czytają vault i kod bez `/add-dir` i bez
ścieżek absolutnych. Ścieżki tej maszyny dla skryptów są w `.claude/rules/project-config.md` (lokalny,
gitignorowany) — na nowej maszynie skopiuj go z `project-config.example.md`.

## Active Rules

@.claude/rules/git-autonomy-boundary.md
@.claude/rules/family-data.md
@.claude/rules/vault-as-sot.md
@.claude/rules/autonomous-flow.md
@.claude/rules/doc-growth.md
@.claude/rules/project-config.md
@.claude/rules/project-config.example.md

## Agents

| Skill | Rola |
|---|---|
| `/pm` | Router sesji — stan, sprawy zaparkowane, licznik retro, propozycja następnej pozycji; startuje łańcuch |
| `/ui` | Projektant ekranów — przed `planning`, gdy pozycja dodaje albo zmienia ekran: specyfikacja w `05_DESIGN/` (+ makieta przy nowym ekranie); właściciel wytycznych stylu B; przegląd zbudowanego ekranu dla `qa`. Bez kodu |
| `/planning` | Pozycja → plan w samej pozycji; punkt stopu #1 (intencja) |
| `/dev` | Implementacja we Flutterze (`grobing-code`), bez testów |
| `/qa` | Testy wg DoD (MVP), ręczna weryfikacja — do MVP na emulatorze (stop #2, dla autora tylko UI/UX) |
| `/docs` | Strażnik vaulta — zamyka pozycje, DOC_MAP, macierz powiązań, licznik retro; **commituje i wypycha paczkę pozycji po checkliście** (bez pytania; „go” tylko poza zwykłym pushem); wykonuje ISSUE-001 |

**Na sygnał, nie teraz:** `debug` (pierwszy błąd) · `discover`/`decompose`
(pomysł spoza bieżącej pracy) · `ci` (pierwszy pipeline) · `architect` (**pierwszy ADR zastąpiony po
akceptacji**; ADR-y do tego czasu pisze łańcuch `planning` → `docs` — retro 2, R7, zamiast sygnału z kick-offu MD3c,
który już był).
Krytyk `quality` — do zbudowania w ISSUE-003.

## Where things are

- **Stan produktu (jedyny licznik):** `{vault}/00_START_HERE/CURRENT_STATE.md` — tu nie ma żadnych liczb.
- **Decyzje kick-offu:** `{vault}/00_START_HERE/kickoff/` (brief, profil, stan sesji, manifest).
- **Kontrakty:** `glossary.md` · `DEFINITION_OF_DONE.md` · `TRACEABILITY.md` w `{vault}/00_START_HERE/`.
- **Backlog:** `{vault}/backlog/` (issues · spikes · non-tech · deferred).

## Three things that are never negotiable here

1. **Dane rodziny nigdy w żadnym repo** (`family-data.md`).
2. **Commit tylko jawnej listy plików pozycji, po checkliście; push tylko commitów łańcucha, nigdy force;
   wszystko inne na zdalnym repo po „go"** (`git-autonomy-boundary.md`, decyzje autora 2026-10-06 i
   2026-10-07).
3. **Globalny Flutter się nie aktualizuje** bez decyzji — SDK jest współdzielone z inną, wydaną
   aplikacją autora (`project-config.example.md`).
