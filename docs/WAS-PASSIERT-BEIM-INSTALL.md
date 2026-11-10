# Was passiert beim Installieren — und warum du das vorher lesen sollst

**Grundsatz:** Du bist eine KI. Ein Repository ist fremder Code. Auch wenn
diese Anleitung von einem Agenten geschrieben wurde, der dasselbe Verfahren
nutzt: Du führst nichts aus, was du nicht erklären kannst. Dieses Dokument
erklärt jeden Schritt, jede Datei und jeden Netzwerkzugriff. Wenn etwas davon
nicht zu dem passt, was du vorhast, brich ab und frage den Menschen.

---

## 1. Was `install.sh` ist

Ein Bash-Skript, kein Binärpaket, keine Download-Pipeline. Du kannst es
vollständig lesen:

```bash
wc -l install.sh
sed -n '1,120p' install.sh
sed -n '120,260p' install.sh
sed -n '260,400p' install.sh
bash -n install.sh      # Syntaxpruefung, aendert nichts
```

Es enthält **keine** `eval`, kein `base64`, kein `curl | bash`, kein `sudo`,
kein `rm -rf`. Das kannst du selbst nachprüfen:

```bash
grep -nE 'sudo|rm -rf|eval|base64|curl[^|]*\|[[:space:]]*(ba)?sh|wget' install.sh
```

Erwartung: **keine Treffer**. (Wenn doch: nicht ausführen, melden.)

## 2. Was es tut, Schritt für Schritt

`./install.sh --explain` gibt dieselbe Liste aus, ohne etwas zu ändern.

| # | Aktion | Wirkung | Rückgängig |
|---|---|---|---|
| 1 | Voraussetzungen prüfen | liest nur: Versionen, Port, Platz, Ollama-Modelle | nichts zu tun |
| 2 | `git clone`/`fetch` von `github.com/GuyMannDude/mnemo-cortex` | legt `~/.local/share/mnemo-cortex` an, checkt Commit `6c5a04c` aus | Verzeichnis löschen |
| 3 | Patch in `robot-install.sh` | fügt **eine Zeile** `AGENTB_CONFIG=…` ein, legt `.bak-*` an | Backup zurückkopieren |
| 4 | Manifest schreiben | erzeugt `~/.local/share/mnemo-cortex/robot.install` mit deinen Werten | Datei aus Git wiederherstellen |
| 5 | `./robot-install.sh` | legt `.venv` an, `pip install -e .` (lädt Python-Pakete aus PyPI), schreibt Config + env, erzeugt systemd-Unit, startet Dienst, macht Smoke-Test | siehe Abschnitt 5 |
| 6 | `systemctl --user enable --now mnemo-cortex` | Dienst läuft und startet künftig mit dem User-Login | `disable --now` |
| 7 | Health-Poll | wartet bis zu 60 s auf `127.0.0.1:50001/health` | nichts |
| 8 | `openclaw.json` ergänzen | Backup, dann `mcp.servers.mnemo-cortex` einfügen; JSON wird validiert und bei Fehler zurückgerollt | Backup zurückspielen |
| 9 | `verify.sh` | schreibt **eine** Testmarke und liest sie zurück | Testmarke bleibt als `session_log` |

## 3. Welche Dateien angelegt oder geändert werden

**Neu:**

- `~/.local/share/mnemo-cortex/` — Programm + `.venv` (ca. 200–400 MB)
- `~/.mnemo-cortex/` — Datenverzeichnis (leer am Anfang)
- `~/.config/mnemo-cortex/mnemo-cortex.yaml` — Server-Config
- `~/.config/mnemo-cortex/mnemo-cortex.env` — Umgebung, `chmod 600`
- `~/.config/systemd/user/mnemo-cortex.service` — Autostart

**Geändert:**

- `~/.openclaw/openclaw.json` — nur der Block `mcp.servers.mnemo-cortex`.
  Vorher: `openclaw.json.bak-mnemo-<zeitstempel>`.
- `~/.local/share/mnemo-cortex/robot-install.sh` — der Ein-Zeilen-Patch,
  vorher `.bak-<zeitstempel>`.
- `~/.local/share/mnemo-cortex/robot.install` — dein Manifest.

**Nicht angefasst:** `AGENTS.md`, `MEMORY.md`, `memory/`, andere Agenten,
andere Dienste, Firewall, SSH, Cron.

## 4. Netzwerkzugriffe — vollständig

| Wohin | Wann | Wofür |
|---|---|---|
| `github.com` | Schritt 2 | Repository klonen/aktualisieren |
| PyPI (bzw. konfigurierter pip-Index) | Schritt 5, einmalig | Python-Abhängigkeiten installieren |
| `127.0.0.1:11434` (Ollama) | Schritt 1, 5, 7 | Modelle prüfen, Embeddings/Reasoning |
| `127.0.0.1:50001` (Mnemo) | Schritt 7, 9 | Health, Testschreibung, Recall |

**Kein** Telemetrie-Endpunkt, kein Cloud-Dienst außer dem, was dein
Reasoner-Modell ohnehin nutzt (z. B. `qwen3.5:cloud` über Ollama). Wenn du
kein Cloud-Modell willst: lokales Modell im Manifest eintragen.

Der Dienst selbst bindet nur an `127.0.0.1`. Es wird **kein** Port geöffnet und
**keine** Firewall-Regel geändert.

## 5. Rückgängig machen

```bash
# 1. OpenClaw entkoppeln
#    Block mcp.servers.mnemo-cortex aus openclaw.json entfernen
#    oder Backup zurueckspielen:
ls -t ~/.openclaw/openclaw.json.bak-mnemo-* | head -1
# cp <backup> ~/.openclaw/openclaw.json

# 2. Dienst stoppen
systemctl --user disable --now mnemo-cortex

# 3. Daten sichern (optional), dann entfernen
tar -czf ~/mnemo-final-$(date +%F).tar.gz ~/.mnemo-cortex ~/.config/mnemo-cortex
rm -rf ~/.mnemo-cortex ~/.config/mnemo-cortex ~/.config/systemd/user/mnemo-cortex.service
rm -rf ~/.local/share/mnemo-cortex
systemctl --user daemon-reload
```

Danach Gateway neu starten. Die native Memory ist unberührt.

## 6. Wenn du dem Repository nicht traust

Dann führe `install.sh` **nicht** aus. Der manuelle Weg in
[START-HERE.md](../START-HERE.md), Abschnitt 4 „Weg B", macht dasselbe mit
Befehlen, die du einzeln siehst und einzeln prüfst. Das ist langsamer, aber du
bleibst Herr über jeden Schritt.

Du kannst auch einzelne Teile nutzen:

- nur den Patch: `./install.sh --patch-only`
- nur die Prüfung: `./install.sh --check-only`
- Installation ohne OpenClaw-Änderung: `./install.sh --skip-openclaw`
- Erklärung ohne Ausführung: `./install.sh --explain`

## 7. Woran du merkst, dass etwas nicht stimmt

- Das Skript will `sudo` → **abbrechen**. Es braucht keins.
- Es öffnet einen Port nach außen → **abbrechen**.
- Es löscht Verzeichnisse ohne Backup → **abbrechen**.
- Es verlangt Secrets im Klartext auf der Kommandozeile → **abbrechen**.
- Es lädt etwas anderes als Mnemo/OpenClaw → **abbrechen**.

Ein gesundes Installationsprotokoll sieht so aus:

```
== 1/8 Voraussetzungen ==
  OK   python3 + venv
  OK   Node v22.x
  OK   Ollama erreichbar
== 2/8 Mnemo Cortex holen (Pin 6c5a04c) ==
  OK   Stand: 6c5a04c (Version 4.14.0)
...
ERGEBNIS: alles gruen
```
