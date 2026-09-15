-- ============================================================================
-- BlacksmithConfig - 铁匠铺配置（双端共享）
-- 槽位强化等级表 + 品质消耗表(洗练/分解) + 槽位卷轴映射
-- 来源: docs/配置文件/建筑-铁匠铺.txt
-- ============================================================================

local BlacksmithConfig = {}

--- 最大强化等级
BlacksmithConfig.MAX_ENHANCE_LEVEL = 100

--- 槽位强化配置（100 级）
--- 每行: { goldCost, scrollCost, attrBoostPct }
--- attrBoostPct: 基础属性百分比加成（0.05 = 5%）
--- 索引 = 强化等级（从当前等级升到下一级的消耗）
BlacksmithConfig.ENHANCE_TABLE = {
    [1  ] = { gold = 100         , scroll = 2  , boost = 0.05 },
    [2  ] = { gold = 205         , scroll = 4  , boost = 0.10 },
    [3  ] = { gold = 415         , scroll = 6  , boost = 0.15 },
    [4  ] = { gold = 736         , scroll = 8  , boost = 0.20 },
    [5  ] = { gold = 1173        , scroll = 10 , boost = 0.25 },
    [6  ] = { gold = 2597        , scroll = 12 , boost = 0.30 },
    [7  ] = { gold = 3327        , scroll = 14 , boost = 0.35 },
    [8  ] = { gold = 4193        , scroll = 16 , boost = 0.40 },
    [9  ] = { gold = 5203        , scroll = 18 , boost = 0.45 },
    [10 ] = { gold = 6363        , scroll = 20 , boost = 0.50 },
    [11 ] = { gold = 11522       , scroll = 22 , boost = 0.55 },
    [12 ] = { gold = 13198       , scroll = 24 , boost = 0.60 },
    [13 ] = { gold = 15058       , scroll = 26 , boost = 0.65 },
    [14 ] = { gold = 17111       , scroll = 28 , boost = 0.70 },
    [15 ] = { gold = 19367       , scroll = 30 , boost = 0.75 },
    [16 ] = { gold = 32753       , scroll = 32 , boost = 0.80 },
    [17 ] = { gold = 35991       , scroll = 34 , boost = 0.85 },
    [18 ] = { gold = 39491       , scroll = 36 , boost = 0.90 },
    [19 ] = { gold = 43266       , scroll = 38 , boost = 0.95 },
    [20 ] = { gold = 47329       , scroll = 40 , boost = 1.00 },
    [21 ] = { gold = 77543       , scroll = 42 , boost = 1.05 },
    [22 ] = { gold = 83520       , scroll = 44 , boost = 1.10 },
    [23 ] = { gold = 89896       , scroll = 46 , boost = 1.15 },
    [24 ] = { gold = 96691       , scroll = 48 , boost = 1.20 },
    [25 ] = { gold = 103926      , scroll = 50 , boost = 1.25 },
    [26 ] = { gold = 167433      , scroll = 52 , boost = 1.30 },
    [27 ] = { gold = 178405      , scroll = 54 , boost = 1.35 },
    [28 ] = { gold = 190025      , scroll = 56 , boost = 1.40 },
    [29 ] = { gold = 202326      , scroll = 58 , boost = 1.45 },
    [30 ] = { gold = 215342      , scroll = 60 , boost = 1.50 },
    [31 ] = { gold = 343664      , scroll = 62 , boost = 1.55 },
    [32 ] = { gold = 363947      , scroll = 64 , boost = 1.60 },
    [33 ] = { gold = 385344      , scroll = 66 , boost = 1.65 },
    [34 ] = { gold = 407911      , scroll = 68 , boost = 1.70 },
    [35 ] = { gold = 431707      , scroll = 70 , boost = 1.75 },
    [36 ] = { gold = 685189      , scroll = 72 , boost = 1.80 },
    [37 ] = { gold = 723048      , scroll = 74 , boost = 1.85 },
    [38 ] = { gold = 762900      , scroll = 76 , boost = 1.90 },
    [39 ] = { gold = 804845      , scroll = 78 , boost = 1.95 },
    [40 ] = { gold = 848987      , scroll = 80 , boost = 2.00 },
    [41 ] = { gold = 1343155     , scroll = 82 , boost = 2.05 },
    [42 ] = { gold = 1414413     , scroll = 84 , boost = 2.10 },
    [43 ] = { gold = 1489334     , scroll = 86 , boost = 2.15 },
    [44 ] = { gold = 1568101     , scroll = 88 , boost = 2.20 },
    [45 ] = { gold = 1650906     , scroll = 90 , boost = 2.25 },
    [46 ] = { gold = 2606927     , scroll = 92 , boost = 2.30 },
    [47 ] = { gold = 2741873     , scroll = 94 , boost = 2.35 },
    [48 ] = { gold = 2883667     , scroll = 96 , boost = 2.40 },
    [49 ] = { gold = 3032650     , scroll = 98 , boost = 2.45 },
    [50 ] = { gold = 3189183     , scroll = 100, boost = 2.50 },
    [51 ] = { gold = 5030463     , scroll = 102, boost = 2.55 },
    [52 ] = { gold = 5287086     , scroll = 104, boost = 2.60 },
    [53 ] = { gold = 5556640     , scroll = 106, boost = 2.65 },
    [54 ] = { gold = 5839772     , scroll = 108, boost = 2.70 },
    [55 ] = { gold = 6137161     , scroll = 110, boost = 2.75 },
    [56 ] = { gold = 9674279     , scroll = 112, boost = 2.80 },
    [57 ] = { gold = 10163593    , scroll = 114, boost = 2.85 },
    [58 ] = { gold = 10677473    , scroll = 116, boost = 2.90 },
    [59 ] = { gold = 11217147    , scroll = 118, boost = 2.95 },
    [60 ] = { gold = 11783904    , scroll = 120, boost = 3.00 },
    [61 ] = { gold = 18568649    , scroll = 122, boost = 3.05 },
    [62 ] = { gold = 19503181    , scroll = 124, boost = 3.10 },
    [63 ] = { gold = 20484540    , scroll = 126, boost = 3.15 },
    [64 ] = { gold = 21515067    , scroll = 128, boost = 3.20 },
    [65 ] = { gold = 22597220    , scroll = 130, boost = 3.25 },
    [66 ] = { gold = 35600372    , scroll = 132, boost = 3.30 },
    [67 ] = { gold = 37386991    , scroll = 134, boost = 3.35 },
    [68 ] = { gold = 39263041    , scroll = 136, boost = 3.40 },
    [69 ] = { gold = 41232993    , scroll = 138, boost = 3.45 },
    [70 ] = { gold = 43301543    , scroll = 140, boost = 3.50 },
    [71 ] = { gold = 68210430    , scroll = 142, boost = 3.55 },
    [72 ] = { gold = 71628052    , scroll = 144, boost = 3.60 },
    [73 ] = { gold = 75216655    , scroll = 146, boost = 3.65 },
    [74 ] = { gold = 78984788    , scroll = 148, boost = 3.70 },
    [75 ] = { gold = 82941427    , scroll = 150, boost = 3.75 },
    [76 ] = { gold = 130643998   , scroll = 152, boost = 3.80 },
    [77 ] = { gold = 137183798   , scroll = 154, boost = 3.85 },
    [78 ] = { gold = 144050688   , scroll = 156, boost = 3.90 },
    [79 ] = { gold = 151261022   , scroll = 158, boost = 3.95 },
    [80 ] = { gold = 158831973   , scroll = 160, boost = 4.00 },
    [81 ] = { gold = 250172357   , scroll = 162, boost = 4.05 },
    [82 ] = { gold = 262689075   , scroll = 164, boost = 4.10 },
    [83 ] = { gold = 275831729   , scroll = 166, boost = 4.15 },
    [84 ] = { gold = 289631615   , scroll = 168, boost = 4.20 },
    [85 ] = { gold = 304121596   , scroll = 170, boost = 4.25 },
    [86 ] = { gold = 479004264   , scroll = 172, boost = 4.30 },
    [87 ] = { gold = 502963077   , scroll = 174, boost = 4.35 },
    [88 ] = { gold = 528119931   , scroll = 176, boost = 4.40 },
    [89 ] = { gold = 554534728   , scroll = 178, boost = 4.45 },
    [90 ] = { gold = 582270364   , scroll = 180, boost = 4.50 },
    [91 ] = { gold = 917089323   , scroll = 182, boost = 4.55 },
    [92 ] = { gold = 962952889   , scroll = 184, boost = 4.60 },
    [93 ] = { gold = 1011109733  , scroll = 186, boost = 4.65 },
    [94 ] = { gold = 1061674520  , scroll = 188, boost = 4.70 },
    [95 ] = { gold = 1114767646  , scroll = 190, boost = 4.75 },
    [96 ] = { gold = 1755773292  , scroll = 192, boost = 4.80 },
    [97 ] = { gold = 1843571557  , scroll = 194, boost = 4.85 },
    [98 ] = { gold = 1935759835  , scroll = 196, boost = 4.90 },
    [99 ] = { gold = 2032557627  , scroll = 198, boost = 4.95 },
    [100] = { gold = 2134195408  , scroll = 200, boost = 5.00 },
}

--- 装备槽位 → 对应卷轴货币字段映射
BlacksmithConfig.SLOT_SCROLL_MAP = {
    weapon    = "weaponScroll",
    offhand   = "offhandScroll",
    armor     = "armorScroll",
    accessory = "accessoryScroll",
}

--- 获取强化到指定等级的消耗和加成
--- 传入目标等级（即当前等级+1），返回升到该等级需要的消耗
---@param level number 目标强化等级 (1~100)
---@return {gold: number, scroll: number, boost: number}|nil
function BlacksmithConfig.getEnhanceCost(level)
    return BlacksmithConfig.ENHANCE_TABLE[level]
end

--- 获取指定等级的属性加成倍率
--- 等级 0 返回 0，等级 1~100 返回对应 boost
---@param level number 当前强化等级 (0~100)
---@return number 加成倍率（0.05 = 5%）
function BlacksmithConfig.getEnhanceBoost(level)
    if level <= 0 then return 0 end
    local entry = BlacksmithConfig.ENHANCE_TABLE[level]
    return entry and entry.boost or 0
end

--- 装备品质消耗配置（用于洗练/分解）
--- decBase/decScale: 分解精粹奖励基础与等级缩放
--- refBase/refInc/refLvScale: 洗练精粹消耗基础、递增、等级缩放
BlacksmithConfig.QUALITY_COST = {
    [1] = { decBase =  5, decScale = 0.1, refBase = 10, refInc = 1, refLvScale = 0.05 },
    [2] = { decBase = 10, decScale = 0.1, refBase = 20, refInc = 2, refLvScale = 0.05 },
    [3] = { decBase = 15, decScale = 0.1, refBase = 30, refInc = 3, refLvScale = 0.05 },
    [4] = { decBase = 20, decScale = 0.1, refBase = 40, refInc = 4, refLvScale = 0.05 },
    [5] = { decBase = 25, decScale = 0.1, refBase = 50, refInc = 5, refLvScale = 0.05 },
    [6] = { decBase = 30, decScale = 0.1, refBase = 60, refInc = 6, refLvScale = 0.05 },
}

--- 单件装备洗练次数上限（用于精粹计费；达到后仍可继续洗练，但次数与消耗不再上涨）
BlacksmithConfig.REFINE_COUNT_CAP = 20

--- 洗练时锁定词缀：精粹消耗倍率（锁定任意一条即整体 ×1.5）
BlacksmithConfig.REFINE_LOCK_COST_MULT = 1.5

--- 计费用洗练次数（不超过 CAP-1，保证第 20 次后消耗不再上涨）
---@param refineCount number|nil
---@return number
function BlacksmithConfig.getRefineBillCount(refineCount)
    local n = math.floor(tonumber(refineCount) or 0)
    return math.min(n, BlacksmithConfig.REFINE_COUNT_CAP - 1)
end

--- 洗练后写入的累计次数（不超过上限）
---@param refineCount number|nil
---@return number
function BlacksmithConfig.clampRefineCount(refineCount)
    local n = math.floor(tonumber(refineCount) or 0)
    return math.min(n, BlacksmithConfig.REFINE_COUNT_CAP)
end

--- 洗练成功后递增累计次数
---@param refineCount number|nil
---@return number
function BlacksmithConfig.nextRefineCount(refineCount)
    return BlacksmithConfig.clampRefineCount((tonumber(refineCount) or 0) + 1)
end

--- 计算单次洗练精粹消耗
---@param quality number
---@param equipLv number|nil
---@param refineCount number|nil 当前累计次数（计费时内部封顶）
---@param grip string|nil "twohand" 时翻倍
---@return number
function BlacksmithConfig.calcRefineEssenceCost(quality, equipLv, refineCount, grip)
    local q = quality or 1
    local qCost = BlacksmithConfig.QUALITY_COST[q] or BlacksmithConfig.QUALITY_COST[1]
    local billCount = BlacksmithConfig.getRefineBillCount(refineCount)
    local lv = equipLv or 1
    local cost = math.floor((qCost.refBase + billCount * qCost.refInc) * (1 + lv * qCost.refLvScale))
    if grip == "twohand" then
        cost = cost * 2
    end
    return cost
end

--- 锁定词缀后的洗练精粹消耗（lockedCount > 0 时整体 ×REFINE_LOCK_COST_MULT）
---@param cost number
---@param lockedCount number|nil
---@return number
function BlacksmithConfig.applyRefineLockCostMult(cost, lockedCount)
    if lockedCount and lockedCount > 0 then
        return math.floor(cost * BlacksmithConfig.REFINE_LOCK_COST_MULT + 0.5)
    end
    return cost
end

--- 分解时累计洗练精粹消耗（用于 50% 返还，次数同样封顶）
---@param quality number
---@param equipLv number|nil
---@param refineCount number|nil
---@param grip string|nil
---@return number
function BlacksmithConfig.calcTotalRefineSpent(quality, equipLv, refineCount, grip)
    local q = quality or 1
    local qCost = BlacksmithConfig.QUALITY_COST[q] or BlacksmithConfig.QUALITY_COST[1]
    local paidCount = BlacksmithConfig.clampRefineCount(refineCount)
    if paidCount <= 0 then return 0 end
    local lvMult = 1 + (equipLv or 1) * qCost.refLvScale
    local gripMult = (grip == "twohand") and 2 or 1
    local totalSpent = 0
    for i = 0, paidCount - 1 do
        totalSpent = totalSpent + math.floor((qCost.refBase + i * qCost.refInc) * lvMult) * gripMult
    end
    return totalSpent
end

return BlacksmithConfig

