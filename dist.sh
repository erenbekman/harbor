#!/bin/bash
# Release artifact: Harbor.zip — the asset name the updater expects.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

VERSION="$(cat VERSION)"
rm -f Harbor.zip
/usr/bin/ditto -c -k --keepParent "Harbor.app" Harbor.zip

echo "✓ Harbor.zip — v${VERSION}"
echo "  gh release create v${VERSION} Harbor.zip --title \"Harbor v${VERSION}\" --notes \"…\""
