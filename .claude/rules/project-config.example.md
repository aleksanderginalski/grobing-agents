# Project Configuration — EXAMPLE (committed)

> **Ten plik pełni dwie role:** (1) **commitowana tożsamość systemu** — wartości realne, nie
> placeholdery; (2) **szablon ścieżek lokalnych** — skopiuj do `project-config.md` (gitignorowany) i
> wypełnij ścieżki dla swojej maszyny.
>
> **Dlaczego tożsamość jest oddzielona od ścieżki** (T-14 + T-15, decyzja z kick-offu): *które*
> repozytoria tworzą Grobing jest takie samo na każdej maszynie i musi być commitowane; *gdzie* leżą
> jest per-maszyna. Trzymanie obu w pliku ignorowanym czyni każdy check obejmujący kilka repo
> **niewykonalnym** — nic poza tą maszyną nie umiałoby ich znaleźć.

## Identity — committed

```yaml
project_name: "Grobing"
sot_repos:                       # z czego składa się system — po TOŻSAMOŚCI, nie po ścieżce
  - repo: "grobing-agents"       # agenci, reguły, konfiguracja Claude Code — tu otwierasz sesje
    role: "agents"
  - repo: "grobing-vault"        # dokumentacja = SoT (decyzje, backlog, kontrakty)
    role: "vault"
  - repo: "grobing-code"         # aplikacja Flutter (Android)
    role: "code"
platform: "claude-code"
language: "pl"                   # treść po polsku; nagłówki i nazwy pól po angielsku (Meta-dec. 1)
```

## Product invariants — committed

> Jedno miejsce na fakty, których agenci **nie mogą wymyślać** (wzorzec „Project Identity" z
> wcześniejszej aplikacji autora). Stan produktu (etap, co w toku) **nie** jest tutaj — żyje w
> `grobing-vault/00_START_HERE/CURRENT_STATE.md`.

```yaml
app_type: "A — Android app, Flutter, local-first (no backend, no accounts, no analytics)"
flutter_version_pinned: "3.41.1"     # SDK jest współdzielone z inną, wydaną aplikacją autora —
                                     # NIE aktualizuj globalnego Fluttera bez decyzji (ADR-002).
                                     # Sprawdza ją grobing-code/pubspec.yaml → environment.flutter;
                                     # zmiana = obie linie w jednej paczce
platforms: ["android"]               # iPhone: Won't (now), MoSCoW W5
android_package: "com.grobing.app"   # decyzja autora 2026-10-05 (ISSUE-002). NIGDY nie zmieniaj —
                                     # inna nazwa = inna aplikacja, nie widzi bazy z telefonu
root_widget: "GrobingApp"            # grobing-code/lib/app/grobing_app.dart
security_level: "ASVS-lite (MVP), przełożony na telefon — patrz PROJECT_BRIEF §Security"
family_data_in_repos: "NEVER — patrz .claude/rules/family-data.md"
```

## Local paths — template (fill in `project-config.md`, never here)

```yaml
vault_local_path: ""                 # np. "C:\\Programowanie\\Grobing\\grobing-vault"
code_local_path: ""                  # np. "C:\\Programowanie\\Grobing\\grobing-code"
release_keystore_dir: ""             # POZA każdym drzewem projektu; nigdy w repo (floor: no secrets in repo)
family_data_dir: ""                  # np. "C:\\Programowanie\\Grobing\\_dane-rodziny" — POZA trzema repo i
                                     # workspace'em; przystanek roboczy na notatki rodziny (family-data.md, R3).
                                     # Tu leży też rdzenie-straznika.txt — lista autora dla strażnika treści
                                     # (ISSUE-020); bez niej git add/commit są zablokowane
```

Agenci resolwują `{vault}` i `{code}` z `project-config.md`. **Skille nie zawierają ścieżek
absolutnych.** Z tego samego pliku czyta je strażnik danych rodziny
(`.claude/hooks/family-data-guard.ps1`, ISSUE-006). Bez pliku albo z pustą ścieżką strażnik **blokuje**
zapis plików oraz `git add`/`commit`, więc na nowej maszynie ten plik powstaje pierwszy (ręcznie).
