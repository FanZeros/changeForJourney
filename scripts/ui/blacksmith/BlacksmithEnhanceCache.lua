-- ============================================================================
-- BlacksmithEnhanceCache - 可升阶角标。只看装备自己的 ascendLevel，不读格子。
-- ============================================================================

local M = {}

function M.bind(deps)
    local ClientDispatcher = deps.ClientDispatcher
    local PlayerStore = deps.PlayerStore
    local GameState = deps.GameState
    local CharacterPanel = deps.CharacterPanel
    local ExpTable = deps.ExpTable
    local BlacksmithEnhance = deps.BlacksmithEnhance
    local EQUIP_SLOT_ORDER = deps.EQUIP_SLOT_ORDER
    local MAX_PARTY = deps.MAX_PARTY
    local cache = deps.cache

    local function equippedAt(partySlot, equipSlot)
        local teamSlots = CharacterPanel.getTeamSlotsData()
        local slot = teamSlots and teamSlots[partySlot]
        if not slot or slot.state ~= "occupied" or not slot.heroId then
            return nil
        end
        local eqData = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
        if not eqData or not eqData.inventory then return nil end
        local EquipmentSystem = require("systems.EquipmentSystem")
        local heroEq = EquipmentSystem.getHeroSlots(eqData, slot.heroId)
        local seq = heroEq and heroEq[equipSlot]
        if not seq then return nil end
        local equip = eqData.inventory[tostring(seq)] or eqData.inventory[seq]
        if equip then EquipmentSystem.hydrate(equip) end
        return equip
    end

    local function canAfford(equip, equipSlot, gold)
        if not equip then return false end
        local BlacksmithConfig = require("config.BlacksmithConfig")
        local EquipmentSystem = require("systems.EquipmentSystem")
        gold = gold or GameState.getGold()
        local curLevel = EquipmentSystem.getAscendLevel(equip)
        local maxLv = math.min(BlacksmithConfig.MAX_ENHANCE_LEVEL,
            ExpTable.getEnhanceLevelCap(GameState.getLevel()))
        if curLevel >= maxLv then return false end
        local cost = BlacksmithConfig.getAscendCost(curLevel + 1)
        if not cost then return false end
        local scrollField = BlacksmithConfig.SLOT_SCROLL_MAP[equip.slot or equipSlot]
        local scrollGetter = scrollField and BlacksmithEnhance.getScrollGetter(scrollField)
        local ownedScroll = 0
        if scrollGetter and GameState[scrollGetter] then
            ---@diagnostic disable-next-line: assign-type-mismatch
            ownedScroll = GameState[scrollGetter]()
        end
        return gold >= cost.gold and ownedScroll >= cost.scroll
    end

    -- 旧签名仍接收 slotEnhanceData，调用方不用改；格子数据已不再读取。
    local function canEnhanceSlot(partySlot, equipSlot, _slotEnhanceData, gold)
        return canAfford(equippedAt(partySlot, equipSlot), equipSlot, gold)
    end

    local function canEnhancePartySlot(partySlot, _slotEnhanceData, gold)
        local teamSlots = CharacterPanel.getTeamSlotsData()
        local slot = teamSlots and teamSlots[partySlot]
        if not slot or slot.state ~= "occupied" then return false end
        for _, equipSlot in ipairs(EQUIP_SLOT_ORDER) do
            if canEnhanceSlot(partySlot, equipSlot, nil, gold) then
                return true
            end
        end
        return false
    end

    local function refreshEnhanceCache()
        if not cache.dirty then return end
        cache.dirty = false
        local gold = GameState.getGold()
        for i = 1, MAX_PARTY do
            cache.slotCanEnhance[i] = cache.slotCanEnhance[i] or {}
            local anyCanEnhance = false
            local teamSlots = CharacterPanel.getTeamSlotsData()
            local slot = teamSlots and teamSlots[i]
            if slot and slot.state == "occupied" then
                for _, equipSlot in ipairs(EQUIP_SLOT_ORDER) do
                    local can = canEnhanceSlot(i, equipSlot, nil, gold)
                    cache.slotCanEnhance[i][equipSlot] = can
                    if can then anyCanEnhance = true end
                end
            else
                for _, equipSlot in ipairs(EQUIP_SLOT_ORDER) do
                    cache.slotCanEnhance[i][equipSlot] = false
                end
            end
            cache.partyCanEnhance[i] = anyCanEnhance
        end
    end

    local function getCachedPartyCanEnhance(partySlot)
        refreshEnhanceCache()
        return cache.partyCanEnhance[partySlot] or false
    end

    local function getCachedSlotCanEnhance(partySlot, equipSlot)
        refreshEnhanceCache()
        local ps = cache.slotCanEnhance[partySlot]
        return ps and ps[equipSlot] or false
    end

    local function canEnhanceAny()
        local gold = GameState.getGold()
        local teamSlots = CharacterPanel.getTeamSlotsData()
        for partySlot = 1, MAX_PARTY do
            local slot = teamSlots and teamSlots[partySlot]
            if slot and slot.state == "occupied" then
                for _, equipSlot in ipairs(EQUIP_SLOT_ORDER) do
                    if canEnhanceSlot(partySlot, equipSlot, nil, gold) then
                        return true
                    end
                end
            end
        end
        return false
    end

    return {
        canEnhanceSlot = canEnhanceSlot,
        canEnhancePartySlot = canEnhancePartySlot,
        refreshEnhanceCache = refreshEnhanceCache,
        getCachedPartyCanEnhance = getCachedPartyCanEnhance,
        getCachedSlotCanEnhance = getCachedSlotCanEnhance,
        canEnhanceAny = canEnhanceAny,
    }
end

return M
