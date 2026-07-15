#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export THEOS="${THEOS:-/Users/macmini/work/theos}"
export PATH="/opt/homebrew/opt/make/libexec/gnubin:/opt/homebrew/bin:$THEOS/bin:$PATH"

make clean
make package FINALPACKAGE=1

DEB=$(ls -t packages/com.o2ol.switchbox_*.deb | head -1)
echo "DEB=$DEB"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
dpkg-deb -x "$DEB" "$STAGE"

APP="$STAGE/Applications/SwitchBox.app"
if [[ ! -d "$APP" ]]; then
  echo "SwitchBox.app not found in deb" >&2
  ls -laR "$STAGE" | head -50
  exit 1
fi

# ensure entitlements
if command -v ldid >/dev/null 2>&1; then
  ldid -Sentitlements.plist "$APP/SwitchBox"
fi

IPA_DIR=$(mktemp -d)
mkdir -p "$IPA_DIR/Payload"
cp -a "$APP" "$IPA_DIR/Payload/"

VER=$(grep '^Version:' control | awk '{print $2}')
OUT_IPA="$ROOT/SwitchBox_${VER}.ipa"
OUT_TIPA="$ROOT/SwitchBox_${VER}.tipa"
rm -f "$OUT_IPA" "$OUT_TIPA"
(
  cd "$IPA_DIR"
  zip -qr "$OUT_IPA" Payload
)
cp -f "$OUT_IPA" "$OUT_TIPA"
ls -lh "$OUT_IPA" "$OUT_TIPA"
echo "OK: $OUT_IPA"
