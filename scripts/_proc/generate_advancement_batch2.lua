-- 第二批：拾骸者、裂隙使的基础/二转十图，以及沿原设计精修的一转四图。
-- 沿用 generate_advancement_trials 的 CPU 图元、十二面底板和预乘降采样。
-- 默认安装授权十四图；-review-only只烘焙，不改正式PNG。原meta不变。
-- UrhoXRuntime _proc/generate_advancement_batch2.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
local ROOT = "/workspace/assets/image/职业图标/"
local OUTPUT = "/workspace/.git/advancement-icons-validation/batch2/generated/"
local BACKUP = "/workspace/.git/advancement-icons-validation/batch2/originals/"
local ORDER = { 2, 3, 103, 104, 105, 106, 205, 206, 207, 208, 209, 210, 211, 212 }
local SIZE, SCALE, CENTER = 560, 2, 139.5
local DARK, GOLD = { 14, 12, 10 }, { 161, 121, 64 }
local BONE, SHADE = { 220, 206, 170 }, { 77, 55, 30 }
---@type Image[]
local images = {}
---@type table<number, fun(d: table, branchId: integer)>
local drawers = {}
local install = true
local invalidMode = false
for _, argument in ipairs(GetArguments()) do
    if argument == "-review-only" then install = false end
    if argument == "-batch1" or argument == "-batch3" or argument == "-first-review"
        or argument == "-seal-review" then invalidMode = true end
end

local function clamp(v, low, high) return math.max(low, math.min(high, v)) end
local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

---@param id integer
---@return Image
local function render(id)
    local red, green, blue, alpha = {}, {}, {}, {}
    for i = 1, SIZE * SIZE do red[i], green[i], blue[i], alpha[i] = 0, 0, 0, 0 end
    local function blend(x, y, color, opacity)
        local i, a = y * SIZE + x + 1, opacity or 1
        local old = alpha[i]
        local combined = a + old * (1 - a)
        if combined == 0 then return end
        red[i] = (color[1] * a + red[i] * old * (1 - a)) / combined
        green[i] = (color[2] * a + green[i] * old * (1 - a)) / combined
        blue[i] = (color[3] * a + blue[i] * old * (1 - a)) / combined
        alpha[i] = combined
    end
    local function scan(x0, y0, x1, y1, inside, top, bottom, opacity)
        for y = math.max(0, math.floor(y0 * SCALE)), math.min(SIZE - 1, math.ceil(y1 * SCALE)) do
            local py = (y + 0.5) / SCALE - 0.5
            local t = clamp((py - y0) / math.max(1, y1 - y0), 0, 1)
            local base = bottom and mix(top, bottom, t) or top
            for x = math.max(0, math.floor(x0 * SCALE)), math.min(SIZE - 1, math.ceil(x1 * SCALE)) do
                local px = (x + 0.5) / SCALE - 0.5
                if inside(px, py) then
                    local color = base
                    if bottom then
                        local brushed = math.sin(px * 3.7 + math.sin(py * 0.45)) * 0.016
                        local worn = math.sin(px * 0.3 + py * 0.2) * math.sin(py * 0.35 - px * 0.17) * 0.052
                        local keyLight = math.exp(-((px - 115) ^ 2 + (py - 105) ^ 2) / 2000) * 0.08
                        local factor = 0.97 + brushed + worn + keyLight
                        color = { clamp(base[1] * factor, 0, 255), clamp(base[2] * factor, 0, 255), clamp(base[3] * factor, 0, 255) }
                    end
                    blend(x, y, color, opacity)
                end
            end
        end
    end
    local function polygon(points, top, bottom, opacity)
        local x0, y0, x1, y1 = 280, 280, 0, 0
        for _, p in ipairs(points) do
            x0, y0, x1, y1 = math.min(x0, p[1]), math.min(y0, p[2]), math.max(x1, p[1]), math.max(y1, p[2])
        end
        scan(x0, y0, x1, y1, function(x, y)
            local inside, last = false, points[#points]
            for _, p in ipairs(points) do
                if (p[2] > y) ~= (last[2] > y) and x < (last[1] - p[1]) * (y - p[2]) / (last[2] - p[2]) + p[1] then
                    inside = not inside
                end
                last = p
            end
            return inside
        end, top, bottom, opacity)
    end
    local function line(x0, y0, x1, y1, width, color, opacity)
        local vx, vy = x1 - x0, y1 - y0
        local length = vx * vx + vy * vy
        scan(math.min(x0, x1) - width, math.min(y0, y1) - width,
            math.max(x0, x1) + width, math.max(y0, y1) + width, function(x, y)
                local t = length > 0 and clamp(((x - x0) * vx + (y - y0) * vy) / length, 0, 1) or 0
                return (x - x0 - vx * t) ^ 2 + (y - y0 - vy * t) ^ 2 <= (width * 0.5) ^ 2
            end, color, nil, opacity)
    end
    local function stroke(points, width, color, closed, opacity)
        for i = 1, #points - 1 do line(points[i][1], points[i][2], points[i + 1][1], points[i + 1][2], width, color, opacity) end
        if closed then line(points[#points][1], points[#points][2], points[1][1], points[1][2], width, color, opacity) end
    end
    local function ellipse(cx, cy, rx, ry, top, bottom)
        scan(cx - rx, cy - ry, cx + rx, cy + ry, function(x, y)
            return ((x - cx) / rx) ^ 2 + ((y - cy) / ry) ^ 2 <= 1
        end, top, bottom)
    end
    local function arc(cx, cy, rx, ry, first, last, width, color)
        local points = {}
        for i = 0, 48 do
            local a = (first + (last - first) * i / 48) * math.pi / 180
            points[#points + 1] = { cx + math.cos(a) * rx, cy + math.sin(a) * ry }
        end
        stroke(points, width, color, false)
    end
    local function curve(points, x1, y1, x2, y2, x3, y3)
        local p = points[#points]
        for i = 1, 28 do
            local t, u = i / 28, 1 - i / 28
            points[#points + 1] = { u ^ 3 * p[1] + 3 * u ^ 2 * t * x1 + 3 * u * t ^ 2 * x2 + t ^ 3 * x3,
                u ^ 3 * p[2] + 3 * u ^ 2 * t * y1 + 3 * u * t ^ 2 * y2 + t ^ 3 * y3 }
        end
    end
    local function emblem(points, top, bottom)
        stroke(points, 7, DARK, true)
        polygon(points, top or BONE, bottom or GOLD)
        stroke(points, 1.5, GOLD, true)
    end
    local function star(cx, cy, radius, color)
        polygon({ { cx, cy - radius }, { cx + radius * 0.23, cy - radius * 0.23 },
            { cx + radius * 0.72, cy }, { cx + radius * 0.23, cy + radius * 0.23 },
            { cx, cy + radius }, { cx - radius * 0.23, cy + radius * 0.23 },
            { cx - radius * 0.72, cy }, { cx - radius * 0.23, cy - radius * 0.23 } }, color)
    end

    -- 与第一批及已确认111/112完全相同的底板；不读旧图、不回填环像素。
    local function rim(radius)
        local points = {}
        for i = 0, 11 do
            local angle = (-105 + i * 30) * math.pi / 180
            points[#points + 1] = { CENTER + math.cos(angle) * radius, CENTER + math.sin(angle) * radius }
        end
        return points
    end
    polygon(rim(133), DARK)
    polygon(rim(129), { 113, 94, 64 }, { 38, 30, 23 })
    polygon(rim(124), { 44, 40, 32 }, { 23, 21, 18 })
    stroke(rim(128), 1.4, GOLD, true)
    stroke({ rim(127)[8], rim(127)[9], rim(127)[10], rim(127)[11] }, 1.2, BONE, false, 0.55)
    ellipse(CENTER, CENTER, 115, 115, DARK)
    ellipse(CENTER, CENTER, 112.5, 112.5, { 43, 39, 31 }, { 22, 21, 19 })
    arc(CENTER, CENTER, 114, 114, 0, 360, 1.5, SHADE)
    arc(CENTER, CENTER, 113.5, 113.5, 193, 305, 1.1, GOLD)
    for _, p in ipairs({ { 140, 21 }, { 259, 140 }, { 140, 259 }, { 21, 140 } }) do
        ellipse(p[1], p[2], 4, 4, DARK)
        ellipse(p[1], p[2] - 0.6, 2.7, 2.7, GOLD, SHADE)
        line(p[1] - 1.5, p[2] - 1.2, p[1] + 0.8, p[2] - 1.2, 0.9, BONE, 0.6)
    end
    local draw = assert(drawers[id], "第二批没有授权的绘图编号：" .. id)
    draw({ polygon = polygon, line = line, stroke = stroke, ellipse = ellipse,
        arc = arc, curve = curve, emblem = emblem, star = star,
        DARK = DARK, GOLD = GOLD, BONE = BONE, SHADE = SHADE }, id)
    local image = Image()
    images[#images + 1] = image
    assert(image:SetSize(SIZE, SIZE, 4), "创建第二批母图失败")
    for y = 0, SIZE - 1 do
        for x = 0, SIZE - 1 do
            local i = y * SIZE + x + 1
            image:SetPixel(x, y, Color(red[i] / 255, green[i] / 255, blue[i] / 255, alpha[i]))
        end
    end
    return image
end

---@param master Image
---@return Image
local function reduce(master)
    local small = Image()
    images[#images + 1] = small
    assert(small:SetSize(280, 280, 4), "创建第二批280图失败")
    for y = 0, 279 do
        for x = 0, 279 do
            local r, g, b, a = 0, 0, 0, 0
            for sy = 0, SCALE - 1 do
                for sx = 0, SCALE - 1 do
                    local c = master:GetPixel(x * SCALE + sx, y * SCALE + sy)
                    r, g, b, a = r + c.r * c.a, g + c.g * c.a, b + c.b * c.a, a + c.a
                end
            end
            if a > 0 then small:SetPixel(x, y, Color(r / a, g / a, b / a, a / (SCALE * SCALE)))
            else small:SetPixel(x, y, Color(0, 0, 0, 0)) end
        end
    end
    return small
end

function Start()
    local ok, err = pcall(function()
        assert(not invalidMode, "第二批入口不可选择其他批次或历史审核模式")
        local spoil = require("_proc.advancement.BatchSpoil")
        local rift = require("_proc.advancement.BatchRift")
        local firstSpoil = require("_proc.advancement.ReviewSpoil")
        local firstRift = require("_proc.advancement.ReviewRift")
        drawers = { [2] = spoil, [205] = spoil, [206] = spoil, [207] = spoil, [208] = spoil,
            [3] = rift, [209] = rift, [210] = rift, [211] = rift, [212] = rift,
            [103] = firstSpoil, [104] = firstSpoil, [105] = firstRift, [106] = firstRift }
        assert(fileSystem:CreateDir(OUTPUT), "创建第二批烘焙目录失败")
        for _, id in ipairs(ORDER) do
            local name = "UI_icon_ZY_" .. id .. ".png"
            print("[adv-batch2] " .. id .. " 开始CPU绘制职业器物")
            local master = render(id)
            local small = reduce(master)
            assert(master:SavePNG(OUTPUT .. "UI_icon_ZY_" .. id .. "_560.png"), "保存第二批母图失败")
            assert(small:SavePNG(OUTPUT .. name), "保存第二批成图失败")
            print("[adv-batch2] " .. id .. " 560母图/280RGBA成图完成")
        end
        if install then
            -- 全批成功烘焙并确认原资源齐全后备份；不涉及meta写入。
            local rollback = BACKUP .. "current/"
            assert(fileSystem:CreateDir(BACKUP) and fileSystem:CreateDir(rollback), "创建第二批备份目录失败")
            for _, id in ipairs(ORDER) do
                local name = "UI_icon_ZY_" .. id .. ".png"
                assert(fileSystem:FileExists(ROOT .. name) and fileSystem:FileExists(ROOT .. name .. ".meta"), "缺少第二批原PNG/meta：" .. id)
                if not fileSystem:FileExists(BACKUP .. name) then
                    assert(fileSystem:Copy(ROOT .. name, BACKUP .. name), "保存第二批原图失败：" .. id)
                end
                assert(fileSystem:Copy(ROOT .. name, rollback .. name), "保存第二批本次恢复图失败：" .. id)
            end
            local installed = {}
            local copied, copyError = pcall(function()
                for _, id in ipairs(ORDER) do
                    local name = "UI_icon_ZY_" .. id .. ".png"
                    installed[#installed + 1] = name
                    assert(fileSystem:Copy(OUTPUT .. name, ROOT .. name), "安装第二批失败：" .. id)
                    print("[adv-batch2] 已替换 " .. id .. "，原UUID/meta不变")
                end
            end)
            if not copied then
                local restored = true
                for _, name in ipairs(installed) do
                    local restoredOK, result = pcall(function() return fileSystem:Copy(rollback .. name, ROOT .. name) end)
                    if not restoredOK or not result then restored = false end
                end
                error(tostring(copyError) .. (restored and "；已恢复原图" or "；恢复失败，请核对备份"))
            end
        end
        print("[adv-batch2] ALL PASS：新画十枚＋精修四枚，模式=" .. (install and "安装" or "仅审核"))
    end)
    for _, image in ipairs(images) do image:Dispose() end
    images = {}
    if not ok then log:Write(LOG_ERROR, "[adv-batch2] " .. tostring(err)) end
    engine:Exit()
end
