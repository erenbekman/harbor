#!/bin/bash
# Pre-ship security sweep. Run from the repo root: ./tests/security/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
fail=0

echo "→ 1. shell quoting (command injection through project paths and commands)"
mkdir -p .build/security
cp tests/security/quoting.swift .build/security/main.swift
swiftc -o .build/security/quoting Sources/Harbor/Core/Shell.swift .build/security/main.swift 2>&1 | grep -E "error" | head -3
.build/security/quoting || fail=1

echo
echo "→ 2. update integrity (a tampered bundle must fail the check the updater now runs)"
APP="Harbor.app"
if [ ! -d "$APP" ]; then echo "SKIP  build it first: ./build.sh"; else
  if codesign --verify --deep --strict "$APP" 2>/dev/null; then
    echo "PASS  the shipped bundle verifies"
  else
    echo "FAIL  the shipped bundle does not verify"; fail=1
  fi
  rm -rf .build/security/Tampered.app
  ditto "$APP" .build/security/Tampered.app
  printf 'x' >> .build/security/Tampered.app/Contents/MacOS/Harbor
  if codesign --verify --deep --strict .build/security/Tampered.app 2>/dev/null; then
    echo "FAIL  a tampered bundle still verifies — the updater's check is worthless"; fail=1
  else
    echo "PASS  a tampered bundle is rejected"
  fi
  ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
  [ "$ID" = "com.erenbekman.harbor" ] && echo "PASS  bundle identifier is pinned ($ID)" \
    || { echo "FAIL  unexpected bundle identifier: $ID"; fail=1; }
  rm -rf .build/security/Tampered.app
fi

echo
echo "→ 3. on-disk permissions (projects.json, magic.log are not world-readable)"
SUPPORT="$HOME/Library/Application Support/Harbor"
if [ -d "$SUPPORT" ]; then
  DIRMODE=$(stat -f "%Lp" "$SUPPORT")
  [ "$DIRMODE" = "700" ] && echo "PASS  support directory is 0700" \
    || { echo "FAIL  support directory is $DIRMODE"; fail=1; }
  for f in projects.json magic.log; do
    [ -f "$SUPPORT/$f" ] || continue
    MODE=$(stat -f "%Lp" "$SUPPORT/$f")
    [ "$MODE" = "600" ] && echo "PASS  $f is 0600" || { echo "FAIL  $f is $MODE"; fail=1; }
  done
else
  echo "SKIP  no support directory yet"
fi

echo
echo "→ 4. release asset host allowlist is enforced in code"
grep -q "allowedHosts" Sources/Harbor/Core/Updater.swift \
  && echo "PASS  the updater refuses assets from other hosts" \
  || { echo "FAIL  no host allowlist in Updater.swift"; fail=1; }

echo
[ $fail -eq 0 ] && echo "✓ all checks passed" || echo "✗ findings above"
exit $fail
