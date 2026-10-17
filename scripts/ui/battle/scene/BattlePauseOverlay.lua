-- 沿用 scaffold-2d 的新 UI 子树，复用战场宿主帧；只读真实暂停时钟，不接管输入。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local BattleClock = require("ui.battle.combat.BattleClock")
local I18n = require("core.I18n")
local M = {}
---@type Panel?
local root = nil
---@type Label?
local caption = nil

function M.init()
    if root then return end
    Surface.init()
    caption = UI.Label { text = "", fontFamily = "sans", fontWeight = "normal",
        fontSize = 18, minFontSize = 12, fontColor = {242,242,240,255},
        textAlign = "center", verticalAlign = "middle", flexShrink = 1 }
    root = UI.Panel { width = 1, height = 1, pointerEvents = "none", overflow = "hidden",
        backgroundColor = {72,75,79,145}, alignItems = "center", justifyContent = "center",
        children = {
            UI.Panel { paddingHorizontal = 20, height = 62, maxWidth = "90%",
                backgroundColor = {27,29,32,225}, borderRadius = 8, borderWidth = 1,
                borderColor = {175,178,182,155}, flexDirection = "row", gap = 12,
                alignItems = "center", pointerEvents = "none", children = {
                    UI.Panel { width = 16, height = 22, flexDirection = "row", gap = 6,
                        children = {
                            UI.Panel { width = 5, height = 22, backgroundColor = {225,227,231,255} },
                            UI.Panel { width = 5, height = 22, backgroundColor = {225,227,231,255} },
                        } }, caption,
                } },
        } }
end

--- 放在战斗内容之后、按钮与弹窗之前；保留宿主变换及裁剪。
function M.draw(vg, x, y, width, height, active, uiScale)
    if active == false or not BattleClock.isPaused() or width <= 0 or height <= 0 then return end
    M.init()
    if not root or not caption then return end
    local scale = math.max(0.01, tonumber(uiScale) or 1)
    local layoutW, layoutH = width / scale, height / scale
    root:SetWidth(layoutW)
    root:SetHeight(layoutH)
    caption:SetText(I18n.lookup("战斗已暂停"))
    nvgSave(vg)
    nvgIntersectScissor(vg, x, y, width, height)
    nvgTranslate(vg, x, y)
    if scale ~= 1 then nvgScale(vg, scale, scale) end
    Surface.draw(root, vg, layoutW, layoutH)
    nvgRestore(vg)
end

function M.destroy()
    if root then root:Destroy() end
    root, caption = nil, nil
end
return M
