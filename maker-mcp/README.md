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
| （无） | 与 `--start` 相同：升级后开窗口。Windows 前台启动并跳过 Tap 扫码 |
| `--preview` | 只下载本机游戏 Runtime，不开窗口 |
| `--start` | 与不带参数相同 |
| `--verify` | 只校验，不改配置 |

升级完后在 Agent 里 **Reconnect MCP**，新工具才会进当前会话。

Windows 注意：
- 官方 CLI 给已存在的 `%USERPROFILE%\\.codex` 做 mkdir 会报 `EEXIST`。脚本按 Claude / Cursor / Codex 分开升级，撞这个错的 IDE 会跳过。
- 双击 bat 会在**同一个窗口**跑完并 `pause`，不要关黑窗；跑完把最后几行贴回 Agent。

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

## 窗口停在 upgrade 那一行

`--start` 的第一条命令是 `taptap-maker upgrade`，会先用 npx 下载 `@taptap/maker@0.0.34`。
旧脚本用 `capture_output` 把 npm 日志吃掉，窗口就像卡死在 `$ ... taptap-maker upgrade`。
这不是云端 Build。现在日志会直接刷出来，单步超过时限会自己停并打印 TIMEOUT。

若立刻报找不到 `.maker-mcp/config.json`：先在项目根执行一次

```bat
npx -y --package @taptap/maker@0.0.34 taptap-maker init
```

绑定（要登录）后再 `--start`。

## Windows --start：前台开窗口，不走隐藏 PowerShell

官方 `taptap-maker preview start` 在 Windows 上用隐藏 `powershell.exe` 加 `Win32_Process.Create` 拉 supervisor。
这条后台链失败时：`supervisor.log` 是 0 字节，`supervisor_pid` 是 0，Runtime 已安装但窗口出不来。
这不是游戏代码，也不是云端构建，不要重装 Node。

本脚本的 `--start` 在 Windows 上改为与手工验证相同的前台启动：工作目录是项目根，直接运行已安装的 `UrhoXRuntime.exe`。
优先读 `%USERPROFILE%\.taptap-maker\runtime\installation.json` 的 `executable`，否则用最新的 `runtime-*\UrhoXRuntime.exe`。

启动参数带 `-skip_login`，和官方本地预览一样跳过 Tap 扫码登录。漏掉这个参数时，Runtime 会自己弹出扫码，不是游戏逻辑。
黑窗会停到游戏窗口关闭。改完 `scripts/` 后重新双击 `--start`。不要用官方 `preview refresh`，那条仍走没起来的隐藏 supervisor。
