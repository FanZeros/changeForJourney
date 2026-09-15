-- ============================================================================
-- BattleLayout - 战斗布阵（单一事实源，双模式）
-- [strip] 三行并行战斗: 每场战斗一个 948x360 条带，8 卡单线——
--         我方 4 张一排在左半段、敌方 4 张一排在右半段，水平对峙
-- [classic] 原竖屏全页战斗: 上敌排(CY=804)/下我排(CY=1760) 横排居中
-- 坐标契约:
--   strip   : X = 阵营内索引横向展开(我左/敌右), Y = 行中心 STRIP_CY
--   classic : X = 队伍内索引横向居中展开,    Y = 阵营行基准
-- 动画偏移契约(渲染侧):
--   lunge/charge 等 offsetY 沿"朝向敌方"轴; classic 映射到 Y,
--   strip 映射到 X: screenDX = -offset(两阵营统一成立)
-- ============================================================================

local BattleLayout = {}

-- ---- 模式 ----
BattleLayout.MODE = "classic"   -- "classic" | "strip"
function BattleLayout.setMode(m)
    if m == "strip" or m == "classic" then
        BattleLayout.MODE = m
    end
end

-- ---- 卡片原始尺寸（两模式通用；strip 渲染时乘 CARD_SCALE）----
BattleLayout.CARD_W = 198
BattleLayout.CARD_H = 438

-- ======================== strip 模式（三行并行战斗条带） ========================
-- 条带设计空间 = 948x360（窗口像素 1:1，由 BattleTriPage 逐行平移/裁剪）
BattleLayout.STRIP_W     = 948
BattleLayout.STRIP_H     = 360
BattleLayout.CARD_SCALE  = 0.48                       -- 条带内卡牌缩放(95x210)
BattleLayout.STRIP_CY    = BattleLayout.STRIP_H * 0.5         -- 180
BattleLayout.STRIP_MARGIN = 30                            -- 两端留白
BattleLayout.STRIP_PITCH  = 100                     -- 同阵营卡间距（中心距）
-- 我方从右(前排/靠中)向左排布；敌方从左(前排/靠中)向右排布
-- → 双方 1 号位都在中央对峙位，4 号位在屏幕两端，完全镜像对称
BattleLayout.STRIP_ALLY_X0  = BattleLayout.STRIP_MARGIN
    + BattleLayout.CARD_W * BattleLayout.CARD_SCALE * 0.5
    + 3 * BattleLayout.STRIP_PITCH                                    -- ≈377.5（我方前排位）
BattleLayout.STRIP_ENEMY_X0 = BattleLayout.STRIP_W
    - BattleLayout.STRIP_MARGIN - BattleLayout.CARD_W * BattleLayout.CARD_SCALE * 0.5
    - 3 * BattleLayout.STRIP_PITCH                                    -- ≈570.5（敌方前排位）

BattleLayout.MAX_PER_SIDE = 4

-- ---- 前后排受击权重 ----
-- 1号位(前排/靠中心)被攻击概率最高；4 槽权重表 5/4/2/2（前排被击概率约为后排 2.5 倍）
-- 由技能树天赋可修改（HIT_WEIGHTS 动态覆写，见横屏三栏方案 · 前后排×技能树规划）
BattleLayout.HIT_WEIGHTS = { 5, 4, 2, 2 }

--- 阵营内第 idx 槽位的受击权重（配合加权随机选取使用）
---@param idx number 槽位（1=前排）
---@return number
function BattleLayout.hitWeight(idx)
    idx = math.max(1, math.min(BattleLayout.MAX_PER_SIDE, math.floor(tonumber(idx) or 1)))
    return BattleLayout.HIT_WEIGHTS[idx] or 1
end

--- strip: 阵营内第 idx 张卡的中心
---@param group string "ally" | "enemy"
---@param idx number
---@return number cx
---@return number cy
local function stripCardPos(group, idx)
    idx = math.max(1, math.min(BattleLayout.MAX_PER_SIDE, math.floor(tonumber(idx) or 1)))
    local cx
    if group == "ally" then
        cx = BattleLayout.STRIP_ALLY_X0 - (idx - 1) * BattleLayout.STRIP_PITCH
    else
        cx = BattleLayout.STRIP_ENEMY_X0 + (idx - 1) * BattleLayout.STRIP_PITCH
    end
    return cx, BattleLayout.STRIP_CY
end

-- ======================== classic 模式（原竖屏全页战斗） ========================
BattleLayout.DESIGN_W  = 1080
BattleLayout.ENEMY_ROW_CY = 804
BattleLayout.ALLY_ROW_CY  = 1760
BattleLayout.CLASSIC_CARD_SPACING = 7

--- classic: 队伍内第 idx 张卡的中心（横排居中，恢复原始公式）
local function classicCardPos(group, idx, count)
    count = math.max(1, count or BattleLayout.MAX_PER_SIDE)
    local totalW = count * BattleLayout.CARD_W + (count - 1) * BattleLayout.CLASSIC_CARD_SPACING
    local startCX = (BattleLayout.DESIGN_W - totalW) * 0.5 + BattleLayout.CARD_W * 0.5
    idx = math.max(1, idx or 1)
    local cx = startCX + (idx - 1) * (BattleLayout.CARD_W + BattleLayout.CLASSIC_CARD_SPACING)
    local cy = (group == "ally") and BattleLayout.ALLY_ROW_CY or BattleLayout.ENEMY_ROW_CY
    return cx, cy
end

-- ======================== 统一入口 ========================

--- 阵营判定（己方卡带 heroId，敌方卡带 monsterId；过滤副本亦正确）
---@param units table[]|nil
---@return string|nil "ally" | "enemy" | nil
function BattleLayout.detectGroup(units)
    local first = units and units[1]
    if not first then return nil end
    if first.heroId ~= nil then return "ally" end
    if first.monsterId ~= nil then return "enemy" end
    return nil
end

--- 卡片中心坐标（按当前模式）
---@param group string "ally" | "enemy"
---@param idx number
---@param count number|nil classic 模式用于横向居中展开
---@return number cx
---@return number cy
function BattleLayout.cardPos(group, idx, count)
    if BattleLayout.MODE == "strip" then
        return stripCardPos(group, idx)
    end
    return classicCardPos(group, idx, count)
end

--- 按单位列表取卡片坐标（空列表走模式对应的兜底点）
---@param units table[]|nil
---@param idx number|nil
---@param fallbackCY number|nil classic 模式空列表 Y 兜底
---@return number cx
---@return number cy
function BattleLayout.posForList(units, idx, fallbackCY)
    local group = BattleLayout.detectGroup(units)
    if not group then
        if BattleLayout.MODE == "strip" then
            return BattleLayout.STRIP_W * 0.5, BattleLayout.STRIP_CY
        end
        return BattleLayout.DESIGN_W * 0.5, fallbackCY or BattleLayout.ALLY_ROW_CY
    end
    return BattleLayout.cardPos(group, idx, idx and #units or nil)
end

--- 战场中心（classic 兜底锚点用）
BattleLayout.FIELD_CY = BattleLayout.ALLY_ROW_CY

return BattleLayout
