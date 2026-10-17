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
-- 两侧融合来线使用 x=510/570 独立通道，至 y=1830 才汇合：
--   307                    776
--    |                      |
-- 140+---340---510   570---740+---940   y=1758
--  |      |     |     |     |     |
--  |      |     +--+--+     |     |    y=1830
--  |      |        |       |     |
-- [1]    [2]      [3]     [4]   [5]    y=1858（图标顶边）
-- 每段列出其下游节点；共用横杆只着色真正经过该段的路径，不误亮邻节点竖腿。
local EDGES = {
    { side = 1, x1 = 307, y1 = 1699, x2 = 307, y2 = 1758, dest = { 1, 2, 3 } },
    { side = 1, x1 = 140, y1 = 1758, x2 = 307, y2 = 1758, dest = { 1 } },
    { side = 1, x1 = 307, y1 = 1758, x2 = 340, y2 = 1758, dest = { 2, 3 } },
    { side = 1, x1 = 340, y1 = 1758, x2 = 510, y2 = 1758, dest = { 3 } },
    { side = 1, x1 = 140, y1 = 1758, x2 = 140, y2 = 1858, dest = { 1 } },
    { side = 1, x1 = 340, y1 = 1758, x2 = 340, y2 = 1858, dest = { 2 } },
    { side = 1, x1 = 510, y1 = 1758, x2 = 510, y2 = 1830, dest = { 3 } },
    { side = 1, x1 = 510, y1 = 1830, x2 = 540, y2 = 1830, dest = { 3 } },
    { side = 2, x1 = 776, y1 = 1699, x2 = 776, y2 = 1758, dest = { 3, 4, 5 } },
    { side = 2, x1 = 570, y1 = 1758, x2 = 740, y2 = 1758, dest = { 3 } },
    { side = 2, x1 = 740, y1 = 1758, x2 = 776, y2 = 1758, dest = { 3, 4 } },
    { side = 2, x1 = 776, y1 = 1758, x2 = 940, y2 = 1758, dest = { 5 } },
    { side = 2, x1 = 740, y1 = 1758, x2 = 740, y2 = 1858, dest = { 4 } },
    { side = 2, x1 = 940, y1 = 1758, x2 = 940, y2 = 1858, dest = { 5 } },
    { side = 2, x1 = 570, y1 = 1758, x2 = 570, y2 = 1830, dest = { 3 } },
    { side = 2, x1 = 540, y1 = 1830, x2 = 570, y2 = 1830, dest = { 3 } },
    { side = 0, x1 = 540, y1 = 1830, x2 = 540, y2 = 1858, dest = { 3 } },
}

--- 返回可直接以已有矢量矩形风格填充的线段（无 NanoVG/存档/输入副作用）。
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
    local result = {}
    local half = 6
    for _, edge in ipairs(EDGES) do
        local parentId = edge.side == 1 and parents[1] or parents[2]
        local active = not first and heroLevel >= AVC.COST[1].level
            or first == parentId
        if edge.side == 0 then
            active = not first and heroLevel >= AVC.COST[1].level
                or first == parents[1] or first == parents[2]
        end
        local gold = false
        if active and legalSecond then
            for _, index in ipairs(edge.dest) do
                if byIndex[index] == second then gold = true; break end
            end
        end
        local alpha = locked and 0.35 or (active and (not second or gold) and 1 or 0.3)
        local x, y, w, h
        if edge.y1 == edge.y2 then
            x, y = edge.x1 - half, edge.y1 - half
            w, h = edge.x2 - edge.x1 + half * 2, half * 2
        else
            x, y = edge.x1 - half, math.max(1699, edge.y1 - half)
            w, h = half * 2, math.min(1858, edge.y2 + half) - y
        end
        result[#result + 1] = {
            x = x, y = y, w = w, h = h, alpha = alpha, gold = gold and not locked,
        }
    end
    return result
end

return T
