# 宿命旅途 H5（changeForJourney）

宿命旅途（856061）Web 版：UrhoX H5 构建产物 + GitHub Pages 离线自部署形态。

- 免登录离线运行（WebSocket shim → skipping login），广告为 FakeAd 预览
- 跨域隔离由最小 Service Worker（sw-coop.js）注入，引擎 70MB 运行时走官方 CDN；引擎静态资源 SW 本地缓存（缓存优先 + ETag 协商，对策 CDN `max-age=5`）
- 三段式预载：前台 80MB 核心 UI（进度遮罩）→ 剩余小图后台无感补载 → >1MB 大图保持惰性；常驻显存 507MB→81MB
- 仓库 `* -text` 防 CRLF 破坏资源哈希校验

访问：https://fanzeros.github.io/changeForJourney/

启动流程：sw-coop 注入隔离头 → 引擎 CDN（SW 缓存优先）→ 预载进度遮罩 → **DarkTitleScreen** 横屏暗黑标题（轻触继续）→ **LetterIntro** 先祖来信（仅首登）→ IntroCutscene 睁眼过场 → 主界面。

完整改动记录见 [CHANGELOG.md](CHANGELOG.md)；改造文档见 [docs/](docs/)（协作与 dist 部署约定、暗黑魔塔改造总体方案、素材清单与暗黑风格方案）。

## 源码目录 scripts-src/

游戏 Lua 源码（语义路径，300 模块）：
- `main.lua` 入口；`ui/` 24+ 页面模块（统一 draw/open/isOpen/handleDragBegin 协议）
- `systems/` 战斗公式/天赋/状态效果；`config/` 数值与关卡配置（含 `AssetManifest.lua` 全量预载清单）
- `network/` Client/Standalone 双模式渲染与输入；`server/` 竞技场等服务端
- `core/` 基础设施：Viewport（三联视口）、DarkIcon（暗黑矢量图标/九宫格）、HorizonBg（横屏共享大背景）、DrawUtil/EventBus/GameState
- `ui/` 新增：DarkTitleScreen（横屏暗黑标题）、LetterIntro（首登先祖来信）

## 横屏 PC 多面板版（已实跑验证）

`core/Viewport.lua` + `network/Standalone.lua`（HORIZON_MODE）/ `network/Client.lua`（H5 路径）：
- 1920×1080 三联**无缝拼接**（BASE 1458 = 3×486，scale 0.45）：左=功能经营（城镇+市场/铁匠/酒馆/竞技场），中=主视图（战斗/角色/日志+全局弹窗），右=角色固定
- 左右面板由 `core/HorizonBg` 各显示城镇大图一半，构成同一连续世界；中面板战斗保持独立背景
- 模态弹窗出现时左右面板压暗聚焦
- 输入按面板命中 + 设计坐标逆变换，页面代码零改动
- `H_SKIP_START=true` 跳过竖屏开始画面（PC 离线形态），标题仪式感由 DarkTitleScreen 补齐
- 验证：UrhoXRuntime 软渲染 120 帧 validate Lua 零错误 + 三联截图确认
