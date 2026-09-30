-- ============================================================================
-- BlacksmithEnhanceCache - 可升阶角标。只看装备自己的 ascendLevel，不读格子。
-- 铁匠铺强化已改为"选装备"（含背包），角标按全量装备遍历计算 canEnhanceAny。
-- ============================================================================

local M = {}

function M.bind(deps)
    local ClientDispatcher = deps.ClientDispatcher
    local PlayerStore = deps.PlayerStore
    local GameState = deps.GameState
    local ExpTable = deps.ExpTable
    local BlacksmithEnhance = deps.BlacksmithEnhance
    local cache = deps.cache

    --- 单件装备当前是否可升阶（等级未满 + 金币/对应卷轴足够升一级）
    local function canEnhance(equip, gold)
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
        local scrollField = BlacksmithConfig.SLOT_SCROLL_MAP[equip.slot]
        local scrollGetter = scrollField and BlacksmithEnhance.getScrollGetter(scrollField)
        local ownedScroll = 0
        if scrollGetter and GameState[scrollGetter] then
            ---@diagnostic disable-next-line: assign-type-mismatch
            ownedScroll = GameState[scrollGetter]()
        end
        return gold >= cost.gold and ownedScroll >= cost.scroll
    end

    cache.canEnhance = canEnhance

    local function refreshEnhanceCache()
        if not cache.dirty then return end
        cache.dirty = false
        local gold = GameState.getGold()
        local eqData = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
        local any = false
        if eqData and eqData.inventory then
            for _, equip in pairs(eqData.inventory) do
                if canEnhance(equip, gold) then
                    any = true
                    break
                end
            end
        end
        cache.anyCanEnhance = any
    end

    local function canEnhanceAny()
        refreshEnhanceCache()
        return cache.anyCanEnhance or false
    end

    return {
        canEnhance = canEnhance,
        refreshEnhanceCache = refreshEnhanceCache,
        canEnhanceAny = canEnhanceAny,
    }
end

return M
