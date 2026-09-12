# 协作与 dist 部署约定（致 feat/dark-tower-p0）

> 2026-09-12，横屏三联线（main）与暗黑魔塔线（feat/dark-tower-p0）发生了一次 dist 部署层撞车。
> 本文档整理发现、已做的处理、以及后续协作约定。**feat 线下次 merge main 时请先读本文。**

---

## 一、发生了什么（撞车复盘）

两边在**互不知情**的情况下平行推进，且都动了 `assets/` + `1.0.0/1.0.1 manifest`：

| 工作线 | 做了什么 |
|---|---|
| main（横屏三联线） | CRC32 重哈希部署：`Standalone.lua → a25c4688`、新增 `Viewport.lua → 575a8348`、`Client.lua → 70026d12`、`ClientInput.lua → c00d41e7`，8 个 manifest 同步 hash/size |
| feat（暗黑魔塔线） | 也更新了 dist：`40b443cb` 内容换为横屏版 Standalone（等价实现，不同哈希文件名）、Client/ClientInput dist 指回**竖屏旧哈希**（`1ff10b2b`/`6f909522`，分叉早于 main 的 Client 横屏补丁）、**删除了 Viewport dist 文件**、manifest 全部 pretty-print（+9000 行/文件） |

**结果**：同一件事（横屏 Standalone 上 dist）做了两遍；Client/ClientInput dist 差点被回退成竖屏版；Viewport 差点丢失。

**已处理**（merge d6ecd97）：dist 层冲突全部以 main 的横屏 CRC 状态为准；scripts-src 层正常合并（无冲突，暗黑化与横屏互补）。合并后已验证：4 个横屏哈希文件与 manifest 条目完好。

---

## 二、协作约定（请共同遵守）

1. **dist 层（assets/ 与 1.0.0、1.0.1 的 manifest）只由 CRC32 管线生成，禁止手工直接改**
   - 流程：改 `scripts-src/` 源码 → 跑重哈希脚本（CRC32 前 8 位 = 文件名哈希，manifest 同步 hash/size）→ commit
   - 参考实现：main 仓库的 `patch_dist_horizon.py` 工作目录脚本（或将固化进仓库）
2. **manifest 保持紧凑单行格式**（与 Maker 管线产物一致）。feat 侧的 pretty-print 已在合并中收敛回紧凑版——如果需要可读格式用于调试，另存副本，不要提交格式化版（每文件 +9000 行 diff 会淹没真实变更）
3. **feat 线定期 `merge main`**：当前 feat 缺少 main 上的这些能力，merge 后才能看到：
   - Client/ClientInput 横屏（此前 feat 的 dist 把它们指回竖屏，是因为分叉时 Client 补丁还不存在）
   - core/Viewport.lua（三联视口）
   - 左右面板图标暗黑化（reddot/power 14 处）
4. **改名/删除 dist 文件前先对照 manifest**：确认没有其他条目引用，且变更会随合并影响所有工作线

---

## 三、需要两边一起解决的事项

1. **DarkIcon × 横屏三联整合验证**：DarkIcon 目前接入的是竖屏渲染路径的 TopBar/BottomNav/画廊；横屏三联（左功能/中主视图/右角色）下各面板的暗黑化观感未联调。main 已实跑验证三联渲染 + Lua 零错误，缺 DarkIcon 开启态的联合截图
2. **图标范围对齐**：main 已替换 `ICON_HD→reddot`、`ICON_ZDL→power`（8 模块 14 处）；`ICON_UP`、`UI_AN_*` 系列、`ICON_CZ_*`（城镇建筑入口）尚未矢量画——feat 的 B2 迁移如果会碰到这些，请基于 DarkIcon 扩展 painter，避免再引入贴图依赖
3. **联机回归**：Client 横屏仅在 loopback 验证过加载期；需要真实服务器环境回归（TapTap 容器）
4. **AnnouncementPanel 模式推广**：B2 的 drawNine 底板迁移模式如果推广到 LeftDock/CharacterPanel 等横屏面板，注意横屏下面板设计空间仍是 1080×2400（视口层已处理缩放），页面代码不需要感知横屏

---

## 四、技术速查（两边通用）

- **资源文件名哈希 = CRC32 前 8 位 hex**（引擎按 manifest 的 hash+size 校验）
- manifest 文件名里的哈希不是内容校验（改内容无需重命名文件）
- 8 个 manifest 必须同步改：`1.0.0/{455bc44a,a1b65461,origin,origin.b4}` + `1.0.1/{04bc0cdf,ff073c70,origin,origin.b1}`（分发版条目带 `groups`，origin 版带 `prefix:"../scripts"`）
- 新增文件：自造 22 位 uuid（base64url），分发版 `groups:["default","#blocking"]`
- 验证：融合目录 `/workspace/.tmp/rt_856061` + UrhoXRuntime（validate/screenshot）；H5 用浏览器 + CDP 截图（WASM 满载时 Playwright 常规截图会挂，走 `Page.captureScreenshot`）

---

## 五、当前基线

- main = `d6ecd97`（合并 feat 新提交后），tag `v1.1.0` 在此之前
- 线上 H5 = 横屏三联版（Client loopback 路径），已实测布局生效
- 验证基线：120 帧 validate Lua 零错误；缺失资源 `UI_ICON_JZ_HJ/SP/WQ.png` 为镜像部分导出（非代码问题）
