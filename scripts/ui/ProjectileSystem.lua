-- ============================================================================
-- ProjectileSystem - 投射物特效系统
-- 管理远程攻击角色的飞行投射物（火球、箭矢、闪电链、飞镖等）
-- 渲染层：在 BattleEffects 之前绘制（卡片之上）
-- ============================================================================

local ProjectileSystem = {}
-- ======================== [多实例] 投射物状态容器 ========================
local function newState()
    return { projectiles = {} }
end
local PS_DEFAULT = newState()
local PS_BCS = PS_DEFAULT
function ProjectileSystem.newState() return newState() end
function ProjectileSystem.mount(s) PS_BCS = s or PS_DEFAULT end
function ProjectileSystem.mountedState() return PS_BCS end


local GameSFX = require "systems.GameSFX"
local Diag = require("systems.BattleDiag")

-- 活跃投射物列表
local starGateDrawTime = 0

-- NanoVG 上下文
local vg_ = nil

-- 图片句柄缓存  { [key] = handle }
local images = {}

local CONFIGS = {
    -- ---- 近战英雄（melee 穿透特效） ----
    [1] = {
        type = "melee", imgKey = "EF_ATK_1",
        imgW = 200, imgH = 200, duration = 0.45,
    },
    -- 2: 火球术 — 红色拖尾
    [2] = {
        type = "fly", imgKey = "EF_ATK_2",
        imgW = 200, imgH = 200, duration = 0.55,
        trail = { 255, 80, 30 },
    },
    -- 3: 箭矢 — 白色拖尾
    [3] = {
        type = "fly", imgKey = "EF_ATK_3",
        imgW = 200, imgH = 200, duration = 0.50,
        trail = { 255, 255, 255 },
    },
    [4] = {
        type = "melee", imgKey = "EF_ATK_4",
        imgW = 200, imgH = 200, duration = 0.45,
    },
    [5] = {
        type = "melee", imgKey = "EF_ATK_5",
        imgW = 200, imgH = 200, duration = 0.45,
    },
    -- 6: 闪电链 — 从角色拉伸到怪物（hitRatio=0.3 表示视觉到达时即触发伤害）
    [6] = {
        type = "lightning", imgKey = "EF_ATK_6",
        imgW = 200, imgH = 200, duration = 0.35,
        hitRatio = 0.3,
    },
    -- 7: 能量子弹 — 无额外处理（此处 melee 英雄的 ID 序列在下方补完）
    [7] = {
        type = "fly", imgKey = "EF_ATK_7",
        imgW = 200, imgH = 200, duration = 0.50,
    },
    [8] = {
        type = "melee", imgKey = "EF_ATK_8",
        imgW = 200, imgH = 200, duration = 0.45,
    },
    -- 9: 自然蝴蝶 — 贝塞尔曲线
    [9] = {
        type = "bezier", imgKey = "EF_ATK_9",
        imgW = 200, imgH = 200, duration = 0.65,
    },
    [10] = {
        type = "melee", imgKey = "EF_ATK_10",
        imgW = 200, imgH = 200, duration = 0.45,
    },
    [11] = {
        type = "melee", imgKey = "EF_ATK_11",
        imgW = 200, imgH = 200, duration = 0.45,
    },
    -- 12: 冰锥 — 蓝色拖尾
    [12] = {
        type = "fly", imgKey = "EF_ATK_12",
        imgW = 200, imgH = 200, duration = 0.55,
        trail = { 100, 180, 255 },
    },
    -- 13: 能量箭 — 紫色拖尾
    [13] = {
        type = "fly", imgKey = "EF_ATK_13",
        imgW = 200, imgH = 200, duration = 0.50,
        trail = { 180, 80, 255 },
    },
    -- 14: 飞镖 — 持续旋转
    [14] = {
        type = "fly", imgKey = "EF_ATK_14",
        imgW = 200, imgH = 200, duration = 0.55,
        rotate = true,
    },
    -- 15: 圣光球 — 贝塞尔曲线
    [15] = {
        type = "bezier", imgKey = "EF_ATK_15",
        imgW = 200, imgH = 200, duration = 0.65,
    },
    -- ---- 新增角色攻击特效（16/20/21/22/23） ----
    [16] = {
        type = "melee", imgKey = "EF_ATK_16",
        imgW = 200, imgH = 200, duration = 0.45,
    },
    [20] = {
        type = "bezier", imgKey = "EF_ATK_20",
        imgW = 200, imgH = 200, duration = 0.60,
        trail = { 190, 120, 255 },
    },
    [21] = {
        type = "fly", imgKey = "EF_ATK_21",
        imgW = 200, imgH = 200, duration = 0.55,
        trail = { 120, 220, 255 },
    },
    [22] = {
        type = "fly", imgKey = "EF_ATK_22",
        imgW = 200, imgH = 200, duration = 0.50,
        trail = { 80, 255, 120 },
    },
    [23] = {
        type = "bezier", imgKey = "EF_ATK_23",
        imgW = 200, imgH = 200, duration = 0.65,
    },
}

-- ======================== 怪物投射物配置（字符串 key） ========================

local MONSTER_CONFIGS = {
    -- 直线飞行 (type = "fly")
    ["EF_MS_8"]  = { type = "fly", imgKey = "EF_MS_8",  imgW = 200, imgH = 200, duration = 0.55 },
    ["EF_MS_9"]  = { type = "melee", imgKey = "EF_MS_9",  imgW = 200, imgH = 200, duration = 0.45 },
    ["EF_MS_13"] = { type = "fly", imgKey = "EF_MS_13", imgW = 200, imgH = 200, duration = 0.50 },
    ["EF_MS_24"] = { type = "fly", imgKey = "EF_MS_24", imgW = 200, imgH = 200, duration = 0.55 },
    ["EF_MS_27"] = { type = "fly", imgKey = "EF_MS_27", imgW = 200, imgH = 200, duration = 0.55 },
    ["EF_MS_46"] = { type = "fly", imgKey = "EF_MS_46", imgW = 200, imgH = 200, duration = 0.55 },
    ["EF_MS_50"] = { type = "fly", imgKey = "EF_MS_50", imgW = 200, imgH = 200, duration = 0.55 },
    ["EF_MS_53"] = { type = "fly", imgKey = "EF_MS_53", imgW = 200, imgH = 200, duration = 0.55 },

    -- 抖动飞行 (type = "shake") — 爪击特效（远程怪也复用此key时按远程行为）
    ["EF_MS_7"]  = { type = "shake", imgKey = "EF_MS_7",  imgW = 200, imgH = 200, duration = 0.45 },
    ["EF_MS_30"] = { type = "melee", imgKey = "EF_MS_30", imgW = 200, imgH = 200, duration = 0.45 },

    -- 贝塞尔曲线飞行 (type = "bezier")
    ["EF_MS_47"]  = { type = "bezier", imgKey = "EF_MS_47",  imgW = 200, imgH = 200, duration = 0.65 },
    ["EF_ZY_106"] = { type = "bezier", imgKey = "EF_ZY_106", imgW = 200, imgH = 200, duration = 0.65 },
    ["EF_ZY_224"] = { type = "bezier", imgKey = "EF_ZY_224", imgW = 200, imgH = 200, duration = 0.65 },

    -- 旋转 + 贝塞尔曲线 (type = "bezier", rotate = true)
    ["EF_MS_16"] = { type = "bezier", imgKey = "EF_MS_16", imgW = 200, imgH = 200, duration = 0.65, rotate = true },
    ["EF_MS_39"] = { type = "melee", imgKey = "EF_MS_39", imgW = 200, imgH = 200, duration = 0.45 },
    ["EF_MS_43"] = { type = "melee", imgKey = "EF_MS_43", imgW = 200, imgH = 200, duration = 0.45 },

    -- 复用英雄投射物（怪物使用同样的特效 key，远程行为）
    ["EF_ATK_2"]  = { type = "fly", imgKey = "EF_ATK_2",  imgW = 200, imgH = 200, duration = 0.55, trail = { 255, 80, 30 } },
    ["EF_ATK_3"]  = { type = "fly", imgKey = "EF_ATK_3",  imgW = 200, imgH = 200, duration = 0.50, trail = { 255, 255, 255 } },
    ["EF_ATK_6"]  = { type = "lightning", imgKey = "EF_ATK_6",  imgW = 200, imgH = 200, duration = 0.35, hitRatio = 0.3 },
    ["EF_ATK_13"] = { type = "fly", imgKey = "EF_ATK_13", imgW = 200, imgH = 200, duration = 0.50, trail = { 180, 80, 255 } },
    ["EF_ATK_9"]  = { type = "bezier", imgKey = "EF_ATK_9",  imgW = 200, imgH = 200, duration = 0.65 },

    -- ---- 近战怪物特效（type = "melee"：极快穿透） ----
    ["EF_MS_1"]   = { type = "melee", imgKey = "EF_MS_1",   imgW = 200, imgH = 200, duration = 0.45 },
    ["EF_ATK_1"]  = { type = "melee", imgKey = "EF_ATK_1",  imgW = 200, imgH = 200, duration = 0.45 },
    ["EF_ATK_4"]  = { type = "melee", imgKey = "EF_ATK_4",  imgW = 200, imgH = 200, duration = 0.45 },
    ["EF_ATK_5"]  = { type = "melee", imgKey = "EF_ATK_5",  imgW = 200, imgH = 200, duration = 0.45 },
    ["EF_ATK_8"]  = { type = "melee", imgKey = "EF_ATK_8",  imgW = 200, imgH = 200, duration = 0.45 },
    ["EF_ATK_10"] = { type = "melee", imgKey = "EF_ATK_10", imgW = 200, imgH = 200, duration = 0.45 },
    ["EF_ATK_11"] = { type = "melee", imgKey = "EF_ATK_11", imgW = 200, imgH = 200, duration = 0.45 },
    ["EF_ATK_16"] = { type = "melee", imgKey = "EF_ATK_16", imgW = 200, imgH = 200, duration = 0.45 },
    ["EF_ATK_20"] = { type = "bezier", imgKey = "EF_ATK_20", imgW = 200, imgH = 200, duration = 0.60, trail = { 190, 120, 255 } },
    ["EF_ATK_21"] = { type = "fly", imgKey = "EF_ATK_21", imgW = 200, imgH = 200, duration = 0.55, trail = { 120, 220, 255 } },
    ["EF_ATK_22"] = { type = "fly", imgKey = "EF_ATK_22", imgW = 200, imgH = 200, duration = 0.50, trail = { 80, 255, 120 } },
    ["EF_ATK_23"] = { type = "bezier", imgKey = "EF_ATK_23", imgW = 200, imgH = 200, duration = 0.65 },
    ["EF_MS_22"]  = { type = "melee", imgKey = "EF_MS_22",  imgW = 200, imgH = 200, duration = 0.45 },
    ["EF_MS_36"]  = { type = "melee", imgKey = "EF_MS_36",  imgW = 200, imgH = 200, duration = 0.45 },
}

-- 技能投射物配置（heroId → skill 投射物）
local SKILL_CONFIGS = {
    -- 11: 夜华斩 — 贝塞尔曲线斩击
    [11] = {
        type = "bezier", imgKey = "EF_skill_11",
        imgW = 200, imgH = 400, duration = 0.55,
        trail = { 255, 50, 50 },
    },
    -- 16: 灵月飞剑 — 卡片中心生成 → 外扩至圆上 → 齐射
    [16] = {
        type = "flyingSword", imgKey = "EF_skill_16",
        imgW = 200, imgH = 200, duration = 0.85,
        expandFrac = 0.32,
        hitRatio = 0.32 + (1 - 0.32) * 0.92,
        trail = { 180, 220, 255 },
    },
    -- 20: 星门 — 星门处发射的暗影星辉
    [20] = {
        type = "bezier", imgKey = "EF_skill_20",
        imgW = 200, imgH = 200, duration = 0.55,
        trail = { 220, 160, 255 },
    },
}

-- 转职天赋投射物配置（talentProjKey → 投射物配置）
-- 用于不绑定 heroId 的通用天赋投射物（如奥术飞弹：任何法师转职后都能触发）
local TALENT_PROJ_CONFIGS = {
    -- 106 奥术飞弹 — 贝塞尔曲线紫色飞弹
    ["EF_ZY_106"] = {
        type = "bezier", imgKey = "EF_ZY_106",
        imgW = 200, imgH = 200, duration = 0.55,
        trail = { 160, 100, 255 },
    },
    -- 224 奥能充盈爆炸 — 复用奥术飞弹素材（稍快）
    ["EF_ZY_224"] = {
        type = "bezier", imgKey = "EF_ZY_224",
        imgW = 200, imgH = 200, duration = 0.45,
        trail = { 200, 80, 255 },
    },
}

-- ======================== 辅助函数 ========================

--- 二次贝塞尔曲线插值
local function bezier2(p0x, p0y, p1x, p1y, p2x, p2y, t)
    local u = 1 - t
    local x = u * u * p0x + 2 * u * t * p1x + t * t * p2x
    local y = u * u * p0y + 2 * u * t * p1y + t * t * p2y
    return x, y
end

--- 加载投射物图片（懒加载）
local function getImage(key)
    if images[key] then return images[key] end
    local path = "image/特效投射物/" .. key .. ".png"
    local handle = nvgCreateImage(vg_, path, 0)
    images[key] = handle
    print("[ProjectileSystem] loaded image: " .. path .. " → handle=" .. tostring(handle))
    return handle
end

-- [三行并行] 条带渲染缩放：投射物/星门等视觉尺寸 × renderScale
-- （卡牌在条带内缩至 CARD_SCALE，投射物同步缩放避免比例失调；飞行时长为 duration 制不受影响）
local renderScale = 1.0
function ProjectileSystem.setRenderScale(s) renderScale = s or 1.0 end

--- [分帧预热] 收集全部投射物图 key（去重，供战斗卡牌分帧泵预热）
function ProjectileSystem.getImageKeys()
    local keys, seen = {}, {}
    for _, cfgTable in ipairs({ CONFIGS, MONSTER_CONFIGS, SKILL_CONFIGS, TALENT_PROJ_CONFIGS }) do
        for _, cfg in pairs(cfgTable) do
            local k = cfg.imgKey
            if k and not seen[k] then
                seen[k] = true
                keys[#keys + 1] = k
            end
        end
    end
    return keys
end

--- [分帧预热] 单张预热（走 getImage 缓存，命中即跳过）
function ProjectileSystem.prewarmOne(key)
    getImage(key)
end

-- [看情况抛物线] fly 直线弹的飞行距离 ≥ ARC_TRIGGER_DIST 时升级为贝塞尔弧线
-- （条带空间: 前排对峙≈193px 直线，跨场≈800px 弧线；可按观感调整）
local ARC_TRIGGER_DIST = 300
function ProjectileSystem.setArcTriggerDist(d) ARC_TRIGGER_DIST = d or 300 end

--- 绘制投射物图片（居中，支持旋转/缩放/透明度）
--- 素材默认朝右(+X方向)，angle=0时朝右，angle=-π/2时朝上
local function drawProjectileImage(vg, imgHandle, cx, cy, w, h, angle, alpha)
    if not imgHandle or imgHandle <= 0 then return end
    w = w * renderScale
    h = h * renderScale
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    if angle ~= 0 then
        nvgRotate(vg, angle)
    end
    local paint = nvgImagePattern(vg, -w * 0.5, -h * 0.5, w, h, 0, imgHandle, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, -w * 0.5, -h * 0.5, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    nvgRestore(vg)
end

local function getStarGateDrawPosition(baseX, baseY, index, count, isAlly)
    local xOffset = isAlly and 150 or -150
    local yOffset = -118
    if count >= 2 then
        local pairSign = (index == 1) and -1 or 1
        xOffset = pairSign * 118
        yOffset = -118
    end
    local floatY = math.sin(starGateDrawTime * 2.0 + index * 1.7) * 9
    return baseX + xOffset, baseY + yOffset + floatY
end

local function drawStarGateAura(vg, cx, cy, size, alpha)
    local a = math.floor(120 * alpha)
    local glow = nvgRadialGradient(vg, cx, cy, size * 0.18, size * 0.62,
        nvgRGBA(160, 80, 255, a), nvgRGBA(80, 20, 160, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, size * 0.62)
    nvgFillPaint(vg, glow)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, size * 0.38)
    nvgStrokeWidth(vg, 4)
    nvgStrokeColor(vg, nvgRGBA(230, 180, 255, math.floor(150 * alpha)))
    nvgStroke(vg)
end

-- ======================== 拖尾绘制 ========================

--- 绘制拖尾效果（沿飞行方向的渐变尾巴）
local function drawTrail(vg, cx, cy, prevCX, prevCY, color, t, size)
    local dx = prevCX - cx
    local dy = prevCY - cy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 2 then return end

    local nx = dx / dist
    local ny = dy / dist

    local tailLen = math.min(dist, size * 1.5)
    local tailEndX = cx + nx * tailLen
    local tailEndY = cy + ny * tailLen

    local headW = size * 0.35
    local tailW = size * 0.05
    local perpX = -ny
    local perpY = nx

    local alpha = math.floor(180 * (1 - t * 0.5))

    local gradPaint = nvgLinearGradient(vg,
        cx, cy, tailEndX, tailEndY,
        nvgRGBA(color[1], color[2], color[3], alpha),
        nvgRGBA(color[1], color[2], color[3], 0))

    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + perpX * headW, cy + perpY * headW)
    nvgLineTo(vg, cx - perpX * headW, cy - perpY * headW)
    nvgLineTo(vg, tailEndX - perpX * tailW, tailEndY - perpY * tailW)
    nvgLineTo(vg, tailEndX + perpX * tailW, tailEndY + perpY * tailW)
    nvgClosePath(vg)
    nvgFillPaint(vg, gradPaint)
    nvgFill(vg)

    -- 头部发光
    local glowR = size * 0.4
    local glowPaint = nvgRadialGradient(vg,
        cx, cy, glowR * 0.1, glowR,
        nvgRGBA(color[1], color[2], color[3], math.floor(alpha * 0.6)),
        nvgRGBA(color[1], color[2], color[3], 0))
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, glowR)
    nvgFillPaint(vg, glowPaint)
    nvgFill(vg)
end

-- ======================== 各类型绘制函数 ========================

--- 直线飞行投射物
--- 方向策略：素材朝右(+X), 用 atan2 得到飞行角度直接旋转
local function updateAndDrawFly(proj, vg, t)
    local cfg = proj.cfg

    -- 线性插值（恒定速度）
    local cx = proj.startX + (proj.endX - proj.startX) * t
    local cy = proj.startY + (proj.endY - proj.startY) * t

    -- 飞行角度：atan2(dy, dx)
    -- 素材朝右 = 角度0, 所以直接用这个角度旋转即可
    local dx = proj.endX - proj.startX
    local dy = proj.endY - proj.startY
    local flyAngle = math.atan(dy, dx)

    -- 旋转效果（飞镖等）: 在飞行角度基础上叠加自转
    local drawAngle = flyAngle
    if cfg.rotate then
        drawAngle = drawAngle + t * math.pi * 8
    end

    -- 缩放
    local drawW = cfg.imgW
    local drawH = cfg.imgH

    -- 拉伸动画（蝴蝶等）
    if cfg.stretch then
        local stretchT = math.sin(t * math.pi * 6)
        drawW = cfg.imgW * (1.0 + stretchT * 0.25)
    end

    -- 透明度：末尾淡出
    local alpha = 1.0
    if t > 0.8 then
        alpha = 1.0 - (t - 0.8) / 0.2
    end

    -- 绘制拖尾
    if cfg.trail then
        local prevT = math.max(0, t - 0.08)
        local prevX = proj.startX + (proj.endX - proj.startX) * prevT
        local prevY = proj.startY + (proj.endY - proj.startY) * prevT
        drawTrail(vg, cx, cy, prevX, prevY, cfg.trail, t, cfg.imgW * 0.5)
    end

    -- 绘制投射物
    local imgHandle = getImage(cfg.imgKey)
    drawProjectileImage(vg, imgHandle, cx, cy, drawW, drawH, drawAngle, alpha)
end

--- 抖动飞行投射物（爪击等）
--- 沿飞行方向直线移动，同时垂直于飞行路径做正弦振荡
local function updateAndDrawShake(proj, vg, t)
    local cfg = proj.cfg

    -- 飞行方向
    local dx = proj.endX - proj.startX
    local dy = proj.endY - proj.startY
    local dist = math.sqrt(dx * dx + dy * dy)
    local flyAngle = math.atan(dy, dx)

    -- 线性插值基准位置
    local baseX = proj.startX + dx * t
    local baseY = proj.startY + dy * t

    -- 垂直于飞行方向的抖动偏移
    local perpX = -dy / math.max(dist, 1)
    local perpY =  dx / math.max(dist, 1)
    local shakeAmp = 12  -- 抖动幅度（像素）
    local shakeFreq = 30 -- 抖动频率
    local offset = math.sin(t * shakeFreq) * shakeAmp * (1 - t) -- 越靠近终点越小

    local cx = baseX + perpX * offset
    local cy = baseY + perpY * offset

    -- 透明度：末尾淡出
    local alpha = 1.0
    if t > 0.8 then
        alpha = 1.0 - (t - 0.8) / 0.2
    end

    local imgHandle = getImage(cfg.imgKey)
    drawProjectileImage(vg, imgHandle, cx, cy, cfg.imgW, cfg.imgH, flyAngle, alpha)
end

--- 贝塞尔曲线飞行投射物（圣光球、蝴蝶等）
--- 通用设计：通过最小弧线半径保证任何距离（包括起终点重合）都有可见弧线
local MIN_ARC_RADIUS = 160  -- 最小弧线半径（像素），决定最短距离下弧线的弯曲程度

local function updateAndDrawBezier(proj, vg, t)
    local cfg = proj.cfg

    local dx = proj.endX - proj.startX
    local dy = proj.endY - proj.startY
    local dist = math.sqrt(dx * dx + dy * dy)

    -- 距离极小时，给终点一个微偏，避免方向向量退化为零
    local effEndX, effEndY = proj.endX, proj.endY
    if dist < 1 then
        effEndX = proj.startX + 1
        effEndY = proj.startY
        dx = 1
        dy = 0
        dist = 1
    end

    -- 计算垂直偏移量：max(最小半径, 距离×0.4)
    local perpLen = math.max(MIN_ARC_RADIUS * renderScale, dist * 0.4)

    -- 归一化方向 + 垂直方向
    local ndx = dx / dist
    local ndy = dy / dist
    local perpNx = -ndy * proj.bezierSide
    local perpNy =  ndx * proj.bezierSide

    -- 控制点 = 中点 + 垂直偏移
    local midX = (proj.startX + effEndX) * 0.5
    local midY = (proj.startY + effEndY) * 0.5
    local ctrlX = midX + perpNx * perpLen
    local ctrlY = midY + perpNy * perpLen

    -- 线性插值（恒定速度）
    local cx, cy = bezier2(proj.startX, proj.startY, ctrlX, ctrlY, effEndX, effEndY, t)

    -- 切线方向 → 飞行角度
    local u = 1 - t
    local tangentX = 2 * u * (ctrlX - proj.startX) + 2 * t * (effEndX - ctrlX)
    local tangentY = 2 * u * (ctrlY - proj.startY) + 2 * t * (effEndY - ctrlY)
    local flyAngle = math.atan(tangentY, tangentX)

    -- 旋转效果（飞斧、船锚等）: 在飞行角度基础上叠加自转
    if cfg.rotate then
        flyAngle = flyAngle + t * math.pi * 8
    end

    -- 前一帧位置（拖尾用）
    local prevT = math.max(0, t - 0.06)
    local prevX, prevY = bezier2(proj.startX, proj.startY, ctrlX, ctrlY, effEndX, effEndY, prevT)

    -- 透明度：末尾淡出
    local alpha = 1.0
    if t > 0.85 then
        alpha = 1.0 - (t - 0.85) / 0.15
    end

    -- 拖尾（金色发光）
    drawTrail(vg, cx, cy, prevX, prevY, { 255, 220, 100 }, t, cfg.imgW * 0.4)

    local imgHandle = getImage(cfg.imgKey)
    drawProjectileImage(vg, imgHandle, cx, cy, cfg.imgW, cfg.imgH, flyAngle, alpha)
end

--- 闪电链（拉伸到目标）
local function updateAndDrawLightning(proj, vg, t)
    local cfg = proj.cfg

    local dx = proj.endX - proj.startX
    local dy = proj.endY - proj.startY
    local dist = math.sqrt(dx * dx + dy * dy)
    local angle = math.atan(dy, dx)

    -- 延伸进度：快速伸出
    local extendT
    if t < 0.3 then
        extendT = t / 0.3
        extendT = 1 - (1 - extendT) * (1 - extendT)
    else
        extendT = 1.0
    end

    local alpha = 1.0
    if t > 0.7 then
        alpha = 1.0 - (t - 0.7) / 0.3
    end

    -- 当前延伸长度
    local curDist = dist * extendT
    -- 闪电链中点
    local midX = proj.startX + math.cos(angle) * curDist * 0.5
    local midY = proj.startY + math.sin(angle) * curDist * 0.5

    -- 绘制拉伸的闪电图片
    local stretchW = math.max(cfg.imgW, curDist)
    local imgHandle = getImage(cfg.imgKey)
    if not imgHandle or imgHandle <= 0 then return end

    nvgSave(vg)
    nvgTranslate(vg, midX, midY)
    nvgRotate(vg, angle)
    -- 用 nvgImagePattern 重复/拉伸图片
    local paint = nvgImagePattern(vg, -stretchW * 0.5, -cfg.imgH * 0.5,
        stretchW, cfg.imgH, 0, imgHandle, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, -stretchW * 0.5, -cfg.imgH * 0.5, stretchW, cfg.imgH)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    nvgRestore(vg)
end

--- 斩击特效（原地播放，夜华斩）
local function updateAndDrawSlash(proj, vg, t)
    local cfg = proj.cfg

    -- 斩击在目标位置播放
    local cx = proj.endX
    local cy = proj.endY

    -- 缩放动画
    local scale
    if t < 0.2 then
        scale = 0.3 + 0.7 * (1 - (1 - t / 0.2) * (1 - t / 0.2))
    elseif t < 0.5 then
        scale = 1.0
    else
        scale = 1.0 - (t - 0.5) / 0.5 * 0.3
    end

    -- 透明度
    local alpha = 1.0
    if t > 0.6 then
        alpha = 1.0 - (t - 0.6) / 0.4
    end

    -- 红色光晕
    if cfg.slashTint and alpha > 0.01 then
        local glowR = cfg.imgH * 0.5 * scale
        local ga = math.floor(100 * alpha)
        local glowPaint = nvgRadialGradient(vg,
            cx, cy, glowR * 0.2, glowR,
            nvgRGBA(cfg.slashTint[1], cfg.slashTint[2], cfg.slashTint[3], ga),
            nvgRGBA(cfg.slashTint[1], cfg.slashTint[2], cfg.slashTint[3], 0))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, glowR)
        nvgFillPaint(vg, glowPaint)
        nvgFill(vg)
    end

    -- 绘制斩击图片
    local imgHandle = getImage(cfg.imgKey)
    drawProjectileImage(vg, imgHandle, cx, cy,
        cfg.imgW * scale, cfg.imgH * scale, 0, alpha)
end

--- 近战穿透特效（快速斩击，穿过目标卡片后继续飞行一段再消失）
--- 视觉效果：一道斩击从己方飞出 → 命中目标 → 穿过卡片继续飞行 → 淡出消失
local MELEE_HIT_RATIO    = 0.45 -- 后备值；实际按距离动态计算（见 spawn 处）
local MELEE_DURATION     = 0.45 -- 整个飞行时长（含穿透段）
local MELEE_OVERSHOOT    = 250  -- 穿过目标后继续飞行的距离（像素）
local MELEE_SOLID_FRAC   = 0.4  -- 穿过目标后前 40% 距离内保持满透明度
local MELEE_FADE_FRAC    = 0.6  -- 后 60% 距离内淡出

local function updateAndDrawMelee(proj, vg, t)
    local cfg = proj.cfg

    -- 飞行方向
    local dx = proj.endX - proj.startX
    local dy = proj.endY - proj.startY
    local dist = math.sqrt(dx * dx + dy * dy)
    local flyAngle = math.atan(dy, dx)

    -- 总飞行距离 = 起点到终点 + 穿透距离
    local totalDist = dist + MELEE_OVERSHOOT
    -- 用真实时间驱动位置（不受 draw 层 t 的 clamp 限制）
    local realT = proj.timer / cfg.duration
    local curDist = totalDist * realT
    -- 基于方向的当前位置
    local ndx = (dist > 0.1) and (dx / dist) or 1
    local ndy = (dist > 0.1) and (dy / dist) or 0
    local cx = proj.startX + ndx * curDist
    local cy = proj.startY + ndy * curDist

    -- 透明度：经过目标后先保持满透明度一段再淡出（斩击穿透感）
    local alpha = 1.0
    if curDist > dist then
        local pastDist = curDist - dist  -- 超过目标的距离
        local solidDist = MELEE_OVERSHOOT * MELEE_SOLID_FRAC  -- 保持满透明度的距离
        if pastDist > solidDist then
            -- 超过保持段后开始淡出
            local fadeDist = MELEE_OVERSHOOT * MELEE_FADE_FRAC
            alpha = 1.0 - (pastDist - solidDist) / fadeDist
            alpha = math.max(0, alpha)
        end
        -- else: 仍在保持段内，alpha = 1.0
    end

    -- 绘制投射物
    local imgHandle = getImage(cfg.imgKey)
    drawProjectileImage(vg, imgHandle, cx, cy, cfg.imgW, cfg.imgH, flyAngle, alpha)
end

-- 近战穿透的默认配置
local MELEE_DEFAULT_CFG = { duration = MELEE_DURATION, hitRatio = MELEE_HIT_RATIO }

local function easeOutCubic(x)
    local inv = 1 - x
    return 1 - inv * inv * inv
end

local function easeInQuad(x)
    return x * x
end

local function easeInOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    end
    local f = 2 * t - 2
    return 0.5 * f * f * f + 1
end

local FLYBACK_PIERCE_DIST = 120

--- 主飞剑首段命中后，转为穿透→转向→折返三段飞回
local function setupFlybackContinuation(proj, fb)
    proj.isFlybackReturn = true
    proj.isFlyback = nil
    proj.hitX = fb.hitX
    proj.hitY = fb.hitY
    proj.behindX = fb.hitX + fb.dirX * FLYBACK_PIERCE_DIST
    proj.behindY = fb.hitY + fb.dirY * FLYBACK_PIERCE_DIST
    proj.pierceAngle = math.atan(fb.dirY, fb.dirX)
    proj.onReturnHit = fb.onReturnHit
    proj.onArrive = nil
    proj.returnHitDone = false
    proj.arrived = false
    proj.timer = 0
    proj.cfg = setmetatable({
        duration = 0.75,
        hitRatio = 0.98,
        flybackPierceFrac = 0.25,
        flybackTurnFrac = 0.40,
        flybackTrail = { 255, 200, 100 },
    }, { __index = proj.cfg })
end

--- 灵月飞剑：卡片中心 → 圆上等分点 → 齐射；飞回：穿透 → 转向 → 折返命中
local function updateAndDrawFlyingSword(proj, vg, t)
    local cfg = proj.cfg

    if proj.isFlybackReturn then
        local pierceEnd = cfg.flybackPierceFrac or 0.25
        local turnEnd = cfg.flybackTurnFrac or 0.40
        local trail = cfg.flybackTrail or { 255, 200, 100 }
        local cx, cy, drawAngle, prevX, prevY

        if t < pierceEnd then
            local p = easeOutCubic(t / pierceEnd)
            cx = proj.hitX + (proj.behindX - proj.hitX) * p
            cy = proj.hitY + (proj.behindY - proj.hitY) * p
            drawAngle = proj.pierceAngle
            prevX = cx - math.cos(proj.pierceAngle) * 18
            prevY = cy - math.sin(proj.pierceAngle) * 18
        elseif t < turnEnd then
            cx, cy = proj.behindX, proj.behindY
            local p = easeInOutCubic((t - pierceEnd) / (turnEnd - pierceEnd))
            drawAngle = proj.pierceAngle + math.pi * p
            prevX, prevY = cx, cy
        else
            local p = easeInQuad((t - turnEnd) / (1 - turnEnd))
            cx = proj.behindX + (proj.hitX - proj.behindX) * p
            cy = proj.behindY + (proj.hitY - proj.behindY) * p
            drawAngle = proj.pierceAngle + math.pi
            prevX = cx - math.cos(drawAngle) * 20
            prevY = cy - math.sin(drawAngle) * 20
        end

        local alpha = 1.0
        if t > 0.94 then
            alpha = 1.0 - (t - 0.94) / 0.06
        end

        if t >= pierceEnd * 0.5 and cfg.flybackTrail then
            drawTrail(vg, cx, cy, prevX, prevY, trail, t, cfg.imgW * 0.42)
        end

        local imgHandle = getImage(cfg.imgKey)
        drawProjectileImage(vg, imgHandle, cx, cy, cfg.imgW * 0.88, cfg.imgH * 0.88, drawAngle, alpha)
        return
    end

    local expandFrac = cfg.expandFrac or 0.32

    local cx, cy, drawAngle, alpha, drawW, drawH
    drawW = cfg.imgW
    drawH = cfg.imgH

    if t < expandFrac then
        local phaseT = easeOutCubic(t / expandFrac)
        cx = proj.centerX + (proj.ringX - proj.centerX) * phaseT
        cy = proj.centerY + (proj.ringY - proj.centerY) * phaseT
        drawAngle = proj.spawnAngle
        alpha = 0.55 + 0.45 * phaseT
        local scale = 0.75 + 0.25 * phaseT
        drawW = cfg.imgW * scale
        drawH = cfg.imgH * scale
    else
        local attackSpan = 1 - expandFrac
        local phaseT = easeInQuad((t - expandFrac) / attackSpan)
        cx = proj.ringX + (proj.endX - proj.ringX) * phaseT
        cy = proj.ringY + (proj.endY - proj.ringY) * phaseT
        local dx = proj.endX - proj.ringX
        local dy = proj.endY - proj.ringY
        drawAngle = math.atan(dy, dx)
        alpha = 1.0
        if t > 0.88 then
            alpha = 1.0 - (t - 0.88) / 0.12
        end

        if cfg.trail then
            local prevAttackT = math.max(0, phaseT - 0.12)
            local prevX = proj.ringX + (proj.endX - proj.ringX) * prevAttackT
            local prevY = proj.ringY + (proj.endY - proj.ringY) * prevAttackT
            drawTrail(vg, cx, cy, prevX, prevY, cfg.trail, t, cfg.imgW * 0.45)
        end
    end

    local imgHandle = getImage(cfg.imgKey)
    drawProjectileImage(vg, imgHandle, cx, cy, drawW, drawH, drawAngle, alpha)
end

--- 根据起终点距离计算近战 hitRatio，使伤害恰好在特效到达目标时触发
local function calcMeleeHitRatio(startX, startY, endX, endY)
    local dx = endX - startX
    local dy = endY - startY
    local dist = math.sqrt(dx * dx + dy * dy)
    local totalDist = dist + MELEE_OVERSHOOT
    if totalDist < 1 then return MELEE_HIT_RATIO end
    return dist / totalDist
end

-- 类型 → 绘制函数映射
local DRAW_FUNCS = {
    fly          = updateAndDrawFly,
    pierce       = updateAndDrawFly,  -- [单发穿透] 直线路径, 命中事件在 update 中按位置触发
    shake        = updateAndDrawShake,
    bezier       = updateAndDrawBezier,
    lightning    = updateAndDrawLightning,
    slash        = updateAndDrawSlash,
    melee        = updateAndDrawMelee,
    flyingSword  = updateAndDrawFlyingSword,
}

-- ======================== 公共 API ========================

--- 初始化
function ProjectileSystem.init(vg)
    -- 释放旧纹理，防止 GPU 显存泄漏
    if vg_ then
        for _, handle in pairs(images) do
            if handle and handle > 0 then
                nvgDeleteImage(vg_, handle)
            end
        end
    end
    vg_ = vg
    images = {}
    PS_BCS.projectiles = {}
    starGateDrawTime = 0
    print("[ProjectileSystem] init OK")
end

--- 判断英雄是否有远程投射物配置（melee 类型不算远程，用于 isRangedUnit 判断）
function ProjectileSystem.hasProjectile(heroId)
    local cfg = CONFIGS[heroId]
    return cfg ~= nil and cfg.type ~= "melee"
end

--- 判断英雄是否有任何攻击特效配置（包括 melee，用于 onAttackHit 触发特效）
function ProjectileSystem.hasHeroEffect(heroId)
    return CONFIGS[heroId] ~= nil
end

--- 判断英雄是否有技能投射物配置
function ProjectileSystem.hasSkillProjectile(heroId)
    return SKILL_CONFIGS[heroId] ~= nil
end

--- 判断转职天赋是否有投射物配置
function ProjectileSystem.hasTalentProjectile(talentProjKey)
    return talentProjKey ~= nil and TALENT_PROJ_CONFIGS[talentProjKey] ~= nil
end

--- 判断怪物攻击特效 key 是否有投射物配置
function ProjectileSystem.hasMonsterProjectile(effectKey)
    return effectKey ~= nil and MONSTER_CONFIGS[effectKey] ~= nil
end

--- 通过特效 key 触发怪物投射物
--- @param effectKey string 特效 key
--- @param startX number 起点 X
--- @param startY number 起点 Y
--- @param endX number 终点 X
--- @param endY number 终点 Y
--- @param onArrive function 到达回调
--- @param isMelee boolean|nil 强制近战模式（共用key时覆盖为melee行为）
--- @param opts table|nil 可选参数 { target = unit } 用于目标死亡时提前取消投射物
function ProjectileSystem.spawnByKey(effectKey, startX, startY, endX, endY, onArrive, isMelee, opts)
    local cfg = MONSTER_CONFIGS[effectKey]
    if not cfg then return end

    -- 播放对应投射物音效
    GameSFX.play(cfg.imgKey)

    -- 近战 override：共用 key（如 EF_MS_13, EF_MS_7, EF_MS_47）被近战怪物使用时，
    -- 强制替换为 melee 行为（极快穿透）
    if isMelee and cfg.type ~= "melee" then
        cfg = {
            type     = "melee",
            imgKey   = cfg.imgKey,
            imgW     = cfg.imgW,
            imgH     = cfg.imgH,
            duration = MELEE_DEFAULT_CFG.duration,
            hitRatio = calcMeleeHitRatio(startX, startY, endX, endY),
        }
    end

    -- melee 类型：按距离动态计算 hitRatio
    if cfg.type == "melee" then
        local ratio = calcMeleeHitRatio(startX, startY, endX, endY)
        cfg = setmetatable({ hitRatio = ratio }, { __index = cfg })
    end

    local proj = {
        cfg      = cfg,
        timer    = 0,
        startX   = startX,
        startY   = startY,
        endX     = endX,
        endY     = endY,
        onArrive = onArrive,
        arrived  = false,
        target   = opts and opts.target or nil,
    }

    -- 贝塞尔曲线：随机弯曲方向
    if cfg.type == "bezier" then
        proj.bezierSide = (math.random() > 0.5) and 1 or -1
    end

    -- [看情况抛物线] fly 直线弹距离足够远时升级为弧线（弧顶始终向上）
    if cfg.type == "fly" then
        local ddx, ddy = endX - startX, endY - startY
        if (ddx * ddx + ddy * ddy) >= ARC_TRIGGER_DIST * ARC_TRIGGER_DIST then
            proj.arcUpgrade = true
            proj.bezierSide = (endX >= startX) and -1 or 1
        end
    end

    PS_BCS.projectiles[#PS_BCS.projectiles + 1] = proj
end

--- 触发一个攻击投射物
--- onArrive: 投射物到达目标时的回调（用于延迟伤害）
--- opts: 可选参数 { target = unit } 用于目标死亡时提前取消投射物
function ProjectileSystem.spawn(heroId, startX, startY, endX, endY, onArrive, opts)
    -- [N3-DIAG] 投射物最终坐标
    if Diag.logEnabled then
        print(string.format("[N3-DIAG] ProjSpawn heroId=%s startX=%.1f startY=%.1f endX=%.1f endY=%.1f",
            tostring(heroId), startX, startY, endX, endY))
    end
    local cfg = CONFIGS[heroId]
    if not cfg then return end

    -- 播放对应投射物音效
    GameSFX.play(cfg.imgKey)

    -- melee 类型：按距离动态计算 hitRatio
    if cfg.type == "melee" then
        local ratio = calcMeleeHitRatio(startX, startY, endX, endY)
        cfg = setmetatable({ hitRatio = ratio }, { __index = cfg })
    end

    local proj = {
        cfg      = cfg,
        timer    = 0,
        startX   = startX,
        startY   = startY,
        endX     = endX,
        endY     = endY,
        onArrive = onArrive,
        arrived  = false,
        target   = opts and opts.target or nil,
    }

    -- 贝塞尔曲线：随机弯曲方向
    if cfg.type == "bezier" then
        proj.bezierSide = (math.random() > 0.5) and 1 or -1
    end

    PS_BCS.projectiles[#PS_BCS.projectiles + 1] = proj
end

--- [单发穿透] 一发弹沿直线穿过目标群, 按位置进度(atT)依次触发命中事件
--- 与"一次丢 N 个弹"相对: 多目标攻击只飞一发, 视觉为穿透
--- @param source table { heroId=id } 或 { key=effectKey }（弹体视觉取自对应配置）
--- @param hitEvents table[] 已按 atT 升序排序的 { atT=0..1, onHit=function }
--- @return boolean 是否成功生成（无弹体配置返回 false, 调用方回退逐目标）
function ProjectileSystem.spawnPierce(source, startX, startY, endX, endY, hitEvents, opts)
    local base = nil
    if type(source) == "table" then
        if source.heroId then base = CONFIGS[source.heroId]
        elseif source.key then base = MONSTER_CONFIGS[source.key] end
    end
    if not base or not hitEvents or #hitEvents == 0 then return false end

    -- 防御: 强制按 atT 升序（探测曾抓到插入序触发/队头阻塞问题）
    table.sort(hitEvents, function(a, b) return (a.atT or 0) < (b.atT or 0) end)

    local cfg = setmetatable({ type = "pierce" }, { __index = base })
    if base.imgKey then GameSFX.play(base.imgKey) end

    local proj = {
        cfg          = cfg,
        timer        = 0,
        startX       = startX,
        startY       = startY,
        endX         = endX,
        endY         = endY,
        pierceEvents = hitEvents,
        nextEventIdx = 1,
        onArrive     = opts and opts.onArrive or nil,
        arrived      = false,
    }
    PS_BCS.projectiles[#PS_BCS.projectiles + 1] = proj
    return true
end

--- 触发一个技能投射物
function ProjectileSystem.spawnSkill(heroId, startX, startY, endX, endY, onArrive, opts)
    local cfg = SKILL_CONFIGS[heroId]
    if not cfg then return end

    -- 播放对应投射物音效
    GameSFX.play(cfg.imgKey)

    local proj = {
        cfg      = cfg,
        timer    = 0,
        startX   = startX,
        startY   = startY,
        endX     = endX,
        endY     = endY,
        onArrive = onArrive,
        arrived  = false,
        target   = opts and opts.target or nil,
    }

    -- 贝塞尔曲线：设置弯曲方向
    if cfg.type == "bezier" then
        if opts and opts.bezierSide then
            proj.bezierSide = opts.bezierSide
        else
            proj.bezierSide = (math.random() > 0.5) and 1 or -1
        end
    end

    -- 灵月飞剑：从卡片中心外扩至圆上，再齐射
    if cfg.type == "flyingSword" then
        local count = (opts and opts.flyingSwordCount) or 1
        local idx = (opts and opts.flyingSwordIndex) or 1
        local radius = ((opts and opts.flyingSwordRadius) or 90) * renderScale
        local angleOnRing = (2 * math.pi / count) * (idx - 1) - math.pi * 0.5
        proj.centerX = startX
        proj.centerY = startY
        proj.ringX = startX + math.cos(angleOnRing) * radius
        proj.ringY = startY + math.sin(angleOnRing) * radius
        proj.spawnAngle = math.atan(endY - startY, endX - startX)
    end

    PS_BCS.projectiles[#PS_BCS.projectiles + 1] = proj
end

--- 触发一个转职天赋投射物（按 talentProjKey 查找配置，不依赖 heroId）
--- @param talentProjKey string 天赋投射物 key（如 "EF_ZY_106"）
--- @param startX number 起点 X
--- @param startY number 起点 Y
--- @param endX number 终点 X
--- @param endY number 终点 Y
--- @param onArrive function 到达回调
--- @param opts table|nil 可选参数 { bezierSide = 1|-1 }
function ProjectileSystem.spawnTalent(talentProjKey, startX, startY, endX, endY, onArrive, opts)
    local cfg = TALENT_PROJ_CONFIGS[talentProjKey]
    if not cfg then return end

    -- 播放对应投射物音效
    GameSFX.play(cfg.imgKey)

    local proj = {
        cfg      = cfg,
        timer    = 0,
        startX   = startX,
        startY   = startY,
        endX     = endX,
        endY     = endY,
        onArrive = onArrive,
        arrived  = false,
    }

    if cfg.type == "bezier" then
        if opts and opts.bezierSide then
            proj.bezierSide = opts.bezierSide
        else
            proj.bezierSide = (math.random() > 0.5) and 1 or -1
        end
    end

    PS_BCS.projectiles[#PS_BCS.projectiles + 1] = proj
end

local function safeInvokeProjectileCallback(label, fn)
    if not fn then return nil end
    local ok, ret = pcall(fn)
    if not ok then
        print("[ProjectileSystem] " .. tostring(label) .. " callback failed: " .. tostring(ret))
        return nil
    end
    return ret
end

--- 每帧更新
function ProjectileSystem.update(dt)
    starGateDrawTime = starGateDrawTime + dt
    local i = 1
    while i <= #PS_BCS.projectiles do
        local proj = PS_BCS.projectiles[i]
        proj.timer = proj.timer + dt

        -- [单发穿透] 按飞行进度依次触发沿线命中事件
        if proj.pierceEvents and not proj.arrived then
            local pdur = (proj.cfg and proj.cfg.duration) or 0.5
            if pdur <= 0 then pdur = 0.01 end
            local pt = math.min(1, proj.timer / pdur)
            while proj.nextEventIdx <= #proj.pierceEvents
                  and proj.pierceEvents[proj.nextEventIdx].atT <= pt do
                local ev = proj.pierceEvents[proj.nextEventIdx]
                proj.nextEventIdx = proj.nextEventIdx + 1
                if ev.onHit then
                    safeInvokeProjectileCallback("pierce-hit", ev.onHit)
                end
            end
        end

        -- 目标死亡检测：如果投射物跟踪的目标已死亡，立即触发到达并快速消失
        -- 防止治疗投射物飞向墓碑的视觉问题
        if not proj.arrived and not proj.hitResolved and proj.target and proj.target.hp and proj.target.hp <= 0 then
            proj.hitResolved = true
            proj.arrived = true
            if proj.onArrive then
                safeInvokeProjectileCallback("onArrive(dead-target)", proj.onArrive)
            end
            -- 强制跳到尾部让其快速淡出移除
            proj.timer = (proj.cfg and proj.cfg.duration) or 0.01
        end

        -- 到达时触发回调（仅一次）
        -- hitRatio: 闪电链等视觉先到达的投射物，按比例提前触发伤害
        local duration = (proj.cfg and proj.cfg.duration) or 0.01
        if duration <= 0 then duration = 0.01 end
        local hitTime = duration
        if proj.cfg.hitRatio then
            hitTime = duration * proj.cfg.hitRatio
        end
        if not proj.arrived and proj.timer >= hitTime then
            if proj.isFlybackReturn then
                if not proj.returnHitDone then
                    proj.returnHitDone = true
                    if proj.onReturnHit then safeInvokeProjectileCallback("onReturnHit", proj.onReturnHit) end
                end
                if proj.timer >= duration then
                    proj.arrived = true
                end
            else
                local continueFb = nil
                if not proj.hitResolved then
                    proj.hitResolved = true
                    if proj.onArrive then
                        continueFb = safeInvokeProjectileCallback("onArrive", proj.onArrive)
                    end
                end
                if continueFb and type(continueFb) == "table" and proj.cfg.type == "flyingSword" then
                    setupFlybackContinuation(proj, continueFb)
                else
                    proj.arrived = true
                end
            end
        end
        -- 加一点淡出余量（duration 后多保留 0.15s 用于淡出动画）
        if proj.timer >= duration + 0.15 then
            table.remove(PS_BCS.projectiles, i)
        else
            i = i + 1
        end
    end
end

--- 绘制摘星星星人常驻星门召唤物
---@param vg table
---@param units table[]
---@param cardCY number 兜底 Y（列阵下为战场中心）
---@param getCardCX function
---@param isAlly boolean
-- [左4vs右4] getCardCY 可选: 按索引取竖排 Y
---@param getCardCY function|nil
function ProjectileSystem.drawStarGates(vg, units, cardCY, getCardCX, isAlly, getCardCY)
    if not vg or not units or not getCardCX then return end
    local imgHandle = getImage("EF_skill_20")
    for i, unit in ipairs(units) do
        local shouldDraw = unit
            and unit.heroId == 20
            and ((unit.hp and unit.hp > 0) or (unit._starGatePersistsAfterDeath and unit._starGateSummoned))
        if shouldDraw then
            local count = unit._starGateCount or 1
            if count <= 0 then
                count = (unit.awakeningNodes and unit.awakeningNodes[6] == true) and 2 or 1
            end
            local baseX = getCardCX(units, i)
            local baseCY = getCardCY and getCardCY(units, i) or cardCY
            for gateIndex = 1, count do
                local cx, cy = getStarGateDrawPosition(baseX, baseCY, gateIndex, count, isAlly)
                local pulse = 0.94 + 0.06 * math.sin(starGateDrawTime * 3.4 + gateIndex)
                local size = 118 * pulse * renderScale
                local alpha = 0.88 + 0.12 * math.sin(starGateDrawTime * 2.6 + gateIndex * 0.7)
                drawStarGateAura(vg, cx, cy, size, alpha)
                drawProjectileImage(vg, imgHandle, cx, cy, size, size, starGateDrawTime * 1.8 * (isAlly and 1 or -1), alpha)
            end
        end
    end
end

--- 绘制所有活跃投射物
function ProjectileSystem.draw(vg)
    for _, proj in ipairs(PS_BCS.projectiles) do
        local duration = (proj.cfg and proj.cfg.duration) or 0.01
        if duration <= 0 then duration = 0.01 end
        local t = math.min(1, proj.timer / duration)
        local trajType = proj.cfg.type
        if proj.arcUpgrade then trajType = "bezier" end  -- [看情况抛物线]
        local drawFunc = DRAW_FUNCS[trajType]
        if drawFunc then
            nvgSave(vg)
            drawFunc(proj, vg, t)
            nvgRestore(vg)
        end
    end
end

--- 清除所有投射物
function ProjectileSystem.reset()
    PS_BCS.projectiles = {}
    starGateDrawTime = 0
end

--- 获取当前活跃投射物数量（调试用）
function ProjectileSystem.getActiveCount()
    return #PS_BCS.projectiles
end

return ProjectileSystem
