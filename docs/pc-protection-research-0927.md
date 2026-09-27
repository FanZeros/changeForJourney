# PC 发行包代码保护强化调研（2026-09-27，`feat927/ele-protection-research-0927`）

> 状态：**纯调研文档，未改动任何打包流水线**。上游现状见
> `electron-shell/README.md`（2026-09-24 审核 + 2026-09-27 全量压缩试点）。
> 本文回答一个问题：在当前「Maker Build → dist → Electron extraResources → 本机
> http server → WASM Lua VM」的架构下，**还能把保护做到多强、每一步的代价和验证方式是什么**。

---

## 1. 现状与攻击面盘点（事实，来自本分支代码）

| # | 事实 | 出处 |
|---|------|------|
| A | 361 个 Lua 以**明文源码**进入 `dist/assets/{uuid}-{hash}.lua`，UUID 文件名 + zip 不构成保护 | README「PC 发行包代码保护现状」 |
| B | `pack_release.py:sync_dist()` 原样复制 `dist/` → `electron-shell/game/`，electron-builder 放入 `extraResources`，**不在 asar 内**，解包零门槛 | `pack_release.py` |
| C | 运行时由 Electron 内置 Node http server（`main.js:103`）按 URL 直接 `sendFile` 明文 Lua（MIME `text/plain`） | `main.js:48,63-101` |
| D | **F12 可开 DevTools**：Network 面板能看到每个 `.lua` 的完整响应体，等于官方提供提取器 | `main.js:172-176` |
| E | 已有 `obfuscation_trial.py`：单模块改名试点 + 全量「去注释/压缩排」试点（-22.6% 体积），均只在隔离目录，未接入发行；处理后仍是**可读明文** | README「全量隔离压缩试点」 |
| F | 官方 Build 的 LSP 检查依赖 EmmyLua `---` 注释；直接删注释的产物无法通过正式 Build（大量 `undefined-global`） | README 试点小节 |
| G | manifest 记录文件 hash/size，**不能事后改 `dist/assets/*.lua` 内容**，否则破坏资源加载/校验 | README「不要直接对 dist 做文本替换」 |
| H | 引擎是 WASM Lua VM（UrhoX web runtime，打包时从官方 CDN 镜像），是否接受 **Lua 5.4 字节码**未验证；`string.dump`/`load` 在该 VM 内是否启用未知 | README + `pack_release.py` CDN 镜像逻辑 |
| I | 游戏为**离线单机**（登录已被 WS shim 跳过），不存在可信服务端可以托管逻辑 | README「运行行为」 |

**结论（威胁模型）**：玩家侧拥有完整进程内存与文件系统。任何纯客户端方案的
上限都是「提高逆向成本」，不是「保密」。真正需要保密的东西（未来若有排行榜
校验、内购发货、防作弊）只能走服务端；当前离线单机形态下，合理目标是
**让 casual 提取/改包不值得做，让存档作弊可检测**，同时不破坏官方 Build 与热更流程。

---

## 2. 可选方案分级评估

按「强度递增、风险递增」排列。每级独立可用，也可叠加（推荐叠加顺序 L1→L2→L3）。

### L0（现状）：明文
略。

### L1：全量保守混淆（源码→源码，AST 级）
把现有 `--all-scripts` 的「去注释压缩」升级为**真正重命名**：

- 做法：Lua parser（如自写 5.4 语法解析或借助 Tree-sitter-lua）建 AST，
  对**所有 local 变量/函数参数/局部函数名**做作用域安全重命名（`a0,a1,...` 或
  无意义混淆名），可选：字符串字面量提取+运行期解码、常量折叠、
  死代码注入、控制流平坦化（激进，风险高，先不做）。
- **必须保留**：文件名、`require` 模块路径字符串、模块表对外字段名
  （`M.Get` 等被跨模块调用的 key）、全局引擎 API 名、EmmyLua `---` 注释
  （否则过不了官方 LSP，见事实 F）。即 L1 产物仍要能进正式 Build；
  **正确接入点是 Build 之前**：对源码副本混淆 → 用副本跑官方 Build
  （双轨「Build 用原版、打包用混淆版」会撞事实 G 的 manifest 校验，不可行）。
- 强度：★★☆（自动化工具可较大程度恢复结构，但足以挡住脚本小子；字符串解码后
  逻辑仍可读）。
- 风险：中。重命名 bug = 运行期炸。缓解：作用域分析必须处理
  upvalue/`...`/goto label/`_ENV`；每个混淆产物跑「60 帧启动 + 存档回归 +
  `scripts/tests/` 全量」再放行。
- 工作量：2-4 天（写混淆器 + 全量回归）。
- 参考实现：开源 **Prometheus**（Lua obfuscator，支持 rename/字符串加密/
  控制流），但它是 Lua 写的、对 5.4 + EmmyLua 注释保留需要验证；
  更稳的是在现有 Python 试点基础上自建 AST。

### L2：Lua 5.4 字节码（`luac`/`string.dump`）
- 做法：混淆后（L1 产物）再编译为字节码。攻击者失去变量名和结构，
  需要专门的 5.4 反编译器（存在，但比反混淆源码费劲一个量级）。
- **两个未验证前提（必须先做 POC）**：
  1. WASM Lua VM 是否接受字节码 chunk（`luaL_loadbuffer` 天然支持，
     但 web 构建可能裁剪/禁用，或用自定义 loader 只认文本）；
  2. 官方 Build 是否允许 `.lua` 资源内容以字节码形态进 manifest
     （Build 前有 LSP 检查，字节码过不了 LSP → 需要「Build 校验用
     文本、打包时替换、同步重算 manifest hash」——这与事实 G 冲突，
     必须弄清 manifest hash 是**引擎运行时强校验**还是仅打包期校验；
     若运行时强校验，替换后必须重写 manifest 的 hash/size 字段并确认
     引擎接受）。
- 强度：★★★（配合 L1 再 +1）。字节码≠加密，`unluac` 类工具对标准 5.4
  有效；可再叠一层「魔数/头尾字节扰动」让通用反编译器不识别（VM 侧需
  对应容忍——大概率不行，除非改引擎，故仅作为可选项记录）。
- 风险：高（平台/版本锁死：字节码与 Lua 版本、字长、endianness 绑定；
  引擎升级即碎）。
- 工作量：POC 0.5 天，接入 1-2 天（若前提成立）。
- **POC 步骤**（隔离环境）：
  1. 拿到打包后的 engine wasm 资产（`electron-shell/game/src/engine/`）；
  2. 在预览页 Console 里验证 VM 是否吃字节码：fetch 一个已知 lua 资源 →
     本地 `luac5.4` 编译 → 塞回同 URL 观察能否运行（或最小化：写一个
     `load(字节码)` 的入口脚本走官方 Runtime 验证）；
  3. 用 run-lua-validate 思路对字节码版 `scripts/` 跑 60 帧。

### L3：静态加密 + Electron 主进程内存解密（at-rest encryption）
- 做法：`game/assets/*.lua` 落盘为密文；`main.js` 的 `sendFile` 对 `.lua`
  请求**先解密再响应**。密钥不落地明文：由 `main.js` 混淆
  （javascript-obfuscator / bytenode 编译为 V8 字节码）+ 派生常量持有。
- 效果：解包 `extraResources` 得到的是密文 → 挡住「拖出来就是源码」这条
  最短路径；配合 **发布版关闭 F12 DevTools**（事实 D，必须做，一行改动）
  再挡住 Network 面板明文提取。
- 天花板：攻击者 dump 渲染进程内存 / 改 `main.js` 重开 DevTools 仍可拿到
  明文。属于「防君子不防小人」，但性价比极高。
- 与官方 Build 的关系：加密发生在 `pack_release.py:sync_dist()` 之后、
  electron-builder 之前，**不改 dist、不改 manifest**（manifest 在密文旁
  原样保留；引擎请求 → main.js 解密 → 引擎收到与 hash 一致的明文），
  绕开事实 G。⚠️ 需确认引擎是否在运行时对响应体做 hash 校验：
  若做，此方案天然兼容（明文一致）；若 loader 用 hash 做缓存 key，也不受影响。
- 强度：★★☆（静态）；配合关 DevTools + main.js bytenode ≈ ★★★。
- 风险：低-中。黑屏自愈逻辑（main.js 2s 重试）需覆盖解密失败分支；
  Range 请求（视频）与解密并存时，仅对 `.lua` 整文件解密、禁用其 Range。
- 工作量：1-2 天。

### L4：完整性自校验（防改包/防存档注入，而非防看源码）
- 做法：打包时对 `game/` 全量文件生成签名清单（私钥不进包，包内只放公钥
  或 hash 树根）；`main.js` 启动时抽验；Lua 侧存档增加 HMAC（密钥同样只能
  藏在客户端 → 只能防「随手改 JSON」，防不了有心人）。
- 强度：对作弊 ★★☆，对逆向 0。是否值得做取决于产品对单机改档的态度。
- 工作量：1 天。可选，优先级最低。

### 明确不推荐 / 不可行
- **改 WASM 引擎本体**（自定义字节码格式、VM 内解密）：需要引擎源码与
  官方维护配合，超出本项目权限。
- **服务端托管逻辑**：离线单机形态（事实 I），无服务器；未来若上 TapTap
  联机/云存档再评估。
- **直接文本替换 `dist/assets/*.lua`**：破坏 manifest（事实 G），已有结论，不再重复试验。
- **v8 snapshot / asar 加固**：只保护 Electron 壳 JS，与 Lua 无关；asar
  本身可 `npx asar extract`，不构成保护。

---

## 3. 推荐路线图

| 阶段 | 内容 | 前置 | 产物 |
|------|------|------|------|
| P0（半天） | 发布版关 F12/DevTools + 收敛 `main.js` 明文日志中的路径信息；**零成本高收益** | 无 | `main.js` diff |
| P1（1-2 天） | L2-POC：验证 WASM VM 是否吃 Lua 5.4 字节码、manifest hash 是否运行时强校验 | 本机 Windows 打包环境（云端代理传大 zip 会断，README 已有结论） | POC 报告，决定 L2 是否可行 |
| P2（2-4 天） | L1 AST 重命名混淆器（在 `obfuscation_trial.py` 基础上升级），接入点=官方 Build **之前**的源码副本；全量回归（60 帧 + 存档 + tests/） | 可与 P0 并行 | 混淆器 + 回归记录 |
| P3（1-2 天） | L3 静态加密 + main.js 内存解密 + main.js bytenode；接入 `pack_release.py` 新增 `--protect` 开关（默认关，不影响现有流程） | P2 产物作为加密输入 | 带保护开关的打包链 |
| P4（视 P1） | 若字节码可行：L1→L2 串联，密文形态换成字节码 | P1 PASS | 最终形态：AST 混淆 + 字节码 + 静态加密三层 |

**最终合理上限**：L1+L2+L3 ≈ 「需要专业逆向技能 + 动态调试才能还原逻辑」。
再往上（真保密）在纯客户端架构下不存在，如实标注，不做过度承诺。

## 4. 与既有约束的对照自检

- [x] 不改仓库源码 / `dist/`（所有接入点都在副本或打包期）
- [x] 不违反「manifest hash 不可事后改」（L3 在响应时解密，落盘密文与
      manifest 的关系在 P1 中验证；L1/L2 在 Build 前生效，manifest 天然一致）
- [x] 官方 LSP/Build 依赖 EmmyLua 注释 → L1 保留 `---` 注释
- [x] 基线已知故障（`StoryPlayer` 缺 `network.ClientDispatcher`、lootbox
      两处旧断言）不属于本调研引入，回归对比时以「与原版行为一致」为准
- [x] 不推 workspace 分支；本文档只进 `feat927/ele-protection-research-0927`
