#!/bin/bash
# macOS 原生启停脚本（对应 windows-native 的 .cmd 约定）：
# 1. 必须立即返回 —— 后台拉起 wb2api，不阻塞调用方
# 2. 日志分流写 server.out.log / server.err.log
set -u
UPSTREAM_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$UPSTREAM_DIR/data/wb2api.pid"
LOG_OUT="$UPSTREAM_DIR/data/server.out.log"
LOG_ERR="$UPSTREAM_DIR/data/server.err.log"

mkdir -p "$UPSTREAM_DIR/data" "$UPSTREAM_DIR/auths"

# 已在跑就不重复拉起
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  exit 0
fi

cd "$UPSTREAM_DIR"
nohup ./wb2api > "$LOG_OUT" 2> "$LOG_ERR" &
echo $! > "$PID_FILE"
exit 0
