-- ClassChangeTree.lua
-- 转职树纯布局：五个唯一二转节点、两父各三条直角路径及逐段着色。
local AVC = require("config.AdvancementConfig")

local T = {}
T.iconW, T.iconH = 166, 166
T.nameFontSize = 36
T.pos = {
    { iconCX = 140, iconCY = 1941, nameCX = 140, nameCY = 2017 },
    { iconCX = 340, iconCY = 1941, nameCX = 340, nameCY = 2017 },
    { iconCX = 540, iconCY = 1941, nameCX = 540, nameCY = 2017 },
    { iconCX = 740, iconCY = 1941, nameCX = 740, nameCY = 2017 },
    { iconCX = 940, iconCY = 1941, nameCX = 940, nameCY = 2017 },
}

--- 绘制和命中共用此列表；融合只在中心出现一次，原四分支次序不变。
---@param classId string
---@return table[]
function T.getNodes(classId)
    local first = AVC.FIRST_BRANCHES[classId]
    if not first then return {} end
    local left = AVC.SECOND_BRANCHES[first[1]] or {}
    local right = AVC.SECOND_BRANCHES[first[2]] or {}
    local ids = { left[1], left[2], left[3], right[1], right[2] }
    local nodes = {}
    for i = 1, 5 do
        local cfg = ids[i] and AVC.get(ids[i])
        if cfg then
            nodes[#nodes + 1] = { id = ids[i], name = cfg.name, pos = T.pos[i], index = i }
        end
    end
    return nodes
end

-- 所有路径从一转图标真实底边 y=1699 出发，止于二转图标真实顶边 y=1858。
-- 一转中心与二转中心对齐：借面 340 落在千面正上方，剥面 740 落在致命面正上方，
-- 两条黄色主路径各自成为一条直竖线，不再有横向小折。
-- 融合节点无相(540)由左右父各引一条竖线并排接入（中缝 4px），不再共用单条中干：
--      340                       740
--       |                         |
-- 140+--+------+---+---+---------+--+---940   y=1758（两父横杆各自延伸到融合线）
--  |      |    |L  |R         |     |
-- [1]    [2]  [3] [3]        [5]   [4]       y=1858（图标顶边）
-- 静面  千面  无相(左/右)    致命面 双面
-- 每段列出其下游节点；线段按竖线切成互不重叠的矩形，交点只由一条线覆盖，
-- 避免半透明段叠加导致交点更亮；横杆只着色真正经过该段的路径。
local LINE_THICK = 12
local HALF = LINE_THICK * 0.5
local BAR_TOP, BAR_BOT = 1758 - HALF, 1758 + HALF
local ICON_TOP, ICON_BOT = 1699, 1858
-- 一转中心与二转中心对齐后的坐标（原 307/776 会让黄色路径横向错位）
local BR1_CX, BR2_CX = 340, 740
-- 融合节点无相的两条并排竖线：以 540 为中缝左右各一条，中缝留一线宽便于辨认
local CENTER_GAP = 12
local FUSION_LX = 540 - CENTER_GAP * 0.5 - LINE_THICK
local FUSION_RX = 540 + CENTER_GAP * 0.5
local EDGES = {
    -- 父线主干：一转底边 → 横杆下沿（覆盖自身与横杆的交点）
    { side = 1, x = BR1_CX - HALF, y = ICON_TOP, w = LINE_THICK, h = BAR_BOT - ICON_TOP, dest = { 1, 2, 3 } },
    { side = 2, x = BR2_CX - HALF, y = ICON_TOP, w = LINE_THICK, h = BAR_BOT - ICON_TOP, dest = { 3, 4, 5 } },
    -- 横杆：按竖线切成互不重叠的小段（每段止于相邻竖线外沿）
    { side = 1, x = 140 + HALF, y = BAR_TOP, w = (BR1_CX - HALF) - (140 + HALF), h = LINE_THICK, dest = { 1 } },
    { side = 1, x = BR1_CX + HALF, y = BAR_TOP, w = FUSION_LX - (BR1_CX + HALF), h = LINE_THICK, dest = { 3 } },
    { side = 2, x = FUSION_RX + LINE_THICK, y = BAR_TOP, w = (BR2_CX - HALF) - (FUSION_RX + LINE_THICK), h = LINE_THICK, dest = { 3 } },
    { side = 2, x = BR2_CX + HALF, y = BAR_TOP, w = (940 - HALF) - (BR2_CX + HALF), h = LINE_THICK, dest = { 5 } },
    -- 竖线：横杆上沿 → 二转图标顶边
    { side = 1, x = 140 - HALF, y = BAR_TOP, w = LINE_THICK, h = ICON_BOT - BAR_TOP, dest = { 1 } },
    { side = 1, x = FUSION_LX, y = BAR_TOP, w = LINE_THICK, h = ICON_BOT - BAR_TOP, dest = { 3 } },
    { side = 2, x = FUSION_RX, y = BAR_TOP, w = LINE_THICK, h = ICON_BOT - BAR_TOP, dest = { 3 } },
    { side = 2, x = 940 - HALF, y = BAR_TOP, w = LINE_THICK, h = ICON_BOT - BAR_TOP, dest = { 5 } },
    -- 一转正下方二转竖线：横杆下沿 → 图标顶边（主干已覆盖横杆处，互不重叠）
    { side = 1, x = BR1_CX - HALF, y = BAR_BOT, w = LINE_THICK, h = ICON_BOT - BAR_BOT, dest = { 2 } },
    { side = 2, x = BR2_CX - HALF, y = BAR_BOT, w = LINE_THICK, h = ICON_BOT - BAR_BOT, dest = { 4 } },
}

--- 返回可直接以已有矢量矩形风格填充的线段（无 NanoVG/存档/输入副作用）。
--- 各矩形互不重叠：交点只由一条线覆盖，半透明段不会叠加变亮。
---@param classId string
---@param advBranch table|nil
---@param heroLevel number
---@param locked boolean
---@return table[]
function T.getLineSegments(classId, advBranch, heroLevel, locked)
    local parents = AVC.FIRST_BRANCHES[classId]
    if not parents then return {} end
    local nodes = T.getNodes(classId)
    local byIndex = {}
    for _, node in ipairs(nodes) do byIndex[node.index] = node.id end
    local first = advBranch and advBranch.first
    local second = advBranch and advBranch.second
    local legalSecond = first and second and AVC.isParentBranch(second, first)
    local levelOk = heroLevel >= AVC.COST[1].level
    local result = {}
    for _, edge in ipairs(EDGES) do
        local active
        if edge.side == 1 then
            active = (not first and levelOk) or first == parents[1]
        else
            active = (not first and levelOk) or first == parents[2]
        end
        local gold = false
        if active and legalSecond then
            for _, index in ipairs(edge.dest) do
                if byIndex[index] == second then gold = true; break end
            end
        end
        local alpha = locked and 0.35 or (active and (not second or gold) and 1 or 0.3)
        result[#result + 1] = {
            x = edge.x, y = edge.y, w = edge.w, h = edge.h,
            alpha = alpha, gold = gold and not locked,
        }
    end
    return result
end

return T
