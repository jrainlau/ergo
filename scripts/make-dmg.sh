#!/bin/zsh
# 用法：scripts/make-dmg.sh <Ergo.app 路径> <输出 dmg 路径>
# 生成带 “Applications” 快捷方式的 dmg。仅依赖系统自带的 hdiutil。
set -euo pipefail

APP="${1:?用法: make-dmg.sh <Ergo.app> <输出.dmg>}"
OUT="${2:?用法: make-dmg.sh <Ergo.app> <输出.dmg>}"

[[ -d "$APP" ]] || { echo "找不到 $APP" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil create -volname "Ergo" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT" >/dev/null
echo "已生成 $OUT"
