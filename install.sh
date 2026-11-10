#!/usr/bin/env bash
# install.sh — baut das Mnemo-Memory-Verfahren auf diesem Host ein.
#
#   ./install.sh                 alles: Voraussetzungen, Mnemo, Dienst, OpenClaw-Config, Test
#   ./install.sh --check-only    nur Voraussetzungen pruefen, nichts aendern
#   ./install.sh --patch-only    nur den Installer-Patch setzen (fuer den manuellen Weg)
#   ./install.sh --no-service    ohne systemd (Container/macOS), Dienst muss selbst gestartet werden
#   ./install.sh --skip-openclaw Mnemo installieren, openclaw.json nicht anfassen
#   ./install.sh --with-native-local  zusaetzlich memory.search.provider="local" setzen
#   ./install.sh --restart-gateway    am Ende OpenClaw neu starten (beendet Sitzungen!)
#
# Anpassbar per Umgebungsvariable:
#   MNEMO_AGENT_ID=openclaw-shared   MNEMO_SHARE=always   MNEMO_PORT=50001
#   MNEMO_DIR=~/.local/share/mnemo-cortex
#   OPENCLAW_CONFIG=~/.openclaw/openclaw.json
#   MNEMO_REASON_MODEL=qwen3.5:cloud  MNEMO_EMBED_MODEL=nomic-embed-text
#   MNEMO_PIN=6c5a04c
set -euo pipefail

MNEMO_AGENT_ID="${MNEMO_AGENT_ID:-openclaw-shared}"
MNEMO_SHARE="${MNEMO_SHARE:-always}"
MNEMO_PORT="${MNEMO_PORT:-50001}"
MNEMO_DIR="${MNEMO_DIR:-$HOME/.local/share/mnemo-cortex}"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"
MNEMO_REASON_MODEL="${MNEMO_REASON_MODEL:-qwen3.5:cloud}"
MNEMO_EMBED_MODEL="${MNEMO_EMBED_MODEL:-nomic-embed-text}"
MNEMO_PIN="${MNEMO_PIN:-6c5a04c}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CHECK_ONLY=0; PATCH_ONLY=0; NO_SERVICE=0; SKIP_OPENCLAW=0; WITH_NATIVE_LOCAL=0; RESTART_GATEWAY=0; EXPLAIN=0

usage() {
  cat <<'EOF'
install.sh — baut das Mnemo-Memory-Verfahren auf diesem Host ein.

  ./install.sh                 alles: Voraussetzungen, Mnemo, Dienst, OpenClaw-Config, Test
  ./install.sh --explain       zeigt jeden Schritt und jede Dateiaenderung, aendert nichts
  ./install.sh --check-only    nur Voraussetzungen pruefen, nichts aendern
  ./install.sh --patch-only    nur den Installer-Patch setzen (fuer den manuellen Weg)
  ./install.sh --no-service    ohne systemd (Container/macOS), Dienst muss selbst gestartet werden
  ./install.sh --skip-openclaw Mnemo installieren, openclaw.json nicht anfassen
  ./install.sh --with-native-local  zusaetzlich memory.search.provider="local" setzen
  ./install.sh --restart-gateway    am Ende OpenClaw neu starten (beendet Sitzungen!)

Anpassbar per Umgebungsvariable:
  MNEMO_AGENT_ID=openclaw-shared   MNEMO_SHARE=always   MNEMO_PORT=50001
  MNEMO_DIR=~/.local/share/mnemo-cortex
  OPENCLAW_CONFIG=~/.openclaw/openclaw.json
  MNEMO_REASON_MODEL=qwen3.5:cloud  MNEMO_EMBED_MODEL=nomic-embed-text
  MNEMO_PIN=6c5a04c
EOF
}

explain() {
  cat <<EOF
== Was dieses Skript tun WUERDE (nichts wurde geaendert) ==

Ziele:
  Programm:  $MNEMO_DIR          (git clone, Commit $MNEMO_PIN)
  Daten:     $HOME/.mnemo-cortex
  Config:    $HOME/.config/mnemo-cortex/{mnemo-cortex.yaml,mnemo-cortex.env}
  Dienst:    $HOME/.config/systemd/user/mnemo-cortex.service
  OpenClaw:  $OPENCLAW_CONFIG
  Tenant:    $MNEMO_AGENT_ID (share=$MNEMO_SHARE, port=$MNEMO_PORT)
  Modelle:   Embedding=$MNEMO_EMBED_MODEL  Reasoner=$MNEMO_REASON_MODEL

Schritte:
  1  Voraussetzungen lesen (Versionen, Port, Platz, Ollama-Modelle) — keine Aenderung
  2  git fetch/clone https://github.com/GuyMannDude/mnemo-cortex, checkout $MNEMO_PIN
  3  robot-install.sh patchen: eine Zeile AGENTB_CONFIG in die env-Datei (mit .bak)
  4  robot.install schreiben (Port, Tenant, Modelle)
  5  .venv anlegen, pip install -e . (PyPI), Config+env schreiben, systemd-Unit erzeugen
  6  systemctl --user enable --now mnemo-cortex
  7  bis 60 s auf http://127.0.0.1:$MNEMO_PORT/health warten
$( [ "$SKIP_OPENCLAW" = 1 ] && echo "  8  OpenClaw-Config: uebersprungen (--skip-openclaw)" || echo "  8  openclaw.json: Backup, dann mcp.servers.mnemo-cortex einfuegen (JSON validiert)" )
  9  verify.sh: eine Testmarke schreiben und zuruecklesen

Netzwerk: github.com (Code), PyPI (Python-Pakete), 127.0.0.1:11434 (Ollama),
          127.0.0.1:$MNEMO_PORT (Mnemo). Sonst nichts. Keine root-Rechte, kein Port nach aussen.

Nicht angefasst: AGENTS.md, MEMORY.md, memory/, andere Dienste, Firewall.
Rueckgaengig: docs/WAS-PASSIERT-BEIM-INSTALL.md, Abschnitt 5.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --explain) EXPLAIN=1 ;;
    --check-only) CHECK_ONLY=1 ;;
    --patch-only) PATCH_ONLY=1 ;;
    --no-service) NO_SERVICE=1 ;;
    --skip-openclaw) SKIP_OPENCLAW=1 ;;
    --with-native-local) WITH_NATIVE_LOCAL=1 ;;
    --restart-gateway) RESTART_GATEWAY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unbekannte Option: $arg (--help zeigt alles)" >&2; exit 2 ;;
  esac
done

ok()   { printf '  OK   %s\n' "$*"; }
warn() { printf '  WARN %s\n' "$*"; }
fail() { printf '  FAIL %s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }
die()  { printf '\nABBRUCH: %s\n' "$*" >&2; exit 1; }

# ── Patch: AGENTB_CONFIG in die env-Datei ────────────────────────────────
apply_installer_patch() {
  local f="$1/robot-install.sh"
  [ -f "$f" ] || die "robot-install.sh fehlt in $1 — Repository unvollstaendig?"
  if grep -q 'echo "AGENTB_CONFIG=\$CONFIG_FILE"' "$f"; then
    ok "Installer-Patch bereits vorhanden"
    return 0
  fi
  cp -a "$f" "$f.bak-$(date +%Y%m%d-%H%M%S)"
  python3 - "$f" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines(keepends=True)
out, done = [], False
for line in lines:
    out.append(line)
    if not done and 'echo "# Mnemo Cortex env' in line:
        out.append(line[:len(line) - len(line.lstrip())] + 'echo "AGENTB_CONFIG=$CONFIG_FILE"\n')
        done = True
if not done:
    sys.exit("Ankerzeile fuer Patch nicht gefunden")
open(p, "w").writelines(out)
PY
  ok "Installer-Patch gesetzt (AGENTB_CONFIG)"
}

preflight() {
  step "1/8 Voraussetzungen"
  local missing=0

  command -v python3 >/dev/null || { fail "python3 fehlt"; missing=1; }
  if command -v python3 >/dev/null; then
    python3 -c 'import venv' >/dev/null 2>&1 && ok "python3 + venv" || { fail "python3-venv fehlt (apt install python3-venv)"; missing=1; }
    python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' \
      && ok "Python >= 3.10" || { fail "Python zu alt (>= 3.10)"; missing=1; }
  fi

  command -v git >/dev/null && ok "git" || { fail "git fehlt"; missing=1; }
  command -v curl >/dev/null && ok "curl" || { fail "curl fehlt"; missing=1; }

  if command -v node >/dev/null; then
    local major; major=$(node -p 'process.versions.node.split(".")[0]')
    [ "$major" -ge 18 ] && ok "Node $(node --version)" || { fail "Node zu alt ($(node --version), >= 18)"; missing=1; }
  else
    fail "node fehlt (>= 18)"; missing=1
  fi

  if systemctl --user is-system-running >/dev/null 2>&1; then
    ok "systemd-User-Instanz"
  else
    warn "keine systemd-User-Instanz — mit --no-service installieren"
  fi

  if curl -s --max-time 5 "http://127.0.0.1:11434/api/tags" | grep -q '"models"'; then
    ok "Ollama erreichbar"
    local tags; tags=$(curl -s --max-time 5 "http://127.0.0.1:11434/api/tags")
    printf '%s' "$tags" | grep -q "$MNEMO_EMBED_MODEL" \
      && ok "Embedding-Modell $MNEMO_EMBED_MODEL vorhanden" \
      || { fail "Embedding-Modell fehlt: ollama pull $MNEMO_EMBED_MODEL"; missing=1; }
    printf '%s' "$tags" | grep -q "${MNEMO_REASON_MODEL%%:*}" \
      && ok "Reasoner-Modell $MNEMO_REASON_MODEL vorhanden" \
      || warn "Reasoner $MNEMO_REASON_MODEL nicht gefunden — ggf. anderes Modell setzen"
  else
    fail "Ollama nicht erreichbar auf 127.0.0.1:11434"; missing=1
  fi

  if (ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null) | grep -q ":$MNEMO_PORT "; then
    if curl -s --max-time 3 "http://127.0.0.1:$MNEMO_PORT/health" | grep -q '"status":"ok"'; then
      warn "Port $MNEMO_PORT belegt durch ein laufendes Mnemo — Schritte 2-6 aktualisieren nur, Daten bleiben"
    else
      fail "Port $MNEMO_PORT belegt durch einen anderen Prozess"; missing=1
    fi
  else
    ok "Port $MNEMO_PORT frei"
  fi

  local av; av=$(df -Pk "$HOME" | awk 'NR==2 {print $4}')
  [ "${av:-0}" -gt 512000 ] && ok "Platz frei ($((av/1024)) MB)" || { fail "zu wenig Platz (< 500 MB)"; missing=1; }

  [ "$missing" = 0 ] || die "Voraussetzungen fehlen — siehe FAIL oben, dann erneut starten."
}

fetch_mnemo() {
  step "2/8 Mnemo Cortex holen (Pin $MNEMO_PIN)"
  if [ -d "$MNEMO_DIR/.git" ]; then
    git -C "$MNEMO_DIR" fetch --quiet origin || die "git fetch fehlgeschlagen (Netz/GitHub?)"
  else
    mkdir -p "$(dirname "$MNEMO_DIR")"
    git clone --quiet https://github.com/GuyMannDude/mnemo-cortex.git "$MNEMO_DIR" \
      || die "git clone fehlgeschlagen (Netz/GitHub?)"
  fi
  git -C "$MNEMO_DIR" checkout --quiet "$MNEMO_PIN" 2>/dev/null \
    || die "Commit $MNEMO_PIN nicht gefunden — Repositorystand pruefen"
  local ver; ver=$(grep -m1 '^version' "$MNEMO_DIR/pyproject.toml" | cut -d'"' -f2)
  ok "Stand: $MNEMO_PIN (Version ${ver:-unbekannt})"
}

write_manifest() {
  step "3/8 Manifest schreiben"
  local src="$HERE/templates/robot.install" dst="$MNEMO_DIR/robot.install"
  [ -f "$src" ] || die "templates/robot.install fehlt — Repository unvollstaendig?"
  python3 - "$src" "$dst" "$MNEMO_REASON_MODEL" "$MNEMO_EMBED_MODEL" "$MNEMO_PORT" "$MNEMO_AGENT_ID" <<'PY'
import sys
src, dst, reason, embed, port, agent = sys.argv[1:7]
t = open(src).read()
t = t.replace('"model": "qwen3.5:cloud"', f'"model": "{reason}"')
t = t.replace('"model": "nomic-embed-text"', f'"model": "{embed}"')
t = t.replace('"port": 50001', f'"port": {int(port)}')
t = t.replace('"agent_id": "openclaw-shared"', f'"agent_id": "{agent}"')
open(dst, "w").write(t)
PY
  ok "Manifest geschrieben (Port $MNEMO_PORT, Agent $MNEMO_AGENT_ID)"
}

run_installer() {
  step "4/8 Installer ausfuehren (legt .venv an, dauert 1-3 Minuten)"
  local out rc=0
  out=$(cd "$MNEMO_DIR" && ./robot-install.sh 2>/tmp/mnemo-install.err) || rc=$?
  printf '%s\n' "$out" | tail -c 1200
  if [ "$rc" != 0 ] || ! printf '%s' "$out" | grep -q '"ok": *true'; then
    echo "--- Installer-Log (stderr, letzte Zeilen) ---" >&2
    tail -30 /tmp/mnemo-install.err >&2 || true
    die "Installer meldet keinen Erfolg. Stufe im JSON oben lesen, dann docs/FEHLERBILDER.md."
  fi
  ok "Installer erfolgreich"
}

start_service() {
  step "5/8 Dienst starten"
  if [ "$NO_SERVICE" = 1 ]; then
    warn "uebersprungen (--no-service). Manuell starten:"
    echo "     $MNEMO_DIR/.venv/bin/python -m uvicorn agentb.server:app --host 127.0.0.1 --port $MNEMO_PORT"
    return 0
  fi
  systemctl --user daemon-reload
  systemctl --user enable --now mnemo-cortex >/dev/null 2>&1 \
    || die "Dienst startet nicht: journalctl --user -u mnemo-cortex -n 50 --no-pager"
  ok "mnemo-cortex aktiv"
}

wait_health() {
  step "6/8 Health abwarten"
  local i
  for i in $(seq 1 30); do
    if curl -s --max-time 2 "http://127.0.0.1:$MNEMO_PORT/health" | grep -q '"status":"ok"'; then
      ok "health ok: $(curl -s "http://127.0.0.1:$MNEMO_PORT/health" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("v"+d["version"], "embedding="+d["embedding"]["active"])' 2>/dev/null)"
      return 0
    fi
    sleep 2
  done
  die "health nach 60 s nicht ok: journalctl --user -u mnemo-cortex -n 50 --no-pager"
}

merge_openclaw_config() {
  step "7/8 OpenClaw-Config"
  if [ "$SKIP_OPENCLAW" = 1 ]; then warn "uebersprungen (--skip-openclaw)"; return 0; fi
  if [ ! -f "$OPENCLAW_CONFIG" ]; then
    warn "keine Config unter $OPENCLAW_CONFIG — Block manuell aus templates/openclaw-mcp.json eintragen"
    return 0
  fi
  local backup="$OPENCLAW_CONFIG.bak-mnemo-$(date +%Y%m%d-%H%M%S)"
  cp -a "$OPENCLAW_CONFIG" "$backup"
  python3 - "$OPENCLAW_CONFIG" "$MNEMO_DIR" "$MNEMO_PORT" "$MNEMO_AGENT_ID" "$MNEMO_SHARE" "$WITH_NATIVE_LOCAL" <<'PY'
import json, sys
path, mdir, port, agent, share, native_local = sys.argv[1:7]
d = json.load(open(path))
block = {
    "command": "/usr/bin/node",
    "args": [f"{mdir}/integrations/mcp-bridge/server.js"],
    "env": {
        "MNEMO_URL": f"http://127.0.0.1:{int(port)}",
        "MNEMO_AGENT_ID": agent,
        "MNEMO_SHARE": share,
    },
    "cwd": f"{mdir}/integrations/mcp-bridge",
    "supportsParallelToolCalls": True,
    "connectionTimeoutMs": 10000,
    "requestTimeoutMs": 30000,
}
d.setdefault("mcp", {}).setdefault("servers", {})["mnemo-cortex"] = block
if native_local == "1":
    mem = d.setdefault("memory", {})
    mem.setdefault("search", {}).setdefault("provider", "local")
tmp = path + ".tmp-mnemo"
with open(tmp, "w") as fh:
    json.dump(d, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
json.load(open(tmp))          # Validierung
PY
  mv "$OPENCLAW_CONFIG.tmp-mnemo" "$OPENCLAW_CONFIG"
  python3 -c "import json,sys; json.load(open('$OPENCLAW_CONFIG'))" \
    || { cp -a "$backup" "$OPENCLAW_CONFIG"; die "Config ungueltig — Backup zurueckgespielt: $backup"; }
  ok "MCP-Block eingetragen (Backup: $backup)"
}

run_verify() {
  step "8/8 Funktionstest"
  if [ -x "$HERE/verify.sh" ]; then
    "$HERE/verify.sh" "http://127.0.0.1:$MNEMO_PORT" "$MNEMO_AGENT_ID" || die "Funktionstest fehlgeschlagen — docs/FEHLERBILDER.md"
  else
    warn "verify.sh fehlt — manuell: curl -s 127.0.0.1:$MNEMO_PORT/health"
  fi
}

summary() {
  cat <<EOF

== Fertig ==
  Dienst:   mnemo-cortex auf 127.0.0.1:$MNEMO_PORT
  Daten:    ~/.mnemo-cortex
  Config:   ~/.config/mnemo-cortex/
  Tenant:   $MNEMO_AGENT_ID (share=$MNEMO_SHARE)

  Naechster Schritt: OpenClaw einmal neu starten, damit die MCP-Tools laden.
    - im Chat: der Eigentuemer sendet /restart
    - auf dem Host: openclaw gateway restart   (beendet laufende Sitzungen)

  Danach in der Sitzung pruefen: mnemo_recall, mnemo_save, mnemo_search.
  Arbeitsregeln: templates/AGENTS-memory-block.md in AGENTS.md uebernehmen.
EOF
}

if [ "$EXPLAIN" = 1 ]; then explain; echo; echo "Nur Erklaerung — nichts geaendert."; exit 0; fi
if [ "$CHECK_ONLY" = 1 ]; then preflight; echo; echo "Nur Pruefung — nichts geaendert."; exit 0; fi
if [ "$PATCH_ONLY" = 1 ]; then apply_installer_patch "$MNEMO_DIR"; exit 0; fi

preflight
fetch_mnemo
apply_installer_patch "$MNEMO_DIR"
write_manifest
run_installer
start_service
wait_health
merge_openclaw_config
run_verify
summary

if [ "$RESTART_GATEWAY" = 1 ]; then
  step "Gateway-Neustart"
  openclaw gateway restart && ok "Gateway neu gestartet" || warn "Neustart fehlgeschlagen — manuell pruefen"
fi
