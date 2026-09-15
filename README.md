# 终焉之门·单机版 H5（changeForJourney）

终焉之门·单机版（宿命旅途 856061 改名演进线）Web 版：UrhoX H5 构建产物 + GitHub Pages 离线自部署形态。
当前线上产物：v1.0.4（2026-09-15）；Windows 离线版下载见 Releases（tag `win64-v1.0.4`）。

- 免登录离线运行（WebSocket shim → skipping login），广告为 FakeAd 预览
- 跨域隔离由最小 Service Worker（sw-coop.js）注入，引擎 70MB 运行时走官方 CDN
- 仓库 `* -text` 防 CRLF 破坏资源哈希校验

访问：https://fanzeros.github.io/changeForJourney/

改造计划（横屏 PC 多面板版）见工作区 docs/suyuan-landscape-plan.md。

## 源码目录 scripts-src/

游戏 Lua 源码（语义路径，300 模块）：
- `main.lua` 入口；`ui/` 24+ 页面模块（统一 draw/open/isOpen/handleDragBegin 协议）
- `systems/` 战斗公式/天赋/状态效果；`config/` 数值与关卡配置
- `network/` Client/Standalone 双模式渲染与输入；`server/` 竞技场等服务端
- 横屏 PC 版改造进行中（core/Viewport.lua 多面板方案）

## 横屏 PC 多面板版（已实跑验证）

`core/Viewport.lua` + `network/Standalone.lua`（HORIZON_MODE）：
- 1920×1080 三联竖屏面板（486×1080/面板，scale 0.45）：左=功能经营（城镇+市场/铁匠/酒馆/竞技场），中=主视图（战斗/角色/日志+全局弹窗），右=角色固定
- 输入按面板命中 + 设计坐标逆变换，页面代码零改动
- `H_SKIP_START=true` 跳过开始画面（PC 离线形态）
- 验证：UrhoXRuntime 软渲染 120 帧 validate Lua 零错误 + 三联截图确认
