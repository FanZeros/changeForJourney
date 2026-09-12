# 宿命旅途 H5（changeForJourney）

宿命旅途（856061）Web 版：UrhoX H5 构建产物 + GitHub Pages 离线自部署形态。

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
