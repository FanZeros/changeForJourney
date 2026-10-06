-- ============================================================================
-- CharacterPower - 装备应用 / 战力计算 / 角标刷新（玩法不变）
-- ============================================================================

local M = {}

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

    local function refreshPowerCache()
        local talentsData = ClientDispatcher.get("talents") or PlayerStore.Get("talents")
        local litNodes = talentsData and talentsData.litNodes or nil
        if litNodes then
            HC.setDefaultLitNodes(litNodes)
        end

        -- 名册缓存与列表索引一致；订阅刷新也覆盖未出战的已拥有英雄。
        -- 沿用 rebuildRoster 的正式战力缺省队口径，不受当前视图影响。
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

        local teams = get("teams") or {}
        local ownedSet = get("ownedSet") or {}
        local teamPowerCaches = get("teamPowerCaches")
        local runtimeOnlyPowerCaches = {}
        local runtimePerHero = litNodes and TalentEffect.calcRuntimeOnlyPower(litNodes) or 0
        for t = 1, TEAM_COUNT do
            local team = teams[t] or teams[tostring(t)]
            local slots = team and team.slots or {}
            local cache = teamPowerCaches[t]
            local deployedCount = 0
            for i = 1, MAX_SLOTS do
                local slot = slots[i]
                local heroId = slot and tonumber(slot.heroId)
                if slot and slot.state == "occupied" and heroId and ownedSet[heroId] then
                    if cache then cache[i] = calcHeroPower(heroId, i, t) end
                    deployedCount = deployedCount + 1
                elseif cache then
                    cache[i] = 0
                end
            end
            runtimeOnlyPowerCaches[t] = runtimePerHero * deployedCount
        end
        set("runtimeOnlyPowerCaches", runtimeOnlyPowerCaches)
        set("runtimeOnlyPowerCache", runtimeOnlyPowerCaches[1] or 0)

        -- 顶栏保持队1口径；各队标题和当前队接口使用对应队的缓存。
        local total = runtimeOnlyPowerCaches[1] or 0
        local mainCache = teamPowerCaches[1] or {}
        for i = 1, MAX_SLOTS do
            total = total + (mainCache[i] or 0)
        end

        GameState.setPower(total)
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
        findHeroDeployPosition = findHeroDeployPosition,
        calcHeroPower = calcHeroPower,
        calcHeroEstimate = calcHeroEstimate,
        refreshPowerCache = refreshPowerCache,
        refreshUpgradeBadgeCache = refreshUpgradeBadgeCache,
        refreshNavBadge = refreshNavBadge,
        POWER_SKIP = POWER_SKIP,
    }
end

return M
