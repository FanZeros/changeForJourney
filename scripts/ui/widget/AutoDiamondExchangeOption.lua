-- 黑晶自动兑换选项：复用设计坐标控件桥，绘制/命中共用尺寸，只修改本地偏好。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local SettingsPanel = require("ui.hud.popup.SettingsPanel")
local I18n = require("core.I18n")

local M = { HEIGHT = 56 }

-- 在宿主init阶段创建UI上下文；不能在NanoVGRender回调内首次设置渲染顺序。
function M.init()
    Surface.init()
end

---@class AutoDiamondExchangeView
---@field root Panel
---@field checkbox Checkbox
---@field title Label
---@field hint Label
---@type table<string, AutoDiamondExchangeView>
local views = {}

local TEXT = {
    zh_CN = { title = "自动兑换", ticket = "券不足时补足缺口 · %d黑晶/张", key = "钥匙不足时补足缺口 · %d黑晶/把" },
    zh_TW = { title = "自動兌換", ticket = "券不足時補足缺口 · %d黑晶/張", key = "鑰匙不足時補足缺口 · %d黑晶/把" },
    en = { title = "Auto exchange", ticket = "Fill missing tickets · %d gems each", key = "Fill missing keys · %d gems each" },
    ja = { title = "自動交換", ticket = "不足分のチケットを補充 · 1枚%d黒晶", key = "不足分の鍵を補充 · 1本%d黒晶" },
    ko = { title = "자동 교환", ticket = "부족한 티켓만 보충 · 장당 흑수정 %d개", key = "부족한 열쇠만 보충 · 개당 흑수정 %d개" },
}

local function viewFor(scope, width)
    local view = views[scope]
    if view then return view end
    Surface.init()
    local checkbox = UI.Checkbox {
        width = 40, height = M.HEIGHT, size = 32, flexShrink = 0,
        checked = false, borderRadius = 5,
        checkedBgColor = { 196, 160, 90, 255 }, checkmarkColor = { 26, 18, 10, 255 },
        uncheckedBgColor = { 35, 30, 28, 255 }, uncheckedBorderColor = { 150, 125, 88, 255 },
    }
    local title = UI.Label {
        text = "", width = "100%", height = 30, fontSize = 28,
        fontFamily = "sans", fontColor = { 246, 224, 177, 255 }, verticalAlign = "middle",
    }
    local hint = UI.Label {
        text = "", width = "100%", height = 26, fontSize = 22,
        fontFamily = "sans", fontColor = { 205, 195, 177, 255 }, verticalAlign = "middle",
    }
    local root = UI.Panel {
        width = width, height = M.HEIGHT, flexDirection = "row", alignItems = "center", gap = 14,
        children = {
            checkbox,
            UI.Panel { flex = 1, minWidth = 0, flexShrink = 1, height = M.HEIGHT,
                children = { title, hint } },
        },
    }
    view = { root = root, checkbox = checkbox, title = title, hint = hint }
    views[scope] = view
    return view
end

function M.draw(vg, scope, cx, cy, width, price, disabled)
    local view = viewFor(scope, width)
    local text = TEXT[I18n.get()] or TEXT.zh_CN
    view.checkbox:SetChecked(SettingsPanel.isAutoDiamondExchangeEnabled(scope))
    view.checkbox:SetDisabled(disabled == true)
    view.title:SetText(text.title)
    local template = scope:sub(1, 6) == "gacha_" and text.ticket or text.key
    view.hint:SetText(string.format(template, price))
    nvgSave(vg)
    nvgTranslate(vg, cx - width * 0.5, cy - M.HEIGHT * 0.5)
    if disabled then nvgGlobalAlpha(vg, 0.5) end
    Surface.draw(view.root, vg, width, M.HEIGHT)
    nvgRestore(vg)
end

-- 宿主先处理模态/动画/在途请求，再传入同一套设计坐标，整行均可点。
function M.handleInput(dx, dy, scope, cx, cy, width, disabled)
    if math.abs(dx - cx) > width * 0.5 or math.abs(dy - cy) > M.HEIGHT * 0.5 then return false end
    if not disabled then
        SettingsPanel.setAutoDiamondExchangeEnabled(scope,
            not SettingsPanel.isAutoDiamondExchangeEnabled(scope))
    end
    return true
end

return M
