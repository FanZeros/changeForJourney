# memory-index — 《终焉之门》改造完整交接文档

## 本地任务：启动卡顿优化（2026-10-07）

- 分支 `perf1007/startup-stutter`，功能提交 `c7974776`（基于5fca1d82），目标已滚动合入workspace1005截至56cfbd3c的最新提交。尚未正常push／创建PR；PR同源查询为空。未推workspace系列、不强推、不自动合并。
- 合入最新目标时记忆文档冲突已双保留；唯一重叠Lua `BattleTriPage.lua` 保留两侧改动：本轮 `preload` 的缓存与首屏背景预热，目标PR114真实battle-detail热点及卡片动画／存活检查。实测74素材断言过、引导5312断言过、教程入口17/474、Horizon1334等过。
- 当前已查到LSP：本轮生产改动文件零Error；`DungeonConfig.lua` 在目标新增功能行另有2条nilable `integer?`→`string|number` 既有/上游相关诊断，不属本轮改动。Build前仅存故意未暂存的 `.project/project.json` 与 `settings.json` 身份生成差异，需先恢复后Build。上次build成功的source payload针对c7974776的旧目标，还不是当前三方合并树，不作当前PR构建证明。
- 副本章节视觉测试已在最新树跑：全部章节绘制部分仍过，但16组中10失败，根因是严格mock未声明目标新增require `ui.battle.stage.ExpeditionOverview`（多组HARNESS_FAIL），以及一项200001固定预期与目标PR115成长数据实际值不符；相应整轮resource visual不通过。本轮未改目标生产/旧测试掩盖失败。后续如需修复需独立判断是不是目标PR115预期漂移，并覆盖真实行为。
- 最新目标56cfbd3c（PR115）：新增副本／通天塔经验与掉率、StageExpHelper，目标本身此前测试通过与否未在本任务验，Visual兼容失败留上述记录。TutorialRecruit部署及DungeonGuide在专用隔离目录断言全过并通过validate60帧；FocusedOnboarding 5312/0和validate PASS；resource visual validate的scene PASS但整体FAIL。已查输入单击：input真实同帧位移已验证、translate内命中与事件首帧复位，未扩做VR/CWD要求外的旁支。
- 与中间PR114 target5fca1d82四轮已验证A/B同SHA ec8fa4ca相同统计：标题Update wall峰448→167ms、图片回调峰42→2；title-ready等待5→118/119帧；Enter淡出Render425→172ms、letter Update470→4ms。战斗后段Update145→321ms、Render64→187ms反而上升；新接入教程界面/周边基础设施，不可直接把该A/B提升外推到最新56cf合并树。解码上限仍2；不宣称设备FPS或整体不卡。
- 官方Build与新功能PR仍待完成；远端URL干净使用存储凭据helper，PAT不得入命令行/配置/日志，用户已在聊天公开PAT需自行立即撤销轮换。Git提交作者Maker已配置。

## 已推PR交接：两段装备教程真实详情入口（2026-10-07）

- 教程独立分支 `feat1005/tutorial-character-detail-entry-20261007` 功能1eb0999be743e6d1f8a81538abe9d869966389a1 已正常push；PR #114 已创建，base workspace1005，后续已外部合并并继续前进。测试/实现路径与固定父、组合树分别核验；详见该提交历史。
- 组1真实战斗卡→角色详情→武器槽→仓库穿戴；组2真实队1头像→角色详情→一键装备。入口来源/英雄/打开与配装tab门控、实际卡片投影及身份按压防旧Up；不改存档字段/玩法。
- 专项17/474、Horizon199/1334、manager58、recovery69、roster60、targets66及其他六套专项通过；Focused5312/0及Recruit5159、DungeonGuide6183通过。旧Backpack 24失败在固定父同集合；seam旧4805仍有既有失败，不冒称全绿。详细失败口径见先前任务记忆。

## 已完成：启动卡顿首轮优化（原基线5fca1d82上的证据）

- `StartupQueue` 每帧单resume，4ms软墙钟预算/每帧2图片miss限制；19步全完成才ready，Stop丢弃未完worker。单图和纯CPU不可抢占，title等待显著延长；局部context守卫不意味着完整宿主支持同VM重启。
- Town19图／三行UI及存档背景／实际首场卡片按需前置；MAP_1与hero20星门仅有需求才读。BGM start7→1、SFX63→0，按需同步加载；战力通知重建/refresh去重，测试fixture context调用23→12／29→12。玩法、奖励、存档schema未改。
- Queue34、Audio762、HeroSync396、Assets74全部0失败exit0；BattleCard14、ProjectileArc原入口、host165通过（host夹具在隔离runner注入新增依赖，原165断言不变）。旧public3 / artifact harness / resource visual旧预期失败未隐藏。
- 官方旧树Build b11成功、571根Lua，17本轮Lua真实包逐字节一致；Build期间附属daemon LSP闸门不可用被跳过，但本轮修改Lua逐文件severity1无Error。
- 同版ec8fa隔离A/B四次运行：title Update墙钟峰448→167ms、回调解码42→2；title ready等待5→118/119帧；battle Update 145→321ms、battle Render64→187ms恶化。末尾构建后复跑title ready101、Update峰329ms，解码仍≤2；实验波动显著，只证明开始阶段拆峰，非稳定设备性能。
- 7日离线装备/遗匣大批生成与每秒/退出存盘成本均未改未测；下一阶段应首先补最新56cf树的完整Build、payload和目标回归，再确认首屏等待体验，并处理剩余渲染后段卡图。
