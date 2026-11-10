# Betrieb: Tagesbetrieb, Wartung, Rückbau

## Täglicher Umgang

### Wann erinnern

| Situation | Werkzeug |
|---|---|
| Frage zu früherer Arbeit, Entscheidung, Person, Vorliebe | `memory_search` (nativ), bei älteren/agentenübergreifenden Fakten `mnemo_recall` |
| „Wie haben wir das letzte Mal …?" | `mnemo_recall_trajectory` |
| Exakter Wert (Version, Port, Zuständigkeit) | `mnemo_fact_*` bzw. gezielter Recall |
| Unsicher, ob ein Fakt noch gilt | Treffer lesen, `stale_warning` beachten, live prüfen |

### Wann speichern

Speichere **nach Salienz**, nicht nach Vollständigkeit:

- getroffene Entscheidung samt Begründung
- verifizierter Fakt (Tool-Output, Quellcode, direkte Aussage)
- gelöstes nicht-triviales Problem (Symptom → Ursache → Fix)
- stabile Vorliebe des Menschen
- bewährter Arbeitsablauf (Trajectory)

**Nicht** speichern: Chatverlauf, Zwischenschritte, Logzeilen, Secrets,
spekulative Vermutungen als `verified`.

### Qualität der Einträge

Ein guter Eintrag beantwortet: *Was*, *warum*, *wo gilt es*, *wie sicher*, *wann
gelernt*. Ein schlechter Eintrag ist ein Satz ohne Kontext („geht wieder").

## Backups

Zwei Pfade gehören zusammen:

```bash
tar -czf "$HOME/mnemo-backup-$(date +%F).tar.gz" \
  "$HOME/.mnemo-cortex" "$HOME/.config/mnemo-cortex"
```

Wiederherstellen: Dienst stoppen, beide Verzeichnisse zurückkopieren, Rechte
prüfen (`env`-Datei `600`), Dienst starten, Checks aus dem Abschnitt
„Gesundheitscheck“ unten.

Die native Memory (Workspace) sichert man separat über Git oder das
OpenClaw-Backup — sie ist nicht Teil von Mnemo.

## Update von Mnemo Cortex

```bash
cd ~/.local/share/mnemo-cortex
git pull --ff-only
# Patch pruefen und nur bei Bedarf neu setzen (eine Zeile)
grep -q 'AGENTB_CONFIG=\$CONFIG_FILE' robot-install.sh || \
  sed -i '/echo "# Mnemo Cortex env/a\    echo "AGENTB_CONFIG=$CONFIG_FILE"' robot-install.sh
./robot-install.sh                     # vorhandene Config bleibt
systemctl --user restart mnemo-cortex
# danach Gesundheitscheck unten
```

Vorher Backup (siehe oben). Nach dem Update prüfen, ob der Patch noch greift:

```bash
grep -c 'AGENTB_CONFIG' ~/.config/mnemo-cortex/mnemo-cortex.env   # muss 1 sein
```

## Mehrere Agenten auf einem Host

Ein Server, mehrere Tenants. In `openclaw.json` pro Agent ein eigener
MCP-Block mit eigener ID — oder ein gemeinsamer Block, dann teilen alle
Agenten desselben OpenClaw automatisch das Gedächtnis.

| Ziel | `MNEMO_AGENT_ID` | `MNEMO_SHARE` |
|---|---|---|
| Alle Agenten teilen alles | `openclaw-shared` (überall gleich) | `always` |
| Jeder Agent getrennt | pro Agent eigene ID | `separate` |
| Trennen, aber gezielt suchen | eigene IDs | `separate` + `mnemo_search` nach `mnemo_share` |

Wichtig: Die ID beim **Schreiben** und **Lesen** muss gleich sein. Der häufigste
„Ich finde nichts"-Fall ist eine abweichende ID.

## Mehrere Hosts

Mnemo ist ein Host-Dienst. Ein zweiter Host sollte **nicht** dieselbe Datenbank
über NFS/SMB einbinden. Zwei saubere Wege:

1. **Eigene Instanz pro Host** — einfachste Variante, Gedächtnisse bleiben
   getrennt. Für Austausch die relevanten Fakten manuell übertragen.
2. **Ein Server, zweiter Host als Client** — Verbindung nur über SSH-Tunnel:
   `ssh -N -L 50001:127.0.0.1:50001 user@server`, dann im Client
   `MNEMO_URL=http://127.0.0.1:50001`. Port nie öffentlich freigeben.

## Ressourcen

- Ruhezustand: ~60–120 MB RAM, kaum CPU.
- Erste Embeddings eines neuen Modells brauchen etwas Zeit; danach ist die
  Suche schnell.
- Das Reasoner-Modell wird nur für Zusammenfassungen/Preflight/Dreaming
  gebraucht. Cloud-Modelle verursachen dabei Kosten — Menge über
  `session_log`-Kategorie und Auto-Capture im Blick behalten.

## Rückbau

```bash
# 1) OpenClaw entkoppeln: Block mcp.servers.mnemo-cortex aus openclaw.json entfernen,
#    Gateway neu starten, pruefen dass keine mnemo_*-Tools mehr erscheinen.
# 2) Dienst stoppen und deaktivieren
systemctl --user disable --now mnemo-cortex
# 3) Daten sichern, dann entfernen
tar -czf "$HOME/mnemo-final-$(date +%F).tar.gz" "$HOME/.mnemo-cortex" "$HOME/.config/mnemo-cortex"
# rm -rf nur nach ausdruecklicher Bestaetigung des Eigentuemers
```

Die native Memory bleibt unberührt und funktioniert weiter.

## Gesundheitscheck (regelmäßig)

```bash
systemctl --user is-active mnemo-cortex
curl -s http://127.0.0.1:50001/health | python3 -m json.tool
ss -ltn | grep 50001                 # muss 127.0.0.1 zeigen
journalctl --user -u mnemo-cortex --since "-24h" | grep -iE 'error|traceback' | tail
```

Schreib-/Lesetest wie in [START-HERE.md](../START-HERE.md), Abschnitt 8: eine
Testmarke schreiben und zurücklesen. Erst wenn beides klappt, sind Embeddings,
Schreiben und Lesen zusammen belegt.
