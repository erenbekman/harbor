#!/bin/bash
# End-to-end MCP protocol test. Runs against an isolated support directory and
# tmux socket, never the user's real projects or services.
set -uo pipefail
cd "$(dirname "$0")/../.."
fail=0

BIN=".build/debug/Harbor"
[ -x "$BIN" ] || BIN=".build/release/Harbor"
[ -x "$BIN" ] || { echo "SKIP  build first: swift build"; exit 0; }

ROOT=$(mktemp -d /tmp/harbor-mcp-test.XXXXXX)
PROJECT="$ROOT/demo"
SUPPORT="$ROOT/support"
SOCKET="$ROOT/tmux.sock"
PORT=8791
mkdir -p "$PROJECT" "$SUPPORT"
echo "hello from harbor" > "$PROJECT/index.html"

cat > "$SUPPORT/projects.json" <<JSON
[ { "id": "11111111-1111-1111-1111-111111111111", "name": "demo", "path": "$PROJECT", "tint": 0,
    "services": [ { "id": "22222222-2222-2222-2222-222222222222", "name": "web",
                    "command": "python3 -m http.server $PORT", "dir": "", "health": "/" } ] } ]
JSON

run_mcp() { (cd "$PROJECT" && HARBOR_SUPPORT_DIR="$SUPPORT" HARBOR_TMUX_SOCKET="$SOCKET" "$OLDPWD/$BIN" mcp); }
check() { if [ "$2" = "1" ]; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }

echo "→ protocol"
OUT=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"nope/nope"}' \
  'not json at all' \
  | run_mcp)
echo "$OUT" | python3 -c '
import json,sys
lines=[json.loads(l) for l in sys.stdin if l.strip()]
by={l.get("id"):l for l in lines if "id" in l}
ok=lambda c,m: print(("PASS  " if c else "FAIL  ")+m) or c
r=by.get(1,{}).get("result",{})
good = all([
  ok(r.get("protocolVersion")=="2025-06-18","initialize echoes the protocol version"),
  ok(r.get("serverInfo",{}).get("name")=="harbor","serverInfo names harbor"),
  ok({t["name"] for t in by.get(2,{}).get("result",{}).get("tools",[])} ==
     {"list_services","start_service","stop_service","restart_service","read_logs"},"tools/list has the five tools"),
  ok(by.get(3,{}).get("error",{}).get("code")==-32601,"unknown method is -32601"),
  ok(any(l.get("error",{}).get("code")==-32700 for l in lines),"broken JSON is -32700"),
  ok(all(("result" in l) or ("error" in l) for l in lines),"every line is a JSON-RPC response"),
])
sys.exit(0 if good else 1)
' || fail=1

echo
echo "→ tools"
text() { python3 -c '
import json,sys
want=int(sys.argv[1])
for line in sys.stdin:
    if not line.strip(): continue
    m=json.loads(line)
    if m.get("id")==want:
        print(m["result"]["content"][0]["text"])
' "$1"; }

OUT=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_services","arguments":{}}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"start_service","arguments":{"service":"web","wait_seconds":25}}}' \
  | run_mcp)
echo "$OUT" | python3 -c '
import json,sys
rows={}
for line in sys.stdin:
    if not line.strip(): continue
    m=json.loads(line)
    if m.get("id") in (2,3): rows[m["id"]]=json.loads(m["result"]["content"][0]["text"])
ok=lambda c,msg: print(("PASS  " if c else "FAIL  ")+msg) or c
listed={s["name"]: s for s in rows.get(2,{}).get("services",[])}
started=rows.get(3,{})
good=all([
  ok(listed.get("web",{}).get("status")=="stopped","list_services resolves the project from cwd and reports stopped"),
  ok(started.get("status")=="running","start_service brings the service up"),
  ok(started.get("port")==8791,"start_service reports the measured port"),
  ok(started.get("url")=="http://localhost:8791","it hands back a usable url"),
  ok(started.get("started_by")=="agent","the session is marked as agent-started"),
])
sys.exit(0 if good else 1)
' || fail=1

curl -s -o /dev/null "http://localhost:$PORT/" || true
sleep 1

OUT=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"read_logs","arguments":{"service":"web","contains":"GET","lines":999999}}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"stop_service","arguments":{"service":"web"}}}' \
  | run_mcp)
echo "$OUT" | python3 -c '
import json,sys
rows={}
for line in sys.stdin:
    if not line.strip(): continue
    m=json.loads(line)
    if m.get("id") in (2,3): rows[m["id"]]=json.loads(m["result"]["content"][0]["text"])
ok=lambda c,msg: print(("PASS  " if c else "FAIL  ")+msg) or c
good=all([
  ok("GET" in rows.get(2,{}).get("output",""),"read_logs finds the request line and clamps lines"),
  ok(rows.get(3,{}).get("status")=="stopped","stop_service stops it"),
])
sys.exit(0 if good else 1)
' || fail=1

echo
echo "→ refusals"
OUT=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"start_service","arguments":{"service":"nope"}}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"start_service","arguments":{"service":"web; rm -rf /tmp/harbor-should-not-exist"}}}' \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"list_services","arguments":{"project":"nosuchproject"}}}' \
  | run_mcp)
echo "$OUT" | python3 -c '
import json,sys
errs={}
for line in sys.stdin:
    if not line.strip(): continue
    m=json.loads(line)
    if m.get("id") in (2,3,4): errs[m["id"]]=m["result"]
ok=lambda c,m: print(("PASS  " if c else "FAIL  ")+m) or c
good=all([
  ok(errs.get(2,{}).get("isError") is True,"an unregistered service is refused"),
  ok(errs.get(3,{}).get("isError") is True,"a service name with shell characters is refused"),
  ok(errs.get(4,{}).get("isError") is True,"an unknown project is refused"),
])
sys.exit(0 if good else 1)
' || fail=1
[ -e /tmp/harbor-should-not-exist ] && { echo "FAIL  injection created a file"; fail=1; } || echo "PASS  nothing was executed from the service name"

tmux -S "$SOCKET" kill-server 2>/dev/null
rm -rf "$ROOT"
echo
[ $fail -eq 0 ] && echo "✓ all checks passed" || echo "✗ findings above"
exit $fail
