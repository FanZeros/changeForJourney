-- ============================================================================
-- QualityMark - 装备品质小图。背包、铁匠分解、遗匣共用 UI_ICON_PZSX_1~6。
-- ============================================================================
local DrawUtil = require("core.DrawUtil")

local QualityMark = {}
local PATHS = {
    "image/通用图标/UI_ICON_PZSX_1.png",
    "image/通用图标/UI_ICON_PZSX_2.png",
    "image/通用图标/UI_ICON_PZSX_3.png",
    "image/通用图标/UI_ICON_PZSX_4.png",
    "image/通用图标/UI_ICON_PZSX_5.png",
    "image/通用图标/UI_ICON_PZSX_6.png",
}
---@type integer[]
local icons = {}
local ready = false

function QualityMark.init(vg)
    if ready then return end
    ready = true
    for index = 1, #PATHS do
        icons[index] = nvgCreateImage(vg, PATHS[index], 0) or -1
        if icons[index] < 0 then
            print("[QualityMark] missing " .. PATHS[index])
        end
    end
end

function QualityMark.count()
    return #PATHS
end

---@param quality number
---@return integer
function QualityMark.get(quality)
    local index = math.tointeger(quality)
    if not index then return -1 end
    return icons[index] or -1
end

--- 按其他页面的品质小图绘制。缺图时返回 false，调用方可以回退文字。
---@param quality number
---@return boolean
function QualityMark.draw(vg, quality, cx, cy, size, alpha)
    local img = QualityMark.get(quality)
    if img < 0 then return false end
    DrawUtil.drawImageCentered(vg, img, cx, cy, size, size, alpha or 1)
    return true
end

return QualityMark
