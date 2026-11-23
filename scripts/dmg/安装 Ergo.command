#!/bin/bash
# Ergo 使用 ad-hoc 签名，从网上下载后会被 Gatekeeper 隔离（提示“无法验证开发者”）。
# 双击本脚本即可：必要时把 Ergo 装进「应用程序」，然后解除隔离并启动。
# 无论你是先把 Ergo 拖进「应用程序」再运行本脚本，还是直接运行本脚本，结果都一样。

DEST="/Applications/Ergo.app"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/Ergo.app"

if [ -d "$SRC" ] && [ "$SRC" != "$DEST" ]; then
  # 在 DMG 里运行：安装（覆盖旧版）
  echo "正在安装 Ergo 到 /Applications ..."
  pkill -x Ergo 2>/dev/null && sleep 1
  rm -rf "$DEST"
  ditto "$SRC" "$DEST" || { echo "安装失败，请手动把 Ergo 拖进「应用程序」后重新运行本脚本。"; exit 1; }
fi

if [ ! -d "$DEST" ]; then
  echo "没有找到 $DEST，请先把 Ergo 拖进「应用程序」。"
  exit 1
fi

xattr -dr com.apple.quarantine "$DEST"
echo "已解除隔离，正在启动 Ergo ..."
open "$DEST"
