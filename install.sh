#!/bin/bash
# Builds and installs into /Applications.
set -euo pipefail
cd "$(dirname "$0")"

# Services run inside tmux so they survive quitting the app. Without it Harbor
# cannot start anything at all.
if ! command -v tmux >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "→ tmux is missing; installing with Homebrew…"
    brew install tmux
  else
    echo "✗ tmux is required and Homebrew is not installed."
    echo "  https://github.com/tmux/tmux/wiki/Installing"
    exit 1
  fi
fi

./build.sh

echo "→ installing into /Applications…"
rm -rf "/Applications/Harbor.app"
cp -R "Harbor.app" /Applications/
xattr -cr "/Applications/Harbor.app" 2>/dev/null || true

echo "✓ installed — launching"
open "/Applications/Harbor.app"
