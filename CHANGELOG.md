# changeForJourney 项目改动记录与规划

> 宿命旅途（TapTap 856061）H5 化 + 横屏 PC 多面板改造的完整记录。
> 仓库：https://github.com/FanZeros/changeForJourney
> 线上：https://fanzeros.github.io/changeForJourney/
> 更新：2026-09-13

---

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
| `6306bf1` | **图标大小写修复**：UI_icon_JZ_FS 资源名（大小写敏感文件系统加载失败） |
| `e6edf29` | **暗黑魔塔 P0 起步**：DarkIcon 暗黑矢量图标库（Palette 色板单一来源）+ TopBar/BottomNav 接入 + 新旧对比画廊验收页 |
| `d23b739` | **矢量九宫格 B1**：DarkIcon.drawNine 面板体系（panel/plain/btn/slot/fill 五样式）+ 画廊九宫格区块 |
| `e17bcae` | **补齐横屏源码**：Client/ClientInput 横屏改造源码此前仅 dist 重哈希产物入库，源码遗漏同步 |
| `d861ad9` | **B2 首模块**：AnnouncementPanel 迁移 drawNine(panel) 矢量底板 + 正文文字色适配暗底 |
| `e201815` | **左右面板图标暗黑化 P1**：8 模块 ICON_HD→DarkIcon.reddot、ICON_ZDL/IMG.power→power（14 绘制点），页面打开实跑验证 Lua 零错误 |
| `6d8769b` | **协作约定**：docs/COLLABORATION.md——dist 部署撞车复盘、CRC32 管线约定、待共同解决事项 |
| `89af358` | **视口修复**：Viewport 面板补 DS=0.45 内容缩放（原本只显示设计稿左上角）+ RewardPopup nvgScissor 改 intersect 封住物品逃逸面板 |
| `9a7d9c8` | **三联无缝拼接**：BASE 1458 = 3×486，去除面板间隔与两侧留边 |
| `f2f81f8` | **弹窗聚焦**：中面板有模态弹窗时压暗左右面板（渲染顺序重排：侧栏先于中板） |
| `a95642b` | **启动全量预载**：config/AssetManifest.lua 全量图片清单分帧装载 + 全局贴图去重包装 + 加载进度遮罩（横/竖屏） |
| `fdba785` | **卷轴图标大小写修复**：UI_icon_JZ_WQ/HJ/SP（预载体检发现的同族问题） |
| `9f78bd4` | **回滚纠偏**：撤销 dist 直改部署（1.0.2 直加目录 + latest 指向劫持，违反 COLLABORATION.md 约定一），改走 CRC32 管线重新部署 |
| `4211a02` | **预载修复**：自适应字节预算（250MB 超限转惰性）+ 修复清单丢失 image/ 前缀导致 742 次加载失败 |
| `ed34825` | **角色改名**：25 个配置/战斗/系统文件（卡琳→大狗嚼、麦琪→奶龙龙、琳达→叮咚鸡等），与本地实跑版本一致 |
| `eb89cec` | **暗黑魔塔 P0 上线**：DarkIcon 矢量图标 + 暗黑化 UI + 三联无缝 + 角色改名 + 预载清单，CRC32 重哈希部署（ba10ce0 merge 入 main） |
| `7e4e2a0` | **资产修复**：3 张 16bit PNG（立绘对照/卡面对比/玩梗全家福）转 8bit 消除纹理创建报错；清单更新至 743 项 |
| `2bf8fca` | **横屏暗黑标题 DarkTitleScreen**：H5 启动即见标题（LOGO 呼吸 + 余烬粒子 + 轻触继续），补上 H5 标题仪式感 |
| `7710400` | **sw-coop 引擎静态资源本地缓存**：SW Cache Storage 缓存优先（命中秒出）+ 后台 ETag 条件请求校验（对策 CDN max-age=5），引导阶段明显提速 |
| `b07261a` | **预载防冻结**：开始/标题画面保持可交互（点击即转惰性）+ 遮罩覆盖标题层 + 30s 总时限；清单剔除 21 张设计稿（735 项/459MB） |
| `e903835` | **三段式加载**：前台只预载 80MB 核心 UI，剩余小图后台每帧 3ms 无感补载，>1MB 大图保持惰性；常驻显存 507MB→81MB |
| `81c8e08` | **横屏共享大背景**：core/HorizonBg 左右面板各显城镇大图一半（虚拟 2160×2400 连续画布），中面板战斗保持独立背景；CharacterPanelDraw 更名 Draw2（绕开构建 LSP 冻结缓存） |
| `75ff1e3` | **先祖来信 LetterIntro**：首登开场剧情——标题后、睁眼前的继承信（7 段逐行显墨 + 火漆印「宿」，轻松带梗版）；入包新增 8 manifest 条目（`47d53af`） |

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

### 3.3 横屏三联布局（已实现 · 无缝拼接版）

```
1920×1080，三联无缝：BASE 1458 = 3×486（去除面板间隔与两侧留边，逻辑分辨率等比缩放居中）
每面板 = 1080×2400 × scale 0.45（高度占满）
左 = 功能经营（城镇 + 市场/铁匠/教堂/酒馆/竞技场/公会），背景 = HorizonBg 城镇大图左半
中 = 主视图（BottomNav：角色/日志/战斗/副本 + 全屏战斗页 + 全局弹窗层），战斗保持独立背景
右 = 角色固定，背景 = HorizonBg 城镇大图右半（与左半构成同一连续世界，虚拟 2160×2400 cover-crop）
模态弹窗出现时左右面板压暗聚焦（渲染顺序：侧栏先于中板）
```

- 页面代码**零改动**：Viewport.begin = `nvgSave + nvgTranslate + nvgScale(0.45) + nvgIntersectScissor`，面板内就是原 1080×2400 坐标系（89af358 补上 DS=0.45 内容缩放，修复只显示设计稿左上角的问题）
- 输入：`Viewport.hit` 面板命中 + 坐标逆变换；ClientInput 经 toDesign 单点改造 + effectiveTab()（左面板强制 Tab4、右面板强制 Tab1、中面板随 BottomNav）
- `H_SKIP_START=true`：StartScreen.skipForReconnect() 跳过竖屏开始画面；横屏标题由 DarkTitleScreen 补上（见 3.6）
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
| 清单路径缺前缀 | 预载 742 次加载失败 | AssetManifest 条目必须写完整逻辑路径 `"image/xxx.png"` |
| 16bit PNG | 纹理创建报错 | 转 8bit 后入库（预载体检揪出 3 张，见 7e4e2a0） |
| dist 直改 | 绕过 CRC32 管线手工改 assets/manifest，造成多线撞车与回退事故 | 一律走重哈希管线，约定见 docs/COLLABORATION.md（9f78bd4 已回滚直改） |

### 3.5 三段式预载（一次性加载管线）

- **config/AssetManifest.lua**：工具生成的全量图片清单（735 项，按字节升序，已剔除设计稿/美术参照 21 张/459MB）
- **FG 前台**：进游戏前只预载 80MB 核心 UI 小图（进度遮罩；点击画面即结束前台预载转后台；30s 总时限防冻结）
- **BG 后台**：剩余小图每帧 3ms 无感补载；>1MB 大图保持惰性（首次引用才加载）
- **全局贴图去重包装**：预载与各模块 init 共用同一 nvg 图片句柄，避免重复解码——常驻显存 **507MB → 81MB**
- 启动预载预算自适应：250MB 超限自动降级为惰性（4211a02）

### 3.6 sw-coop 引擎静态资源缓存 + 启动流程

- **缓存**：tapcode CDN 对引擎文件（index.min.js / UrhoXRuntime.wasm / .data / engine-res / official-res）只给 `max-age=5`，每次进游戏都要重拉。sw-coop.js 对 `tapcode-sce.spark.xd.com/src/` 前缀启用 SW Cache Storage **缓存优先**（命中秒出）+ 后台 `no-cache` 条件请求（ETag 304 代价极小）跟进版本更新；更新生效延迟一次访问
- **H5 启动流程（现版）**：sw-coop 注入 COOP/COEP → 引擎 CDN（SW 缓存优先）→ 引擎 skipping login → Client loopback → 三段式预载（进度遮罩）→ **DarkTitleScreen** 横屏暗黑标题（LOGO 呼吸 + 余烬粒子，轻触继续）→ **LetterIntro** 先祖来信（仅首登，7 段逐行显墨 + 火漆印，1080×2400 letterbox）→ IntroCutscene 睁眼过场 → 主界面

---

## 四、横屏改造规划与进度

### 已完成（阶段 0-2 + Client 同步 + P0 联合上线）

- ✅ core/Viewport.lua 视口抽象（注册/变换/裁剪/命中/逆变换）
- ✅ Standalone.lua 三联渲染 + 输入路由（原生实跑验证：Lua 零错误 + 截图确认）
- ✅ Client.lua + ClientInput.lua 同步改造（H5 实跑验证：横屏布局生效截图确认）
- ✅ CRC32 重哈希部署管线（patch_dist_horizon.py 可复用；dist 直改已被回滚并立约，见 docs/COLLABORATION.md）
- ✅ 三联无缝拼接（BASE 1458 = 3×486）+ Viewport DS=0.45 内容缩放修复 + RewardPopup 裁剪修复
- ✅ 弹窗聚焦：模态弹窗时压暗左右面板
- ✅ **暗黑魔塔 P0**：DarkIcon 矢量图标库 + TopBar/BottomNav 暗黑化 + 左右面板 8 模块图标暗黑化（14 绘制点）+ AnnouncementPanel drawNine 迁移（详见 docs/暗黑魔塔改造总体方案.md）
- ✅ **三段式预载**：前台 80MB + 后台无感补载 + 30s 时限（常驻显存 507MB→81MB）
- ✅ **DarkTitleScreen** 横屏暗黑标题 + **LetterIntro** 先祖来信首登剧情
- ✅ sw-coop 引擎静态资源本地缓存（引导提速）
- ✅ core/HorizonBg 左右面板共享城镇大背景

### 待做（按优先级）

1. **暗黑魔塔 B2 剩余迁移**：MailPanel → ArenaLogDialog → ArenaShopPage → BackpackPanel（400 带大面板）等，逐模块截图对比 + validate
2. **暗黑魔塔 B3-B5**：按钮体系铺开（btn 替换 UI_AN_*）→ 地图压暗滤镜 → 其余面板清尾；P2 卡牌/装备/天赋（详见 docs/暗黑魔塔改造总体方案.md §五）
3. **阶段 3 面板交互打磨**：面板头部条（标题/切换/交换/临时放大）；左右面板的二级页返回栈
4. **阶段 4 联机回归**：真实服务器环境（TapTap 容器）回归 Client 横屏；目前仅 loopback 验证
5. **二期会话化**：页面模块 `state.open` 单例 → 每面板 UI 会话（支持同一页面多面板打开）
6. **弹窗全局化二期**：弹窗从"中面板空间"提升为全窗口浮层（需重设计弹窗坐标基准；压暗聚焦已做，坐标基准未动）
7. **战斗页横屏适配**（可选）：BattleScene 重设计为横屏布局（当前保持竖屏居中 + 独立背景）
8. **Right 面板内容核实**：CharacterPanel 未 open 时的绘制内容偏场景图，需确认角色属性面板的呈现路径

### 已知一期限制

- 弹窗为模态且绘制于中面板空间（左右面板交互触发的弹窗也出现在中面板；已做左右压暗聚焦）
- 同一页面同时只能在一个面板打开（页面模块单例状态）
- StartScreen/Loading 仍为竖屏画布居中（横屏标题仪式感已由 DarkTitleScreen 补齐，LetterIntro 首登走 letterbox，Loading 未动）
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
#    ⚠️ 禁止直改 assets/ 或 manifest（9f78bd4 教训），约定见 docs/COLLABORATION.md

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
