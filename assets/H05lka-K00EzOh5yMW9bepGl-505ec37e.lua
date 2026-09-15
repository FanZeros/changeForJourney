-- ============================================================================
-- SweepService - 扫荡业务逻辑
-- 职责: 扣除扫荡券，即时发放固定关卡收益（首通奖励×10）
-- 层级: server/sweep  |  通过 PDM 读写，禁止网络 IO
-- ============================================================================

local PDM             = require("server.character.PlayerDataManager")
local OfflineCalc     = require("systems.OfflineCalc")
local SC              = require("config.StageConfig")
local StageProvider   = require("shared.StageProvider")
local ExpTable        = require("config.ExpTable")
local LootBoxSystem   = require("systems.LootBoxSystem")
local HeroService     = require("server.hero.HeroService")
local StageUtils      = require("shared.StageUtils")
local IdleIncomeConfig = require("config.IdleIncomeConfig")

local SweepService = {}

-- 每次扫荡消耗的扫荡券数
SweepService.SWEEP_COST = 1
-- 扫荡收益 = 即时领取 N 分钟挂机收益（与挂机/离线统一走 IdleIncomeConfig）
SweepService.REWARD_MINUTES = 10
-- 扫荡固定掉落装备数
SweepService.EQUIP_DROP_COUNT = 10
-- 扫荡固定掉落卷轴数
SweepService.SCROLL_DROP_COUNT = 10
-- 扫荡覆盖的关卡数量
SweepService.SWEEP_STAGE_COUNT = 5

-- ======================== 执行扫荡 ========================

-- collectPrevStages 已提取到 shared.StageUtils（扫荡与挂机共用）
local collectPrevStages = StageUtils.collectPrevStages

--- 消耗 1 张扫荡券，平均扫荡记录关卡前 5 关，发放综合收益
---@param uid number
---@return boolean ok
---@return string|nil err
---@return table|nil result  { gold, heroExp, playerExp, equipCount, scrolls, stages }
function SweepService.Sweep(uid)
    local currency   = PDM.GetModule(uid, "currency")
    local battleData = PDM.GetModule(uid, "battle")
    local heroesData = PDM.GetModule(uid, "heroes")
    local playerData = PDM.GetModule(uid, "player")
    local lootbox    = PDM.GetModule(uid, "lootbox")

    if not currency or not battleData or not heroesData or not playerData or not lootbox then
        return false, "数据未加载"
    end

    -- 检查扫荡券是否足够
    local owned = currency.sweepTicket or 0
    if owned < SweepService.SWEEP_COST then
        return false, "扫荡券不足"
    end

    -- 以玩家最高进度关卡为基准，无论挂机在哪一关
    local stageConfig = StageProvider.GetForServer(PDM.GetServerId(uid))
    local maxStageId = battleData.maxStageId or battleData.currentStageId
    if not maxStageId then
        return false, "尚未开始冒险"
    end

    -- 收集前 5 关（从最高进度关卡往回数）
    local sweepStages = collectPrevStages(maxStageId, SweepService.SWEEP_STAGE_COUNT, stageConfig)
    if #sweepStages == 0 then
        return false, "当前关卡无法扫荡"
    end

    -- 出战英雄数
    local deployed  = heroesData.deployed or {}
    local heroCount = #deployed
    if heroCount == 0 then
        return false, "未出战英雄"
    end

    -- ── 计算奖励（与挂机/离线统一走 IdleIncomeConfig） ──
    -- 1 张扫荡券 = 即时领取 REWARD_MINUTES 分钟的挂机收益（基于玩家最高进度关卡）
    local stageCount = #sweepStages
    local cfgGoldPerMin, cfgExpPerMin = IdleIncomeConfig.get(maxStageId)
    local goldAmount = math.floor(cfgGoldPerMin * SweepService.REWARD_MINUTES)
    local baseExp    = math.floor(cfgExpPerMin * SweepService.REWARD_MINUTES)

    -- 英雄经验 = baseExp × 出战人数倍率（与挂机一致）
    local heroCountMult = ExpTable.heroCountExpMult[heroCount] or 1.0
    local heroExpTotal  = math.floor(baseExp * heroCountMult)

    -- [对比日志] 旧方案（首通奖励×4/关）值，仅用于新旧对比
    local oldTotalGold, oldTotalExp = 0, 0
    for _, entry in ipairs(sweepStages) do
        oldTotalGold = oldTotalGold + (entry.fcGold or 0)
        oldTotalExp  = oldTotalExp  + (entry.fcExp or 0)
    end
    local oldGold = math.floor(oldTotalGold * 4)
    local oldExp  = math.floor(oldTotalExp * 4)
    print(string.format("[SWEEP_COMPARE] maxStage=%s  gold: %d→%d(%+d)  playerExp: %d→%d(%+d)  (cfg %d/%d per-min × %d min)",
        tostring(maxStageId), oldGold, goldAmount, goldAmount - oldGold,
        oldExp, baseExp, baseExp - oldExp,
        cfgGoldPerMin, cfgExpPerMin, SweepService.REWARD_MINUTES))

    -- ── 扣券 ──
    currency.sweepTicket = owned - SweepService.SWEEP_COST
    PDM.MarkDirty(uid, "currency")

    -- ── 发放奖励 ──

    -- 1) 金币
    if goldAmount > 0 then
        currency.gold = (currency.gold or 0) + goldAmount
        PDM.MarkDirty(uid, "currency")
    end

    -- 2) 英雄经验
    local perHeroExp = 0
    if heroCount > 0 and heroExpTotal > 0 then
        perHeroExp = math.floor(heroExpTotal / heroCount + 0.5)
        for _, heroId in ipairs(deployed) do
            local numId = tonumber(heroId) or heroId
            local heroData = heroesData.roster[numId]
            if heroData then
                heroData.exp = (heroData.exp or 0) + perHeroExp
                ExpTable.autoLevelUpHero(heroData)
            end
        end
        PDM.MarkDirty(uid, "heroes")
        HeroService.ApplyResonanceSync(uid)
    end

    -- 3) 冒险经验
    if baseExp > 0 then
        local oldLv = playerData.level or 1
        playerData.exp = (playerData.exp or 0) + baseExp
        ExpTable.autoLevelUpPlayer(playerData)
        PDM.MarkDirty(uid, "player")
        if playerData.level > oldLv then
            HeroService.SyncHeroLevelsToPlayerLevel(uid, playerData.level)
        end
    end

    -- 4) 装备掉落：固定 10 件，平均分配到各关卡，品质由各关卡怪物池决定
    local MC = require("config.MonsterConfig")
    local equipsPerStage = math.floor(SweepService.EQUIP_DROP_COUNT / stageCount)
    local remainder = SweepService.EQUIP_DROP_COUNT - equipsPerStage * stageCount
    local equipSeeds = {}
    local equipByQuality = {}  -- [quality] = count

    for stageIdx, stageEntry in ipairs(sweepStages) do
        -- 按实际出怪队列构建品质池（与 BattleScene.generateEnemyList 一致）
        -- 挂机模式：idleCount 只怪，Boss 占 1 个名额，普通怪 round-robin 填充其余
        local spawnList = {}
        local monsters = stageEntry.monsters or {}
        local totalCount = stageEntry.idleCount or 10
        local hasBoss = stageEntry.bossId and stageEntry.bossId > 0
        local normalCount = hasBoss and (totalCount - 1) or totalCount

        if #monsters > 0 then
            for i = 1, normalCount do
                local typeIdx = ((i - 1) % #monsters) + 1
                spawnList[#spawnList + 1] = monsters[typeIdx]
            end
        end
        if hasBoss then
            -- Boss 插入队列中间（与战斗逻辑一致）
            local insertPos = math.ceil(#spawnList / 2) + 1
            table.insert(spawnList, insertPos, stageEntry.bossId)
        end

        local poolSize = #spawnList
        local maxDropQ = stageConfig.getMaxDropQuality and stageConfig.getMaxDropQuality(stageEntry) or SC.getMaxDropQuality(stageEntry)

        -- 该关卡分配的装备数（前 remainder 个关卡多分 1 件）
        local dropCount = equipsPerStage + (stageIdx <= remainder and 1 or 0)

        for i = 1, dropCount do
            local quality
            if poolSize > 0 then
                local typeIdx = math.random(1, poolSize)
                local monsterId = spawnList[typeIdx]
                local template = MC.MONSTERS[monsterId]
                local monsterQ = template and template.quality or 1
                quality = OfflineCalc._rollQualityByMonster(monsterQ)
            else
                quality = 1
            end
            if quality > maxDropQ then quality = maxDropQ end
            equipSeeds[#equipSeeds + 1] = {
                stageId = stageEntry.id,
                quality = quality,
                level   = stageEntry.monsterLevel,
                count   = 1,
            }
            equipByQuality[quality] = (equipByQuality[quality] or 0) + 1
        end
    end
    -- 合并相同 stageId+quality+level 的种子
    equipSeeds = OfflineCalc._mergeSeeds(equipSeeds)

    for _, seed in ipairs(equipSeeds) do
        local count = seed.count or 1
        for _ = 1, count do
            LootBoxSystem.addSeed(lootbox, seed.stageId, seed.quality, seed.level)
        end
    end
    PDM.MarkDirty(uid, "lootbox")

    -- 5) 卷轴掉落：固定 10 个，随机分配到 4 种类型
    local scrollTypes = { "weaponScroll", "offhandScroll", "armorScroll", "accessoryScroll" }
    local scrollDrops = {}
    for _ = 1, SweepService.SCROLL_DROP_COUNT do
        local st = scrollTypes[math.random(1, #scrollTypes)]
        scrollDrops[st] = (scrollDrops[st] or 0) + 1
    end
    local totalScrolls = SweepService.SCROLL_DROP_COUNT
    for scrollField, count in pairs(scrollDrops) do
        if count > 0 then
            currency[scrollField] = (currency[scrollField] or 0) + count
        end
    end
    PDM.MarkDirty(uid, "currency")

    -- 收集扫荡关卡 ID 列表（供客户端显示）
    local sweepStageIds = {}
    for _, entry in ipairs(sweepStages) do
        sweepStageIds[#sweepStageIds + 1] = entry.id
    end

    print(string.format("[SweepService] uid=%s swept %d stages (%s): gold=%d heroExp=%d playerExp=%d equips=%d scrolls=%d ticketLeft=%d",
        tostring(uid), stageCount, table.concat(sweepStageIds, ","),
        goldAmount, heroExpTotal, baseExp,
        SweepService.EQUIP_DROP_COUNT, totalScrolls, currency.sweepTicket))

    return true, nil, {
        gold            = goldAmount,
        heroExp         = perHeroExp,
        heroExpTotal    = heroExpTotal,
        playerExp       = baseExp,
        equipCount      = SweepService.EQUIP_DROP_COUNT,
        equipByQuality  = equipByQuality,
        scrollDrops     = scrollDrops,
        ticketLeft      = currency.sweepTicket,
        sweepStages     = sweepStageIds,  -- 实际扫荡的关卡列表
    }
end

return SweepService
