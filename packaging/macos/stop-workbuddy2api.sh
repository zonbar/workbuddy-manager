#!/bin/bash
# macOS 原生停止脚本：按 PID 文件 + 进程路径校验，避免误杀同名进程
set -u
UPSTREAM_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$UPSTREAM_DIR/data/wb2api.pid"

if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE")"
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    # 校验确实是本目录的 wb2api
    if ps -p "$PID" -o comm= 2>/dev/null | grep -q "wb2api"; then
      kill "$PID"
      for _ in $(seq 1 20); do
        kill -0 "$PID" 2>/dev/null || break
        sleep 0.5
      done
      kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
    fi
  fi
  rm -f "$PID_FILE"
fi
exit 0
