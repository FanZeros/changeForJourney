# Maker MCP / 本地 Runtime 一键更新

官方包：`@taptap/maker@0.0.34`（TapTap Maker 本地 CLI + MCP）

## 一键（本机 Windows / Mac）

```bat
maker-mcp\update-maker-mcp.bat
```

```bash
bash maker-mcp/update-maker-mcp.sh
```

| 参数 | 作用 |
|------|------|
| （无） | 升级 MCP，写入 Claude / Cursor / Codex 配置 |
| `--preview` | 再下载本机游戏 Runtime 到 `~/.taptap-maker/runtime/` |
| `--start` | 升级后直接开本地预览窗口（不远端构建） |
| `--verify` | 只校验，不改配置 |

升级完后在 Agent 里 **Reconnect MCP**，新工具才会进当前会话。

Windows 注意：官方 CLI 给已存在的 `%USERPROFILE%\\.codex` 做 mkdir 会报 `EEXIST`。
一键脚本会按 Claude / Cursor / Codex 分开升级，撞这个错的 IDE 会跳过，不影响其余。

## 和「远端 Build」的关系

本项目是单机客户端（`multiplayer.enabled=false`，入口 `main.lua`）：

- 改 `scripts/` / `assets/` → 本机 `preview start/refresh` 即可看
- **不用**等云端 build
- 只有改了服务端、或要发测试包/上线，才需要远端构建

## 手动等价命令

```bash
npx -y --package @taptap/maker@0.0.34 taptap-maker upgrade --target-dir <项目根> --json
npx -y --package @taptap/maker@0.0.34 taptap-maker mcp verify --json
npx -y --package @taptap/maker@0.0.34 taptap-maker preview install --target-dir <项目根> --json
npx -y --package @taptap/maker@0.0.34 taptap-maker preview start --target-dir <项目根> --json
```

`preview install/start` 要求项目已绑定（存在 `.maker-mcp/config.json`）。未绑定先跑：

```bash
npx -y @taptap/maker init
```
