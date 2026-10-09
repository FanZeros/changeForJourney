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
local BlacksmithConfig = require("config.BlacksmithConfig")
local EquipmentSystem  = require("systems.EquipmentSystem")
local CurrencyService  = require("rules.currency.CurrencyService")
local HeroService      = require("rules.hero.HeroService")
local DC               = require("config.DungeonConfig")

local OfflineService = {}

---@class OfflineHeroEntry
---@field id number
---@field team number

---@class OfflinePendingReward
---@field rewards OfflineTeamRewards
---@field panelData table

-- 内存中暂存的一份待领取离线奖励（不持久化）；重推不重新计算/骰装备。
---@type table<number, OfflinePendingReward>
local pendingRewards = {}

-- ======================== 常量 ========================

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
            -- [奖励可点击] 附带完整装备实例，供弹窗点击查看只读详情（纯 table，可序列化）
            equip      = equip,
        }
    end
end

--- 已拥有英雄数据兼容存档数字/字符串键，不修改名册。
---@param heroesData table
---@param heroId number
---@return table|nil
local function getHeroData(heroesData, heroId)
    local roster = heroesData.roster
    if type(roster) ~= "table" then return nil end
    local hero = roster[heroId] or roster[tostring(heroId)]
    return type(hero) == "table" and hero or nil
end

--- 收集已解锁非空队伍的真实出战英雄；整队脏槽位不发奖，不用 deployed 复活明确空队。
--- 初算只用存档；阵容晚到后的预览/领取可读已应用的面板槽位。
---@param heroesData table|nil
---@param battleProgress table|nil
---@param useLive boolean|nil
---@return OfflineHeroEntry[]
local function collectUnlockedHeroes(heroesData, battleProgress, useLive)
    ---@type OfflineHeroEntry[]
    local entries = {}
    if type(heroesData) ~= "table" then return entries end
    local unlockedTeams = ExpTable.getUnlockedTeamCount(battleProgress)
    ---@type table|nil
    local teams = type(heroesData.teams) == "table" and heroesData.teams or nil
    local hasTeamConfig = heroesData.teams ~= nil
        and (type(heroesData.teams) ~= "table" or next(heroesData.teams) ~= nil)
    if useLive ~= false then
        local okPanel, CharacterPanel = pcall(require, "ui.character.panel.CharacterPanel")
        if okPanel and CharacterPanel.getTeamSlotIds and CharacterPanel.isHeroesDataApplied
            and CharacterPanel.isHeroesDataApplied() then
            local liveTeams = CharacterPanel.getTeamSlotIds()
            if type(liveTeams) == "table" then
                teams = liveTeams
                hasTeamConfig = true
            end
        end
    end
    local seen = {}
    for teamIdx = 1, unlockedTeams do
        ---@type table|nil
        local slots = nil
        if hasTeamConfig then
            local team = teams and (teams[teamIdx] or teams[tostring(teamIdx)])
            if type(team) == "table" and type(team.slots) == "table" then slots = team.slots end
        elseif teamIdx == 1 and type(heroesData.deployed) == "table" then
            slots = heroesData.deployed -- 仅无队表的旧版存档 fallback 队1
        end
        if slots then
            local valid = true
            local slotCount = 0
            local localSeen = {}
            ---@type OfflineHeroEntry[]
            local teamEntries = {}
            for key, heroId in pairs(slots) do
                local slotIdx = type(key) == "number" and math.tointeger(key) or nil
                local id = (type(heroId) == "number" or type(heroId) == "string")
                    and math.tointeger(tonumber(heroId) or -1) or nil
                slotCount = slotCount + 1
                if not slotIdx or slotIdx < 1 or slotIdx > (ExpTable.TEAM_MAX_SLOTS or 4)
                    or not id or id < 0 then
                    valid = false
                elseif id > 0 then
                    if localSeen[id] or seen[id] or not getHeroData(heroesData, id) then
                        valid = false
                    else
                        localSeen[id] = true
                        teamEntries[#teamEntries + 1] = { id = id, team = teamIdx }
                    end
                end
            end
            -- 稀疏/超长槽位也算脏配置，不用 ipairs 截断后凭空凑出非空队。
            if slotCount ~= #slots or slotCount > (ExpTable.TEAM_MAX_SLOTS or 4) then valid = false end
            if valid then
                table.sort(teamEntries, function(a, b) return a.id < b.id end)
                for _, entry in ipairs(teamEntries) do
                    seen[entry.id] = true
                    entries[#entries + 1] = entry
                end
            end
        end
    end
    return entries
end

--- 从存档已解锁非空队伍构造计算参数。账户 max 只用于拒绝脏越界，不作为收益关卡。
---@param heroesData table
---@param battleData table
---@param stageConfig table
---@param dungeonData table|nil
---@return OfflineTeamSpec[]
local function collectOfflineTeams(heroesData, battleData, stageConfig, dungeonData)
    ---@type OfflineTeamSpec[]
    local result = {}
    local counts = {}
    for _, hero in ipairs(collectUnlockedHeroes(heroesData, battleData, false)) do
        counts[hero.team] = (counts[hero.team] or 0) + 1
    end
    -- 非表但非空值不是旧档缺字段，不以 currentStageId 绕过脏队表。
    if battleData.teamStageIds ~= nil and type(battleData.teamStageIds) ~= "table" then return result end
    local savedStages = type(battleData.teamStageIds) == "table" and battleData.teamStageIds or {}
    local challengeSources = type(battleData.offlineChallengeSources) == "table"
        and battleData.offlineChallengeSources or {}
    local maxId = math.tointeger(tonumber(battleData.maxStageId) or 0)
    local maxPrevious = maxId and stageConfig.getTerminalPrevStageId(maxId)
    local maxRank = maxPrevious and maxPrevious + 0.5 or maxId or 0
    for teamIdx = 1, ExpTable.getUnlockedTeamCount(battleData) do
        local value = savedStages[tostring(teamIdx)]
        if value == nil then value = savedStages[teamIdx] end
        if value == nil and teamIdx == 1 then value = battleData.currentStageId end
        local stageId = (type(value) == "number" or type(value) == "string")
            and math.tointeger(tonumber(value) or 0) or nil
        local heroCount = counts[teamIdx] or 0
        local challenge = challengeSources[tostring(teamIdx)] or challengeSources[teamIdx]
        if challenge ~= nil then
            -- 明确覆盖来源不能因无效快照退回主线；塔三队参与，离线只保留零产出说明。
            if type(challenge) == "table" and heroCount > 0 then
                local sourceId = math.tointeger(tonumber(challenge.stageId) or 0)
                if challenge.sourceKind == "tower" and challenge.paused == true then
                    local TC = require("config.TowerConfig")
                    local floor = sourceId and sourceId - 400000 or 0
                    if sourceId and floor >= 1 and floor <= TC.MAX_FLOOR then
                        result[#result + 1] = { teamIdx = teamIdx, stageId = sourceId,
                            heroCount = heroCount, sourceKind = "tower", paused = true,
                            sourceName = "通天塔 第" .. floor .. "层" }
                    end
                elseif challenge.sourceKind == "dungeon" and sourceId
                    and DC.decodeStageId(sourceId)
                    and DC.isStageUnlocked(sourceId, battleData, dungeonData) then
                    local entry = stageConfig.getStage(sourceId)
                    result[#result + 1] = { teamIdx = teamIdx, stageId = sourceId,
                        heroCount = heroCount, sourceKind = "dungeon", sourceName = entry and entry.name }
                end
            end
        elseif stageId and stageId > 0 and heroCount > 0 and stageConfig.getStage(stageId) then
            local allowed = true
            if stageConfig.isResourceStage and stageConfig.isResourceStage(stageId) then
                allowed = DC.isStageUnlocked(stageId, battleData, dungeonData)
            else
                local previous = stageConfig.getTerminalPrevStageId(stageId)
                local stageRank = previous and previous + 0.5 or stageId
                -- 缺 max 的旧档只允许队1已保存当前关；不凭空给其他队伍最高关收益。
                if maxRank > 0 then allowed = stageRank <= maxRank
                else allowed = teamIdx == 1 end
            end
            if allowed then
                result[#result + 1] = { teamIdx = teamIdx, stageId = stageId, heroCount = heroCount }
            end
        end
    end
    return result
end

--- 预览和领取共用每队经验分配；资源队不会分到主线队的经验池。
--- 无 teamRewards 的旧内存数据仅队1兼容，不对多队均分账户总池。
---@param heroesData table
---@param rewards OfflineTeamRewards
---@param battleProgress table|nil
---@return table[] { heroId, teamIdx, expGain }
local function buildHeroExpGrants(heroesData, rewards, battleProgress)
    local grants = {}
    local entries = collectUnlockedHeroes(heroesData, battleProgress)
    local counts = {}
    for _, entry in ipairs(entries) do counts[entry.team] = (counts[entry.team] or 0) + 1 end
    ---@type table<number, OfflineTeamReward>
    local byTeam = {}
    if type(rewards.teamRewards) == "table" then
        for _, reward in ipairs(rewards.teamRewards) do byTeam[reward.teamIdx] = reward end
    else
        byTeam[1] = {
            teamIdx = 1, stageId = 0, heroCount = counts[1] or 0,
            gold = 0, diamond = 0, adventureExp = 0, kills = 0, equipSeeds = {}, scrollDrops = {},
            adventurerExp = rewards.adventurerExp or 0,
        }
    end
    for _, entry in ipairs(entries) do
        local teamReward = byTeam[entry.team]
        if teamReward and (teamReward.adventurerExp or 0) > 0 then
            -- 阵容缩小不放大缺席者份额；新增队员也不提高本队基准份额，取整沿用旧口径。
            local divisor = math.max(counts[entry.team], teamReward.heroCount or 0)
            local perHeroExp = math.floor(teamReward.adventurerExp / divisor + 0.5)
            grants[#grants + 1] = { heroId = entry.id, teamIdx = entry.team, expGain = perHeroExp }
        end
    end
    return grants
end

--- 构建出战队员的升级预览（只读；每队使用自身经验和实际出战人数倍率）。
---@param heroesData table|nil
---@param rewards OfflineTeamRewards
---@param battleProgress table|nil
---@return table[]
local function buildHeroExpPreview(heroesData, rewards, battleProgress)
    local preview = {}
    if type(heroesData) ~= "table" then return preview end
    for _, grant in ipairs(buildHeroExpGrants(heroesData, rewards, battleProgress)) do
        local numId = grant.heroId
        local heroData = getHeroData(heroesData, numId)
        if heroData then
            local beforeLv = heroData.level or 1
            local beforeExp = heroData.exp or 0
            local sim = ExpTable.simulateHeroExp(beforeLv, beforeExp, grant.expGain)
            local cfg = HeroConfig.get(numId)
            preview[#preview + 1] = {
                heroId     = numId,
                name       = (cfg and cfg.name) or ("#" .. tostring(numId)),
                quality    = cfg and cfg.quality or 1,
                teamIdx    = grant.teamIdx,
                startLevel = beforeLv,
                startExp   = beforeExp,
                level      = sim.level,
                exp        = sim.exp,
                maxExp     = sim.maxExp,
                levelGain  = sim.gain,
                expGain    = grant.expGain,
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

--- 结算来源只读副本；面板不得按当前界面、最高主线或首通奖励重新推断。
---@param rewards OfflineTeamRewards
---@param stageConfig table
---@return table[]
local function buildTeamSources(rewards, stageConfig)
    local sources = {}
    for _, reward in ipairs(rewards.teamRewards or {}) do
        local entry = stageConfig.getStage(reward.stageId)
        local id, floor = DC.decodeStageId(reward.stageId)
        local sourceStageId = entry and (entry.sourceStageId or entry.id) or nil
        local equipCount = 0
        for _, seed in ipairs(reward.equipSeeds or {}) do equipCount = equipCount + (seed.count or 0) end
        local scrollDrops = {}
        for key, amount in pairs(reward.scrollDrops or {}) do scrollDrops[key] = amount end
        sources[#sources + 1] = {
            teamIdx = reward.teamIdx, stageId = reward.stageId, sourceStageId = sourceStageId,
            sourceKind = reward.sourceKind or (id and "resource" or "main"),
            sourceName = reward.sourceName or (entry and entry.name) or "未知来源",
            resourceDungeonId = id, resourceFloor = floor,
            heroCount = reward.heroCount, paused = reward.paused == true,
            gold = reward.gold, diamond = reward.diamond,
            adventureExp = reward.adventureExp, adventurerExp = reward.adventurerExp,
            kills = reward.kills, equipCount = equipCount, scrollDrops = scrollDrops,
            seconds = rewards.seconds, effectiveSeconds = rewards.effectiveSeconds,
        }
    end
    return sources
end

-- ======================== 生命周期 ========================

--- 获取今日 UTC+8 日期字符串
---@return string "YYYY-MM-DD"
local function getTodayDateStr()
    local UTC8_OFFSET = 28800
    local t = os.time() + UTC8_OFFSET
    return os.date("!%Y-%m-%d", t)
end


--- 阵容晚于弹窗到达时，按当前槽位重算队员经验预览。
---@param uid number
---@return table[]|nil
function OfflineService.RebuildHeroPreview(uid)
    local pending = pendingRewards[uid]
    if not pending or not pending.rewards then return nil end
    local heroesData = PDM.GetModule(uid, "heroes")
    if not heroesData then return nil end
    local battleProgress = PDM.GetModule(uid, "battle")
    local preview = buildHeroExpPreview(heroesData, pending.rewards, battleProgress)
    pending.panelData.heroExpPreview = preview
    return preview
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

    local offlineSeconds = math.max(0, now - lastOnline)
    local battleData = PDM.GetModule(uid, "battle")
    -- 单机在线战斗已按击杀发奖；旧在线累积器不应再计入离线时长。
    if battleData and (battleData.idleAccumSec or 0) > 0 then
        battleData.idleAccumSec = 0
        PDM.MarkDirty(uid, "battle")
    end

    -- 不满足最低离线时间
    if offlineSeconds < OfflineCalc.MIN_SECONDS then
        if battleData and battleData.offlineChallengeSources ~= nil then
            battleData.offlineChallengeSources = nil
            PDM.MarkDirty(uid, "battle")
        end
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

    -- 每支已解锁非空队伍在各自保存的当前关结算，idleHeroCount 旧账户快照不跨队挪用。
    local stageConfig = StageProvider.Get()
    local dungeonData = PDM.GetModule(uid, "dungeon")
    local teams = collectOfflineTeams(heroesData, battleData, stageConfig, dungeonData)
    local rewards = OfflineCalc.calcTeamOfflineRewards(offlineSeconds, teams, stageConfig)
    -- 覆盖战斗在冷启动不恢复；本次参数已捕获，待领期间靠内存奖励防重。
    if battleData.offlineChallengeSources ~= nil then
        battleData.offlineChallengeSources = nil
        PDM.MarkDirty(uid, "battle")
    end
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
        diamond        = rewards.diamond,
        heroExpPreview = buildHeroExpPreview(heroesData, rewards, battleData),
        teamSources    = buildTeamSources(rewards, stageConfig),
        rewards        = {},
        -- [7日硬顶] 面板展示封顶信息
        hardCapSeconds  = rewards.hardCapSeconds or OfflineCalc.HARD_CAP_SECONDS,
        cappedByHardCap = rewards.cappedByHardCap or false,
        tailRatio       = rewards.tailRatio or OfflineCalc.TAIL_RATIO,
        rawSeconds      = rewards.rawSeconds,
    }

    -- 金币
    if rewards.gold > 0 then
        panelData.rewards[#panelData.rewards + 1] = {
            type   = "gold",
            amount = rewards.gold,
        }
    end

    -- 黑钻展示沿用 diamond 类型，领取写入 currency.gems。
    if rewards.diamond > 0 then
        panelData.rewards[#panelData.rewards + 1] = { type = "diamond", amount = rewards.diamond }
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
        .. " gold=" .. rewards.gold .. " diamond=" .. rewards.diamond
        .. " teams=" .. #rewards.teamRewards .. " kills=" .. rewards.kills
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
    local lootboxData = PDM.GetModule(uid, "lootbox")
    local equipCount = #(rewards.grantedEquips or {})
    if not lootboxData and EquipmentSystem.getInventoryCount(equipData) + equipCount
        > EquipmentSystem.MAX_INVENTORY then
        return false, "遗匣数据未加载"
    end

    -- 1) 金币/黑钻；本地字段仍是 gems，展示/回执保持 diamond。
    local goldAmount = math.floor(rewards.gold or 0)
    local diamondAmount = math.floor(rewards.diamond or 0)
    currency.gold = (currency.gold or 0) + goldAmount
    currency.gems = (currency.gems or 0) + diamondAmount
    PDM.MarkDirty(uid, "currency")

    -- 2) 每队英雄只领取本队经验，忽略可过期/可篡改的面板 expGain。
    local battleProgress = PDM.GetModule(uid, "battle")
    local heroExpGrants = buildHeroExpGrants(heroesData, rewards, battleProgress)
    local heroDirty = false
    local perHeroExp = 0 -- 旧回执仅能代表一致份额；多队不一致时用 heroExpGrants。
    local sameShare = true
    for i, grant in ipairs(heroExpGrants) do
        local heroData = getHeroData(heroesData, grant.heroId)
        if heroData and grant.expGain > 0 then
            heroData.exp = (heroData.exp or 0) + grant.expGain
            ExpTable.autoLevelUpHero(heroData)
            heroDirty = true
        end
        if i == 1 then perHeroExp = grant.expGain
        elseif perHeroExp ~= grant.expGain then sameShare = false end
    end
    if not sameShare then perHeroExp = 0 end
    if heroDirty then
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

    -- 4) 展示时已生成的真实装备 → 背包；满包转入遗匣，不重骰或丢弃。
    local inventoryCount, lootboxCount = 0, 0
    local lootboxEquips = {}
    for _, equip in ipairs(rewards.grantedEquips or {}) do
        local destination = LootBoxSystem.deliverEquipment(lootboxData, equipData, equip)
        if destination == "lootbox" then
            lootboxCount = lootboxCount + 1
            lootboxEquips[#lootboxEquips + 1] = {
                type = "equip", templateId = equip.templateId, quality = equip.quality,
                level = equip.level, slot = equip.slot, equip = equip, destination = destination,
            }
        else
            inventoryCount = inventoryCount + 1
        end
    end
    if inventoryCount > 0 then
        PDM.MarkDirty(uid, "equipment")
    end
    if lootboxCount > 0 then
        PDM.MarkDirty(uid, "lootbox")
        print("[OfflineService] 满包装备已入遗匣=" .. lootboxCount
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
        .. " gold=" .. goldAmount .. " diamond=" .. diamondAmount)

    return true, nil, {
        gold      = goldAmount,
        diamond   = diamondAmount,
        heroExp   = perHeroExp,
        heroExpGrants = heroExpGrants,
        playerExp = playerExp,
        lootboxEquips = lootboxEquips,
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
            local entries = collectUnlockedHeroes(heroesData, battleData)
            local heroCount = #entries
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
                        if #entries > 0 then
                            local perHeroExp = math.floor(rewards.adventurerExp / #entries + 0.5)
                            for _, entry in ipairs(entries) do
                                local heroData = heroesData.roster and heroesData.roster[entry.id]
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

                        -- 装备种子（符合自动分解条件的直接转精粹，与击杀掉落同一语义）
                        local equipData = PDM.GetModule(uid, "equipment")
                        local autoSettings = (equipData and equipData.settings) or nil
                        local autoEssence = 0
                        for _, seed in ipairs(rewards.equipSeeds or {}) do
                            local count = seed.count or 1
                            for _ = 1, count do
                                local q, lv = seed.quality or 1, seed.level or 1
                                if BlacksmithConfig.shouldAutoDecompose(autoSettings, q, lv) then
                                    local essence = BlacksmithConfig.calcAutoDecomposeEssence(q, lv)
                                    autoEssence = autoEssence + essence
                                    BlacksmithConfig.recordAutoDecompose(lootbox, q, lv, essence)
                                else
                                    LootBoxSystem.addSeed(lootbox, seed.stageId, q, lv)
                                end
                            end
                        end
                        PDM.MarkDirty(uid, "lootbox")
                        if autoEssence > 0 then
                            CurrencyService.Add(uid, "essence", autoEssence)
                            print("[Offline] auto-decompose essence=+" .. autoEssence .. " uid=" .. tostring(uid))
                        end

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

        -- 2. 快照已解锁队伍的真实出战人数（排除空槽 0 与锁队）
        battleData.idleHeroCount = #collectUnlockedHeroes(heroesData, battleData)

        -- 3. 设置模式为离线（阻止 Update handler 继续累加）
        battleData.battleMode = "offline"

        PDM.MarkDirty(uid, "battle")
    end

    OfflineService.MarkOnline(uid)
end

-- ======================== 在线时间边界 ========================

--- 仅推进在线时刻，不额外结算挂机收益；单机战斗收益已按击杀发放。
---@param uid number
function OfflineService.MarkOnline(uid)
    if pendingRewards[uid] then return end
    local sessionData = PDM.GetModule(uid, "session")
    if not sessionData or (sessionData.lastOnlineTime or 0) <= 0 then return end
    local now = os.time()
    if now > sessionData.lastOnlineTime then
        sessionData.lastOnlineTime = now
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

--- 远征概览使用已加载快照；沿用领取资格，不访问 PDM/session 或待领奖励。
---@param heroesData table|nil
---@param battleData table|nil
---@param dungeonData table|nil
---@param seconds number|nil
---@return OfflineTeamRewards|nil
function OfflineService.PreviewTeamIncome(heroesData, battleData, dungeonData, seconds)
    if type(heroesData) ~= "table" or type(battleData) ~= "table" then return nil end
    local config = StageProvider.Get()
    local teams = collectOfflineTeams(heroesData, battleData, config, dungeonData)
    return OfflineCalc.previewTeamOfflineRewards(seconds or 3600, teams, config)
end

return OfflineService
