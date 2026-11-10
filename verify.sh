#!/usr/bin/env bash
# verify.sh — prueft eine Mnemo-Cortex-Installation Ende-zu-Ende.
#
#   ./verify.sh                        Default: http://127.0.0.1:50001 / openclaw-shared
#   ./verify.sh http://127.0.0.1:50001 mein-agent
#
# Exit-Code 0 = alles gruen, 1 = mindestens ein Fehler.
set -uo pipefail

URL="${1:-http://127.0.0.1:50001}"
AGENT="${2:-${MNEMO_AGENT_ID:-openclaw-shared}}"
CONFIG="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"
fail=0

ok()  { printf '  OK   %s\n' "$*"; }
bad() { printf '  FAIL %s\n' "$*"; fail=1; }

echo "== 1/6 Dienst =="
if systemctl --user is-active --quiet mnemo-cortex 2>/dev/null; then
  ok "mnemo-cortex.service active"
else
  bad "Dienst nicht aktiv — systemctl --user status mnemo-cortex --no-pager"
fi

echo "== 2/6 Health =="
health=$(curl -s --max-time 5 "$URL/health" || true)
if printf '%s' "$health" | grep -q '"status":"ok"'; then
  ok "health: $(printf '%s' "$health" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("v"+d["version"], "embedding="+d["embedding"]["active"], "reasoning="+d["reasoning"]["active"])' 2>/dev/null)"
  printf '%s' "$health" | grep -q '"failed_over":false' || bad "ein Provider ist auf Fallback — Modell/Key pruefen"
else
  bad "health nicht ok: ${health:-keine Antwort} — journalctl --user -u mnemo-cortex -n 50 --no-pager"
fi

echo "== 3/6 Nur lokal erreichbar =="
if ss -ltn 2>/dev/null | grep -q "127.0.0.1:${URL##*:}"; then
  ok "lauscht auf 127.0.0.1"
elif ss -ltn 2>/dev/null | grep -q ":${URL##*:}"; then
  bad "nicht auf 127.0.0.1 gebunden — env-Datei AGENTB_CONFIG pruefen, docs/FEHLERBILDER.md"
else
  bad "kein Listener auf ${URL##*:}"
fi

echo "== 4/6 Recall (lesend) =="
rec=$(curl -s --max-time 20 -X POST "$URL/context" -H 'Content-Type: application/json' \
  -d "{\"prompt\":\"healthcheck selftest\",\"agent_id\":\"$AGENT\",\"max_results\":1}" || true)
if printf '%s' "$rec" | grep -q '"chunks"'; then
  ok "POST /context antwortet"
else
  bad "POST /context fehlerhaft: $(printf '%s' "$rec" | head -c 300)"
fi

echo "== 5/6 Save -> Recall (Testmarke) =="
mark="MNEMO-SELFTEST-$(date +%Y%m%d-%H%M%S)"
save=$(curl -s --max-time 30 -X POST "$URL/writeback" -H 'Content-Type: application/json' \
  -d "{\"session_id\":\"$AGENT-selftest\",\"summary\":\"Installations-Selftest $mark: Mnemo Cortex antwortet auf Schreiben und Lesen.\",\"key_facts\":[\"selftest_marker=$mark\"],\"projects_referenced\":[],\"decisions_made\":[],\"agent_id\":\"$AGENT\",\"source\":\"tool\",\"category\":\"session_log\"}" || true)
if printf '%s' "$save" | grep -q '"memory_id"'; then
  ok "gespeichert ($(printf '%s' "$save" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("memory_id","?"))' 2>/dev/null))"
else
  bad "writeback fehlerhaft: $(printf '%s' "$save" | head -c 300)"
fi
sleep 2
hit=$(curl -s --max-time 20 -X POST "$URL/context" -H 'Content-Type: application/json' \
  -d "{\"prompt\":\"$mark\",\"agent_id\":\"$AGENT\",\"max_results\":3,\"exclude_categories\":[]}" || true)
if printf '%s' "$hit" | grep -q "$mark"; then
  ok "Testmarke wiedergefunden"
else
  bad "Testmarke nicht wiedergefunden — Embedding-Modell/Index pruefen"
fi

echo "== 6/6 OpenClaw-Config =="
if [ -f "$CONFIG" ]; then
  if python3 - "$CONFIG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
s = d.get("mcp", {}).get("servers", {}).get("mnemo-cortex")
if not s:
    print("  FAIL mcp.servers.mnemo-cortex fehlt")
    sys.exit(1)
missing = [k for k in ("command", "args", "env") if not s.get(k)]
if missing:
    print("  FAIL Block unvollstaendig: " + ", ".join(missing))
    sys.exit(1)
print("  OK   mcp.servers.mnemo-cortex vorhanden")
PY
  then :; else fail=1; fi
else
  bad "keine Config unter $CONFIG"
fi

echo
if [ "$fail" = 0 ]; then
  echo "ERGEBNIS: alles gruen"
else
  echo "ERGEBNIS: Fehler vorhanden (siehe FAIL) — docs/FEHLERBILDER.md"
fi
exit "$fail"
