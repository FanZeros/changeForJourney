-- 招募表现时间轴：只采样已完成的抽奖结果，不调用随机、扣费、发奖或存档。
local M = {}
M.INTRO_DURATION = 1.8
M.CARD_DURATION = 0.66
M.CARD_DELAY = 0.12
M.FADE_DURATION = 0.35

local function clamp(value)
    return math.max(0, math.min(1, value))
end

local function smooth(value)
    local t = clamp(value)
    return t * t * (3 - 2 * t)
end

function M.cardSpan(count)
    return M.CARD_DURATION + math.max(0, count - 1) * M.CARD_DELAY
end

-- 聚光、开门、退场交叠；时间源由宿主持有，不在 draw 中推进。
function M.intro(elapsed)
    local t = math.max(0, elapsed)
    local charge = smooth(t / 0.8)
    local opening = smooth((t - 0.72) / 0.72)
    local vanish = smooth((t - 1.35) / 0.45)
    return {
        charge = charge, opening = opening, alpha = 1 - vanish,
        ringAngle = t * 0.38 + opening * 0.45,
        sealScale = 0.84 + charge * 0.16 + opening * 0.36,
        sealAlpha = 1 - smooth((t - 0.72) / 0.4),
        light = charge * (1 - vanish),
    }
end

-- 每张卡先落位再绕纵轴翻开；横向缩放不降到0，避免退化变换。
function M.card(elapsed, index)
    local localT = elapsed - (index - 1) * M.CARD_DELAY
    local t = clamp(localT / M.CARD_DURATION)
    local arrival = 1 - (1 - clamp(t / 0.45)) ^ 3
    local flip = smooth((t - 0.28) / 0.60)
    local front = flip >= 0.5
    local scaleX = math.max(0.045, math.abs(math.cos(flip * math.pi)))
    local glowT = clamp((t - 0.55) / 0.45)
    return {
        visible = localT > 0, front = front, alpha = arrival,
        offsetY = 170 * (1 - arrival), scaleX = scaleX,
        scale = 0.88 + arrival * 0.12,
        glow = front and math.sin(glowT * math.pi) or 0,
        settled = t >= 1,
    }
end

-- 品质只影响表现，英雄碎片/资源亦保持实际结果品质，不假造高稀有角色。
function M.color(quality)
    if quality == 4 then return { 236, 119, 92 } end
    if quality == 3 then return { 240, 199, 112 } end
    if quality == 2 then return { 178, 143, 221 } end
    if quality == 1 then return { 127, 177, 190 } end
    return { 183, 178, 164 }
end

return M
