# 宿命旅途 H5（changeForJourney）

宿命旅途（856061）Web 版：UrhoX H5 构建产物 + GitHub Pages 离线自部署形态。

- 免登录离线运行（WebSocket shim → skipping login），广告为 FakeAd 预览
- 跨域隔离由最小 Service Worker（sw-coop.js）注入，引擎 70MB 运行时走官方 CDN
- 仓库 `* -text` 防 CRLF 破坏资源哈希校验

访问：https://fanzeros.github.io/changeForJourney/

改造计划（横屏 PC 多面板版）见工作区 docs/suyuan-landscape-plan.md。
