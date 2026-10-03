-- 套装徽记共享缓存与装备角标布局；采用用户审核通过的 V3 程序化素材。
local SetConfig = require("config.EquipmentSetConfig")
local EquipmentConfig = require("config.EquipmentConfig")
local DrawUtil = require("core.DrawUtil")
local M = {}
local cache = {}
local badgeCache = {}

function M.setId(equip)
    if not equip then return nil end
    local tpl = EquipmentConfig.ITEMS[equip.templateId]
    return tpl and SetConfig.getSetIdForTemplate(tpl) or nil
end

function M.isEnabled()
    -- 惰性读取设置，避免装备图标组件在角色/仓库初始化时形成依赖环。
    local settings = require("ui.hud.popup.SettingsPanel")
    return settings.isSetIconsEnabled()
end

function M.hasBadge(equip)
    return equip ~= nil and M.setId(equip) ~= nil and M.isEnabled()
end

function M.get(vg, setId)
    if not vg or not SetConfig.get(setId) then return -1 end
    local cached = cache[setId]
    if cached ~= nil then return cached end
    local path = "image/套装图标/v3/SET_" .. setId .. ".png"
    local image = nvgCreateImage(vg, path, 0)
    cache[setId] = image or -1
    if not image or image < 0 then print("[EquipmentSetIcon] 加载失败：" .. path) end
    return cache[setId]
end

-- 仅装备角标使用透明主体图；失败时跳过，不回退到带框V3。
local function getBadge(vg, setId)
    if not vg or not SetConfig.get(setId) then return -1 end
    local cached = badgeCache[setId]
    if cached ~= nil then return cached end
    local path = "image/套装图标/badge/SET_" .. setId .. ".png"
    local image = nvgCreateImage(vg, path, 0)
    badgeCache[setId] = image or -1
    if not image or image < 0 then print("[EquipmentSetIcon] 无框徽记加载失败：" .. path) end
    return badgeCache[setId]
end

-- 完整套装列表/筛选图标不受装备角标开关影响。
function M.draw(vg, setId, cx, cy, size, alpha)
    local image = M.get(vg, setId)
    if image < 0 then return false end
    DrawUtil.drawImageCentered(vg, image, cx, cy, size, size, alpha or 1)
    return true
end

function M.badgeLayout(cx, cy, cellSize)
    local size = cellSize * 0.275
    local pad = cellSize * 0.025
    local x, y = cx - cellSize * 0.5 + pad, cy + cellSize * 0.5 - pad - size
    return { x = x, y = y, size = size, cx = x + size * 0.5, cy = y + size * 0.5 }
end

function M.levelLayout(equip, cx, cy, cellSize)
    -- 等级固定原右下位置，开关套装角标不改变等级的对齐和字号。
    return {
        x = cx + cellSize * 0.45,
        y = cy + cellSize * 0.4625,
        fontSize = math.min(40, cellSize * 0.25),
        align = NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM,
    }
end

function M.drawBadge(vg, equip, cx, cy, cellSize, alpha)
    if not M.hasBadge(equip) then return false end
    local image = getBadge(vg, M.setId(equip))
    if image < 0 then return false end
    local layout = M.badgeLayout(cx, cy, cellSize)
    DrawUtil.drawImageCentered(vg, image, layout.cx, layout.cy, layout.size, layout.size, alpha or 1)
    return true
end

return M
