#!/bin/bash
set -euo pipefail
# Usage: ./scripts/publish_to_icloud.sh [version]
# Default version from control file.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VER="${1:-}"
if [[ -z "$VER" ]]; then
  VER=$(grep '^Version:' control | awk '{print $2}')
fi

IPA="$ROOT/SwitchBox_${VER}.ipa"
TIPA="$ROOT/SwitchBox_${VER}.tipa"
if [[ ! -f "$IPA" ]]; then
  echo "Missing $IPA — run ./scripts/build_ipa.sh first" >&2
  exit 1
fi
if [[ ! -f "$TIPA" ]]; then
  cp -f "$IPA" "$TIPA"
fi

ICLOUD_ROOT="/Users/macmini/Library/Mobile Documents/com~apple~CloudDocs/插件"
SB="$ICLOUD_ROOT/switchbox"
VDIR="$SB/versions/$VER"

mkdir -p "$VDIR" "$SB/latest"
cp -f "$IPA"  "$VDIR/SwitchBox_${VER}.ipa"
cp -f "$TIPA" "$VDIR/SwitchBox_${VER}.tipa"
cp -f "$IPA"  "$SB/latest/SwitchBox.ipa"
cp -f "$TIPA" "$SB/latest/SwitchBox.tipa"

cat > "$VDIR/README.txt" <<READ
切号箱 SwitchBox ${VER}

桌面名：切号箱
Bundle：com.o2ol.switchbox

安装：TrollStore 安装本目录 ipa/tipa，或使用 ../../latest/

功能：轻量多配置容器切换（备份/替换 Documents + Library）
备份目录（设备上）：/var/mobile/Library/SwitchBox/
READ

cat > "$VDIR/CHANGELOG.txt" <<CHG
${VER}
轻量切号：App 列表 / 新建配置 / 切换 / 删除 / 打开关闭目标 App
CHG

cp -f "$VDIR/README.txt" "$SB/latest/README.txt"
printf '%s\n' "$VER" > "$SB/CURRENT"

(
  cd "$VDIR"
  zip -qr "SwitchBox_${VER}.zip" "SwitchBox_${VER}.ipa" "SwitchBox_${VER}.tipa" README.txt CHANGELOG.txt
)

echo "Published ${VER} -> $SB"
echo "CURRENT=$(cat "$SB/CURRENT")"
ls -la "$SB/latest"
ls -la "$VDIR"
