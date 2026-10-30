#!/bin/bash
# WorkBuddyManager.app 启动器
# 首次运行把可写运行时落到 ~/Library/Application Support/WorkBuddyManager/
set -u

EXEC_DIR="$(cd "$(dirname "$0")" && pwd)"
RES="$EXEC_DIR/../Resources"
SUP="$HOME/Library/Application Support/WorkBuddyManager"
RUN="$SUP/runtime"
PY="$RES/python/bin/python3.11"
PANEL_LOG="$SUP/data/panel.out.log"
PANEL_URL="http://127.0.0.1:7864"
UP_URL="http://127.0.0.1:7863"

http_ok() { curl -s -o /dev/null --max-time 2 -w '%{http_code}' "$1" 2>/dev/null | grep -q '^2\|^5'; }

# ── 已在跑就直接开浏览器 ──────────────────────────────
if http_ok "$PANEL_URL"; then
  open "$PANEL_URL"
  exit 0
fi

mkdir -p "$SUP/data"

# ── 首次运行：复制可写运行时 ─────────────────────────
if [ ! -d "$RUN" ]; then
  cp -R "$RES/app" "$RUN"
  cp -R "$RES/upstream" "$RUN/upstream"
fi
mkdir -p "$RUN/upstream/auths" "$RUN/upstream/data"

# ── 上游 config.json：首次生成随机 api_key ───────────
if [ ! -f "$RUN/upstream/config.json" ]; then
  "$PY" - "$RUN/upstream" << 'PYEOF'
import json, secrets, sys, pathlib
d = pathlib.Path(sys.argv[1])
cfg = json.load(open(d / 'config.example.json'))
cfg['api_key'] = 'wb2api-' + secrets.token_hex(16)
json.dump(cfg, open(d / 'config.json', 'w'), indent=2, ensure_ascii=False)
PYEOF
fi

# ── 环境变量（对标 .env，native 模式）────────────────
export WB_MANAGER_HOST=127.0.0.1
export WB_MANAGER_PORT=7864
export WB2API_MODE=native
export WB2API_BASE="$UP_URL"
export WB2API_START_SCRIPT="$RUN/upstream/start-workbuddy2api.sh"
export WB2API_STOP_SCRIPT="$RUN/upstream/stop-workbuddy2api.sh"
export WB2API_LOG_FILE="$RUN/upstream/data/server.err.log"
export WB2API_CHAT_LOG_FILE="$RUN/upstream/data/server.out.log"
export WB_AUTH_DIR="$RUN/upstream/auths"
export WB_UPSTREAM_CONFIG="$RUN/upstream/config.json"
export WB_UPSTREAM_DIR="$RUN/upstream"
export WB_DATA_DIR="$SUP/data"
export WB_STATIC_DIR="$RUN/web/out"
export PYTHONPATH="$RES/site-packages"

# ── 拉起上游 ─────────────────────────────────────────
"$RUN/upstream/start-workbuddy2api.sh"

# ── 拉起管理端 ───────────────────────────────────────
PANEL_PID=""
if ! http_ok "$PANEL_URL"; then
  nohup "$PY" -m uvicorn server.main:app \
    --host 127.0.0.1 --port 7864 \
    --app-dir "$RUN" >> "$PANEL_LOG" 2>&1 &
  PANEL_PID=$!
fi

# ── 等就绪后开浏览器 ─────────────────────────────────
for _ in $(seq 1 30); do
  if http_ok "$PANEL_URL"; then break; fi
  sleep 1
done
open "$PANEL_URL"

# ── 首次登录信息落到显眼位置（初始密码只在 data 目录里，容易找不到）──
PWDFILE="$SUP/data/initial-admin-password.txt"
INFO="$SUP/登录信息.txt"
if [ -f "$PWDFILE" ] && [ ! -f "$INFO" ]; then
  {
    echo "登录地址：$PANEL_URL"
    echo "用户名　：admin"
    echo "密码　　：$(cat "$PWDFILE")"
    echo ""
    echo "登录后建议在「设置 → 管理用户」里改密码，之后本文件可删除。"
    echo "若提示「失败次数过多」，重启本应用即可解除（锁定计数在内存里）。"
  } > "$INFO"
fi

# ── 保活：上游/管理端挂了自动拉起；退出时清理 ────────
cleanup() {
  [ -n "$PANEL_PID" ] && kill "$PANEL_PID" 2>/dev/null
  "$RUN/upstream/stop-workbuddy2api.sh" 2>/dev/null
  exit 0
}
trap cleanup TERM INT
while true; do
  sleep 5
  if [ -n "$PANEL_PID" ] && ! kill -0 "$PANEL_PID" 2>/dev/null; then
    nohup "$PY" -m uvicorn server.main:app \
      --host 127.0.0.1 --port 7864 \
      --app-dir "$RUN" >> "$PANEL_LOG" 2>&1 &
    PANEL_PID=$!
  fi
  if ! http_ok "$UP_URL" && ! pgrep -f "$RUN/upstream/wb2api" >/dev/null 2>&1; then
    "$RUN/upstream/start-workbuddy2api.sh"
  fi
done
