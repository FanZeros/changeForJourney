# versions — 版本历史(最新在最上面)

> ⚠️ GitHub Release `win64-v1.0.2` 上的 zip 为 2026-09-14 内容(462.5MB),落后当前代码——再交付前需用最新 dist 重打(见 electron-shell/README.md)。

| 版本 | 日期 | 摘要 |
|------|------|------|
| v2.30-workspace923 | 2026-09-23 | 从 workspace 开 workspace923，合入四人新角色 + 滚轮/右键/五语 + 职业标/Maker MCP。供本机测试，未推 workspace。 |
| v2.29-i18n-rightequip-tune | 2026-09-23 | 扩 HUD/城镇/配装五语词表；右键不可穿提示、已穿卸下、音效+Toast。分支 `feat/wheel-rightequip-i18n`。 |
| v2.28-wheel-rightequip-i18n | 2026-09-23 | 滚轮补齐 + 右键快速装备 + 顶栏远征等级 + 五语切换。 |
| v2.28-four-meme-heroes | 2026-09-23 | 接入老六/哈基米/加载中/高ping战士（替代立绘）。分支 feat/four-meme-heroes。 |
| v2.27-workspace-integrate | 2026-09-22 | 整合今天三线到 workspace：overlays 星图剔除+CharacterPower、docs 套装/六契/1.5竖屏天赋树、rename 远征文案。已推 origin/workspace。 |
| v2.26-rename-expedition | 2026-09-22 | 玩家可见文案：冒险等级→远征等级、冒险家→远征队员、冒险招募券→远征招募券、冒险日志/奖励→远征日志/奖励。内部键名不变。分支 `feat/rename-adventure-to-expedition`。 |
| v2.25-refactor-three-more | 2026-09-22 | Talent 减伤/复活、Church 槽位动画、Blacksmith 结果转发。Talent 1116 / Church 1004 / Blacksmith 1337。 |
| v2.24-refactor-four-extracts | 2026-09-22 | Church 输入/名单 + Talent 攻前/受伤 + Blacksmith 输入。Church 1060 / Talent 1315 / Blacksmith 1384。 |
| v2.23-refactor-church-draw | 2026-09-22 | ChurchPage drawPageImpl 抽到 ChurchDraw。ChurchPage 1416 / ChurchDraw 568。 |
| v2.22-drop-guild-shell | 2026-09-22 | 删版本不一致弹窗与公会 Handler/Service；城镇卸空回调。GuildConfig 排行保留。 |
| v2.21-drop-server-select | 2026-09-22 | 卸掉 StartScreen 选服条与 ServerSelectPanel；点击直接进游戏。 |
| v2.20-drop-mp-ui | 2026-09-22 | 删除公会页/选角/加载页等仅多人 UI；消息处理器解绑。 |
| v2.19-drop-multiplayer-shell | 2026-09-22 | 去掉多人入口，删除 Client/Server 联网壳；单机仍用 LocalActionBridge+server Handler。 |
| v2.18-gameaction-local | 2026-09-22 | 单机 sendAction 走 GameAction→LocalActionBridge，UI 不再加载 Client。 |
| v2.17-refactor-market-input | 2026-09-22 | Market 点击/拖拽/滚轮抽到 MarketInput。Market 1402。 |
| v2.16-refactor-town-draw | 2026-09-22 | Market/Blacksmith drawPageImpl 抽到 MarketDraw/BlacksmithDraw。Market 1589 / Blacksmith 1533。 |
| v2.15-refactor-four | 2026-09-22 | onAfterAttack/ClientUpdate/BattleScenePhases + 市场商品卡/铁匠装备槽。TalentManager 1728 / Client 1348 / BattleScene 1765。 |
| v2.14-merge-workspace | 2026-09-22 | 合并 origin/workspace（中缝C款/ICON_UP/礼拜堂标签/ZBBJ/791 meta）。冲突仅 Standalone.lua，SEAMBAR_ASPECT 补进 Horizon。@ fa7a775 |
| v2.13-refactor-server-town | 2026-09-22 | ServerEnterGame + BattleSceneTick + 城镇页 DrawUtil 委托。Server 1693 / BattleScene 1890。@ 24eb755 |
| v2.12-refactor-four | 2026-09-22 | 连击Combo + loadStage + TAL.update + ClientRender。TalentManager 2838 / Client 1844 / BattleScene 2014 / BattleCombat 1637。@ 88ccd19 |
| v2.11-refactor-casualty | 2026-09-22 | BattleScene 抽出死亡补位/胜负到 BattleCasualty；2384→2154。分支 refactor/extract-battle-overlays @ ebc1db4 |
| v2.10-refactor-clientboot | 2026-09-22 | Client 抽出启动接线到 ClientBoot；2487→2143。分支 refactor/extract-battle-overlays @ a9c2566 |
| v2.9-refactor-talents | 2026-09-22 | TalentManager 再抽 Alex/Elwyn/Sera/Suhua；3276 行。分支 refactor/extract-battle-overlays @ 3e9920f |
| v2.8-refactor-anim | 2026-09-22 | BattleCombat 抽出卡牌动画到 BattleCombatAnim；修 Lua5.4 `\!` 启动崩 + ETS 依赖。分支 refactor/extract-battle-overlays @ a3f6930 |
| v2.7-awk3 | 2026-09-18 | 觉醒 7 阶压成 3 阶：粗暴/机制/进化，旧档 1–3→1、4–6→2、7→3 |
| v2.6-awk-extra | 2026-09-18 | 超模技改成觉醒1/4/7解锁，不再默认自带 |
| v2.5-talent-rework | 2026-09-18 | 8 个主技能按梗人设整段换机制 |
| v2.4-talent-rename | 2026-09-18 | 全员天赋改名+5 主技能机制对齐梗人设 |
| v2.3-electron-win | 2026-09-17 | Electron Windows 离线包：win-unpacked zip 461MB |
| v2.2-extra-talent | 2026-09-17 | 4 个混合追加技试点：衔骨图鉴/冰雕/分裂弹/预存复活 |
| v2.1-seam-back | 2026-09-17 | 三行模式隐藏页内重复返回键，只留中缝层 |
| v2.1-workspace | 2026-09-17 | 新工作区检出 origin/workspace@d790dc0；已 build 单机；等用户指令 |
| v2.0.1-electron-release | 2026-09-14 | Electron zip 462.5MB 覆盖上传 GitHub Release win64-v1.0.2（含暗黑建筑五件套/骷髅头Boss/阵亡紧凑/击杀进度%） |
| v2.1-wip | 2026-09-13 | 暗黑强梗试点(#4/#5)完成待验收;三层参考管线确立;交接文档部署 |
| v2.0 | 2026-09-13 | 卡面/立绘 v1 全量实装(浅灰白背景版,用户验收未通过);入队台词调研挂起 |
| v1.9 | 2026-09-13 | 名字二轮(黄桃龙/阿姨压/小黑子/真布诗人)+20 称号玩梗化+远征长替换 |
| v1.8 | 2026-09-13 | 对话全量重写(战斗 24 角色+剧情 73 情景)+"汪"→"叫!" |
| v1.7 | 2026-09-13 | 外祖父遗产信(LetterIntro)实装+世界观修正+视觉精修 |
| v1.6 | 2026-09-13 | 世界大背景(全窗口+7 页背景+27 关卡图)统一 |
| v1.5 | 2026-09-13 | 暗黑标题页(DarkTitleScreen 终焉之门版)上线,游戏内实拍验收通过 |
| v1.4 | 2026-09-13 | A 方案实装(#9/#11/#21 立绘+卡面),高清立绘导出管线 |
| v1.3 | 2026-09-13 | 20 张玩梗立绘三批生成(全部达标),双参考管线+暗黑前基准图 |
| v1.2 | 2026-09-12 | 角色总览图(引擎渲染);资产盘点(KTX 发现) |
| v1.1 | 2026-09-12 | 玩梗改名全量(20 角色+台词+剧情)+文本一致性 |
| v1.0 | 2026-09-12 | 玩梗匹配方案(联网调研)+用户拍板 |
