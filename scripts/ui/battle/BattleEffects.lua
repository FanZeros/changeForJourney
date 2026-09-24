-- ============================================================================
-- BattleEffects - 通用受击特效模块（NanoVG 绘制）
-- 根据被攻击单位的护甲类型播放对应的受击特效
-- 护甲类型: 1=皮甲 2=轻甲 3=重甲 4=板甲 5=布甲
-- ============================================================================

local BattleEffects = {}
-- [多实例] 活动特效列表随战斗 mount 切换; fxPool/particlePool 对象池全局共享
local function newFxState()
    return { effects = {} }
end
local BE_DEFAULT = newFxState()
local BE_BCS = BE_DEFAULT
-- [三行并行] 条带渲染缩放：粒子视觉尺寸 × fxScale（与卡牌缩放同步）
local fxScale = 1.0
function BattleEffects.setRenderScale(s) fxScale = s or 1.0 end

function BattleEffects.newFxState() return newFxState() end
function BattleEffects.mount(s) BE_BCS = s or BE_DEFAULT end
function BattleEffects.mountedState() return BE_BCS end


-- 活跃特效列表

-- ======================== 对象池 ========================
-- 避免每次命中都创建新 table，减少 GC 压力

local fxPool = {}         -- 回收的特效对象池
local particlePool = {}   -- 回收的粒子数组池

--- 从池中获取一个特效对象（或新建）
local function acquireFx()
    local n = #fxPool
    if n > 0 then
        local fx = fxPool[n]
        fxPool[n] = nil
        return fx
    end
    return {}
end

--- 回收特效对象到池中
local function releaseFx(fx)
    -- 回收子粒子数组
    if fx._dust then
        particlePool[#particlePool + 1] = fx._dust
        fx._dust = nil
    end
    if fx._sparks then
        particlePool[#particlePool + 1] = fx._sparks
        fx._sparks = nil
    end
    if fx._particles then
        particlePool[#particlePool + 1] = fx._particles
        fx._particles = nil
    end
    if fx._cracks then
        particlePool[#particlePool + 1] = fx._cracks
        fx._cracks = nil
    end
    if fx._debris then
        particlePool[#particlePool + 1] = fx._debris
        fx._debris = nil
    end
    if fx._shreds then
        particlePool[#particlePool + 1] = fx._shreds
        fx._shreds = nil
    end
    if fx._rays then
        particlePool[#particlePool + 1] = fx._rays
        fx._rays = nil
    end
    -- 清空引用字段
    fx.def = nil
    fxPool[#fxPool + 1] = fx
end

--- 从池中获取一个粒子数组（或新建），并重设大小
---@param count number 需要的粒子数
---@return table
local function acquireParticles(count)
    local n = #particlePool
    if n > 0 then
        local arr = particlePool[n]
        particlePool[n] = nil
        -- 截断多余元素
        for i = count + 1, #arr do
            arr[i] = nil
        end
        -- 确保元素存在（可能不够，需要补）
        for i = 1, count do
            if not arr[i] then arr[i] = {} end
        end
        return arr
    end
    local arr = {}
    for i = 1, count do arr[i] = {} end
    return arr
end

-- 外部上下文
local vg_ = nil

-- ======================== 特效定义 ========================

--- 特效类型注册表（key = armorType 数字）
local EFFECT_TYPES = {}

-- ============================================================================
-- 辅助：通用散射粒子生成（使用对象池）
-- ============================================================================
local function makeParticles(count, speedMin, speedMax, sizeMin, sizeMax)
    local ps = acquireParticles(count)
    for i = 1, count do
        local p = ps[i]
        p.angle = math.random() * math.pi * 2
        p.speed = speedMin + math.random() * (speedMax - speedMin)
        p.size  = sizeMin + math.random() * (sizeMax - sizeMin)
    end
    return ps
end

-- ============================================================================
-- 1 - 皮甲：钝击波纹 + 尘土飞溅（白色）
-- 设计思路：柔软材质的钝击感，同心弧波纹 + 团状尘土云，无尖锐线条
-- ============================================================================
EFFECT_TYPES[1] = {
    duration = 0.45,
    label    = "leather",

    setup = function(fx)
        -- 尘土团块（大椭圆/不规则团状，非圆形小点）— 使用对象池
        fx._dust = acquireParticles(7)
        for i = 1, 7 do
            local d = fx._dust[i]
            d.angle   = math.random() * math.pi * 2
            d.speed   = 50 + math.random() * 110
            d.rx      = 12 + math.random() * 18
            d.ry      = 8 + math.random() * 12
            d.rot     = math.random() * math.pi
            d.rotSpd  = (-1 + math.random() * 2) * 3
            d.gravity = 40 + math.random() * 40
        end
    end,

    draw = function(fx, vg, t)
        local tx, ty = fx.tgtX, fx.tgtY

        -- 1) 中心钝击闪光（极短 0~0.12，扁平椭圆形，区别于其他圆形闪光）
        if t < 0.12 then
            local fp = t / 0.12
            local fa
            if fp < 0.4 then
                fa = math.floor(220 * (fp / 0.4))
            else
                fa = math.floor(220 * (1 - (fp - 0.4) / 0.6))
            end
            local frx = 55 + 25 * fp   -- 横向更宽
            local fry = 30 + 15 * fp   -- 纵向较窄
            nvgSave(vg)
            nvgTranslate(vg, tx, ty)
            -- 用缩放做椭圆
            local flashPaint = nvgRadialGradient(vg,
                0, 0, frx * 0.15, frx,
                nvgRGBA(255, 246, 104, fa),
                nvgRGBA(255, 246, 104, 0))
            nvgBeginPath(vg)
            nvgEllipse(vg, 0, 0, frx, fry)
            nvgFillPaint(vg, flashPaint)
            nvgFill(vg)
            nvgRestore(vg)
        end

        -- 2) 尘土团块飞溅 (0.04~1.0，椭圆形团块带旋转和重力下坠)
        if t >= 0.04 and fx._dust then
            local dt2 = (t - 0.04) / 0.96
            local a = math.floor(180 * (1 - dt2 * 0.8))
            if a > 1 then
                for _, d in ipairs(fx._dust) do
                    local dist = d.speed * dt2
                    local px = tx + math.cos(d.angle) * dist
                    local py = ty + math.sin(d.angle) * dist + d.gravity * dt2 * dt2
                    local scl = 1 - dt2 * 0.5
                    local rx = d.rx * scl
                    local ry = d.ry * scl
                    local curRot = d.rot + d.rotSpd * dt2

                    if rx > 1 and ry > 1 then
                        nvgSave(vg)
                        nvgTranslate(vg, px, py)
                        nvgRotate(vg, curRot)
                        nvgBeginPath(vg)
                        nvgEllipse(vg, 0, 0, rx, ry)
                        nvgFillColor(vg, nvgRGBA(255, 246, 104, a))
                        nvgFill(vg)
                        nvgRestore(vg)
                    end
                end
            end
        end
    end,
}

-- ============================================================================
-- 2 - 轻甲：金属碎片飞溅 + 细长火花线（白色）×0.85
-- ============================================================================
EFFECT_TYPES[2] = {
    duration = 0.35,
    label    = "light",

    setup = function(fx)
        fx._sparks = acquireParticles(8)
        for i = 1, 8 do
            local s = fx._sparks[i]
            s.angle  = math.rad(-90 + math.random() * 180)
            s.length = 68 + math.random() * 102
            s.speed  = 136 + math.random() * 170
        end
        fx._particles = makeParticles(8, 85, 187, 3.4, 8.5)
    end,

    draw = function(fx, vg, t)
        local tx, ty = fx.tgtX, fx.tgtY

        -- 火花线 (0~0.8)
        if t < 0.8 then
            local p = t / 0.8
            local ep = 1 - (1 - p) * (1 - p)
            local alpha = math.floor(250 * (1 - p * 0.5))

            for _, sp in ipairs(fx._sparks) do
                local dist = sp.speed * ep
                local cx = tx + math.cos(sp.angle) * dist
                local cy = ty + math.sin(sp.angle) * dist
                local len = sp.length * (1 - p * 0.4)
                local dx = math.cos(sp.angle) * len * 0.5
                local dy = math.sin(sp.angle) * len * 0.5

                nvgBeginPath(vg)
                nvgMoveTo(vg, cx - dx, cy - dy)
                nvgLineTo(vg, cx + dx, cy + dy)
                nvgStrokeWidth(vg, 6 * (1 - p * 0.3))
                nvgStrokeColor(vg, nvgRGBA(255, 246, 104, alpha))
                nvgStroke(vg)
            end
        end

        -- 中心闪点 (0~0.4)
        if t < 0.4 then
            local fp = t / 0.4
            local fa = math.floor(255 * (1 - fp))
            local fr = 31 + 37 * fp
            local flashPaint = nvgRadialGradient(vg,
                tx, ty, fr * 0.1, fr,
                nvgRGBA(255, 246, 104, fa),
                nvgRGBA(255, 246, 104, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, tx, ty, fr)
            nvgFillPaint(vg, flashPaint)
            nvgFill(vg)
        end

        -- 碎片粒子（合批：同色圆形合并为单个 path）
        if t >= 0.03 and fx._particles then
            local pt = (t - 0.03) / 0.97
            local a = math.floor(200 * (1 - pt))
            if a > 1 then
                nvgBeginPath(vg)
                local hasAny = false
                for _, p in ipairs(fx._particles) do
                    local dist = p.speed * pt
                    local px = tx + math.cos(p.angle) * dist
                    local py = ty + math.sin(p.angle) * dist
                    local sz = (p.size * (1 - pt * 0.4)) * fxScale
                    if sz > 1 then
                        nvgCircle(vg, px, py, sz)
                        hasAny = true
                    end
                end
                if hasAny then
                    nvgFillColor(vg, nvgRGBA(255, 246, 104, a))
                    nvgFill(vg)
                end
            end
        end
    end,
}

-- ============================================================================
-- 3 - 重甲：金属钝击凹陷 + 短促冲击线 + 碎片弹飞（白色）×1.5
-- 设计思路：集中在受击点的短促撞击感，不做大范围扩散
-- ============================================================================
EFFECT_TYPES[3] = {
    duration = 0.35,
    label    = "heavy",

    setup = function(fx)
        -- 4~6 根从中心向外的短冲击线（模拟凹陷裂纹）
        local count = 4 + math.random(0, 2)
        fx._cracks = acquireParticles(count)
        local baseAngle = math.random() * math.pi * 2
        for i = 1, count do
            local c = fx._cracks[i]
            c.angle  = baseAngle + (i - 1) * (math.pi * 2 / count) + math.rad(-15 + math.random() * 30)
            c.innerR = 15 + math.random() * 15
            c.outerR = 75 + math.random() * 60
        end
        -- 少量碎片（5~7 个小方块）
        local dCount = 5 + math.random(0, 2)
        fx._debris = acquireParticles(dCount)
        for i = 1, dCount do
            local d = fx._debris[i]
            d.angle  = math.random() * math.pi * 2
            d.speed  = 150 + math.random() * 210
            d.size   = 7.5 + math.random() * 12
            d.rotSpd = (-1 + math.random() * 2) * 8
        end
    end,

    draw = function(fx, vg, t)
        local tx, ty = fx.tgtX, fx.tgtY

        -- 1) 中心撞击闪光（极短 0~0.15，快速出现快速消失）
        if t < 0.15 then
            local fp = t / 0.15
            local fa
            if fp < 0.3 then
                fa = math.floor(255 * (fp / 0.3))
            else
                fa = math.floor(255 * (1 - (fp - 0.3) / 0.7))
            end
            local fr = 45 + 30 * fp
            local flashPaint = nvgRadialGradient(vg,
                tx, ty, fr * 0.15, fr,
                nvgRGBA(255, 246, 104, fa),
                nvgRGBA(255, 246, 104, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, tx, ty, fr)
            nvgFillPaint(vg, flashPaint)
            nvgFill(vg)
        end

        -- 2) 凹陷裂纹线（0~0.5，快速出现后停住并淡出）
        if t < 0.5 then
            local p = t / 0.5
            local extend = 1 - (1 - math.min(p * 2, 1)) * (1 - math.min(p * 2, 1))
            local alpha = math.floor(240 * (1 - p * 0.8))
            local thick = 12 * (1 - p * 0.5)

            for _, ck in ipairs(fx._cracks) do
                local dx = math.cos(ck.angle)
                local dy = math.sin(ck.angle)
                local r1 = ck.innerR * extend
                local r2 = ck.outerR * extend

                nvgBeginPath(vg)
                nvgMoveTo(vg, tx + dx * r1, ty + dy * r1)
                nvgLineTo(vg, tx + dx * r2, ty + dy * r2)
                nvgStrokeWidth(vg, thick)
                nvgStrokeColor(vg, nvgRGBA(255, 246, 104, alpha))
                nvgStroke(vg)
            end
        end

        -- 3) 中心凹陷圆弧（0~0.4，不扩散，固定大小，仅淡出）
        if t < 0.4 then
            local dp = t / 0.4
            local da = math.floor(180 * (1 - dp))
            local dRadius = 42 + 12 * dp
            nvgBeginPath(vg)
            nvgCircle(vg, tx, ty, dRadius)
            nvgStrokeWidth(vg, 7.5 * (1 - dp * 0.4))
            nvgStrokeColor(vg, nvgRGBA(255, 246, 104, da))
            nvgStroke(vg)
        end

        -- 4) 碎片弹飞（0.03~1.0，小方块从受击点弹出）
        if t >= 0.03 and fx._debris then
            local pt = (t - 0.03) / 0.97
            local a = math.floor(200 * (1 - pt))
            if a > 1 then
                for _, d in ipairs(fx._debris) do
                    local dist = d.speed * pt
                    local px = tx + math.cos(d.angle) * dist
                    local py = ty + math.sin(d.angle) * dist + 90 * pt * pt
                    local sz = (d.size * (1 - pt * 0.5)) * fxScale
                    local rot = d.rotSpd * pt

                    if sz > 1 then
                        nvgSave(vg)
                        nvgTranslate(vg, px, py)
                        nvgRotate(vg, rot)
                        nvgBeginPath(vg)
                        nvgRect(vg, -sz, -sz, sz * 2, sz * 2)
                        nvgFillColor(vg, nvgRGBA(255, 246, 104, a))
                        nvgFill(vg)
                        nvgRestore(vg)
                    end
                end
            end
        end
    end,
}

-- ============================================================================
-- 4 - 板甲：金属高亮反弹火花 + 环形震荡（白色）×0.65
-- ============================================================================
EFFECT_TYPES[4] = {
    duration = 0.40,
    label    = "plate",

    setup = function(fx)
        fx._sparks = acquireParticles(10)
        for i = 1, 10 do
            local s = fx._sparks[i]
            s.angle  = math.rad((i - 1) * 36 + math.random() * 20 - 10)
            s.length = 65 + math.random() * 65
            s.speed  = 117 + math.random() * 104
        end
        fx._particles = makeParticles(8, 52, 117, 3.9, 7.8)
    end,

    draw = function(fx, vg, t)
        local tx, ty = fx.tgtX, fx.tgtY

        -- 中心爆闪 (0~0.35)
        if t < 0.35 then
            local fp = t / 0.35
            local fa
            if fp < 0.3 then
                fa = math.floor(255 * (fp / 0.3))
            else
                fa = math.floor(255 * (1 - (fp - 0.3) / 0.7))
            end
            local fr = 26 + 45.5 * fp
            local flashPaint = nvgRadialGradient(vg,
                tx, ty, fr * 0.1, fr,
                nvgRGBA(255, 246, 104, fa),
                nvgRGBA(255, 246, 104, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, tx, ty, fr)
            nvgFillPaint(vg, flashPaint)
            nvgFill(vg)
        end

        -- 放射火花线 (0~0.8)
        if t < 0.8 then
            local p = t / 0.8
            local ep = 1 - (1 - p) * (1 - p)
            local alpha = math.floor(255 * (1 - p * 0.4))

            for _, sp in ipairs(fx._sparks) do
                local dist = sp.speed * ep
                local cx = tx + math.cos(sp.angle) * dist
                local cy = ty + math.sin(sp.angle) * dist
                local len = sp.length * (1 - p * 0.5)
                local dx = math.cos(sp.angle) * len * 0.5
                local dy = math.sin(sp.angle) * len * 0.5

                nvgBeginPath(vg)
                nvgMoveTo(vg, cx - dx, cy - dy)
                nvgLineTo(vg, cx + dx, cy + dy)
                nvgStrokeWidth(vg, 5.8 * (1 - p * 0.4))
                nvgStrokeColor(vg, nvgRGBA(255, 246, 104, alpha))
                nvgStroke(vg)
            end
        end

        -- 震荡环 (0.1~0.9)
        if t >= 0.1 and t < 0.9 then
            local rp = (t - 0.1) / 0.8
            local ringR = 26 + 117 * rp
            local ra = math.floor(180 * (1 - rp))
            nvgBeginPath(vg)
            nvgCircle(vg, tx, ty, ringR)
            nvgStrokeWidth(vg, 5.2 * (1 - rp * 0.6))
            nvgStrokeColor(vg, nvgRGBA(255, 246, 104, ra))
            nvgStroke(vg)
        end

        -- 碎片（合批：同色圆形合并为单个 path）
        if t >= 0.05 and fx._particles then
            local pt = (t - 0.05) / 0.95
            local a = math.floor(220 * (1 - pt))
            if a > 1 then
                nvgBeginPath(vg)
                local hasAny = false
                for _, p in ipairs(fx._particles) do
                    local dist = p.speed * pt
                    local px = tx + math.cos(p.angle) * dist
                    local py = ty + math.sin(p.angle) * dist
                    local sz = (p.size * (1 - pt * 0.4)) * fxScale
                    if sz > 1 then
                        nvgCircle(vg, px, py, sz)
                        hasAny = true
                    end
                end
                if hasAny then
                    nvgFillColor(vg, nvgRGBA(255, 246, 104, a))
                    nvgFill(vg)
                end
            end
        end
    end,
}

-- ============================================================================
-- 5 - 布甲：魔法碎布飘散 + 柔和光晕（白色）
-- ============================================================================
EFFECT_TYPES[5] = {
    duration = 0.50,
    label    = "cloth",

    setup = function(fx)
        fx._shreds = acquireParticles(9)
        for i = 1, 9 do
            local sh = fx._shreds[i]
            sh.angle  = math.rad(-90 + math.random() * 180)
            sh.speed  = 60 + math.random() * 120
            sh.width  = 16 + math.random() * 24
            sh.height = 24 + math.random() * 36
            sh.rot    = math.random() * math.pi * 2
            sh.rotSpd = (-1 + math.random() * 2) * 5
        end
    end,

    draw = function(fx, vg, t)
        local tx, ty = fx.tgtX, fx.tgtY

        -- 柔和光晕 (0~0.8)
        if t < 0.8 then
            local gp = t / 0.8
            local ga
            if gp < 0.25 then
                ga = math.floor(200 * (gp / 0.25))
            else
                ga = math.floor(200 * (1 - (gp - 0.25) / 0.75))
            end
            local gr = 70 + 130 * gp
            local glowPaint = nvgRadialGradient(vg,
                tx, ty, gr * 0.2, gr,
                nvgRGBA(255, 246, 104, ga),
                nvgRGBA(255, 246, 104, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, tx, ty, gr)
            nvgFillPaint(vg, glowPaint)
            nvgFill(vg)
        end

        -- 碎布飘散 (0.05~1.0)
        if t >= 0.05 and fx._shreds then
            local sp = (t - 0.05) / 0.95
            local a = math.floor(220 * (1 - sp * 0.7))

            if a > 1 then
                for _, sh in ipairs(fx._shreds) do
                    local dist = sh.speed * sp
                    local px = tx + math.cos(sh.angle) * dist
                    local py = ty + math.sin(sh.angle) * dist + 50 * sp * sp
                    local curRot = sh.rot + sh.rotSpd * sp
                    local w = sh.width * (1 - sp * 0.3)
                    local h = sh.height * (1 - sp * 0.3)

                    if w > 1 and h > 1 then
                        nvgSave(vg)
                        nvgTranslate(vg, px, py)
                        nvgRotate(vg, curRot)
                        nvgBeginPath(vg)
                        nvgRect(vg, -w * 0.5, -h * 0.5, w, h)
                        nvgFillColor(vg, nvgRGBA(255, 246, 104, a))
                        nvgFill(vg)
                        nvgRestore(vg)
                    end
                end
            end
        end

        -- 内圈魔法星点 (0.1~0.7)（合批：8个同色圆形合并为单个 path）
        if t >= 0.1 and t < 0.7 then
            local mp = (t - 0.1) / 0.6
            local ma = math.floor(180 * (1 - mp))
            local count = 8
            local sr = 7 * (1 - mp * 0.4)
            local r = 40 + 80 * mp
            nvgBeginPath(vg)
            for i = 1, count do
                local ang = (i / count) * math.pi * 2 + mp * 2
                local sx = tx + math.cos(ang) * r
                local sy = ty + math.sin(ang) * r
                nvgCircle(vg, sx, sy, sr)
            end
            nvgFillColor(vg, nvgRGBA(255, 246, 104, ma))
            nvgFill(vg)
        end
    end,
}

-- ============================================================================
-- 银光闪光（闪电卖鸡 #21 天赋触发）
-- 银白色斜向长线切割怪物卡片
-- ============================================================================
local SILVER_FLASH_CARD_HW = 99
local SILVER_FLASH_CARD_HH = 219

local SILVER_FLASH_EFFECT = {
    duration = 0.48,
    label    = "silver_flash",

    setup = function(fx)
        -- 斜切角度：约从左上到右下（轻微随机）
        fx._slashAngle = -0.72 + (math.random() - 0.5) * 0.12
        fx._halfW = SILVER_FLASH_CARD_HW
        fx._halfH = SILVER_FLASH_CARD_HH
    end,

    draw = function(fx, vg, t)
        local tx, ty = fx.tgtX, fx.tgtY
        local hw, hh = fx._halfW, fx._halfH
        local angle = fx._slashAngle
        local cosA, sinA = math.cos(angle), math.sin(angle)
        local slashLen = math.sqrt(hw * hw + hh * hh) * 2.4

        -- 卡片范围内裁剪
        nvgSave(vg)
        nvgScissor(vg, tx - hw, ty - hh, hw * 2, hh * 2)

        -- 1) 斜向银光切割线（0.02~0.38，由短变长扫过卡片）
        if t >= 0.02 and t < 0.42 then
            local st = (t - 0.02) / 0.40
            local headT = math.min(1, st * 1.35)
            local tailT = math.max(0, headT - 0.42)
            local headDist = slashLen * (headT - 0.5)
            local tailDist = slashLen * (tailT - 0.5)
            local hx = tx + cosA * headDist
            local hy = ty + sinA * headDist
            local lx = tx + cosA * tailDist
            local ly = ty + sinA * tailDist

            local alpha
            if st < 0.25 then
                alpha = math.floor(255 * (st / 0.25))
            else
                alpha = math.floor(255 * (1 - (st - 0.25) / 0.75))
            end

            -- 外层光晕（宽、淡）
            nvgLineCap(vg, NVG_ROUND)
            nvgBeginPath(vg)
            nvgMoveTo(vg, lx, ly)
            nvgLineTo(vg, hx, hy)
            nvgStrokeWidth(vg, 18)
            nvgStrokeColor(vg, nvgRGBA(200, 230, 255, math.floor(alpha * 0.35)))
            nvgStroke(vg)

            -- 中层银白
            nvgBeginPath(vg)
            nvgMoveTo(vg, lx, ly)
            nvgLineTo(vg, hx, hy)
            nvgStrokeWidth(vg, 8)
            nvgStrokeColor(vg, nvgRGBA(240, 248, 255, math.floor(alpha * 0.75)))
            nvgStroke(vg)

            -- 核心亮线
            nvgBeginPath(vg)
            nvgMoveTo(vg, lx, ly)
            nvgLineTo(vg, hx, hy)
            nvgStrokeWidth(vg, 3)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, alpha))
            nvgStroke(vg)
        end

        -- 2) 切割瞬间全卡闪白（0.08~0.28）
        if t >= 0.08 and t < 0.30 then
            local fp = (t - 0.08) / 0.22
            local fa
            if fp < 0.35 then
                fa = math.floor(140 * (fp / 0.35))
            else
                fa = math.floor(140 * (1 - (fp - 0.35) / 0.65))
            end
            nvgBeginPath(vg)
            nvgRect(vg, tx - hw, ty - hh, hw * 2, hh * 2)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, fa))
            nvgFill(vg)
        end

        -- 3) 斩击余韵：沿切口方向的细长高光（0.15~0.48）
        if t >= 0.15 and t < 0.48 then
            local rt = (t - 0.15) / 0.33
            local fade = math.floor(180 * (1 - rt))
            if fade > 2 then
                local d0 = slashLen * -0.5
                local d1 = slashLen * 0.5
                nvgBeginPath(vg)
                nvgMoveTo(vg, tx + cosA * d0, ty + sinA * d0)
                nvgLineTo(vg, tx + cosA * d1, ty + sinA * d1)
                nvgStrokeWidth(vg, 2.5 * (1 - rt * 0.6))
                nvgStrokeColor(vg, nvgRGBA(220, 240, 255, fade))
                nvgLineCap(vg, NVG_ROUND)
                nvgStroke(vg)
            end
        end

        nvgResetScissor(vg)
        nvgRestore(vg)
    end,
}

-- ======================== 公共 API ========================

--- 初始化（传入 vg 上下文）
function BattleEffects.init(vg)
    vg_ = vg
end

--- 触发一个受击特效
---@param armorType number 护甲类型 (1~5)
---@param tgtX number 目标中心X（设计分辨率）
---@param tgtY number 目标中心Y
function BattleEffects.spawn(armorType, tgtX, tgtY)
    local def = EFFECT_TYPES[armorType]
    if not def then
        def = EFFECT_TYPES[1]  -- fallback 皮甲
    end

    local fx = acquireFx()
    fx.type     = armorType
    fx.def      = def
    fx.timer    = 0
    fx.duration = def.duration
    fx.tgtX     = tgtX
    fx.tgtY     = tgtY

    -- 调用特效类型的初始化（预计算随机参数）
    if def.setup then
        def.setup(fx)
    end

    BE_BCS.effects[#BE_BCS.effects + 1] = fx
end

--- 闪电卖鸡「银光」触发闪光
---@param tgtX number
---@param tgtY number
function BattleEffects.spawnSilverFlash(tgtX, tgtY)
    local fx = acquireFx()
    fx.type     = "silver_flash"
    fx.def      = SILVER_FLASH_EFFECT
    fx.timer    = 0
    fx.duration = SILVER_FLASH_EFFECT.duration
    fx.tgtX     = tgtX
    fx.tgtY     = tgtY
    if SILVER_FLASH_EFFECT.setup then
        SILVER_FLASH_EFFECT.setup(fx)
    end
    BE_BCS.effects[#BE_BCS.effects + 1] = fx
end

--- 天赋/弹射等附加 VFX（由 BattleCombat 或场景回调触发）
---@param tgtX number
---@param tgtY number
---@param projOpts table|nil
function BattleEffects.spawnTalentVfx(tgtX, tgtY, projOpts)
    if projOpts and projOpts.silverFlashVfx then
        BattleEffects.spawnSilverFlash(tgtX, tgtY)
    end
end

--- 每帧更新
function BattleEffects.update(dt)
    local i = 1
    while i <= #BE_BCS.effects do
        local fx = BE_BCS.effects[i]
        fx.timer = fx.timer + dt
        if fx.timer >= fx.duration then
            -- 回收到对象池而非直接丢弃
            releaseFx(fx)
            table.remove(BE_BCS.effects, i)
        else
            i = i + 1
        end
    end
end

--- 绘制所有活跃特效（默认 alpha 混合，不改全局混合模式避免污染后续 UI）
function BattleEffects.draw(vg)
    for _, fx in ipairs(BE_BCS.effects) do
        local t = fx.timer / fx.duration
        local def = fx.def
        if def.draw then
            nvgSave(vg)
            def.draw(fx, vg, t)
            nvgRestore(vg)
        end
    end
end

--- 清除所有特效
function BattleEffects.reset()
    BE_BCS.effects = {}
end

--- 获取当前活跃特效数量（调试用）
function BattleEffects.getActiveCount()
    return #BE_BCS.effects
end

return BattleEffects
