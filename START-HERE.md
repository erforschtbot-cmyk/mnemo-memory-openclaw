# START HERE — Anleitung für die einbauende KI

**Für dich.** Du bist eine KI auf einem OpenClaw-Host und sollst dieses
Gedächtnisverfahren einbauen. Du brauchst kein Vorwissen über Mnemo, MCP oder
dieses Repository. Arbeite die Schritte der Reihe nach ab. Jeder Schritt sagt
dir, was du tun sollst, was du sehen wirst und was du tun sollst, wenn es anders
aussieht.

**Grundregeln für dich:**

1. **Nichts improvisieren.** Keine Modellnamen raten, keine Ports ändern, keine
   Firewall öffnen, nichts nach außen freigeben.
2. **Nicht überspringen.** Die Reihenfolge hat Gründe: ohne Dienst kein MCP,
   ohne MCP keine Tools.
3. **Prüfen statt glauben.** Jeder Schritt hat einen Erwartungswert. Weicht er
   ab, brich ab und lies [docs/FEHLERBILDER.md](docs/FEHLERBILDER.md).
4. **Nur eine Frage an den Menschen**, wenn wirklich etwas fehlt (siehe
   Abschnitt 9). Alles andere kannst du selbst feststellen.
5. **Keine Secrets in Erinnerungen.** Keine Passwörter, Tokens, Schlüssel.

---

## 0. Begriffe in 60 Sekunden

- **OpenClaw** – die Agenten-Plattform, auf der du läufst. Konfiguration:
  `~/.openclaw/openclaw.json`. Agenten-Tools werden über MCP-Server erweitert.
- **MCP** – ein Standard, über den ein Agent zusätzliche Tools bekommt. Ein
  MCP-Server ist hier ein kleines Node-Programm, das OpenClaw startet.
- **Mnemo Cortex** – ein lokaler Dienst (Python), der Erinnerungen speichert und
  semantisch wiederfindet. Er läuft getrennt von OpenClaw auf Port 50001.
- **Bridge** – das Node-Programm dazwischen. Es übersetzt MCP-Aufrufe in
  HTTP-Aufrufe an Mnemo.
- **Tenant / Agent-ID** – Name, unter dem Erinnerungen abgelegt werden. Gleiche
  ID = gleiches Gedächtnis. Hier: `openclaw-shared`.

Es gibt **zwei** Gedächtnisse, absichtlich:

- **OpenClaw nativ**: Dateien im Workspace (`MEMORY.md`, `memory/*.md`),
  `memory_search`, nächtliche Konsolidierung. Bleibt wie es ist.
- **Mnemo**: sofort abfragbar, semantisch, agentenübergreifend, mit Verfall.
  Das baust du jetzt ein.

---

## 1. Feststellen, wo du bist

Führe aus und notiere die Ausgaben:

```bash
whoami
echo "$HOME"
uname -s
```

Erwartung: ein Benutzername, ein Home-Pfad, `Linux`.

OpenClaw finden:

```bash
command -v openclaw || ls -l "$HOME/.npm-global/bin/openclaw"
openclaw --version 2>/dev/null || "$HOME/.npm-global/bin/openclaw" --version
```

Erwartung: eine Version wie `OpenClaw 2026.x.y (...)`. Merke dir den **vollen
Pfad** des Befehls; wenn `openclaw` nicht im PATH liegt, benutze ihn mit Pfad.

Prüfen, ob du eine Shell hast: ja, sonst hättest du die Befehle nicht ausführen
können. Ohne Shell kannst du nur den Link an den Menschen geben (Abschnitt 9).

---

## 2. Voraussetzungen prüfen

Führe diesen Block **komplett** aus. Er ändert nichts.

```bash
echo "--- Python ---"; python3 --version
echo "--- venv ---"; python3 -c 'import venv; print("venv ok")'
echo "--- Node ---"; node --version
echo "--- Git ---"; git --version
echo "--- systemd ---"; systemctl --user is-system-running 2>/dev/null || echo "keine systemd-User-Instanz"
echo "--- Ollama ---"; curl -s --max-time 5 http://127.0.0.1:11434/api/tags | head -c 120
echo "--- Modelle ---"; ollama list 2>/dev/null | grep -E 'nomic-embed-text|qwen3.5' || echo "Modelle fehlen"
echo "--- Port ---"; (ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null) | grep ':50001' || echo "Port 50001 frei"
echo "--- Platz ---"; df -h "$HOME" | tail -1
```

**Sollzustand:**

| Prüfung | Erwartung |
|---|---|
| Python | `Python 3.10` oder höher |
| venv | `venv ok` |
| Node | `v18` oder höher |
| Git | eine Version |
| systemd | `running` (sonst später `--no-service`) |
| Ollama | JSON mit `"models"` |
| Modelle | `nomic-embed-text` **und** ein Reasoner |
| Port | `Port 50001 frei` |
| Platz | mindestens 500 MB frei |

**Wenn etwas fehlt:**

- `venv` fehlt → Debian/Ubuntu: `sudo apt install -y python3-venv`; Arch:
  `sudo pacman -S --needed python`
- Node fehlt → `sudo apt install -y nodejs npm` **oder** Node 20 über
  `nvm`/`fnm`. Mindestens 18.
- Git fehlt → `sudo apt install -y git`
- Ollama fehlt → **erst den Menschen fragen** (Abschnitt 9). Nicht einfach
  installieren, das ist ein eigener Dienst mit eigenem Speicherbedarf.
- `nomic-embed-text` fehlt → `ollama pull nomic-embed-text` (Pflicht, sonst
  findet Recall nichts).
- Reasoner fehlt → `ollama pull qwen3.5:cloud`. Ohne Cloud-Zugang ein lokales
  Modell wählen, z. B. `qwen3:8b`, und in Schritt 3 einsetzen.
- Port belegt → `ss -ltnp | grep 50001` zeigt den Prozess. Nicht killen, erst
  prüfen, ob dort schon ein Mnemo läuft (`curl -s 127.0.0.1:50001/health`).
  Läuft dort bereits eines, ist der Dienst schon da: weiter mit Schritt 5.

---

## 3. Repository holen

```bash
git clone https://github.com/erforschtbot-cmyk/mnemo-memory-openclaw.git "$HOME/.openclaw/mnemo-handover"
cd "$HOME/.openclaw/mnemo-handover"
ls
```

Erwartung: `README.md  START-HERE.md  install.sh  verify.sh  docs  templates`.

Wenn das Verzeichnis schon existiert: nicht neu klonen, sondern

```bash
cd "$HOME/.openclaw/mnemo-handover" && git pull --ff-only
```

---

## 3.5 Bevor du ausführst: prüfen, was der Code tut

**Du startest kein fremdes Skript blind.** Auch dieses nicht. Drei Prüfungen,
zwei Minuten:

```bash
cd "$HOME/.openclaw/mnemo-handover"
wc -l install.sh
bash -n install.sh
# gefaehrliche Muster suchen (Erwartung: keine Treffer)
grep -nE 'sudo|rm -rf|eval|base64|curl[^|]*\|[[:space:]]*(ba)?sh|wget' install.sh
# Plan anzeigen, ohne etwas zu aendern
./install.sh --explain
```

Dann beantworte fuer dich diese drei Fragen. Kannst du eine nicht beantworten,
lies [docs/WAS-PASSIERT-BEIM-INSTALL.md](docs/WAS-PASSIERT-BEIM-INSTALL.md),
bevor du weitermachst.

1. **Welche Dateien werden geändert?** (Antwort: neues Programmverzeichnis,
   Config unter `~/.config/mnemo-cortex`, systemd-Unit, ein Block in
   `openclaw.json` — Letzteres mit Backup.)
2. **Wohin geht Netzwerkverkehr?** (github.com für den Code, PyPI für
   Python-Pakete, `127.0.0.1` für Ollama und Mnemo. Sonst nichts.)
3. **Wie mache ich es rückgängig?** (Dienst deaktivieren, Block aus
   `openclaw.json` entfernen, Verzeichnisse löschen —
   `docs/WAS-PASSIERT-BEIM-INSTALL.md`, Abschnitt 5.)

Wenn das Skript `sudo` verlangt, einen Port nach außen öffnet oder ohne Backup
löscht: **abbrechen und melden**. Das ist hier nicht vorgesehen.

---

## 4. Installieren

### Weg A — ein Befehl (empfohlen)

```bash
cd "$HOME/.openclaw/mnemo-handover"
./install.sh
```

Das Skript macht:

1. Voraussetzungen erneut prüfen (bricht mit klarer Meldung ab)
2. Mnemo Cortex nach `~/.local/share/mnemo-cortex` holen, gepinnt auf `6c5a04c`
3. den Pflicht-Patch am Installer setzen
4. Installations-Manifest schreiben (loopback, Port 50001, Ollama-Modelle)
5. `.venv` anlegen, Paket installieren, systemd-Unit erzeugen und starten
6. auf `/health` warten
7. den MCP-Block in `~/.openclaw/openclaw.json` eintragen (mit Backup)
8. `verify.sh` ausführen (Schreiben + Lesen)

**Erwartung am Ende:**

```
== Ergebnis ==
  OK   Dienst aktiv
  OK   health ok (v4.14.0)
  OK   loopback 127.0.0.1:50001
  OK   Recall antwortet
  OK   gespeichert und wiedergefunden
ERGEBNIS: alles gruen
Naechster Schritt: OpenClaw neu starten ...
```

Kommt `ERGEBNIS: Fehler vorhanden` → Abschnitt 8 / `docs/FEHLERBILDER.md`.

### Weg B — manuell (nur wenn Weg A scheitert)

Dann musst du verstehen, was passiert. Die Einzelbefehle:

```bash
# 1) Quellcode
git clone https://github.com/GuyMannDude/mnemo-cortex.git "$HOME/.local/share/mnemo-cortex"
cd "$HOME/.local/share/mnemo-cortex"
git checkout 6c5a04c
grep -m1 '^version' pyproject.toml          # muss 4.14.0 sein

# 2) Pflicht-Patch: AGENTB_CONFIG in die env-Datei schreiben
"$HOME/.openclaw/mnemo-handover/install.sh" --patch-only

# 3) Manifest
cp "$HOME/.openclaw/mnemo-handover/templates/robot.install" robot.install

# 4) Installieren
./robot-install.sh                           # muss {"ok": true} ausgeben

# 5) Dienst
systemctl --user daemon-reload
systemctl --user enable --now mnemo-cortex
systemctl --user status mnemo-cortex --no-pager | head -12
```

Warum der Patch Pflicht ist: ohne `AGENTB_CONFIG` in
`~/.config/mnemo-cortex/mnemo-cortex.env` startet der Dienst mit
Fallback-Bind `0.0.0.0` und verweigert ohne Auth den Start. Das ist kein
Schönheitsfehler, sondern der häufigste Abbruchgrund.

---

## 5. OpenClaw anbinden

### 5a. Prüfen, was das Skript eingetragen hat

```bash
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.openclaw/openclaw.json")
d = json.load(open(p))
s = d.get("mcp", {}).get("servers", {}).get("mnemo-cortex")
print(json.dumps(s, indent=1) if s else "FEHLT: mcp.servers.mnemo-cortex")
PY
```

Erwartung: ein Block mit `command`, `args`, `env` (`MNEMO_URL`,
`MNEMO_AGENT_ID`, `MNEMO_SHARE`).

`MNEMO_AGENT_ID` ist der Name des Gedächtnisses. `openclaw-shared` bedeutet:
alle Agenten dieses Hosts teilen es. Willst du Trennung, nutze pro Agent eine
eigene ID und `MNEMO_SHARE=separate`.

### 5b. Neu starten

Die MCP-Server werden nur beim Start geladen.

- Läuft dein Agent **in** dieser OpenClaw: Der Eigentümer sendet `/restart` im
  Chat. Du selbst startest den Gateway nicht neu, während du darin arbeitest.
- Hast du Shell-Zugriff auf den Host und keinen laufenden Chat: 
  `openclaw gateway restart` (oder den vollen Pfad). Achtung: das beendet
  laufende Sitzungen.

### 5c. Prüfen, dass die Tools da sind

In der nächsten Sitzung muss deine Tool-Liste diese Namen enthalten (Präfix je
nach Host, z. B. `mnemo-cortex__mnemo_recall`):

`mnemo_recall`, `mnemo_save`, `mnemo_search`, `mnemo_share`,
`mnemo_recall_trajectory`, `mnemo_save_trajectory`, `mnemo_fact_save`,
`mnemo_fact_demote`

Fehlen sie: `openclaw.json` prüfen (JSON gültig?), Pfad in `args` existiert?
`node <pfad>/server.js` muss starten. Dann erneut neu starten.

---

## 6. Echter Funktionstest aus der Sitzung

Nicht nur curl — die Tools müssen aus dem Agenten heraus funktionieren.

**Test 1 — Erinnern (lesend):**

Rufe `mnemo_recall` auf mit `query: "Mnemo Cortex Langzeitgedächtnis"`,
`max_results: 3`.

Erwartung: Treffer mit `relevance`, `category`, `source`, Alter. Oder
`No memories found.` bei einer frischen Installation — das ist **ok**, solange
Test 2 funktioniert.

**Test 2 — Speichern und wiederfinden:**

Rufe `mnemo_save` auf mit:

```
summary: "Installations-Selftest: Mnemo Cortex ist auf diesem Host eingebaut und antwortet."
key_facts: ["selftest_marker=MNEMO-OK-<datum>"]
source: "tool"
category: "session_log"
```

Erwartung: Antwort mit `memory_id`, `session`, `agent`, `category_used`.

Dann `mnemo_recall` mit `query: "MNEMO-OK-<datum>"` und
`exclude_categories: []`.

Erwartung: genau dieser Treffer. Kommt er nicht, ist das Embedding-Modell nicht
aktiv → `docs/FEHLERBILDER.md`.

**Test 3 — native Memory unberührt:**

`memory_search` mit irgendeinem Begriff aus dem Workspace.

Erwartung: funktioniert wie vorher. Mnemo ersetzt die native Schicht nicht.

---

## 7. Arbeitsregeln aktivieren

Ohne Regeln speichert der Agent entweder nichts oder Müll. Kopiere den Inhalt
von [templates/AGENTS-memory-block.md](templates/AGENTS-memory-block.md) in die
`AGENTS.md` deines OpenClaw-Workspace (Abschnitt `## Memory` ersetzen oder
ergänzen).

Kurzfassung, die du selbst ab jetzt befolgst:

- Vor Fragen zu früherer Arbeit: `memory_search`, dann bei älteren oder
  agentenübergreifenden Fakten `mnemo_recall`/`mnemo_search`.
- Vor wiederkehrenden Aufgaben: `mnemo_recall_trajectory`.
- Speichern nach Salienz: Entscheidungen, verifizierte Fakten, gelöste
  nicht-triviale Probleme. Kein Chat-Protokoll, keine Logs.
- `source: "user"` nur, wenn der Mensch es gesagt hat; `"tool"` bei
  deterministischem Tool-Output; sonst `"inferred"`.
- `stale_warning` ernst nehmen: IPs, Ports, Prozessstände vor dem Handeln live
  prüfen.
- Nach guter nicht-trivialer Arbeit: `mnemo_save_trajectory` mit Schritten,
  Ergebnis und ehrlicher 1–5-Bewertung.

---

## 8. Abnahmeprotokoll

Melde dem Menschen genau diese Punkte, jeweils mit Ergebnis:

```
[ ] Mnemo-Dienst: systemctl --user is-active mnemo-cortex  -> active
[ ] Health: curl 127.0.0.1:50001/health                     -> status ok, v4.14.0
[ ] Bind: ss -ltn | grep 50001                              -> 127.0.0.1:50001 (nicht 0.0.0.0)
[ ] verify.sh                                               -> alles gruen
[ ] MCP-Block in openclaw.json                              -> vorhanden
[ ] Gateway neu gestartet                                   -> ja/nein
[ ] Tools sichtbar                                          -> welche Namen
[ ] Save->Recall aus der Sitzung                            -> memory_id + Treffer
[ ] memory_search nativ                                     -> funktioniert
[ ] AGENTS.md-Regeln eingetragen                            -> ja/nein
```

Fehlschläge nicht beschönigen. Ein nicht verifizierter Punkt ist ein offener
Punkt.

---

## 9. Was du den Menschen fragen darfst (und was nicht)

**Fragen, wenn zutreffend:**

1. „Ollama ist nicht installiert. Soll ich es installieren, oder machst du das?“
2. „Welches Reasoner-Modell soll ich nutzen: `qwen3.5:cloud` (Cloud) oder ein
   lokales Modell?“
3. „Soll das Gedächtnis von allen Agenten geteilt werden
   (`openclaw-shared`, `MNEMO_SHARE=always`) oder jeder Agent getrennt?“

**Nicht fragen, selbst prüfen:** Pfade, Versionen, Ports, ob OpenClaw läuft, wo
die Config liegt, ob Node/Python da ist.

**Nie ohne Auftrag:** Ports nach außen öffnen, Firewall ändern, Gateway
deinstallieren, `~/.mnemo-cortex` löschen, Secrets in Erinnerungen schreiben.

---

## 10. Wenn du keine Shell hast

Dann kannst du nicht installieren. Gib dem Menschen diese Zeilen:

```
Repository: https://github.com/erforschtbot-cmyk/mnemo-memory-openclaw
Darin: START-HERE.md (Anleitung), install.sh (Ein-Kommando-Installation)
Voraussetzungen: Linux + systemd, Python 3.10+, Node 18+, Ollama mit
nomic-embed-text und einem Reasoner-Modell.
```

Und bitte ihn, dir danach die Ausgabe von `./install.sh` und `./verify.sh` zu
zeigen; dann prüfst du das Ergebnis und übernimmst die Arbeitsregeln aus
Abschnitt 7.

---

## 11. Reihenfolge zum Nachschlagen

```
1. whoami / openclaw --version        -> wo bin ich
2. Voraussetzungsblock               -> was fehlt
3. git clone                         -> Werkzeuge da
3.5 install.sh lesen + --explain     -> verstehen, was passiert
4. ./install.sh                      -> Dienst + Config + Test
5. openclaw.json prüfen              -> Block vorhanden
6. Gateway neu starten               -> MCP lädt
7. mnemo_save + mnemo_recall         -> wirklich funktionsfähig
8. AGENTS.md-Regeln                  -> Verhalten
9. Abnahmeprotokoll                  -> melden
```

Alles Weitere: [docs/WAS-PASSIERT-BEIM-INSTALL.md](docs/WAS-PASSIERT-BEIM-INSTALL.md),
[docs/HINTERGRUND.md](docs/HINTERGRUND.md),
[docs/BETRIEB.md](docs/BETRIEB.md), [docs/FEHLERBILDER.md](docs/FEHLERBILDER.md).
