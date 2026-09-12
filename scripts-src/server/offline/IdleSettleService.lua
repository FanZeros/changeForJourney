-- ============================================================================
-- IdleSettleService - 在线挂机定时结算（Update handler 驱动）
-- 职责: 每帧累加 idleAccumSec，满 60s 结算一次在线挂机收益
-- 层级: server/offline  |  通过 PDM 读写，禁止直接网络 IO
-- 设计参考: docs/挂机收益统一方案-v2.md §9.3 / §9.4
-- ============================================================================

local PDM           = require("server.character.PlayerDataManager")
local OfflineCalc   = require("systems.OfflineCalc")
local StageProvider = require("shared.StageProvider")
local ExpTable      = require("config.ExpTable")
local LootBoxSystem = require("systems.LootBoxSystem")
local HeroService   = require("server.hero.HeroService")

local IdleSettleService = {}

-- ======================== 常量 ========================

local IDLE_SETTLE_INTERVAL = 60  -- 每 60 秒结算一次在线挂机收益
local SPEED_CARD_BONUS = 0.20    -- 加速卡：在线挂机收益 +20%

local function getSpeedCardEffectiveSeconds(uid, seconds)
    local currency = PDM.GetModule(uid, "currency")
    if currency and (tonumber(currency.speedCardExpireAt) or 0) > os.time() then
        return seconds * (1 + SPEED_CARD_BONUS), true
    end
    return seconds, false
end

-- ======================== 内部：奖励发放 ========================

--- 实际发放挂机奖励到玩家各模块（纯数据操作，可被 pcall 包裹）
--- 与 OfflineService.ClaimRewards 的 grant 逻辑一致，但无 bonus/面板逻辑
---@param uid number
---@param rewards table  OfflineCalc.calcOnlineIdleRewards 的返回值
local function grantIdleRewards(uid, rewards)
    local currency   = PDM.GetModule(uid, "currency")
    local heroesData = PDM.GetModule(uid, "heroes")
    local playerData = PDM.GetModule(uid, "player")
    local lootbox    = PDM.GetModule(uid, "lootbox")

    if not currency or not heroesData or not playerData or not lootbox then
        error("grantIdleRewards: 模块数据未加载 uid=" .. tostring(uid))
    end

    -- 1) 金币
    local goldAmount = math.floor(rewards.gold or 0)
    if goldAmount > 0 then
        currency.gold = (currency.gold or 0) + goldAmount
        PDM.MarkDirty(uid, "currency")
    end

    -- 2) 英雄经验（平分给出战英雄）
    local deployed = heroesData.deployed or {}
    local heroCount = #deployed
    if heroCount > 0 then
        local totalHeroExp = math.floor(rewards.adventurerExp or 0)
        if totalHeroExp > 0 then
            local perHeroExp = math.floor(totalHeroExp / heroCount + 0.5)
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
    end

    -- 3) 冒险经验（玩家升级）
    local playerExp = math.floor(rewards.adventureExp or 0)
    if playerExp > 0 then
        local oldLv = playerData.level or 1
        playerData.exp = (playerData.exp or 0) + playerExp
        ExpTable.autoLevelUpPlayer(playerData)
        PDM.MarkDirty(uid, "player")
        if playerData.level > oldLv then
            HeroService.SyncHeroLevelsToPlayerLevel(uid, playerData.level)
        end
    end

    -- 4) 装备种子 → 战利品缓冲
    local equipSeeds = rewards.equipSeeds or {}
    if #equipSeeds > 0 then
        for _, seed in ipairs(equipSeeds) do
            local count = seed.count or 1
            for _ = 1, count do
                LootBoxSystem.addSeed(lootbox, seed.stageId, seed.quality, seed.level)
            end
        end
        PDM.MarkDirty(uid, "lootbox")
    end

    -- 5) 卷轴掉落 → 货币
    local scrollDrops = rewards.scrollDrops or {}
    local scrollDirty = false
    for scrollField, count in pairs(scrollDrops) do
        local amount = math.floor(count)
        if amount > 0 then
            currency[scrollField] = (currency[scrollField] or 0) + amount
            scrollDirty = true
        end
    end
    if scrollDirty then
        PDM.MarkDirty(uid, "currency")
    end
end

-- ======================== 内部：结算执行 ========================

--- 执行一次在线挂机结算（pcall 保护）
---@param uid number
---@param bd table  battle 模块数据引用
local function settleOnlineIdle(uid, bd)
    local settleSeconds = bd.idleAccumSec or 0
    if settleSeconds <= 0 then return end

    -- 获取实时出战英雄数
    local heroesData = PDM.GetModule(uid, "heroes")
    local heroCount = 0
    if heroesData and heroesData.deployed then
        heroCount = #heroesData.deployed
    end
    if heroCount <= 0 then heroCount = 1 end  -- 安全下限

    local stageConfig = StageProvider.GetForServer(PDM.GetServerId(uid))
    local incomeStageId, dropStageId = OfflineCalc.resolveIdleStageAnchors(bd, stageConfig)
    local calcSeconds, speedCardActive = getSpeedCardEffectiveSeconds(uid, settleSeconds)
    local rewards = OfflineCalc.calcOnlineIdleRewards(calcSeconds, incomeStageId, heroCount, dropStageId, stageConfig)

    if not rewards then
        -- 计算结果为空（不应发生，如 maxStageId 配置缺失），安全清零
        bd.idleAccumSec = 0
        PDM.MarkDirty(uid, "battle")
        print("[IdleSettle][WARN] calcOnlineIdleRewards returned nil uid=" .. tostring(uid)
            .. " seconds=" .. tostring(settleSeconds) .. " incomeStage=" .. tostring(incomeStageId))
        return
    end

    -- pcall 保护：失败时 idleAccumSec 不变，下次 tick 自动重试（铁律 #9）
    local ok, err = pcall(grantIdleRewards, uid, rewards)
    if ok then
        -- 减法而非清零：保留结算期间新增的 dt（设计文档 §9.3 关键决策）
        bd.idleAccumSec = bd.idleAccumSec - settleSeconds
        bd.lastIdleClaimTime = os.time()
        PDM.MarkDirty(uid, "battle")

        print("[IdleSettle] settled uid=" .. tostring(uid)
            .. " sec=" .. string.format("%.1f", settleSeconds)
            .. " incomeStage=" .. tostring(incomeStageId)
            .. " dropStage=" .. tostring(dropStageId)
            .. (speedCardActive and " speedCard=1.2x" or "")
            .. " gold=" .. tostring(rewards.gold)
            .. " exp=" .. tostring(rewards.adventureExp))
    else
        -- 失败：idleAccumSec 保持不变，下个周期重试
        print("[IdleSettle][ERROR] grantIdleRewards FAILED uid=" .. tostring(uid)
            .. " err=" .. tostring(err)
            .. " sec=" .. string.format("%.1f", settleSeconds))
    end
end

-- ======================== 公开接口 ========================

--- 每帧调用：累加在线挂机时间，满 IDLE_SETTLE_INTERVAL 时触发结算
--- 由 Server.lua 的 Update handler 对每个 isInGame 玩家调用
---@param uid number
---@param dt number  帧间隔（秒）
function IdleSettleService.HandleIdleAccum(uid, dt)
    local bd = PDM.GetModule(uid, "battle")
    if not bd then return end

    -- battleMode 守卫（#4 竞态保护）：
    --   "idle"      → 常规挂机，累积在线收益
    --   "firstClear"→ 首通战斗进行中，后台同样累积在线挂机收益（按当前 maxStageId 计费）
    --   "offline"   → 离线状态，由 OfflineService 在登录时单独结算，跳过以防重复计费
    if bd.battleMode ~= "idle" and bd.battleMode ~= "firstClear" then return end

    bd.idleAccumSec = (bd.idleAccumSec or 0) + dt

    if bd.idleAccumSec >= IDLE_SETTLE_INTERVAL then
        settleOnlineIdle(uid, bd)
    end
end

--- 首通成功前的预结算：在 maxStageId 推进前结算当前累积（按旧关卡计费）
--- 防止新关卡"追溯提升"已累积时间的收益（设计文档 §9.4）
--- 由 BattleService.NextStage 在更新 maxStageId 前调用
---@param uid number
function IdleSettleService.PreSettleForFirstClear(uid)
    local bd = PDM.GetModule(uid, "battle")
    if not bd then return end

    local accum = bd.idleAccumSec or 0
    if accum <= 0 then return end

    -- 获取实时出战英雄数
    local heroesData = PDM.GetModule(uid, "heroes")
    local heroCount = 0
    if heroesData and heroesData.deployed then
        heroCount = #heroesData.deployed
    end
    if heroCount <= 0 then heroCount = 1 end

    local stageConfig = StageProvider.GetForServer(PDM.GetServerId(uid))
    local incomeStageId, dropStageId = OfflineCalc.resolveIdleStageAnchors(bd, stageConfig)
    local calcSeconds, speedCardActive = getSpeedCardEffectiveSeconds(uid, accum)
    local rewards = OfflineCalc.calcOnlineIdleRewards(calcSeconds, incomeStageId, heroCount, dropStageId, stageConfig)

    if not rewards then
        bd.idleAccumSec = 0
        PDM.MarkDirty(uid, "battle")
        return
    end

    local ok, err = pcall(grantIdleRewards, uid, rewards)
    if ok then
        bd.idleAccumSec = 0  -- 首通预结算使用清零（没有并发 dt 问题）
        bd.lastIdleClaimTime = os.time()
        PDM.MarkDirty(uid, "battle")
        print("[IdleSettle] pre-settle for first-clear uid=" .. tostring(uid)
            .. " sec=" .. string.format("%.1f", accum)
            .. " incomeStage=" .. tostring(incomeStageId)
            .. " dropStage=" .. tostring(dropStageId)
            .. (speedCardActive and " speedCard=1.2x" or "")
            .. " gold=" .. tostring(rewards.gold))
    else
        -- 失败则保留 idleAccumSec，后续 Update 会以新 maxStageId 重算（玩家不亏）
        print("[IdleSettle][ERROR] pre-settle FAILED uid=" .. tostring(uid)
            .. " err=" .. tostring(err))
    end
end

return IdleSettleService
