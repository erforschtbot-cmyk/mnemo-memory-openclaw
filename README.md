# Mnemo-Memory für OpenClaw

Ein komplettes, selbst installierendes Gedächtnisverfahren für OpenClaw-Agenten:
**Mnemo Cortex** als lokales Langzeitgedächtnis, angebunden per **MCP**, plus die
Arbeitsregeln, die daraus brauchbares Erinnern machen.

> **Du bist eine KI und sollst das hier einbauen?**
> Lies nicht dieses README, sondern **[START-HERE.md](START-HERE.md)**. Das ist
> die Schritt-für-Schritt-Anleitung mit Prüfpunkten. Dieses README erklärt nur,
> *was* du da installierst.

---

## Was am Ende läuft

```
OpenClaw-Agent ──MCP──> mcp-bridge (Node) ──HTTP──> Mnemo Cortex (127.0.0.1:50001)
      │                                                    │
      └── native Memory (MEMORY.md, memory/*.md)           └── ~/.mnemo-cortex (Daten)
```

Drei Schichten:

| Schicht | Aufgabe | Standard-OpenClaw? |
|---|---|---|
| **Mnemo Cortex** | semantisches Langzeitgedächtnis, Kategorien, Verfall, strukturierte Fakten, Task-Rezepte | nein |
| **MCP-Bridge** | stellt Mnemo als Agent-Tools bereit (`mnemo_recall`, `mnemo_save`, …) | nein |
| **OpenClaw Memory** | `memory_search`, Tagesnotizen, `MEMORY.md`, nächtliches Dreaming | ja |

Die native Schicht bleibt unangetastet. Mnemo ergänzt sie um das, was OpenClaw
von sich aus nicht kann: **sofort abfragbares, agentenübergreifendes,
semantisches Gedächtnis mit Verfallslogik.**

## Was du bekommst

- **`mnemo_recall`** – semantisch erinnern (mit Alter, Quelle, Kategorie und
  `stale_warning`, wenn ein Fakt veraltet sein könnte)
- **`mnemo_save`** – Entscheidungen und Fakten speichern, Kategorie steuert den
  Verfall
- **`mnemo_search`** – agentenübergreifend suchen
- **`mnemo_fact_save` / `mnemo_fact_demote`** – exakte `(entity, attribute)`-Fakten
  mit Confidence statt Fuzzy-Text
- **`mnemo_save_trajectory` / `mnemo_recall_trajectory`** – funktionierende
  Arbeitsabläufe als Rezept speichern und vor ähnlichen Aufgaben wiederfinden
- **automatische Erfassung** – Tool-Aktivität wird als `session_log` mitgeschrieben
  und per Default aus normalen Recalls herausgefiltert

## Installation in einem Befehl

Voraussetzungen: Linux mit systemd-User-Instanz, Python ≥ 3.10, Node ≥ 18,
Git, curl, **Ollama** mit `nomic-embed-text` und einem Reasoner-Modell.

```bash
git clone https://github.com/erforschtbot-cmyk/mnemo-memory-openclaw.git ~/.openclaw/mnemo-handover
cd ~/.openclaw/mnemo-handover
./install.sh --explain     # zeigt jeden Schritt, aendert nichts
./install.sh               # erst nachdem du den Plan gelesen hast
```

Das Skript prüft die Voraussetzungen, installiert Mnemo Cortex (gepinnt auf den
verifizierten Stand), richtet den systemd-Dienst ein, trägt den MCP-Block in
`~/.openclaw/openclaw.json` ein und prüft am Ende Schreiben und Lesen.

Danach **einmal** OpenClaw neu starten (Eigentümer: `/restart`), damit die
MCP-Tools geladen werden. Fertig.

## Kein Blindflug

Das Skript ist lesbarer Bash-Code, kein Installer-Blob. Es verlangt **kein
sudo**, öffnet **keinen Port nach außen**, löscht nichts und sichert
`openclaw.json` vor jeder Änderung. Was es genau tut — jede Datei, jeder
Netzwerkzugriff, jeder Rückweg — steht in
[docs/WAS-PASSIERT-BEIM-INSTALL.md](docs/WAS-PASSIERT-BEIM-INSTALL.md). Wenn du
dem Repository nicht traust, nimm den manuellen Weg in
[START-HERE.md](START-HERE.md), Abschnitt 4 „Weg B“: dieselben Schritte, aber
einzeln sichtbar.

Prüfen statt glauben:

```bash
bash -n install.sh
grep -nE 'sudo|rm -rf|eval|base64|curl[^|]*\|[[:space:]]*(ba)?sh|wget' install.sh   # muss leer sein
./install.sh --explain
```

Details, Flags und Sonderfälle: [START-HERE.md](START-HERE.md).

## Dokumentation

| Datei | Inhalt |
|---|---|
| [START-HERE.md](START-HERE.md) | Anleitung für die einbauende KI, Schritt für Schritt mit Erwartungswerten |
| [docs/WAS-PASSIERT-BEIM-INSTALL.md](docs/WAS-PASSIERT-BEIM-INSTALL.md) | jede Aktion, jede Datei, jeder Netzwerkzugriff, Rückbau |
| [docs/HINTERGRUND.md](docs/HINTERGRUND.md) | Architektur, Datenfluss, warum zwei Gedächtnisse |
| [docs/BETRIEB.md](docs/BETRIEB.md) | Tagesbetrieb: wann erinnern, was speichern, Wartung, Rückbau |
| [docs/FEHLERBILDER.md](docs/FEHLERBILDER.md) | Symptom → Ursache → Fix |

## Voraussetzungen im Detail

- **Betriebssystem:** Linux mit systemd (User-Unit). macOS/Container: Server
  läuft, Autostart muss anders gelöst werden (`--no-service`).
- **Python 3.10+**, `python3-venv`
- **Node 18+** (nur für die MCP-Bridge)
- **Ollama** auf `127.0.0.1:11434` mit:
  - `nomic-embed-text` (Embeddings, Pflicht)
  - einem Reasoner, z. B. `qwen3.5:cloud` (für Zusammenfassungen/Preflight)
- **~500 MB** freier Platz, Port **50001** frei
- **OpenClaw** installiert, Config unter `~/.openclaw/openclaw.json`

## Sicherheit

- Der Dienst bindet **nur an 127.0.0.1**. Kein LAN, kein Internet, keine Auth
  nach außen nötig.
- Keine Passwörter oder Tokens in Erinnerungen speichern. Mnemo liegt im
  Klartext auf der Platte (`~/.mnemo-cortex`); Dateirechte schützen, nicht der
  Dienst.
- Das Skript sichert `openclaw.json` vor jeder Änderung nach
  `openclaw.json.bak-<zeitstempel>`.

## Stand

Verifiziert auf OpenClaw mit mehreren Agenten, Mnemo Cortex **4.14.0**
(Commit `6c5a04c`), Ollama `nomic-embed-text` + `qwen3.5:cloud`.
Die Installationsroutine enthält einen Pflicht-Patch, ohne den der Dienst auf
`0.0.0.0` fällt und ohne Auth nicht startet — siehe
[docs/FEHLERBILDER.md](docs/FEHLERBILDER.md).
