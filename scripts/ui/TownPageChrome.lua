-- ============================================================================
-- TownPageChrome - 城镇二级页共用壳：名称牌 / 返回 / 底栏 Tab / 开闭缓动
-- 铁匠铺、教堂、酒馆、市场、背包共用绘制与点击判定，不改各页玩法内容
-- ============================================================================

local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")

local M = {}

M.DESIGN_W = 1080
M.DESIGN_H = 2400

M.NAME = {
    BG_CX = 147, BG_CY = 136, BG_W = 294, BG_H = 123,
    TEXT_CX = 148, TEXT_CY = 130, FONT = 50,
}

M.BACK = { CX = 958, CY = 1150, W = 184, H = 143 }

M.TAB3 = {
    BG_CX = 540, BG_CY = 2308, BG_W = 810, BG_H = 143,
    SLIDER_W = 277, SLIDER_H = 143,
    FONT = 40, TEXT_Y = 2302,
}

M.TAB2 = {
    BG_CX = 639, BG_CY = 2308, BG_W = 810, BG_H = 143,
    SLIDER_W = 410, SLIDER_H = 143,
    FONT = 40, TEXT_Y = 2302,
}

M.COLOR_BONE = { r = 0xD8, g = 0xC9, b = 0xA3 }
M.COLOR_BROWN = { r = 0x81, g = 0x57, b = 0x3c }
M.COLOR_WHITE = { r = 255, g = 255, b = 255 }

M.OPEN_DUR = 0.45
M.CLOSE_DUR = 0.38
M.TAB_ANIM_DUR = 0.35

function M.easeOutCubic(t)
    local t1 = 1 - t
    return 1 - t1 * t1 * t1
end

function M.easeInCubic(t)
    return t * t * t
end

function M.easeInOutCubic(t)
    if t < 0.5 then return 4 * t * t * t end
    local f = 2 * t - 2
    return 0.5 * f * f * f + 1
end

--- 打开/关闭动画进度。closing 时从 1 收到 0。
---@return number progress, boolean closeFinished, boolean openJustFinished
function M.slideProgress(state, openDur, closeDur)
    openDur = openDur or M.OPEN_DUR
    closeDur = closeDur or M.CLOSE_DUR
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        local rawT = math.min(1.0, elapsed / closeDur)
        return 1 - M.easeInCubic(rawT), (rawT >= 1.0), false
    end
    local elapsed = time.elapsedTime - state.openTime
    local rawT = math.min(1.0, elapsed / openDur)
    return M.easeOutCubic(rawT), false, (rawT >= 1.0)
end

---@param vg userdata
---@param img number
---@param title string
---@param opts table|nil { textCX, textCY, font }
function M.drawNamePlate(vg, img, title, opts)
    opts = opts or {}
    local N = M.NAME
    DrawUtil.drawImageCentered(vg, img, N.BG_CX, N.BG_CY, N.BG_W, N.BG_H, 1.0)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, opts.font or N.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, opts.textCX or N.TEXT_CX, opts.textCY or N.TEXT_CY, title, nil)
end

---@param vg userdata
---@param opts table|nil { skip, cx, cy, w, h, dir }
function M.drawBack(vg, opts)
    opts = opts or {}
    if opts.skip then return end
    ---@diagnostic disable-next-line: undefined-global
    if H_SEAM_BACK then return end
    local B = M.BACK
    DrawUtil.drawBackChevron(vg,
        opts.cx or B.CX, opts.cy or B.CY,
        opts.w or B.W, opts.h or B.H,
        opts.dir or "left")
end

---@param dx number
---@param dy number
---@param opts table|nil { skip, cx, cy, w, h }
---@return boolean
function M.hitBack(dx, dy, opts)
    opts = opts or {}
    if opts.skip then return false end
    ---@diagnostic disable-next-line: undefined-global
    if H_SEAM_BACK then return false end
    local B = M.BACK
    return DrawUtil.hitTest(dx, dy,
        opts.cx or B.CX, opts.cy or B.CY,
        opts.w or B.W, opts.h or B.H)
end

--- Tab 滑块插值。easing="out" 用 easeOutCubic，默认 easeInOutCubic。
---@return number tabIdx, number fromIdx, number eased, boolean animating
function M.tabSlide(state, tabMap, animDur, easing)
    animDur = animDur or M.TAB_ANIM_DUR
    local tabIdx = tabMap[state.tab] or 1
    local fromIdx = tabMap[state.tabFrom] or tabIdx
    local tabElapsed = time.elapsedTime - (state.tabSwitchTime or 0)
    local tabT = math.min(1.0, tabElapsed / animDur)
    local eased
    if easing == "out" then
        eased = M.easeOutCubic(tabT)
    else
        eased = M.easeInOutCubic(tabT)
    end
    local animating = (tabT < 1.0 and tabIdx ~= fromIdx)
    return tabIdx, fromIdx, eased, animating
end

---@param vg userdata
---@param imgTabBg number
---@param cfg table
---  cfg.items: { {name, cx, cy, textX?, textY?} }
---  cfg.tabIdx, cfg.fromIdx, cfg.eased
---  cfg.activePred: fun(i, item): boolean
---  cfg.sliderW, cfg.sliderH
---  cfg.bgCX, cfg.bgCY, cfg.bgW, cfg.bgH
---  cfg.font, cfg.active, cfg.inactive
---  cfg.drawBadge: fun(vg, i, item, textX, textY)|nil
function M.drawTabBar(vg, imgTabBg, cfg)
    local bgCX = cfg.bgCX or M.TAB3.BG_CX
    local bgCY = cfg.bgCY or M.TAB3.BG_CY
    local bgW = cfg.bgW or M.TAB3.BG_W
    local bgH = cfg.bgH or M.TAB3.BG_H
    DrawUtil.drawImageCentered(vg, imgTabBg, bgCX, bgCY, bgW, bgH, 1.0)

    local items = cfg.items
    local tabIdx = cfg.tabIdx or 1
    local fromIdx = cfg.fromIdx or tabIdx
    local eased = cfg.eased or 1
    local fromItem = items[fromIdx] or items[tabIdx]
    local targetItem = items[tabIdx] or items[1]
    local sliderW = cfg.sliderW or M.TAB3.SLIDER_W
    local sliderH = cfg.sliderH or M.TAB3.SLIDER_H
    local sliderCX = fromItem.cx + (targetItem.cx - fromItem.cx) * eased
    local sliderCY = fromItem.cy + (targetItem.cy - fromItem.cy) * eased
    DarkIcon.drawNine(vg, "btn",
        sliderCX - sliderW * 0.5, sliderCY - sliderH * 0.5,
        sliderW, sliderH, { accent = "gold" })

    local font = cfg.font or M.TAB3.FONT
    local active = cfg.active or M.COLOR_BONE
    local inactive = cfg.inactive or M.COLOR_WHITE
    local defaultTextY = cfg.textY or M.TAB3.TEXT_Y
    for i, item in ipairs(items) do
        local isActive = cfg.activePred and cfg.activePred(i, item) or false
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, font)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(active.r, active.g, active.b, 255))
        else
            nvgFillColor(vg, nvgRGBA(inactive.r, inactive.g, inactive.b, 255))
        end
        local textX = item.textX or item.cx
        local textY = item.textY or defaultTextY
        nvgText(vg, textX, textY, item.name, nil)
        if cfg.drawBadge then
            cfg.drawBadge(vg, i, item, textX, textY)
        end
    end
end

---@return integer|nil index
function M.hitTab(dx, dy, items, sliderW, sliderH)
    for i, item in ipairs(items) do
        if DrawUtil.hitTest(dx, dy, item.cx, item.cy, sliderW, sliderH) then
            return i
        end
    end
    return nil
end

return M
