-- ============================================================================
-- CharacterPower - 装备应用 / 战力计算 / 角标刷新（玩法不变）
-- ============================================================================

local M = {}
local EventBus = require("core.EventBus")
local GameEvents = require("config.GameEvents")

function M.bind(deps)
    local AD = deps.AD
    local HC = deps.HC
    local ClientDispatcher = deps.ClientDispatcher
    local PlayerStore = deps.PlayerStore
    local EquipmentSystem = deps.EquipmentSystem
    local EquipmentConfig = deps.EquipmentConfig
    local EquipmentSetSystem = require("systems.EquipmentSetSystem")
    local EquipmentPower = require("systems.EquipmentPower")
    local CPE = require("systems.CombatPowerEstimate")
    -- [927 遗物后端移除] RelicBridge 已删除，不再从 deps 取用
    local ArtifactBridge = deps.ArtifactBridge
    local AwakeningConfig = deps.AwakeningConfig
    local TalentEffect = deps.TalentEffect
    local GameState = deps.GameState
    local CharacterDetail = deps.CharacterDetail
    local CharacterPanel = deps.CharacterPanel
    local BottomNav = deps.BottomNav
    local MAX_SLOTS = deps.MAX_SLOTS
    local TEAM_COUNT = deps.TEAM_COUNT
    local get = deps.get
    local set = deps.set

    local POWER_SKIP = {
        [AD.STR] = true, [AD.AGI] = true, [AD.INT] = true,
        [AD.VIT] = true, [AD.LUK] = true, [AD.SPI] = true,
        [AD.HP]           = true,
        [AD.ATK_INTERVAL] = true,
        [AD.PHYS_RES]     = true,
        [AD.MAG_RES]      = true,
    }

    local function applyEquippedItems(attrs, heroId, partySlot)
        local eqData = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
        if not eqData or not eqData.inventory then
            return nil
        end
        EquipmentPower.applyEquipment(attrs, eqData, heroId)
        local heroEq = EquipmentSystem.getHeroSlots(eqData, heroId)
        local armor = heroEq and heroEq.armor and EquipmentSystem.getFromInventory(eqData, heroEq.armor)
        return armor and AD.ARMOR_TYPE_ENUM[armor.type] or nil
    end

    local function getHeroLevel(heroId)
        local ownedSet = get("ownedSet")
        local ownData = ownedSet[heroId]
        return ownData and ownData.level or 1
    end

    -- 槽位只在所属队里有意义；名册和详情缺省查全队，不读取活动视图。
    ---@param heroId number|string
    ---@param teamIdx? number
    ---@return number|nil slot
    ---@return number|nil team
    local function findHeroDeployPosition(heroId, teamIdx)
        local targetId = tonumber(heroId)
        if not targetId or targetId <= 0 then return nil, nil end
        local firstTeam, lastTeam = 1, TEAM_COUNT
        if teamIdx ~= nil then
            local requestedTeam = tonumber(teamIdx)
            if not requestedTeam or requestedTeam < 1 or requestedTeam > TEAM_COUNT
                or requestedTeam ~= math.floor(requestedTeam) then return nil, nil end
            firstTeam, lastTeam = requestedTeam, requestedTeam
        end
        local teams = get("teams") or {}
        for t = firstTeam, lastTeam do
            local team = teams[t] or teams[tostring(t)]
            local slots = team and team.slots or {}
            for i = 1, MAX_SLOTS do
                local slot = slots[i]
                if slot and slot.state == "occupied" and tonumber(slot.heroId) == targetId then
                    return i, t
                end
            end
        end
        return nil, nil
    end

    -- 正式战力与预估共用真实属性管线；槽位提示必须匹配英雄所属队。
    ---@return table|nil hero 含 attrs/classId/awakening 的单位；失败返回 nil
    local function buildHeroAttrs(heroId, partySlot, teamIdx)
        heroId = tonumber(heroId) or heroId
        local deployedSlot, deployedTeam = findHeroDeployPosition(heroId, teamIdx)
        local matchesSlot = partySlot == nil or tonumber(partySlot) == deployedSlot
        local level = getHeroLevel(heroId)
        local ownedSet = get("ownedSet")
        local ownData = ownedSet[heroId]
        local advBranch = ownData and ownData.advBranch or nil
        local awakening = ownData and ownData.awakening or nil
        local hero = HC.createHero(heroId, level, advBranch, awakening, ownData and ownData.extraTalent)
        if not hero or not hero.attrs then return nil end
        local a = hero.attrs

        applyEquippedItems(a, heroId, deployedSlot)
        if deployedSlot and matchesSlot then
            ArtifactBridge.applyToUnit(a, deployedSlot, nil, deployedTeam)
        end

        hero.awakening = awakening
        return hero
    end

    local function calcHeroPower(heroId, partySlot, teamIdx, wornBatches)
        local deployedSlot, deployedTeam = findHeroDeployPosition(heroId)
        local matches = (partySlot == nil or tonumber(partySlot) == deployedSlot)
            and (teamIdx == nil or tonumber(teamIdx) == deployedTeam)
        local owned = get("ownedSet") or {}
        local options = {
            heroData = owned[tonumber(heroId) or heroId],
            heroes = ClientDispatcher.get("heroes") or PlayerStore.Get("heroes"),
            equipment = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment"),
            artifacts = matches and (ClientDispatcher.get("artifacts") or PlayerStore.Get("artifacts")) or {},
            talents = ClientDispatcher.get("talents") or PlayerStore.Get("talents"),
        }
        -- 仅单次 refresh 内共享模块/已穿装备快照；不跨通知复用，不借错队神器。
        local batch = wornBatches and wornBatches[matches]
        if wornBatches and not batch then
            batch = EquipmentPower.createWornBatch(options)
            wornBatches[matches] = batch
        end
        local context = EquipmentPower.buildWornContext(heroId, options, batch)
        if not context then return 0 end
        return math.floor(context.currentPower + 0.5)
    end

    -- 实战预估（分项计价原型）：与 calcHeroPower 走同一条真实存档管线
    -- （装备/遗物/神器/觉醒），但按英雄伤害大类区别计价物攻/魔攻/治疗属性。
    -- ⚠️ 原型口径，仅供并列参考展示，不替换官方战力，不含觉醒战力加成的
    -- 分项拆分（觉醒/神器固定加成按官方原值并入，见下）。
    local function calcHeroEstimate(heroId, partySlot, teamIdx)
        local hero = buildHeroAttrs(heroId, partySlot, teamIdx)
        if not hero then return 0 end
        local a = hero.attrs
        local base, _category = CPE.estimate(a, a.atkType)
        -- 觉醒战力与神器加成沿用官方口径（原型不拆分其属性来源），保持与
        -- calcHeroPower 的可比性：两者都叠加同一份觉醒/神器固定值。
        local extra = AwakeningConfig.calcTotalCombatPower(heroId, hero.awakening)
            + (a.artifactPowerBonus or 0)
        return math.floor(base + extra + 0.5)
    end

    local function refreshPowerCache(cause)
        -- 此回调可早于评分订阅者；先失效，避免原地更新后红点仍用旧快照。
        EquipmentPower.invalidate()
        local talentsData = ClientDispatcher.get("talents") or PlayerStore.Get("talents")
        local litNodes = talentsData and talentsData.litNodes or nil
        HC.setDefaultLitNodes(litNodes)

        -- 仅在本轮刷新复用同英雄、同实际神器队/槽的计算，不跨通知缓存属性。
        -- 显式队/槽不匹配时仍走独立口径，不能拿名册的神器结果覆盖它。
        local refreshedPowers, wornBatches = {}, {}
        local function powerForRefresh(heroId, partySlot, teamIdx)
            local id = tonumber(heroId) or heroId
            local deployedSlot, deployedTeam = findHeroDeployPosition(id, teamIdx)
            local matchesSlot = partySlot == nil or tonumber(partySlot) == deployedSlot
            local context = deployedSlot and matchesSlot
                and (tostring(deployedTeam) .. ":" .. tostring(deployedSlot)) or "none"
            local key = tostring(id) .. ":" .. context
            local value = refreshedPowers[key]
            if value == nil then
                value = calcHeroPower(id, partySlot, teamIdx, wornBatches)
                refreshedPowers[key] = value
            end
            return value
        end

        -- 名册缓存与列表索引一致；订阅刷新也覆盖未出战的已拥有英雄。
        -- 沿用 rebuildRoster 的正式战力缺省队口径，不受当前视图影响。
        local heroRoster = get("heroRoster")
        local rosterPowerCache = get("rosterPowerCache")
        if heroRoster and rosterPowerCache then
            for i, entry in ipairs(heroRoster) do
                if entry.owned then
                    rosterPowerCache[i] = powerForRefresh(entry.heroId)
                else
                    rosterPowerCache[i] = 0
                end
            end
        end

        local teams = get("teams") or {}
        local ownedSet = get("ownedSet") or {}
        local teamPowerCaches = get("teamPowerCaches")
        local runtimeOnlyPowerCaches = {}
        -- 运行时节点已按各角色生效条件计入共享战力，不再按队伍人头重复加。
        local runtimePerHero = 0
        for t = 1, TEAM_COUNT do
            local team = teams[t] or teams[tostring(t)]
            local slots = team and team.slots or {}
            local cache = teamPowerCaches[t]
            local deployedCount = 0
            for i = 1, MAX_SLOTS do
                local slot = slots[i]
                local heroId = slot and tonumber(slot.heroId)
                if slot and slot.state == "occupied" and heroId and ownedSet[heroId] then
                    if cache then cache[i] = powerForRefresh(heroId, i, t) end
                    deployedCount = deployedCount + 1
                elseif cache then
                    cache[i] = 0
                end
            end
            runtimeOnlyPowerCaches[t] = runtimePerHero * deployedCount
        end
        set("runtimeOnlyPowerCaches", runtimeOnlyPowerCaches)
        set("runtimeOnlyPowerCache", runtimeOnlyPowerCaches[1] or 0)

        -- 全队缓存完成后一次发布快照；队2/3独立成长也会通知，不借活动队推测来源。
        local teamPowers = {}
        for t = 1, TEAM_COUNT do
            local teamTotal = runtimeOnlyPowerCaches[t] or 0
            local cache = teamPowerCaches[t] or {}
            for i = 1, MAX_SLOTS do teamTotal = teamTotal + (cache[i] or 0) end
            teamPowers[t] = teamTotal
        end
        -- 顶栏与选关继续使用队1，专用提示使用完整快照。
        GameState.setPower(teamPowers[1] or 0)
        CharacterDetail.markPowerDirty()
        EventBus.emit(GameEvents.TEAM_POWER_CHANGED, {
            powers = teamPowers,
            cause = cause,
            ready = CharacterPanel.isHeroesDataApplied and CharacterPanel.isHeroesDataApplied() or false,
        })
    end

    -- 正式战力立即发布；全库存换装角标允许跨帧，但只提交完整同版本结果。
    ---@type thread|nil
    local badgeJob = nil
    local badgeRevision = ""
    local completedRevision = ""
    local completedEquipmentBadges = {}
    local badgeDeadline, badgeSteps = 0, 0
    local BADGE_CPU_BUDGET = 0.001
    local BADGE_MAX_STEPS = 128

    -- 只冻结小规模名册/队孔的战斗字段；在线经验和金币每秒变化不应饿死候选任务。
    local function appendSignature(parts, value)
        if type(value) ~= "table" then
            local text = tostring(value)
            parts[#parts + 1] = type(value) .. ":" .. #text .. ":" .. text
            return
        end
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        parts[#parts + 1] = "{"
        for _, key in ipairs(keys) do
            appendSignature(parts, key)
            appendSignature(parts, value[key])
        end
        parts[#parts + 1] = "}"
    end

    local function badgeVersion()
        local parts = {}
        for _, key in ipairs({ "equipment", "artifacts", "talents" }) do
            parts[#parts + 1] = tostring(PlayerStore.GetRevision(key))
        end
        local owned = get("ownedSet") or {}
        local ids = {}
        for id in pairs(owned) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
        for _, id in ipairs(ids) do
            local hero = owned[id]
            appendSignature(parts, id)
            appendSignature(parts, hero.level)
            appendSignature(parts, hero.advBranch)
            appendSignature(parts, hero.awakening)
            appendSignature(parts, hero.extraTalent)
            appendSignature(parts, CharacterPanel.isHeroDeployed(id))
        end
        for team = 1, TEAM_COUNT or 0 do
            local teams = get("teams") or {}
            local slots = (teams[team] or teams[tostring(team)] or {}).slots or {}
            for slot = 1, MAX_SLOTS do
                local entry = slots[slot] or {}
                appendSignature(parts, entry.state)
                appendSignature(parts, entry.heroId)
            end
        end
        return table.concat(parts, "|")
    end

    local function badgeCheckpoint()
        badgeSteps = badgeSteps + 1
        if badgeSteps >= BADGE_MAX_STEPS or os.clock() >= badgeDeadline then
            coroutine.yield()
        end
    end

    local function buildEquipmentBadges(checkpoint)
        local result = {}
        for heroId in pairs(get("ownedSet") or {}) do
            if checkpoint then checkpoint() end
            result[heroId] = CharacterPanel.isHeroDeployed(heroId)
                and CharacterDetail.hasAnyUpgradeForHero(heroId, checkpoint) or false
        end
        return result
    end

    local function publishUpgradeBadges(equipmentBadges)
        local result, hasUpgrade = {}, false
        local okChurch, ChurchPage = pcall(require, "ui.church.ChurchPage")
        local canAdvance = okChurch and ChurchPage.hasAdvanceForHero
        for heroId in pairs(get("ownedSet") or {}) do
            local value = equipmentBadges[heroId] or CharacterDetail.hasAwakeningUpgrade(heroId)
                or (canAdvance and canAdvance(heroId)) or false
            result[heroId], hasUpgrade = value, hasUpgrade or value
        end
        set("upgradeBadgeCache", result)
        BottomNav.setBadge(1, hasUpgrade)
        return result
    end

    -- 显式调用仍同步返回；生产导航通知走下面的预算队列。
    local function refreshUpgradeBadgeCache()
        local result = buildEquipmentBadges()
        if PlayerStore.GetRevision then
            completedRevision, completedEquipmentBadges = badgeVersion(), result
            badgeJob, badgeRevision = nil, completedRevision
        end
        return publishUpgradeBadges(result)
    end

    local function refreshNavBadge()
        if PlayerStore.GetRevision then
            local revision = badgeVersion()
            if completedRevision == revision then
                badgeJob = nil
            elseif not badgeJob or badgeRevision ~= revision then
                badgeRevision = revision
                badgeJob = coroutine.create(function() return buildEquipmentBadges(badgeCheckpoint) end)
            end
            -- 金币/碎片只刷新小规模养成条件，不取消仍有效的全库存任务。
            publishUpgradeBadges(completedEquipmentBadges)
        else
            refreshUpgradeBadgeCache()
        end
        BottomNav.refreshTownBadge()
    end

    local function updateBadges()
        if not badgeJob then return end
        -- 同引用原地更新也由版本识别；丢弃旧任务，避免混用前后两次装备结果。
        if badgeRevision ~= badgeVersion() then refreshNavBadge() end
        if not badgeJob then return end
        local job = badgeJob
        badgeSteps, badgeDeadline = 0, os.clock() + BADGE_CPU_BUDGET
        local ok, result = coroutine.resume(job)
        if not ok then
            badgeJob = nil
            print("[CharacterPower] 角标预算任务失败: " .. tostring(result))
        elseif coroutine.status(job) == "dead" then
            badgeJob = nil
            if badgeRevision == badgeVersion() then
                completedRevision, completedEquipmentBadges = badgeRevision, result
                publishUpgradeBadges(result)
            end
        end
    end

    local function cancelBadgeRefresh()
        badgeJob, badgeRevision, completedRevision = nil, "", ""
        completedEquipmentBadges = {}
        set("upgradeBadgeCache", {})
        BottomNav.setBadge(1, false)
    end

    return {
        applyEquippedItems = applyEquippedItems,
        getHeroLevel = getHeroLevel,
        findHeroDeployPosition = findHeroDeployPosition,
        calcHeroPower = calcHeroPower,
        calcHeroEstimate = calcHeroEstimate,
        refreshPowerCache = refreshPowerCache,
        refreshUpgradeBadgeCache = refreshUpgradeBadgeCache,
        refreshNavBadge = refreshNavBadge,
        updateBadges = updateBadges,
        cancelBadgeRefresh = cancelBadgeRefresh,
        POWER_SKIP = POWER_SKIP,
    }
end

return M
