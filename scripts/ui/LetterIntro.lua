-- ============================================================================
-- LetterIntro.lua — 先祖来信（首登开场剧情·轻松带梗版）
-- 玩法：黑屏 → 暗色信笺逐行显墨（分 7 段，轻触翻段/自动推进）→ 火漆印「终」
--       → 淡出，无缝衔接 IntroCutscene（睁眼过场）→ SCENARIO_1 → 选角。
-- 触发：仅 Client 新手链（roster 为空），在 IntroCutscene 之前。
-- 绘制：设计空间 1080×2400（横屏由调用方做 letterbox 变换，同 StartScreen）。
-- ============================================================================

local DarkIcon = require("core.DarkIcon")

local LetterIntro = {}

-- ======================== 信件内容（blocks × lines） ========================
-- gold=true 的行用亮金色（关键句）
local BLOCKS = {
    {
        { t = "致我从未谋面的孩子：", gold = true },
        { t = "当你拆开这封信时，" },
        { t = "我应该已经死了。" },
        { t = "——别哭，按公会的规矩，" },
        { t = "这叫「荣休」。" },
    },
    {
        { t = "六年前我带最后一支队伍进了那座塔。" },
        { t = "走出来的只有我的帽子。" },
        { t = "帽子留给你，别嫌旧，" },
        { t = "它挡过龙息。" },
    },
    {
        { t = "随信附上：公会印鉴一枚、" },
        { t = "旧名册一本、" },
        { t = "欠酒馆的账单一沓（坐稳，真的很多）。" },
    },
    {
        { t = "名册上睡着二十三个名字。" },
        { t = "有会叠甲的，有熬夜的，还有内鬼——" },
        { t = "对，名册里真有一个内鬼，" },
        { t = "你自己排查。" },
        { t = "塔底下的东西不讲道理，" },
        { t = "但他们够吵。" },
    },
    {
        { t = "酒在柜子里，账在抽屉里，塔在门外。" },
        { t = "教堂的钟只为活着的人敲，" },
        { t = "能不进就别进。" },
    },
    {
        { t = "本想写点鼓舞人心的话收尾，" },
        { t = "但律师说遗产信里不许画饼。" },
        { t = "所以只说一句大实话：" },
        { t = "公会不需要英雄，", gold = true },
        { t = "需要一个签字的傻子。", gold = true },
        { t = "签吧，反正你已经拆信了。", gold = true, seal = true },
    },
    {
        { t = "——第三十六任远征长，你的外祖父", dim = true },
        { t = "（欠条别弄丢，那也是遗产）", dim = true },
    },
}

-- ======================== 布局常量（设计空间 1080×2400） ========================
-- 注：panel 样式自带标题分隔线（约面板顶部 176px 处），正文从分隔线下方起排
local PANEL_X, PANEL_Y, PANEL_W, PANEL_H = 60, 170, 960, 2000
local TEXT_X, TEXT_W = 125, 820
local TEXT_Y0 = 460
local LINE_H = 50
local FS_BODY, FS_HEAD = 36, 42
local SIG_RIGHT_X = TEXT_X + 800   -- 落款右对齐基线

local C_INK  = { 214, 200, 166 }
local C_GOLD = { 232, 200, 120 }
local C_DIM  = { 150, 142, 124 }
local C_BG   = { 4, 4, 7 }

-- ======================== 状态 ========================
local vg_       = nil
local active    = false
local state     = "reveal"   -- reveal | sealed | fading
local blockIdx  = 1
local revealT   = 0          -- 当前段已用时间
local sealedT   = 0
local fadeT     = 0
local totalT    = 0
local onFinishCb = nil

local LINE_REVEAL = 0.45     -- 行显墨间隔
local BLOCK_HOLD  = 1.5      -- 段末自动翻页延迟
local SEAL_DUR    = 0.9
local FADE_DUR    = 0.6

local function lineCount(b) return #BLOCKS[b] end

--- 已显行的全局序号（含之前所有段）
local function revealedLineTotal(b, revealed)
    local n = 0
    for i = 1, b - 1 do n = n + lineCount(i) end
    return n + revealed
end

-- ======================== 生命周期 ========================
--- 启动信件（onFinish 在淡出完成后回调）
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

--- 轻触：未显完→整段显完；已显完→下一段/封印
function LetterIntro.handleTap()
    if not active or state ~= "reveal" then return end
    local cur = lineCount(blockIdx)
    local revealed = math.floor(revealT / LINE_REVEAL)
    if revealed < cur then
        revealT = cur * LINE_REVEAL   -- 整段瞬间显完
    elseif blockIdx < #BLOCKS then
        blockIdx = blockIdx + 1
        revealT = 0
    else
        state = "sealed"
        sealedT = 0
    end
end

function LetterIntro.update(dt)
    if not active then return end
    totalT = totalT + dt
    if state == "reveal" then
        revealT = revealT + dt
        local cur = lineCount(blockIdx)
        if revealT >= cur * LINE_REVEAL + BLOCK_HOLD then
            -- 自动翻段
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

-- ======================== 绘制（设计空间 1080×2400） ========================
function LetterIntro.draw(vg)
    if not active then return end

    local fade = 1.0
    if state == "fading" then fade = 1.0 - fadeT / FADE_DUR end
    -- 烛光呼吸（轻微确定性闪烁）
    local flicker = 0.93 + 0.05 * math.sin(totalT * 11.0) + 0.02 * math.sin(totalT * 23.7)

    -- 1) 全屏暗幕
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(C_BG[1], C_BG[2], C_BG[3], 250 * fade))
    nvgFill(vg)

    -- 2) 信笺底板（暗铁金饰九宫格）
    local panelA = 255 * fade
    nvgSave(vg)
    nvgGlobalAlpha(vg, fade)
    DarkIcon.drawNine(vg, "panel", PANEL_X, PANEL_Y, PANEL_W, PANEL_H)

    -- 3) 正文逐行显墨
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BASELINE)
    local lineY = TEXT_Y0
    for b = 1, blockIdx do
        local maxLine = lineCount(b)
        if b == blockIdx then
            maxLine = math.min(maxLine, math.floor(revealT / LINE_REVEAL))
        end
        for i = 1, maxLine do
            local L = BLOCKS[b][i]
            local isHead = (b == 1 and i == 1)
            local fs = isHead and FS_HEAD or FS_BODY
            local col = L.gold and C_GOLD or (L.dim and C_DIM or C_INK)
            -- 行内淡入：当前段最后一行按相位渐显
            local a = 255
            if b == blockIdx then
                local phase = revealT - (i - 1) * LINE_REVEAL
                if phase < 0.4 then a = 255 * math.max(0, phase / 0.4) end
            end
            a = a * flicker * fade
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, fs)
            if L.dim then nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BASELINE) end
            nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], a))
            nvgText(vg, L.dim and SIG_RIGHT_X or TEXT_X, lineY, L.t, nil)
            if L.dim then nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BASELINE) end
            lineY = lineY + LINE_H
        end
        if b < blockIdx then
            -- 段间空行
            lineY = lineY + LINE_H * 0.6
        end
    end

    -- 4) 火漆印「终」（信笺右上标题区，最后一段显完时砸下）
    if state == "sealed" then
        local p = math.min(1, sealedT / SEAL_DUR)
        local scale = 1.6 - 0.6 * p              -- 从大到小砸落
        local a = 255 * math.min(1, p * 2) * fade
        local cx, cy, r = 900, 258, 56 * scale
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r)
        nvgFillColor(vg, nvgRGBA(148, 38, 32, 232 * a / 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r * 0.72)
        nvgStrokeColor(vg, nvgRGBA(120, 26, 22, 255 * a / 255))
        nvgStrokeWidth(vg, 4)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 58)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(232, 210, 190, a))
        nvgText(vg, cx, cy + 2, "终", nil)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BASELINE)
    end

    -- 5) 底部提示
    local hintA = (0.35 + 0.5 * (0.5 + 0.5 * math.sin(totalT * 2.2))) * fade
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 160 * hintA))
    if state == "reveal" then
        nvgText(vg, 540, 2270, "· 轻 触 翻 阅 ·", nil)
    end

    -- 6) 四角金饰角标（呼应标题界面）
    local inset, len = 36, 60
    nvgStrokeColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 70 * fade))
    nvgStrokeWidth(vg, 2.5)
    for _, cx in ipairs({ true, false }) do
        for _, cy in ipairs({ true, false }) do
            local px = cx and inset or (1080 - inset)
            local py = cy and inset or (2400 - inset)
            local sx = cx and 1 or -1
            local sy = cy and 1 or -1
            nvgBeginPath(vg)
            nvgMoveTo(vg, px + sx * len, py)
            nvgLineTo(vg, px, py)
            nvgLineTo(vg, px, py + sy * len)
            nvgStroke(vg)
        end
    end

    nvgRestore(vg)
end

return LetterIntro
