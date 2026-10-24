-- 三个小控件的确定性 CPU 烘焙；不加载游戏、存档或 GPU。
-- 沿用程序化脚本 Start / pcall / Exit 范式，4×4 子像素采样保留透明边缘。
-- 用 -output_dir=<已有目录> 指定输出目录；不直接覆盖正式素材。
local SAMPLES = 4

---@param value number
---@return number
local function clamp(value)
    return math.max(0, math.min(1, value))
end

---@param a number[]
---@param b number[]
---@param t number
---@return number[]
local function mix(a, b, t)
    local u = clamp(t)
    return { a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u,
        a[3] + (b[3] - a[3]) * u }
end

---@param vertices number[][]
---@param x number
---@param y number
---@return boolean
local function inside(vertices, x, y)
    local hit = false
    local j = #vertices
    for i = 1, #vertices do
        local a, b = vertices[i], vertices[j]
        if (a[2] > y) ~= (b[2] > y)
            and x < (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1] then
            hit = not hit
        end
        j = i
    end
    return hit
end

---@param cx number
---@param cy number
---@param rx number
---@param ry number
---@return number[][]
local function diamond(cx, cy, rx, ry)
    return { { cx, cy - ry }, { cx + rx, cy }, { cx, cy + ry }, { cx - rx, cy } }
end

---@param x number
---@param y number
---@param left number
---@param top number
---@param width number
---@param height number
---@param radius number
---@return boolean
local function rounded(x, y, left, top, width, height, radius)
    local dx = math.max(left + radius - x, 0, x - (left + width - radius))
    local dy = math.max(top + radius - y, 0, y - (top + height - radius))
    return x >= left and x <= left + width and y >= top and y <= top + height
        and dx * dx + dy * dy <= radius * radius
end

local IRON = { 0.115, 0.125, 0.135 }
local SHADOW = { 0.032, 0.028, 0.026 }
local BRONZE = { 0.48, 0.37, 0.23 }
local BONE = { 0.86, 0.79, 0.62 }

---@param color number[]
---@param x number
---@param y number
---@return number[]
local function brushed(color, x, y)
    local grain = 0.008 * math.sin(y * 5.7 + x * 0.31) + 0.004 * math.sin(x * 13.1 + y * 9.3)
    return { clamp(color[1] + grain), clamp(color[2] + grain), clamp(color[3] + grain) }
end

---@param x number
---@param y number
---@return number[], number
local function awakening(x, y)
    local cx, cy = 49, 63.5
    -- 外轮廓留出安全透明边，中心保持镂空，不遮挡觉醒切片。
    if not inside(diamond(cx, cy + 1, 43, 60), x, y) then return SHADOW, 0 end
    if not inside(diamond(cx, cy, 41, 58), x, y) then return SHADOW, 0.75 end
    local light = clamp(0.65 - (x - cx) * 0.006 - (y - cy) * 0.005)
    if not inside(diamond(cx, cy, 39, 55), x, y) then
        return mix(BRONZE, BONE, light), 1
    end
    if not inside(diamond(cx, cy, 34, 48), x, y) then
        return brushed(mix(IRON, BRONZE, light * 0.4), x, y), 1
    end
    if not inside(diamond(cx, cy, 31, 44), x, y) then
        return mix(SHADOW, BONE, light * 0.75), 1
    end
    return SHADOW, 0
end

---@param x number
---@param y number
---@return number[], number
local function thumb(x, y)
    if not rounded(x, y, 1, 2, 68, 27, 13.5) then return SHADOW, 0 end
    if not rounded(x, y, 2, 2, 66, 25, 12.5) then return SHADOW, 0.9 end
    local light = clamp(1 - (y - 3) / 25)
    if not rounded(x, y, 3.5, 3.5, 63, 22, 11) then
        return mix(SHADOW, BONE, light * 0.85), 1
    end
    if not rounded(x, y, 5, 5, 60, 19, 9.5) then
        return mix(SHADOW, BRONZE, light), 1
    end
    local face = brushed(mix(SHADOW, IRON, light), x, y)
    -- 三条握持刻痕不超过面内边界，缩小后仍可读。
    for _, gx in ipairs({ 28, 35, 42 }) do
        if rounded(x, y, gx - 1.1, 9, 2.2, 11, 1.1) then
            return mix(BRONZE, BONE, light * 0.6), 1
        end
        if rounded(x, y, gx + 0.5, 10, 1.3, 11, 0.65) then return SHADOW, 1 end
    end
    return face, 1
end

local DOWN_OUTLINE = { { 14, 6 }, { 26, 6 }, { 26, 19 }, { 32, 19 },
    { 20, 34 }, { 8, 19 }, { 14, 19 } }
local DOWN_FACE = { { 16, 8 }, { 24, 8 }, { 24, 21 }, { 28, 21 },
    { 20, 31 }, { 12, 21 }, { 16, 21 } }

---@param x number
---@param y number
---@return number[], number
local function down(x, y)
    if not inside(diamond(20, 20, 19, 19), x, y) then return SHADOW, 0 end
    local light = clamp(0.85 - x * 0.008 - y * 0.012)
    local color = SHADOW
    if not inside(diamond(20, 20, 17.5, 17.5), x, y) then
        color = mix(BRONZE, BONE, light * 0.72)
    elseif not inside(diamond(20, 20, 15.5, 15.5), x, y) then
        color = mix(SHADOW, BRONZE, light * 0.6)
    else
        color = brushed(mix(SHADOW, IRON, light * 0.8), x, y)
    end
    if inside(DOWN_OUTLINE, x, y) then color = mix(SHADOW, { 0.55, 0.25, 0.16 }, light) end
    if inside(DOWN_FACE, x, y) then
        color = brushed(mix({ 0.38, 0.065, 0.055 }, { 0.88, 0.25, 0.17 }, light), x, y)
        if x >= 19 and x <= 20.5 and y >= 9 and y <= 26 then
            color = mix(color, { 0.92, 0.44, 0.3 }, 0.5)
        end
    end
    return color, 1
end

---@param width integer
---@param height integer
---@param shader fun(x:number,y:number):number[],number
---@param path string
local function bake(width, height, shader, path)
    local image = Image()
    assert(image:SetSize(width, height, 4), "Image:SetSize 失败")
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local r, g, b, alpha = 0, 0, 0, 0
            for sy = 0, SAMPLES - 1 do
                for sx = 0, SAMPLES - 1 do
                    local color, a = shader(x + (sx + 0.5) / SAMPLES, y + (sy + 0.5) / SAMPLES)
                    r, g, b, alpha = r + color[1] * a, g + color[2] * a, b + color[3] * a, alpha + a
                end
            end
            -- 透明像素 RGB 归零；边缘存非预乘 RGB，避免图像纹理乘黑边。
            local pixel = alpha > 0 and Color(r / alpha, g / alpha, b / alpha, alpha / (SAMPLES * SAMPLES))
                or Color(0, 0, 0, 0)
            image:SetPixel(x, y, pixel)
        end
    end
    assert(image:SavePNG(path), "SavePNG 失败: " .. path)
    image:Dispose()
    print("[dark-ui-bake] 写入 " .. path .. " " .. width .. "x" .. height .. " RGBA")
end

function Start()
    local ok, err = pcall(function()
        local output = ""
        for _, arg in ipairs(GetArguments()) do
            local value = arg:match("^%-output_dir=(.+)$")
            if value then output = value end
        end
        assert(output ~= "", "需要 -output_dir=<已有目录>，防止误覆盖正式素材")
        bake(98, 127, awakening, output .. "/UI_JX_JT.png")
        bake(70, 30, thumb, output .. "/UI_JTTF_HK.png")
        bake(40, 40, down, output .. "/ICON_down.png")
        print("[dark-ui-bake] ALL PASS images=3")
    end)
    if not ok then log:Write(LOG_ERROR, "[dark-ui-bake] " .. tostring(err)) end
    engine:Exit()
end
