-- ============================================================================
-- CharacterRadarDiff 纯几何回归：不加载主入口、不改玩家数据，也不创建 NanoVG 上下文。
-- Runtime: tests/character_radar_diff_test.lua -tapcode_dir=. -tool_mode -graphicsheadless
-- ============================================================================

local RadarDiff = require("ui.character.detail.CharacterRadarDiff")
local KEYS = { "str", "agi", "vit", "spi", "luk", "int" }
local passed, failed = 0, 0

local function check(name, condition)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        print("[RadarDiff] FAIL " .. name)
    end
end

local function near(a, b, eps)
    return math.abs(a - b) <= (eps or 0.000001)
end

local function values(v)
    local result = {}
    for _, key in ipairs(KEYS) do result[key] = v end
    return result
end

local function copy(source)
    local result = {}
    for key, v in pairs(source) do result[key] = v end
    return result
end

---@param comparison CharacterRadarComparison
local function areas(comparison)
    local positive, negative = 0, 0
    for _, region in ipairs(comparison.regions) do
        if region.sign > 0 then positive = positive + region.area else negative = negative + region.area end
    end
    return positive, negative
end

---@param a CharacterRadarPoint
---@param b CharacterRadarPoint
---@param p CharacterRadarPoint
local function cross(a, b, p)
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
end

---@param a CharacterRadarPoint
---@param b CharacterRadarPoint
---@param p CharacterRadarPoint
local function onSegment(a, b, p)
    return math.abs(cross(a, b, p)) <= 0.000001
        and p.x >= math.min(a.x, b.x) - 0.000001 and p.x <= math.max(a.x, b.x) + 0.000001
        and p.y >= math.min(a.y, b.y) - 0.000001 and p.y <= math.max(a.y, b.y) + 0.000001
end

---@param polygon CharacterRadarPoint[]
---@param p CharacterRadarPoint
local function inside(polygon, p)
    local positive, negative = false, false
    for i, a in ipairs(polygon) do
        local c = cross(a, polygon[i % #polygon + 1], p)
        if c > 0.000001 then positive = true elseif c < -0.000001 then negative = true end
    end
    return not (positive and negative)
end

---@param polygon CharacterRadarPoint[]
local function simple(polygon)
    -- 仅判断严格交叉，重复端点或同线退化不算自交。
    for i = 1, #polygon do
        local a, b = polygon[i], polygon[i % #polygon + 1]
        for j = i + 2, #polygon do
            if not (i == 1 and j == #polygon) then
                local c, d = polygon[j], polygon[j % #polygon + 1]
                if cross(a, b, c) * cross(a, b, d) < -0.0000001
                    and cross(c, d, a) * cross(c, d, b) < -0.0000001 then return false end
            end
        end
    end
    return true
end

local function run()
    local current = values(50)
    local equal = RadarDiff.compare(current, copy(current), 800, 1403, 100, 100)
    check("equal has no colored edges", #equal.edges == 0)
    check("equal has no colored area", #equal.regions == 0)
    check("equal original gold area preserved", near(RadarDiff.area(equal.oldVertices), 3750 * math.sqrt(3)))
    local noPreview = RadarDiff.compare(current, nil, 800, 1403, 100, 100)
    check("nil preview has no colored data", #noPreview.edges == 0 and #noPreview.regions == 0)

    local stronger = copy(current)
    stronger.str = 70
    local increase = RadarDiff.compare(current, stronger, 800, 1403, 100, 100)
    local up, down = areas(increase)
    local expected = 1000 * math.sin(math.pi / 3)
    check("only strength touches two edges", #increase.edges == 2)
    check("strength sectors are 1 and 6", increase.edges[1].sector == 1 and increase.edges[2].sector == 6)
    check("strength creates exactly two difference sectors", #increase.regions == 2)
    check("increase area numerical match", near(up, expected) and down == 0)
    check("increase area is new minus old", near(up, RadarDiff.area(increase.newVertices) - RadarDiff.area(increase.oldVertices)))
    check("increase leaves gold area unchanged", near(RadarDiff.area(increase.oldVertices), RadarDiff.area(equal.oldVertices)))
    check("only changed vertex moves", near(increase.oldVertices[2].x, increase.newVertices[2].x)
        and near(increase.oldVertices[2].y, increase.newVertices[2].y)
        and not near(increase.oldVertices[1].y, increase.newVertices[1].y))
    for _, edge in ipairs(increase.edges) do check("increase edge green", edge.sign == 1) end

    local decrease = RadarDiff.compare(stronger, current, 800, 1403, 100, 100)
    up, down = areas(decrease)
    check("decrease area numerical match", up == 0 and near(down, expected))
    check("decrease area is old minus new", near(down, RadarDiff.area(decrease.oldVertices) - RadarDiff.area(decrease.newVertices)))
    for _, edge in ipairs(decrease.edges) do check("decrease edge red", edge.sign == -1) end

    local mixedValues = copy(current)
    mixedValues.str, mixedValues.agi = 70, 30
    local mixed = RadarDiff.compare(current, mixedValues, 800, 1403, 100, 100)
    up, down = areas(mixed)
    check("mixed has positive and negative area", up > 0 and down > 0)
    check("mixed signed areas match net polygon difference", near(up - down,
        RadarDiff.area(mixed.newVertices) - RadarDiff.area(mixed.oldVertices)))
    check("mixed touches three edges, crossing edge split", #mixed.edges == 4)
    check("mixed same sector crossing signs", mixed.edges[1].sector == 1 and mixed.edges[2].sector == 1
        and mixed.edges[1].sign == 1 and mixed.edges[2].sign == -1)
    local intersection = mixed.edges[1].to
    check("crossing segments share exact endpoint", intersection == mixed.edges[2].from)
    check("crossing lies on old edge", onSegment(mixed.oldVertices[1], mixed.oldVertices[2], intersection))
    check("crossing lies on new edge", onSegment(mixed.newVertices[1], mixed.newVertices[2], intersection))
    check("symmetric crossing matches exact half parameter", near(intersection.x,
        (mixed.newVertices[1].x + mixed.newVertices[2].x) * 0.5))
    local asymmetricValues = copy(current)
    asymmetricValues.str, asymmetricValues.agi = 80, 40
    local asymmetric = RadarDiff.compare(current, asymmetricValues, 800, 1403, 100, 100)
    local asymmetricCross = asymmetric.edges[1].to
    check("asymmetric crossing not guessed midpoint", not near(asymmetricCross.x,
        (asymmetric.newVertices[1].x + asymmetric.newVertices[2].x) * 0.5)
        and onSegment(asymmetric.oldVertices[1], asymmetric.oldVertices[2], asymmetricCross))
    for _, region in ipairs(mixed.regions) do
        check("mixed no self intersection", simple(region.vertices))
        check("mixed signed area data", near(region.signedArea, region.sign * RadarDiff.area(region.vertices)))
        if region.sector == 1 then check("crossing sector split into triangles", #region.vertices == 3) end
    end

    -- 旧/新边在中心相交（一个轴从0增加，邻轴减少到0），不丢掉非退化面积。
    local zeroBefore, zeroAfter = values(50), values(50)
    zeroBefore.str, zeroAfter.str, zeroAfter.agi = 0, 50, 0
    local zeroMixed = RadarDiff.compare(zeroBefore, zeroAfter, 800, 1403, 100, 100)
    up, down = areas(zeroMixed)
    check("zero mixed still has both signs", up > 0 and down > 0)
    check("zero crossing triangles degenerate and skipped", #zeroMixed.regions == 2)
    check("zero mixed exact net area", near(up - down,
        RadarDiff.area(zeroMixed.newVertices) - RadarDiff.area(zeroMixed.oldVertices)))

    local tinyBefore, tinyAfter = values(50), values(50)
    tinyBefore.str, tinyAfter.str = 0.01, 0.02
    local tiny = RadarDiff.compare(tinyBefore, tinyAfter, 800, 1403, 175, 100)
    check("0.01 below old floor still colors two edges", #tiny.edges == 2 and #tiny.regions == 2)
    check("no minimum radius floor", near(1403 - tiny.oldVertices[1].y, 0.0175))
    local negative = RadarDiff.compare(values(-10), values(-1), 800, 1403, 175, 100)
    check("negative values clamp to center without coloring", #negative.regions == 0 and #negative.edges == 0)
    local invisible = RadarDiff.compare(values(0), values(0.000000000001), 800, 1403, 175, 100)
    check("numerically negligible near zero skipped", #invisible.regions == 0 and #invisible.edges == 0)
    local clamped = RadarDiff.compare(values(110), values(150), 800, 1403, 175, 100)
    check("same clamped vertices no colors", #clamped.edges == 0 and #clamped.regions == 0)
    local badScale = RadarDiff.compare(nil, nil, 0, 0, 0, 0)
    check("nil and zero scale safe", #badScale.oldVertices == 6 and #badScale.regions == 0)
    check("inputs never mutated", current.str == 50 and stronger.str == 70 and tinyBefore.str == 0.01)

    -- 确定性扩样：逐扇区面积守恒、差集质心归属、顶点不自交；不改全局随机种子。
    local areaOk, membershipOk, simpleOk = true, true, true
    for sample = 1, 200 do
        local old, new = {}, {}
        for i, key in ipairs(KEYS) do
            old[key] = (sample * 13 + i * 37) % 101
            new[key] = (sample * 43 + i * 19) % 101
        end
        local diff = RadarDiff.compare(old, new, 800, 1403, 175, 100)
        local positive, negativeArea = areas(diff)
        areaOk = areaOk and near(positive - negativeArea,
            RadarDiff.area(diff.newVertices) - RadarDiff.area(diff.oldVertices), 0.00001)
        for _, region in ipairs(diff.regions) do
            simpleOk = simpleOk and simple(region.vertices)
            local x, y = 0, 0
            for _, point in ipairs(region.vertices) do x, y = x + point.x, y + point.y end
            local point = { x = x / #region.vertices, y = y / #region.vertices }
            local j = region.sector % 6 + 1
            local origin = { x = 800, y = 1403 }
            local oldSector = { origin, diff.oldVertices[region.sector], diff.oldVertices[j] }
            local newSector = { origin, diff.newVertices[region.sector], diff.newVertices[j] }
            local inOld, inNew = inside(oldSector, point), inside(newSector, point)
            membershipOk = membershipOk and ((region.sign > 0 and inNew and not inOld)
                or (region.sign < 0 and inOld and not inNew))
        end
    end
    check("200 mixed samples signed area conservation", areaOk)
    check("200 mixed samples never fill shared inner area", membershipOk)
    check("200 mixed samples no self intersections", simpleOk)
end

function Start()
    print("[RadarDiff] START")
    run()
    print(string.format("[RadarDiff] %d PASS / %d FAIL", passed, failed))
    if failed == 0 then print("[RadarDiff] ALL PASS") end
    engine:Exit()
end
