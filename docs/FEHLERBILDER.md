# Fehlerbilder: Symptom → Ursache → Fix

Erst `./verify.sh` laufen lassen. Es sagt, welche Schicht betroffen ist.
Danach hier die passende Zeile suchen. Nichts davon erfordert Raten.

## Schnelltabelle

| Symptom | Wahrscheinliche Ursache | Fix |
|---|---|---|
| Dienst startet nicht, Log nennt `0.0.0.0` oder Auth | `AGENTB_CONFIG` fehlt in der env-Datei | `./install.sh --patch-only`, dann `daemon-reload` + restart |
| `health` ok, aber `reasoning.healthy=false` | Reasoner-Modell fehlt oder Cloud-Key fehlt | `ollama pull …`, env prüfen |
| Recall findet nichts, Selftest war grün | andere `MNEMO_AGENT_ID` beim Lesen | IDs angleichen |
| Recall liefert nur Zufallstreffer | Embedding-Modell fehlt oder wurde gewechselt | `ollama pull nomic-embed-text`, Dienst neu starten |
| MCP-Tools fehlen im Agenten | Gateway nicht neu gestartet, Pfad falsch | `openclaw.json` prüfen, einmal neu starten |
| `requestTimeoutMs` / Timeout beim ersten Aufruf | Modelle werden gerade geladen | Timeout 30000 lassen, zweiter Aufruf |
| Port 50001 belegt | anderer Prozess oder zweite Instanz | `ss -ltnp \| grep 50001`, Prozess identifizieren |
| Nach OpenClaw-Update weg | Config überschrieben | MCP-Block erneut eintragen, verifizieren |
| `verify.sh` FAIL bei „nicht auf 127.0.0.1 gebunden" | Dienst hat Fallback-Host genutzt | Patch + env prüfen (unten) |
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
"$HOME/.openclaw/mnemo-handover/install.sh" --patch-only
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

## 2. Health ok, aber Suche schlecht

```bash
curl -s 127.0.0.1:50001/health | python3 -m json.tool
```

- `embedding.healthy: false` → Modell fehlt: `ollama pull nomic-embed-text`,
  dann `systemctl --user restart mnemo-cortex`.
- `embedding.active` weicht vom erwarteten Modell ab → jemand hat die Config
  geändert. Der Index passt dann nicht mehr; nach dem Zurückstellen neu
  indexieren lassen (Mnemo macht das beim nächsten Schreibvorgang, sonst
  `verify.sh` als Schreibtest).
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

- Block fehlt → `./install.sh` erneut (trägt ihn idempotent ein).
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

`verify.sh` trennt beides. Schreibt der Save, aber der Recall findet die
Testmarke nicht, ist fast immer das Embedding-Modell die Ursache — oder der
Index wurde mit einem anderen Modell gebaut. `health.embedding` prüfen und
nach dem Fix den Dienst neu starten.

## 6. Nach einem OpenClaw-Update

Updates können `openclaw.json` neu schreiben. Danach:

```bash
./verify.sh          # prueft auch den MCP-Block
./install.sh --skip-openclaw   # nur falls Mnemo selbst betroffen ist
```

Der MCP-Block ist idempotent; erneutes Eintragen schadet nicht.

## 7. Was du bei Unsicherheit NICHT tust

- Keine `rm -rf` auf `~/.mnemo-cortex`, solange kein Backup existiert.
- Keine Firewall-Regel für Port 50001.
- Kein `0.0.0.0` „damit es von außen geht".
- Keine zweite Mnemo-Instanz auf demselben Port.
- Keine Modellnamen raten — `ollama list` fragen.
- Keine Änderungen an `openclaw.json` ohne Backup (install.sh macht eins).
