-- 已确认一转资源契约：真实PNG/配置检查，不加载游戏或读写玩家存档。
-- UrhoXRuntime tests/advancement_icon_asset_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
local AVC = require("config.AdvancementConfig")
local CC = require("config.ClassConfig")
local ROOT = "image/职业图标/"
local passes, failures = 0, 0
---@type Image[]
local images = {}
local function check(ok, label)
    if ok then passes = passes + 1 else failures = failures + 1 end
    print((ok and "[PASS] " or "[FAIL] ") .. label)
end

-- 第一批授权十图；UUID固定为替换前已存在meta，不生成/更新meta。
local BATCH1 = {
    { 1, "seal", 0, 0, "gate_seal_rift", "C3oGqRUwT4JIgJbzeaf22GKu" },
    { 6, "debt", 0, 0, "gate_debt_defer", "EqKL8cj5hYzTbivPK1PReDae" },
    { 201, "seal", 2, 101, "gate_201_seal_strip", "FbAHKVA_AC4-re6Ah9F9iqLh" },
    { 202, "seal", 2, 101, "gate_202_martyr", "EPqGOZ9lN2Koe4xtmCWny9fZ" },
    { 203, "seal", 2, 102, "gate_203_deadgate", "FPW2UTFvEKZP_TxlPuow_scH" },
    { 204, "seal", 2, 102, "gate_204_recoil", "DRmG2VchHcYWvUe_wlESnogy" },
    { 221, "debt", 2, 111, "gate_221_war", "F-odcdRFd8wpRTKdQFtQmwLe" },
    { 222, "debt", 2, 111, "gate_222_blood", "EHro2TVyOjH-U5Kimsd7jOsn" },
    { 223, "debt", 2, 112, "gate_223_pardon", "CpRuCRRv9b__jAc7DuA0CcDa" },
    { 224, "debt", 2, 112, "gate_224_punish", "C642ARpXZT1fGVPXzUs6Rnqp" },
}
---@type table<number, Image>
local batchImages = {}
local function readMeta(id)
    -- ReadString读的是零终止串，不是整份JSON；与现有源码夹具同用ReadLine/IsEof。
    local file = File("/workspace/assets/" .. ROOT .. "UI_icon_ZY_" .. id .. ".png.meta", FILE_READ)
    local ok, text = pcall(function()
        assert(file:IsOpen(), "无法打开meta " .. id)
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        return table.concat(lines, "\n")
    end)
    file:Dispose()
    assert(ok, text)
    return cjson.decode(text)
end
local function testBatch1()
    check(CC.KNIGHT == "seal" and CC.PRIEST == "debt", "第一批真实classId为seal/debt")
    check(AVC.COST[1].level == 10 and AVC.COST[1].gold == 10000, "保留一转10级10000金币")
    check(AVC.COST[2].level == 25 and AVC.COST[2].gold == 100000, "保留二转25级100000金币")
    local uuids = {}
    for _, row in ipairs(BATCH1) do
        local id, classId, level, parent, talentId = row[1], row[2], row[3], row[4], row[5]
        local cfg = level == 0 and CC.get(classId) or AVC.get(id)
        check(cfg ~= nil, id .. "真实配置存在")
        if level == 0 then
            check(AVC.get(id) == nil and CC.get(classId).name == (id == 1 and "封门人" or "司仪"), id .. "基础职业归属不误作转职分支")
            check(CC.get(classId).talentId == talentId, id .. "基础天赋保持")
        else
            check(cfg.baseClass == classId and cfg.advLevel == 2 and cfg.combatPower == 20, id .. "二转职业归属阶段战力保持")
            check(cfg.parentBranch == parent and AVC.get(parent).baseClass == classId, id .. "parent与baseClass一致")
            local siblings = AVC.SECOND_BRANCHES[parent]
            check(siblings and (siblings[1] == id or siblings[2] == id), id .. "原父分支映射包含自身")
            check(cfg.talentId == talentId, id .. "原天赋保持")
            check(not AVC.canAdvance(24, 1000000, 2, classId, id, { first = parent }), id .. "二十四级拒绝")
            check(AVC.canAdvance(25, 100000, 2, classId, id, { first = parent }), id .. "二十五级精确金币门槛开放")
            check(not AVC.canAdvance(25, 99999, 2, classId, id, { first = parent }), id .. "少一金币拒绝")
            check(not AVC.canAdvance(30, 1000000, 2, classId, id, nil), id .. "缺一转拒绝")
            check(not AVC.canAdvance(30, 1000000, 2, classId, id, { first = parent, second = id }), id .. "已有二转拒绝")
            local wrongParent = classId == "seal" and 111 or 101
            check(not AVC.canAdvance(30, 1000000, 2, classId, id, { first = wrongParent }), id .. "不串另一基础职业父分支")
            local otherParent = parent % 2 == 1 and parent + 1 or parent - 1
            check(not AVC.canAdvance(30, 1000000, 2, classId, id, { first = otherParent }), id .. "不串同职业另一路父分支")
            check(not AVC.canAdvance(30, 1000000, 1, classId, id, nil), id .. "二转图不走一转门槛")
        end
        local meta = readMeta(id)
        check(meta.uuid == row[6], id .. "原meta UUID逐字保持")
        check(not uuids[meta.uuid], id .. "UUID无重复归属")
        uuids[meta.uuid] = true
        local file = assert(cache:GetFile(ROOT .. "UI_icon_ZY_" .. id .. ".png"))
        file:Dispose()
        local image = Image()
        images[#images + 1] = image
        batchImages[id] = image
        local loaded = image:Load("/workspace/assets/" .. ROOT .. "UI_icon_ZY_" .. id .. ".png")
        check(loaded, id .. "第一批真实PNG可加载")
        check(image.width == 280 and image.height == 280 and image.components == 4, id .. "第一批280×280 RGBA")
        if loaded and image.width == 280 and image.height == 280 then
            local transparent, opaque, partial, dirty, outside, changed = 0, 0, 0, 0, 0, 0
            for y = 0, 279 do
                for x = 0, 279 do
                    local c = image:GetPixel(x, y)
                    if c.a == 0 then
                        transparent = transparent + 1
                        if c.r ~= 0 or c.g ~= 0 or c.b ~= 0 then dirty = dirty + 1 end
                    elseif c.a == 1 then opaque = opaque + 1
                    else partial = partial + 1 end
                    local differs = image:GetPixelInt(x, y) ~= images[1]:GetPixelInt(x, y)
                    if (x - 139.5) ^ 2 + (y - 139.5) ^ 2 > 114 ^ 2 then
                        if differs then outside = outside + 1 end
                    elseif differs then changed = changed + 1 end
                end
            end
            check(transparent > 20000 and opaque > 50000, id .. "第一批透明四角与实体底板")
            check(partial > 100 and dirty == 0, id .. "第一批抗锯齿无透明残色")
            check(image:GetPixel(0, 0).a == 0 and image:GetPixel(279, 279).a == 0, id .. "第一批画布边界透明")
            check(outside == 0, id .. "半径114外与111共用底板逐像素相同 mismatch=" .. outside)
            check(changed > 500, id .. "半径114内不是复制111 changed=" .. changed)
        end
    end
    -- 全十图两两比较，防止不同职业/不同父分支误装成另一已通过的图。
    for i = 1, #BATCH1 - 1 do
        for j = i + 1, #BATCH1 do
            local idA, idB = BATCH1[i][1], BATCH1[j][1]
            local a, b = batchImages[idA], batchImages[idB]
            local changed = 0
            for y = 26, 253 do
                for x = 26, 253 do
                    if (x - 139.5) ^ 2 + (y - 139.5) ^ 2 <= 114 ^ 2
                        and a:GetPixelInt(x, y) ~= b:GetPixelInt(x, y) then
                        changed = changed + 1
                    end
                end
            end
            check(changed > 500, idA .. "/" .. idB .. "第一批无重复主体 changed=" .. changed)
        end
    end
    -- 不仅比较文件或RGBA不同，也比较骨白主轮廓占位；纯统一换色不能替代职业结构差异。
    for _, pair in ipairs({ { 1, 6 }, { 201, 202 }, { 203, 204 }, { 221, 222 }, { 223, 224 } }) do
        local a, b = batchImages[pair[1]], batchImages[pair[2]]
        local changed, shapeChanged = 0, 0
        for y = 26, 253 do
            for x = 26, 253 do
                if (x - 139.5) ^ 2 + (y - 139.5) ^ 2 <= 114 ^ 2 then
                    if a:GetPixelInt(x, y) ~= b:GetPixelInt(x, y) then changed = changed + 1 end
                    local ca, cb = a:GetPixel(x, y), b:GetPixel(x, y)
                    local brightA = ca.a > 0.5 and (ca.r + ca.g + ca.b) / 3 > 0.55
                    local brightB = cb.a > 0.5 and (cb.r + cb.g + cb.b) / 3 > 0.55
                    if brightA ~= brightB then shapeChanged = shapeChanged + 1 end
                end
            end
        end
        local label = pair[1] .. "/" .. pair[2]
        check(changed > 500, label .. "主体像素差异=" .. changed)
        check(shapeChanged > 200, label .. "骨白主轮廓占位差异=" .. shapeChanged)
    end
end

-- 精修专项只记录真实模块向父接口发出的图元；不创建NanoVG/GPU，不写PNG或存档。
-- 不导出生产局部helper，不复制Sutherland–Hodgman实现；以下面积/边界检查消费真实片段。
---@class AdvancementCPURecord
---@field kind string
---@field points number[][]
---@field color number[]
---@field bottom number[]|nil
---@field width number|nil
---@field opacity number|nil
---@field closed boolean|nil
local CPU_CENTER, CPU_LIMIT, CPU_EPS = 139.5, 108, 0.0000001
---@param value any
---@return boolean
local function cpuFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
---@param points number[][]
---@return number
local function cpuSignedArea(points)
    local sum = 0
    for i, p in ipairs(points) do
        local q = points[i % #points + 1]
        sum = sum + p[1] * q[2] - q[1] * p[2]
    end
    return sum * 0.5
end
---@param points number[][]
---@return number[][]
local function cpuCopyPoints(points)
    local result = {}
    for _, p in ipairs(points) do result[#result + 1] = { p[1], p[2] } end
    return result
end
---@param r AdvancementCPURecord
---@return AdvancementCPURecord
local function cpuCopyRecord(r)
    return {
        kind = r.kind, points = cpuCopyPoints(r.points),
        color = { r.color[1], r.color[2], r.color[3] },
        bottom = r.bottom and { r.bottom[1], r.bottom[2], r.bottom[3] } or nil,
        width = r.width, opacity = r.opacity, closed = r.closed,
    }
end
---@param r AdvancementCPURecord
local function cpuValidateRecord(r)
    assert(type(r.color) == "table" and #r.color == 3, "CPU图元必须为三通道RGB")
    for i = 1, 3 do local c = r.color[i]; assert(cpuFinite(c) and c >= 0 and c <= 255, "CPU RGB非有限或越界") end
    assert(r.opacity == nil or (cpuFinite(r.opacity) and r.opacity >= 0 and r.opacity <= 1), "CPU opacity非法")
    assert(r.closed == nil or type(r.closed) == "boolean", "CPU closed非法")
    assert(type(r.points) == "table" and #r.points >= (r.kind == "polygon" and 3 or 2), "CPU图元顶点不足")
    local padding = 0
    if r.kind == "polygon" then
        assert(r.bottom == nil, "父polygon传入bottom将重启旧刷纹")
    else
        assert(cpuFinite(r.width) and r.width > 0 and r.width < CPU_LIMIT * 2, "CPU描边宽度非法")
        padding = r.width * 0.5
    end
    for _, p in ipairs(r.points) do
        assert(type(p) == "table" and #p == 2 and cpuFinite(p[1]) and cpuFinite(p[2]), "CPU坐标非有限或格式非法")
        local radius = math.sqrt((p[1] - CPU_CENTER) ^ 2 + (p[2] - CPU_CENTER) ^ 2)
        assert(radius + padding <= CPU_LIMIT + CPU_EPS, "CPU半径108含描边越界")
        -- 父scan的采样是(px+0.5)/2-0.5；对应560母图坐标为2*(x+0.5)。
        local mx, my, mp = (p[1] + 0.5) * 2, (p[2] + 0.5) * 2, padding * 2
        local mc = (CPU_CENTER + 0.5) * 2
        assert(math.sqrt((mx - mc) ^ 2 + (my - mc) ^ 2) + mp <= CPU_LIMIT * 2 + CPU_EPS,
            "CPU 2x母图半径含描边越界")
        assert(mx - mp >= 0 and my - mp >= 0 and mx + mp < 560 and my + mp < 560,
            "CPU 2x母图实体触及画布边缘")
    end
    if r.kind == "polygon" then
        local area = cpuSignedArea(r.points)
        assert(cpuFinite(area) and math.abs(area) > 0, "CPU polygon面积非有限或退化")
    end
end

-- 父curve按实际生成器28步展开；只实现父接口合同，不实现或替代模块的裁切helper。
local function cpuRecorder()
    ---@type AdvancementCPURecord[]
    local records = {}
    local counter = { calls = 0, curves = 0, legacy = 0 }
    local d = {
        DARK = { 14, 12, 10 }, GOLD = { 161, 121, 64 },
        BONE = { 220, 206, 170 }, SHADE = { 77, 55, 30 },
    }
    ---@param r AdvancementCPURecord
    local function emit(r)
        counter.calls = counter.calls + 1
        cpuValidateRecord(r)
        records[#records + 1] = cpuCopyRecord(r)
    end
    function d.polygon(points, top, bottom, opacity)
        emit({ kind = "polygon", points = points, color = top, bottom = bottom, opacity = opacity })
    end
    function d.line(x0, y0, x1, y1, width, color, opacity)
        emit({ kind = "line", points = { { x0, y0 }, { x1, y1 } }, color = color, width = width, opacity = opacity })
    end
    function d.stroke(points, width, color, closed, opacity)
        emit({ kind = "stroke", points = points, color = color, width = width, closed = closed, opacity = opacity })
    end
    function d.arc(cx, cy, rx, ry, first, last, width, color)
        counter.calls = counter.calls + 1
        assert(cpuFinite(cx) and cpuFinite(cy) and cpuFinite(rx) and cpuFinite(ry)
            and cpuFinite(first) and cpuFinite(last) and rx > 0 and ry > 0, "CPU arc参数非法")
        local points = {}
        for i = 0, 48 do
            local angle = (first + (last - first) * i / 48) * math.pi / 180
            points[#points + 1] = { cx + math.cos(angle) * rx, cy + math.sin(angle) * ry }
        end
        local r = { kind = "arc", points = points, color = color, width = width }
        cpuValidateRecord(r)
        records[#records + 1] = cpuCopyRecord(r)
    end
    function d.curve(points, x1, y1, x2, y2, x3, y3)
        counter.calls, counter.curves = counter.calls + 1, counter.curves + 1
        assert(type(points) == "table" and #points > 0, "CPU curve无起点")
        local p = points[#points]
        for _, value in ipairs({ p[1], p[2], x1, y1, x2, y2, x3, y3 }) do
            assert(cpuFinite(value), "CPU curve参数非有限")
        end
        for i = 1, 28 do
            local t, u = i / 28, 1 - i / 28
            points[#points + 1] = { u ^ 3 * p[1] + 3 * u ^ 2 * t * x1 + 3 * u * t ^ 2 * x2 + t ^ 3 * x3,
                u ^ 3 * p[2] + 3 * u ^ 2 * t * y1 + 3 * u * t ^ 2 * y2 + t ^ 3 * y3 }
        end
    end
    local function rejectLegacy(...)
        counter.calls, counter.legacy = counter.calls + 1, counter.legacy + 1
        error("精修必须使用本地polygon/描边，禁止父emblem/ellipse/star")
    end
    d.emblem, d.ellipse, d.star = rejectLegacy, rejectLegacy, rejectLegacy
    return d, records, counter
end

-- 独立固定十个已批准的主要器物轮廓，不从生产源码解析坐标或自造裁切结果。
-- 曲线形只固定父28步展开后的端点/总点数，面积参照真正收到的完整描边路径。
---@class AdvancementCPUAnchor
---@field count integer
---@field points number[][]
---@field indices integer[]|nil
---@field rotated boolean|nil
---@type table<number, AdvancementCPUAnchor>
local CPU_ANCHORS = {
    [1] = { count = 12, points = { { 139.5, 52 }, { 176, 68 }, { 200, 97 }, { 200, 156 },
        { 186, 189 }, { 159, 217 }, { 139.5, 229 }, { 120, 217 }, { 93, 189 }, { 79, 156 }, { 79, 97 }, { 103, 68 } } },
    [201] = { count = 8, points = { { 97, 60 }, { 181, 60 }, { 197, 76 }, { 197, 194 },
        { 183, 215 }, { 97, 215 }, { 82, 194 }, { 82, 77 } } },
    [202] = { count = 12, points = { { 122, 55 }, { 156, 55 }, { 173, 69 }, { 188, 96 },
        { 190, 151 }, { 179, 176 }, { 157, 192 }, { 122, 192 }, { 100, 175 }, { 89, 151 }, { 91, 96 }, { 106, 69 } } },
    [203] = { count = 14, points = { { 68, 190 }, { 68, 88 }, { 98, 64 }, { 181, 64 },
        { 210, 88 }, { 210, 190 }, { 195, 208 }, { 179, 208 }, { 179, 103 }, { 166, 92 },
        { 113, 92 }, { 100, 103 }, { 100, 208 }, { 84, 208 } } },
    [204] = { count = 8, rotated = true, points = { { -31, -59 }, { -28, -77 }, { -10, -86 },
        { 18, -86 }, { 36, -72 }, { 40, -49 }, { 29, -34 }, { -23, -36 } } },
    [6] = { count = 169, indices = { 1, 29, 57, 85, 113, 141, 169 }, points = {
        { 95.75, 177.75 }, { 118.25, 112.75 }, { 160.75, 112.75 }, { 183.25, 177.75 },
        { 183.25, 195.25 }, { 95.75, 195.25 }, { 95.75, 177.75 } } },
    [221] = { count = 10, points = { { 105, 171 }, { 97, 152 }, { 108, 122 }, { 115, 108 },
        { 126, 96 }, { 150, 94 }, { 161, 109 }, { 160, 132 }, { 151, 151 }, { 151, 168 } } },
    [222] = { count = 6, points = { { 105, 112 }, { 175, 112 }, { 180, 184 }, { 164, 203 },
        { 116, 203 }, { 100, 184 } } },
    [223] = { count = 12, points = { { 60, 99 }, { 101, 103 }, { 139, 119 }, { 177, 103 },
        { 219, 99 }, { 219, 180 }, { 204, 195 }, { 171, 190 }, { 139, 206 }, { 107, 190 }, { 75, 195 }, { 60, 180 } } },
    [224] = { count = 113, indices = { 1, 29, 57, 85, 113 }, points = {
        { 168, 53.28 }, { 129.6, 90.24 }, { 168, 150.72 }, { 207.68, 90.24 }, { 168, 53.28 } } },
}

---@param r AdvancementCPURecord
---@param id integer
---@return boolean
local function cpuMatchesAnchor(r, id)
    local anchor = CPU_ANCHORS[id]
    if r.kind ~= "stroke" or r.closed ~= true or not r.width or r.width < 7 or #r.points ~= anchor.count then return false end
    for i, p in ipairs(anchor.points) do
        local x, y = p[1], p[2]
        if anchor.rotated then
            x, y = CPU_CENTER + p[1] * math.cos(math.pi / 6) - p[2] * math.sin(math.pi / 6),
                CPU_CENTER + p[1] * math.sin(math.pi / 6) + p[2] * math.cos(math.pi / 6)
        end
        local q = r.points[anchor.indices and anchor.indices[i] or i]
        if math.abs(q[1] - x) > CPU_EPS or math.abs(q[2] - y) > CPU_EPS then return false end
    end
    return true
end

---@param point number[]
---@param outline number[][]
---@return boolean
local function cpuOnBoundary(point, outline)
    for i, p in ipairs(outline) do
        local q = outline[i % #outline + 1]
        local dx, dy = q[1] - p[1], q[2] - p[2]
        local length = dx * dx + dy * dy
        if length > 0 then
            local t = ((point[1] - p[1]) * dx + (point[2] - p[2]) * dy) / length
            local cross = (point[1] - p[1]) * dy - (point[2] - p[2]) * dx
            if t >= -CPU_EPS and t <= 1 + CPU_EPS and math.abs(cross) <= CPU_EPS * math.sqrt(length) then return true end
        end
    end
    return false
end

---@param records AdvancementCPURecord[]
---@param index integer
local function cpuCheckStrips(records, index)
    local outline = records[index].points
    local target, area, count = math.abs(cpuSignedArea(outline)), 0, 0
    local boundary, ordered, continuous = true, true, true
    local previousY, firstMid, lastMid = -math.huge, 0, 0
    ---@type number[]|nil
    local firstColor = nil
    ---@type number[]|nil
    local lastColor = nil
    for i = index + 1, #records do
        local r = records[i]
        if r.kind ~= "polygon" then break end
        local y0, y1 = math.huge, -math.huge
        for j, p in ipairs(r.points) do
            y0, y1 = math.min(y0, p[2]), math.max(y1, p[2])
            if not cpuOnBoundary(p, outline) then boundary = false end
            local q = r.points[j % #r.points + 1]
            -- y裁切的新增边只可能水平；其它边中点也必须位于原轮廓边上。
            if math.abs(q[2] - p[2]) > CPU_EPS
                and not cpuOnBoundary({ (p[1] + q[1]) * 0.5, (p[2] + q[2]) * 0.5 }, outline) then boundary = false end
        end
        if count > 0 and math.abs(y0 - previousY) > CPU_EPS then ordered = false end
        local mid = (y0 + y1) * 0.5
        if count == 0 then firstMid, firstColor = mid, r.color end
        previousY = y1
        lastMid, lastColor = mid, r.color
        area, count = area + math.abs(cpuSignedArea(r.points)), count + 1
        if area >= target - CPU_EPS * math.max(1, target) then break end
    end
    local complete = math.abs(area - target) <= CPU_EPS * math.max(1, target)
    local varied = false
    if count > 1 and firstColor and lastColor and lastMid > firstMid then
        for c = 1, 3 do if math.abs(lastColor[c] - firstColor[c]) > 1 then varied = true end end
        for i = index + 1, index + count do
            local r = records[i]
            local y0, y1 = math.huge, -math.huge
            for _, p in ipairs(r.points) do y0, y1 = math.min(y0, p[2]), math.max(y1, p[2]) end
            local t = ((y0 + y1) * 0.5 - firstMid) / (lastMid - firstMid)
            for c = 1, 3 do
                if math.abs(r.color[c] - firstColor[c] - (lastColor[c] - firstColor[c]) * t) > 0.000001 then continuous = false end
            end
        end
    end
    return complete, boundary, ordered, continuous and varied, count
end

---@param a AdvancementCPURecord[]
---@param b AdvancementCPURecord[]
---@return boolean
local function cpuSameGeometry(a, b)
    if #a ~= #b then return false end
    for i, r in ipairs(a) do
        local s = b[i]
        if r.kind ~= s.kind or r.width ~= s.width or r.closed ~= s.closed or #r.points ~= #s.points then return false end
        for j, p in ipairs(r.points) do
            if p[1] ~= s.points[j][1] or p[2] ~= s.points[j][2] then return false end
        end
    end
    return true
end

local function testBatch1CPU()
    -- 真实require返回绘图函数；不修改模块、package.loaded或生成器。
    ---@type table<number, fun(d: table, id: any)>
    local drawers = {
        [1] = require("_proc.advancement.BatchSeal"), [6] = require("_proc.advancement.BatchPrayer"),
    }
    ---@type table<number, AdvancementCPURecord[]>
    local allRecords = {}
    for _, row in ipairs(BATCH1) do
        local id = row[1]
        local draw = drawers[row[2] == "seal" and 1 or 6]
        local d, records, counter = cpuRecorder()
        local ok, err = pcall(draw, d, id)
        check(ok, id .. "真实CPU模块执行及finite/RGB/opacity/面积/108含描边/2x合同 " .. (ok and "" or tostring(err)))
        check(counter.calls > 0 and #records > 0, id .. "实际父图元非空，不用空stub虚过")
        check(counter.legacy == 0, id .. "父emblem/ellipse/star调用为0")
        local polygons, noBottom, raw48, nilOpacity, explicitOpacity = 0, true, 0, 0, 0
        local anchorIndex = 0
        for i, r in ipairs(records) do
            if r.kind == "polygon" then
                polygons = polygons + 1
                noBottom = noBottom and r.bottom == nil
                if #r.points == 48 then raw48 = raw48 + 1 end
            end
            if r.opacity == nil then nilOpacity = nilOpacity + 1 else explicitOpacity = explicitOpacity + 1 end
            if anchorIndex == 0 and cpuMatchesAnchor(r, id) then anchorIndex = i end
        end
        check(polygons > 1 and noBottom, id .. "所有真正发出的父polygon bottom=nil")
        check(anchorIndex > 0, id .. "保留批准的主要器物轮廓锚点")
        if anchorIndex > 0 then
            local complete, boundary, ordered, continuous, count = cpuCheckStrips(records, anchorIndex)
            check(complete, id .. "真实主面条带总面积等于完整描边形状")
            check(boundary, id .. "真实片段顶点及非水平边不越原形状边界")
            check(ordered and count > 1, id .. "主面条带沿y无缝连续且不是完整单色面")
            check(continuous, id .. "主面RGB沿全高连续渐变而非各片重新起色")
        end
        print("[CPU-COVERAGE] id=" .. id .. " polygons=" .. polygons .. " raw48=" .. raw48
            .. " curve28=" .. counter.curves .. " opacity_nil=" .. nilOpacity .. " opacity_explicit=" .. explicitOpacity)
        allRecords[id] = records
    end
    -- 全十图的图元几何独立于颜色，防止只换RGB却仍复制另一个职业主体。
    for i = 1, #BATCH1 - 1 do
        for j = i + 1, #BATCH1 do
            local a, b = BATCH1[i][1], BATCH1[j][1]
            check(not cpuSameGeometry(allRecords[a], allRecords[b]), a .. "/" .. b .. "CPU几何不靠颜色区分")
        end
    end
    for _, base in ipairs({ 1, 6 }) do
        local draw = drawers[base]
        -- 全正式42图中的其它ID都拒绝，含另一模块五图及已确认一转。
        local invalid = { -1, 0, 7, 999, 1.5, "1", "6", false, {}, math.huge, -math.huge, 0 / 0 }
        for id = 1, 6 do if not (base == 1 and id == 1) and not (base == 6 and id == 6) then invalid[#invalid + 1] = id end end
        for id = 101, 112 do invalid[#invalid + 1] = id end
        for id = 201, 224 do
            if not (base == 1 and id >= 201 and id <= 204) and not (base == 6 and id >= 221 and id <= 224) then
                invalid[#invalid + 1] = id
            end
        end
        -- nil单独调用，不能放ipairs表内被提前截断。
        local d, _, counter = cpuRecorder()
        local ok = pcall(draw, d, nil)
        check(not ok and counter.calls == 0, base .. "模块nil ID在任何父调用前拒绝")
        for _, id in ipairs(invalid) do
            local parent, _, calls = cpuRecorder()
            local accepted = pcall(draw, parent, id)
            check(not accepted and calls.calls == 0, base .. "模块非法ID=" .. tostring(id) .. "父调用0拒绝")
        end
    end
    -- 负对照修改真实record的调用元数据，坐标/线宽/RGB保持不变；不是自造裁切算法。
    for _, id in ipairs({ 1, 6 }) do
        ---@type AdvancementCPURecord|nil
        local sample = nil
        for _, r in ipairs(allRecords[id]) do if r.kind == "polygon" then sample = r; break end end
        if sample then
            local oldBrush = cpuCopyRecord(sample)
            oldBrush.bottom = { sample.color[1], sample.color[2], sample.color[3] }
            check(cpuSameGeometry({ sample }, { oldBrush }) and oldBrush.color[1] == sample.color[1]
                and oldBrush.color[2] == sample.color[2] and oldBrush.color[3] == sample.color[3], id .. "负对照几何/RGB不变")
            check(not pcall(cpuValidateRecord, oldBrush), id .. "同几何同RGB恢复父bottom仍被拒绝")
            local invalidOpacity = cpuCopyRecord(sample)
            invalidOpacity.opacity = -0.1
            check(not pcall(cpuValidateRecord, invalidOpacity), id .. "同几何同RGB非法opacity被拒绝")
            local zeroOpacity = cpuCopyRecord(sample)
            zeroOpacity.opacity = 0
            check(pcall(cpuValidateRecord, zeroOpacity) and zeroOpacity.opacity == 0, id .. "记录器允许显式零opacity不擅改成1")
            local parent, _, calls = cpuRecorder()
            check(not pcall(parent.emblem, sample.points, sample.color, nil) and calls.legacy == 1,
                id .. "同几何同RGB调用父emblem被真实拒绝回调拦截")
        end
    end
    print("[CPU-BOUNDARY] 只覆盖真实十图发出的片段；raw48计数不是全部椭圆裁切前48点证明。")
    print("[CPU-BOUNDARY] 未直接触发局部helper的过细/零高/无bottom/显式opacity边界；记录器负对照不等于helper分支覆盖。")
    print("[CPU-BOUNDARY] 面积与边界参照实际描边及固定主轮廓锚点，不替代GPU/像素接缝或其它局部阴影面验收。")
end

function Start()
    local ok, err = pcall(function()
        for _, id in ipairs({ 111, 112 }) do
            local cfg = AVC.get(id)
            check(cfg.baseClass == CC.PRIEST and cfg.advLevel == 1, id .. "司仪一转归属")
            check(cfg.combatPower == 15, id .. "原战力不变")
            check(not AVC.canAdvance(9, 1000000, 1, CC.PRIEST, id, nil), id .. "九级不开放")
            check(AVC.canAdvance(10, 10000, 1, CC.PRIEST, id, nil), id .. "十级原金币门槛")
            check(not AVC.canAdvance(10, 9999, 1, CC.PRIEST, id, nil), id .. "金币不足拒绝")
            check(not AVC.canAdvance(10, 10000, 1, CC.KNIGHT, id, nil), id .. "错职业拒绝")
            check(not AVC.canAdvance(30, 1000000, 1, CC.PRIEST, id, { first = id }), id .. "不重复一转")
            local image = Image()
            images[#images + 1] = image
            -- 单独核验资源根解析；Image:Load采用现有烘焙脚本已实测的文件名重载。
            local file = assert(cache:GetFile(ROOT .. "UI_icon_ZY_" .. id .. ".png"))
            file:Dispose()
            local loaded = image:Load("/workspace/assets/" .. ROOT .. "UI_icon_ZY_" .. id .. ".png")
            check(loaded, id .. "真实PNG资源可加载")
            check(image.width == 280 and image.height == 280 and image.components == 4, id .. "280×280 RGBA")
            local transparent, partial, opaque, dirty = 0, 0, 0, 0
            for y = 0, 279 do
                for x = 0, 279 do
                    local c = image:GetPixel(x, y)
                    if c.a == 0 then
                        transparent = transparent + 1
                        if c.r ~= 0 or c.g ~= 0 or c.b ~= 0 then dirty = dirty + 1 end
                    elseif c.a == 1 then opaque = opaque + 1
                    else partial = partial + 1 end
                end
            end
            check(transparent > 20000 and opaque > 50000, id .. "透明四角和实体底板")
            check(partial > 100 and dirty == 0, id .. "抗锯齿边缘与零透明残色")
            check(image:GetPixel(0, 0).a == 0 and image:GetPixel(279, 279).a == 0, id .. "画布边界透明")
        end
        check(AVC.get(111).talentId == "gate_111_defer2", "延祷机制不变")
        check(AVC.get(112).talentId == "gate_112_confess", "领忏机制不变")
        for _, row in ipairs({ { 111, 221, 223 }, { 112, 223, 221 } }) do
            local branch = { first = row[1] }
            check(not AVC.canAdvance(24, 100000, 2, CC.PRIEST, row[2], branch), "二转二十四级拒绝")
            check(AVC.canAdvance(25, 100000, 2, CC.PRIEST, row[2], branch), "二转二十五级原门槛")
            check(not AVC.canAdvance(25, 100000, 2, CC.PRIEST, row[3], branch), "二转不串分支")
        end
        local shared, different = true, false
        for y = 0, 279 do
            for x = 0, 279 do
                local a, b = images[1]:GetPixelInt(x, y), images[2]:GetPixelInt(x, y)
                -- 主体断链最外端含描边/降采样到半径111；底板从内圈114外核验。
                if (x - 139.5) ^ 2 + (y - 139.5) ^ 2 > 114 ^ 2 then
                    if a ~= b then shared = false end
                elseif a ~= b then different = true end
            end
        end
        check(shared, "两图全新外圈底板逐像素一致")
        check(different, "两分支不是同图换色")
        -- 封门人本轮由用户确认替换，新增覆盖而不删除司仪原34项。
        for _, id in ipairs({ 101, 102 }) do
            local cfg = AVC.get(id)
            check(cfg.baseClass == CC.KNIGHT and cfg.advLevel == 1, id .. "封门人一转归属")
            check(cfg.combatPower == 15, id .. "原战力不变")
            check(not AVC.canAdvance(9, 1000000, 1, CC.KNIGHT, id, nil), id .. "九级不开放")
            check(AVC.canAdvance(10, 10000, 1, CC.KNIGHT, id, nil), id .. "十级原金币门槛")
            check(not AVC.canAdvance(10, 9999, 1, CC.KNIGHT, id, nil), id .. "金币不足拒绝")
            check(not AVC.canAdvance(10, 10000, 1, CC.PRIEST, id, nil), id .. "错职业拒绝")
            local file = assert(cache:GetFile(ROOT .. "UI_icon_ZY_" .. id .. ".png"))
            file:Dispose()
            local image = Image()
            images[#images + 1] = image
            check(image:Load("/workspace/assets/" .. ROOT .. "UI_icon_ZY_" .. id .. ".png"), id .. "真实PNG资源可加载")
            check(image.width == 280 and image.height == 280 and image.components == 4, id .. "280×280 RGBA")
            local transparent, partial, dirty = 0, 0, 0
            for y = 0, 279 do
                for x = 0, 279 do
                    local c = image:GetPixel(x, y)
                    if c.a == 0 then
                        transparent = transparent + 1
                        if c.r ~= 0 or c.g ~= 0 or c.b ~= 0 then dirty = dirty + 1 end
                    elseif c.a < 1 then partial = partial + 1 end
                end
            end
            check(transparent > 20000 and partial > 100 and dirty == 0, id .. "透明外缘抗锯齿无残色")
        end
        check(AVC.get(101).talentId == "gate_101_latch", "门闩机制保持")
        check(AVC.get(102).talentId == "gate_102_sluice", "闸门机制保持")
        for _, row in ipairs({ { 101, 201, 203 }, { 102, 203, 201 } }) do
            check(AVC.canAdvance(25, 100000, 2, CC.KNIGHT, row[2], { first = row[1] }), row[1] .. "二转原路径开放")
            check(not AVC.canAdvance(25, 100000, 2, CC.KNIGHT, row[3], { first = row[1] }), row[1] .. "二转不串分支")
        end
        local allShare, sealDifferent = true, false
        for y = 0, 279 do
            for x = 0, 279 do
                local a = images[3]:GetPixelInt(x, y)
                local b = images[4]:GetPixelInt(x, y)
                if (x - 139.5) ^ 2 + (y - 139.5) ^ 2 > 114 ^ 2 then
                    if a ~= b or a ~= images[1]:GetPixelInt(x, y) then allShare = false end
                elseif a ~= b then sealDifferent = true end
            end
        end
        check(allShare, "四枚已确认图共用全新底板")
        check(sealDifferent, "门闩与闸门不是同图换色")
        check(passes + failures == 60, "原60项断言完整执行")
        testBatch1()
        check(passes + failures == 319, "原319项断言完整执行，精修专项只追加")
        testBatch1CPU()
    end)
    for _, image in ipairs(images) do image:Dispose() end
    images = {}
    if not ok then failures = failures + 1; log:Write(LOG_ERROR, tostring(err)) end
    print("[advancement_icon_asset_test] " .. (failures == 0 and "ALL PASS" or "FAILED")
        .. " passes=" .. passes .. " failures=" .. failures)
    engine:Exit()
end
