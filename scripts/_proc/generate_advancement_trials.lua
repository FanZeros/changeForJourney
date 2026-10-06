-- 职业一转：CPU 多边形/贝塞尔绘制，主体和底板全部程序生成。
-- 基于既有转职试稿与 procedural-lua-headless 的 Start/pcall/Exit 模板。
-- 默认审核111/112；-seal-review审核101/102，-first-review审核103–110。
-- 两个-review模式均禁止安装；显式-install仍只替换111/112。
-- UrhoXRuntime _proc/generate_advancement_trials.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless -seal-review
local ROOT = "/workspace/assets/image/职业图标/"
local OUT = "/workspace/.git/advancement-icons-validation/generated/"
local SEAL_OUT = "/workspace/assets/image/审核_职业转职_20261006_封门人/"
local FIRST_OUT = "/workspace/assets/image/审核_职业转职_20261006_其余一转/"
local BACKUP = "/workspace/.git/advancement-icons-validation/originals/"
local SIZE, SCALE = 560, 2
local CENTER = 139.5
local DARK = { 14, 12, 10 }
local GOLD = { 161, 121, 64 }
local BONE = { 220, 206, 170 }
local SHADE = { 77, 55, 30 }
local ORDER = { 111, 112 }
local install, sealReview, firstReview = false, false, false
for _, argument in ipairs(GetArguments()) do
    if argument == "-install" then install = true end
    if argument == "-seal-review" then sealReview = true end
    if argument == "-first-review" then firstReview = true end
end
if sealReview then ORDER = { 101, 102 } end
if firstReview then ORDER = { 103, 104, 105, 106, 107, 108, 109, 110 } end
---@type table<number, fun(d: table, branchId: integer)>
local reviewDrawers = {}
---@type Image[]
local images = {}

local function clamp(v, low, high) return math.max(low, math.min(high, v)) end
local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

---@param branchId integer
---@return Image
local function render(branchId)
    local red, green, blue, alpha = {}, {}, {}, {}
    -- 整张画布从透明开始，既不读旧PNG，也不回填旧外环。
    for i = 1, SIZE * SIZE do
        red[i], green[i], blue[i], alpha[i] = 0, 0, 0, 0
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

    -- 两分支共用十二面暗铁底板：外缘旧铜倒角、内沿骨白细光，主体留足负空间。
    -- 不复用旧图像；底板和圣铃使用同一套 DARK/GOLD/BONE/SHADE 材质。
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
    -- 四枚小铜钉仅锚定底板，不添与职业无关的徽记。
    for _, p in ipairs({ { 140, 21 }, { 259, 140 }, { 140, 259 }, { 21, 140 } }) do
        ellipse(p[1], p[2], 4, 4, DARK)
        ellipse(p[1], p[2] - 0.6, 2.7, 2.7, GOLD, SHADE)
        line(p[1] - 1.5, p[2] - 1.2, p[1] + 0.8, p[2] - 1.2, 0.9, BONE, 0.6)
    end

    local drawReview = reviewDrawers[branchId]
    if drawReview then
        drawReview({ polygon = polygon, line = line, stroke = stroke, ellipse = ellipse,
            arc = arc, curve = curve, emblem = emblem, star = star,
            DARK = DARK, GOLD = GOLD, BONE = BONE, SHADE = SHADE }, branchId)
    elseif branchId == 101 or branchId == 102 then
        -- 封门人共享门盾轮廓：双层旧铜门框、骨白铁甲、暗色负空间。
        -- 门闩以横向锁杆蓄住伤害；闸门以抬起的栅齿和侧向泄压区分。
        local frame = { { 79, 218 }, { 79, 88 }, { 88, 68 }, { 111, 53 },
            { 168, 53 }, { 191, 68 }, { 200, 88 }, { 200, 218 },
            { 184, 231 }, { 95, 231 } }
        emblem(frame, GOLD, SHADE)
        local inner = { { 92, 214 }, { 92, 91 }, { 98, 78 }, { 116, 66 },
            { 163, 66 }, { 181, 78 }, { 187, 91 }, { 187, 214 },
            { 177, 219 }, { 102, 219 } }
        polygon(inner, { 47, 40, 29 }, DARK)
        stroke(inner, 2, DARK, true)
        stroke({ { 82, 214 }, { 82, 88 }, { 91, 70 }, { 113, 56 }, { 168, 56 } }, 2, BONE, false, 0.75)
        stroke({ { 198, 90 }, { 198, 215 }, { 183, 228 }, { 99, 228 } }, 2, SHADE, false)
        for _, x in ipairs({ 85, 194 }) do
            for _, y in ipairs({ 100, 153, 207 }) do
                ellipse(x, y, 4.1, 4.1, DARK)
                ellipse(x - 0.5, y - 0.6, 2.6, 2.6, BONE, GOLD)
            end
        end
        emblem({ { 126, 59 }, { 153, 59 }, { 159, 66 }, { 153, 73 },
            { 126, 73 }, { 120, 66 } }, GOLD, SHADE)
        line(132, 65, 147, 65, 2, BONE)

        if branchId == 101 then
            -- 闭合双扉与加厚横闩表达更大的储伤容量；下方分流箭强调转敌。
            local left = { { 98, 90 }, { 117, 77 }, { 135, 77 }, { 135, 205 }, { 99, 205 } }
            local right = { { 144, 77 }, { 162, 77 }, { 180, 90 }, { 180, 205 }, { 144, 205 } }
            emblem(left, BONE, GOLD)
            emblem(right, BONE, GOLD)
            polygon({ { 103, 96 }, { 122, 84 }, { 131, 84 }, { 131, 198 }, { 104, 198 } }, GOLD, SHADE)
            polygon({ { 148, 84 }, { 158, 84 }, { 175, 95 }, { 175, 198 }, { 148, 198 } }, GOLD, SHADE)
            line(139.5, 80, 139.5, 202, 6.5, DARK)
            line(137, 82, 137, 200, 1.3, BONE, 0.75)
            for _, y in ipairs({ 104, 182 }) do
                for _, side in ipairs({ -1, 1 }) do
                    local x = 139.5 + side * 26
                    emblem({ { x - 11, y - 7 }, { x + 11, y - 7 },
                        { x + 11, y + 7 }, { x - 11, y + 7 } }, BONE, GOLD)
                    line(x - 7, y, x + 7, y, 1.8, SHADE)
                    ellipse(x - 6, y, 2.3, 2.3, DARK)
                    ellipse(x + 6, y, 2.3, 2.3, DARK)
                end
            end
            emblem({ { 94, 125 }, { 185, 125 }, { 190, 131 }, { 190, 151 },
                { 185, 157 }, { 94, 157 }, { 89, 151 }, { 89, 131 } }, BONE, GOLD)
            polygon({ { 99, 145 }, { 181, 145 }, { 185, 151 }, { 95, 151 } }, SHADE)
            line(96, 129, 182, 129, 2.4, BONE)
            emblem({ { 130, 119 }, { 149, 119 }, { 149, 163 }, { 130, 163 } }, GOLD, SHADE)
            ellipse(139.5, 134, 3.3, 3.3, DARK)
            ellipse(139.5, 150, 3.3, 3.3, DARK)
            -- 一个蓄压核心分成两支向外箭，避免误用圣铃/治疗星纹。
            polygon({ { 139.5, 180 }, { 146, 188 }, { 139.5, 196 }, { 133, 188 } }, BONE, GOLD)
            for _, side in ipairs({ -1, 1 }) do
                local x = 139.5 + side * 47
                stroke({ { 139.5, 194 }, { 139.5, 213 }, { x, 213 } }, 6.5, DARK, false)
                stroke({ { 139.5, 194 }, { 139.5, 213 }, { x, 213 } }, 2.8, BONE, false)
                polygon({ { x + side * 9, 213 }, { x - side * 1, 207 },
                    { x - side * 1, 219 } }, BONE, GOLD)
            end
        else
            -- 半提起的铁闸露出明确门洞，栅齿与侧排气口表达满载泄压。
            polygon({ { 99, 94 }, { 117, 80 }, { 163, 80 }, { 180, 94 },
                { 180, 210 }, { 99, 210 } }, DARK)
            polygon({ { 105, 174 }, { 175, 174 }, { 178, 209 }, { 101, 209 } }, { 24, 22, 18 }, DARK)
            for _, x in ipairs({ 107, 123, 140, 157, 173 }) do
                emblem({ { x - 4, 88 }, { x + 4, 88 }, { x + 4, 151 },
                    { x, 162 }, { x - 4, 151 } }, BONE, GOLD)
                line(x - 1.6, 92, x - 1.6, 147, 1.3, BONE, 0.8)
            end
            for _, y in ipairs({ 107, 133 }) do
                emblem({ { 99, y - 4 }, { 180, y - 4 }, { 180, y + 4 }, { 99, y + 4 } }, GOLD, SHADE)
                line(102, y - 2, 176, y - 2, 1.5, BONE, 0.7)
            end
            -- 内向短矛头表示强制引敌，底部向外泄压与门闩分流形态不同。
            for _, side in ipairs({ -1, 1 }) do
                local x = 139.5 + side * 80
                for _, y in ipairs({ 116, 145, 174 }) do
                    line(x + side * 11, y, x - side * 7, y, 6, DARK)
                    line(x + side * 11, y, x - side * 7, y, 2.6, GOLD)
                    emblem({ { x - side * 14, y }, { x - side * 3, y - 7 },
                        { x - side * 3, y + 7 } }, BONE, GOLD)
                end
                local relief = { { 139.5 + side * 31, 187 } }
                curve(relief, 139.5 + side * 39, 180, 139.5 + side * 47, 183,
                    139.5 + side * 51, 198)
                stroke(relief, 7, DARK, false)
                stroke(relief, 2.6, BONE, false)
                polygon({ { 139.5 + side * 55, 201 }, { 139.5 + side * 49, 211 },
                    { 139.5 + side * 46, 198 } }, BONE, GOLD)
            end
            -- 空门洞中的暗铜拱线保留深度，不再加十字、皇冠或其他职业符号。
            stroke({ { 117, 209 }, { 117, 177 }, { 125, 170 }, { 154, 170 },
                { 162, 177 }, { 162, 209 } }, 1.8, GOLD, false, 0.45)
            line(109, 210, 170, 210, 3, GOLD)
            line(108, 214, 171, 214, 1.5, BONE, 0.7)
        end
    elseif branchId == 111 then
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

    if branchId == 111 or branchId == 112 then
    -- 两个司仪分支共用骨白旧铜圣铃；不是换色图，以附属结构区分机制。
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
    end

    local image = Image()
    images[#images + 1] = image
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
---@return Image
local function reduce(master)
    local small = Image()
    images[#images + 1] = small
    assert(small:SetSize(280, 280, 4), "创建280×280转职图失败")
    -- 全画布预乘 Alpha 平均；透明外缘不会混入黑边，也没有旧框回填分支。
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
        -- 审核模式没有安装权限，即便误传-install也在任何写盘前拒绝。
        assert(not (sealReview and firstReview), "只能选择一种审核运行模式")
        assert(not ((sealReview or firstReview) and install), "审核模式只生成审核图，禁止同时安装")
        -- 审核模块的加载也纳入pcall；缺模块时失败日志和Image清理仍会收尾。
        if firstReview then
            local spoil = require("_proc.advancement.ReviewSpoil")
            local rift = require("_proc.advancement.ReviewRift")
            local echo = require("_proc.advancement.ReviewEcho")
            local mask = require("_proc.advancement.ReviewMask")
            reviewDrawers = { [103] = spoil, [104] = spoil, [105] = rift, [106] = rift,
                [107] = echo, [108] = echo, [109] = mask, [110] = mask }
        end
        local output = firstReview and FIRST_OUT or (sealReview and SEAL_OUT or OUT)
        assert(fileSystem:CreateDir(output), "创建转职审核目录失败")
        if install then assert(fileSystem:CreateDir(BACKUP), "创建转职原图备份目录失败") end
        -- 两图都成功生成后才进入安装阶段；审核运行绝不触碰正式图。
        for _, branchId in ipairs(ORDER) do
            local name = "UI_icon_ZY_" .. branchId .. ".png"
            print("[adv-trial] " .. branchId .. " 开始全底板和主体程序绘制")
            local master = render(branchId)
            local small = reduce(master)
            assert(master:SavePNG(output .. "UI_icon_ZY_" .. branchId .. "_560.png"), "保存母图失败")
            assert(small:SavePNG(output .. name), "保存审核图失败")
            print("[adv-trial] " .. branchId .. " 280×280 RGBA审核PNG已保存")
        end
        if install then
            for _, branchId in ipairs(ORDER) do
                local name = "UI_icon_ZY_" .. branchId .. ".png"
                if not fileSystem:FileExists(BACKUP .. name) then
                    assert(fileSystem:Copy(ROOT .. name, BACKUP .. name), "备份转职原图失败：" .. name)
                end
            end
            for _, branchId in ipairs(ORDER) do
                local name = "UI_icon_ZY_" .. branchId .. ".png"
                assert(fileSystem:Copy(OUT .. name, ROOT .. name), "安装转职图失败：" .. name)
                print("[adv-trial] 已安装 " .. name .. "，原.meta保持不变")
            end
        end
        print("[adv-trial] ALL PASS：" .. #ORDER .. "枚"
            .. (firstReview and "其余一转" or (sealReview and "封门人一转" or "司仪一转"))
            .. "，模式=" .. (install and "安装" or "仅审核"))
    end)
    -- 成功与失败都立即释放所有已创建Image，退出不依赖GC。
    for _, image in ipairs(images) do image:Dispose() end
    images = {}
    if not ok then log:Write(LOG_ERROR, "[adv-trial] " .. tostring(err)) end
    engine:Exit()
end
