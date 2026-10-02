-- 套装图标：CPU 程序化金属徽章，不使用 AI 出图。
-- 完整V3：UrhoXRuntime _proc/generate_set_icons.lua -tapcode_dir=. -tool_mode -graphicsheadless
-- 装备无框徽记：同命令追加 -set-badges，仅输出badge目录，不覆盖完整V3。
local Sets = require("config.EquipmentSetConfig")
local Details = require("_proc.SetIconDetails")
local badgeOnly = false
for _, argument in ipairs(GetArguments()) do
    if argument == "-set-badges" then badgeOnly = true end
end
local OUT = "/workspace/assets/image/套装图标/" .. (badgeOnly and "badge/" or "v3/")
local SIZE, SCALE = 512, 2
local ORDER = { "carapace", "faceless", "riftcrystal", "last_rite", "tidepress", "nitros",
    "swordgate", "starless", "ironwall", "emberscout", "gambler", "bonehunger" }

local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function render(def)
    local red, green, blue, alpha = {}, {}, {}, {}
    local base = def.color
    local light = mix(base, { 215, 211, 192 }, 0.36)
    local shade = mix(base, { 13, 12, 16 }, 0.74)
    local dark = { 7, 8, 12 }
    local rim = mix(base, { 96, 89, 74 }, 0.52)
    local subjectScale = 1
    local function transform(v) return 128 + (v - 128) * subjectScale end
    local function blend(x, y, c, a)
        if a <= 0 then return end
        local i = y * SIZE + x + 1
        local old = alpha[i] or 0
        local combined = a + old * (1 - a)
        local f = old * (1 - a)
        red[i] = (c[1] * a + (red[i] or 0) * f) / combined
        green[i] = (c[2] * a + (green[i] or 0) * f) / combined
        blue[i] = (c[3] * a + (blue[i] or 0) * f) / combined
        alpha[i] = combined
    end
    local function scan(x0, y0, x1, y1, inside, top, bottom, opacity)
        local left = math.max(0, math.floor(x0 * SCALE))
        local right = math.min(SIZE - 1, math.ceil(x1 * SCALE))
        local first = math.max(0, math.floor(y0 * SCALE))
        local last = math.min(SIZE - 1, math.ceil(y1 * SCALE))
        for y = first, last do
            local py = (y + 0.5) / SCALE
            local t = math.max(0, math.min(1, (py - y0) / math.max(1, y1 - y0)))
            local c = bottom and mix(top, bottom, t) or top
            for x = left, right do
                local px = (x + 0.5) / SCALE
                if inside(px, py) then
                    local color = c
                    if subjectScale > 1 and bottom then
                        -- 铜铁斑驳与局部高光，避免均匀渐变呈塑料质感。
                        local seed = math.sin(math.floor(px * 1.5) * 12.9898 + math.floor(py * 1.5) * 78.233) * 43758.5453
                        local grain = (seed - math.floor(seed)) * 2 - 1
                        local mottled = math.sin(px * 0.23 + py * 0.17) * math.sin(py * 0.31 - px * 0.11)
                        local keyLight = math.exp(-((px - 105) ^ 2 + (py - 81) ^ 2) / 2400)
                        local factor = 0.86 + grain * 0.07 + mottled * 0.095 + keyLight * 0.22
                        color = { c[1] * factor, c[2] * factor, c[3] * factor }
                    end
                    blend(x, y, color, opacity or 1)
                end
            end
        end
    end
    local function poly(points, top, bottom, opacity)
        local projected = {}
        for _, p in ipairs(points) do projected[#projected + 1] = { transform(p[1]), transform(p[2]) } end
        points = projected
        local x0, y0, x1, y1 = 256, 256, 0, 0
        for _, p in ipairs(points) do
            x0, y0 = math.min(x0, p[1]), math.min(y0, p[2])
            x1, y1 = math.max(x1, p[1]), math.max(y1, p[2])
        end
        scan(x0, y0, x1, y1, function(x, y)
            local hit, j = false, #points
            for i = 1, #points do
                local p, q = points[i], points[j]
                if (p[2] > y) ~= (q[2] > y) and x < (q[1] - p[1]) * (y - p[2]) / (q[2] - p[2]) + p[1] then
                    hit = not hit
                end
                j = i
            end
            return hit
        end, top, bottom, opacity)
    end
    local function circle(cx, cy, radius, top, bottom, opacity)
        cx, cy, radius = transform(cx), transform(cy), radius * subjectScale
        scan(cx - radius, cy - radius, cx + radius, cy + radius,
            function(x, y) return (x - cx) ^ 2 + (y - cy) ^ 2 <= radius ^ 2 end,
            top, bottom, opacity)
    end
    local function line(x0, y0, x1, y1, width, color, opacity)
        x0, y0, x1, y1 = transform(x0), transform(y0), transform(x1), transform(y1)
        width = width * subjectScale
        local vx, vy = x1 - x0, y1 - y0
        local len2 = vx * vx + vy * vy
        scan(math.min(x0, x1) - width, math.min(y0, y1) - width,
            math.max(x0, x1) + width, math.max(y0, y1) + width,
            function(x, y)
                local t = len2 > 0 and math.max(0, math.min(1, ((x - x0) * vx + (y - y0) * vy) / len2)) or 0
                return (x - x0 - t * vx) ^ 2 + (y - y0 - t * vy) ^ 2 <= (width * 0.5) ^ 2
            end, color, nil, opacity)
    end
    local function stroke(points, width, color, closed, opacity)
        for i = 1, #points - 1 do line(points[i][1], points[i][2], points[i + 1][1], points[i + 1][2], width, color, opacity) end
        if closed then line(points[#points][1], points[#points][2], points[1][1], points[1][2], width, color, opacity) end
    end
    local function arc(cx, cy, radius, first, last, width, color, opacity)
        local points = {}
        for i = 0, 40 do
            local a = (first + (last - first) * i / 40) * math.pi / 180
            points[#points + 1] = { cx + math.cos(a) * radius, cy + math.sin(a) * radius }
        end
        stroke(points, width, color, false, opacity)
    end
    local function bezier(p0, p1, p2, p3, width, color, opacity)
        local points = {}
        for i = 0, 28 do
            local t, u = i / 28, 1 - i / 28
            points[#points + 1] = { u ^ 3 * p0[1] + 3 * u ^ 2 * t * p1[1] + 3 * u * t ^ 2 * p2[1] + t ^ 3 * p3[1],
                u ^ 3 * p0[2] + 3 * u ^ 2 * t * p1[2] + 3 * u * t ^ 2 * p2[2] + t ^ 3 * p3[2] }
        end
        stroke(points, width, color, false, opacity)
    end
    local function glyph(points, amount)
        stroke(points, 5, dark, true)
        poly(points, amount and mix(light, base, amount) or light, shade)
        stroke(points, 1.6, mix(light, { 225, 216, 191 }, 0.32), true, 0.72)
    end
    local function oct(inset, cut, dy)
        dy = dy or 0
        local far = 256 - inset
        return { { inset + cut, inset + dy }, { far - cut, inset + dy }, { far, inset + cut + dy },
            { far, far - cut + dy }, { far - cut, far + dy }, { inset + cut, far + dy },
            { inset, far - cut + dy }, { inset, inset + cut + dy } }
    end
    -- 装备角标不画八角框、黑底、背景泛光或上下装饰线，只保留主体。
    if not badgeOnly then
        poly(oct(7, 40, 4), { 0, 0, 0 }, nil, 0.55)
        poly(oct(7, 40), mix(rim, { 171, 160, 134 }, 0.3), { 23, 22, 23 })
        poly(oct(11, 38), { 18, 17, 21 }, { 7, 8, 12 })
        stroke(oct(15, 36), 1.2, rim, true, 0.65)
        for i = 8, 1, -1 do circle(128, 125, 65 + i * 3, base, nil, 0.009) end
        line(57, 11, 196, 11, 1, light, 0.45)
        line(57, 244, 196, 244, 1, base, 0.25)
    end
    -- 只变换后续主体，框体不随符号放大；主体轮廓约扩张22%。
    subjectScale = 1.22
    if def.id == "starless" then
        -- 只提亮星盘主体：保留原紫色配色与暗底，增强细轨和星芒的对比。
        base = mix(base, { 206, 188, 242 }, 0.36)
        light = mix(base, { 237, 230, 250 }, 0.52)
        shade = mix(base, { 24, 20, 38 }, 0.60)
    end

    if def.id == "carapace" then
        -- 对称甲虫壳：叠片、头角与三对肢节。
        for _, side in ipairs({ -1, 1 }) do
            for i = 0, 2 do
                stroke({ { 128 + side * 30, 108 + i * 25 }, { 128 + side * 53, 95 + i * 29 },
                    { 128 + side * 67, 106 + i * 31 } }, 7, shade)
                stroke({ { 128 + side * 30, 106 + i * 25 }, { 128 + side * 53, 93 + i * 29 },
                    { 128 + side * 67, 104 + i * 31 } }, 3.5, light)
            end
        end
        glyph({ { 100, 81 }, { 111, 65 }, { 145, 65 }, { 156, 81 }, { 147, 96 }, { 109, 96 } })
        glyph({ { 89, 102 }, { 104, 86 }, { 152, 86 }, { 167, 102 }, { 165, 154 }, { 149, 183 },
            { 128, 196 }, { 107, 183 }, { 91, 154 } })
        line(128, 94, 128, 185, 4, dark)
        for _, y in ipairs({ 121, 143, 163 }) do
            stroke({ { 94, y - 8 }, { 125, y + 2 } }, 3.6, shade)
            stroke({ { 131, y + 2 }, { 162, y - 8 } }, 3.6, shade)
        end
        stroke({ { 113, 73 }, { 107, 53 }, { 96, 51 } }, 4, light)
        stroke({ { 143, 73 }, { 149, 53 }, { 160, 51 } }, 4, light)
    elseif def.id == "faceless" then
        -- 无面眼罩与夜行兜帽。
        glyph({ { 128, 54 }, { 163, 74 }, { 181, 130 }, { 165, 179 }, { 128, 199 }, { 91, 179 }, { 75, 130 }, { 93, 74 } }, 0.65)
        glyph({ { 102, 88 }, { 128, 79 }, { 154, 88 }, { 161, 115 }, { 152, 151 }, { 128, 180 }, { 104, 151 }, { 95, 115 } })
        poly({ { 98, 111 }, { 118, 116 }, { 123, 131 }, { 104, 123 } }, dark)
        poly({ { 158, 111 }, { 138, 116 }, { 133, 131 }, { 152, 123 } }, dark)
        stroke({ { 126, 138 }, { 122, 150 }, { 134, 150 } }, 3, shade)
        line(117, 159, 138, 159, 3, dark)
        arc(187, 65, 11, 75, 288, 4, light)
    elseif def.id == "riftcrystal" then
        -- 主晶体与两侧碎片，用亮暗面区分几何。
        glyph({ { 128, 52 }, { 159, 88 }, { 148, 155 }, { 128, 191 }, { 108, 155 }, { 97, 88 } })
        poly({ { 128, 55 }, { 128, 186 }, { 108, 153 }, { 100, 90 } }, mix(base, { 255, 255, 255 }, 0.4), base)
        stroke({ { 100, 90 }, { 128, 105 }, { 156, 90 } }, 2.5, light)
        line(128, 104, 128, 186, 2, light)
        glyph({ { 69, 116 }, { 87, 92 }, { 104, 132 }, { 97, 174 }, { 82, 160 } }, 0.3)
        glyph({ { 186, 103 }, { 170, 95 }, { 156, 149 }, { 170, 175 }, { 182, 147 } }, 0.5)
        stroke({ { 115, 72 }, { 128, 86 }, { 139, 77 } }, 4, dark)
        glyph({ { 195, 78 }, { 201, 86 }, { 197, 94 }, { 191, 85 } })
    elseif def.id == "last_rite" then
        -- 圣杯和仪式光环，不使用职业人物头像。
        arc(128, 86, 42, 195, 345, 3, light, 0.8)
        for _, a in ipairs({ 215, 245, 270, 295, 325 }) do
            local rad = a * math.pi / 180
            line(128 + math.cos(rad) * 47, 86 + math.sin(rad) * 47,
                128 + math.cos(rad) * 56, 86 + math.sin(rad) * 56, 3, light)
        end
        glyph({ { 86, 96 }, { 170, 96 }, { 163, 126 }, { 144, 148 }, { 135, 153 }, { 135, 178 },
            { 154, 183 }, { 160, 193 }, { 96, 193 }, { 102, 183 }, { 121, 178 }, { 121, 153 }, { 112, 148 }, { 93, 126 } })
        arc(86, 114, 17, 80, 280, 5, base)
        arc(170, 114, 17, -100, 100, 5, base)
        glyph({ { 118, 81 }, { 128, 58 }, { 138, 81 }, { 128, 92 } })
        line(99, 103, 157, 103, 4, light)
        circle(128, 123, 6, base)
    elseif def.id == "tidepress" then
        -- 水滴中的压力脉纹，周围压缩水环。
        arc(128, 137, 66, 160, 310, 6, shade)
        arc(128, 137, 65, -25, 80, 5, light)
        glyph({ { 128, 53 }, { 148, 87 }, { 165, 111 }, { 173, 135 }, { 169, 159 }, { 152, 180 },
            { 128, 188 }, { 104, 180 }, { 87, 159 }, { 83, 135 }, { 91, 111 }, { 108, 87 } })
        bezier({ 102, 145 }, { 115, 122 }, { 140, 174 }, { 155, 146 }, 4, dark)
        bezier({ 101, 128 }, { 112, 105 }, { 137, 154 }, { 155, 126 }, 4, shade)
        bezier({ 111, 106 }, { 108, 111 }, { 96, 121 }, { 97, 136 }, 4, light)
        glyph({ { 186, 87 }, { 192, 99 }, { 183, 112 }, { 179, 101 } }, 0.2)
    elseif def.id == "nitros" then
        -- 急速轮毂、燃焰与尾迹。
        glyph({ { 77, 119 }, { 88, 95 }, { 92, 65 }, { 119, 83 }, { 128, 51 }, { 148, 82 },
            { 158, 71 }, { 177, 107 }, { 169, 124 }, { 130, 145 } }, 0.18)
        circle(133, 144, 45, dark)
        circle(133, 142, 40, light, shade)
        circle(133, 142, 30, dark)
        for i = 0, 5 do
            local a = i * math.pi / 3
            line(133 + math.cos(a) * 10, 142 + math.sin(a) * 10,
                133 + math.cos(a) * 29, 142 + math.sin(a) * 29, 5, base)
        end
        circle(133, 142, 10, light, base)
        line(58, 145, 83, 145, 6, base)
        line(67, 164, 91, 164, 5, light)
        line(79, 183, 160, 183, 3, shade)
    elseif def.id == "swordgate" then
        -- 门框与三柄倒悬飞剑。
        stroke({ { 82, 187 }, { 82, 78 }, { 128, 56 }, { 174, 78 }, { 174, 187 } }, 11, shade)
        stroke({ { 82, 185 }, { 82, 76 }, { 128, 54 }, { 174, 76 }, { 174, 185 } }, 5, light)
        for _, p in ipairs({ { 103, 104, 161 }, { 128, 87, 190 }, { 153, 104, 161 } }) do
            local x, y, bottom = p[1], p[2], p[3]
            glyph({ { x - 5, y }, { x + 5, y }, { x + 5, bottom - 14 }, { x, bottom }, { x - 5, bottom - 14 } })
            line(x - 12, y - 3, x + 12, y - 3, 4, base)
            line(x, y - 4, x, y - 16, 4, light)
        end
        line(72, 194, 184, 194, 4, light)
    elseif def.id == "starless" then
        -- 月蚀核心与断裂星轨。
        circle(128, 126, 39, shade)
        circle(128, 126, 29, dark)
        arc(128, 126, 39, 180, 295, 5, light)
        arc(128, 126, 67, 25, 180, 4, base)
        arc(128, 126, 67, 205, 337, 3, light, 0.8)
        stroke({ { 82, 82 }, { 128, 57 }, { 187, 109 }, { 157, 176 }, { 82, 171 } }, 2, base, false, 0.5)
        for _, p in ipairs({ { 82, 82, 5 }, { 128, 57, 6 }, { 187, 109, 5 }, { 157, 176, 6 }, { 82, 171, 4 } }) do
            circle(p[1], p[2], p[3], light, base)
        end
        glyph({ { 128, 113 }, { 132, 123 }, { 143, 127 }, { 132, 131 }, { 128, 141 }, { 124, 131 }, { 113, 127 }, { 124, 123 } })
    elseif def.id == "ironwall" then
        -- 塔盾内部帝国城垛。
        glyph({ { 81, 75 }, { 128, 56 }, { 175, 75 }, { 171, 147 }, { 155, 175 }, { 128, 197 },
            { 101, 175 }, { 85, 147 } })
        poly({ { 95, 86 }, { 128, 73 }, { 161, 86 }, { 157, 144 }, { 143, 165 }, { 128, 178 },
            { 113, 165 }, { 99, 144 } }, shade, dark)
        glyph({ { 105, 147 }, { 105, 110 }, { 113, 110 }, { 113, 99 }, { 122, 99 }, { 122, 110 },
            { 134, 110 }, { 134, 99 }, { 143, 99 }, { 143, 110 }, { 151, 110 }, { 151, 147 } }, 0.3)
        poly({ { 123, 131 }, { 133, 131 }, { 133, 148 }, { 123, 148 } }, dark)
        line(111, 155, 145, 155, 3, light)
    elseif def.id == "emberscout" then
        -- 弓、箭与燃烧箭簇。
        bezier({ 154, 72 }, { 69, 77 }, { 66, 166 }, { 151, 192 }, 9, shade)
        bezier({ 151, 69 }, { 68, 74 }, { 65, 163 }, { 148, 189 }, 4.5, light)
        stroke({ { 150, 70 }, { 125, 127 }, { 149, 189 } }, 2.5, base)
        line(96, 142, 170, 90, 5, light)
        glyph({ { 158, 91 }, { 167, 74 }, { 183, 69 }, { 184, 88 }, { 169, 103 } })
        glyph({ { 171, 75 }, { 175, 53 }, { 187, 64 }, { 198, 65 }, { 191, 84 }, { 180, 85 } }, 0.2)
        stroke({ { 88, 141 }, { 86, 153 }, { 103, 151 } }, 4, base)
    elseif def.id == "gambler" then
        -- 菱形骰子与残响双环，点数是可读核心。
        arc(128, 130, 72, 180, 285, 3, light, 0.7)
        arc(128, 130, 72, -10, 80, 4, base)
        glyph({ { 123, 66 }, { 184, 101 }, { 184, 162 }, { 124, 193 }, { 71, 161 }, { 71, 99 } })
        poly({ { 124, 128 }, { 184, 102 }, { 184, 161 }, { 124, 193 } }, shade)
        poly({ { 72, 100 }, { 124, 128 }, { 124, 191 }, { 72, 160 } }, base, shade)
        stroke({ { 72, 100 }, { 124, 128 }, { 184, 102 } }, 3, light)
        line(124, 128, 124, 191, 3, dark)
        for _, p in ipairs({ { 113, 91 }, { 139, 107 }, { 92, 127 }, { 103, 153 }, { 149, 140 }, { 164, 159 } }) do
            circle(p[1], p[2], 5, dark)
        end
    elseif def.id == "bonehunger" then
        -- 双獠牙衔骨，原色铜棕，骨白高光。
        glyph({ { 79, 67 }, { 103, 95 }, { 97, 148 }, { 112, 179 }, { 95, 170 }, { 78, 139 }, { 73, 102 } }, 0.15)
        glyph({ { 177, 67 }, { 153, 95 }, { 159, 148 }, { 144, 179 }, { 161, 170 }, { 178, 139 }, { 183, 102 } }, 0.15)
        circle(92, 126, 14, light, shade)
        circle(102, 132, 13, light, shade)
        circle(164, 126, 14, light, shade)
        circle(154, 132, 13, light, shade)
        glyph({ { 92, 122 }, { 164, 122 }, { 169, 141 }, { 156, 151 }, { 100, 151 }, { 87, 141 } })
        poly({ { 106, 122 }, { 150, 122 }, { 148, 139 }, { 108, 139 } }, mix(light, { 255, 242, 215 }, 0.5), base)
        glyph({ { 106, 172 }, { 128, 194 }, { 150, 172 }, { 145, 185 }, { 128, 204 }, { 111, 185 } }, 0.3)
    end
    -- 主体二次刻画：套装各有独立结构，不只是同一平面符号换色。
    local edge = mix(light, { 221, 213, 190 }, 0.48)
    if def.id == "carapace" then
        for _, y in ipairs({ 104, 125, 146, 164 }) do
            for _, side in ipairs({ -1, 1 }) do
                circle(128 + side * 21, y, 2.2, edge, shade)
            end
        end
        stroke({ { 110, 96 }, { 104, 133 }, { 113, 166 } }, 2, edge, false, 0.75)
        stroke({ { 135, 118 }, { 141, 125 }, { 136, 133 }, { 145, 143 } }, 1.6, dark)
    elseif def.id == "faceless" then
        poly({ { 102, 90 }, { 114, 88 }, { 109, 112 }, { 99, 113 } }, edge, shade, 0.48)
        poly({ { 132, 84 }, { 151, 93 }, { 153, 108 }, { 139, 105 } }, base, shade, 0.55)
        stroke({ { 88, 123 }, { 93, 150 }, { 111, 177 } }, 2, edge, false, 0.65)
        stroke({ { 141, 86 }, { 136, 101 }, { 143, 110 } }, 1.5, dark)
        stroke({ { 126, 161 }, { 124, 173 } }, 1.7, dark)
    elseif def.id == "riftcrystal" then
        poly({ { 128, 56 }, { 148, 88 }, { 132, 102 } }, edge, base, 0.85)
        poly({ { 130, 108 }, { 151, 96 }, { 143, 155 } }, base, shade, 0.65)
        stroke({ { 128, 120 }, { 120, 129 }, { 123, 144 }, { 113, 155 } }, 2, dark)
        stroke({ { 88, 105 }, { 89, 133 }, { 85, 151 } }, 2, edge, false, 0.8)
        line(168, 119, 162, 146, 1.6, edge)
    elseif def.id == "last_rite" then
        arc(128, 115, 27, 30, 150, 2, edge, 0.7)
        stroke({ { 103, 109 }, { 109, 131 }, { 117, 138 } }, 2.5, edge, false, 0.75)
        for _, x in ipairs({ 109, 128, 147 }) do
            glyph({ { x, 116 }, { x + 3, 121 }, { x, 126 }, { x - 3, 121 } }, 0.5)
        end
        line(128, 155, 128, 174, 2, edge)
        line(105, 187, 150, 187, 2, edge, 0.8)
    elseif def.id == "tidepress" then
        poly({ { 127, 60 }, { 116, 109 }, { 91, 137 }, { 104, 99 } }, edge, base, 0.45)
        bezier({ 100, 160 }, { 116, 172 }, { 142, 168 }, { 156, 156 }, 2, edge, 0.85)
        circle(144, 103, 3.5, edge, base)
        circle(151, 113, 2.4, edge, base)
        stroke({ { 132, 169 }, { 128, 177 }, { 137, 174 } }, 1.6, dark)
    elseif def.id == "nitros" then
        arc(133, 142, 35, 190, 305, 2, edge, 0.9)
        for i = 0, 11 do
            local a = i * math.pi / 6
            line(133 + math.cos(a) * 40, 142 + math.sin(a) * 40,
                133 + math.cos(a) * 44, 142 + math.sin(a) * 44, 2.5, dark)
        end
        poly({ { 115, 100 }, { 123, 76 }, { 133, 110 }, { 150, 98 }, { 143, 124 } }, edge, base, 0.55)
        line(63, 156, 78, 156, 2, edge, 0.6)
    elseif def.id == "swordgate" then
        for _, p in ipairs({ { 82, 88 }, { 82, 151 }, { 174, 88 }, { 174, 151 } }) do
            circle(p[1], p[2], 2.5, edge, shade)
        end
        for _, p in ipairs({ { 103, 104, 158 }, { 128, 90, 184 }, { 153, 104, 158 } }) do
            line(p[1] - 1.6, p[2], p[1] - 1.6, p[3], 1.6, edge, 0.85)
            line(p[1] + 2.5, p[2] + 3, p[1] + 2.5, p[3] - 5, 1.4, dark)
        end
        stroke({ { 100, 73 }, { 128, 62 }, { 158, 77 } }, 1.6, base, false, 0.9)
    elseif def.id == "starless" then
        arc(128, 126, 47, 195, 280, 1.7, shade, 0.7)
        arc(128, 126, 76, 70, 155, 1.2, edge, 0.6)
        for i = 0, 8 do
            local a = (211 + i * 10) * math.pi / 180
            line(128 + math.cos(a) * 61, 126 + math.sin(a) * 61,
                128 + math.cos(a) * 66, 126 + math.sin(a) * 66, 1.5, edge, 0.8)
        end
        circle(128, 126, 4, edge, base)
    elseif def.id == "ironwall" then
        for _, p in ipairs({ { 93, 87 }, { 163, 87 }, { 99, 146 }, { 157, 146 }, { 128, 185 } }) do
            circle(p[1], p[2], 3.1, edge, shade)
        end
        stroke({ { 93, 93 }, { 96, 136 }, { 112, 167 } }, 2, edge, false, 0.7)
        line(110, 123, 145, 123, 1.5, dark)
        line(137, 124, 137, 138, 1.5, dark)
        stroke({ { 145, 151 }, { 139, 158 }, { 142, 161 } }, 2, dark)
    elseif def.id == "emberscout" then
        for i = 0, 5 do line(83 + i * 2, 108 + i * 6, 89 + i * 2, 112 + i * 6, 1.4, base) end
        line(104, 135, 167, 90, 1.4, edge)
        stroke({ { 173, 91 }, { 176, 80 }, { 181, 82 } }, 1.5, dark)
        glyph({ { 94, 137 }, { 82, 134 }, { 83, 143 }, { 92, 145 } }, 0.4)
        circle(186, 51, 2.2, edge)
        circle(202, 71, 2, base)
    elseif def.id == "gambler" then
        stroke({ { 77, 99 }, { 123, 73 }, { 177, 102 } }, 2, edge, false, 0.8)
        stroke({ { 78, 105 }, { 78, 156 }, { 118, 181 } }, 2, edge, false, 0.55)
        stroke({ { 168, 116 }, { 162, 127 }, { 165, 134 } }, 1.7, dark)
        for _, p in ipairs({ { 113, 91 }, { 139, 107 }, { 92, 127 }, { 103, 153 }, { 149, 140 }, { 164, 159 } }) do
            circle(p[1] - 1.2, p[2] - 1.5, 1.7, edge, nil, 0.55)
        end
    elseif def.id == "bonehunger" then
        stroke({ { 82, 80 }, { 87, 108 }, { 87, 142 } }, 2, edge, false, 0.7)
        stroke({ { 174, 80 }, { 169, 108 }, { 169, 142 } }, 2, edge, false, 0.7)
        stroke({ { 110, 126 }, { 112, 132 }, { 121, 131 }, { 124, 139 } }, 1.6, dark)
        line(111, 141, 147, 141, 1.2, edge)
        circle(92, 126, 3, shade)
        circle(164, 126, 3, shade)
        line(128, 192, 128, 199, 2, edge)
    end
    Details.draw(def.id, {
        poly = poly, circle = circle, line = line, stroke = stroke, arc = arc, bezier = bezier,
        glyph = glyph, mix = mix, base = base, light = light, shade = shade, dark = dark, edge = edge,
    })
    local img = Image()
    assert(img:SetSize(SIZE, SIZE, 4), "创建图像失败")
    for y = 0, SIZE - 1 do
        for x = 0, SIZE - 1 do
            local i = y * SIZE + x + 1
            local a = alpha[i] or 0
            if a > 0 then
                -- 非随机拉丝纹理：细微亮度起伏，不抢小尺寸主体。
                local grain = 1 + 0.018 * math.sin(x * 1.7 + y * 0.37)
                img:SetPixel(x, y, Color(math.min(1, red[i] * grain / 255),
                    math.min(1, green[i] * grain / 255), math.min(1, blue[i] * grain / 255), a))
            else
                img:SetPixel(x, y, Color(0, 0, 0, 0))
            end
        end
    end
    assert(img:Resize(256, 256), "图像降采样失败")
    local path = OUT .. "SET_" .. def.id .. ".png"
    assert(img:SavePNG(path), "保存失败：" .. path)
    img:Dispose()
    print("[SetIcons] " .. def.id .. " " .. def.name .. " -> " .. path)
end

function Start()
    local ok, err = pcall(function()
        assert(fileSystem:CreateDir(OUT), "创建素材目录失败")
        for _, id in ipairs(ORDER) do
            local def = Sets.get(id)
            assert(def, "缺少套装：" .. id)
            render(def)
        end
        print("[SetIcons] ALL PASS: 12套配色、透明PNG、256x256，模式=" .. (badgeOnly and "无框装备徽记" or "完整V3"))
    end)
    if not ok then log:Write(LOG_ERROR, "[SetIcons] " .. tostring(err)) end
    engine:Exit()
end
