# START HERE — Anleitung für die einbauende KI

**Für dich.** Du bist eine KI auf einem OpenClaw-Host und sollst dieses
Gedächtnisverfahren einbauen. Du brauchst kein Vorwissen. Du führst **jeden
Befehl selbst** aus, einen nach dem anderen, und prüfst das Ergebnis. Es gibt
kein Installationsskript in diesem Repository — genau damit du nicht blind
etwas ausführst.

Die einzige Ausnahme ist der **Original-Installer von Mnemo Cortex**
(`robot-install.sh`). Den darfst du aufrufen, nachdem du sein Manifest gelesen
und angepasst hast.

**Grundregeln:**

0. **Informiere dich zuerst über die Zielumgebung.** Jede OpenClaw ist anders
   aufgebaut: Benutzer, Dienstmanager, Config-Format, Agenten, manchmal
   Container oder ein Gateway auf einem anderen Host. Siehe Abschnitt 2 und
   [docs/KOMPATIBILITAET.md](docs/KOMPATIBILITAET.md).
1. **Erst prüfen, ob Mnemo hier schon läuft.** Wenn ja: **nicht installieren.**
   Dann nur den MCP-Block ergänzen (Abschnitt 9, Fall B).
2. **Nichts improvisieren.** Keine Modellnamen raten, keine Ports ändern, keine
   Firewall öffnen.
3. **Nicht überspringen.** Die Reihenfolge hat Gründe.
4. **Prüfen statt glauben.** Jeder Schritt nennt einen Erwartungswert. Weicht er
   ab: abbrechen und [docs/FEHLERBILDER.md](docs/FEHLERBILDER.md) lesen.
5. **Keine Secrets in Erinnerungen.**

---

## 0. Begriffe in 60 Sekunden

- **OpenClaw** – die Agenten-Plattform, auf der du läufst. Config:
  `~/.openclaw/openclaw.json`. Zusatz-Tools kommen über MCP-Server.
- **MCP** – Standard für Agenten-Tools. Die Bridge ist ein kleines
  Node-Programm, das OpenClaw startet.
- **Mnemo Cortex** – lokaler Dienst (Python) für semantische Erinnerungen,
  Port 50001, Daten unter `~/.mnemo-cortex`.
- **Bridge** – Node-Programm zwischen MCP und Mnemo.
- **Tenant / Agent-ID** – Name des Gedächtnisses. Gleiche ID = gleiche
  Erinnerungen.

Zwei Gedächtnisse, absichtlich: OpenClaw nativ (`MEMORY.md`, `memory/*.md`,
`memory_search`, nächtliches Dreaming) bleibt unverändert. Mnemo kommt daneben.

---

## 1. Feststellen, wo du bist

```bash
whoami
echo "$HOME"
uname -s
command -v openclaw || ls -l "$HOME/.npm-global/bin/openclaw"
openclaw --version 2>/dev/null || "$HOME/.npm-global/bin/openclaw" --version
```

Erwartung: Benutzer, Home, `Linux`, eine OpenClaw-Version. Merke dir den
OpenClaw-Pfad.

---

## 2. Vorab informieren: passt die Installation hierher?

**Pflicht.** Dieser Eingriff startet einen Dienst, belegt Port 50001 und ändert
`openclaw.json`. In einer anders aufgebauten Umgebung kann das stören.

```bash
echo "--- Dienstmanager ---"
systemctl --user is-system-running 2>/dev/null || echo "keine systemd-User-Instanz"
systemctl --user is-active openclaw-gateway 2>/dev/null || true

echo "--- Laeuft Mnemo schon? ---"
curl -s --max-time 3 http://127.0.0.1:50001/health || echo "keine Antwort auf 50001"
ls -la "$HOME/.config/mnemo-cortex" 2>/dev/null || echo "keine Mnemo-Config"
systemctl --user is-active mnemo-cortex 2>/dev/null || true
ss -ltn | grep 50001 || echo "Port 50001 frei"

echo "--- OpenClaw-Config ---"
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.openclaw/openclaw.json")
try:
    d = json.load(open(p))
    print("JSON ok")
    print("agents:", list((d.get("agents") or {}).get("entries") or {}))
    print("mcp servers:", list((d.get("mcp") or {}).get("servers") or {}))
    print("memory:", d.get("memory"))
except Exception as e:
    print("NICHT JSON-lesbar:", e)
PY

echo "--- Ressourcen ---"
free -m | head -2
df -h "$HOME" | tail -1
```

**Entscheide mit [docs/KOMPATIBILITAET.md](docs/KOMPATIBILITAET.md):**

- **Mnemo antwortet auf 50001 oder es gibt eine Mnemo-Config** → **nicht
  installieren**. Weiter mit Abschnitt 9, Fall B (nur MCP-Block).
- **Alles frei und Grün** → weiter mit Abschnitt 3.
- **Gelb** (JSON5-Config, anderer Node-Pfad, Container, anderer Port) → die
  Anpassung steht in der Matrix.
- **Rot** (flüchtiger Container, fremd verwaltete Instanz, kein Ollama und
  keine Erlaubnis, kein Backup/Rollback, unbekannter Dienst auf 50001) →
  **nicht installieren**, melden und fragen.

---

## 3. Voraussetzungen prüfen

```bash
python3 --version
python3 -c 'import venv; print("venv ok")'
node --version
git --version
curl -s --max-time 5 http://127.0.0.1:11434/api/tags | head -c 120
ollama list | grep -E 'nomic-embed-text|qwen3.5'
```

| Prüfung | Erwartung |
|---|---|
| Python | ≥ 3.10, `venv ok` |
| Node | ≥ 18 |
| Git/curl | vorhanden |
| Ollama | JSON mit `"models"` |
| Modelle | `nomic-embed-text` + ein Reasoner |
| Platz | ≥ 500 MB frei |

Fehlt etwas: erst herstellen (siehe unten), nicht überspringen.

- `venv` fehlt → `sudo apt install -y python3-venv` (Debian/Ubuntu) oder
  `sudo pacman -S --needed python` (Arch)
- Node fehlt → `sudo apt install -y nodejs npm` oder Node ≥ 18 über nvm/fnm
- Ollama fehlt → **Menschen fragen**, nicht selbst installieren
- Embedding fehlt → `ollama pull nomic-embed-text` (Pflicht)
- Reasoner fehlt → `ollama pull qwen3.5:cloud` oder lokales Modell wählen

---

## 4. Mnemo Cortex holen (Original-Projekt)

```bash
git clone https://github.com/GuyMannDude/mnemo-cortex.git "$HOME/.local/share/mnemo-cortex"
cd "$HOME/.local/share/mnemo-cortex"
git checkout 6c5a04c
grep -m1 '^version' pyproject.toml
```

Erwartung: `version = "4.14.0"`.

Wenn das Verzeichnis schon existiert: nicht klonen, sondern

```bash
cd "$HOME/.local/share/mnemo-cortex" && git status --short && git log -1 --oneline
```

und prüfen, ob dort schon eine Installation liegt (dann Abschnitt 2).

---

## 5. Ein-Zeilen-Patch am Original-Installer

Der Upstream-Installer schreibt `AGENTB_CONFIG` nicht in die env-Datei. Ohne
diese Zeile startet der Dienst auf `0.0.0.0` und verweigert ohne Auth den
Start. Das ist der häufigste Abbruchgrund.

**Erst ansehen, was die Zeile tut:**

```bash
grep -n 'Mnemo Cortex env' robot-install.sh
sed -n '355,375p' robot-install.sh
```

**Dann patchen (eine Zeile, nur wenn sie fehlt, vorher Backup):**

```bash
cp -a robot-install.sh robot-install.sh.bak
# idempotent: patcht nur, wenn die Zeile noch nicht vorhanden ist
grep -q 'AGENTB_CONFIG=\$CONFIG_FILE' robot-install.sh || \
  sed -i '/echo "# Mnemo Cortex env/a\    echo "AGENTB_CONFIG=$CONFIG_FILE"' robot-install.sh
grep -n -A2 'Mnemo Cortex env' robot-install.sh
```

Erwartung: unter der Ankerzeile steht **genau einmal**
`echo "AGENTB_CONFIG=$CONFIG_FILE"`. Steht sie doppelt, ist die Datei schon
zweimal gepatcht → Backup zurückspielen und Schritt wiederholen. Mehr ändert
der Patch nicht.

Prüfen, dass nur eine Zeile dazugekommen ist:

```bash
diff robot-install.sh.bak robot-install.sh
```

---

## 6. Manifest anpassen

Das Manifest sagt dem Installer, was gebaut wird. Vorlage aus diesem Repo
nehmen und die Werte prüfen:

```bash
cp templates/robot.install "$HOME/.local/share/mnemo-cortex/robot.install"
```

Öffne die Datei und kontrolliere:

| Feld | Wert | Warum |
|---|---|---|
| `service.host` | `127.0.0.1` | niemals `0.0.0.0` |
| `service.port` | `50001` | muss frei sein |
| `reasoning.model` | Modell aus `ollama list` | sonst kein Preflight |
| `embedding.model` | `nomic-embed-text` | sonst kein Recall |
| `smoke_test.agent_id` | dein Tenant, z. B. `openclaw-shared` | bestimmt die ID |
| `systemd.enabled` | `true` (Linux mit systemd) | sonst `false` |

Der Installer entfernt `//`-Kommentare selbst; du kannst sie stehen lassen.

---

## 7. Original-Installer ausführen

Das ist der **einzige** fremde Installer, den du ausführst. Er legt `.venv` an,
installiert Python-Pakete, schreibt Config und env-Datei, erzeugt die
systemd-Unit und macht einen Smoke-Test.

```bash
cd "$HOME/.local/share/mnemo-cortex"
./robot-install.sh
```

Erwartung: **genau ein JSON-Objekt** auf stdout, `"ok": true`, Exit-Code 0.

```bash
echo "exit=$?"
```

Bei `"ok": false`: die genannte Stufe lesen, reparieren, erneut ausführen.
Nicht weiterbauen.

---

## 8. Dienst und Health prüfen

Der Installer aktiviert den Dienst bereits. Prüfe es selbst:

```bash
systemctl --user is-active mnemo-cortex
systemctl --user status mnemo-cortex --no-pager | head -12
curl -s http://127.0.0.1:50001/health | python3 -m json.tool
ss -ltn | grep 50001
```

Erwartung:

- `active`
- Health: `"status":"ok"`, `version 4.14.0`, `embedding.healthy true`
- `ss` zeigt `127.0.0.1:50001` — **nicht** `0.0.0.0:50001`

Wenn der Dienst nicht läuft:

```bash
journalctl --user -u mnemo-cortex -n 50 --no-pager
```

Häufigste Ursache: `AGENTB_CONFIG` fehlt in
`~/.config/mnemo-cortex/mnemo-cortex.env` → Patch aus Abschnitt 5, dann

```bash
systemctl --user daemon-reload
systemctl --user restart mnemo-cortex
```

### Schreib-/Lesetest (manuell, ein Testeintrag)

```bash
MARK="MNEMO-SELFTEST-$(date +%Y%m%d-%H%M%S)"
curl -s -X POST http://127.0.0.1:50001/writeback \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\":\"openclaw-shared-selftest\",\"summary\":\"Installations-Selftest $MARK\",\"key_facts\":[\"selftest_marker=$MARK\"],\"projects_referenced\":[],\"decisions_made\":[],\"agent_id\":\"openclaw-shared\",\"source\":\"tool\",\"category\":\"session_log\"}"
sleep 2
curl -s -X POST http://127.0.0.1:50001/context \
  -H 'Content-Type: application/json' \
  -d "{\"prompt\":\"$MARK\",\"agent_id\":\"openclaw-shared\",\"max_results\":3,\"exclude_categories\":[]}"
```

Erwartung: erst eine `memory_id`, dann ein Treffer, der `$MARK` enthält. Sonst
Embedding-Modell prüfen.

---

## 9. OpenClaw anbinden

### Fall A — Mnemo wurde gerade neu installiert

Backup, dann Block eintragen. **Nicht** die GUI-Speichern-Schaltfläche nutzen,
wenn der Host dabei sofort neu startet.

```bash
cp -a "$HOME/.openclaw/openclaw.json" "$HOME/.openclaw/openclaw.json.bak-$(date +%Y%m%d-%H%M%S)"
python3 -m json.tool "$HOME/.openclaw/openclaw.json" > /dev/null && echo "Config ist valides JSON"
```

Öffne `~/.openclaw/openclaw.json` und ergänze unter `mcp` → `servers` (bestehende
Server bleiben stehen):

```json
"mnemo-cortex": {
  "command": "/usr/bin/node",
  "args": ["/home/<USER>/.local/share/mnemo-cortex/integrations/mcp-bridge/server.js"],
  "env": {
    "MNEMO_URL": "http://127.0.0.1:50001",
    "MNEMO_AGENT_ID": "openclaw-shared",
    "MNEMO_SHARE": "always"
  },
  "cwd": "/home/<USER>/.local/share/mnemo-cortex/integrations/mcp-bridge",
  "supportsParallelToolCalls": true,
  "connectionTimeoutMs": 10000,
  "requestTimeoutMs": 30000
}
```

`<USER>` ersetzen, `command` auf den echten Node-Pfad setzen
(`command -v node`). Danach validieren:

```bash
python3 -m json.tool "$HOME/.openclaw/openclaw.json" > /dev/null && echo "JSON ok"
```

Ist die Datei kein reines JSON (Kommentare/JSON5), trage den Block mit deinem
Editor ein und prüfe die Datei mit dem Werkzeug, das dieser Host sonst nutzt.
Nichts automatisch umschreiben.

### Fall B — Mnemo läuft hier schon

**Nicht installieren, nicht patchen, keinen Dienst anfassen.** Nur den
MCP-Block ergänzen — mit der **vorhandenen** Agent-ID, sonst siehst du die
alten Erinnerungen nicht:

```bash
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.openclaw/openclaw.json")
d = json.load(open(p))
s = (d.get("mcp") or {}).get("servers", {}).get("mnemo-cortex")
print("vorhandener Block:", json.dumps(s, indent=1) if s else "keiner")
PY
```

- Block vorhanden → nichts tun, nur Abschnitt 10 prüfen.
- Block fehlt → Block wie in Fall A eintragen, aber `MNEMO_AGENT_ID` auf die ID
  setzen, unter der die vorhandenen Daten liegen (aus der Mnemo-Config oder
  beim Betreiber erfragen). `MNEMO_SHARE` passend wählen.

---

## 10. Neu starten und Tools prüfen

MCP-Server werden nur beim Start geladen.

- Läuft dein Agent **in** dieser OpenClaw: Der Eigentümer sendet `/restart`.
- Shell-Zugriff, kein laufender Chat: `openclaw gateway restart` (beendet
  Sitzungen).
- Danach `openclaw gateway status`.

In der nächsten Sitzung müssen diese Tools sichtbar sein (Präfix je nach Host,
z. B. `mnemo-cortex__mnemo_recall`):

`mnemo_recall`, `mnemo_save`, `mnemo_search`, `mnemo_share`,
`mnemo_recall_trajectory`, `mnemo_save_trajectory`, `mnemo_fact_save`,
`mnemo_fact_demote`

Fehlen sie: Block prüfen, Pfad prüfen (`ls -l <bridge>/server.js`), erneut neu
starten.

**Funktionstest aus der Sitzung:**

1. `mnemo_save` mit `summary: "Installations-Selftest: Mnemo antwortet."`,
   `source: "tool"`, `category: "session_log"`.
   Erwartung: `memory_id`, `agent`, `category_used`.
2. `mnemo_recall` mit einer eindeutigen Formulierung aus dem Save.
   Erwartung: der Eintrag kommt zurück.
3. `memory_search` mit einem Workspace-Begriff.
   Erwartung: funktioniert wie vorher.

---

## 11. Arbeitsregeln aktivieren

Inhalt von [templates/AGENTS-memory-block.md](templates/AGENTS-memory-block.md)
in die `AGENTS.md` übernehmen (Abschnitt `## Memory` ersetzen/ergänzen).

Kurzfassung: vor Fragen zu früherer Arbeit `memory_search`, bei älteren oder
agentenübergreifenden Fakten `mnemo_recall`/`mnemo_search`, vor wiederkehrenden
Aufgaben `mnemo_recall_trajectory`; speichern nach Salienz; `source` korrekt;
`stale_warning` ernst nehmen; nach guter Arbeit `mnemo_save_trajectory`.

---

## 12. Abnahmeprotokoll

```
[ ] Zielumgebung geprueft (Abschnitt 2, KOMPATIBILITAET.md)
[ ] Mnemo lief vorher nicht / oder: nicht installiert, nur Block ergaenzt
[ ] Dienst: active
[ ] Health: status ok, v4.14.0, embedding healthy
[ ] Bind: 127.0.0.1:50001 (nicht 0.0.0.0)
[ ] Schreib-/Lesetest: memory_id + Treffer
[ ] MCP-Block vorhanden, JSON valide
[ ] Gateway neu gestartet
[ ] Tools sichtbar (Namen notieren)
[ ] Save->Recall aus der Sitzung
[ ] memory_search nativ funktioniert
[ ] AGENTS.md-Regeln eingetragen
```

Fehlschläge nicht beschönigen.

---

## 13. Was du den Menschen fragen darfst

1. „Ollama fehlt. Soll ich es installieren, oder machst du das?"
2. „Welches Reasoner-Modell: `qwen3.5:cloud` oder lokal?"
3. „Mnemo läuft schon. Unter welcher Agent-ID liegen die vorhandenen
   Erinnerungen?"
4. „Soll das Gedächtnis geteilt werden (`MNEMO_SHARE=always`) oder getrennt?"

Alles andere (Pfade, Versionen, Ports, Config-Ort) prüfst du selbst.

**Nie ohne Auftrag:** Ports nach außen öffnen, Firewall ändern, Gateway
deinstallieren, `~/.mnemo-cortex` löschen, Secrets speichern.

---

## 14. Reihenfolge zum Nachschlagen

```
0. Zielumgebung + vorhandene Mnemo-Installation pruefen
1. whoami / openclaw --version
2. Voraussetzungen
3. git clone + Pin
4. Patch (eine Zeile, mit Backup)
5. Manifest anpassen
6. ./robot-install.sh  (Original-Programm)
7. Dienst + Health + Schreib-/Lesetest
8. MCP-Block (Fall A neu / Fall B vorhanden)
9. Gateway neu starten, Tools pruefen
10. AGENTS.md-Regeln
11. Abnahmeprotokoll
```

Weiter: [docs/KOMPATIBILITAET.md](docs/KOMPATIBILITAET.md),
[docs/WAS-PASSIERT-BEIM-INSTALL.md](docs/WAS-PASSIERT-BEIM-INSTALL.md),
[docs/HINTERGRUND.md](docs/HINTERGRUND.md),
[docs/BETRIEB.md](docs/BETRIEB.md), [docs/FEHLERBILDER.md](docs/FEHLERBILDER.md).
