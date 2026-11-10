#!/usr/bin/env bash
# selftest.sh — prueft die Logik von install.sh, ohne das System zu veraendern.
# Laeuft komplett in einem temporaeren Verzeichnis, liest keine echte Config.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok(){ printf '  OK   %s\n' "$*"; }
bad(){ printf '  FAIL %s\n' "$*"; fails=1; }

echo "== Syntax =="
bash -n "$HERE/install.sh" && ok "install.sh" || bad "install.sh"
bash -n "$HERE/verify.sh" && ok "verify.sh" || bad "verify.sh"

echo "== Keine gefaehrlichen Muster =="
if grep -nE 'sudo|rm -rf|eval|base64|curl[^|]*\|[[:space:]]*(ba)?sh|wget' "$HERE/install.sh"; then
  bad "gefaehrliches Muster in install.sh"
else
  ok "keine Treffer"
fi

echo "== Manifest-Erzeugung =="
mkdir -p "$T/mnemo"
cp "$HERE/templates/robot.install" "$T/mnemo/robot.install"
(
  set +e
  source "$HERE/install.sh"
  MNEMO_DIR="$T/mnemo"; MNEMO_REASON_MODEL="qwen3:8b"; MNEMO_EMBED_MODEL="nomic-embed-text"
  MNEMO_PORT=50123; MNEMO_AGENT_ID="test-agent"
  step(){ :; }; ok(){ :; }; warn(){ :; }; die(){ exit 1; }
  write_manifest
)
python3 - "$T/mnemo/robot.install" <<'PY'
import json,re,sys
raw=open(sys.argv[1]).read()
d=json.loads("\n".join(re.sub(r"^\s*//.*$","",l) for l in raw.splitlines()))
assert d["service"]["port"]==50123
assert d["service"]["host"]=="127.0.0.1"
assert d["reasoning"]["model"]=="qwen3:8b"
assert d["embedding"]["model"]=="nomic-embed-text"
assert d["smoke_test"]["agent_id"]=="test-agent"
print("  OK   Manifest ersetzt Port, Modelle, Agent-ID; host bleibt loopback")
PY

echo "== Config-Merge =="
cat > "$T/openclaw.json" <<'JSON'
{
  "agents": { "defaults": { "model": { "primary": "ollama/x:cloud" } } },
  "memory": { "search": { "provider": "local" } }
}
JSON
(
  set +e
  source "$HERE/install.sh"
  OPENCLAW_CONFIG="$T/openclaw.json"; MNEMO_DIR="/tmp/mnemo-test"
  MNEMO_PORT=50123; MNEMO_AGENT_ID="test-agent"; MNEMO_SHARE="separate"; WITH_NATIVE_LOCAL=0
  step(){ :; }; ok(){ :; }; warn(){ :; }; die(){ exit 1; }
  merge_openclaw_config
)
python3 - "$T/openclaw.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
b=d["mcp"]["servers"]["mnemo-cortex"]
assert b["env"]["MNEMO_AGENT_ID"]=="test-agent"
assert b["env"]["MNEMO_SHARE"]=="separate"
assert b["args"][0].endswith("integrations/mcp-bridge/server.js")
assert d["agents"]["defaults"]["model"]["primary"]=="ollama/x:cloud"
assert d["memory"]["search"]["provider"]=="local"
print("  OK   Block eingetragen, bestehende Schluessel erhalten")
PY

echo "== Backup =="
ls "$T"/openclaw.json.bak-mnemo-* >/dev/null 2>&1 && echo "  OK   Backup angelegt" || bad "kein Backup"

echo
[ "$fails" = 0 ] && echo "SELFTEST: alles gruen" || { echo "SELFTEST: Fehler"; exit 1; }
