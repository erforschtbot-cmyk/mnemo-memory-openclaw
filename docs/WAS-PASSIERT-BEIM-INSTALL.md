# Was die Schritte ändern — und warum du sie vorher liest

**Grundsatz:** Dieses Repository enthält **kein Installationsskript**. Du
führst jeden Befehl selbst aus, nachdem du gelesen hast, was er tut. Das ist
langsamer, aber du bleibst Herr über jeden Eingriff. Nur der
Original-Installer von Mnemo Cortex (`robot-install.sh`) ist Fremdcode, der
automatisch mehrere Dinge tut — deshalb wird er hier besonders erklärt.

---

## 1. Annahmen, die die Anleitung macht

| Annahme | Wenn sie nicht stimmt |
|---|---|
| Linux mit systemd-User-Instanz | `systemd.enabled: false` im Manifest, Dienst selbst starten |
| OpenClaw-Config unter `~/.openclaw/openclaw.json` | Pfad beim Editieren anpassen |
| Config ist reines JSON | Block mit dem Editor eintragen, nicht automatisch umschreiben |
| Gateway und Mnemo laufen unter demselben Benutzer | Installation mit dem Gateway-Benutzer ausführen |
| `node` liegt unter dem Pfad aus `command -v node` | diesen Pfad im MCP-Block eintragen |
| Port 50001 ist frei | anderen Port wählen **und** `MNEMO_URL` anpassen |
| Ollama lokal auf `127.0.0.1:11434` | erst Ollama einrichten (Embeddings sind Pflicht) |
| Es läuft noch kein Mnemo | wenn doch: **nicht installieren**, nur MCP-Block (Fall B) |

Die vollständige Entscheidungsmatrix steht in
[KOMPATIBILITAET.md](KOMPATIBILITAET.md).

---

## 2. Die Schritte und ihre Wirkung

| Schritt | Befehl (Kurzform) | Wirkung | Rückgängig |
|---|---|---|---|
| 1 | `git clone …/mnemo-cortex` | legt `~/.local/share/mnemo-cortex` an | Verzeichnis löschen |
| 2 | `git checkout 6c5a04c` | pinnt auf Version 4.14.0 | anderer Checkout |
| 3 | `sed -i` Patch | fügt **eine Zeile** in `robot-install.sh`, Backup liegt daneben | `cp robot-install.sh.bak robot-install.sh` |
| 4 | Manifest kopieren/anpassen | schreibt `robot.install` im Programmverzeichnis | Datei aus Git wiederherstellen |
| 5 | `./robot-install.sh` | legt `.venv` an, `pip install -e .` (PyPI), schreibt Config + env, erzeugt systemd-Unit, startet Dienst, Smoke-Test | siehe Abschnitt 5 |
| 6 | `systemctl --user …` | prüft/startet den Dienst | `disable --now` |
| 7 | MCP-Block eintragen | ändert `~/.openclaw/openclaw.json` (mit Backup) | Backup zurückspielen |
| 8 | Gateway-Neustart | lädt die MCP-Tools | erneuter Neustart |
| 9 | Schreib-/Lesetest | **eine** Testmarke als `session_log` | bleibt als Verlaufseintrag |

Der Testeintrag ist der einzige Schreibvorgang in Erinnerungen, der durch diese
Anleitung entsteht.

---

## 3. Welche Dateien angelegt oder geändert werden

**Neu (durch `robot-install.sh`):**

- `~/.local/share/mnemo-cortex/` — Programm + `.venv` (ca. 200–400 MB)
- `~/.mnemo-cortex/` — Datenverzeichnis
- `~/.config/mnemo-cortex/mnemo-cortex.yaml` — Server-Config
- `~/.config/mnemo-cortex/mnemo-cortex.env` — Umgebung, `chmod 600`
- `~/.config/systemd/user/mnemo-cortex.service` — Autostart

**Geändert:**

- `~/.local/share/mnemo-cortex/robot-install.sh` — der Ein-Zeilen-Patch
  (Backup: `robot-install.sh.bak`)
- `~/.local/share/mnemo-cortex/robot.install` — dein Manifest
- `~/.openclaw/openclaw.json` — nur der Block `mcp.servers.mnemo-cortex`
  (Backup: `openclaw.json.bak-<zeitstempel>`)

**Nicht angefasst:** `AGENTS.md`, `MEMORY.md`, `memory/`, andere Agenten,
andere Dienste, Firewall, SSH, Cron.

---

## 4. Netzwerkzugriffe — vollständig

| Wohin | Wann | Wofür |
|---|---|---|
| `github.com/GuyMannDude/mnemo-cortex` | Schritt 1 | Quellcode klonen |
| PyPI (oder konfigurierter pip-Index) | Schritt 5, einmalig | Python-Abhängigkeiten |
| `127.0.0.1:11434` (Ollama) | Schritt 5 und Tests | Modelle, Embeddings, Reasoning |
| `127.0.0.1:50001` (Mnemo) | Tests | Health, Schreiben, Lesen |

**Kein** Telemetrie-Endpunkt. Kein Port wird nach außen geöffnet, keine
Firewall-Regel geändert. Wenn dein Reasoner ein Cloud-Modell ist
(`qwen3.5:cloud`), nutzt Ollama dafür das Internet — das ist eine Entscheidung
über das Modell, nicht über dieses Verfahren.

---

## 5. Rückgängig machen

```bash
# 1) OpenClaw entkoppeln: Block mcp.servers.mnemo-cortex entfernen
#    oder Backup zurueckspielen:
ls -t ~/.openclaw/openclaw.json.bak-* | head -1
# cp <backup> ~/.openclaw/openclaw.json

# 2) Dienst stoppen
systemctl --user disable --now mnemo-cortex

# 3) Daten sichern, dann entfernen
tar -czf ~/mnemo-final-$(date +%F).tar.gz ~/.mnemo-cortex ~/.config/mnemo-cortex
rm -rf ~/.mnemo-cortex ~/.config/mnemo-cortex
rm -f ~/.config/systemd/user/mnemo-cortex.service
systemctl --user daemon-reload

# 4) optional Programmverzeichnis
rm -rf ~/.local/share/mnemo-cortex
```

Danach Gateway neu starten. Die native Memory ist unberührt.

---

## 6. Woran du merkst, dass etwas nicht stimmt

- Ein Befehl verlangt `sudo`, obwohl es nicht nötig ist → prüfen, warum.
- Ein Schritt öffnet einen Port nach außen → **abbrechen**.
- Ein Befehl löscht Verzeichnisse ohne Backup → **abbrechen**.
- Der Installer will Secrets auf der Kommandozeile → **abbrechen**.
- Es wird etwas anderes als Mnemo/OpenClaw geladen → **abbrechen**.

Ein gesundes Protokoll sieht so aus:

```
$ ./robot-install.sh
{"ok": true, "steps": {"deps": {...}, "venv": {...}, "pip": {...},
 "config": {...}, "systemd": {...}, "smoke_test": {"ok": true}}, ...}
exit=0

$ systemctl --user is-active mnemo-cortex
active

$ curl -s 127.0.0.1:50001/health
{"status":"ok","version":"4.14.0", ... "embedding":{...,"healthy":true} ...}

$ ss -ltn | grep 50001
LISTEN 0 2048 127.0.0.1:50001 0.0.0.0:*
```
