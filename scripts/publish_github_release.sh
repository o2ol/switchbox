#!/bin/bash
set -euo pipefail
# Usage: ./scripts/publish_github_release.sh [version]
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VER="${1:-}"
if [[ -z "$VER" ]]; then
  VER=$(grep '^Version:' control | awk '{print $2}')
fi
TAG="v${VER}"
IPA="$ROOT/SwitchBox_${VER}.ipa"
TIPA="$ROOT/SwitchBox_${VER}.tipa"
[[ -f "$IPA" ]] || { echo "missing $IPA — run ./scripts/build_ipa.sh first"; exit 1; }
[[ -f "$TIPA" ]] || cp -f "$IPA" "$TIPA"

export PATH="/opt/homebrew/bin:$PATH"
gh auth status >/dev/null

NOTES="SwitchBox ${VER}

- TrollStore multi-profile account switcher
- Fresh profile + local device-ID seed reset
- iOS / iPadOS 15+ · arm64
- Prefer .tipa

https://github.com/o2ol/switchbox
"

if gh release view "$TAG" -R o2ol/switchbox >/dev/null 2>&1; then
  gh release upload "$TAG" "$IPA" "$TIPA" --clobber -R o2ol/switchbox
  gh release edit "$TAG" -R o2ol/switchbox --notes "$NOTES" --draft=false
else
  gh release create "$TAG" "$IPA" "$TIPA" \
    -R o2ol/switchbox \
    --title "SwitchBox ${VER}" \
    --notes "$NOTES"
fi
echo "OK: https://github.com/o2ol/switchbox/releases/tag/${TAG}"
