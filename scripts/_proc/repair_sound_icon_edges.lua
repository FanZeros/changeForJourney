-- 音量按钮补边：由未截断圆弧拟合外缘，仅补四向缺失的金属圆环。
-- 运行：UrhoXRuntime _proc/repair_sound_icon_edges.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
-- 参考 proc_seambar.lua 的 CPU 像素修复范式；不改变喇叭图案、画布尺寸或 .meta。
local ROOT = "/workspace/assets/image/通用图标/"
local BACKUP = "/workspace/assets/backup/通用图标/音量按钮原图备份/"
local OUTPUT = ROOT .. "音量按钮修复/"
local NAMES = { "UI_ICON_YX_KQ.png", "UI_ICON_YX_GB.png" }
local CENTER_X, CENTER_Y = 66.04, 70.08
local RADIUS_X, RADIUS_Y = 58.25, 59.42
local SAMPLES = 4

local function clamp(v, low, high) return math.max(low, math.min(high, v)) end

-- 显式按预乘透明度插值，透明黑像素不会污染采样出的金色。
---@param image Image
---@return Color
local function sample(image, x, y)
    local x0, y0 = math.floor(x), math.floor(y)
    local tx, ty = x - x0, y - y0
    local red, green, blue, alpha = 0, 0, 0, 0
    for iy = 0, 1 do
        for ix = 0, 1 do
            local c = image:GetPixel(clamp(x0 + ix, 0, image.width - 1), clamp(y0 + iy, 0, image.height - 1))
            local weight = (ix == 0 and 1 - tx or tx) * (iy == 0 and 1 - ty or ty) * c.a
            red, green, blue, alpha = red + c.r * weight, green + c.g * weight, blue + c.b * weight, alpha + weight
        end
    end
    if alpha <= 0 then return Color(0, 0, 0, 0) end
    return Color(red / alpha, green / alpha, blue / alpha, alpha)
end

-- 同半径相邻完整弧段的颜色沿角度延续，保留原按钮的铜金色和倒角层次。
---@param image Image
---@return Color
local function rimColor(image, angle, radius)
    local red, green, blue, weights = 0, 0, 0, 0
    for _, side in ipairs({ -1, 1 }) do
        for step = 1, 18 do
            local offset = step * 0.055
            local a = angle + side * offset
            local r = math.min(radius, 0.994)
            local sx = CENTER_X + math.cos(a) * RADIUS_X * r
            local sy = CENTER_Y + math.sin(a) * RADIUS_Y * r
            -- 远离矩形截断边界，避免把平口处损坏的颜色拿来延续。
            if sx >= 12 and sx <= 120 and sy >= 15 and sy <= 125 then
                local c = sample(image, sx, sy)
                if c.a > 0.12 then
                    local weight = c.a / (offset * offset + 0.02)
                    red, green, blue, weights = red + c.r * weight, green + c.g * weight,
                        blue + c.b * weight, weights + weight
                    break
                end
            end
        end
    end
    assert(weights > 0, "无法从完整圆弧获取边框颜色")
    return Color(red / weights, green / weights, blue / weights, 1)
end

---@param source Image
---@return Image
local function repair(source)
    local image = Image()
    assert(image:SetSize(source.width, source.height, 4), "创建修复画布失败")
    local changed = 0
    for y = 0, source.height - 1 do
        for x = 0, source.width - 1 do
            local original = source:GetPixel(x, y)
            local c = original
            -- 仅操作旧矩形平口附近，内部原像素完全保留。
            local nearCut = x <= 11 or x >= 121 or y <= 14 or y >= 126
            if nearCut and original.a < 1 then
                local red, green, blue, alpha = 0, 0, 0, 0
                for iy = 0, SAMPLES - 1 do
                    for ix = 0, SAMPLES - 1 do
                        local px = x - 0.5 + (ix + 0.5) / SAMPLES
                        local py = y - 0.5 + (iy + 0.5) / SAMPLES
                        local dx, dy = (px - CENTER_X) / RADIUS_X, (py - CENTER_Y) / RADIUS_Y
                        local radius = math.sqrt(dx * dx + dy * dy)
                        if radius <= 1 then
                            local metal = rimColor(source, math.atan(dy, dx), radius)
                            red, green, blue, alpha = red + metal.r, green + metal.g, blue + metal.b, alpha + 1
                        end
                    end
                end
                if alpha > 0 then
                    local coverage = alpha / (SAMPLES * SAMPLES)
                    local added = coverage * (1 - original.a)
                    local combined = original.a + added
                    c = Color((original.r * original.a + red / alpha * added) / combined,
                        (original.g * original.a + green / alpha * added) / combined,
                        (original.b * original.a + blue / alpha * added) / combined, combined)
                    changed = changed + 1
                end
            end
            image:SetPixel(x, y, c)
        end
    end
    print(string.format("[sound-edge] 补齐 %d 个边缘像素，画布 %d×%d", changed, source.width, source.height))
    return image
end

function Start()
    local ok, err = pcall(function()
        assert(fileSystem:CreateDir(BACKUP), "创建原图备份目录失败")
        assert(fileSystem:CreateDir(OUTPUT), "创建修复目录失败")
        -- 先备份全部源文件；重跑始终从原图读取，避免累计补边。
        for _, name in ipairs(NAMES) do
            if not fileSystem:FileExists(BACKUP .. name) then
                assert(fileSystem:Copy(ROOT .. name, BACKUP .. name), "备份失败：" .. name)
            end
        end
        for _, name in ipairs(NAMES) do
            local source = Image()
            assert(source:Load(BACKUP .. name), "读取原图失败：" .. name)
            assert(source.width == 130 and source.height == 144, "原图尺寸不符：" .. name)
            local fixed = repair(source)
            assert(fixed:SavePNG(OUTPUT .. name), "保存修复图失败：" .. name)
            fixed:Dispose(); source:Dispose()
            print("[sound-edge] 已修复：" .. name)
        end
        for _, name in ipairs(NAMES) do
            assert(fileSystem:Copy(OUTPUT .. name, ROOT .. name), "替换失败：" .. name)
        end
        print("[sound-edge] 两张原路径已更新，.meta 未修改，画布四周仍保留透明安全区")
    end)
    if not ok then log:Write(LOG_ERROR, "[sound-edge] " .. tostring(err)) end
    engine:Exit()
end
