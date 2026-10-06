-- 职业徽章：统一旧金属倒角、骨白铭刻与菱形外框；司仪使用仪式圣铃。
-- 司仪：UrhoXRuntime _proc/generate_ceremonial_icon.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
-- 其余五职业：同命令追加 -class-set；不覆盖已确认的司仪图标。
-- 基于 generate_set_icons.lua 的 CPU 多边形/曲线绘制及像素混合范式。
local ROOT = "/workspace/assets/image/通用图标/"
local BACKUP = "/workspace/assets/backup/通用图标/司仪图标原图备份/"
local EXPORT = ROOT .. "司仪图标/"
local CLASS_BACKUP = "/workspace/assets/backup/通用图标/职业图标原图备份/"
local CLASS_EXPORT = ROOT .. "职业图标/"
local CLASS_COLORS = {
    { 158, 83, 69 }, { 179, 117, 64 }, { 113, 153, 167 },
    { 113, 147, 79 }, { 146, 110, 158 }, { 186, 143, 69 },
}
local classSet = false
for _, argument in ipairs(GetArguments()) do
    if argument == "-class-set" then classSet = true end
end
local SIZE, SCALE = 512, 8
local DARK = { 15, 12, 9 }
local BONE = { 235, 218, 172 }

local function clamp(v, low, high) return math.max(low, math.min(high, v)) end
local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

---@param source Image
---@param classId integer
---@return Image
local function render(source, classId)
    local GOLD = CLASS_COLORS[classId]
    local SHADE = mix(GOLD, DARK, 0.55)
    local metalTop = mix(BONE, GOLD, 0.18)
    local metalBottom = mix(GOLD, DARK, 0.25)
    local red, green, blue, alpha = {}, {}, {}, {}
    -- 原框保持在最外层菱形；仅重绘内部主体区域。
    for y = 0, SIZE - 1 do
        for x = 0, SIZE - 1 do
            local px, py = (x + 0.5) / SCALE - 0.5, (y + 0.5) / SCALE - 0.5
            local i = y * SIZE + x + 1
            local ix = clamp(math.floor(px + 0.5), 0, 63)
            local iy = clamp(math.floor(py + 0.5), 0, 63)
            local c = source:GetPixel(ix, iy)
            red[i], green[i], blue[i], alpha[i] = c.r * 255, c.g * 255, c.b * 255, c.a
            if math.abs(px - 31.5) + math.abs(py - 31.5) < 24.2 then
                local glow = math.exp(-((px - 30) ^ 2 + (py - 27) ^ 2) / 180)
                local grain = math.sin(px * 3.4 + py * 1.7) * math.sin(py * 2.1 - px * 1.3)
                red[i], green[i], blue[i], alpha[i] = 37 + glow * 19 + grain * 1.8,
                    30 + glow * 14 + grain * 1.2, 20 + glow * 7 + grain, 1
            end
        end
    end
    local function blend(x, y, color, opacity)
        local i = y * SIZE + x + 1
        local a = opacity or 1
        local old = alpha[i] or 0
        local combined = a + old * (1 - a)
        red[i] = (color[1] * a + red[i] * old * (1 - a)) / combined
        green[i] = (color[2] * a + green[i] * old * (1 - a)) / combined
        blue[i] = (color[3] * a + blue[i] * old * (1 - a)) / combined
        alpha[i] = combined
    end
    local function scan(x0, y0, x1, y1, inside, top, bottom, opacity)
        for y = math.max(0, math.floor(y0 * SCALE)), math.min(SIZE - 1, math.ceil(y1 * SCALE)) do
            local py = (y + 0.5) / SCALE - 0.5
            local t = clamp((py - y0) / math.max(1, y1 - y0), 0, 1)
            local color = bottom and mix(top, bottom, t) or top
            for x = math.max(0, math.floor(x0 * SCALE)), math.min(SIZE - 1, math.ceil(x1 * SCALE)) do
                local px = (x + 0.5) / SCALE - 0.5
                if math.abs(px - 31.5) + math.abs(py - 31.5) < 24.2 and inside(px, py) then
                    blend(x, y, color, opacity)
                end
            end
        end
    end
    local function polygon(points, top, bottom, opacity)
        local x0, y0, x1, y1 = 64, 64, 0, 0
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
        for i = 1, #points - 1 do
            line(points[i][1], points[i][2], points[i + 1][1], points[i + 1][2], width, color, opacity)
        end
        if closed then line(points[#points][1], points[#points][2], points[1][1], points[1][2], width, color, opacity) end
    end
    local function ellipse(cx, cy, rx, ry, top, bottom)
        scan(cx - rx, cy - ry, cx + rx, cy + ry, function(x, y)
            return ((x - cx) / rx) ^ 2 + ((y - cy) / ry) ^ 2 <= 1
        end, top, bottom)
    end
    local function arc(cx, cy, radius, first, last, width, color, opacity)
        local points = {}
        for i = 0, 36 do
            local a = (first + (last - first) * i / 36) * math.pi / 180
            points[#points + 1] = { cx + math.cos(a) * radius, cy + math.sin(a) * radius }
        end
        stroke(points, width, color, false, opacity)
    end
    local function curve(points, x1, y1, x2, y2, x3, y3)
        local p = points[#points]
        for i = 1, 24 do
            local t, u = i / 24, 1 - i / 24
            points[#points + 1] = { u ^ 3 * p[1] + 3 * u ^ 2 * t * x1 + 3 * u * t ^ 2 * x2 + t ^ 3 * x3,
                u ^ 3 * p[2] + 3 * u ^ 2 * t * y1 + 3 * u * t ^ 2 * y2 + t ^ 3 * y3 }
        end
    end

    local function emblem(points, top, bottom)
        stroke(points, 3.2, DARK, true)
        polygon(points, top or metalTop, bottom or metalBottom)
        stroke(points, 0.75, GOLD, true)
    end
    local function curvedStroke(points, width, color, opacity)
        stroke(points, width, color, false, opacity)
    end

    if classId == 1 then
        -- 封门人：门扉重盾与中央门缝，厚重防御轮廓优先于装饰。
        local shield = { { 18.9, 22 }, { 31.5, 16.1 }, { 44.1, 22 }, { 42.8, 35.8 },
            { 38.3, 42.6 }, { 31.5, 47.1 }, { 24.7, 42.6 }, { 20.2, 35.8 } }
        emblem(shield)
        polygon({ { 22.5, 24.1 }, { 31.5, 20.3 }, { 40.5, 24.1 }, { 39.1, 35.3 },
            { 35.1, 40.6 }, { 31.5, 43.1 }, { 27.9, 40.6 }, { 23.9, 35.3 } }, SHADE, DARK)
        emblem({ { 26.8, 25.9 }, { 36.2, 25.9 }, { 36.2, 36.9 }, { 31.5, 40 }, { 26.8, 36.9 } }, GOLD, SHADE)
        line(31.5, 26.6, 31.5, 39.2, 1.65, DARK)
        line(30.5, 27.4, 30.5, 37.8, 0.9, BONE)
        line(22.2, 23.4, 24.4, 35.1, 1.15, BONE, 0.75)
        for _, x in ipairs({ 24.4, 38.6 }) do ellipse(x, 25.4, 1, 1, BONE, GOLD) end
    elseif classId == 2 then
        -- 拾骸者：长剑仍代表物理输出，骨节护手表达击杀拾骸。
        emblem({ { 31.5, 13.7 }, { 35.5, 20.2 }, { 34.4, 35.2 }, { 31.5, 37.7 },
            { 28.6, 35.2 }, { 27.5, 20.2 } })
        polygon({ { 31.5, 14.6 }, { 31.5, 35.4 }, { 29.3, 33.8 }, { 28.7, 20.3 } }, BONE, GOLD)
        line(31.5, 20.3, 31.5, 35.1, 1.15, SHADE)
        line(31.5, 37.7, 31.5, 46.3, 5.0, DARK)
        line(31.5, 37.7, 31.5, 46.3, 2.9, GOLD)
        for _, y in ipairs({ 40, 42.3, 44.6 }) do line(30.3, y, 32.7, y + 0.6, 0.9, DARK) end
        line(23.1, 36.8, 39.9, 36.8, 5.6, DARK)
        line(23.1, 36.8, 39.9, 36.8, 2.8, BONE)
        for _, x in ipairs({ 22.7, 40.3 }) do
            ellipse(x, 35.7, 1.8, 1.7, metalTop, GOLD)
            ellipse(x, 37.9, 1.8, 1.7, metalTop, GOLD)
        end
        emblem({ { 31.5, 46 }, { 34, 48 }, { 31.5, 50.4 }, { 29, 48 } }, BONE, GOLD)
    elseif classId == 3 then
        -- 裂隙使：开裂的晶核嵌在短爪法杖上，避免普通圆珠法杖。
        line(31.5, 30, 31.5, 47.2, 5.5, DARK)
        line(31.5, 30, 31.5, 47.2, 3, metalTop)
        line(32.3, 32.5, 32.3, 45.8, 0.9, SHADE)
        emblem({ { 31.5, 13.6 }, { 38.5, 21.7 }, { 31.5, 31.3 }, { 24.5, 21.7 } }, metalTop, GOLD)
        polygon({ { 31.5, 14.4 }, { 31.5, 29.8 }, { 25.7, 21.7 } }, BONE, GOLD)
        stroke({ { 32.5, 17 }, { 29.9, 21.3 }, { 33.6, 22.7 }, { 30.3, 28.8 } }, 1.6, DARK, false)
        stroke({ { 23.6, 21.8 }, { 23.5, 29.1 }, { 28, 32.5 }, { 35, 32.5 }, { 39.5, 29.1 }, { 39.4, 21.8 } }, 4.2, DARK, false)
        stroke({ { 23.6, 21.8 }, { 23.5, 29.1 }, { 28, 32.5 }, { 35, 32.5 }, { 39.5, 29.1 }, { 39.4, 21.8 } }, 1.9, metalTop, false)
        line(28.4, 36.3, 34.6, 36.3, 2, GOLD)
        line(29.1, 40, 33.9, 40, 1.2, GOLD)
        emblem({ { 20.7, 22.3 }, { 22.7, 25.2 }, { 20.7, 28 }, { 18.7, 25.2 } }, GOLD, BONE)
        emblem({ { 42.3, 22.3 }, { 44.3, 25.2 }, { 42.3, 28 }, { 40.3, 25.2 } }, GOLD, BONE)
    elseif classId == 4 then
        -- 回响客：弓的弧线与斜向箭形成主轮廓，短箭影暗示延迟回响。
        local bow = { { 36.7, 16.4 } }
        curve(bow, 17, 19.3, 16.2, 37.9, 36.7, 46.6)
        curvedStroke(bow, 6.1, DARK)
        curvedStroke(bow, 3.1, metalTop)
        curvedStroke(bow, 0.9, BONE, 0.75)
        stroke({ { 36.7, 16.4 }, { 31, 31.8 }, { 36.7, 46.6 } }, 2.4, DARK, false)
        stroke({ { 36.7, 16.4 }, { 31, 31.8 }, { 36.7, 46.6 } }, 0.95, BONE, false)
        line(25.4, 39.7, 41, 24.1, 3.5, DARK)
        line(25.4, 39.7, 41, 24.1, 1.7, BONE)
        emblem({ { 40.2, 23.1 }, { 45.5, 20.8 }, { 43.2, 26.1 }, { 41, 25.2 } }, metalTop, GOLD)
        stroke({ { 23.7, 36.3 }, { 23.8, 40.6 }, { 28.1, 40.7 } }, 1.65, GOLD, false)
        line(25, 29.7, 29.3, 25.4, 1.05, GOLD, 0.65)
        line(25.7, 25.2, 29.6, 21.3, 0.9, BONE, 0.40)
    elseif classId == 5 then
        -- 换面人：左右明暗相反的双相面具，比旋刃更直观表达换面。
        local mask = { { 31.5, 17 }, { 42.6, 22.2 }, { 40.8, 35.5 },
            { 36.8, 42.8 }, { 31.5, 47 }, { 26.2, 42.8 }, { 22.2, 35.5 }, { 20.4, 22.2 } }
        emblem(mask)
        polygon({ { 31.5, 17.7 }, { 42, 22.6 }, { 40.2, 35.3 }, { 36.3, 42.3 }, { 31.5, 46 } }, GOLD, SHADE)
        stroke({ { 31.5, 19.4 }, { 30.1, 27.7 }, { 32.4, 32.5 }, { 30.8, 38.2 }, { 31.5, 44.6 } }, 1.3, DARK, false)
        polygon({ { 24.1, 27.1 }, { 29.4, 29.3 }, { 29, 32.3 }, { 25, 30.5 } }, DARK)
        polygon({ { 38.9, 27.1 }, { 33.6, 29.3 }, { 34, 32.3 }, { 38, 30.5 } }, DARK)
        line(24.8, 26.8, 29.3, 28.4, 0.9, BONE)
        line(33.7, 28.4, 38.2, 26.8, 0.9, BONE)
        stroke({ { 28.8, 38.5 }, { 31.4, 39.3 }, { 34.3, 38.5 } }, 1.4, DARK, false)
        line(23.3, 23.7, 23.8, 26.1, 1, BONE, 0.85)
    else
    -- 两侧短祝祷光芒只作辅助，不画音量声波，避免与音效按钮混淆。
    for _, side in ipairs({ -1, 1 }) do
        line(31.5 + side * 13, 24, 31.5 + side * 15.5, 22, 1.3, GOLD, 0.72)
        line(31.5 + side * 15.5, 30, 31.5 + side * 18, 30, 1.2, BONE, 0.64)
    end
    -- 铃柄为短环与小结，与司剑长剑及司术长法杖形成清晰轮廓区别。
    arc(31.5, 18, 3.1, 0, 360, 4.7, DARK)
    arc(31.5, 18, 3.1, 0, 360, 2.1, GOLD)
    arc(31.5, 18, 3.1, 190, 310, 1.1, BONE)
    line(31.5, 20.4, 31.5, 24, 4.5, DARK)
    line(31.5, 20.4, 31.5, 24, 2.5, BONE)
    local body = { { 21, 38 } }
    curve(body, 25, 33, 23, 27, 27.1, 24)
    curve(body, 29.5, 22.2, 33.5, 22.2, 35.9, 24)
    curve(body, 40, 27, 38, 33, 42, 38)
    curve(body, 44.2, 39.6, 43.4, 41, 40.6, 41.6)
    curve(body, 35.6, 43, 27.4, 43, 22.4, 41.6)
    curve(body, 19.6, 41, 18.8, 39.6, 21, 38)
    stroke(body, 3.7, DARK, true)
    polygon(body, BONE, SHADE)
    stroke(body, 0.8, GOLD, true)
    -- 左侧反光与右側暗面表现旧铜倒角。
    stroke({ { 27.6, 25.1 }, { 25.6, 28.8 }, { 25.2, 33 }, { 23.6, 36.9 } }, 1.5, BONE, false, 0.90)
    stroke({ { 35.5, 25.4 }, { 37.2, 30.8 }, { 38.7, 36.8 } }, 1.2, SHADE, false, 0.86)
    ellipse(31.5, 40.1, 10.7, 2.4, GOLD, BONE)
    ellipse(31.5, 40.7, 8.5, 1.3, DARK)
    -- 铃舌突出铃口：小尺寸也能识别为铃铛而不是头盔。
    line(31.5, 40.9, 31.5, 45.1, 2.1, GOLD)
    ellipse(31.5, 45.4, 2.3, 2.0, BONE, SHADE)
    -- 胸口四芒纹代表祈祷与护佑，不使用战士剑刃意象。
    polygon({ { 31.5, 27.5 }, { 32.4, 30.4 }, { 35, 31.4 }, { 32.4, 32.2 },
        { 31.5, 35.2 }, { 30.6, 32.2 }, { 28, 31.4 }, { 30.6, 30.4 } }, DARK)
    polygon({ { 31.5, 28.7 }, { 32, 30.8 }, { 33.8, 31.4 }, { 32, 31.8 },
        { 31.5, 34 }, { 31, 31.8 }, { 29.2, 31.4 }, { 31, 30.8 } }, BONE, GOLD)
    end

    local image = Image()
    assert(image:SetSize(SIZE, SIZE, 4), "创建司仪图标画布失败")
    for y = 0, SIZE - 1 do
        for x = 0, SIZE - 1 do
            local i = y * SIZE + x + 1
            image:SetPixel(x, y, Color(red[i] / 255, green[i] / 255, blue[i] / 255, alpha[i]))
        end
    end
    return image
end

---@param image Image
---@param original Image
---@return Image
local function reduce(image, original)
    local small = Image()
    assert(small:SetSize(64, 64, 4), "创建64×64司仪图标失败")
    for y = 0, 63 do
        for x = 0, 63 do
            if math.abs(x - 31.5) + math.abs(y - 31.5) >= 24.2 then
                small:SetPixel(x, y, original:GetPixel(x, y))
            else
                local r, g, b, a = 0, 0, 0, 0
                for sy = 0, SCALE - 1 do
                    for sx = 0, SCALE - 1 do
                        local c = image:GetPixel(x * SCALE + sx, y * SCALE + sy)
                        r, g, b, a = r + c.r * c.a, g + c.g * c.a, b + c.b * c.a, a + c.a
                    end
                end
                small:SetPixel(x, y, Color(r / a, g / a, b / a, a / (SCALE * SCALE)))
            end
        end
    end
    return small
end

function Start()
    local ok, err = pcall(function()
        local backup = classSet and CLASS_BACKUP or BACKUP
        local output = classSet and CLASS_EXPORT or EXPORT
        local first, last = classSet and 1 or 6, classSet and 5 or 6
        assert(fileSystem:CreateDir(backup), "创建职业原图备份目录失败")
        assert(fileSystem:CreateDir(output), "创建职业输出目录失败")
        -- 先完整备份，再生成全部PNG；最后统一替换，不修改已确认的司仪。
        for classId = first, last do
            local name = "ICON_ZY_" .. classId .. ".png"
            if not fileSystem:FileExists(backup .. name) then
                assert(fileSystem:Copy(ROOT .. name, backup .. name), "备份职业原图失败：" .. name)
            end
        end
        for classId = first, last do
            local name = "ICON_ZY_" .. classId .. ".png"
            local source = Image()
            assert(source:Load(backup .. name), "读取职业原图失败：" .. name)
            assert(source.width == 64 and source.height == 64, "职业原图应为64×64：" .. name)
            print("[class-icon] 已读取 " .. name .. "，保留原菱框，统一金属主体")
            local master = render(source, classId)
            local small = reduce(master, source)
            assert(master:SavePNG(output .. "ICON_ZY_" .. classId .. "_512.png"), "保存职业高清图失败")
            assert(small:SavePNG(output .. name), "保存职业64×64图失败")
            small:Dispose(); master:Dispose(); source:Dispose()
        end
        for classId = first, last do
            local name = "ICON_ZY_" .. classId .. ".png"
            assert(fileSystem:Copy(output .. name, ROOT .. name), "替换职业图标失败：" .. name)
        end
        print("[class-icon] 图标替换完成，尺寸64×64，.meta 未修改；原图统一备份assets/backup")
    end)
    if not ok then log:Write(LOG_ERROR, "[class-icon] " .. tostring(err)) end
    engine:Exit()
end
