# Mnemo-Memory für OpenClaw

Eine Anleitung, mit der eine KI auf einem OpenClaw-Host ein **lokales
Langzeitgedächtnis** einbaut: **Mnemo Cortex** als Dienst, angebunden per
**MCP**, plus die Arbeitsregeln, die daraus brauchbares Erinnern machen.

> **Du bist eine KI und sollst das einbauen?**
> Lies **[START-HERE.md](START-HERE.md)**. Dort stehen alle Befehle einzeln,
> mit Erwartungswerten. Dieses Repository enthält **kein Installationsskript** —
> du installierst selbst, Schritt für Schritt, und prüfst jedes Ergebnis.
> Einzige Ausnahme: der Original-Installer von Mnemo Cortex
> (`robot-install.sh`) aus dem Upstream-Projekt, den du nach dem Lesen seines
> Manifests ausführst.
>
> **Vorher Pflicht:** Prüfe, ob Mnemo auf dem Host **schon läuft**, und ob die
> Umgebung passt. Jede OpenClaw ist anders aufgebaut. Wenn schon eine
> Installation existiert, wird **nicht installiert**, sondern nur der
> MCP-Block ergänzt — sonst überschreibst du Config, Dienst und Tenant.
> Siehe **[docs/KOMPATIBILITAET.md](docs/KOMPATIBILITAET.md)**.

---

## Was am Ende läuft

```
OpenClaw-Agent ──MCP──> mcp-bridge (Node) ──HTTP──> Mnemo Cortex (127.0.0.1:50001)
      │                                                    │
      └── native Memory (MEMORY.md, memory/*.md)           └── ~/.mnemo-cortex (Daten)
```

| Schicht | Aufgabe | Standard-OpenClaw? |
|---|---|---|
| **Mnemo Cortex** | semantisches Langzeitgedächtnis, Kategorien, Verfall, strukturierte Fakten, Task-Rezepte | nein |
| **MCP-Bridge** | stellt Mnemo als Agent-Tools bereit (`mnemo_recall`, `mnemo_save`, …) | nein |
| **OpenClaw Memory** | `memory_search`, Tagesnotizen, `MEMORY.md`, nächtliches Dreaming | ja |

Die native Schicht bleibt unangetastet.

## Was du bekommst

- `mnemo_recall` – semantisch erinnern, mit Alter, Quelle, Kategorie und
  `stale_warning`
- `mnemo_save` – Entscheidungen und Fakten speichern, Kategorie steuert den
  Verfall
- `mnemo_search` – agentenübergreifend suchen
- `mnemo_fact_save` / `mnemo_fact_demote` – exakte `(entity, attribute)`-Fakten
- `mnemo_save_trajectory` / `mnemo_recall_trajectory` – bewährte Arbeitsabläufe
- automatische Erfassung von Tool-Aktivität als `session_log`

## Ablauf in Kurzform

1. **Zielumgebung prüfen** – läuft Mnemo schon? Config lesbar? Port frei?
2. **Voraussetzungen** – Python, Node, Git, Ollama mit `nomic-embed-text`
3. **Upstream holen** – `github.com/GuyMannDude/mnemo-cortex`, Pin `6c5a04c`
4. **Eine Zeile patchen** – `AGENTB_CONFIG` in die env-Datei, mit Backup
5. **Manifest anpassen** – loopback, Port 50001, Modelle, Tenant
6. **Original-Installer ausführen** – `./robot-install.sh`
7. **Dienst, Health, Schreib-/Lesetest** – selbst prüfen
8. **MCP-Block eintragen** – in `~/.openclaw/openclaw.json`
9. **Gateway neu starten** – Tools prüfen
10. **AGENTS.md-Regeln** – Verhalten übernehmen

Alle Befehle stehen ausformuliert in [START-HERE.md](START-HERE.md).

## Voraussetzungen

- **Linux mit systemd** (User-Unit). macOS/Container: Dienst manuell starten.
- **Python ≥ 3.10** inkl. `venv`
- **Node ≥ 18** für die MCP-Bridge
- **Ollama** auf `127.0.0.1:11434` mit `nomic-embed-text` und einem Reasoner
- **~500 MB** frei, Port **50001** frei
- **OpenClaw** installiert, Config unter `~/.openclaw/openclaw.json`

## Dokumentation

| Datei | Inhalt |
|---|---|
| [START-HERE.md](START-HERE.md) | Anleitung für die einbauende KI, Befehl für Befehl |
| [docs/KOMPATIBILITAET.md](docs/KOMPATIBILITAET.md) | Vorab-Prüfung: läuft Mnemo schon? passt die Umgebung? Grün/Gelb/Rot |
| [docs/WAS-PASSIERT-BEIM-INSTALL.md](docs/WAS-PASSIERT-BEIM-INSTALL.md) | was jeder Schritt ändert, welche Dateien, welcher Netzwerkverkehr, Rückbau |
| [docs/HINTERGRUND.md](docs/HINTERGRUND.md) | Architektur, Datenfluss, warum zwei Gedächtnisse |
| [docs/BETRIEB.md](docs/BETRIEB.md) | Tagesbetrieb, Backups, Updates, Rückbau |
| [docs/FEHLERBILDER.md](docs/FEHLERBILDER.md) | Symptom → Ursache → Fix |

## Sicherheit

- Der Dienst bindet **nur an 127.0.0.1**. Kein LAN, kein Internet, keine Auth
  nach außen. `0.0.0.0` ist ein Fehler, kein Feature.
- Keine Passwörter oder Tokens in Erinnerungen. Mnemo liegt im Klartext auf der
  Platte (`~/.mnemo-cortex`); Dateirechte schützen, nicht der Dienst.
- Vor jeder Änderung an `openclaw.json`: Backup anlegen
  (`openclaw.json.bak-<zeitstempel>`).

## Stand

Verifiziert mit OpenClaw, Mnemo Cortex **4.14.0** (Commit `6c5a04c`), Ollama
`nomic-embed-text` + `qwen3.5:cloud`. Der Ein-Zeilen-Patch ist nötig, weil der
Upstream-Installer `AGENTB_CONFIG` nicht in die env-Datei schreibt — ohne ihn
fällt der Dienst auf `0.0.0.0` und startet ohne Auth nicht.
