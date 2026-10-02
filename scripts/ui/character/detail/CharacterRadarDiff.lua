-- ============================================================================
-- CharacterRadarDiff - 六围雷达同尺度几何差集；不依赖引擎或属性派生。
-- ============================================================================

---@class CharacterRadarPoint
---@field x number
---@field y number

---@class CharacterRadarEdge
---@field sector integer
---@field sign integer 增加为 1，减少为 -1
---@field from CharacterRadarPoint
---@field to CharacterRadarPoint

---@class CharacterRadarRegion
---@field sector integer
---@field sign integer 增加为 1，减少为 -1
---@field vertices CharacterRadarPoint[]
---@field area number 非负几何面积
---@field signedArea number 增减带符号的面积，不依赖顶点绕序

---@class CharacterRadarComparison
---@field oldVertices CharacterRadarPoint[]
---@field newVertices CharacterRadarPoint[]
---@field edges CharacterRadarEdge[] 仅包含真正移动的试穿边（混合增减拆为两段）
---@field regions CharacterRadarRegion[] 仅包含两个多边形的差集，不包含共享内区

local M = {}
local KEYS = { "str", "agi", "vit", "spi", "luk", "int" }
local POSITION_EPS = 0.00000001
local AREA_EPS = 0.0000001

local function finite(value)
    local n = tonumber(value) or 0
    if n ~= n or n == math.huge or n == -math.huge then return 0 end
    return n
end

---@param vertices CharacterRadarPoint[]
---@return number
function M.area(vertices)
    if #vertices < 3 then return 0 end
    -- 先平移到首点，避免较大屏幕坐标的鞋带公式相消。
    local origin = vertices[1]
    local twice = 0
    for i = 2, #vertices - 1 do
        local a, b = vertices[i], vertices[i + 1]
        twice = twice + (a.x - origin.x) * (b.y - origin.y)
            - (a.y - origin.y) * (b.x - origin.x)
    end
    return math.abs(twice) * 0.5
end

local function direction(delta)
    if delta > POSITION_EPS then return 1 end
    if delta < -POSITION_EPS then return -1 end
    return 0
end

---@param result CharacterRadarComparison
---@param sector integer
---@param sign integer
---@param vertices CharacterRadarPoint[]
local function addRegion(result, sector, sign, vertices)
    local area = M.area(vertices)
    if area <= AREA_EPS then return end
    result.regions[#result.regions + 1] = {
        sector = sector, sign = sign, vertices = vertices, area = area, signedArea = sign * area,
    }
end

---@param result CharacterRadarComparison
---@param sector integer
---@param sign integer
---@param a CharacterRadarPoint
---@param b CharacterRadarPoint
local function addEdge(result, sector, sign, a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    if dx * dx + dy * dy <= POSITION_EPS * POSITION_EPS then return end
    result.edges[#result.edges + 1] = { sector = sector, sign = sign, from = a, to = b }
end

--- 六个扇区分别比较旧/新三角形：同向是四边形，异向在边交点处分两三角形。
--- 所有坐标都用同一个 maxValue；不设置最小半径，0.01 的真实变化也可比较。
---@param current table<string, number>|nil
---@param preview table<string, number>|nil
---@param cx number
---@param cy number
---@param radius number
---@param maxValue number
---@return CharacterRadarComparison
function M.compare(current, preview, cx, cy, radius, maxValue)
    local scale = math.max(POSITION_EPS, finite(maxValue))
    local r = math.max(0, finite(radius))
    local before, after, signs = {}, {}, {}
    ---@type CharacterRadarComparison
    local result = { oldVertices = {}, newVertices = {}, edges = {}, regions = {} }
    for i, key in ipairs(KEYS) do
        local oldR = r * math.max(0, math.min(1, finite(current and current[key]) / scale))
        local newR = preview and r * math.max(0, math.min(1, finite(preview[key]) / scale)) or oldR
        local angle = -math.pi * 0.5 + (i - 1) * math.pi / 3
        local ux, uy = math.cos(angle), math.sin(angle)
        before[i], after[i], signs[i] = oldR, newR, direction(newR - oldR)
        result.oldVertices[i] = { x = cx + ux * oldR, y = cy + uy * oldR }
        result.newVertices[i] = { x = cx + ux * newR, y = cy + uy * newR }
    end
    for i = 1, 6 do
        local j = i % 6 + 1
        local si, sj = signs[i], signs[j]
        if si ~= 0 or sj ~= 0 then
            local oi, oj = result.oldVertices[i], result.oldVertices[j]
            local ni, nj = result.newVertices[i], result.newVertices[j]
            if si * sj < 0 then
                -- 在扇区两条轴组成的基底中求交，避开屏幕平移/几乎平行边的误差。
                -- 新边参数 t = oldRj * (newRi-oldRi) / (oldRj*newRi-oldRi*newRj)。
                -- 严格异号时分母两项不会同向相消；零半径时交点退化为中心也成立。
                local a, b, c, d = before[i], before[j], after[i], after[j]
                local denominator = b * (c - a) - a * (d - b)
                local t = math.max(0, math.min(1, b * (c - a) / denominator))
                local crossing = { x = ni.x + (nj.x - ni.x) * t,
                    y = ni.y + (nj.y - ni.y) * t }
                addRegion(result, i, si, { oi, crossing, ni })
                addRegion(result, i, sj, { oj, nj, crossing })
                addEdge(result, i, si, ni, crossing)
                addEdge(result, i, sj, crossing, nj)
            else
                local sign = si ~= 0 and si or sj
                addRegion(result, i, sign, { oi, oj, nj, ni })
                addEdge(result, i, sign, ni, nj)
            end
        end
    end
    return result
end

return M
