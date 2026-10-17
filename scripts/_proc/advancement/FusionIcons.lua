-- 融合二转图标烘焙：沿用现有职业图标的暗铁旧铜底板与两种一转器物。
-- 基于既有 Batch3Raster 的 Image/Start/Dispose/Exit 离线脚手架，不调用GPU或读取玩家档。
local ROOT = "/workspace/assets/image/职业图标/"
local SIZE, CENTER = 280, 139.5
local PAIRS = {
    { 225, 101, 102 }, { 226, 103, 104 }, { 227, 105, 106 },
    { 228, 107, 108 }, { 229, 109, 110 }, { 230, 111, 112 },
}

---@param id integer
---@return Image
local function load(id)
    local image = Image()
    assert(image:Load(ROOT .. "UI_icon_ZY_" .. id .. ".png"), "无法读取一转图标 " .. id)
    assert(image.width == SIZE and image.height == SIZE and image.components == 4, "一转图标规格不一致")
    return image
end

-- 两种器物沿斜向接缝合流；中央双环铆钉表达双入口，不改变共用外框。
---@param left Image
---@param right Image
---@return Image
local function fuse(left, right)
    local image = Image()
    assert(image:SetSize(SIZE, SIZE, 4), "创建融合图标失败")
    for y = 0, SIZE - 1 do
        for x = 0, SIZE - 1 do
            local dx, dy = x - CENTER, y - CENTER
            local radius = math.sqrt(dx * dx + dy * dy)
            local split = CENTER + dy * 0.20
            local color = left:GetPixel(x, y)
            if radius <= 110 then
                color = x < split and left:GetPixel(x, y) or right:GetPixel(x, y)
                if math.abs(x - split) < 2.2 and radius < 103 then
                    color = Color(0.63, 0.47, 0.25, 1)
                end
                local diamond = math.abs(dx) + math.abs(dy)
                if diamond < 21 then
                    color = diamond > 17 and Color(0.63, 0.47, 0.25, 1) or Color(0.055, 0.047, 0.039, 1)
                    local ringLeft = math.sqrt((dx + 5) ^ 2 + dy ^ 2)
                    local ringRight = math.sqrt((dx - 5) ^ 2 + dy ^ 2)
                    if math.abs(ringLeft - 7) < 1.7 or math.abs(ringRight - 7) < 1.7 then
                        color = Color(0.86, 0.81, 0.67, 1)
                    end
                end
            end
            image:SetPixel(x, y, color)
        end
    end
    return image
end

function Start()
    local ok, err = pcall(function()
        for _, row in ipairs(PAIRS) do
            local left, right = load(row[2]), load(row[3])
            local image = fuse(left, right)
            assert(image:SavePNG(ROOT .. "UI_icon_ZY_" .. row[1] .. ".png"), "融合图标写入失败")
            print("[FusionIcons] " .. row[1] .. " <- " .. row[2] .. " + " .. row[3] .. " 280x280 RGBA")
            image:Dispose()
            left:Dispose()
            right:Dispose()
        end
    end)
    if not ok then log:Write(LOG_ERROR, "[FusionIcons] " .. tostring(err)) end
    engine:Exit()
end
