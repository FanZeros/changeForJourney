-- ============================================================================
-- CharacterPower - 装备应用 / 战力计算 / 角标刷新（玩法不变）
-- ============================================================================

local M = {}

--- 只读查询英雄真实出战位置，兼容面板槽对象与存档 ID 槽（含 0 空位/字符串键）。
--- 已提供的 teams[t].slots 是该队权威布局；仅队1缺布局时兼容旧 deployed。
--- 显式快照绝不回读存档，未上阵返回 nil,nil，不借用编辑队或旧镜像槽。
---@param heroId number|string
---@param heroesData table|nil
---@return number|nil partySlot
---@return number|nil teamIdx
function M.findHeroDeployment(heroId, heroesData)
    local id = tonumber(heroId)
    if not id or id <= 0 or id ~= math.floor(id) then return nil, nil end
    local teams = heroesData and heroesData.teams
    for teamIdx = 1, 3 do
        local team = teams and (teams[teamIdx] or teams[tostring(teamIdx)])
        local slots = team and team.slots
        if type(slots) ~= "table" then
            slots = teamIdx == 1 and heroesData and heroesData.deployed or nil
        end
        if type(slots) == "table" then
            for partySlot = 1, 4 do
                local slot = slots[partySlot] or slots[tostring(partySlot)]
                local sourceId = slot
                if type(slot) == "table" then
                    sourceId = slot.state == "occupied" and slot.heroId or nil
                end
                if tonumber(sourceId) == id then return partySlot, teamIdx end
            end
        end
    end
    return nil, nil
end

function M.bind(deps)
    local AD = deps.AD
    local HC = deps.HC
    local ClientDispatcher = deps.ClientDispatcher
    local PlayerStore = deps.PlayerStore
    local EquipmentSystem = deps.EquipmentSystem
    local EquipmentConfig = deps.EquipmentConfig
    local EquipmentSetSystem = require("systems.EquipmentSetSystem")
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
        local heroEq = EquipmentSystem.getHeroSlots(eqData, heroId)
        if not heroEq then
            return nil
        end

        local heroesData = ClientDispatcher.get("heroes") or PlayerStore.Get("heroes")
        if partySlot == nil then
            partySlot = EquipmentSystem.findPartySlot(heroesData and heroesData.deployed, heroId)
        end

        local appliedSeqs = {}
        local equippedArmorType = nil
        for _, slotKey in ipairs(EquipmentConfig.SLOTS) do
            local seq = heroEq[slotKey]
            if seq and not appliedSeqs[seq] then
                local equip = eqData.inventory[tostring(seq)]
                if equip then
                    EquipmentSystem.hydrate(equip)
                    local slotBoost = EquipmentSystem.getAscendBoost(equip)
                    EquipmentSystem.applyToUnit(attrs, equip, seq, slotBoost)
                    appliedSeqs[seq] = true
                    if slotKey == "armor" and equip.type then
                        equippedArmorType = AD.ARMOR_TYPE_ENUM[equip.type]
                    end
                end
            end
        end
        EquipmentSetSystem.applyToUnit(
            attrs, eqData, heroId,
            EquipmentSystem.getFromInventory, EquipmentSystem.getHeroSlots)
        return equippedArmorType
    end

    local function getHeroLevel(heroId)
        local ownedSet = get("ownedSet")
        local ownData = ownedSet[heroId]
        return ownData and ownData.level or 1
    end

    -- 构建真实存档管线的英雄单位；普通卡面/名册从全部队伍查询，不受编辑队影响。
    -- 显式队/槽仍供正式槽位缓存使用；未上阵英雄不应用任何队槽神器。
    ---@return table|nil hero 含 attrs/classId/awakening 的单位；失败返回 nil
    local function buildHeroAttrs(heroId, partySlot, teamIdx)
        local realSlot, realTeam = M.findHeroDeployment(heroId, { teams = get("teams") })
        if realSlot then
            partySlot = partySlot or realSlot
            teamIdx = teamIdx or realTeam
        else
            partySlot, teamIdx = nil, nil
        end
        local level = getHeroLevel(heroId)
        local ownedSet = get("ownedSet")
        local ownData = ownedSet[heroId]
        local advBranch = ownData and ownData.advBranch or nil
        local awakening = ownData and ownData.awakening or nil
        local hero = HC.createHero(heroId, level, advBranch, awakening, ownData and ownData.extraTalent)
        if not hero or not hero.attrs then return nil end
        local a = hero.attrs

        applyEquippedItems(a, heroId, partySlot)
        if partySlot then
            ArtifactBridge.applyToUnit(a, partySlot, nil, teamIdx)
        end

        hero.awakening = awakening
        return hero
    end

    local function calcHeroPower(heroId, partySlot, teamIdx)
        local hero = buildHeroAttrs(heroId, partySlot, teamIdx)
        if not hero then return 0 end
        local a = hero.attrs

        local total = 0
        for key, meta in pairs(AD.META) do
            if not POWER_SKIP[key] and meta.valueModel and meta.valueModel > 0 then
                local val = a:get(key)
                if meta.dataType == AD.TYPE_PCT then
                    total = total + val * (meta.valueModel / 100)
                else
                    total = total + val * meta.valueModel
                end
            end
        end
        total = total + AwakeningConfig.calcTotalCombatPower(heroId, hero.awakening)
        total = total + (a.artifactPowerBonus or 0)

        return math.floor(total + 0.5)
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

    local runtimeOnlyPowerByTeam = {}

    local function getTotalPower(teamIdx)
        teamIdx = tonumber(teamIdx) or 1
        if teamIdx ~= math.floor(teamIdx) or teamIdx < 1 or teamIdx > TEAM_COUNT then return 0 end
        local teamPowerCaches = get("teamPowerCaches")
        local cache = teamPowerCaches[teamIdx] or {}
        local total = 0
        for i = 1, MAX_SLOTS do total = total + (cache[i] or 0) end
        return total + (runtimeOnlyPowerByTeam[teamIdx] or 0)
    end

    local function refreshPowerCache()
        local talentsData = ClientDispatcher.get("talents") or PlayerStore.Get("talents")
        local litNodes = talentsData and talentsData.litNodes or nil
        if litNodes then
            HC.setDefaultLitNodes(litNodes)
        end

        -- 名册与卡面共用英雄真实归属；切换编辑队不改变固定构筑的战力。
        local heroRoster = get("heroRoster")
        local rosterPowerCache = get("rosterPowerCache")
        if heroRoster and rosterPowerCache then
            for i, entry in ipairs(heroRoster) do
                if entry.owned then
                    rosterPowerCache[i] = calcHeroPower(entry.heroId)
                else
                    rosterPowerCache[i] = 0
                end
            end
        end

        local teams = get("teams")
        local teamPowerCaches = get("teamPowerCaches")
        local runtimePerHero = litNodes and TalentEffect.calcRuntimeOnlyPower(litNodes) or 0
        for t = 1, TEAM_COUNT do
            local slots = teams[t] and teams[t].slots
            local cache = teamPowerCaches[t]
            local deployedCount = 0
            if slots and cache then
                for i = 1, MAX_SLOTS do
                    local slot = slots[i]
                    if slot and slot.state == "occupied" and slot.heroId then
                        cache[i] = calcHeroPower(slot.heroId, i, t)
                        deployedCount = deployedCount + 1
                    else
                        cache[i] = 0
                    end
                end
            end
            -- 空队也覆盖为0，不能保留队一人数或上一份缓存。
            runtimeOnlyPowerByTeam[t] = runtimePerHero * deployedCount
        end

        -- 旧 scalar 保留给兼容绑定；正式总战力/顶栏仍只计队一，不改产品口径。
        set("runtimeOnlyPowerCache", runtimeOnlyPowerByTeam[1] or 0)
        GameState.setPower(getTotalPower(1))
        CharacterDetail.markPowerDirty()
    end

    local function refreshUpgradeBadgeCache()
        local ownedSet = get("ownedSet")
        local upgradeBadgeCache = {}
        -- 转职已迁到角色详情页签，可转职也计入角色页角标
        local okChurch, ChurchPage = pcall(require, "ui.church.ChurchPage")
        local canAdvance = (okChurch and ChurchPage.hasAdvanceForHero) and ChurchPage.hasAdvanceForHero or nil
        for heroId, _ in pairs(ownedSet) do
            local advance = canAdvance and canAdvance(heroId) or false
            if CharacterPanel.isHeroDeployed(heroId) then
                upgradeBadgeCache[heroId] = CharacterDetail.hasAnyUpgradeForHero(heroId)
                    or CharacterDetail.hasAwakeningUpgrade(heroId) or advance
            else
                upgradeBadgeCache[heroId] = CharacterDetail.hasAwakeningUpgrade(heroId) or advance
            end
        end
        set("upgradeBadgeCache", upgradeBadgeCache)
        return upgradeBadgeCache
    end

    local function refreshNavBadge()
        local upgradeBadgeCache = refreshUpgradeBadgeCache()
        local hasUpgrade = false
        for _, v in pairs(upgradeBadgeCache) do
            if v then
                hasUpgrade = true
                break
            end
        end
        BottomNav.setBadge(1, hasUpgrade)
        BottomNav.refreshTownBadge()
    end

    return {
        applyEquippedItems = applyEquippedItems,
        getHeroLevel = getHeroLevel,
        calcHeroPower = calcHeroPower,
        calcHeroEstimate = calcHeroEstimate,
        getTotalPower = getTotalPower,
        refreshPowerCache = refreshPowerCache,
        refreshUpgradeBadgeCache = refreshUpgradeBadgeCache,
        refreshNavBadge = refreshNavBadge,
        POWER_SKIP = POWER_SKIP,
    }
end

return M
