# macOS 打包（Apple Silicon）

把管理端（FastAPI）+ 前端（Next.js 静态导出）+ 上游网关（Go）封装成自包含的 `WorkBuddyManager.app`，再压成 DMG。产物不依赖目标机上的 Python / Node / Go / Docker。

## 产物

```
WorkBuddyManager-<version>-macOS-arm64.dmg
```

内含 `WorkBuddyManager.app`、`使用说明.txt` 与指向 `/Applications` 的软链。

## 构建

```bash
# 前端静态导出（产物在 web/out，仓库不提交）
cd web && npm ci && npm run build:export && cd ..

# 依赖：Go（arm64）、uv、Python 3.11 可再定位运行时目录
./packaging/macos/build-dmg.sh \
  --upstream /path/to/upstream \
  --python   /path/to/cpython-3.11-macos-aarch64-none \
  --version  2.11.6 \
  --out      dist
```

- `--upstream`：含 `cmd/server` 的上游源码目录（发布包里的 `upstream/`）
- `--python`：python-build-standalone 的 CPython 3.11 目录，会整份复制进包内
- `--version`：写入 `Info.plist` 与产物文件名

脚本会依次完成：编译 arm64 版 `wb2api` → 组装 `.app` → 用 `uv pip install --target` 把依赖装进包内 → 写 `Info.plist` 与启动器 → ad-hoc 签名 → `hdiutil` 打 DMG → 输出 sha256。

## 运行期结构

应用启动后不使用 DMG 内的只读文件，首次运行会把可写运行时释放到：

```
~/Library/Application Support/WorkBuddyManager/runtime/   # server、web、upstream、数据
~/Library/Application Support/WorkBuddyManager/data/      # 数据库、用户、日志
```

启动器（`launcher.sh` → `Contents/MacOS/WorkBuddyManager`）负责：

- 首次运行释放运行时、生成随机 `api_key` 的 `config.json`
- 以 native 模式拉起上游（`start-workbuddy2api.sh`）与 uvicorn
- 等面板就绪后打开浏览器
- 子进程挂掉自动拉起；应用退出时一并停止
- 把初始登录信息写到 `~/Library/Application Support/WorkBuddyManager/登录信息.txt`

## 注意

- 只构建 arm64，Intel 机型不适用
- 使用 ad-hoc 签名（`codesign -s -`），未做公证，首次打开需右键 → 打开
- 端口固定：上游 `7863`、面板 `7864`，均为 `127.0.0.1`
