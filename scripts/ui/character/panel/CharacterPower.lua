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
    local RelicBridge = deps.RelicBridge
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

    local function calcHeroPower(heroId, partySlot)
        local teamSlots = get("teamSlots")
        if not partySlot then
            for i = 1, MAX_SLOTS do
                local slot = teamSlots[i]
                if slot.state == "occupied" and slot.heroId == heroId then
                    partySlot = i
                    break
                end
            end
        end
        local level = getHeroLevel(heroId)
        local ownedSet = get("ownedSet")
        local ownData = ownedSet[heroId]
        local advBranch = ownData and ownData.advBranch or nil
        local awakening = ownData and ownData.awakening or nil
        local hero = HC.createHero(heroId, level, advBranch, awakening, ownData and ownData.extraTalent)
        if not hero or not hero.attrs then return 0 end
        local a = hero.attrs

        applyEquippedItems(a, heroId, partySlot)
        RelicBridge.applyToUnit(a, hero.classId)
        if partySlot then
            ArtifactBridge.applyToUnit(a, partySlot)
        end

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
        total = total + AwakeningConfig.calcTotalCombatPower(heroId, awakening)
        total = total + (a.artifactPowerBonus or 0)

        return math.floor(total + 0.5)
    end

    local function refreshPowerCache()
        local talentsData = ClientDispatcher.get("talents") or PlayerStore.Get("talents")
        local litNodes = talentsData and talentsData.litNodes or nil
        if litNodes then
            HC.setDefaultLitNodes(litNodes)
        end

        local teams = get("teams")
        local teamPowerCaches = get("teamPowerCaches")
        local deployedCount = 0
        for t = 1, TEAM_COUNT do
            local slots = teams[t] and teams[t].slots
            local cache = teamPowerCaches[t]
            if slots and cache then
                for i = 1, MAX_SLOTS do
                    local slot = slots[i]
                    if slot.state == "occupied" and slot.heroId then
                        cache[i] = calcHeroPower(slot.heroId, i)
                        if t == 1 then deployedCount = deployedCount + 1 end
                    else
                        cache[i] = 0
                    end
                end
            end
        end

        local total = 0
        do
            local mainCache = teamPowerCaches[1]
            for i = 1, MAX_SLOTS do
                total = total + (mainCache[i] or 0)
            end
        end

        local runtimeOnlyPowerCache
        if litNodes and deployedCount > 0 then
            runtimeOnlyPowerCache = TalentEffect.calcRuntimeOnlyPower(litNodes) * deployedCount
        else
            runtimeOnlyPowerCache = 0
        end
        set("runtimeOnlyPowerCache", runtimeOnlyPowerCache)
        total = total + runtimeOnlyPowerCache

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
        calcHeroPower = calcHeroPower,
        refreshPowerCache = refreshPowerCache,
        refreshUpgradeBadgeCache = refreshUpgradeBadgeCache,
        refreshNavBadge = refreshNavBadge,
        POWER_SKIP = POWER_SKIP,
    }
end

return M
