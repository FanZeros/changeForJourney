-- ============================================================================
-- BlacksmithEnhanceCache - 可强化缓存 / 角标查询（玩法不变）
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

    local function canEnhanceSlot(partySlot, equipSlot, slotEnhanceData, gold)
        local BlacksmithConfig = require("config.BlacksmithConfig")
        ---@diagnostic disable-next-line: assign-type-mismatch
        slotEnhanceData = slotEnhanceData or ClientDispatcher.get("slotEnhance") or PlayerStore.Get("slotEnhance")
        if not slotEnhanceData or not slotEnhanceData.levels then return false end
        gold = gold or GameState.getGold()

        local partyLevels = slotEnhanceData.levels[tostring(partySlot)]
            or slotEnhanceData.levels[partySlot]
        -- partyLevels 为 nil 表示该出战位从未强化过，所有槽位等级视为 0
        local curLevel = (partyLevels and partyLevels[equipSlot]) or 0
        -- 动态上限 = min(硬上限, 玩家等级限制)
        local maxLv = math.min(BlacksmithConfig.MAX_ENHANCE_LEVEL,
            ExpTable.getEnhanceLevelCap(GameState.getLevel()))
        if curLevel >= maxLv then return false end

        local nextLevel = curLevel + 1
        local cost = BlacksmithConfig.getEnhanceCost(nextLevel)
        if not cost then return false end

        local scrollField = BlacksmithConfig.SLOT_SCROLL_MAP[equipSlot]
        local scrollGetter = scrollField and BlacksmithEnhance.getScrollGetter(scrollField)
        local ownedScroll = 0
        if scrollGetter and GameState[scrollGetter] then
        ---@diagnostic disable-next-line: assign-type-mismatch
            ownedScroll = GameState[scrollGetter]()
        end
        return gold >= cost.gold and ownedScroll >= cost.scroll
    end

    local function canEnhancePartySlot(partySlot, slotEnhanceData, gold)
        -- 只有已上阵角色的出战位才能强化，空槽位/未解锁槽位不算
        local teamSlots = CharacterPanel.getTeamSlotsData()
        local slot = teamSlots and teamSlots[partySlot]
        if not slot or slot.state ~= "occupied" then return false end

        for _, equipSlot in ipairs(EQUIP_SLOT_ORDER) do
            if canEnhanceSlot(partySlot, equipSlot, slotEnhanceData, gold) then
                return true
            end
        end
        return false
    end

    local function refreshEnhanceCache()
        if not cache.dirty then return end
        cache.dirty = false

        -- 预取共享数据，避免 canEnhanceSlot 内部重复读取
        local slotEnhanceData = ClientDispatcher.get("slotEnhance") or PlayerStore.Get("slotEnhance")
        local gold = GameState.getGold()

        for i = 1, MAX_PARTY do
            cache.slotCanEnhance[i] = cache.slotCanEnhance[i] or {}
            local anyCanEnhance = false
            -- 只有已上阵角色的出战位才能强化
            local teamSlots = CharacterPanel.getTeamSlotsData()
            local slot = teamSlots and teamSlots[i]
            if slot and slot.state == "occupied" then
                for _, equipSlot in ipairs(EQUIP_SLOT_ORDER) do
                    local can = canEnhanceSlot(i, equipSlot, slotEnhanceData, gold)
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
        local BlacksmithConfig = require("config.BlacksmithConfig")
        local slotEnhanceData = ClientDispatcher.get("slotEnhance") or PlayerStore.Get("slotEnhance")
        if not slotEnhanceData or not slotEnhanceData.levels then return false end

        local gold = GameState.getGold()
        local teamSlots = CharacterPanel.getTeamSlotsData()

        for partySlot = 1, MAX_PARTY do
            -- 跳过空槽位和未解锁槽位：只有已上阵角色的装备槽才算可强化
            local slot = teamSlots and teamSlots[partySlot]
            if slot and slot.state == "occupied" then
                local partyLevels = slotEnhanceData.levels[tostring(partySlot)]
                    or slotEnhanceData.levels[partySlot]
                for _, equipSlot in ipairs(EQUIP_SLOT_ORDER) do
                    local curLevel = (partyLevels and partyLevels[equipSlot]) or 0
                    if curLevel < BlacksmithConfig.MAX_ENHANCE_LEVEL then
                        local nextLevel = curLevel + 1
                        local cost = BlacksmithConfig.getEnhanceCost(nextLevel)
                        if cost then
                            local scrollField = BlacksmithConfig.SLOT_SCROLL_MAP[equipSlot]
                            local scrollGetter = scrollField and BlacksmithEnhance.getScrollGetter(scrollField)
                            local ownedScroll = 0
                            if scrollGetter and GameState[scrollGetter] then
                            ---@diagnostic disable-next-line: assign-type-mismatch
                                ownedScroll = GameState[scrollGetter]()
                            end
                            if gold >= cost.gold and ownedScroll >= cost.scroll then
                                return true
                            end
                        end
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
