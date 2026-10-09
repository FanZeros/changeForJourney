# 版本与发布状态

> 本文件只描述**当前**发布状态。历史版本演进见 git 历史，不在此罗列。

## 当前版本

| 项 | 值 |
|---|---|
| 游戏版本 | `1.0.7`（`.project/project.json` → `version`） |
| 项目 ID | `m_bz83` |
| 入口 | `main.lua`（`scripts/main.lua` → `boot/Standalone.lua`） |
| 运行形态 | 单机（`multiplayer.enabled=false`） |
| 屏幕方向 | 横屏（`landscape`） |
| TapTap 分类 | `card` |
| 构建产物 | `dist/1.0.7/`，资源清单 `manifest-*.json` |

## 构建与打包

- **构建**：官方 MCP `build` 工具，`scriptsPath=scripts`，入口 `main.lua`。产物输出到 `dist/`，包含全部 Lua 与资源。
- **资源引用模式**：`.project/resources.json` 为全量引用（`groups.default=["**"]`），资源打包不依赖单独的资源清单模块。
- **PC 离线包**：`electron-shell/`（内置 Node http 服务直发 COOP/COEP，127.0.0.1 可信来源，免登录，广告为预览实现）。`electron-shell/README.md` 描述工程结构与补丁项。
- **发布包代码保护**：见 `docs/pc-protection-research-0927.md`（方案评估）与 `docs/pc-obfuscation-similarity-0928.md`（混淆效果实测）。

## 已知发布注意

- GitHub Release 上的 `win64-*` 旧 zip 早于当前代码，再交付前需用最新 `dist` 重打。
- 构建会改写 `.project/project.json` 的 `project_id`；提交前须还原，不要把本地构建身份推入仓库。
