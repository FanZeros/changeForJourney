-- 通天塔专用布局；不修改主线L0透明区域，也不把塔路线写入主线关卡链。
local Layout = {}

---@class TowerPanelRect
---@field x number
---@field y number
---@field w number
---@field h number
---@class TowerScreenLayout
---@field width number
---@field height number
---@field sideScale number
---@field sideHeight number
---@field left TowerPanelRect
---@field center TowerPanelRect
---@field right TowerPanelRect

---@param width number
---@param height number
---@return TowerScreenLayout
function Layout.compute(width, height)
    local w = math.max(1, tonumber(width) or 1920)
    local h = math.max(1, tonumber(height) or 1080)
    local sideW = math.min(486 * h / 1080, w * 0.28)
    local sideScale = sideW / 486
    return {
        width = w, height = h, sideScale = sideScale, sideHeight = h / sideScale,
        left = { x = 0, y = 0, w = sideW, h = h },
        center = { x = sideW, y = 0, w = w - sideW * 2, h = h },
        right = { x = w - sideW, y = 0, w = sideW, h = h },
    }
end

---@param rect TowerPanelRect
function Layout.contains(rect, x, y)
    return x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h
end

function Layout.panelAt(layout, x, y)
    if Layout.contains(layout.left, x, y) then return "left" end
    if Layout.contains(layout.right, x, y) then return "right" end
    if Layout.contains(layout.center, x, y) then return "center" end
    return nil
end

-- 侧栏UI采用486宽设计空间，等比缩放，输入只做一次逆变换。
function Layout.toSide(layout, panel, x, y)
    local rect = panel == "right" and layout.right or layout.left
    return (x - rect.x) / layout.sideScale, (y - rect.y) / layout.sideScale
end

-- 功绩仍为1080×2400设计稿，与侧栏486宽采用同一比例。
function Layout.toTask(layout, x, y)
    local scale = layout.sideScale * 0.45
    return (x - layout.left.x) / scale, (y - layout.left.y) / scale
end

-- 共享框体按参考画布裁出三行中段，再映到塔中栏；人物内容另用等比缩放。
-- 主线 getInteriorRectFor / INTERIORS 原值不改，不给它传窄中栏导致负位置。
function Layout.battleTransform(layout)
    local referenceW, referenceH = 1920, 1080
    local plateW = referenceH * (1672 / 941)
    local plateX = (referenceW - plateW) * 0.5
    local cropX = plateX + 0.2835 * plateW - 20
    local cropRight = plateX + 0.7207 * plateW + 20
    return {
        referenceW = referenceW, referenceH = referenceH, cropX = cropX,
        x = layout.center.x, y = layout.center.y,
        scaleX = layout.center.w / (cropRight - cropX), scaleY = layout.height / referenceH,
    }
end

function Layout.mapInterior(layout, x, y, w, h)
    local t = Layout.battleTransform(layout)
    return t.x + (x - t.cropX) * t.scaleX, t.y + y * t.scaleY,
        w * t.scaleX, h * t.scaleY
end

-- 确认弹窗保持原560×280、左撤退/右取消契约；小窗等比适配。
function Layout.confirm(layout)
    local scale = math.min(1, layout.width / 640, layout.height / 360)
    local cx, cy = layout.width * 0.5, layout.height * 0.5
    return { cx = cx, cy = cy, scale = scale,
        frame = { x = cx - 280 * scale, y = cy - 140 * scale, w = 560 * scale, h = 280 * scale },
        retreat = { x = cx - 220 * scale, y = cy + 50 * scale, w = 180 * scale, h = 56 * scale },
        cancel = { x = cx + 40 * scale, y = cy + 50 * scale, w = 180 * scale, h = 56 * scale } }
end

return Layout
