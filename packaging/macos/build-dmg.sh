#!/bin/bash
# 把管理端 + 上游网关封装成 macOS .app 并打成 DMG（Apple Silicon）
#
# 前置：
#   1. 本脚本在仓库根目录运行（需要 server/、web/out/）
#   2. 上游源码目录（含 cmd/server），即发布包里的 upstream/
#   3. Go 工具链（arm64），Python 3.11 运行时目录（python-build-standalone）
#   4. uv（用于把依赖装到指定目录，不污染系统环境）
#
# 用法：
#   ./packaging/macos/build-dmg.sh \
#     --upstream /path/to/upstream \
#     --python   /path/to/cpython-3.11-macos-aarch64-none \
#     --version  2.11.6 \
#     --out      dist
#
# 产物：dist/WorkBuddyManager-<version>-macOS-arm64.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UPSTREAM=""; PYSRC=""; VERSION=""; OUT="$ROOT/dist"
APP_NAME="WorkBuddyManager"

while [ $# -gt 0 ]; do
  case "$1" in
    --upstream) UPSTREAM="$2"; shift 2 ;;
    --python)   PYSRC="$2";    shift 2 ;;
    --version)  VERSION="$2";  shift 2 ;;
    --out)      OUT="$2";      shift 2 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

[ -d "$ROOT/web/out" ] || { echo "缺少 web/out（前端静态导出产物）"; exit 1; }
[ -d "$ROOT/server" ] || { echo "缺少 server/"; exit 1; }
[ -n "$UPSTREAM" ] && [ -d "$UPSTREAM/cmd/server" ] || { echo "需要 --upstream 指向含 cmd/server 的上游源码目录"; exit 1; }
[ -n "$PYSRC" ] && [ -x "$PYSRC/bin/python3.11" ] || { echo "需要 --python 指向可再定位的 CPython 3.11 目录"; exit 1; }
[ -n "$VERSION" ] || { echo "需要 --version"; exit 1; }
command -v uv >/dev/null || { echo "需要 uv"; exit 1; }

WORK="$(mktemp -d)"
APP="$WORK/$APP_NAME.app"
RES="$APP/Contents/Resources"
trap 'rm -rf "$WORK"' EXIT

echo "==> 1/6 编译上游网关（darwin/arm64）"
( cd "$UPSTREAM" && GOOS=darwin GOARCH=arm64 go build -o "$WORK/wb2api" ./cmd/server )
file "$WORK/wb2api" | grep -q arm64 || { echo "上游二进制不是 arm64"; exit 1; }

echo "==> 2/6 组装 .app 骨架"
mkdir -p "$APP/Contents/MacOS" "$RES/app" "$RES/upstream" "$RES/site-packages"
ditto "$PYSRC" "$RES/python"
ditto "$ROOT/server" "$RES/app/server"
ditto "$ROOT/web/out" "$RES/app/web/out"
rm -rf "$RES/app/server/tests"
find "$RES/app" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true

cp "$WORK/wb2api" "$RES/upstream/wb2api"
cp "$ROOT/packaging/macos/start-workbuddy2api.sh" "$RES/upstream/"
cp "$ROOT/packaging/macos/stop-workbuddy2api.sh" "$RES/upstream/"
cp "$UPSTREAM/config.example.json" "$RES/upstream/"
chmod +x "$RES/upstream/wb2api" "$RES/upstream/"*.sh

echo "==> 3/6 安装 Python 依赖到包内"
uv pip install --python "$RES/python/bin/python3.11" \
  --target "$RES/site-packages" -r "$ROOT/server/requirements.txt" >/dev/null
du -sh "$RES/python" "$RES/site-packages"

echo "==> 4/6 写入 Info.plist 与启动器"
sed -e "s/__VERSION__/$VERSION/g" "$ROOT/packaging/macos/Info.plist" > "$APP/Contents/Info.plist"
sed -e "s/__VERSION__/$VERSION/g" "$ROOT/packaging/macos/launcher.sh" > "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"
[ -f "$ROOT/packaging/macos/AppIcon.icns" ] && cp "$ROOT/packaging/macos/AppIcon.icns" "$RES/$APP_NAME.icns"

echo "==> 5/6 签名（ad-hoc）"
codesign --force --deep -s - "$APP"
codesign -v "$APP"

echo "==> 6/6 打 DMG"
mkdir -p "$OUT"
STAGE="$WORK/stage"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
[ -f "$ROOT/packaging/macos/使用说明.txt" ] && cp "$ROOT/packaging/macos/使用说明.txt" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/$APP_NAME-$VERSION-macOS-arm64.dmg"
hdiutil create -volname "WorkBuddy Manager" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "完成：$DMG"
