-- ============================================================================
-- LetterIntro.lua — 先祖来信（首登开场剧情·轻松带梗版）
-- 玩法：暗色信笺逐行显墨（短版 3 段，轻触翻段/自动推进）→ 火漆印「终」→ 淡出进游戏。
--       后续睁眼过场 / 情景1 已取消，解锁在信件结束时直接发放。
-- 绘制：全窗口逻辑坐标（调用方 nvgResetTransform 后传入 logicalW/logicalH），
--       横屏 16:9 cover 铺满，不再做 1080×2400 letterbox 窄条。
-- 素材（本地路径，不走 URL）：
--   image/GF_KF06_desk_relics_20260915115639.png  书斋桌案（信封+帽）
--   image/GF_KF07_wax_seal_20260915115637.png     火漆特写「终」
-- ============================================================================

---@class LetterIntro
---@field init fun(vg: userdata)
---@field start fun(onFinish: function|nil)
---@field isOpen fun(): boolean
---@field reset fun()
---@field handleTap fun()
---@field update fun(dt: number)
---@field draw fun(vg: userdata, w: number, h: number)
local LetterIntro = {}

-- ======================== 信件内容（blocks × lines） ========================
local BLOCKS = {
    {
        { t = "致我从未谋面的孩子：", gold = true },
        { t = "拆开这封信时，我已经死了。" },
        { t = "按公会规矩，这叫「荣休」。" },
    },
    {
        { t = "帽子、印鉴、名册，都留给你。" },
        { t = "塔底下的东西不讲道理，" },
        { t = "但他们够吵。" },
    },
    {
        { t = "公会不需要英雄，", gold = true },
        { t = "需要一个签字的傻子。", gold = true, seal = true },
        { t = "——第三十六任远征长，你的外祖父", dim = true },
    },
}

local C_INK  = { 214, 200, 166 }
local C_GOLD = { 232, 200, 120 }
local C_DIM  = { 150, 142, 124 }
local C_BG   = { 4, 4, 7 }

-- ======================== 状态 ========================
local vg_       = nil
local imgDesk_  = -1
local imgSeal_  = -1
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
---@param vg userdata
function LetterIntro.init(vg)
    vg_ = vg
    if imgDesk_ < 0 then
        imgDesk_ = nvgCreateImage(vg, "image/GF_KF06_desk_relics_20260915115639.png", 0)
        if imgDesk_ < 0 then
            print("[LetterIntro] WARN: GF_KF06_desk_relics load failed")
        else
            print("[LetterIntro] desk relics loaded")
        end
    end
    if imgSeal_ < 0 then
        imgSeal_ = nvgCreateImage(vg, "image/GF_KF07_wax_seal_20260915115637.png", 0)
        if imgSeal_ < 0 then
            print("[LetterIntro] WARN: GF_KF07_wax_seal load failed")
        else
            print("[LetterIntro] wax seal loaded")
        end
    end
end

function LetterIntro.start(onFinish)
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
---@param vg userdata
---@param w number
---@param h number
local function drawLetter(vg, w, h)
    if not active then return end
    if w <= 0 or h <= 0 then return end

    local fade = 1.0
    if state == "fading" then fade = 1.0 - fadeT / FADE_DUR end
    local flicker = 0.93 + 0.05 * math.sin(totalT * 11.0) + 0.02 * math.sin(totalT * 23.7)

    -- 1) 全屏暗底（盖住左右城镇/角色面板）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(C_BG[1], C_BG[2], C_BG[3], 255 * fade))
    nvgFill(vg)

    -- 2) 背景：reveal 用书斋桌案，sealed 叠火漆特写（16:9 cover 铺满）
    local imgAR = 16 / 9
    local dx, dy, dw, dh = coverRect(w, h, imgAR)
    local bgImg = imgDesk_
    local bgA = fade * flicker
    if state == "sealed" and imgSeal_ >= 0 then
        local p = math.min(1, sealedT / SEAL_DUR)
        if imgDesk_ >= 0 then
            local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, imgDesk_, bgA * (1 - p))
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, w, h)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end
        bgImg = imgSeal_
        bgA = fade * (0.85 + 0.15 * p)
    end
    if bgImg >= 0 then
        local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, bgImg, bgA)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end

    -- 3) 半透明信笺底板（横屏居中，约占 62% 宽 × 78% 高）
    local panelW = math.min(w * 0.62, h * 1.05)
    local panelH = math.min(h * 0.78, w * 0.72)
    local panelX = (w - panelW) * 0.5
    local panelY = (h - panelH) * 0.5 - h * 0.02
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, math.max(10, h * 0.012))
    nvgFillColor(vg, nvgRGBA(12, 10, 8, 210 * fade))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, math.max(10, h * 0.012))
    nvgStrokeColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 90 * fade))
    nvgStrokeWidth(vg, math.max(1.5, h * 0.0025))
    nvgStroke(vg)

    -- 标题分隔金线
    local padX = panelW * 0.08
    local textX = panelX + padX
    local textW = panelW - padX * 2
    local lineY0 = panelY + panelH * 0.10
    nvgBeginPath(vg)
    nvgMoveTo(vg, textX, lineY0)
    nvgLineTo(vg, textX + textW, lineY0)
    nvgStrokeColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 120 * fade))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 4) 正文逐行显墨
    local fsHead = math.max(22, math.min(w * 0.028, h * 0.045))
    local fsBody = math.max(18, math.min(w * 0.022, h * 0.036))
    local lineH  = fsBody * 1.55
    local lineY  = lineY0 + lineH * 1.35
    nvgFontFace(vg, "sans")
    for b = 1, blockIdx do
        local maxLine = lineCount(b)
        if b == blockIdx then
            maxLine = math.min(maxLine, math.floor(revealT / LINE_REVEAL))
        end
        for i = 1, maxLine do
            local L = BLOCKS[b][i]
            local isHead = (b == 1 and i == 1)
            local fs = isHead and fsHead or fsBody
            local col = L.gold and C_GOLD or (L.dim and C_DIM or C_INK)
            local a = 255
            if b == blockIdx then
                local phase = revealT - (i - 1) * LINE_REVEAL
                if phase < 0.4 then a = 255 * math.max(0, phase / 0.4) end
            end
            a = a * flicker * fade
            nvgFontSize(vg, fs)
            if L.dim then
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BASELINE)
            else
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BASELINE)
            end
            nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], a))
            nvgText(vg, L.dim and (textX + textW) or textX, lineY, L.t, nil)
            lineY = lineY + lineH
        end
        if b < blockIdx then
            lineY = lineY + lineH * 0.45
        end
    end

    -- 5) 底部提示
    local hintA = (0.35 + 0.5 * (0.5 + 0.5 * math.sin(totalT * 2.2))) * fade
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(16, math.min(w * 0.018, 28)))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 180 * hintA))
    if state == "reveal" then
        nvgText(vg, w * 0.5, panelY + panelH + h * 0.045, "· 轻 触 翻 阅 ·", nil)
    elseif state == "sealed" then
        nvgText(vg, w * 0.5, panelY + panelH + h * 0.045, "· 火 漆 已 落 ·", nil)
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
