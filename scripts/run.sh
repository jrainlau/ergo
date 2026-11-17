#!/bin/zsh
# 构建（如需要）并启动 Ergo，用于触发系统授权弹窗。
set -e
cd "$(dirname "$0")/.."

APP="build/Build/Products/Debug/Ergo.app"

if [[ "$1" == "--build" || ! -d "$APP" ]]; then
  make build
fi

pkill -x Ergo 2>/dev/null || true
sleep 0.5
open "$APP"
echo "已启动 Ergo。菜单栏会出现图标；在 设置 → 权限 里点“授权”。"
