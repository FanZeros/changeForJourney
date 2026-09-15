# changeForJourney 项目改动记录与规划

> 宿命旅途（TapTap 856061）H5 化 + 横屏 PC 多面板改造的完整记录。
> 仓库：https://github.com/FanZeros/changeForJourney
> 线上：https://fanzeros.github.io/changeForJourney/
> 更新：2026-09-15（v1.0.5）

---

## 2026-09-15 部署 v1.0.5（信件全屏 + 加载门控）

- 先祖来信改为全窗口 16:9 cover，使用本地书斋/火漆素材，不再 letterbox 成竖条
- 资源未下载完成前标题锁定，显示加载进度，禁止点进空背景界面
- 源码 workspace@d4b27f8

## 2026-09-15 部署 v1.0.4（先祖来信开场修复）

- 修横屏标题盖住/吞掉先祖来信：等 DarkTitleScreen 关闭后再播 LetterIntro → 过场 → 情景1
- 开场覆盖提到全窗口最上层（letterbox 1080×2400），开场期间独占输入
- 预载结束当帧继续开场判定，避免标题关闭边沿被吞
- 源码 workspace@f642038

## 2026-09-15 部署 v1.0.3（终焉之门·单机版）

- 以 `workspace` 分支最新源码（998d7eb，2026-09-14 晚：三队并行返回键层、角色卡暗黑化调色统一等）重新 Maker 构建（version bump 1.0.2 → 1.0.3）
- 产物按 skill §3/§4 打补丁：去 preview-bridge/水印、WS 免登录 shim、eruda 移除、crossorigin；sw-coop.js 沿用 engine-cache 增强版
- **GitHub Pages**: main 根目录产物全量替换为 1.0.3（旧 1.0.0/1.0.1/assets 移除）；scripts-src 同步最新源码快照
- **Windows 离线版**: `win64-v1.0.3` Release（electron-builder --dir 产物 zip，445MB，双击 `ZhongYanZhiMen.exe` 即玩）
- 校验：manifest 4562 条全存在；index.html 与上一部署版补丁形态一致

## 一、项目概述

| 项 | 内容 |
|---|---|
| 游戏 | 宿命旅途（多人放置 RPG，300 个 Lua 模块 / 14.6 万行） |
| 源素材 | TapCode 客户端下载缓存镜像（`856061/p_u1jd`，哈希文件名 + manifest fs_path 映射） |
| 目标形态 1 | H5 网页版（GitHub Pages，免登录离线可玩） |
| 目标形态 2 | **横屏 PC 三联面板版**（1920×1080，左功能/中主视图/右角色，互不影响） |
| 工作区 | `/workspace/.tmp/cfj-deploy`（部署仓库）、`/workspace/.tmp/rt_856061`（融合目录，可实跑） |

---

## 二、改动时间线

| Commit | 内容 |
|---|---|
| `8aef8bc` | **H5 部署**：dist 全量（508MB，1125 文件）；剔除 mac-token/user_info 凭证与预览调试桥；去 TapTap 水印（img+CSS）；eruda 移除（CSS+MutationObserver）；sw-coop.js 最小 Service Worker 注入 COOP/COEP（Pages 不发隔离头的标准解法）；WebSocket shim 免登录离线（登录服务定向断连 → 引擎 skipping login）；CDN 子资源加 crossorigin=anonymous；.gitattributes `* -text` 防 CRLF 破坏哈希校验 |
| `295d1e1` | **语义源码入库**：scripts-src/（300 模块语义路径源码，来自 manifest fs_path 映射的融合目录） |
| `ce2ba3a` | **横屏 Standalone 版**：core/Viewport.lua（三面板视口）+ network/Standalone.lua HORIZON_MODE（渲染三联 + 输入面板路由 + H_SKIP_START） |
| `b34a7ad` | **横屏上线**：CRC32 重哈希替换 Standalone.lua + 新增 Viewport.lua，8 个 manifest 同步 |
| `003f844` | **横屏 Client 版**：network/Client.lua（HORIZON transform + 左右面板渲染 + skip）+ network/ClientInput.lua（toDesign 面板命中 + effectiveTab 路由），CRC32 重哈希同步 |

---

## 三、关键技术要点

### 3.1 资源哈希与 manifest（改 Lua 的唯一安全路径）

- **资源文件名 = `<uuid>-<CRC32前8位hex>.<ext>`**，引擎按 manifest 的 `size` + 文件名哈希校验
- 改任何 Lua：新内容 → 重算 CRC32 → 新文件名写入 assets → **同步全部 8 个 manifest**（1.0.0/1.0.1 × 分发版/origin 版）的 `hash`/`size`
- manifest 文件名里的哈希**不是**内容校验（原版即不匹配），无需重命名
- 新增文件：自造 22 位 uuid（base64url 字符集），插入 manifest files 数组（分发版带 `groups:["default","#blocking"]`，origin 版带 `prefix:"../scripts"`）
- 工具脚本：`/workspace/.tmp/patch_dist_horizon.py`（重哈希 + manifest 同步的模板）

### 3.2 H5 运行路径（踩过的重要认知）

- **H5 实际走 `network/Client.lua`**（persistent world 本地回环：`[LocalHost] loopback ready`），**不是** Standalone——两份平行渲染/输入代码都要改
- 分发版 settings.json 是 `multiplayer.enabled:false`，但引擎 persistent world 仍起 loopback 服务端（可玩）
- Client 路径跳过开始画面后会连服务器：**离线环境 15s 超时 → DISCONNECTED → 自动清理**（原生 runtime 验证会卡这里）；有网络的环境（线上 H5）loopback 正常
- 验证环境二分：原生 UrhoXRuntime（改 settings 单机 → 走 Standalone 验证横屏渲染）；浏览器 Playwright/CDP（走 Client 验证 H5 真实路径）

### 3.3 横屏三联布局（已实现）

```
1920×1080 = 120 + [486 面板] + 111 + [486 面板] + 111 + [486 面板] + 120
每面板 = 1080×2400 × scale 0.45（高度占满）
左 = 功能经营（城镇 + 市场/铁匠/教堂/酒馆/竞技场/公会）
中 = 主视图（BottomNav：角色/日志/战斗/副本 + 全屏战斗页 + 全局弹窗层）
右 = 角色固定
```

- 页面代码**零改动**：Viewport.begin = `nvgSave + nvgTranslate + nvgScale(0.45) + nvgIntersectScissor`，面板内就是原 1080×2400 坐标系
- 输入：`Viewport.hit` 面板命中 + 坐标逆变换；ClientInput 经 toDesign 单点改造 + effectiveTab()（左面板强制 Tab4、右面板强制 Tab1、中面板随 BottomNav）
- `H_SKIP_START=true`：StartScreen.skipForReconnect() 跳过开始画面直进主界面（PC 离线形态）
- 滚轮无坐标信息：发给最近交互面板（H_lastPanel）

### 3.4 踩坑记录

| 坑 | 现象 | 解法 |
|---|---|---|
| 双重缩放 | Client StartScreen/Loading 画面缩成 55px 窄条 | 分支内不要再 nvgScale——复用入口按状态设置的外层 scale |
| 偏移缩放空间语义 | Loading 画面偏左不居中 | designOffset 是**缩放后空间**的值：视觉偏移需除以 scale |
| return 位置 | Standalone.lua 加载报 `<eof> expected near 'local'` | 横屏块追加到了 `return Standalone` 之后——return 必须是文件最后语句 |
| 词表误报 | 横屏品类/动画检测把 `酒馆-idle.mp4`、`Wave.ani` 当玩法词 | 品类词只在 .lua 文件名 + 中文品类词（割草/肉鸽/无尽）上匹配 |
| heredoc 转义 | bash heredoc 里 `\!=` 被转义成语法错误 | 用 Write 工具写脚本，或避免 `!=`（用 `not (a == b)`） |
| headless 截图 | 引擎 WASM 满载主线程，Playwright screenshot 永久排队 | CDP `Page.captureScreenshot` + `asyncio.wait_for` 超时保护；chrome 需补 libnspr4/libnss3 等系统库（Ubuntu pool deb 解包 + LD_LIBRARY_PATH）；`--disable-dev-shm-usage` 必带 |

---

## 四、横屏改造规划与进度

### 已完成（阶段 0-2 + Client 同步）

- ✅ core/Viewport.lua 视口抽象（注册/变换/裁剪/命中/逆变换）
- ✅ Standalone.lua 三联渲染 + 输入路由（原生实跑验证：Lua 零错误 + 截图确认）
- ✅ Client.lua + ClientInput.lua 同步改造（H5 实跑验证：横屏布局生效截图确认）
- ✅ CRC32 重哈希部署管线（patch_dist_horizon.py 可复用）

### 待做（按优先级）

1. **阶段 3 面板交互打磨**：面板头部条（标题/切换/交换/临时放大）；左右面板的二级页返回栈
2. **阶段 4 联机回归**：真实服务器环境（TapTap 容器）回归 Client 横屏；目前仅 loopback 验证
3. **二期会话化**：页面模块 `state.open` 单例 → 每面板 UI 会话（支持同一页面多面板打开）
4. **弹窗全局化二期**：弹窗从"中面板空间"提升为全窗口浮层（需重设计弹窗坐标基准）
5. **战斗页横屏适配**（可选）：BattleScene 重设计为横屏布局（当前保持竖屏居中）
6. **Right 面板内容核实**：CharacterPanel 未 open 时的绘制内容偏场景图，需确认角色属性面板的呈现路径

### 已知一期限制

- 弹窗为模态且绘制于中面板空间（左右面板交互触发的弹窗也出现在中面板）
- 同一页面同时只能在一个面板打开（页面模块单例状态）
- StartScreen/Loading 全窗口居中为竖屏画布（1:1 或等比，两侧留黑）
- 联机版仅在 loopback 环境验证过加载，未在真实服务器回归

---

## 五、更新操作手册（SOP）

改了游戏源码后如何更新线上：

```bash
# 1. 同步源码到融合目录（或直接改融合目录内的 scripts/）
cp <改动文件> /workspace/.tmp/rt_856061/scripts/<同路径>/

# 2. 原生快验（改 settings 单机可验 Standalone；Client 需浏览器）
cd /workspace/.tmp/rt_856061
timeout 100 /workspace/.cli/UrhoXRuntime main.lua -tapcode_dir=$PWD -tool_mode \
  -graphicsheadless -validate -validate-frames=120 -validate-timeout=80 -nosound \
  -validate-output=$PWD/.tmp/validate.json

# 3. 重哈希替换进 H5 dist（参照 patch_dist_horizon.py：CRC32 + 8 manifest 同步）

# 4. 推送（部署仓库 /workspace/.tmp/cfj-deploy）
git add -A && git commit -m "..." && git push

# 5. 等 Pages 重建（1-3 分钟，Fastly 缓存最长 10 分钟）+ 浏览器强刷
```

---

## 六、评估体系衔接

本项目的质量评估（七维度/体验向评分）由 `tempGame/skills/game-quality-eval` 承担：
- 评估报告（6 游戏）：`/workspace/docs/game-eval/quality_*.md`
- 宿命旅途评分：**77/100（A）**，玩法与内容 40/45（特色组合/专有命名满档），体验 19/20（实跑 loopback 验证）
- AI 评审流程：脚本取数 → Read evidence 包 + 拼贴图 → `--semantic/--visual/--style/--runtime-notes` 注入
