-- ============================================================================
-- SweepService - 扫荡业务逻辑
-- 职责: 扣除扫荡券，即时发放固定关卡收益（首通奖励×10）
-- 层级: rules/sweep  |  单机本地结算，通过 PDM 读写，禁止网络 IO
-- ============================================================================

local PDM             = require("rules.character.PlayerDataManager")
local OfflineCalc     = require("systems.OfflineCalc")
local SC              = require("config.StageConfig")
local StageProvider   = require("shared.StageProvider")
local ExpTable        = require("config.ExpTable")
local EquipmentSystem = require("systems.EquipmentSystem")
local LootBoxSystem   = require("systems.LootBoxSystem")
local HeroService     = require("rules.hero.HeroService")
local IdleIncomeConfig = require("config.IdleIncomeConfig")

local SweepService = {}

-- 每次扫荡消耗的扫荡券数
SweepService.SWEEP_COST = 1
-- 单次请求最多扫荡次数
SweepService.MAX_COUNT = 10
-- 扫荡收益 = 即时领取 N 分钟挂机收益（与挂机/离线统一走 IdleIncomeConfig）
SweepService.REWARD_MINUTES = 10
-- 扫荡固定掉落装备数
SweepService.EQUIP_DROP_COUNT = 10
-- 扫荡固定掉落卷轴数
SweepService.SCROLL_DROP_COUNT = 10
-- 扫荡只结算最高已通关一关，不再回退前 5 个小关
SweepService.SWEEP_STAGE_COUNT = 1

-- ======================== 执行扫荡 ========================

--- 消耗 count 张扫荡券，只扫最高已通关，奖励按次数相乘
--- 经验按指定队伍发放（默认队1）：扫哪队，哪队出战角色吃经验
---@param uid number
---@param count number|nil
---@param teamIdx number|nil 队伍 1~3，默认 1
---@return boolean ok
---@return string|nil err
---@return table|nil result  { gold, heroExp, playerExp, equipCount, scrolls, stages }
function SweepService.Sweep(uid, count, teamIdx)
    count = math.floor(tonumber(count) or 1)
    if count < 1 then count = 1 end
    if count > SweepService.MAX_COUNT then count = SweepService.MAX_COUNT end
    local currency   = PDM.GetModule(uid, "currency")
    local battleData = PDM.GetModule(uid, "battle")
    local heroesData = PDM.GetModule(uid, "heroes")
    local playerData = PDM.GetModule(uid, "player")
    local equipData  = PDM.GetModule(uid, "equipment")

    if not currency or not battleData or not heroesData or not playerData or not equipData then
        return false, "数据未加载"
    end
    -- 请求门禁必须先于队伍归一化、扣券与发奖；不得把无效/锁定队伍偷偷改扫队1。
    teamIdx = teamIdx == nil and 1 or math.tointeger(tonumber(teamIdx) or 0)
    if not teamIdx or teamIdx < 1 or teamIdx > ExpTable.TEAM_COUNT then
        return false, "无效的队伍编号"
    end
    if teamIdx > ExpTable.getUnlockedTeamCount(battleData) then
        return false, string.format("队伍%d尚未解锁（%s）", teamIdx, ExpTable.getTeamUnlockText(teamIdx))
    end
    if not equipData.inventory then
        equipData.inventory = {}
    end

    -- 检查扫荡券是否足够
    local owned = currency.sweepTicket or 0
    local cost = SweepService.SWEEP_COST * count
    if owned < cost then
        return false, "扫荡券不足"
    end
    local lootboxData = PDM.GetModule(uid, "lootbox")
    local totalEquipDrops = SweepService.EQUIP_DROP_COUNT * count
    -- 满包且遗匣未加载时，在扣券/发奖前拒绝，避免产生无法保存的装备。
    if not lootboxData and EquipmentSystem.getInventoryCount(equipData) + totalEquipDrops
        > EquipmentSystem.MAX_INVENTORY then
        return false, "遗匣数据未加载"
    end

    -- 以玩家最高进度关卡为基准，无论挂机在哪一关
    local stageConfig = StageProvider.Get()
    local maxStageId = battleData.maxStageId or battleData.currentStageId
    if not maxStageId then
        return false, "尚未开始远征"
    end

    -- 只扫最高已通关。maxStageId 未通关时回退一关；终焉神殿不产掉落，再回退到上一关。
    local sweepStageId = maxStageId
    local cleared = battleData.clearedStages or {}
    local function isCleared(id)
        return cleared[id] or cleared[tostring(id)]
    end
    if not isCleared(sweepStageId) then
        sweepStageId = stageConfig.getPrevStageId(sweepStageId)
            or stageConfig.getLastStageOfPrevDifficulty(sweepStageId)
    end
    if sweepStageId and stageConfig.isTerminalTemple and stageConfig.isTerminalTemple(sweepStageId) then
        sweepStageId = stageConfig.getPrevStageId(sweepStageId)
            or stageConfig.getTerminalPrevStageId(sweepStageId)
            or stageConfig.getLastStageOfPrevDifficulty(sweepStageId)
    end
    local sweepEntry = sweepStageId and stageConfig.getStage(sweepStageId) or nil
    if not sweepEntry or (sweepEntry.monsterLevel or 0) <= 0 then
        return false, "当前关卡无法扫荡"
    end
    local sweepStages = { sweepEntry }

    -- 出战英雄：按指定队伍取槽位（排除空槽 0）；队1 无 teams 结构时回退 deployed 镜像
    local TeamSlots = require("shared.heroes.TeamSlots")
    TeamSlots.normalize(heroesData)
    local teamSlots = heroesData.teams and heroesData.teams[teamIdx]
        and heroesData.teams[teamIdx].slots or nil
    ---@type integer[]
    local deployed = {}
    if teamSlots then
        for _, slot in ipairs(teamSlots) do
            local num = tonumber(slot) or 0
            if num > 0 then deployed[#deployed + 1] = num end
        end
    else
        for _, slot in ipairs(heroesData.deployed or {}) do
            local num = tonumber(slot) or 0
            if num > 0 then deployed[#deployed + 1] = num end
        end
    end
    local heroCount = #deployed
    if heroCount == 0 then
        return false, "该队伍未出战英雄"
    end

    -- ── 计算奖励（与挂机/离线统一走 IdleIncomeConfig） ──
    -- 1 张扫荡券 = 即时领取 REWARD_MINUTES 分钟的挂机收益（基于玩家最高进度关卡）
    local stageCount = #sweepStages
    local cfgGoldPerMin, cfgExpPerMin = IdleIncomeConfig.get(maxStageId)
    local goldAmount = math.floor(cfgGoldPerMin * SweepService.REWARD_MINUTES) * count
    local baseExp    = math.floor(cfgExpPerMin * SweepService.REWARD_MINUTES) * count

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
    currency.sweepTicket = owned - cost
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

    -- 3) 扫荡不再增加远征经验

    -- 4) 装备掉落：生成完整实例，满包时转入遗匣。
    local MC = require("config.MonsterConfig")
    local equipsPerStage = math.floor(totalEquipDrops / stageCount)
    local remainder = totalEquipDrops - equipsPerStage * stageCount
    local grantedEquips = {}
    local equipByQuality = {}  -- [quality] = count
    local inventoryCount, lootboxCount = 0, 0

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
            local equip = EquipmentSystem.generateRandom(stageEntry.monsterLevel, quality)
            if not equip then
                print("[SweepService][WARN] generateRandom failed level="
                    .. tostring(stageEntry.monsterLevel) .. " quality=" .. tostring(quality))
            else
                local destination = LootBoxSystem.deliverEquipment(lootboxData, equipData, equip)
                if destination == "lootbox" then
                    lootboxCount = lootboxCount + 1
                else
                    inventoryCount = inventoryCount + 1
                end
                grantedEquips[#grantedEquips + 1] = {
                    type = "equip",
                    templateId = equip.templateId,
                    quality = equip.quality,
                    level = equip.level,
                    slot = equip.slot,
                    equip = equip,
                    destination = destination,
                }
                equipByQuality[equip.quality] = (equipByQuality[equip.quality] or 0) + 1
            end
        end
    end
    if inventoryCount > 0 then
        PDM.MarkDirty(uid, "equipment")
    end
    if lootboxCount > 0 then
        PDM.MarkDirty(uid, "lootbox")
        print("[SweepService] 满包装备已入遗匣=" .. lootboxCount
            .. " uid=" .. tostring(uid))
    end

    -- 5) 卷轴掉落：固定数量，随机分配到 6 种类型
    local scrollTypes = { "weaponScroll", "offhandScroll", "armorScroll", "helmetScroll", "shoesScroll", "accessoryScroll" }
    local scrollDrops = {}
    for _ = 1, SweepService.SCROLL_DROP_COUNT * count do
        local st = scrollTypes[math.random(1, #scrollTypes)]
        scrollDrops[st] = (scrollDrops[st] or 0) + 1
    end
    local totalScrolls = SweepService.SCROLL_DROP_COUNT * count
    for scrollField, amount in pairs(scrollDrops) do
        if amount > 0 then
            currency[scrollField] = (currency[scrollField] or 0) + amount
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
        totalEquipDrops, totalScrolls, currency.sweepTicket))

    return true, nil, {
        gold            = goldAmount,
        heroExp         = perHeroExp,
        heroExpTotal    = heroExpTotal,
        playerExp       = baseExp,
        equipCount      = #grantedEquips,
        equips          = grantedEquips,
        count           = count,
        equipByQuality  = equipByQuality,
        scrollDrops     = scrollDrops,
        ticketLeft      = currency.sweepTicket,
        sweepStages     = sweepStageIds,  -- 实际扫荡的关卡列表
        teamIdx         = teamIdx,        -- 经验发放队伍
    }
end

return SweepService
