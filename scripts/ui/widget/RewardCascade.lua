-- ============================================================================
-- RewardCascade - 奖励逐件弹出动画（共用）
-- ----------------------------------------------------------------------------
-- 从 RewardPopup 抽出的「一件一件获得」动画原语，供任意奖励网格复用：
--   · 时间轴：第 idx 件的出场时刻 / 进度 / 已完成判定 / 已出场件数
--   · 绘制：光柱+冲击环+射线+火花的爆发、上层扫光、出场前的预告框
--   · 变换：出场时的缩放回弹 + 轻微摇摆 + 上浮
--
-- 【用法】
--   local Cascade = require("ui.widget.RewardCascade")
--   local cascade = Cascade.new(#items)        -- 或 Cascade.new(#items, { interval = 0.14 })
--   cascade:start(time.elapsedTime)
--   -- 每帧：
--   local t = cascade:t(idx)                   -- nil=未出场, 0..1=弹出中, >1=已落地
--   if t and t < 1 then Cascade.burst(vg, cx, cy, t, size, r, g, b) end
--   if cascade:finished() then ... end
-- ============================================================================

local RewardCascade = {}

-- ======================== 默认时间轴参数 ========================

--- 前 FAST_AFTER 件用 INTERVAL，之后用 INTERVAL_TAIL（件数多时不拖太久）
RewardCascade.LEAD          = 0.10
RewardCascade.INTERVAL      = 0.12
RewardCascade.INTERVAL_TAIL = 0.10
RewardCascade.FAST_AFTER    = 8
RewardCascade.POP_DUR       = 0.22

-- ======================== 缓动 ========================

--- ease-out back（带回弹）
---@param t number 0~1
---@return number
function RewardCascade.easeOutBack(t)
    local s = 1.70158
    t = t - 1
    return t * t * ((s + 1) * t + s) + 1
end

--- ease-out cubic
---@param t number 0~1
---@return number
function RewardCascade.easeOutCubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

-- ======================== 时间轴对象 ========================

---@class RewardCascadeTimeline
---@field count number 奖励件数
---@field interval number 常规间隔
---@field intervalTail number 件数多时的间隔
---@field fastAfter number 从第几件起切换间隔
---@field popDur number 单件弹出时长
---@field lead number 首件之前的停顿
---@field revealStart number 时间轴起点（time.elapsedTime）
local Timeline = {}
Timeline.__index = Timeline

--- 新建时间轴
---@param count number 奖励件数
---@param opts table|nil { interval, intervalTail, fastAfter, popDur, lead }
---@return RewardCascadeTimeline
function RewardCascade.new(count, opts)
    opts = opts or {}
    local self = setmetatable({}, Timeline)
    self.count        = math.max(0, math.floor(count or 0))
    self.interval     = opts.interval     or RewardCascade.INTERVAL
    self.intervalTail = opts.intervalTail or RewardCascade.INTERVAL_TAIL
    self.fastAfter    = opts.fastAfter    or RewardCascade.FAST_AFTER
    self.popDur       = opts.popDur       or RewardCascade.POP_DUR
    self.lead         = opts.lead         or RewardCascade.LEAD
    self.revealStart  = 0
    return self
end

--- 第 idx 件与上一件的间隔（第 1 件为 0）
---@param idx number
---@return number
function Timeline:gap(idx)
    if idx <= 1 then return 0 end
    if idx > self.fastAfter then return self.intervalTail end
    return self.interval
end

--- 第 idx 件的出场时刻（第 1 件为 0）
---@param idx number
---@return number
function Timeline:startAt(idx)
    if idx <= 1 then return 0 end
    local t = 0
    for i = 2, idx do
        t = t + self:gap(i)
    end
    return t
end

--- 开始播放（now 传 time.elapsedTime）
---@param now number
---@param skipLead boolean|nil true 时立即开始，不留停顿
function Timeline:start(now, skipLead)
    self.revealStart = now + (skipLead and 0 or self.lead)
end

--- 已播放秒数
---@return number
function Timeline:elapsed()
    return time.elapsedTime - self.revealStart
end

--- 单件进度：nil=未出场，0..1=弹出中，>1=已落地
---@param idx number
---@return number|nil
function Timeline:t(idx)
    local elapsed = self:elapsed()
    local startAt = self:startAt(idx)
    if elapsed < startAt then return nil end
    return (elapsed - startAt) / self.popDur
end

--- 当前已开始出场的件数
---@param elapsed number|nil 省略则用当前时间
---@return number
function Timeline:shownCount(elapsed)
    local e = elapsed or self:elapsed()
    if e < 0 or self.count <= 0 then return 0 end
    local shown = 0
    for i = 1, self.count do
        if e + 0.0001 >= self:startAt(i) then
            shown = i
        else
            break
        end
    end
    return shown
end

--- 是否全部落地
---@return boolean
function Timeline:finished()
    if self.count <= 0 then return true end
    return self:elapsed() >= self:startAt(self.count) + self.popDur
end

--- 立即跳到全部落地
function Timeline:skipToEnd()
    self.revealStart = time.elapsedTime - (self:startAt(self.count) + self.popDur)
end

-- ======================== 绘制原语 ========================

--- 单件爆发：光柱 + 冲击环 + 射线 + 火花 + 中心闪白（画在图标下层）
---@param vg any
---@param cx number 中心 X
---@param cy number 中心 Y
---@param t number 单件进度 0~1
---@param size number 图标边长（用于缩放光效尺寸）
---@param r number 强调色 R
---@param g number 强调色 G
---@param b number 强调色 B
function RewardCascade.burst(vg, cx, cy, t, size, r, g, b)
    local glowR = size * (0.28 + t * 0.95)
    local glowA = math.floor(150 * (1 - t) + 28)
    local glow = nvgRadialGradient(vg, cx, cy, 6, glowR,
        nvgRGBA(r, g, b, glowA), nvgRGBA(r, g, b, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, glowR)
    nvgFillPaint(vg, glow)
    nvgFill(vg)

    if t < 0.5 then
        local bt = t / 0.5
        local beamA = math.floor(230 * (1 - bt))
        local beamH = 70 + bt * 150
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - 5 - bt * 8, cy - beamH)
        nvgLineTo(vg, cx + 5 + bt * 8, cy - beamH)
        nvgLineTo(vg, cx + 26, cy + 6)
        nvgLineTo(vg, cx - 26, cy + 6)
        nvgClosePath(vg)
        local beam = nvgLinearGradient(vg, cx, cy - beamH, cx, cy,
            nvgRGBA(255, 248, 210, 0), nvgRGBA(255, 228, 120, beamA))
        nvgFillPaint(vg, beam)
        nvgFill(vg)
    end

    for i = 1, 2 do
        local rt = (t - (i - 1) * 0.1) / 0.72
        if rt > 0 and rt < 1 then
            local radius = 16 + rt * (size * 0.62 + i * 22)
            local a = math.floor(220 * (1 - rt) * (1 - rt))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, radius)
            nvgStrokeWidth(vg, 2.2 + (1 - rt) * 5)
            nvgStrokeColor(vg, nvgRGBA(255, 236, 168, a))
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, radius * 0.78)
            nvgStrokeWidth(vg, 1.6)
            nvgStrokeColor(vg, nvgRGBA(r, g, b, math.floor(a * 0.75)))
            nvgStroke(vg)
        end
    end

    if t < 0.72 then
        local rt = t / 0.72
        nvgSave(vg)
        nvgTranslate(vg, cx, cy)
        nvgRotate(vg, rt * 0.55)
        for i = 1, 10 do
            local ang = (i - 1) / 10 * math.pi * 2
            local inner = 18
            local len = 30 + rt * (58 + (i % 3) * 14)
            local a = math.floor(170 * (1 - rt))
            nvgBeginPath(vg)
            nvgMoveTo(vg, math.cos(ang) * inner, math.sin(ang) * inner)
            nvgLineTo(vg, math.cos(ang) * len, math.sin(ang) * len)
            nvgStrokeWidth(vg, 1.4 + (1 - rt) * 2.4)
            nvgStrokeColor(vg, nvgRGBA(255, 232, 150, a))
            nvgStroke(vg)
        end
        nvgRestore(vg)
    end

    for i = 1, 14 do
        local ang = (i - 1) / 14 * math.pi * 2 + 0.35
        local dist = 8 + t * (62 + (i % 4) * 16)
        local sx = cx + math.cos(ang) * dist
        local sy = cy + math.sin(ang) * dist * 0.7 - (1 - t) * 28
        local sa = math.floor(255 * (1 - t) * (1 - t * 0.25))
        local tail = 16 * (1 - t)
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, sy)
        nvgLineTo(vg, sx - math.cos(ang) * tail, sy - math.sin(ang) * tail * 0.7)
        nvgStrokeWidth(vg, 1.8)
        nvgStrokeColor(vg, nvgRGBA(255, 248, 220, sa))
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, 1.6 + (1 - t) * 2.4)
        nvgFillColor(vg, nvgRGBA(255, 255, 240, sa))
        nvgFill(vg)
    end

    if t < 0.26 then
        local fa = math.floor(210 * (1 - t / 0.26))
        local fr = 18 + (t / 0.26) * 40
        local flash = nvgRadialGradient(vg, cx, cy, 2, fr,
            nvgRGBA(255, 255, 245, fa), nvgRGBA(255, 220, 120, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, fr)
        nvgFillPaint(vg, flash)
        nvgFill(vg)
    end
end

--- 图标上层扫光
---@param vg any
---@param cx number
---@param cy number
---@param t number 单件进度 0~1
---@param size number 图标边长
function RewardCascade.glint(vg, cx, cy, t, size)
    if t < 0.18 or t > 0.82 then return end
    local gt = (t - 0.18) / 0.64
    local glide = -size * 0.55 + gt * size * 1.2
    local a = math.floor(150 * math.sin(gt * math.pi))
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, -0.55)
    nvgBeginPath(vg)
    nvgRect(vg, glide - 10, -size * 0.55, 18, size * 1.1)
    nvgFillColor(vg, nvgRGBA(255, 255, 245, a))
    nvgFill(vg)
    nvgRestore(vg)
end

--- 出场前的预告框（快到该件时闪一下金框）
---@param vg any
---@param cx number
---@param cy number
---@param lead number 距离出场还有多少秒（负数=已过出场时刻，不画）
---@param size number 图标边长
function RewardCascade.anticipate(vg, cx, cy, lead, size)
    if lead <= -0.08 then return end
    local a = math.floor(110 * ((lead + 0.08) / 0.08))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - size * 0.42, cy - size * 0.42, size * 0.84, size * 0.84, 14)
    nvgStrokeWidth(vg, 2)
    nvgStrokeColor(vg, nvgRGBA(247, 220, 120, a))
    nvgStroke(vg)
end

--- 施加出场变换（缩放回弹 + 摇摆 + 上浮）。调用方负责 nvgSave/nvgRestore。
---@param vg any
---@param cx number
---@param cy number
---@param t number 单件进度 0~1
---@param alpha number 额外透明度 0~1
---@param lift number|nil 上浮距离（默认 -56）
function RewardCascade.applyPop(vg, cx, cy, t, alpha, lift)
    local appear = math.min(1, t / 0.16)
    local pop = math.min(1, t / 0.68)
    local iconScale = 0.16 + 0.84 * RewardCascade.easeOutBack(pop)
    if iconScale < 0.04 then iconScale = 0.04 end
    local wobble = math.sin(t * math.pi * 2.4) * (1 - math.min(1, t)) * 0.2
    local liftDist = (1 - RewardCascade.easeOutCubic(math.min(1, t / 0.5))) * (lift or -56)
    nvgGlobalAlpha(vg, alpha * appear)
    nvgTranslate(vg, cx, cy + liftDist)
    nvgRotate(vg, wobble)
    nvgScale(vg, iconScale, iconScale)
    nvgTranslate(vg, -cx, -cy)
end

return RewardCascade
