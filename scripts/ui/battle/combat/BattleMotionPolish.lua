-- 战斗纯视觉曲线与局部冲击：不读时钟、不消费RNG、不写单位/事件/结算。
-- 所有输入为已有动画归一化进度；端点与原时长由调用方保持。
local M = {}

function M.clamp(t) return math.max(0, math.min(1, t)) end
function M.smooth(t)
    t = M.clamp(t)
    return t * t * (3 - 2 * t)
end
function M.outCubic(t)
    local q = 1 - M.clamp(t)
    return 1 - q * q * q
end

-- 在原0.12秒内轻收势再发力，不插入动画阶段/延迟命中。
function M.launch(t)
    t = M.clamp(t)
    if t < 0.18 then return -0.07 * M.smooth(t / 0.18) end
    return -0.07 + 1.07 * M.outCubic((t - 0.18) / 0.82)
end

-- 快速回位，末段只有原位移6%的回弹；0/1端点精确保持。
function M.recover(t)
    t = M.clamp(t)
    if t < 0.7 then return 1 - 1.06 * M.outCubic(t / 0.7) end
    return -0.06 * (1 - M.smooth((t - 0.7) / 0.3))
end

-- 同色碎片合批，固定三个轨迹；只使用已有spawn生成的记录。
-- 旧铜、骨白、血色为局部辅色，不改变既有技能本色/混合模式。
local COPPER = { 164, 116, 78 }
local BONE = { 224, 210, 181 }
local BLOOD = { 132, 47, 42 }

function M.setupImpact(fx)
    fx._motionColor = fx.type == 5 and BLOOD or (fx.type == 1 and COPPER or BONE)
    fx._motionDir = fx.type == 5 and -1 or 1
end

--- 纯轨迹采样，返回相对受击点的碎片顶点；没有逐帧积分或对象分配。
function M.fragment(t, i, dir)
    t = M.clamp(t)
    local travel = M.outCubic(t)
    local x = dir * (12 + i * 9) * travel
    local y = -(14 + i * 6) * travel + (18 + i * 5) * t * t
    return x, y
end

function M.drawImpact(fx, vg, t, scale)
    local color = fx._motionColor
    if not color then return end
    t = M.clamp(t)
    local tx, ty = fx.tgtX, fx.tgtY
    local dir = fx._motionDir
    local sizeScale = math.min(1, math.max(0.2, scale))
    -- 窄冲击弧先出、碎片后出；既有寿命内消退，不加全屏闪光。
    if t < 0.55 then
        local p = t / 0.55
        local r = (10 + 23 * M.outCubic(p)) * sizeScale
        local a = math.floor(126 * (1 - M.smooth(p)))
        nvgBeginPath(vg)
        nvgMoveTo(vg, tx - r * 0.6, ty + r * 0.25)
        nvgQuadTo(vg, tx, ty - r * 0.7, tx + r * 0.6, ty + r * 0.25)
        nvgStrokeWidth(vg, (2.6 - p) * sizeScale)
        nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], a))
        nvgStroke(vg)
    end
    if t >= 0.08 and t < 0.9 then
        local p = (t - 0.08) / 0.82
        local half = (2.4 - 1.6 * p) * sizeScale
        nvgBeginPath(vg)
        for i = 1, 3 do
            local x, y = M.fragment(p, i, dir)
            local px, py = tx + x * sizeScale, ty + y * sizeScale
            nvgMoveTo(vg, px, py - half)
            nvgLineTo(vg, px + half, py)
            nvgLineTo(vg, px, py + half)
            nvgLineTo(vg, px - half, py)
            nvgClosePath(vg)
        end
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], math.floor(144 * (1 - M.smooth(p)))))
        nvgFill(vg)
    end
end

return M
