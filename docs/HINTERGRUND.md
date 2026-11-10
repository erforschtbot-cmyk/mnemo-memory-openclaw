# Hintergrund: was hier gebaut wird und warum

## Das Problem

OpenClaw bringt ein gutes Datei-Gedächtnis mit: `MEMORY.md`, Tagesnotizen,
`memory_search`, nächtliche Konsolidierung (Dreaming). Das reicht für einen
Agenten, der in seinem Workspace lebt. Es hat aber drei Grenzen:

1. **Kein sofortiges semantisches Abrufen über alte Sitzungen hinweg.** Die
   native Suche arbeitet über Dateien und Indizes, nicht über „was weiß ich
   über dieses Thema".
2. **Kein Agenten-übergreifendes Gedächtnis.** Jeder Workspace hat seine
   eigenen Dateien.
3. **Kein Verfallsbewusstsein.** Eine IP von vor sechs Monaten sieht genauso
   aus wie eine von gestern.

## Die Lösung in drei Schichten

```
┌──────────────────────────────────────────────────────────────────┐
│ OpenClaw-Agent                                                   │
│                                                                  │
│  native Memory                MCP-Tools                          │
│  memory_search                mnemo_recall / mnemo_save / ...    │
│  memory_get                          │                           │
│       │                              │ stdio                     │
│       ▼                              ▼                           │
│  MEMORY.md, memory/*.md       mcp-bridge/server.js (Node)        │
│  memory/.dreams/                     │ HTTP                       │
│                                      ▼                           │
│                          Mnemo Cortex (Python, 127.0.0.1:50001)  │
│                          ~/.mnemo-cortex (SQLite + Vektoren)     │
└──────────────────────────────────────────────────────────────────┘
```

### Schicht 1: Mnemo Cortex (der Server)

Ein lokaler FastAPI-Dienst, gestartet als systemd-User-Unit. Er speichert
Erinnerungen als Textchunks mit Metadaten und Embeddings und findet sie
semantisch wieder.

Wichtige Eigenschaften:

- **Embeddings lokal** über Ollama (`nomic-embed-text`). Kein Cloud-Zwang für
  die Suche.
- **Reasoner** (z. B. `qwen3.5:cloud`) für Zusammenfassungen, Preflight und
  Dreaming. Fällt er aus, bleibt die Suche funktionsfähig.
- **Kategorien mit Verfall:** `topology` (30/90 Tage), `current_state` (90),
  `incident`/`session_log` (90), `relationship` (180). Ab dem Warntag liefert
  ein Treffer ein `stale_warning`, ab dem Stale-Tag fällt er aus strengen
  Abfragen.
- **Strukturierte Fakten:** `(entity, attribute) → value` mit Confidence und
  Audit-Log bei Widerspruch. Für Dinge, die exakt sein müssen (Version, Port,
  Zuständigkeit).
- **Trajectories:** bewährte Arbeitsschritte als Rezept, bewertet 1–5.
- **Auto-Capture:** Tool-Aktivität der Bridge wird als `session_log`
  mitgeschrieben, damit der Verlauf nachvollziehbar bleibt.

### Schicht 2: MCP-Bridge

Ein Node-Prozess ohne eigenen Zustand. OpenClaw startet ihn, er verbindet per
stdio mit dem Agenten und per HTTP mit Mnemo. Konfiguriert wird er
ausschließlich über Umgebungsvariablen im `openclaw.json`-Block:

| Variable | Bedeutung |
|---|---|
| `MNEMO_URL` | Adresse des Servers, immer `http://127.0.0.1:50001` |
| `MNEMO_AGENT_ID` | Tenant-Name; gleiche ID = gleiches Gedächtnis |
| `MNEMO_SHARE` | `always` / `separate` / `never` |

Die Bridge ist der einzige Ort, an dem die Tool-Namen entstehen. Ändert sich
der Pfad in `args`, findet OpenClaw den Server nicht mehr — dann fehlen alle
Tools, ohne Fehlermeldung im Chat.

### Schicht 3: OpenClaw nativ

Bleibt unverändert. Wichtig zu verstehen: **Mnemo ersetzt nichts.** Die native
Schicht ist weiterhin zuständig für Workspace-Dateien, Sitzungsverlauf und die
nächtliche Konsolidierung. Mnemo ist das Langzeitgedächtnis daneben.

## Datenfluss beim Erinnern

1. Der Agent bekommt eine Frage („Wie war das mit dem Dienst auf .96?").
2. `memory_search` durchsucht Workspace-Dateien und Sitzungen.
3. Reicht das nicht, ruft der Agent `mnemo_recall` mit einer Formulierung der
   Frage auf. Mnemo embeddet die Anfrage, sucht ähnliche Chunks, filtert nach
   Kategorie/Alter und liefert Treffer mit Quelle, Alter und ggf. Warnung.
4. Der Agent prüft veraltete Fakten live, bevor er handelt.

## Datenfluss beim Speichern

1. Etwas Salientes passiert (Entscheidung, Fix, verifizierter Fakt).
2. `mnemo_save` schreibt Zusammenfassung + Key-Facts, optional Quelle und
   Kategorie. Ohne Kategorie rät ein Regex-Suggester und nennt die Wahl.
3. Die Bridge puffert Tool-Aktivität und schreibt sie gebündelt als
   `session_log` (Auto-Capture).
4. Nachts konsolidiert OpenClaws Dreaming die nativen Dateien; Mnemo behält
   seine Einträge mit Verfallslogik.

## Wo die Daten liegen

| Pfad | Inhalt |
|---|---|
| `~/.mnemo-cortex/` | Erinnerungen, Vektoren, `facts.sqlite`, Sessions |
| `~/.config/mnemo-cortex/mnemo-cortex.yaml` | Server-Config |
| `~/.config/mnemo-cortex/mnemo-cortex.env` | Umgebung inkl. `AGENTB_CONFIG` (chmod 600) |
| `~/.local/share/mnemo-cortex/` | Programm + `.venv` |
| `~/.config/systemd/user/mnemo-cortex.service` | Autostart |

## Sicherheit und Grenzen

- Der Dienst bindet **nur an Loopback**. Er hat keine Authentifizierung, weil
  er nicht von außen erreichbar ist. Wird er versehentlich auf `0.0.0.0`
  gebunden, verweigert er ohne Auth den Start — das ist eine Schutzfunktion,
  kein Bug.
- Kein Verschlüsselungsversprechen: die Daten liegen im Klartext. Dateirechte
  und Host-Sicherheit schützen sie.
- **Ein Server pro Host.** Mehrere Hosts sollten nicht dieselbe
  `~/.mnemo-cortex`-Datenbank über ein Netzlaufwerk teilen. Wenn ein zweiter
  Host mitlesen soll, gehört er an denselben Server (z. B. per SSH-Tunnel) mit
  eigener `MNEMO_AGENT_ID` und passendem `MNEMO_SHARE`.
- **Kein Ersatz für Backups.** `~/.mnemo-cortex` und `~/.config/mnemo-cortex`
  zusammen sichern.

## Warum die Installationsroutine einen Patch braucht

Der Upstream-Installer schreibt `AGENTB_CONFIG` nicht in die env-Datei. Ohne
diese Variable findet der Dienst seine YAML-Config nicht, fällt auf
`0.0.0.0` zurück und verweigert ohne Auth den Start. Der Patch ist eine Zeile
und wird in [START-HERE.md](../START-HERE.md), Schritt 5, manuell und idempotent
gesetzt. Nach einem `git pull` im
Mnemo-Verzeichnis erneut ausführen.
