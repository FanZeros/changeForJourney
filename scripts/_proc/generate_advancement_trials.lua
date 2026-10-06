-- 转职试稿：沿用职业徽章的 CPU 多边形、贝塞尔与预乘 Alpha 降采样范式。
-- 基于 procedural-lua-headless 的 Start/pcall/Exit 模板；不启动游戏，不替换正式资源。
-- UrhoXRuntime _proc/generate_advancement_trials.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
local ROOT = "/workspace/assets/image/职业图标/"
local OUT = "/workspace/assets/image/审核_转职图标试绘/"
local BACKUP = "/workspace/assets/backup/职业图标/司仪一转试绘原图/"
local SIZE, SCALE = 560, 2
local CENTER, RADIUS = 139.5, 104
local DARK = { 14, 12, 10 }
local GOLD = { 161, 121, 64 }
local BONE = { 220, 206, 170 }
local SHADE = { 77, 55, 30 }
local ORDER = { 111, 112 }

local function clamp(v, low, high) return math.max(low, math.min(high, v)) end
local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

---@param source Image
---@param branchId integer
---@return Image
local function render(source, branchId)
    local red, green, blue, alpha = {}, {}, {}, {}
    -- r>=104 的旧铁圆环及透明外缘只读保留；所有主体限制在环内，避免擦边。
    for y = 0, SIZE - 1 do
        for x = 0, SIZE - 1 do
            local px, py = (x + 0.5) / SCALE - 0.5, (y + 0.5) / SCALE - 0.5
            local i = y * SIZE + x + 1
            local c = source:GetPixelBilinear(clamp(px / 279, 0, 1), clamp(py / 279, 0, 1))
            red[i], green[i], blue[i], alpha[i] = c.r * 255, c.g * 255, c.b * 255, c.a
            if (px - CENTER) ^ 2 + (py - CENTER) ^ 2 < RADIUS ^ 2 then
                local light = math.exp(-((px - 117) ^ 2 + (py - 103) ^ 2) / 4900)
                local grain = math.sin(px * 2.7 + py * 1.5) * math.sin(py * 2.2 - px * 0.9)
                local tarnish = math.sin(px * 0.09 + py * 0.06) * math.sin(py * 0.13 - px * 0.04)
                red[i], green[i], blue[i], alpha[i] = 23 + light * 11 + grain + tarnish * 1.8,
                    22 + light * 8 + grain + tarnish * 1.7, 18 + light * 4 + grain * 0.8 + tarnish, 1
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
            local base = bottom and mix(top, bottom, t) or top
            for x = math.max(0, math.floor(x0 * SCALE)), math.min(SIZE - 1, math.ceil(x1 * SCALE)) do
                local px = (x + 0.5) / SCALE - 0.5
                if (px - CENTER) ^ 2 + (py - CENTER) ^ 2 < RADIUS ^ 2 and inside(px, py) then
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

    if branchId == 111 then
        -- 延祷：同一圣铃连接两份祷盾；沙漏提示延缓而不是两道声波。
        for _, side in ipairs({ -1, 1 }) do
            local x = 140 + side * 65
            stroke({ { 140, 111 }, { 140 + side * 36, 117 }, { x, 137 } }, 7, DARK, false)
            stroke({ { 140, 111 }, { 140 + side * 36, 117 }, { x, 137 } }, 2.2, GOLD, false)
            emblem({ { x - 20, 143 }, { x, 134 }, { x + 20, 143 }, { x + 17, 170 },
                { x + 10, 183 }, { x, 192 }, { x - 10, 183 }, { x - 17, 170 } }, GOLD, SHADE)
            polygon({ { x - 14, 148 }, { x, 141 }, { x + 14, 148 }, { x + 11, 170 },
                { x, 182 }, { x - 11, 170 } }, { 44, 39, 27 }, DARK)
            star(x, 161, 10, BONE)
            line(x - 17, 145, x - 14, 166, 1.4, BONE, 0.65)
        end
        emblem({ { 128, 52 }, { 152, 52 }, { 152, 57 }, { 146, 65 }, { 146, 69 },
            { 152, 77 }, { 152, 82 }, { 128, 82 }, { 128, 77 }, { 134, 69 }, { 134, 65 }, { 128, 57 } }, GOLD, SHADE)
        polygon({ { 133, 57 }, { 147, 57 }, { 140, 65 } }, DARK)
        polygon({ { 140, 69 }, { 147, 77 }, { 133, 77 } }, BONE, GOLD)
    else
        -- 领忏：解开的债链置于铃下；上方展开的祷光表达全队回馈。
        arc(140, 121, 61, 64, 205, 335, 6.5, DARK)
        arc(140, 121, 61, 64, 205, 335, 2.1, GOLD)
        for _, p in ipairs({ { 140, 49, 11 }, { 92, 70, 7 }, { 188, 70, 7 } }) do
            star(p[1], p[2], p[3] + 2, DARK)
            star(p[1], p[2], p[3], BONE)
        end
        for _, side in ipairs({ -1, 1 }) do
            for i = 0, 2 do
                local x, y = 140 + side * (44 + i * 17), 216 - i * 10
                arc(x, y, 11, 7, 0, 360, 8, DARK)
                arc(x, y, 11, 7, 0, 360, 4.2, GOLD)
                arc(x, y, 11, 7, 205, 305, 1.3, BONE)
            end
            -- 两端明显断开，不能只是闭合的项链；中央留出铃舌空间。
            arc(140 + side * 24, 224, 10, 6, side == 1 and 205 or 25,
                side == 1 and 505 or 325, 7.5, DARK)
            arc(140 + side * 24, 224, 10, 6, side == 1 and 205 or 25,
                side == 1 and 505 or 325, 3.6, BONE)
        end
    end

    -- 两个分支共用骨白旧铜圣铃；不是换色图，以附属结构区分机制。
    arc(140, 97, 10, 10, 0, 360, 10, DARK)
    arc(140, 97, 10, 10, 0, 360, 4.4, GOLD)
    arc(140, 97, 10, 10, 200, 310, 1.9, BONE)
    line(140, 105, 140, 119, 11, DARK)
    line(140, 105, 140, 119, 5.4, GOLD)
    local body = { { 99, 183 } }
    curve(body, 109, 165, 106, 137, 120, 125)
    curve(body, 129, 117, 151, 117, 160, 125)
    curve(body, 174, 137, 171, 165, 181, 183)
    curve(body, 192, 190, 188, 197, 177, 199)
    curve(body, 157, 204, 123, 204, 103, 199)
    curve(body, 92, 197, 88, 190, 99, 183)
    stroke(body, 10, DARK, true)
    polygon(body, BONE, SHADE)
    polygon({ { 145, 121 }, { 160, 127 }, { 168, 146 }, { 171, 172 },
        { 183, 188 }, { 166, 193 }, { 157, 172 }, { 153, 145 } }, GOLD, SHADE, 0.55)
    stroke(body, 2, GOLD, true)
    local glint = { { 123, 129 } }
    curve(glint, 111, 140, 117, 163, 105, 180)
    stroke(glint, 4, BONE, false, 0.9)
    local shadow = { { 160, 130 } }
    curve(shadow, 171, 145, 164, 164, 177, 181)
    stroke(shadow, 3, SHADE, false)
    ellipse(140, 193, 45, 9, GOLD, BONE)
    ellipse(140, 195, 35, 5, DARK, { 39, 29, 18 })
    line(140, 194, 140, 211, 5, GOLD)
    ellipse(140, 212, 7.5, 6.3, BONE, SHADE)
    star(140, 153, 15, DARK)
    star(140, 153, 11, BONE)
    -- 稀疏刻痕，不使用模糊光晕或霓虹；保持小尺寸主体识别。
    line(126, 172, 123, 177, 0.8, SHADE, 0.6)
    line(154, 137, 156, 142, 0.9, SHADE, 0.55)

    local image = Image()
    assert(image:SetSize(SIZE, SIZE, 4), "创建转职母图失败")
    for y = 0, SIZE - 1 do
        for x = 0, SIZE - 1 do
            local i = y * SIZE + x + 1
            image:SetPixel(x, y, Color(red[i] / 255, green[i] / 255, blue[i] / 255, alpha[i]))
        end
    end
    return image
end

---@param master Image
---@param original Image
---@return Image
local function reduce(master, original)
    local small = Image()
    assert(small:SetSize(280, 280, 4), "创建280×280转职图失败")
    for y = 0, 279 do
        for x = 0, 279 do
            if (x - CENTER) ^ 2 + (y - CENTER) ^ 2 >= RADIUS ^ 2 then
                small:SetPixel(x, y, original:GetPixel(x, y))
            else
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
    end
    return small
end

function Start()
    local ok, err = pcall(function()
        assert(fileSystem:CreateDir(OUT), "创建转职审核目录失败")
        assert(fileSystem:CreateDir(BACKUP), "创建转职原图备份目录失败")
        for _, branchId in ipairs(ORDER) do
            local name = "UI_icon_ZY_" .. branchId .. ".png"
            if not fileSystem:FileExists(BACKUP .. name) then
                assert(fileSystem:Copy(ROOT .. name, BACKUP .. name), "备份转职原图失败：" .. name)
            end
            local source = Image()
            assert(source:Load(BACKUP .. name), "读取转职原图失败：" .. name)
            assert(source.width == 280 and source.height == 280, "转职原图尺寸不是280×280")
            print("[adv-trial] " .. branchId .. " 原图读取完成，开始环内试绘")
            local master = render(source, branchId)
            local small = reduce(master, source)
            assert(master:SavePNG(OUT .. "UI_icon_ZY_" .. branchId .. "_560.png"), "保存母图失败")
            assert(small:SavePNG(OUT .. name), "保存审核图失败")
            small:Dispose(); master:Dispose(); source:Dispose()
            print("[adv-trial] " .. branchId .. " 审核PNG已保存，正式素材及.meta未修改")
        end
        print("[adv-trial] ALL PASS：2枚司仪一转试稿，原图备份在assets/backup")
    end)
    if not ok then log:Write(LOG_ERROR, "[adv-trial] " .. tostring(err)) end
    engine:Exit()
end
