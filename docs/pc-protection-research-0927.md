# PC 发行包代码保护

> 描述当前打包架构下的保护现状与可选手段。上游现状见 `electron-shell/README.md`。
> 本文只描述方案与结论，不记录实施过程。

## 1. 架构与攻击面

当前链路：Maker Build → `dist` → Electron `extraResources` → 本机 http server → WASM Lua VM。

| # | 事实 | 出处 |
|---|------|------|
| A | Lua 以明文源码进入 `dist/assets/{uuid}-{hash}.lua`，UUID 文件名不构成保护 | `pack_release.py` / `electron-shell/README.md` |
| B | `pack_release.py:sync_dist()` 原样复制 `dist/` → `electron-shell/game/`，放入 `extraResources`（不在 asar 内） | `pack_release.py` |
| C | 运行时由 Electron 内置 Node http server 按 URL 直接 `sendFile` 明文 Lua | `main.js` |
| D | DevTools 可开：Network 面板可见每个 `.lua` 的完整响应体 | `main.js` |
| E | 官方 Build 的 LSP 检查依赖 EmmyLua `---` 注释，去注释产物无法通过正式 Build | 构建流程 |
| F | manifest 记录文件 hash/size，不能事后改 `dist/assets/*.lua` 内容 | 构建流程 |
| G | 引擎为 WASM Lua VM，是否接受 Lua 5.4 字节码未验证 | — |
| H | 游戏为离线单机，无可信服务端可托管逻辑 | — |

**威胁模型**：玩家侧拥有完整进程内存与文件系统。纯客户端方案的上限是提高逆向成本，不是保密。合理目标是让提取/改包不值得做、让存档作弊可检测，同时不破坏官方 Build。

## 2. 可选保护手段

### L0：明文（当前基线）

### L1：全量保守混淆（源码 → 源码，AST 级）
- 对局部变量/参数/局部函数做作用域安全重命名；可选字符串解码、常量折叠、死代码注入。
- **必须保留**：文件名、`require` 路径字符串、跨模块调用的对外字段名、全局引擎 API 名、EmmyLua `---` 注释（否则过不了官方 LSP）。
- 接入点在官方 Build **之前**：对源码副本混淆后跑官方 Build（不能「Build 原版、打包混淆版」，会撞 manifest 校验）。
- 风险中：重命名 bug = 运行期炸；需全量回归后再放行。

### L2：Lua 5.4 字节码
- 在 L1 产物上编译为字节码，攻击者失去变量名与结构。
- **未验证前提**：WASM Lua VM 是否接受字节码 chunk；官方 Build 是否允许字节码进 manifest（与事实 F 的 hash 校验冲突需先确认）。
- 风险高：字节码与 Lua 版本/字长/endianness 绑定，引擎升级即碎。

### L3：静态加密 + 主进程内存解密
- `game/assets/*.lua` 落盘为密文；`main.js` 的 `sendFile` 对 `.lua` 请求先解密再响应。密钥由混淆后的 `main.js` 持有。
- 效果：解包得到密文，挡住「拖出来就是源码」；配合发布版关闭 DevTools 再挡住 Network 面板提取。
- 与官方 Build 的关系：加密发生在 `sync_dist()` 之后、electron-builder 之前，不改 `dist`、不改 manifest。
- 风险低-中：黑屏自愈逻辑需覆盖解密失败分支；视频 Range 请求与解密并存时仅对 `.lua` 整文件解密。

### L4：完整性自校验（防改包/防存档注入）
- 打包时生成签名清单；启动时抽验；存档增加 HMAC（密钥在客户端，只能防随手改 JSON）。
- 对作弊有一定效果，对逆向无效。

### 不推荐 / 不可行
- 改 WASM 引擎本体：需引擎源码与官方配合，超出项目权限。
- 服务端托管逻辑：离线单机形态无服务器。
- 直接文本替换 `dist/assets/*.lua`：破坏 manifest。
- v8 snapshot / asar 加固：只保护 Electron 壳 JS，与 Lua 无关。

## 3. 当前结论

- **L1 已实现**为三档（见 `pc-obfuscation-similarity-0928.md` 与 `electron-shell/README.md`）：局部改名 + `@param` 同步（默认）、叠加剥注释、叠加私有字段改名（实验）。默认档过官方 Build、行为等价抽样通过、`@param` 残留为 0。
- **字段/方法改名收益低**：行级相似度仅再降约 1 个百分点；风险（动态访问、离线不可测的引擎依赖文件）不成比例，默认关闭。
- **L2 字节码是把行级相似度压向 0 的唯一手段**，但依赖 WASM VM 与 manifest 校验两项前提，需在真实打包环境验证。
- **L3 静态加密 + 关 DevTools** 是性价比最高的「防拖包」手段，接入 `pack_release.py` 的 `--protect` 开关（默认关）。

## 4. 约束自检

- 所有接入点都在源码副本或打包期，不改仓库源码与 `dist/`。
- L1 保留 EmmyLua 注释以满足官方 LSP/Build。
- 不直接改 `dist` 内容以避开 manifest 校验。
