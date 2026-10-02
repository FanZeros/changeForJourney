-- 套装图标审核稿：CPU 程序化金属徽章，不使用 AI 出图，不改游戏界面。
-- 用法：UrhoXRuntime _proc/generate_set_icons.lua -tapcode_dir=. -tool_mode -graphicsheadless
-- 配色直接读取 EquipmentSetConfig；512px 绘制后降采样为256px透明 PNG。
local Sets = require("config.EquipmentSetConfig")
local OUT = "/workspace/assets/image/套装图标/"
local SIZE, SCALE = 512, 2
local ORDER = { "carapace", "faceless", "riftcrystal", "last_rite", "tidepress", "nitros",
    "swordgate", "starless", "ironwall", "emberscout", "gambler", "bonehunger" }

local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function render(def)
    local red, green, blue, alpha = {}, {}, {}, {}
    local base = def.color
    local light = mix(base, { 255, 245, 216 }, 0.68)
    local shade = mix(base, { 15, 12, 18 }, 0.65)
    local dark = { 10, 12, 17 }
    local rim = mix(base, { 156, 142, 114 }, 0.38)
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
                if inside(px, py) then blend(x, y, c, opacity or 1) end
            end
        end
    end
    local function poly(points, top, bottom, opacity)
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
        scan(cx - radius, cy - radius, cx + radius, cy + radius,
            function(x, y) return (x - cx) ^ 2 + (y - cy) ^ 2 <= radius ^ 2 end,
            top, bottom, opacity)
    end
    local function line(x0, y0, x1, y1, width, color, opacity)
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
        stroke(points, 1.6, light, true, 0.6)
    end
    local function oct(inset, cut, dy)
        dy = dy or 0
        local far = 256 - inset
        return { { inset + cut, inset + dy }, { far - cut, inset + dy }, { far, inset + cut + dy },
            { far, far - cut + dy }, { far - cut, far + dy }, { inset + cut, far + dy },
            { inset, far - cut + dy }, { inset, inset + cut + dy } }
    end
    -- 切角金属框、冷黑珐琅底、细密刻线，角外透明。
    poly(oct(14, 44, 5), { 0, 0, 0 }, nil, 0.55)
    poly(oct(14, 44), mix(rim, { 238, 226, 202 }, 0.70), { 40, 33, 31 })
    poly(oct(19, 42), { 20, 19, 23 }, { 7, 8, 12 })
    poly(oct(23, 40), mix(rim, light, 0.35), shade)
    poly(oct(27, 37), { 14, 16, 23 }, { 8, 10, 15 })
    stroke(oct(31, 35), 1, base, true, 0.45)
    -- 中心色光以多层透明圆叠加，避免整幅亮色块。
    for i = 10, 1, -1 do circle(128, 127, 55 + i * 3, base, nil, 0.012) end
    arc(128, 128, 77, 195, 270, 1.5, light, 0.15)
    arc(128, 128, 77, 20, 82, 1.5, base, 0.20)
    -- 框内四点及下方徽记槽，所有套装共享。
    for _, p in ipairs({ { 45, 75 }, { 211, 75 }, { 45, 181 }, { 211, 181 } }) do
        circle(p[1], p[2] + 1, 3.5, dark)
        circle(p[1], p[2], 2.1, light, shade)
    end
    line(65, 34, 191, 34, 1.2, light, 0.70)
    line(67, 222, 189, 222, 1, base, 0.55)
    glyph({ { 121, 213 }, { 128, 208 }, { 135, 213 }, { 128, 218 } })

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
        print("[SetIcons] ALL PASS: 12套配色、透明PNG、256x256")
    end)
    if not ok then log:Write(LOG_ERROR, "[SetIcons] " .. tostring(err)) end
    engine:Exit()
end
