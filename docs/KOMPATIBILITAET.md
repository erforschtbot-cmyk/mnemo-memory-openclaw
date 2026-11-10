# Kompatibilität: erst prüfen, dann installieren

**Jede OpenClaw ist anders aufgebaut.** Anderer Benutzer, andere
Installationsart, anderer Dienstmanager, andere Config, andere Agenten, andere
Modelle, manchmal Container oder ein Gateway auf einem anderen Host. Dieses
Verfahren greift in das laufende System ein: es startet einen Dienst, belegt
einen Port und ergänzt die OpenClaw-Config. Deshalb gilt:

> **Bevor du irgendetwas installierst, stellst du den Ist-Zustand fest und
> entscheidest, ob die Installation hier problemlos möglich ist. Wenn du das
> nicht beurteilen kannst, installierst du nicht.**

`./install.sh --check-only` prüft einen Teil davon automatisch und ändert
nichts. Die Punkte, die es **nicht** erkennen kann, stehen unten mit Befehl.

---

## 1. Die zwölf Prüfpunkte

| # | Frage | Befehl | Warum wichtig |
|---|---|---|---|
| 1 | Welche OpenClaw-Version und Installationsart? | `openclaw --version`, `command -v openclaw`, `npm ls -g openclaw` | Config-Schema und MCP-Unterstützung unterscheiden sich zwischen Versionen |
| 2 | Wie wird OpenClaw gestartet? | `systemctl --user status \| head -3`, `systemctl status openclaw`, `docker ps` | Mnemo braucht einen eigenen Dienst; ohne systemd kein Autostart |
| 3 | Ist die Config reines JSON? | `python3 -c "import json;json.load(open('$HOME/.openclaw/openclaw.json'))"` | Bei Kommentaren/JSON5 bricht der automatische Merge ab (mit Hinweis) |
| 4 | Welche MCP-Server laufen schon? | `python3 -c "import json;print(list(json.load(open('$HOME/.openclaw/openclaw.json')).get('mcp',{}).get('servers',{})))"` | Namenskollisionen, doppelte Tools, Konflikte |
| 5 | Welcher Memory-Provider ist aktiv? | `python3 -c "import json;print(json.load(open('$HOME/.openclaw/openclaw.json')).get('memory'))"` | Ein Wechsel kann einen Index-Neubau erzwingen; nicht stillschweigend ändern |
| 6 | Wie viele Agenten und Workspaces? | `openclaw agents list 2>/dev/null` oder Config lesen | Entscheidet Tenant-Strategie (`shared` vs. getrennt) |
| 7 | Läuft der Agent auf diesem Host oder remote? | `openclaw gateway status`, Node-/Tailscale-Konfiguration | Die Bridge muss dort laufen, wo der Agent läuft, und Mnemo dort erreichbar sein |
| 8 | Unter welchem Benutzer läuft der Gateway? | `ps -o user= -C node \| sort -u`, `systemctl --user show -p User` | Mnemo-Unit und Daten müssen demselben Benutzer gehören |
| 9 | Ist Port 50001 frei und bleibt loopback? | `ss -ltn \| grep 50001` | Kein Konflikt, keine öffentliche Bindung |
| 10 | Ressourcen? | `free -m`, `df -h ~`, `ollama ps` | Embeddings/Reasoner brauchen RAM; Ollama wird geteilt |
| 11 | Wie werden Updates gefahren? | vorhandene Skripte/Docs, `openclaw --version` | Der Mnemo-Pin und der Ein-Zeilen-Patch müssen nach Updates erneut geprüft werden |
| 12 | Gibt es Backup und Rückweg? | Backup-Verzeichnis, Git, Snapshots | Ohne Rückweg keine Installation |

---

## 2. Entscheidungsmatrix

**Grün — installieren:**

- Linux mit systemd-User-Instanz oder bewusst `--no-service`
- OpenClaw-Config ist valides JSON (oder du trägst den Block manuell ein)
- Port 50001 frei, Benutzer = Gateway-Benutzer
- Ollama erreichbar, Embedding-Modell vorhanden
- mindestens ~500 MB Platte und genug RAM für das Embedding-Modell
- du kannst `openclaw.json` zurückspielen (Backup vorhanden)

**Gelb — installieren, aber anpassen:**

| Situation | Anpassung |
|---|---|
| Config mit Kommentaren/JSON5 | `install.sh --skip-openclaw`, Block manuell eintragen |
| Node nicht unter `/usr/bin/node` (nvm, fnm) | `NODE_BIN=$(command -v node) ./install.sh` |
| Anderer Port gewünscht/belegt | `MNEMO_PORT=50002 ./install.sh` |
| Kein systemd (Container) | `--no-service`, Start über Container-Entrypoint/Supervisor |
| Mehrere Agenten, getrennte Gedächtnisse | pro Agent eigene `MNEMO_AGENT_ID`, `MNEMO_SHARE=separate` |
| Kein Cloud-Modell erlaubt | lokales Reasoner-Modell im Manifest, z. B. `qwen3:8b` |
| Gateway läuft als anderer Benutzer | Installation mit genau diesem Benutzer ausführen |

**Rot — nicht installieren, erst klären:**

- OpenClaw läuft in einem **flüchtigen Container** ohne persistentes Volume →
  Daten und Dienst wären nach dem Neustart weg.
- Der Gateway wird von **jemand anderem** verwaltet (Managed Hosting, Firma,
  fremde Instanz) → nicht ohne dessen Freigabe in die Config schreiben.
- **Kein Ollama und keine Erlaubnis**, es zu installieren → Embeddings fehlen,
  Recall wäre wertlos.
- **Port 50001 gehört einem unbekannten Dienst** → nicht verdrängen.
- **Weniger als ~500 MB frei** oder RAM dauerhaft am Limit → erst aufräumen.
- **Kein Backup/Rollback** der OpenClaw-Config → erst Backup, dann Installation.
- Du kannst Punkt 1–12 nicht prüfen, weil du keinen Shell-Zugriff hast → nur
  die Anleitung weitergeben, nicht selbst eingreifen.

---

## 3. Was der Installer automatisch erkennt

`./install.sh --check-only` und der Umgebungsbericht im normalen Lauf zeigen:

- Python/venv, Node-Version und Node-Pfad, Git, curl
- systemd-User-Instanz vorhanden oder nicht
- Ollama erreichbar, Embedding-Modell vorhanden, Reasoner vorhanden
- Port 50001 frei / durch Mnemo belegt / durch Fremdprozess belegt
- freier Platz
- OpenClaw-Version (falls CLI im PATH oder unter `~/.npm-global/bin`)
- ob die Config als JSON lesbar ist
- Anzahl Agenten, aktiver Memory-Provider, vorhandene MCP-Server
- ob `mnemo-cortex` bereits eingetragen ist

Was er **nicht** erkennt und du selbst beurteilen musst:

- ob der Gateway in einem Container oder auf einem anderen Host läuft
- ob ein fremder Administrator die Instanz verwaltet
- ob ein bestehender Memory-Provider bewusst gewählt wurde
- ob das Reasoner-Modell Kosten verursacht, die du nicht auslösen darfst
- ob ein Update-Regime existiert, das den Patch später überschreibt

---

## 4. Nach der Installation prüfen (nicht nur den Installer glauben)

```bash
systemctl --user status mnemo-cortex --no-pager | head -5
curl -s 127.0.0.1:50001/health | python3 -m json.tool
ss -ltn | grep 50001                 # muss 127.0.0.1 zeigen
./verify.sh
```

Danach in der Sitzung: `mnemo_save` → `mnemo_recall` → Treffer. Erst dann gilt
die Installation als erfolgreich.

Und nach dem nächsten OpenClaw-Update erneut:

```bash
./verify.sh
```

weil ein Update die `openclaw.json` neu schreiben kann.

---

## 5. Wenn du unsicher bist

Installiere nicht „auf Verdacht". Melde dem Menschen:

- was du vorgefunden hast (Version, Dienstmodell, Config-Format, Ports)
- was der Installer ändern würde (`./install.sh --explain`)
- welche Punkte du nicht beurteilen kannst
- und was du empfiehlst

Das ist kein Zögern, sondern genau die Sorgfalt, die ein Eingriff in ein
laufendes System verlangt.
