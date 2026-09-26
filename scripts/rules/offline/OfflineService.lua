-- ============================================================================
-- OfflineService - 离线收益业务逻辑（统一挂机效率方案 v2）
-- 职责: 离线奖励计算、领取、生命周期管理
-- 层级: server/offline  |  通过 PDM 读写，禁止网络 IO
-- ============================================================================

local PDM              = require("rules.character.PlayerDataManager")
local OfflineCalc      = require("systems.OfflineCalc")
local StageProvider    = require("shared.StageProvider")
local ExpTable         = require("config.ExpTable")
local HeroConfig       = require("config.HeroConfig")
local LootBoxSystem    = require("systems.LootBoxSystem")
local EquipmentSystem  = require("systems.EquipmentSystem")
local CurrencyService  = require("rules.currency.CurrencyService")
local HeroService      = require("rules.hero.HeroService")

local OfflineService = {}

-- 内存中暂存的待领取离线奖励（不持久化）
-- { [uid] = { rewards = ..., panelData = ... } }
local pendingRewards = {}

-- ======================== 常量 ========================

local IDLE_SETTLE_INTERVAL = 60  -- 在线结算周期（秒），用于崩溃恢复判定

-- 卷轴掉落（reward type 用 snake_case 与 RESOURCE_DEFS 对齐）
local SCROLL_TO_REWARD = {
    weaponScroll    = "weapon_scroll",
    offhandScroll   = "offhand_scroll",
    armorScroll     = "armor_scroll",
    accessoryScroll = "accessory_scroll",
    helmetScroll    = "helmet_scroll",
    shoesScroll     = "shoes_scroll",
    sweepTicket     = "sweep_ticket",
}

--- 把离线装备种子立刻生成真实装备。展示和领取共用同一批实例。
---@param equipSeeds table|nil
---@return table[]
local function materializeEquipSeeds(equipSeeds)
    local equips = {}
    for _, seed in ipairs(equipSeeds or {}) do
        local count = math.floor(tonumber(seed.count) or 1)
        if count < 1 then count = 1 end
        for _ = 1, count do
            local equip = EquipmentSystem.generateRandom(seed.level, seed.quality)
            if equip then
                equips[#equips + 1] = equip
            else
                print("[OfflineService][WARN] generateRandom failed level="
                    .. tostring(seed.level) .. " quality=" .. tostring(seed.quality))
            end
        end
    end
    return equips
end

local function appendEquipPreviewItems(list, equips)
    for _, equip in ipairs(equips or {}) do
        list[#list + 1] = {
            type       = "equip",
            templateId = equip.templateId,
            quality    = equip.quality,
            level      = equip.level,
            slot       = equip.slot,
        }
    end
end

--- 构建出战队员的升级预览（只读，不改数据；领取时才真正发经验）
--- 经验与 ClaimRewards 一致：总量平分给出战队员，各自套用自己的等级曲线。
---@param heroesData table|nil
---@param totalHeroExp number 队员经验总合
---@return table[] { heroId, name, quality, startLevel, startExp, level, exp, maxExp, levelGain, expGain, capped }
local function buildHeroExpPreview(heroesData, totalHeroExp)
    local preview = {}
    if not heroesData then return preview end
    local deployed = heroesData.deployed or {}
    local heroCount = #deployed
    if heroCount <= 0 then return preview end

    local total = math.floor(totalHeroExp or 0)
    local perHeroExp = math.floor(total / heroCount + 0.5)

    for _, heroId in ipairs(deployed) do
        local numId = tonumber(heroId) or heroId
        local heroData = heroesData.roster and heroesData.roster[numId]
        if heroData then
            local beforeLv = heroData.level or 1
            local beforeExp = heroData.exp or 0
            local sim = ExpTable.simulateHeroExp(beforeLv, beforeExp, perHeroExp)
            local cfg = HeroConfig.get(numId)
            preview[#preview + 1] = {
                heroId     = numId,
                name       = (cfg and cfg.name) or ("#" .. tostring(numId)),
                quality    = cfg and cfg.quality or 1,
                startLevel = beforeLv,
                startExp   = beforeExp,
                level      = sim.level,
                exp        = sim.exp,
                maxExp     = sim.maxExp,
                levelGain  = sim.gain,
                expGain    = perHeroExp,
                capped     = sim.capped,
            }
        end
    end
    return preview
end

local function appendScrollPreviewItems(list, scrollDrops)
    for scrollField, count in pairs(scrollDrops or {}) do
        if count > 0 then
            list[#list + 1] = {
                type   = SCROLL_TO_REWARD[scrollField] or scrollField,
                amount = count,
            }
        end
    end
end

-- ======================== 生命周期 ========================

--- 获取今日 UTC+8 日期字符串
---@return string "YYYY-MM-DD"
local function getTodayDateStr()
    local UTC8_OFFSET = 28800
    local t = os.time() + UTC8_OFFSET
    return os.date("!%Y-%m-%d", t)
end


--- 玩家进入游戏后计算离线收益，返回面板数据（不做网络 IO）
---@param uid number
---@return table|nil panelData  有离线奖励时返回面板数据，否则 nil
function OfflineService.CalcOnEnter(uid)
    -- 已有未领取的奖励 → 直接返回
    if pendingRewards[uid] then
        print("[OfflineService] resending pending offline reward uid=" .. tostring(uid))
        return pendingRewards[uid].panelData
    end

    local sessionData = PDM.GetModule(uid, "session")
    if not sessionData then
        print("[OfflineService] no session data for uid=" .. tostring(uid))
        return
    end

    local lastOnline = sessionData.lastOnlineTime or 0
    local now = os.time()

    -- 记录首次登录时间（仅首次）
    if (sessionData.firstLoginTime or 0) <= 0 then
        sessionData.firstLoginTime = now
        PDM.MarkDirty(uid, "session")
        print("[OfflineService] recording firstLoginTime uid=" .. tostring(uid))
    end

    -- 计算游戏天数（UTC+8 日界）
    do
        local UTC8_OFFSET = 28800
        local DAY_SECS    = 86400
        local firstDay = math.floor((sessionData.firstLoginTime + UTC8_OFFSET) / DAY_SECS)
        local today    = math.floor((now + UTC8_OFFSET) / DAY_SECS)
        local days = today - firstDay + 1
        if days < 1 then days = 1 end
        sessionData.playDays = days
        PDM.MarkDirty(uid, "session")
    end

    -- 首次登录不产生离线收益
    if lastOnline <= 0 then
        sessionData.lastOnlineTime = now
        PDM.MarkDirty(uid, "session")
        print("[OfflineService] first login, setting lastOnlineTime uid=" .. tostring(uid))
        return
    end

    local offlineSeconds = now - lastOnline

    -- ══════════ 崩溃恢复：检测 lastIdleClaimTime 遗漏 ══════════
    local battleData = PDM.GetModule(uid, "battle")
    if battleData then
        local lastClaim = battleData.lastIdleClaimTime or 0
        if lastClaim > 0 and lastOnline > lastClaim then
            -- 存在未结算窗口（崩溃/热更导致 idleAccumSec 未结算）
            local missedSeconds = lastOnline - lastClaim
            if missedSeconds > 0 and missedSeconds < IDLE_SETTLE_INTERVAL * 2 then
                -- 合理范围内（最多 ~120 秒遗漏），并入离线时长一起结算
                offlineSeconds = offlineSeconds + missedSeconds
                print(string.format(
                    "[OfflineService] crash recovery: added %d missed seconds uid=%s",
                    missedSeconds, tostring(uid)))
            end
        end
        -- 重置累积器（上一轮残留的 idleAccumSec 已合并到 offlineSeconds）
        if (battleData.idleAccumSec or 0) > 0 then
            offlineSeconds = offlineSeconds + battleData.idleAccumSec
            print(string.format(
                "[OfflineService] merging residual idleAccumSec=%d uid=%s",
                math.floor(battleData.idleAccumSec), tostring(uid)))
            battleData.idleAccumSec = 0
            PDM.MarkDirty(uid, "battle")
        end
    end

    -- 不满足最低离线时间
    if offlineSeconds < OfflineCalc.MIN_SECONDS then
        print("[OfflineService] offline too short: " .. math.floor(offlineSeconds) .. "s uid=" .. tostring(uid))
        return
    end

    -- 获取战斗和英雄数据
    local heroesData = PDM.GetModule(uid, "heroes")
    local playerData = PDM.GetModule(uid, "player")

    if not battleData or not heroesData or not playerData then
        print("[OfflineService] missing module data uid=" .. tostring(uid))
        return
    end

    -- 确定计算参数（首通进行中与在线结算使用同一双锚点解析）
    local stageConfig = StageProvider.Get()
    local incomeStageId, dropStageId = OfflineCalc.resolveIdleStageAnchors(battleData, stageConfig)
    if not incomeStageId or incomeStageId <= 0 then
        print("[OfflineService] no idle income stage uid=" .. tostring(uid))
        return
    end

    -- 使用断线时快照的英雄数（离线期间阵容不变）
    local heroCount = battleData.idleHeroCount or 0
    if heroCount <= 0 then
        -- 兼容旧存档：没有快照时用当前出战数
        local deployed = heroesData.deployed or {}
        heroCount = #deployed
    end

    -- 调用统一挂机计算（入口 A：有 MIN/MAX 门槛）
    local rewards = OfflineCalc.calcOfflineIdleRewards(offlineSeconds, incomeStageId, heroCount, dropStageId, stageConfig)
    if not rewards then
        print("[OfflineService] no offline rewards generated uid=" .. tostring(uid))
        return
    end

    -- 构建面板展示数据（v2 结构）
    local panelData = {
        offlineSeconds = rewards.seconds,
        maxSeconds     = rewards.maxSeconds or OfflineCalc.MAX_SECONDS,
        totalKills     = rewards.kills,
        adventureExp   = rewards.adventureExp,
        adventurerExp  = rewards.adventurerExp,
        heroExpPreview = buildHeroExpPreview(heroesData, rewards.adventurerExp),
        rewards        = {},
    }

    -- 金币
    if rewards.gold > 0 then
        panelData.rewards[#panelData.rewards + 1] = {
            type   = "gold",
            amount = rewards.gold,
        }
    end

    -- 装备种子立刻生成真实装备，展示和领取共用同一批
    local grantedEquips = materializeEquipSeeds(rewards.equipSeeds)
    rewards.grantedEquips = grantedEquips
    appendEquipPreviewItems(panelData.rewards, grantedEquips)

    -- 卷轴掉落
    appendScrollPreviewItems(panelData.rewards, rewards.scrollDrops)

    -- 暂存到内存（供领取时使用）
    pendingRewards[uid] = { rewards = rewards, panelData = panelData }

    -- 返回面板数据，由 Server.lua 负责推送
    print("[OfflineService] offline reward ready uid=" .. tostring(uid)
        .. " gold=" .. rewards.gold .. " kills=" .. rewards.kills
        .. " seconds=" .. rewards.seconds)
    return panelData
end

-- ======================== 领取离线收益 ========================

--- 领取离线收益
---@param uid number
---@return boolean ok, string? err, table? result
function OfflineService.ClaimRewards(uid)
    local pending = pendingRewards[uid]
    if not pending then
        return false, "无待领取的离线收益"
    end
    local rewards = pending.rewards

    local sessionData = PDM.GetModule(uid, "session")
    if not sessionData then
        return false, "session 数据未加载"
    end

    local currency   = PDM.GetModule(uid, "currency")
    local heroesData = PDM.GetModule(uid, "heroes")
    local playerData = PDM.GetModule(uid, "player")
    local equipData  = PDM.GetModule(uid, "equipment")

    if not currency or not heroesData or not playerData or not equipData then
        return false, "数据未加载"
    end
    if not equipData.inventory then
        equipData.inventory = {}
    end

    -- 1) 金币
    local goldAmount = rewards.gold
    goldAmount = math.floor(goldAmount)
    currency.gold = (currency.gold or 0) + goldAmount
    PDM.MarkDirty(uid, "currency")

    -- 2) 英雄经验（平分给出战英雄）
    local deployed = heroesData.deployed or {}
    local heroCount = #deployed
    local perHeroExp = 0
    if heroCount > 0 then
        local totalHeroExp = rewards.adventurerExp
        totalHeroExp = math.floor(totalHeroExp)
        perHeroExp = math.floor(totalHeroExp / heroCount + 0.5)
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

    -- 3) 远征经验（玩家升级）
    local playerExp = rewards.adventureExp
    playerExp = math.floor(playerExp)
    local oldLv = playerData.level or 1
    playerData.exp = (playerData.exp or 0) + playerExp
    ExpTable.autoLevelUpPlayer(playerData)
    PDM.MarkDirty(uid, "player")
    if playerData.level > oldLv then
        HeroService.SyncHeroLevelsToPlayerLevel(uid, playerData.level)
    end

    -- 4) 展示时已生成的真实装备 → 背包
    local grantedCount = 0
    local skippedFull = 0
    for _, equip in ipairs(rewards.grantedEquips or {}) do
        if EquipmentSystem.isInventoryFull(equipData) then
            skippedFull = skippedFull + 1
        else
            EquipmentSystem.addToInventory(equipData, equip)
            grantedCount = grantedCount + 1
        end
    end
    if grantedCount > 0 then
        PDM.MarkDirty(uid, "equipment")
    end
    if skippedFull > 0 then
        print("[OfflineService][WARN] inventory full, skipped equips=" .. skippedFull
            .. " uid=" .. tostring(uid))
    end

    -- 5) 卷轴掉落 → 货币
    local scrollDropGroups = { rewards.scrollDrops }
    local scrollDirty = false
    for _, scrollDrops in ipairs(scrollDropGroups) do
        for scrollField, count in pairs(scrollDrops or {}) do
            local amount = math.floor(count)
            if amount > 0 then
                currency[scrollField] = (currency[scrollField] or 0) + amount
                scrollDirty = true
            end
        end
    end
    if scrollDirty then
        PDM.MarkDirty(uid, "currency")
    end

    -- 清理待领取
    pendingRewards[uid] = nil

    -- 领取成功后更新 lastOnlineTime
    local newLOT = os.time()
    sessionData.lastOnlineTime = newLOT
    PDM.MarkDirty(uid, "session")

    print("[OfflineService] claimed offline rewards uid=" .. tostring(uid)
        .. " gold=" .. goldAmount)

    return true, nil, {
        gold      = goldAmount,
        heroExp   = perHeroExp,
        playerExp = playerExp,
    }
end

-- ======================== 标记开场剧情完成 ========================

--- 标记开场剧情已完成
---@param uid number
---@return boolean ok, string? err, table? result
function OfflineService.MarkIntroCompleted(uid)
    local sessionData = PDM.GetModule(uid, "session")
    if not sessionData then
        return false, "session 数据未加载"
    end
    if sessionData.introCompleted then
        return true, nil, { alreadyCompleted = true }
    end
    sessionData.introCompleted = true
    PDM.MarkDirty(uid, "session")
    print("[OfflineService] MARK_INTRO_COMPLETED uid=" .. tostring(uid))
    return true, nil, {}
end

-- ======================== 清除轮回标志 ========================

--- 清除轮回标志（入场动画播放完毕后由客户端调用）
---@param uid number
---@return boolean ok, string? err
function OfflineService.ClearReincarnation(uid)
    local sessionData = PDM.GetModule(uid, "session")
    if not sessionData then
        return false, "session 数据未加载"
    end
    if not sessionData.hasReincarnated then
        return true  -- 已经是 false，幂等
    end
    sessionData.hasReincarnated = false
    PDM.MarkDirty(uid, "session")
    print("[OfflineService] CLEAR_REINCARNATION uid=" .. tostring(uid))
    return true
end

-- ======================== 断线处理 ========================

--- 玩家断线时：最终结算 + 快照 + 更新 lastOnlineTime
---@param uid number
function OfflineService.OnPlayerDisconnect(uid)
    if pendingRewards[uid] then
        -- 有未领取的离线奖励说明玩家停在面板没进入游戏，不更新
        print("[OfflineService] OnPlayerDisconnect SKIPPED (pendingRewards exists) uid=" .. tostring(uid))
        return
    end

    local battleData = PDM.GetModule(uid, "battle")
    local heroesData = PDM.GetModule(uid, "heroes")

    if battleData then
        -- 1. 最终结算剩余 idleAccumSec
        local accumSec = battleData.idleAccumSec or 0
        if accumSec > 0 then
            local heroCount = heroesData and heroesData.deployed and #heroesData.deployed or 0
            local stageConfig = StageProvider.Get()
            local incomeStageId, dropStageId = OfflineCalc.resolveIdleStageAnchors(battleData, stageConfig)
            if incomeStageId > 0 and heroCount > 0 then
                local rewards = OfflineCalc.calcOnlineIdleRewards(accumSec, incomeStageId, heroCount, dropStageId, stageConfig)
                if rewards then
                    -- 内联 grantRewards（简化版，断线时仅写数据不推送客户端）
                    local ok, err = pcall(function()
                        local currency = PDM.GetModule(uid, "currency")
                        local playerData = PDM.GetModule(uid, "player")
                        local lootbox = PDM.GetModule(uid, "lootbox")
                        if not currency or not playerData or not lootbox then return end

                        -- 金币
                        currency.gold = (currency.gold or 0) + math.floor(rewards.gold)
                        PDM.MarkDirty(uid, "currency")

                        -- 英雄经验
                        local deployed = heroesData.deployed or {}
                        if #deployed > 0 then
                            local perHeroExp = math.floor(rewards.adventurerExp / #deployed + 0.5)
                            for _, heroId in ipairs(deployed) do
                                local numId = tonumber(heroId) or heroId
                                local heroData = heroesData.roster and heroesData.roster[numId]
                                if heroData then
                                    heroData.exp = (heroData.exp or 0) + perHeroExp
                                    ExpTable.autoLevelUpHero(heroData)
                                end
                            end
                            PDM.MarkDirty(uid, "heroes")
                            HeroService.ApplyResonanceSync(uid)
                        end

                        -- 远征经验
                        local oldLv = playerData.level or 1
                        playerData.exp = (playerData.exp or 0) + math.floor(rewards.adventureExp)
                        ExpTable.autoLevelUpPlayer(playerData)
                        PDM.MarkDirty(uid, "player")
                        if playerData.level > oldLv then
                            HeroService.SyncHeroLevelsToPlayerLevel(uid, playerData.level)
                        end

                        -- 装备种子
                        for _, seed in ipairs(rewards.equipSeeds or {}) do
                            local count = seed.count or 1
                            for _ = 1, count do
                                LootBoxSystem.addSeed(lootbox, seed.stageId, seed.quality, seed.level)
                            end
                        end
                        PDM.MarkDirty(uid, "lootbox")

                        -- 卷轴
                        for scrollField, count in pairs(rewards.scrollDrops or {}) do
                            local amount = math.floor(count)
                            if amount > 0 then
                                currency[scrollField] = (currency[scrollField] or 0) + amount
                            end
                        end
                        PDM.MarkDirty(uid, "currency")
                    end)

                    if ok then
                        battleData.idleAccumSec = 0
                        battleData.lastIdleClaimTime = os.time()
                        print(string.format(
                            "[OfflineService] disconnect final settle uid=%s accumSec=%.1f gold=%d",
                            tostring(uid), accumSec, math.floor(rewards.gold)))
                    else
                        -- 失败：保留 idleAccumSec，下次上线合并到离线时长
                        print("[OfflineService][ERROR] disconnect settle FAILED uid="
                            .. tostring(uid) .. " err=" .. tostring(err))
                    end
                end
            end
        end

        -- 2. 快照出战英雄数（离线结算用）
        local deployed = heroesData and heroesData.deployed or {}
        battleData.idleHeroCount = #deployed

        -- 3. 设置模式为离线（阻止 Update handler 继续累加）
        battleData.battleMode = "offline"

        PDM.MarkDirty(uid, "battle")
    end

    -- 4. 更新 lastOnlineTime
    local sessionData = PDM.GetModule(uid, "session")
    if sessionData then
        sessionData.lastOnlineTime = os.time()
        PDM.MarkDirty(uid, "session")
    end
end

-- ======================== 工具方法 ========================

--- 检查玩家是否有未领取的离线奖励
---@param uid number
---@return boolean
function OfflineService.HasPendingRewards(uid)
    return pendingRewards[uid] ~= nil
end

--- 断线时清理内存中的待领取数据
---@param uid number
function OfflineService.Cleanup(uid)
    if pendingRewards[uid] then
        print("[OfflineService] cleanup pending rewards uid=" .. tostring(uid))
        pendingRewards[uid] = nil
    end
end

return OfflineService
