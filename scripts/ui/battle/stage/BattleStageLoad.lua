-- ============================================================================
-- BattleStageLoad - 关卡加载（原 BattleScene.loadStage）
-- 状态经 ctx 读写；调用方回写标量
-- ============================================================================

local MAS = require("systems.MapAffixSystem")
local Diag = require("systems.BattleDiag")
local BattleCombat = require("ui.battle.combat.BattleCombat")
local BattleEffects = require("ui.battle.combat.BattleEffects")
local ProjectileSystem = require("ui.battle.combat.ProjectileSystem")
local TM = require("systems.ThreatManager")
local SEM = require("systems.StatusEffectManager")
local RCH = require("systems.RelicConditionHandler")
local ART = require("systems.ArtifactRuntime")
local SpeechBubble = require("ui.widget.SpeechBubble")
local StageBerserk = require("ui.battle.stage.StageBerserk")

local M = {}

---@param ctx table
---@param stageId number
---@param skipBattleStart boolean|nil
function M.load(ctx, stageId, skipBattleStart)
    ctx.ensureBattleCards(ctx.vg_)
    local stageConfig = ctx.getStageConfig()
    local entry = stageConfig.getStage(stageId)
    if not entry then
        print("[BattleScene] 关卡不存在: " .. tostring(stageId))
        return
    end

    ctx.currentStageId = stageId
    ctx.stageName = entry.name
    -- 解锁进度兜底：能被加载的关卡必然已解锁。此前手动"前进"按钮在未通关时
    -- 直接 loadStage(nextId) 不推进 ctx.maxStageId_，导致当前关进度与解锁进度脱节
    -- （选关列表只显示到旧进度、扫荡弹窗识别不了当前关卡）
    if stageId > ctx.maxStageId_ then
        ctx.maxStageId_ = stageId
        ctx.recalcIdleIncome()
    end
    ctx.isFirstClear = not ctx.clearedStages[stageId]
    ctx.idleRangeText_ = nil  -- 关卡变化时重新计算挂机范围文本

    ctx.searchingTimer = nil
    ctx.defeatTimer = nil
    ctx.reincarnationTimer = nil

    -- 切关时重置波次计时（丢弃未完成波次数据）
    ctx.resetWaveTimers()

    -- 章节变化时切换地图背景
    -- 挂机模式：使用范围内最早（最低）章节的背景素材
    local bgChapter = entry.chapter
    if not ctx.isFirstClear then
        local stages = require("shared.StageUtils").collectPrevStages(ctx.maxStageId_, 5, stageConfig)
        if #stages > 0 then
            bgChapter = stages[#stages].chapter  -- 最低关的章节
        end
    end
    if bgChapter ~= ctx.currentChapter and ctx.vg_ then
        ctx.currentChapter = bgChapter
        if ctx.isFirstClear and entry.mapBg then
            -- 终焉神殿使用自定义地图背景
            ctx.setMapBackground(ctx.vg_, "image/关卡地图/" .. entry.mapBg)
        else
            -- 困难/噩梦/地狱复用普通难度地图：chapter 24+ 按 23 章循环映射
            local mapChapter = ((ctx.currentChapter - 1) % 23) + 1
            ctx.setMapBackground(ctx.vg_, "image/关卡地图/MAP_" .. mapChapter .. ".png")
        end
    end

    -- 生成全部敌人（挂机模式用5关混合，首通用单关卡）
    local allEnemies, maxField
    if not ctx.isFirstClear then
        allEnemies, maxField = ctx.generateIdleEnemyList()
    else
        allEnemies = ctx.generateEnemyList(entry)
        maxField = entry.maxFieldEnemies or 5
    end

    -- 前 maxField 个上场，其余入队列
    -- 特殊怪物（_isBonusMonster）占用 maxField 名额（避免超出屏幕），替换末位普通怪物
    -- [三行并行] 条带布局每侧最多 MAX_PER_SIDE(4) 张卡——挂机混合 maxField 保底 5，
    -- 超出槽位的怪 clamp 后会同槽叠卡（视觉上"两个敌人重叠"）；
    -- 上场数按布局槽位收缩，多余的留队列，由击杀补位机制（ctx.enemies[#ctx.enemies]=newUnit）进场
    if require("core.BattleLayout").MODE == "strip" then
        maxField = math.min(maxField, require("core.BattleLayout").MAX_PER_SIDE)
    end
    ctx.enemies, ctx.enemyQueue = ctx.assignEnemiesToField(allEnemies, maxField)
    ctx.stageEnemyTotal_ = #allEnemies
    ctx.stageKillCount_ = 0

    -- ---- 地图词缀：仅首通模式生效，挂机模式不应用 ----
    if ctx.isFirstClear then
        MAS.onStageLoad(entry.chapter, ctx.allies)
        if MAS.hasAffixes() then
            local allEnemiesToBuff = {}
            for _, u in ipairs(ctx.enemies) do allEnemiesToBuff[#allEnemiesToBuff+1] = u end
            for _, u in ipairs(ctx.enemyQueue) do allEnemiesToBuff[#allEnemiesToBuff+1] = u end
            MAS.applyStaticAffixes(allEnemiesToBuff)
        end
    else
        MAS.onStageLoad(0, ctx.allies)  -- 挂机模式：清除词缀
    end

    -- [EnemyGuard] loadStage 重置 guard（每次加载新关都允许再次报警）
    ctx._enemyGuardFired = false
    -- [EnemyGuard] loadStage 完成后验证 ctx.enemies 内容
    print(string.format("[EnemyGuard] loadStage stageId=%s enemies_len=%d enemies_ref=%s allies_len=%d",
        tostring(stageId), #ctx.enemies, tostring(ctx.enemies), #ctx.allies))
    for i, u in ipairs(ctx.enemies) do
        print(string.format("[EnemyGuard]   enemy[%d] monsterId=%s instanceId=%s heroId=%s hp=%s name=%s",
            i, tostring(u.monsterId), tostring(u.instanceId), tostring(u.heroId), tostring(u.hp), tostring(u.name)))
    end

    -- 安装哨兵（loadStage 路径，与 resetBattle 对齐）
    for _, u in ipairs(ctx.allies) do
        Diag.installSentinel(u)
    end
    for _, u in ipairs(ctx.enemies) do
        Diag.installSentinel(u)
    end
    for _, u in ipairs(ctx.enemyQueue) do
        Diag.installSentinel(u)
    end

    -- 重置战斗状态
    ctx.battleActive = true
    if ctx.isFirstClear then
        ctx.firstClearTimeLeft = require("config.GameConfig").Battle.TIME_LIMIT_SEC
    else
        ctx.firstClearTimeLeft = nil
    end
    BattleCombat.reset()
    BattleEffects.reset()
    ProjectileSystem.reset()
    TM.reset()   -- 清空仇恨表
    SEM.reset()  -- 清空状态效果
    RCH.initBattle(ctx.allies)  -- 初始化遗物条件词条（战斗开始时效果在此触发）
    ART.initBattle(ctx.allies)  -- 初始化神器战斗运行时效果
    for _, u in ipairs(ctx.allies) do
        u.atkProgress = 0
    end
    for _, u in ipairs(ctx.enemies) do
        u.atkProgress = 0
    end

    -- 入场动画（交错滑入）
    BattleCombat.playEnterAnims(ctx.enemies, -1)  -- 敌方从上方滑入
    BattleCombat.playEnterAnims(ctx.allies, 1)    -- 己方从下方滑入

    -- 重置台词气泡
    SpeechBubble.reset()

    if not skipBattleStart then
        -- 完整战斗启动：TAL/TM 初始化 + 入场台词
        ctx.startBattleTalents()

        -- [诊断] 战斗开始后即时完整性扫描
        Diag.scanNow(ctx.allies, ctx.enemies, "loadStage_postInit_s" .. tostring(stageId))

        local aliveHeroes = {}
        for _, u in ipairs(ctx.allies) do
            if u.hp > 0 and u.heroId then
                aliveHeroes[#aliveHeroes + 1] = u
            end
        end
        if #aliveHeroes > 0 then
            local speaker = aliveHeroes[math.random(#aliveHeroes)]
            SpeechBubble.trigger(speaker, "entry")
        end
    end

    -- 首通狂暴属于关卡加载状态，不应依赖 skipBattleStart。
    -- nextStage/reload/失败重进等路径会用 skipBattleStart=true 延后天赋启动，
    -- 但首通狂暴计时必须仍然在战斗恢复后正常推进。
    if ctx.isFirstClear then
        StageBerserk.enter(ctx.enemies, ctx.allies)
    else
        StageBerserk.exit()
    end

    ctx.recalcIdleIncome()

    print("[BattleScene] 加载关卡: " .. entry.name
        .. " | 场上: " .. #ctx.enemies
        .. " | 队列: " .. #ctx.enemyQueue
        .. " | 等级: " .. entry.monsterLevel)

    if ctx.onStageLoadedCallback then
        ctx.onStageLoadedCallback(stageId, ctx.isFirstClear)
    end
end


return M
