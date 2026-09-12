-- ============================================================================
-- SpeechBubble - 战斗台词气泡系统
-- 在角色卡片上方绘制对话气泡，支持淡入/保持/淡出动画
-- ============================================================================

local DC = require("config.DialogueConfig")

local SpeechBubble = {}

-- ======================== 常量 ========================

-- 气泡外观（漫画风格）
local BUBBLE_MAX_W       = 380       -- 气泡最大宽度
local BUBBLE_PAD_H       = 32        -- 左右内边距
local BUBBLE_PAD_V       = 22        -- 上下内边距
local BUBBLE_RADIUS      = 18        -- 圆角半径
local BUBBLE_FONT_SIZE   = 28        -- 字体大小
local BUBBLE_LINE_HEIGHT = 38        -- 行高
local BUBBLE_ARROW_W     = 18        -- 箭头底边宽度
local BUBBLE_ARROW_H     = 20        -- 箭头高度
local BUBBLE_ARROW_OFF_X = 10        -- 箭头相对气泡中心水平偏移
local BUBBLE_OFFSET_Y    = -240      -- 气泡底部相对卡片中心的 Y 偏移（负=向上）

-- 漫画风配色
local BUBBLE_FILL_CLR    = { 255, 255, 255 }      -- 纯白填充
local BUBBLE_STROKE_CLR  = { 30, 30, 30 }          -- 深灰近黑描边
local BUBBLE_TEXT_CLR    = { 30, 30, 30 }           -- 深灰近黑文字
local BUBBLE_STROKE_W    = 4                        -- 描边粗细
local BUBBLE_SHADOW_OFF  = 5                        -- 阴影偏移
local BUBBLE_SHADOW_ALPHA = 0.18                    -- 阴影透明度

-- 动画时间
local POP_DURATION       = 0.25      -- 弹出缩放时长
local HOLD_DURATION      = 2.5       -- 保持时长（短台词）
local HOLD_PER_CHAR      = 0.06      -- 每个字符额外保持时间
local FADE_OUT_DURATION  = 0.5       -- 淡出时长
local FLOAT_AMPLITUDE    = 8         -- 浮动幅度（像素）
local FLOAT_SPEED        = 2.2       -- 浮动速度（rad/s）

-- 冷却时间（防止频繁触发）
local COOLDOWNS = {
    entry   = 0.0,   -- 入场无冷却
    crit    = 8.0,   -- 暴击冷却
    kill    = 5.0,   -- 击杀冷却
    death   = 0.0,   -- 阵亡无冷却
    victory = 0.0,   -- 胜利无冷却
}

-- 触发概率（0~1，1.0=必定触发）
local TRIGGER_CHANCE = {
    entry   = 1.0,   -- 入场必定触发
    crit    = 0.35,  -- 暴击 35% 概率
    kill    = 0.40,  -- 击杀 40% 概率
    death   = 0.80,  -- 阵亡 80% 概率
    victory = 1.0,   -- 胜利必定触发
}

-- 快速淡出时长（被新气泡抢占时的旧气泡消失速度）
local DISMISS_DURATION = 0.25

-- 触发优先级（数字越大优先级越高，高优先级可打断低优先级）
local PRIORITIES = {
    entry   = 1,
    crit    = 2,
    kill    = 3,
    victory = 4,
    death   = 5,
}

-- ======================== 状态 ========================

---@class BubbleEntry
---@field text string            显示文字
---@field unit table             关联的战斗单位
---@field triggerType string     触发类型
---@field timer number           已过时间
---@field totalDuration number   总时长（fadeIn + hold + fadeOut）
---@field holdDuration number    保持时长
---@field priority number        优先级

-- 当前活跃气泡列表
---@type BubbleEntry[]
local activeBubbles = {}

-- 每个单位的冷却追踪: cooldownTimers[unit][triggerType] = remainingTime
local cooldownTimers = {}

-- 上下文引用
local getCardCX           = nil  -- function(units, index) -> cx
local getAllies            = nil  -- function() -> allies
local getCardAnimOffsetY  = nil  -- function(unit) -> offsetY
local getChargeOffsetY    = nil  -- function(unit, isAlly) -> offsetY
local ALLY_CARD_CY        = 1760
local CARD_H              = 438

-- ======================== 初始化 ========================

--- 注入上下文依赖
---@param context table
function SpeechBubble.init(context)
    getCardCX          = context.getCardCX
    getAllies           = context.getAllies
    getCardAnimOffsetY = context.getCardAnimOffsetY
    getChargeOffsetY   = context.getChargeOffsetY
    ALLY_CARD_CY       = context.ALLY_CARD_CY or ALLY_CARD_CY
    CARD_H             = context.CARD_H or CARD_H
end

-- ======================== 触发 ========================

--- 将气泡设为快速淡出状态（被新气泡抢占时调用）
---@param b BubbleEntry
local function dismissBubble(b)
    -- 直接跳到淡出阶段起点，且缩短淡出时长
    local fadeStart = POP_DURATION + b.holdDuration
    b.timer = fadeStart
    b.totalDuration = fadeStart + DISMISS_DURATION
    b.holdDuration = 0   -- 不再保持
    b.dismissed = true
end

--- 触发台词气泡
---@param unit table       战斗单位（必须有 heroId 字段）
---@param triggerType string  "entry"|"crit"|"kill"|"death"|"victory"
function SpeechBubble.trigger(unit, triggerType)
    if not unit or not unit.heroId then return end

    -- 查询台词
    local text = DC.get(unit.heroId, triggerType)
    if not text then return end

    -- 检查冷却
    local unitCDs = cooldownTimers[unit]
    if unitCDs and unitCDs[triggerType] and unitCDs[triggerType] > 0 then
        return
    end

    -- 概率判断（冷却通过后再掷骰）
    local chance = TRIGGER_CHANCE[triggerType] or 1.0
    if chance < 1.0 and math.random() > chance then
        return
    end

    local priority = PRIORITIES[triggerType] or 0

    -- 查找该单位是否已有气泡
    for i, b in ipairs(activeBubbles) do
        if b.unit == unit then
            -- 已有气泡：高优先级才能打断
            if priority <= b.priority then
                return
            end
            -- 打断旧气泡
            table.remove(activeBubbles, i)
            break
        end
    end

    -- 全局独占：将所有其他角色的气泡快速淡出
    for _, b in ipairs(activeBubbles) do
        if not b.dismissed then
            dismissBubble(b)
        end
    end

    -- 计算保持时长（按字数动态调整）
    local charCount = utf8.len(text) or #text
    local holdTime = math.max(HOLD_DURATION, charCount * HOLD_PER_CHAR)
    local totalTime = POP_DURATION + holdTime + FADE_OUT_DURATION

    -- 创建气泡
    activeBubbles[#activeBubbles + 1] = {
        text          = text,
        unit          = unit,
        triggerType   = triggerType,
        timer         = 0,
        totalDuration = totalTime,
        holdDuration  = holdTime,
        priority      = priority,
        dismissed     = false,
    }

    -- 设置冷却
    local cd = COOLDOWNS[triggerType] or 0
    if cd > 0 then
        if not cooldownTimers[unit] then
            cooldownTimers[unit] = {}
        end
        cooldownTimers[unit][triggerType] = cd
    end
end

-- ======================== 更新 ========================

--- 每帧更新
---@param dt number
function SpeechBubble.update(dt)
    -- 更新冷却
    for unit, cds in pairs(cooldownTimers) do
        for ttype, remaining in pairs(cds) do
            cds[ttype] = remaining - dt
            if cds[ttype] <= 0 then
                cds[ttype] = nil
            end
        end
        -- 清理空表
        if not next(cds) then
            cooldownTimers[unit] = nil
        end
    end

    -- 更新气泡计时器，移除已结束的
    local i = 1
    while i <= #activeBubbles do
        local b = activeBubbles[i]
        b.timer = b.timer + dt
        if b.timer >= b.totalDuration then
            table.remove(activeBubbles, i)
        else
            i = i + 1
        end
    end
end

-- ======================== 绘制 ========================

--- 计算气泡当前动画状态（漫画风：弹出缩放 + 浮动 + 淡出）
---@param b BubbleEntry
---@return number alpha (0~255)
---@return number scale (缩放比例)
---@return number floatY (浮动偏移)
local function calcBubbleAnim(b)
    local t = b.timer
    local totalDur = b.totalDuration

    if t < 0 or t > totalDur then
        return 0, 0, 0
    end

    -- easeOutBack 弹出缩放
    local scale
    if t < POP_DURATION then
        local p = t / POP_DURATION
        local c1 = 1.70158
        local c3 = c1 + 1
        scale = 1 + c3 * (p - 1) ^ 3 + c1 * (p - 1) ^ 2
    else
        scale = 1.0
    end

    -- 淡出 alpha
    local fadeStart = POP_DURATION + b.holdDuration
    local alpha = 255
    if t > fadeStart then
        local fadeProgress = math.min(1.0, (t - fadeStart) / FADE_OUT_DURATION)
        alpha = math.floor(255 * (1 - fadeProgress))
    end
    alpha = math.max(0, math.min(255, alpha))

    -- 持续浮动（正弦波）
    local floatY = math.sin(t * FLOAT_SPEED) * FLOAT_AMPLITUDE

    return alpha, scale, floatY
end

--- 简易自动换行：将文本按最大宽度拆成多行
---@param vg any
---@param text string
---@param maxW number
---@return string[]
---@return number maxLineW  实际最宽行的宽度
local function wrapText(vg, text, maxW)
    local lines = {}
    local maxLineW = 0
    local currentLine = ""
    local currentW = 0

    -- 按 UTF-8 字符逐字遍历
    for _, code in utf8.codes(text) do
        local ch = utf8.char(code)
        -- 换行符处理
        if ch == "\n" then
            lines[#lines + 1] = currentLine
            if currentW > maxLineW then maxLineW = currentW end
            currentLine = ""
            currentW = 0
        else
            local testLine = currentLine .. ch
            local _, tb = nvgTextBounds(vg, 0, 0, testLine)
            local w = tb[3] - tb[1]
            if w > maxW and #currentLine > 0 then
                lines[#lines + 1] = currentLine
                if currentW > maxLineW then maxLineW = currentW end
                currentLine = ch
                local _, cb = nvgTextBounds(vg, 0, 0, ch)
                currentW = cb[3] - cb[1]
            else
                currentLine = testLine
                currentW = w
            end
        end
    end
    -- 最后一行
    if #currentLine > 0 then
        lines[#lines + 1] = currentLine
        if currentW > maxLineW then maxLineW = currentW end
    end

    return lines, maxLineW
end

--- 查找单位在 allies 数组中的索引
---@param unit table
---@return number|nil index
local function findUnitIndex(unit)
    if not getAllies then return nil end
    local allies = getAllies()
    for i, u in ipairs(allies) do
        if u == unit then return i end
    end
    return nil
end

--- 绘制所有气泡（漫画风格）
---@param vg any NanoVG 上下文
function SpeechBubble.draw(vg)
    if #activeBubbles == 0 then return end
    if not getAllies or not getCardCX then return end

    local allies = getAllies()

    local fc = BUBBLE_FILL_CLR
    local sc = BUBBLE_STROKE_CLR
    local tc = BUBBLE_TEXT_CLR

    for _, b in ipairs(activeBubbles) do
        local alpha, scale, floatY = calcBubbleAnim(b)
        if alpha <= 0 then goto continue end

        -- 找到单位的屏幕位置
        local idx = findUnitIndex(b.unit)
        if not idx then goto continue end

        local cx = getCardCX(allies, idx)
        local baseCY = ALLY_CARD_CY
        local animOff = getCardAnimOffsetY and getCardAnimOffsetY(b.unit) or 0
        local chargeOff = getChargeOffsetY and getChargeOffsetY(b.unit, true) or 0
        local cy = baseCY + animOff + chargeOff

        -- 气泡锚点：卡片上方
        local anchorX = cx
        local anchorY = cy + BUBBLE_OFFSET_Y + floatY

        -- 自动换行计算
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BUBBLE_FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

        local lines, maxLineW = wrapText(vg, b.text, BUBBLE_MAX_W - BUBBLE_PAD_H * 2)
        local lineCount = #lines
        if lineCount == 0 then goto continue end

        local textW = maxLineW
        local textH = lineCount * BUBBLE_LINE_HEIGHT
        local bubbleW = textW + BUBBLE_PAD_H * 2
        local bubbleH = textH + BUBBLE_PAD_V * 2

        -- 气泡矩形位置（居中于锚点 X，底部在锚点 Y）
        local bx = anchorX - bubbleW * 0.5
        local by = anchorY - bubbleH - BUBBLE_ARROW_H

        -- 边界裁剪
        if bx < 10 then bx = 10 end
        if bx + bubbleW > 1070 then bx = 1070 - bubbleW end

        -- 气泡视觉中心（用于缩放基点）
        local bubbleCX = bx + bubbleW * 0.5
        local bubbleCY = by + bubbleH * 0.5

        nvgSave(vg)

        -- 应用 easeOutBack 弹出缩放（以气泡中心为基点）
        nvgTranslate(vg, bubbleCX, bubbleCY)
        nvgScale(vg, scale, scale)
        nvgTranslate(vg, -bubbleCX, -bubbleCY)

        -- 1) 阴影（偏移的深色圆角矩形）
        local so = BUBBLE_SHADOW_OFF
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx + so, by + so, bubbleW, bubbleH, BUBBLE_RADIUS)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(alpha * BUBBLE_SHADOW_ALPHA)))
        nvgFill(vg)

        -- 2) 主体（纯白圆角矩形）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, bubbleW, bubbleH, BUBBLE_RADIUS)
        nvgFillColor(vg, nvgRGBA(fc[1], fc[2], fc[3], alpha))
        nvgFill(vg)

        -- 3) 主体描边（漫画风粗线条）
        nvgStrokeWidth(vg, BUBBLE_STROKE_W)
        nvgStrokeColor(vg, nvgRGBA(sc[1], sc[2], sc[3], alpha))
        nvgStroke(vg)

        -- 4) 尾巴三角形（指向角色）
        local tailTipX = anchorX + BUBBLE_ARROW_OFF_X
        -- 限制箭头不超出气泡边界
        local tailMinX = bx + BUBBLE_RADIUS + BUBBLE_ARROW_W * 0.5
        local tailMaxX = bx + bubbleW - BUBBLE_RADIUS - BUBBLE_ARROW_W * 0.5
        if tailTipX < tailMinX then tailTipX = tailMinX end
        if tailTipX > tailMaxX then tailTipX = tailMaxX end

        local tailBaseY = by + bubbleH - 2  -- 尾巴从气泡底部稍微内缩开始
        local tailTipY  = tailBaseY + BUBBLE_ARROW_H

        -- 尾巴填充
        nvgBeginPath(vg)
        nvgMoveTo(vg, tailTipX - BUBBLE_ARROW_W * 0.5, tailBaseY)
        nvgLineTo(vg, tailTipX, tailTipY)
        nvgLineTo(vg, tailTipX + BUBBLE_ARROW_W * 0.5, tailBaseY)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(fc[1], fc[2], fc[3], alpha))
        nvgFill(vg)

        -- 尾巴描边（左右两条边，不画顶边避免和气泡主体重叠）
        nvgBeginPath(vg)
        nvgMoveTo(vg, tailTipX - BUBBLE_ARROW_W * 0.5, tailBaseY)
        nvgLineTo(vg, tailTipX, tailTipY)
        nvgLineTo(vg, tailTipX + BUBBLE_ARROW_W * 0.5, tailBaseY)
        nvgStrokeWidth(vg, BUBBLE_STROKE_W)
        nvgStrokeColor(vg, nvgRGBA(sc[1], sc[2], sc[3], alpha))
        nvgStroke(vg)

        -- 尾巴与主体接缝覆盖（用白色矩形盖住重叠区描边）
        nvgBeginPath(vg)
        nvgRect(vg, tailTipX - BUBBLE_ARROW_W * 0.5 + 2, tailBaseY - 3,
                BUBBLE_ARROW_W - 4, 6)
        nvgFillColor(vg, nvgRGBA(fc[1], fc[2], fc[3], alpha))
        nvgFill(vg)

        -- 5) 文字（深色）
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BUBBLE_FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], alpha))

        for li, line in ipairs(lines) do
            local tx = bx + BUBBLE_PAD_H
            local ty = by + BUBBLE_PAD_V + (li - 1) * BUBBLE_LINE_HEIGHT
            nvgText(vg, tx, ty, line)
        end

        nvgRestore(vg)

        ::continue::
    end
end

-- ======================== 工具 ========================

--- 重置所有气泡和冷却（切关/重置战斗时调用）
function SpeechBubble.reset()
    activeBubbles = {}
    cooldownTimers = {}
end

--- 获取当前活跃气泡数
---@return number
function SpeechBubble.getActiveCount()
    return #activeBubbles
end

return SpeechBubble
