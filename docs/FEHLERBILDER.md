# Fehlerbilder: Symptom → Ursache → Fix

Erst die drei Ebenen prüfen: Dienst, Health/Bind, Schreib-/Lesetest. Die
Befehle stehen unten und in [START-HERE.md](../START-HERE.md), Abschnitt 8.
Danach hier die passende Zeile suchen. Nichts davon erfordert Raten.

## Schnelltabelle

| Symptom | Wahrscheinliche Ursache | Fix |
|---|---|---|
| Dienst startet nicht, Log nennt `0.0.0.0` oder Auth | `AGENTB_CONFIG` fehlt in der env-Datei | Patch setzen (unten, Abschnitt 1), dann `daemon-reload` + restart |
| `health` ok, aber `reasoning.healthy=false` | Reasoner-Modell fehlt oder Cloud-Key fehlt | `ollama pull …`, env prüfen |
| Recall findet nichts, Selftest war grün | andere `MNEMO_AGENT_ID` beim Lesen | IDs angleichen |
| Recall liefert nur Zufallstreffer | Embedding-Modell fehlt oder wurde gewechselt | `ollama pull nomic-embed-text`, Dienst neu starten |
| MCP-Tools fehlen im Agenten | Gateway nicht neu gestartet, Pfad falsch | `openclaw.json` prüfen, einmal neu starten |
| `requestTimeoutMs` / Timeout beim ersten Aufruf | Modelle werden gerade geladen | Timeout 30000 lassen, zweiter Aufruf |
| Port 50001 belegt | anderer Prozess oder zweite Instanz | `ss -ltnp \| grep 50001`, Prozess identifizieren |
| Nach OpenClaw-Update weg | Config überschrieben | MCP-Block erneut eintragen, verifizieren |
| Bind-Prüfung FAIL bei „nicht auf 127.0.0.1 gebunden" | Dienst hat Fallback-Host genutzt | Patch + env prüfen (unten) |
| Alles grün, aber Agent „erinnert" nichts | Agent nutzt `memory_search` statt `mnemo_recall` | AGENTS.md-Regeln übernehmen |

---

## 1. Dienst startet nicht

```bash
systemctl --user status mnemo-cortex --no-pager | head -20
journalctl --user -u mnemo-cortex -n 80 --no-pager
```

Typische Meldungen und Bedeutung:

**`Refusing to start without auth on 0.0.0.0`** (oder ähnlich)
→ Die env-Datei enthält `AGENTB_CONFIG` nicht, der Dienst nimmt den
Fallback-Host. Prüfen:

```bash
grep AGENTB_CONFIG ~/.config/mnemo-cortex/mnemo-cortex.env   # muss vorhanden sein
```

Fehlt sie:

```bash
grep -q 'AGENTB_CONFIG=\$CONFIG_FILE' ~/.local/share/mnemo-cortex/robot-install.sh || \
  sed -i '/echo "# Mnemo Cortex env/a\    echo "AGENTB_CONFIG=$CONFIG_FILE"' ~/.local/share/mnemo-cortex/robot-install.sh
cd ~/.local/share/mnemo-cortex && ./robot-install.sh
systemctl --user daemon-reload
systemctl --user restart mnemo-cortex
```

**`config file not found`**
→ `AGENTB_CONFIG` zeigt auf einen falschen Pfad. In der env-Datei muss stehen:
`AGENTB_CONFIG=/home/<user>/.config/mnemo-cortex/mnemo-cortex.yaml`.

**`Address already in use`**
→ Port belegt. `ss -ltnp | grep 50001`. Läuft dort schon ein Mnemo, ist nichts
zu tun. Ist es ein anderer Prozess: nicht killen, erst den Eigentümer fragen.

**Python-/Modulfehler beim Start**
→ venv defekt. Neu installieren:

```bash
cd ~/.local/share/mnemo-cortex
rm -rf .venv        # nur nach Bestaetigung; Daten liegen woanders
./robot-install.sh
```

## 1b. Dienst lauscht auf 0.0.0.0

**Symptom:** `ss -ltn | grep 50001` zeigt `0.0.0.0:50001` oder `*:50001`.

**Bedeutung:** Der Dienst ist im gesamten LAN ohne Authentifizierung erreichbar.
Das ist kein Betriebsdetail, sondern eine offene Schnittstelle.

**Es gibt drei Ursachen. Prüfe sie in dieser Reihenfolge:**

1. **YAML:** `server.host` steht auf `0.0.0.0`.
2. **env:** `AGENTB_CONFIG` fehlt, der Dienst nimmt den Fallback-Host.
3. **systemd-Unit:** `ExecStart` wurde nachträglich von Hand auf `--host 0.0.0.0`
   geändert. Das ist die Ursache, die man übersieht, weil Manifest und YAML
   weiterhin `127.0.0.1` sagen — die Unit ist die dritte Quelle.

```bash
# 1) YAML
grep -n 'host:' ~/.config/mnemo-cortex/mnemo-cortex.yaml
# 2) env
grep -n 'AGENTB_CONFIG' ~/.config/mnemo-cortex/mnemo-cortex.env
# 3) Unit — entscheidend: was wird WIRKLICH gestartet?
systemctl --user cat mnemo-cortex | grep -n 'ExecStart'
systemctl --user show mnemo-cortex -p ExecStart --value
```

**Fix, je nach Befund:**

- YAML: `host: 127.0.0.1` setzen.
- env: `AGENTB_CONFIG=$HOME/.config/mnemo-cortex/mnemo-cortex.yaml` ergänzen
  (Datei bleibt `chmod 600`), nur nach Prüfung des Pfads.
- Unit: `--host 0.0.0.0` in der `ExecStart`-Zeile durch `--host 127.0.0.1`
  ersetzen. Die Datei liegt unter
  `~/.config/systemd/user/mnemo-cortex.service`. Vorher Backup:

```bash
cp -a ~/.config/systemd/user/mnemo-cortex.service ~/.config/systemd/user/mnemo-cortex.service.bak
# Editor: nur --host aendern, Rest unveraendert lassen
systemctl --user daemon-reload
systemctl --user restart mnemo-cortex
ss -ltn | grep 50001          # muss 127.0.0.1 zeigen
curl -s http://127.0.0.1:50001/health | head -c 120
```

**Vor dem Neustart prüfen, ob gerade jemand von außen verbunden ist:**

```bash
ss -tn state established '( sport = :50001 )'
```

Stehen dort fremde IPs, ist der Neustart ein Bruch für diese Clients — das ist
beabsichtigt (die offene Schnittstelle geht zu), muss aber angekündigt werden.

**Wichtig:** Nicht per `robot-install.sh` „reparieren“. Der Lauf würde die Unit
zwar aus dem Manifest neu bauen, aber auch Config, env und Tenant anfassen —
bei einer laufenden Installation ist das der falsche Weg (siehe
[KOMPATIBILITAET.md](KOMPATIBILITAET.md), Abschnitt 0).

Wenn der Dienst bewusst von anderen Hosts erreichbar sein soll: nicht über
`0.0.0.0` lösen, sondern über einen SSH-Tunnel oder eine authentifizierte
Reverse-Proxy-Regel. Ohne Auth gehört Mnemo nicht ins Netz.

## 2. Health ok, aber Suche schlecht

```bash
curl -s 127.0.0.1:50001/health | python3 -m json.tool
```

- `embedding.healthy: false` → Modell fehlt: `ollama pull nomic-embed-text`,
  dann `systemctl --user restart mnemo-cortex`.
- `embedding.active` weicht vom erwarteten Modell ab → jemand hat die Config
  geändert. Der Index passt dann nicht mehr; nach dem Zurückstellen neu
  indexieren lassen (Mnemo macht das beim nächsten Schreibvorgang; sonst
  Schreib-/Lesetest aus [START-HERE.md](../START-HERE.md), Abschnitt 8,
  wiederholen).
- `reasoning.failed_over: true` → Reasoner ausgefallen. Suche funktioniert
  weiter, Zusammenfassungen nicht. Modell/Key prüfen.

## 3. Recall findet nichts

Drei mögliche Ursachen, in dieser Reihenfolge prüfen:

1. **Falsche Agent-ID.** Schreiben und Lesen müssen dieselbe ID nutzen.
   ```bash
   curl -s -X POST 127.0.0.1:50001/context -H 'Content-Type: application/json' \
     -d '{"prompt":"selftest","agent_id":"openclaw-shared","max_results":3}'
   ```
   Mit einer anderen `agent_id` kommt nichts, obwohl Daten da sind.
2. **Kategorie gefiltert.** Standardmäßig wird `session_log` ausgeschlossen.
   Für den Test `"exclude_categories":[]` mitschicken.
3. **Kein Embedding.** `health.embedding.healthy` prüfen.

## 4. MCP-Tools fehlen

Der Agent sieht `mnemo_recall` usw. nicht:

```bash
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.openclaw/openclaw.json")
d = json.load(open(p))
print(json.dumps(d.get("mcp", {}).get("servers", {}).get("mnemo-cortex"), indent=1))
PY
```

- Block fehlt → Block aus `templates/openclaw-mcp.json` manuell eintragen
  (START-HERE, Abschnitt 9), Datei validieren, Backup nicht vergessen.
- Pfad in `args` existiert nicht → `ls -l <pfad>/server.js`.
- JSON ungültig → OpenClaw startet mit letzter bekannter Config; Fehler im
  Log. Backup zurückspielen: `ls ~/.openclaw/openclaw.json.bak-mnemo-*`.
- Alles korrekt, Tools fehlen weiter → Gateway wirklich neu gestartet?
  MCP-Server werden nur beim Start geladen.

Test ohne OpenClaw, ob die Bridge selbst startet:

```bash
cd ~/.local/share/mnemo-cortex/integrations/mcp-bridge
MNEMO_URL=http://127.0.0.1:50001 MNEMO_AGENT_ID=openclaw-shared timeout 3 node server.js
```

Erwartung: keine Fehlermeldung, Prozess wartet auf stdio (Exit 124 durch
`timeout` ist normal).

## 5. Schreiben klappt, Lesen nicht (oder umgekehrt)

Trenne die beiden Tests: einmal schreiben (`POST /writeback`), einmal lesen
(`POST /context`) — Befehle in [START-HERE.md](../START-HERE.md), Abschnitt 8.
Schreibt der Save, aber der Recall findet die
Testmarke nicht, ist fast immer das Embedding-Modell die Ursache — oder der
Index wurde mit einem anderen Modell gebaut. `health.embedding` prüfen und
nach dem Fix den Dienst neu starten.

## 6. Nach einem OpenClaw-Update

Updates können `openclaw.json` neu schreiben. Danach:

```bash
# Block pruefen
python3 - <<'PY'
import json, os
d = json.load(open(os.path.expanduser("~/.openclaw/openclaw.json")))
print((d.get("mcp") or {}).get("servers", {}).get("mnemo-cortex"))
PY
# Dienst pruefen
systemctl --user is-active mnemo-cortex
curl -s http://127.0.0.1:50001/health
```

Der MCP-Block ist idempotent; erneutes Eintragen schadet nicht.

## 7. Was du bei Unsicherheit NICHT tust

- Keine `rm -rf` auf `~/.mnemo-cortex`, solange kein Backup existiert.
- Keine Firewall-Regel für Port 50001.
- Kein `0.0.0.0` „damit es von außen geht".
- Keine zweite Mnemo-Instanz auf demselben Port.
- Keine Modellnamen raten — `ollama list` fragen.
- Keine Änderungen an `openclaw.json` ohne Backup (vorher `cp` mit Zeitstempel).
