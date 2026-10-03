-- ============================================================================
-- LetterIntro.lua — 先祖来信（开场第一幕·横屏信笺）
-- 玩法：暗色横信逐行显墨（4 段）→ 火漆印「终」→ 交给门厅点卯（ScenarioDialogue.OPENING）。
-- 绘制：全窗口逻辑坐标。横屏信笺偏左、矮而宽，右边留出书斋桌案。
-- 素材（本地路径，不走 URL）：
--   image/界面底板/剧情日记/GF_KF06.png  书斋桌案（信封+帽），全程不切火漆特写
-- ============================================================================

---@class LetterIntro
---@field init fun(vg: NVGContextWrapper?)
---@field start fun(onFinish: function|nil)
---@field isOpen fun(): boolean
---@field reset fun()
---@field handleTap fun()
---@field update fun(dt: number)
---@field draw fun(vg: NVGContextWrapper?, w: number, h: number)
local LetterIntro = {}
local I18n = require("core.I18n")
local Story = require("core.I18nStory")
local Display = require("ui.story.StoryDisplay")

-- ======================== 信件内容（blocks × lines） ========================
local BLOCKS = {
    {
        { t = "致第三十七任远征长：", gold = true },
        { t = "拆开这封信时，我已经荣休了。" },
        { t = "公会管这叫交接。我管这叫甩锅。" },
    },
    {
        { t = "帽子、印鉴、名册，都在桌上。" },
        { t = "塔底下的山海怪不讲道理，" },
        { t = "但它们会排队上门。" },
    },
    {
        { t = "门外有三条吵闹的命。" },
        { t = "狗会咬，龙会烧，鸡会敲铃。" },
        { t = "先听他们把话说完，再出门。" },
    },
    {
        { t = "公会不需要英雄。", gold = true },
        { t = "需要一个肯签字的傻子。", gold = true, seal = true },
        { t = "——第三十六任，你的外祖父", dim = true },
    },
}

local C_INK  = { 214, 200, 166 }
local C_GOLD = { 232, 200, 120 }
local C_DIM  = { 150, 142, 124 }
local C_BG   = { 4, 4, 7 }

-- ======================== 状态 ========================
local vg_       = nil
local imgDesk_  = -1
local active    = false
local state     = "reveal"   -- reveal | sealed | fading
local blockIdx  = 1
local revealT   = 0
local sealedT   = 0
local fadeT     = 0
local totalT    = 0
local onFinishCb = nil

local LINE_REVEAL = 0.45
local BLOCK_HOLD  = 1.5
local SEAL_DUR    = 0.9
local FADE_DUR    = 0.6

local function lineCount(b) return #BLOCKS[b] end

-- 构造显示单元，不改 BLOCKS。第 5/6 行合成一句，等原两行都揭示后显示完整译句。
---@class LetterDisplayUnit
---@field text string
---@field block integer
---@field first integer
---@field last integer
---@field gold boolean|nil
---@field dim boolean|nil
local function displayUnits()
    local units = {} ---@type LetterDisplayUnit[]
    for b, block in ipairs(BLOCKS) do
        for i, line in ipairs(block) do
            if not (b == 2 and i == 3) then
                local source = line.t
                local last = i
                if b == 2 and i == 2 then
                    source = source .. block[3].t
                    last = 3
                end
                units[#units + 1] = { text = Display.text(source), block = b, first = i,
                    last = last, gold = line.gold, dim = line.dim }
            end
        end
    end
    return units
end

-- 先尝试原单栏信笺；只有14px仍装不下才扩板并按完整段分组双栏。
-- 没有滚动/新输入坐标：全文和末尾翻阅提示均在窗口内，保留全局tap契约。
local function letterLayout(vg, w, h, units)
    local preferredBody = math.max(16, math.min(w * 0.016, h * 0.026))
    local preferredHead = math.max(20, math.min(w * 0.022, h * 0.034))
    local function arrange(panelX, panelY, panelW, panelH, columns)
        local padX = panelW * (columns == 1 and 0.08 or 0.045)
        local textX = panelX + padX
        local textW = panelW - padX * 2
        local gap = columns == 2 and 24 or 0
        local columnW = (textW - gap) / columns
        local lineY0 = panelY + panelH * (columns == 1 and 0.14 or 0.06)
        local bodyY = lineY0 + math.max(8, panelH * 0.035)
        local availableH = panelY + panelH * 0.94 - bodyY
        local font = preferredBody
        local entries = {} ---@type table[]
        local fits = false
        while true do
            local heights = { 0, 0 }
            local previousBlocks = { 1, 3 }
            for index, unit in ipairs(units) do
                local column = columns == 2 and unit.block > 2 and 2 or 1
                local fs = index == 1 and font * preferredHead / preferredBody or font
                if unit.block ~= previousBlocks[column] then
                    heights[column] = heights[column] + font * 1.38 * 0.45
                    previousBlocks[column] = unit.block
                end
                local rows = Display.layoutText(vg, unit.text, columnW, fs)
                entries[index] = { rows = rows, font = fs,
                    x = textX + (column - 1) * (columnW + gap),
                    y = bodyY + heights[column], width = columnW }
                heights[column] = heights[column] + #rows * fs * 1.38
            end
            fits = math.max(heights[1], heights[2]) <= availableH
            if fits or font <= 14 then break end
            font = math.max(14, font - 0.5)
        end
        return { x = panelX, y = panelY, width = panelW, height = panelH,
            textX = textX, textW = textW, lineY = lineY0, entries = entries, fits = fits,
            footerY = math.min(h - 24, panelY + panelH + h * 0.045) }
    end
    local panelW, panelH = math.min(w * 0.70, 1320), math.min(h * 0.62, 680)
    local layout = arrange(w * 0.06, (h - panelH) * 0.46, panelW, panelH, 1)
    if not layout.fits then
        local marginX, marginY = math.max(18, w * 0.03), math.max(18, h * 0.04)
        layout = arrange(marginX, marginY, w - marginX * 2, h - marginY * 2 - 44, 2)
    end
    return layout
end

--- 16:9 图 cover 铺满窗口（与 DarkTitleScreen 同一套算法）
local function coverRect(w, h, imgAR)
    local winAR = w / h
    local dw, dh
    if winAR > imgAR then
        dw, dh = w, w / imgAR
    else
        dh, dw = h, h * imgAR
    end
    return (w - dw) * 0.5, (h - dh) * 0.5, dw, dh
end

-- ======================== 生命周期 ========================
---@param vg NVGContextWrapper?
function LetterIntro.init(vg)
    vg_ = vg
end

local function ensureLetterImages()
    if not vg_ then return end
    if imgDesk_ < 0 then
        imgDesk_ = nvgCreateImage(vg_, "image/界面底板/剧情日记/GF_KF06.png", 0)
        if imgDesk_ < 0 then
            print("[LetterIntro] WARN: GF_KF06 load failed")
        else
            print("[LetterIntro] desk relics loaded")
        end
    end
end

function LetterIntro.start(onFinish)
    ensureLetterImages()
    if active then return end
    active      = true
    state       = "reveal"
    blockIdx    = 1
    revealT     = 0
    sealedT     = 0
    fadeT       = 0
    totalT      = 0
    onFinishCb  = onFinish
    print("[LetterIntro] started")
end

function LetterIntro.isOpen()
    return active
end

function LetterIntro.reset()
    active = false
    state = "reveal"
    blockIdx = 1
    revealT = 0
    sealedT = 0
    fadeT = 0
    totalT = 0
    onFinishCb = nil
end

function LetterIntro.handleTap()
    if not active then return end
    -- 任意阶段都允许点击推进：翻段 / 跳过火漆 / 立刻淡出
    if state == "reveal" then
        local cur = lineCount(blockIdx)
        local revealed = math.floor(revealT / LINE_REVEAL)
        if revealed < cur then
            revealT = cur * LINE_REVEAL
        elseif blockIdx < #BLOCKS then
            blockIdx = blockIdx + 1
            revealT = 0
        else
            state = "sealed"
            sealedT = 0
        end
    elseif state == "sealed" then
        state = "fading"
        fadeT = 0
    elseif state == "fading" then
        fadeT = FADE_DUR
    end
end

function LetterIntro.update(dt)
    if not active then return end
    totalT = totalT + dt
    if state == "reveal" then
        revealT = revealT + dt
        local cur = lineCount(blockIdx)
        if revealT >= cur * LINE_REVEAL + BLOCK_HOLD then
            if blockIdx < #BLOCKS then
                blockIdx = blockIdx + 1
                revealT = 0
            else
                state = "sealed"
                sealedT = 0
            end
        end
    elseif state == "sealed" then
        sealedT = sealedT + dt
        if sealedT >= SEAL_DUR + 0.8 then
            state = "fading"
            fadeT = 0
        end
    elseif state == "fading" then
        fadeT = fadeT + dt
        if fadeT >= FADE_DUR then
            active = false
            print("[LetterIntro] finished")
            if onFinishCb then
                local cb = onFinishCb
                onFinishCb = nil
                cb()
            end
        end
    end
end

-- ======================== 绘制（全窗口逻辑坐标） ========================
---@param vg NVGContextWrapper?
---@param w number
---@param h number
local function drawLetter(vg, w, h)
    if not active then return end
    if w <= 0 or h <= 0 then return end
    ensureLetterImages()

    local fade = 1.0
    if state == "fading" then fade = 1.0 - fadeT / FADE_DUR end
    local flicker = 0.93 + 0.05 * math.sin(totalT * 11.0) + 0.02 * math.sin(totalT * 23.7)

    -- 1) 全屏暗底（盖住左右城镇/角色面板）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(C_BG[1], C_BG[2], C_BG[3], 255 * fade))
    nvgFill(vg)

    -- 2) 背景：全程书斋桌案，不切火漆特写
    local imgAR = 16 / 9
    local dx, dy, dw, dh = coverRect(w, h, imgAR)
    local bgImg = imgDesk_
    local bgA = fade * flicker
    if bgImg >= 0 then
        local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, bgImg, bgA)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end

    -- 3) 整封译文决定布局；逐段揭示不跳版，小屏优先扩板而非缩成微字。
    local units = displayUnits()
    local layout = letterLayout(vg, w, h, units)
    local panelX, panelY = layout.x, layout.y
    local panelW, panelH = layout.width, layout.height
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, math.max(10, h * 0.012))
    nvgFillColor(vg, nvgRGBA(12, 10, 8, 210 * fade))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, math.max(10, h * 0.012))
    nvgStrokeColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 90 * fade))
    nvgStrokeWidth(vg, math.max(1.5, h * 0.0025))
    nvgStroke(vg)

    -- 幕标与分隔金线
    local textX, textW, lineY0 = layout.textX, layout.textW, layout.lineY
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(14, math.min(w * 0.014, 22)))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BASELINE)
    nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 160 * fade))
    nvgBeginPath(vg)
    nvgMoveTo(vg, textX, lineY0)
    nvgLineTo(vg, textX + textW, lineY0)
    nvgStrokeColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 120 * fade))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 4) 预折行布局保持全文/段落顺序；右栏仅放完整的第三、四段。
    for index, unit in ipairs(units) do
        local entry = layout.entries[index]
        local rows, fs = entry.rows, entry.font
        local visible = unit.block < blockIdx or (unit.block == blockIdx
            and unit.last <= math.floor(revealT / LINE_REVEAL))
        if visible then
            local col = unit.gold and C_GOLD or (unit.dim and C_DIM or C_INK)
            local a = 255
            if unit.block == blockIdx then
                local elapsed = revealT - (unit.last - 1) * LINE_REVEAL
                a = 255 * math.min(1, math.max(0, elapsed / 0.4))
            end
            nvgFontSize(vg, fs)
            nvgTextAlign(vg, (unit.dim and NVG_ALIGN_RIGHT or NVG_ALIGN_LEFT) + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], a * flicker * fade))
            Display.drawRows(vg, unit.dim and (entry.x + entry.width) or entry.x, entry.y,
                rows, Story.length(unit.text), fs * 1.38)
        end
    end

    -- 5) 底部提示
    local hintA = (0.35 + 0.5 * (0.5 + 0.5 * math.sin(totalT * 2.2))) * fade
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(16, math.min(w * 0.018, 28)))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 180 * hintA))
    if state == "reveal" then
        Display.draw(vg, w * 0.5, layout.footerY, "· 轻 触 翻 阅 ·")
    elseif state == "sealed" then
        Display.draw(vg, w * 0.5, layout.footerY, "· 火 漆 已 落 ·")
    end

    -- 6) 四角金饰（全窗口）
    local inset, len = math.max(18, h * 0.028), math.max(28, h * 0.05)
    nvgStrokeColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 90 * fade))
    nvgStrokeWidth(vg, 2.2)
    for _, cx in ipairs({ true, false }) do
        for _, cy in ipairs({ true, false }) do
            local px = cx and inset or (w - inset)
            local py = cy and inset or (h - inset)
            local sx = cx and 1 or -1
            local sy = cy and 1 or -1
            nvgBeginPath(vg)
            nvgMoveTo(vg, px + sx * len, py)
            nvgLineTo(vg, px, py)
            nvgLineTo(vg, px, py + sy * len)
            nvgStroke(vg)
        end
    end
end

LetterIntro.draw = drawLetter

return LetterIntro
