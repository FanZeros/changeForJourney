-- ============================================================================
-- OfflineService - 离线收益业务逻辑（统一挂机效率方案 v2）
-- 职责: 离线奖励计算、领取、生命周期管理
-- 层级: server/offline  |  通过 PDM 读写，禁止网络 IO
-- ============================================================================

local PDM              = require("server.character.PlayerDataManager")
local OfflineCalc      = require("systems.OfflineCalc")
local StageProvider    = require("shared.StageProvider")
local ExpTable         = require("config.ExpTable")
local LootBoxSystem    = require("systems.LootBoxSystem")
local EquipmentSystem  = require("systems.EquipmentSystem")
local CurrencyService  = require("server.currency.CurrencyService")
local HeroService      = require("server.hero.HeroService")

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
}

local function appendEquipPreviewItems(list, equipSeeds)
    for _, seed in ipairs(equipSeeds or {}) do
        local previewEquip = EquipmentSystem.generateRandom(seed.level, seed.quality)
        list[#list + 1] = {
            type       = "equip",
            templateId = previewEquip and previewEquip.templateId or nil,
            quality    = seed.quality,
            level      = seed.level,
            count      = seed.count,
        }
    end
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

--- 获取当日剩余额外奖励次数
---@param sessionData table
---@return number remaining
local function getRemainingBonusCount(sessionData)
    local today = getTodayDateStr()
    if sessionData.offlineBonusDate ~= today then
        return 3  -- BONUS_MAX_DAILY 保留兼容，后续移除
    end
    local used = sessionData.offlineBonusCount or 0
    return math.max(0, 3 - used)
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
    local stageConfig = StageProvider.GetForServer(PDM.GetServerId(uid))
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

    -- 计算额外 +2 小时的奖励预览（供面板展示，保持 bonus 机制兼容）
    local bonusSeconds = 7200
    local bonusRewards = OfflineCalc.calcOnlineIdleRewards(bonusSeconds, incomeStageId, heroCount, dropStageId, stageConfig)

    -- 构建面板展示数据（v2 结构）
    local panelData = {
        offlineSeconds = rewards.seconds,
        maxSeconds     = rewards.maxSeconds or OfflineCalc.MAX_SECONDS,
        totalKills     = rewards.kills,
        adventureExp   = rewards.adventureExp,
        adventurerExp  = rewards.adventurerExp,
        rewards        = {},
        -- 额外奖励信息（保持向后兼容）
        bonusRemaining = getRemainingBonusCount(sessionData),
        bonusMaxDaily  = 3,
        bonusSeconds   = bonusSeconds,
    }

    -- 额外奖励预览数据（供客户端增加显示值）
    if bonusRewards then
        panelData.bonusPreview = {
            gold          = bonusRewards.gold,
            adventureExp  = bonusRewards.adventureExp,
            adventurerExp = bonusRewards.adventurerExp,
            rewards       = {},
        }
        appendEquipPreviewItems(panelData.bonusPreview.rewards, bonusRewards.equipSeeds)
        appendScrollPreviewItems(panelData.bonusPreview.rewards, bonusRewards.scrollDrops)
    end

    -- 金币
    if rewards.gold > 0 then
        panelData.rewards[#panelData.rewards + 1] = {
            type   = "gold",
            amount = rewards.gold,
        }
    end

    -- 装备种子（展示为装备图标）
    appendEquipPreviewItems(panelData.rewards, rewards.equipSeeds)

    -- 卷轴掉落
    appendScrollPreviewItems(panelData.rewards, rewards.scrollDrops)

    -- 暂存到内存（包含 bonusRewards 供领取时使用）
    pendingRewards[uid] = { rewards = rewards, panelData = panelData, bonusRewards = bonusRewards }

    -- 返回面板数据，由 Server.lua 负责推送
    print("[OfflineService] offline reward ready uid=" .. tostring(uid)
        .. " gold=" .. rewards.gold .. " kills=" .. rewards.kills
        .. " seconds=" .. rewards.seconds)
    return panelData
end

-- ======================== 领取离线收益 ========================

--- 离线 +2 小时额外奖励：用特权点代替看广告时消耗的点数（固定 1，禁止一次扣光）
local OFFLINE_BONUS_PRIVILEGE_COST = 1

--- 领取离线收益
---@param uid number
---@param claimBonus boolean 是否领取额外 +2 小时奖励
---@param usePrivilege boolean 是否消耗特权点（而非看广告）
---@return boolean ok, string? err, table? result
function OfflineService.ClaimRewards(uid, claimBonus, usePrivilege)
    local pending = pendingRewards[uid]
    if not pending then
        return false, "无待领取的离线收益"
    end
    local rewards = pending.rewards

    -- 如果请求额外奖励，校验每日次数
    local sessionData = PDM.GetModule(uid, "session")
    if not sessionData then
        return false, "session 数据未加载"
    end

    local currency   = PDM.GetModule(uid, "currency")
    local heroesData = PDM.GetModule(uid, "heroes")
    local playerData = PDM.GetModule(uid, "player")
    local lootbox    = PDM.GetModule(uid, "lootbox")

    if not currency or not heroesData or not playerData or not lootbox then
        return false, "数据未加载"
    end

    local bonusApplied = false
    local bonusRewards = pending.bonusRewards
    local privilegeDeducted = 0

    if claimBonus then
        local remaining = getRemainingBonusCount(sessionData)
        if remaining <= 0 then
            return false, "今日额外奖励次数已用完"
        end
        if not bonusRewards then
            return false, "额外奖励数据异常"
        end
        -- 扣除特权点（如果使用特权点）— 固定只扣 1 点，不与余额挂钩
        if usePrivilege then
            local balBefore = math.max(0, math.floor(tonumber(currency.privilegePoint) or 0))
            local okDeduct, newBal = CurrencyService.Deduct(uid, "privilegePoint", OFFLINE_BONUS_PRIVILEGE_COST)
            if not okDeduct then
                print("[OfflineService] privilege deduct FAIL uid=" .. tostring(uid)
                    .. " need=" .. OFFLINE_BONUS_PRIVILEGE_COST
                    .. " bal=" .. tostring(balBefore))
                return false, "特权点不足"
            end
            privilegeDeducted = OFFLINE_BONUS_PRIVILEGE_COST
            print("[OfflineService] privilege deduct uid=" .. tostring(uid)
                .. " cost=" .. OFFLINE_BONUS_PRIVILEGE_COST
                .. " " .. tostring(balBefore) .. "→" .. tostring(newBal))
        end
        -- 更新每日计数
        local today = getTodayDateStr()
        if sessionData.offlineBonusDate ~= today then
            sessionData.offlineBonusDate  = today
            sessionData.offlineBonusCount = 0
        end
        sessionData.offlineBonusCount = (sessionData.offlineBonusCount or 0) + 1
        bonusApplied = true
    end

    -- 1) 金币（基础 + 额外奖励）
    local goldAmount = rewards.gold
    if bonusApplied then
        goldAmount = goldAmount + (bonusRewards.gold or 0)
    end
    goldAmount = math.floor(goldAmount)
    currency.gold = (currency.gold or 0) + goldAmount
    PDM.MarkDirty(uid, "currency")

    -- 2) 英雄经验（平分给出战英雄）
    local deployed = heroesData.deployed or {}
    local heroCount = #deployed
    local perHeroExp = 0
    if heroCount > 0 then
        local totalHeroExp = rewards.adventurerExp
        if bonusApplied then
            totalHeroExp = totalHeroExp + (bonusRewards.adventurerExp or 0)
        end
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

    -- 3) 冒险经验（玩家升级）
    local playerExp = rewards.adventureExp
    if bonusApplied then
        playerExp = playerExp + (bonusRewards.adventureExp or 0)
    end
    playerExp = math.floor(playerExp)
    local oldLv = playerData.level or 1
    playerData.exp = (playerData.exp or 0) + playerExp
    ExpTable.autoLevelUpPlayer(playerData)
    PDM.MarkDirty(uid, "player")
    if playerData.level > oldLv then
        HeroService.SyncHeroLevelsToPlayerLevel(uid, playerData.level)
    end

    -- 4) 装备种子 → 战利品缓冲
    local equipSeedGroups = { rewards.equipSeeds }
    if bonusApplied then
        equipSeedGroups[#equipSeedGroups + 1] = bonusRewards.equipSeeds
    end
    local equipDirty = false
    for _, equipSeeds in ipairs(equipSeedGroups) do
        for _, seed in ipairs(equipSeeds or {}) do
            local count = seed.count or 1
            for _ = 1, count do
                LootBoxSystem.addSeed(lootbox, seed.stageId, seed.quality, seed.level)
            end
            equipDirty = true
        end
    end
    if equipDirty then
        PDM.MarkDirty(uid, "lootbox")
    end

    -- 5) 卷轴掉落 → 货币
    local scrollDropGroups = { rewards.scrollDrops }
    if bonusApplied then
        scrollDropGroups[#scrollDropGroups + 1] = bonusRewards.scrollDrops
    end
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
        .. " bonus=" .. tostring(bonusApplied)
        .. " usePrivilege=" .. tostring(usePrivilege)
        .. " privilegeCost=" .. tostring(privilegeDeducted)
        .. " privilegeLeft=" .. tostring(currency.privilegePoint or 0)
        .. " gold=" .. goldAmount)

    -- 含特权点扣除时立即刷盘，缩短断线丢扣账窗口
    if privilegeDeducted > 0 then
        PDM.FlushImmediate(uid)
    end

    return true, nil, {
        bonusApplied = bonusApplied,
        gold         = goldAmount,
        heroExp      = perHeroExp,
        playerExp    = playerExp,
        privilegeCost = privilegeDeducted,
        privilegeLeft = currency.privilegePoint or 0,
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
            local stageConfig = StageProvider.GetForServer(PDM.GetServerId(uid))
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

                        -- 冒险经验
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
