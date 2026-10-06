-- 暗黑词缀品级：独立字母轮廓、金属倒角和轻微磨损，完全在 CPU 上生成。
-- 运行：UrhoXRuntime _proc/generate_rarity_icons.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
-- 沿用 generate_set_icons.lua 的 Image 像素烘焙范式，不依赖字体、网络或 NanoVG。
local ROOT = "/workspace/assets/image/通用图标/"
local ARCHIVE = "/workspace/assets/backup/通用图标/稀有度原图备份/"
local EXPORT = ROOT .. "暗黑稀有度/"
local SIZE, SCALE = 352, 8
local ORDER = { "S", "A", "B", "C", "D" }
local PALETTE = {
    S = { 216, 158, 46 }, A = { 138, 78, 194 }, B = { 62, 126, 194 },
    C = { 95, 158, 62 }, D = { 138, 133, 120 },
}

local function clamp(v, low, high) return math.max(low, math.min(high, v)) end
local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- 自绘古典锐角衬线字形。闭合轮廓采用奇偶填充，内孔保持真正透明。
local function path(x, y) return { { x, y } } end
local function point(p, x, y) p[#p + 1] = { x, y } end
local function curve(p, x1, y1, x2, y2, x3, y3)
    local from = p[#p]
    for i = 1, 24 do
        local t, u = i / 24, 1 - i / 24
        point(p, u ^ 3 * from[1] + 3 * u ^ 2 * t * x1 + 3 * u * t ^ 2 * x2 + t ^ 3 * x3,
            u ^ 3 * from[2] + 3 * u ^ 2 * t * y1 + 3 * u * t ^ 2 * y2 + t ^ 3 * y3)
    end
end

local function contours(letter)
    if letter == "A" then
        return {
            { { 22, 5.4 }, { 24.2, 6.5 }, { 34.2, 34.4 }, { 38, 36.9 }, { 25.2, 36.9 },
              { 28.1, 34.5 }, { 25.9, 28 }, { 15.6, 28 }, { 13.4, 34.5 }, { 17, 36.9 },
              { 6.4, 36.9 }, { 10.1, 34.4 }, { 20.2, 7.2 } },
            { { 20.8, 13.4 }, { 16.7, 24.7 }, { 24.8, 24.7 } },
        }
    elseif letter == "S" then
        local p = path(34.4, 5.8)
        point(p, 34.4, 16.1); point(p, 31.5, 13.4)
        curve(p, 29.4, 9.3, 26.4, 8.4, 22.6, 8.4)
        curve(p, 18.2, 8.4, 15.4, 10.5, 15.4, 13.6)
        curve(p, 15.4, 17, 19.2, 18, 24.4, 20)
        curve(p, 31.6, 22.8, 35.6, 24.5, 35.6, 29.9)
        curve(p, 35.6, 35.3, 30.2, 38, 23.4, 38)
        curve(p, 18.8, 38, 15.6, 36.8, 12.9, 35.4)
        point(p, 9.4, 38.1); point(p, 9.4, 25.9); point(p, 12.5, 28.7)
        curve(p, 15.1, 33.3, 18.6, 35, 23, 35)
        curve(p, 27.2, 35, 29.2, 33, 29.2, 30.4)
        curve(p, 29.2, 27.4, 25.8, 26.1, 20.3, 24)
        curve(p, 12.8, 21.3, 9.4, 18.9, 9.4, 13.7)
        curve(p, 9.4, 8.3, 15, 5.3, 21.7, 5.3)
        curve(p, 26, 5.3, 29.3, 6.5, 31.4, 7.7)
        point(p, 34.4, 5.8)
        return { p }
    elseif letter == "B" then
        local p = path(7.7, 6.1)
        point(p, 24.5, 6.1)
        curve(p, 31.8, 6.1, 35.1, 9.2, 35.1, 13.9)
        curve(p, 35.1, 17.5, 32.5, 19.7, 29, 20.6)
        curve(p, 33.9, 21.5, 36.4, 24, 36.4, 28.7)
        curve(p, 36.4, 34.5, 32, 37, 24.9, 37)
        point(p, 7.7, 37); point(p, 11.6, 34.5); point(p, 11.6, 8.6)
        local h1 = path(18, 9.2)
        point(h1, 22.4, 9.2)
        curve(h1, 26.7, 9.2, 28.9, 10.7, 28.9, 14.4)
        curve(h1, 28.9, 17.8, 26.5, 19.2, 22.4, 19.2)
        point(h1, 18, 19.2)
        local h2 = path(18, 22.3)
        point(h2, 23, 22.3)
        curve(h2, 27.7, 22.3, 30, 24.5, 30, 28.8)
        curve(h2, 30, 32.6, 27.7, 33.9, 23, 33.9)
        point(h2, 18, 33.9)
        return { p, h1, h2 }
    elseif letter == "C" then
        local p = path(34.8, 5.9)
        point(p, 34.8, 17); point(p, 31.8, 14)
        curve(p, 30, 9.9, 27.8, 8.5, 23.7, 8.5)
        curve(p, 17.2, 8.5, 14.1, 13.2, 14.1, 21.5)
        curve(p, 14.1, 29.8, 17.5, 34.8, 24, 34.8)
        curve(p, 28, 34.8, 30.7, 32.6, 33, 28.8)
        point(p, 35.3, 29.7)
        curve(p, 32.6, 35.4, 28.7, 38, 22.4, 38)
        curve(p, 12.9, 38, 7, 31.9, 7, 21.7)
        curve(p, 7, 11.8, 13.4, 5.3, 22.7, 5.3)
        curve(p, 27.1, 5.3, 29.8, 6.6, 31.7, 7.8)
        point(p, 34.8, 5.9)
        return { p }
    end
    local p = path(7.5, 6.1)
    point(p, 22.7, 6.1)
    curve(p, 32.7, 6.1, 37, 12.3, 37, 21.4)
    curve(p, 37, 31.5, 32.3, 37, 22.5, 37)
    point(p, 7.5, 37); point(p, 11.5, 34.5); point(p, 11.5, 8.6)
    local h = path(18, 9.3)
    point(h, 21.6, 9.3)
    curve(h, 28.4, 9.3, 30.3, 14.6, 30.3, 21.5)
    curve(h, 30.3, 29.4, 28.1, 33.8, 21.6, 33.8)
    point(h, 18, 33.8)
    return { p, h }
end

local function rasterMask(shapes)
    local mask = {}
    -- 扫描线排序后成对填充，避免逐像素遍历全部贝塞尔线段。
    for y = 0, SIZE - 1 do
        local py, intersections = (y + 0.5) / SCALE, {}
        for _, polygon in ipairs(shapes) do
            local last = polygon[#polygon]
            for _, p in ipairs(polygon) do
                if (p[2] > py) ~= (last[2] > py) then
                    intersections[#intersections + 1] = last[1] + (py - last[2]) * (p[1] - last[1]) / (p[2] - last[2])
                end
                last = p
            end
        end
        table.sort(intersections)
        for j = 1, #intersections - 1, 2 do
            local first = math.max(0, math.ceil(intersections[j] * SCALE - 0.5))
            local last = math.min(SIZE - 1, math.floor(intersections[j + 1] * SCALE - 0.5))
            for x = first, last do mask[y * SIZE + x + 1] = true end
        end
    end
    return mask
end

local function distance(mask, target)
    local values = {}
    for i = 1, SIZE * SIZE do values[i] = (mask[i] == true) == target and 0 or 10000 end
    local diagonal = math.sqrt(2)
    for y = 0, SIZE - 1 do
        for x = 0, SIZE - 1 do
            local i = y * SIZE + x + 1
            local d = values[i]
            if x > 0 then d = math.min(d, values[i - 1] + 1) end
            if y > 0 then
                d = math.min(d, values[i - SIZE] + 1)
                if x > 0 then d = math.min(d, values[i - SIZE - 1] + diagonal) end
                if x < SIZE - 1 then d = math.min(d, values[i - SIZE + 1] + diagonal) end
            end
            values[i] = d
        end
    end
    for y = SIZE - 1, 0, -1 do
        for x = SIZE - 1, 0, -1 do
            local i = y * SIZE + x + 1
            local d = values[i]
            if x < SIZE - 1 then d = math.min(d, values[i + 1] + 1) end
            if y < SIZE - 1 then
                d = math.min(d, values[i + SIZE] + 1)
                if x > 0 then d = math.min(d, values[i + SIZE - 1] + diagonal) end
                if x < SIZE - 1 then d = math.min(d, values[i + SIZE + 1] + diagonal) end
            end
            values[i] = d
        end
    end
    return values
end

local function render(letter)
    local base = PALETTE[letter]
    local light = mix(base, { 244, 226, 183 }, 0.43)
    local shade = mix(base, { 24, 20, 19 }, 0.60)
    local rim = mix(base, { 36, 30, 22 }, 0.70)
    local mask = rasterMask(contours(letter))
    local inner, outer = distance(mask, false), distance(mask, true)
    local image = Image()
    assert(image:SetSize(SIZE, SIZE, 4), "创建图标失败：" .. letter)
    image:Clear(Color(0, 0, 0, 0))
    for y = 1, SIZE - 2 do
        for x = 1, SIZE - 2 do
            local i = y * SIZE + x + 1
            local px, py = (x + 0.5) / SCALE, (y + 0.5) / SCALE
            local rgb, alpha = { 0, 0, 0 }, 0
            if mask[i] then
                local t = clamp((py - 6) / 32, 0, 1)
                -- 不连续反射带模拟锻造金属，避免糖果色均匀渐变。
                local reflection = 0.32 * math.exp(-((t - 0.16) / 0.12) ^ 2)
                    - 0.22 * math.exp(-((t - 0.53) / 0.10) ^ 2)
                    + 0.10 * math.exp(-((t - 0.79) / 0.10) ^ 2)
                local seed = math.sin(math.floor(px * 5) * 12.9898 + math.floor(py * 5) * 78.233) * 43758.5453
                local grain = seed - math.floor(seed) - 0.5
                local mottled = math.sin(px * 1.15 + py * 0.47) * math.sin(py * 0.71 - px * 0.23)
                local factor = 1.06 - t * 0.24 + reflection + grain * 0.065 + mottled * 0.028
                rgb = { base[1] * factor, base[2] * factor, base[3] * factor }
                local bevel = clamp(1 - inner[i] / (SCALE * 0.78), 0, 1)
                if bevel > 0 then
                    local dx = inner[i + 1] - inner[i - 1]
                    local dy = inner[i + SIZE] - inner[i - SIZE]
                    local length = math.sqrt(dx * dx + dy * dy)
                    local lighting = length > 0 and (dx * 0.63 + dy * 0.78) / length or 0
                    local edge = lighting > 0 and mix(base, light, lighting) or mix(base, shade, -lighting)
                    rgb = mix(rgb, edge, bevel)
                end
                -- 两处浅划痕，仅改变颜色，不削穿字母轮廓。
                local scratch = math.abs(py - (12.8 + px * 0.18)) < 0.075 and px > 17 and px < 27
                    or math.abs(py - (32.4 - px * 0.14)) < 0.065 and px > 11 and px < 23
                if scratch and inner[i] > SCALE * 0.75 then rgb = mix(rgb, shade, 0.42) end
                alpha = 1
            elseif outer[i] < SCALE * 0.92 then
                local edge = outer[i] / SCALE
                rgb = edge < 0.44 and rim or { 10, 8, 6 }
                alpha = clamp((0.92 - edge) / 0.22, 0, 1)
            end
            if alpha > 0 then
                image:SetPixel(x, y, Color(clamp(rgb[1], 0, 255) / 255,
                    clamp(rgb[2], 0, 255) / 255, clamp(rgb[3], 0, 255) / 255, alpha))
            end
        end
    end
    return image
end

-- 显式预乘再平均、还原 RGB，避免透明像素缩放导致黑边。
local function reduce(source, size)
    local image = Image()
    assert(image:SetSize(size, size, 4), "创建缩略图失败")
    local step = SIZE // size
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local r, g, b, a = 0, 0, 0, 0
            for sy = 0, step - 1 do
                for sx = 0, step - 1 do
                    local c = source:GetPixel(x * step + sx, y * step + sy)
                    r, g, b, a = r + c.r * c.a, g + c.g * c.a, b + c.b * c.a, a + c.a
                end
            end
            if a > 0 then image:SetPixel(x, y, Color(r / a, g / a, b / a, a / (step * step)))
            else image:SetPixel(x, y, Color(0, 0, 0, 0)) end
        end
    end
    return image
end

function Start()
    local ok, err = pcall(function()
        assert(fileSystem:CreateDir(ARCHIVE), "创建备份目录失败")
        assert(fileSystem:CreateDir(EXPORT), "创建导出目录失败")
        -- 先保存全部原图，再生成所有新图；最后统一替换，不触碰 .meta。
        for _, letter in ipairs(ORDER) do
            local name = "ICON_CZBZ_" .. letter .. ".png"
            local original = cache:GetResource("Image", "image/通用图标/" .. name)
            assert(original, "无法读取原图：" .. name)
            assert(original.width == 44 and original.height == 44, "原图尺寸不符合44×44约定")
            if not fileSystem:FileExists(ARCHIVE .. name) then
                assert(original:SavePNG(ARCHIVE .. name), "保存原图备份失败")
            end
            print("[rarity] 原图已确认：" .. name .. " 44×44")
        end
        for _, letter in ipairs(ORDER) do
            local name = "ICON_CZBZ_" .. letter .. ".png"
            local master = render(letter)
            assert(master:SavePNG(EXPORT .. "ICON_CZBZ_" .. letter .. "_352.png"), "保存高清图失败")
            local small = reduce(master, 44)
            assert(small:SavePNG(EXPORT .. name), "保存44×44图失败")
            master:Dispose(); small:Dispose()
            print("[rarity] 已生成：" .. letter .. "，透明PNG 44×44 / 352×352")
        end
        for _, letter in ipairs(ORDER) do
            local name = "ICON_CZBZ_" .. letter .. ".png"
            assert(fileSystem:Copy(EXPORT .. name, ROOT .. name), "替换图标失败：" .. name)
        end
        print("[rarity] 五个图标已替换，原文件名和 .meta 保持不变")
    end)
    if not ok then log:Write(LOG_ERROR, "[rarity] " .. tostring(err)) end
    engine:Exit()
end
