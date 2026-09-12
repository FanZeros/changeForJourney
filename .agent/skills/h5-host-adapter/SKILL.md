---
name: h5-host-adapter
description: >
  MineEmpire / H5 小游戏静态适配层规范。记录已落地的宿主隔离、启动门控、激励广告等待、
  存档恢复、移动 WebView 兼容、低性能渲染和转生增益保留。
  Use when users need to (1) 适配 TapTap / Android WebView / Electron 宿主,
  (2) 修复启动花屏、健康游戏忠告叠字、空白初始化, (3) 接入或排查激励视频首次点击失败,
  (4) 处理损坏存档、转生后增益消失, (5) 做手机端 HUD/性能/旧 WebView 兼容,
  (6) 查看 MineEmpire 已完成的静态适配层，而不是重新发明一套。
---

# H5 宿主静态适配层

这是一份**已落地**的静态规范，不是待实现计划。后续改启动、广告、存档、移动端兼容时，先对照这份文档，再改代码。

参考实现：`/workspace/MineEmpire`

广告底层接口细节仍看 `h5-ad-integration`。本 skill 只写**业务适配层**：如何等待、如何隔离宿主、如何恢复、如何不卡死玩家。

---

## 适配层职责

把游戏逻辑和不稳定宿主隔开。游戏代码只面对稳定接口，不直接碰原生桥、宿主 DOM、损坏存档。

```
游戏 UI / Zustand store
        |
        v
静态适配层
  - 启动门控与 CSS 隔离
  - 广告服务 (adService)
  - 存档 normalize / hydration
  - 移动端 API 兜底
  - 低性能渲染开关
        |
        +-- TapTap H5 (window.tap)
        +-- Android WebView (window.HWGOEA)
        +-- Electron IPC (window.electronAPI)
        +-- 浏览器 localStorage
```

原则：

- 宿主异常不能阻止游戏挂载。
- 广告失败不能让第一次点击直接失败；服务层负责等待和重试。
- 存档损坏不能静默空白；要有 loading / ready / error。
- 转生重置进度，但不要清掉玩家刚看广告买到的限时增益。
- 手机旧 WebView 缺 API 时降级，不要抛错。

---

## 1. 启动门控与宿主 CSS 隔离

### 问题

TapTap / 健康游戏忠告等宿主 DOM 可能插在 `#root` 外面。如果全局 `*` / `body` 套了像素字体和游戏背景，宿主文字会乱码、叠字。React 若在字体、overlay、布局稳定前就显示，会出现“只渲染一小块 UI”。

### 落地做法

`index.html`：

- `#root` 默认 `opacity: 0; visibility: hidden`
- 只有 `html[data-app-ready="true"]` 才显示游戏

`src/styles.css`：

- 游戏字体、像素化、边框色只作用在 `#root, #root *`
- `html, body` 只保留底色和 overflow，不污染宿主节点

`src/main.tsx`：

1. 先 `flushSync` 挂载 React，保证首帧已渲染但不可见。
2. 等 `document.fonts.ready`（失败不阻塞）。
3. 检测 body 直属大尺寸可见节点，视为宿主 overlay，最多等 30s。
4. 再等两帧 `requestAnimationFrame`。
5. 设置 `document.documentElement.dataset.appReady = "true"`。

### 规则

- 不要用全局 `* { font-family: 像素字体 }`。
- 不要在样式稳定前显示 `#root`。
- overlay 检测只看 **body 直属子节点**，排除 `#root` 和 `SCRIPT`。
- 字体加载失败必须放行，不能永久黑屏。

### 已知限制

几何启发式可能把大型非 overlay 节点误判为加载层，最多卡住约 30 秒。后续若宿主提供明确 selector / 回调，优先改用协议，而不是再放宽面积阈值。

---

## 2. 激励广告适配层

实现：`src/services/adService.ts`

### 平台优先级

1. TapTap H5：`window.tap.createRewardedVideoAd`
2. Android：`window.HWGOEA`
3. 无桥：`none`，调试环境 `showRewardAd()` 直接返回 `true`

### 业务层禁止做的事

- 点击前用 `isRewardAdReady()` 提前拒绝。第一次几乎总是未就绪。
- 业务自己 `load()` + 立刻 `show()`。
- 用户关广告后还自动重试（会变成强制观看）。

业务只做：

```ts
const rewarded = await showRewardAd();
if (rewarded) grantReward();
```

等待、稳定、重试全部放进 `adService`。

### 等待策略

| 常量 | 值 | 作用 |
|------|----|------|
| `AD_READY_TIMEOUT_MS` | 30s | 总等待上限 |
| `AD_READY_POLL_MS` | 250ms | 轮询间隔 |
| `AD_READY_STABLE_MS` | 1s | ready 后还要稳定 1 秒 |
| `ANDROID_POST_LOAD_WARMUP_MS` | 1.5s | Android 强制 reload 后预热 |
| `ANDROID_LOAD_THROTTLE_MS` | 1s | 避免狂刷 load |

`waitForRewardAdReady()`：ready 必须连续稳定 `AD_READY_STABLE_MS`，中途变 false 就清零重计。

### H5

- 广告实例单例，不要每次点击新建。
- `show()` 失败：`load()` → 等稳定 → 再 `show()`。
- 只在 `onClose({ isEnded: true })` 时发奖。
- 播放结束后延迟 1s 预加载下一条。

### Android

- `initAndroidRewardAd()` 幂等，可重复调用。
- 结果字符串原样保留：`rewarded` / `closed` / `failed:not_ready` / `failed:timeout` / `failed:busy` / `failed:exception`。
- 第一次 `failed:not_ready` 等加载失败：强制 load → 预热 1.5s → 再等稳定 ready → 再 show。
- `closed` 和 `failed:busy` **不重试**。
- 回调超时 30s。
- `onRewardAdResult` 必须在 show 前注册好。

### 广告与玩法的关系

| 入口 | 是否可选 | 奖励 |
|------|----------|------|
| 增益站自动挖矿 | 可选 | 12 小时自动挖矿 |
| 增益站 ×2 速度 | 可选 | 3 小时挖掘速度 ×2 |
| 离线奖励翻倍 | 可选 | 离线收益 ×2；无“放弃”按钮 |
| 转生双倍碎片 | 可选 | 世界/现实转生碎片 ×2 |
| 每日任务三倍 | 可选 | 看完才发三倍 |

正常玩法永远可走，不看广告也能挖矿、转生、领离线。

广告位文案外侧保持克制，主矿场不要铺满“看广告”。增益放进独立“增益站”。

---

## 3. 存档与初始化适配层

实现：`src/state/game.ts`、`src/routes/play.tsx`、`electron/main.cjs`

### hydration 三态

```ts
hydrationStatus: "loading" | "ready" | "error"
hydrationError: string | null
```

`/play` 必须按状态渲染：

- `error`：存档无法读取 + “初始化游戏数据”
- `loading` 或未 mount：只显示 loading
- `ready`：才渲染矿场 UI

不要把 `useEffect(() => setMounted(true))` 当成存档已恢复。

### 自定义 merge，禁止默认浅合并

Zustand persist 默认浅合并会让 `resources: null`、`upgrades: {}` 直接覆盖默认值，随后 UI `.find()` / 展开对象会崩。

`mergePersistedGameState()` 必须：

- record 不是对象就回退默认
- array 不是数组就回退默认
- 数字非有限值回退
- `ownedTools` 非法时保留默认 `{ stick: true }`
- `reviewRating` 只接受 1–5
- 未知结构丢弃，缺字段补默认

损坏 JSON：`onRehydrateStorage(state, error)` 必须吃 `error`，切到 `hydrationStatus: "error"`。Zustand 失败路径**不会** `hasHydrated = true`，所以应用自己维护终态。

离线收益 `computeOfflineGain()` 包 try/catch，坏数据不能卡死启动。

### Electron 存档

- 写入：先写 `.tmp`，再 `rename` 到正式 json，避免断电截断。
- `hardReset` 必须 `await removeSave()`，确认 `true` 后再 `reload`。
- 删除失败展示错误，禁止立刻刷新把坏档再读回来。

Web 端 `localStorage.removeItem` 可同步，但也走同一套成功/失败语义。

### 转生 vs 重置

`reset()` 仍清广告增益，供“初始化游戏数据 / 完整重置”使用。

`worldRebirth` / `realityRebirth` 在 `reset()` 前快照：

```ts
adAutoMineUntil
adSpeedBoostUntil
```

重置后再写回。转生清进度，但限时广告增益按原到期时间继续走。

---

## 4. 移动 WebView 兼容

旧 Android WebView 常见缺口：

- `MediaQueryList.addEventListener` 不存在
- `ResizeObserver` 不存在

落地：

- `src/hooks/use-mobile.tsx`：有 `addEventListener` 用新 API，否则 `addListener` / `removeListener`。
- Canvas / 粒子层：先判断 `typeof ResizeObserver === "function"`，没有就退回 `window.resize`。

HUD / 弹窗：

- 窄屏用 `min-w-0`、全宽约束、内部滚动。
- 不要写死 `width: 400px` 的绝对卡片。
- 层切换器在手机上用 `left-2 right-2`，不要 shrink-to-fit 超出左边界。
- 碎片商城手机改纵向流：货币、天赋列表、永久加成从上到下，不要桌面双栏硬套。

炸弹：

- 工具栏按钮扩大热区。
- **更关键**：矿物按钮在 `bombMode` 时不要 `stopPropagation` 掉投放。点在矿上也应落到画布坐标并投弹。

---

## 5. 低性能渲染适配

实现：`src/lib/perfMode.ts`

自动开启条件（任一）：

- `prefers-reduced-motion: reduce`
- `deviceMemory <= 4`
- `hardwareConcurrency <= 4`
- 窄屏或粗指针：`(max-width: 768px), (pointer: coarse)`

用户设置可覆盖，并写入 `localStorage`。

性能模式下：

- Canvas DPR cap = 1（约 4× 填充量下降）
- 粒子数量 ×0.35，可跳过装饰 kind
- 登录页粒子 108 → 32
- 触摸设备不做鼠标视差
- 锤子光效 10 → 5
- Boss 血量数字可隐藏
- **粒子特效默认关闭**（新用户 / 无存档偏好）

不要把矿物改成完全不可点；先减 DOM/DPR，再考虑 canvas 化。

---

## 6. 接入检查清单

改宿主相关代码前过一遍：

启动

- [ ] 游戏样式只作用 `#root`
- [ ] `#root` 在 `data-app-ready` 前隐藏
- [ ] 字体失败不会永久隐藏
- [ ] `initAdService` 抛错不能阻止 `createRoot`

广告

- [ ] UI 不预检 `isRewardAdReady()`
- [ ] `showRewardAd()` 内部等待 + 稳定 + 一次重试
- [ ] 用户关闭广告不重试
- [ ] 不看广告也能完成核心循环

存档

- [ ] persist 使用自定义 merge
- [ ] hydration 有 loading / ready / error
- [ ] Electron 原子写
- [ ] hardReset 等待删除成功
- [ ] 转生保留广告增益时间戳

移动端

- [ ] matchMedia / ResizeObserver 有旧 API 回退
- [ ] 弹窗在窄屏可滚动且不溢出
- [ ] 炸弹能点在矿物上

---

## 7. 文件地图

| 文件 | 适配职责 |
|------|----------|
| `MineEmpire/index.html` | 启动隐藏 / `data-app-ready` |
| `MineEmpire/src/main.tsx` | 字体、宿主 overlay、reveal |
| `MineEmpire/src/styles.css` | `#root` 样式隔离 |
| `MineEmpire/src/services/adService.ts` | H5 / Android 广告等待与重试 |
| `MineEmpire/src/state/game.ts` | persist merge、hydration、转生保留增益 |
| `MineEmpire/src/routes/play.tsx` | hydration UI 门控 |
| `MineEmpire/electron/main.cjs` | 原子存档、IPC |
| `MineEmpire/electron/preload.cjs` | `electronAPI` |
| `MineEmpire/src/lib/perfMode.ts` | 低性能检测与 DPR cap |
| `MineEmpire/src/hooks/use-mobile.tsx` | 旧 matchMedia |
| `MineEmpire/src/lib/particles.ts` | 粒子默认关闭 |

测试：

- `src/services/__tests__/adService.test.ts` — 首次 `failed:not_ready` 后重试成功
- `src/state/__tests__/save-migration.test.ts` — 坏结构回退、损坏 JSON 进 error
- `src/state/__tests__/rebirth.test.ts` — 转生保留广告增益

---

## 8. 不要再踩的坑

1. 第一次点广告就提示失败：业务层预检 ready，或 show 前没等稳定。
2. 启动花屏 / 健康忠告叠字：全局 CSS 污染了宿主 DOM。
3. 部分玩家一直转圈或空白：损坏存档被浅合并，或 hydration error 被忽略。
4. 点“初始化”后问题还在：Electron `removeSave` 没 await 就 reload。
5. 转生后 12h 自动挖矿没了：`reset()` 清了 `adAutoMineUntil`，转生没恢复。
6. 手机点进矿场直接崩溃：`addEventListener` / `ResizeObserver` 未兜底。
7. 炸弹点不出来：矿物 `stopPropagation` 吞掉了投放点击。

---

## 9. H5 商店物料

H5 包不要直接复用 Steam/桌面原图标和 Banner。名称按「原游戏名 + H5」，例如「矿业帝国H5」。

全部正式文件放 `game_material/`，生成后默认再复制一份到 `assets/image/` 方便预览。

### 图标

- 模型：GPT Image（`model: gpt`）
- 尺寸：`1:1`，输出 `512x512`
- 参考图：现有方图标，如 `MineEmpire/src/assets/_steam_icon_source.png`
- 只加右下角金色 `H5` 角标，不重绘主体
- **商店页禁止白边/浅色透明边**：四角不能露白，不能半透明浅边。圆角外用深色不透明像素填满，整图 alpha=255
- 生成后若仍有白角或透明衬底，合成到深蓝底 `(18,14,48)` 再导出

### Banner

- 模型：GPT Image（`model: gpt`）
- 尺寸：`16:9`，输出 `1920x1080`
- 参考图：现有横版头图 + Logo
- 主标题写成「矿业帝国H5」，H5 跟在游戏名后面同一行，不是右下角小标
- 画面铺满，四周深色矿洞，不要白边、不要透明边、不要留白

### 落地文件

| 用途 | 路径 |
|------|------|
| 正式 H5 图标 | `MineEmpire/game_material/icon-h5.png` |
| 正式 H5 Banner | `MineEmpire/game_material/banner-h5.png` |
| 预览副本 | `assets/image/icon-h5.png`、`assets/image/banner-h5.png` |

复制命令：

```bash
cp MineEmpire/game_material/icon-h5.png assets/image/icon-h5.png
cp MineEmpire/game_material/banner-h5.png assets/image/banner-h5.png
```

桌面/Steam 仍用原图；H5 / TapTap 小游戏商店用带 H5 名称的图标和 Banner。
