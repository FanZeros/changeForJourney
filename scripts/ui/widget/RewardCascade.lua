-- ============================================================================
-- RewardCascade - 奖励逐件弹出动画（共用）
-- ----------------------------------------------------------------------------
-- 从 RewardPopup 抽出的「一件一件获得」动画原语，供任意奖励网格复用：
--   · 时间轴：第 idx 件的出场时刻 / 进度 / 已完成判定 / 已出场件数
--   · 绘制：铜金辉光、短流星、金属薄扫、出场前的预告框
--   · 变换：收敛的缩放回弹 + 轻微摇摆 + 落位
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
---@field fastAfter number 前多少件使用常规间隔
---@field fasterAfter number|nil 前多少件之后使用最快间隔
---@field intervalFaster number|nil 最快间隔
---@field popDur number 单件弹出时长
---@field lead number 首件之前的停顿
---@field revealStart number 时间轴起点（time.elapsedTime）
local Timeline = {}
Timeline.__index = Timeline

--- 新建时间轴
---@param count number 奖励件数
---@param opts table|nil { interval, intervalTail, fastAfter, intervalFaster, fasterAfter, popDur, lead }
---@return RewardCascadeTimeline
function RewardCascade.new(count, opts)
    opts = opts or {}
    local self = setmetatable({}, Timeline)
    self.count        = math.max(0, math.floor(count or 0))
    self.interval     = opts.interval     or RewardCascade.INTERVAL
    self.intervalTail = opts.intervalTail or RewardCascade.INTERVAL_TAIL
    self.fastAfter    = opts.fastAfter    or RewardCascade.FAST_AFTER
    self.fasterAfter  = opts.fasterAfter
    self.intervalFaster = opts.intervalFaster
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
    if self.fasterAfter and idx > self.fasterAfter then
        return self.intervalFaster or self.intervalTail
    end
    if idx > self.fastAfter then return self.intervalTail end
    return self.interval
end

--- 第 idx 件的出场时刻（第 1 件为 0）
---@param idx number
---@return number
function Timeline:startAt(idx)
    if idx <= 1 then return 0 end
    -- 按三个间隔区段直接求和，避免网格逐件查询时反复遍历前面的奖励。
    local normalEnd = math.max(1, math.floor(self.fastAfter))
    if self.fasterAfter then
        normalEnd = math.min(normalEnd, math.max(1, math.floor(self.fasterAfter)))
    end
    local normalCount = math.max(0, math.min(idx, normalEnd) - 1)
    local tailEnd = self.fasterAfter and math.max(1, math.floor(self.fasterAfter)) or idx
    local tailCount = math.max(0, math.min(idx, tailEnd) - normalEnd)
    local fasterCount = self.fasterAfter and math.max(0, idx - tailEnd) or 0
    return normalCount * self.interval + tailCount * self.intervalTail
        + fasterCount * (self.intervalFaster or self.intervalTail)
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
    -- 时间轴单调，二分定位最新出场项；保留原来的浮点边界容差。
    local low, high = 1, self.count
    local shown = 0
    while low <= high do
        local mid = math.floor((low + high) * 0.5)
        if e + 0.0001 >= self:startAt(mid) then
            shown = mid
            low = mid + 1
        else
            high = mid - 1
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

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function valid(vg, cx, cy, t, size)
    return vg ~= nil and finite(cx) and finite(cy) and finite(t) and finite(size) and size > 0
end

--- 铜金余辉与六枚短流星（图标下层）。纯时间采样，不保留粒子队列。
---@param vg any
---@param cx number
---@param cy number
---@param t number 单件进度，首尾均无残留
---@param size number
---@param r number
---@param g number
---@param b number
function RewardCascade.burst(vg, cx, cy, t, size, r, g, b)
    if not valid(vg, cx, cy, t, size) or t <= 0 or t >= 1 then return end
    if not finite(r) or not finite(g) or not finite(b) then return end
    -- 品质色仍可辨认，压住白色核心，沿既有暗铁/旧铜色系。
    local cr = math.floor(math.max(0, math.min(255, r)) * 0.45 + 201 * 0.55)
    local cg = math.floor(math.max(0, math.min(255, g)) * 0.45 + 151 * 0.55)
    local cb = math.floor(math.max(0, math.min(255, b)) * 0.45 + 59 * 0.55)
    local envelope = math.sin(t * math.pi) * (1 - t)
    local radius = size * (0.40 + 0.34 * RewardCascade.easeOutCubic(t))
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, radius)
    nvgFillPaint(vg, nvgRadialGradient(vg, cx, cy, size * 0.10, radius,
        nvgRGBA(cr, cg, cb, math.floor(104 * envelope)), nvgRGBA(cr, cg, cb, 0)))
    nvgFill(vg)

    -- 一道薄落位环，不恢复旋转射线或粗大光柱。
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, size * (0.36 + 0.28 * t))
    nvgStrokeWidth(vg, 1.1)
    nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, math.floor(88 * envelope)))
    nvgStroke(vg)
    for i = 1, 6 do
        local angle = i * 2.399963 + 0.25
        local distance = size * (0.32 + t * (0.34 + (i % 3) * 0.05))
        local x = cx + math.cos(angle) * distance
        local y = cy + math.sin(angle) * distance * 0.7 - size * 0.08 * (1 - t)
        local tail = size * 0.065 * (1 - t)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - math.cos(angle) * tail, y - math.sin(angle) * tail * 0.7)
        nvgLineTo(vg, x, y)
        nvgStrokeWidth(vg, 1.2)
        nvgStrokeColor(vg, nvgRGBA(215, 174, 100, math.floor(150 * envelope)))
        nvgStroke(vg)
    end
    nvgRestore(vg)
end

--- 图标上层金属薄扫：仅在原扫光窗口内，裁剪到图标，避开外侧数量。
---@param vg any
---@param cx number
---@param cy number
---@param t number
---@param size number
function RewardCascade.glint(vg, cx, cy, t, size)
    if not valid(vg, cx, cy, t, size) or t <= 0.18 or t >= 0.82 then return end
    local gt = (t - 0.18) / 0.64
    local glide = -size * 0.58 + gt * size * 1.16
    local band = math.max(1, size * 0.035)
    nvgSave(vg)
    nvgIntersectScissor(vg, cx - size * 0.5, cy - size * 0.5, size, size)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, -0.42)
    nvgBeginPath(vg)
    nvgRect(vg, glide - band * 0.5, -size * 0.65, band, size * 1.3)
    nvgFillColor(vg, nvgRGBA(221, 185, 125, math.floor(88 * math.sin(gt * math.pi))))
    nvgFill(vg)
    nvgRestore(vg)
end

--- 出场前80ms预告框。lead沿现有调用契约为 elapsed-startAt（负数=尚未出场）。
---@param vg any
---@param cx number
---@param cy number
---@param lead number
---@param size number
function RewardCascade.anticipate(vg, cx, cy, lead, size)
    if not valid(vg, cx, cy, lead, size) or lead <= -0.08 or lead >= 0 then return end
    local pulse = math.sin((lead + 0.08) / 0.08 * math.pi)
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - size * 0.42, cy - size * 0.42, size * 0.84, size * 0.84,
        math.min(8, size * 0.06))
    nvgStrokeWidth(vg, 1.1)
    nvgStrokeColor(vg, nvgRGBA(201, 151, 59, math.floor(72 * pulse)))
    nvgStroke(vg)
    nvgRestore(vg)
end

--- 收敛落位；大模式只调用此原语，也实际受益。调用方负责 Save/Restore。
--- 数量随图标最小76%入场，不再缩至16%；0.22秒原结束时刻不变。
---@param vg any
---@param cx number
---@param cy number
---@param t number
---@param alpha number
---@param lift number|nil 默认 -28，显式距离仍沿用调用值
function RewardCascade.applyPop(vg, cx, cy, t, alpha, lift)
    if vg == nil or not finite(cx) or not finite(cy) or not finite(t) or not finite(alpha) then return end
    if lift ~= nil and not finite(lift) then return end
    local progress = math.max(0, math.min(1, t))
    local appear = math.min(1, progress / 0.16)
    local pop = math.min(1, progress / 0.68)
    local iconScale = 0.76 + 0.24 * RewardCascade.easeOutBack(pop)
    local wobble = math.sin(progress * math.pi * 2.4) * (1 - progress) * 0.035
    local liftDist = (1 - RewardCascade.easeOutCubic(math.min(1, progress / 0.5))) * (lift or -28)
    nvgGlobalAlpha(vg, math.max(0, math.min(1, alpha)) * appear)
    nvgTranslate(vg, cx, cy + liftDist)
    nvgRotate(vg, wobble)
    nvgScale(vg, iconScale, iconScale)
    nvgTranslate(vg, -cx, -cy)
end

return RewardCascade
