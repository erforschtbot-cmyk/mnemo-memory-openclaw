# Kompatibilität: erst prüfen, dann installieren

**Jede OpenClaw ist anders aufgebaut.** Anderer Benutzer, andere
Installationsart, anderer Dienstmanager, andere Config, andere Agenten, andere
Modelle, manchmal Container oder ein Gateway auf einem anderen Host.

Deshalb gilt: **Bevor du etwas installierst, stellst du den Ist-Zustand fest
und entscheidest, ob der Eingriff hier problemlos ist.** Wenn du das nicht
beurteilen kannst, installierst du nicht.

Dieses Repository automatisiert das nicht. Du führst die Prüfbefehle selbst
aus und liest die Ausgaben.

---

## 0. Der wichtigste Fall zuerst: Mnemo läuft schon

```bash
curl -s --max-time 3 http://127.0.0.1:50001/health
ls -la "$HOME/.config/mnemo-cortex" 2>/dev/null
systemctl --user is-active mnemo-cortex 2>/dev/null
ss -ltn | grep 50001
```

**Wenn irgendetwas davon existiert oder antwortet:**

- **Nicht installieren.** Kein `git clone` in dasselbe Verzeichnis, kein
  `robot-install.sh`, kein Patch, kein Dienst-Neustart.
- Prüfe, unter welcher **Agent-ID** die vorhandenen Erinnerungen liegen:
  ```bash
  python3 - <<'PY'
  import json, os
  p = os.path.expanduser("~/.openclaw/openclaw.json")
  d = json.load(open(p))
  s = (d.get("mcp") or {}).get("servers", {}).get("mnemo-cortex")
  print(json.dumps(s, indent=1) if s else "kein MCP-Block vorhanden")
  PY
  ```
- Fehlt der MCP-Block, trage ihn mit **dieser** ID ein (START-HERE,
  Abschnitt 9, Fall B). Alles andere bleibt unangetastet.
- Ein `robot-install.sh`-Lauf würde Config, systemd-Unit und Tenant
  überschreiben. Erinnerungen unter einem anderen Tenant wären danach nicht
  mehr sichtbar.
- Zeigt `ss -ltn | grep 50001` den Dienst auf `0.0.0.0`, ist das ein
  Sicherheitsbefund — aber **kein Grund für eine Neuinstallation**. Ursache
  kann YAML, env **oder die systemd-Unit** sein; der gezielte Fix steht in
  [FEHLERBILDER.md](FEHLERBILDER.md), Abschnitt 1b.

---

## 1. Die zwölf Prüfpunkte

| # | Frage | Befehl | Warum wichtig |
|---|---|---|---|
| 1 | Welche OpenClaw-Version und Installationsart? | `openclaw --version`, `command -v openclaw`, `npm ls -g openclaw` | Config-Schema und MCP-Unterstützung unterscheiden sich |
| 2 | Wie wird OpenClaw gestartet? | `systemctl --user status \| head -3`, `systemctl status openclaw`, `docker ps` | Mnemo braucht einen Dienst; ohne systemd kein Autostart |
| 3 | Ist die Config reines JSON? | `python3 -c "import json;json.load(open('$HOME/.openclaw/openclaw.json'))"` | Bei JSON5/Kommentaren nicht automatisch umschreiben |
| 4 | Welche MCP-Server laufen schon? | Config lesen (siehe unten) | Namenskollisionen, doppelte Tools |
| 5 | Welcher Memory-Provider ist aktiv? | Config lesen | Ein Wechsel kann einen Index-Neubau erzwingen |
| 6 | Wie viele Agenten und Workspaces? | `openclaw agents list` oder Config | Entscheidet die Tenant-Strategie |
| 7 | Läuft der Agent auf diesem Host? | `openclaw gateway status` | Die Bridge muss dort laufen, wo der Agent läuft |
| 8 | Unter welchem Benutzer läuft der Gateway? | `ps -o user= -C node \| sort -u` | Mnemo-Unit und Daten müssen diesem Benutzer gehören |
| 9 | Ist Port 50001 frei und bleibt loopback? | `ss -ltn \| grep 50001` | Kein Konflikt, keine öffentliche Bindung |
| 10 | Ressourcen? | `free -m`, `df -h ~`, `ollama ps` | Embeddings/Reasoner brauchen RAM |
| 11 | Wie werden Updates gefahren? | vorhandene Skripte/Docs | Patch und Pin nach Updates erneut prüfen |
| 12 | Gibt es Backup und Rückweg? | Backup-Verzeichnis, Git, Snapshots | Ohne Rückweg keine Installation |

Config-Details in einem Rutsch:

```bash
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.openclaw/openclaw.json")
d = json.load(open(p))
print("Agenten:", list((d.get("agents") or {}).get("entries") or {}))
print("MCP-Server:", list((d.get("mcp") or {}).get("servers") or {}))
print("memory:", json.dumps(d.get("memory")))
PY
```

---

## 2. Entscheidungsmatrix

**Grün — installieren:**

- Linux mit systemd-User-Instanz (oder Dienst bewusst manuell starten)
- OpenClaw-Config valides JSON
- Port 50001 frei
- Benutzer = Gateway-Benutzer
- Ollama erreichbar, `nomic-embed-text` vorhanden
- ≥ 500 MB Platte, genug RAM
- Backup der Config möglich

**Gelb — installieren, aber anpassen:**

| Situation | Anpassung |
|---|---|
| Config mit Kommentaren/JSON5 | Block mit dem Editor eintragen, Datei mit dem hosteigenen Werkzeug validieren |
| Node nicht `/usr/bin/node` (nvm/fnm) | echten Pfad aus `command -v node` im MCP-Block eintragen |
| Anderer Port nötig | `service.port` im Manifest **und** `MNEMO_URL` im MCP-Block anpassen |
| Kein systemd (Container) | `systemd.enabled: false` im Manifest, Dienst über Supervisor starten |
| Mehrere Agenten, getrennte Gedächtnisse | pro Agent eigene ID, `MNEMO_SHARE=separate` |
| Kein Cloud-Modell erlaubt | lokales Reasoner-Modell im Manifest, z. B. `qwen3:8b` |
| Gateway läuft als anderer Benutzer | Installation mit genau diesem Benutzer |

**Rot — nicht installieren:**

- **Mnemo läuft hier schon** (Abschnitt 0) → nicht neu installieren.
- OpenClaw in einem **flüchtigen Container** ohne persistentes Volume.
- Der Gateway wird **von jemand anderem verwaltet**.
- **Kein Ollama und keine Erlaubnis**, es zu installieren.
- **Port 50001 gehört einem unbekannten Dienst.**
- **Kein Backup/Rollback** der OpenClaw-Config.
- Du hast **keinen Shell-Zugriff** → nur die Anleitung weitergeben.

---

## 3. Was du selbst prüfen musst

Automatisch prüfbar sind: Versionen, Port, Platz, Ollama-Modelle, Existenz von
Config/Unit/Health.

Nicht automatisch beurteilbar:

- ob der Gateway in einem Container oder auf einem anderen Host läuft
- ob ein fremder Administrator die Instanz verwaltet
- ob ein bestehender Memory-Provider bewusst gewählt wurde
- ob das Reasoner-Modell Kosten verursacht, die du nicht auslösen darfst
- ob ein Update-Regime existiert, das den Patch später überschreibt

---

## 4. Nach der Installation prüfen

```bash
systemctl --user is-active mnemo-cortex
curl -s http://127.0.0.1:50001/health | python3 -m json.tool
ss -ltn | grep 50001          # muss 127.0.0.1 zeigen
curl -s -X POST http://127.0.0.1:50001/context \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"selftest","agent_id":"<dein-tenant>","max_results":3}'
```

Danach in der Sitzung: `mnemo_save` → `mnemo_recall` → Treffer.

Nach jedem OpenClaw-Update erneut prüfen, weil die Config neu geschrieben
werden kann.

---

## 5. Wenn du unsicher bist

Installiere nicht auf Verdacht. Melde:

- was du vorgefunden hast (Version, Dienstmodell, Config-Format, Ports)
- was die Schritte ändern würden (siehe
  [WAS-PASSIERT-BEIM-INSTALL.md](WAS-PASSIERT-BEIM-INSTALL.md))
- welche Punkte du nicht beurteilen kannst
- was du empfiehlst
