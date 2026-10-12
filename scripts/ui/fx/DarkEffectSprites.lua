-- 暗黑特效渲染：每条播放独占 Spine，缺扩展/素材时降级到分层 PNG，再到旧矢量。
-- 控制器持有墙钟与业务回调；本模块只按 elapsed 采样，不订阅事件、不修改玩家数据。
-- token 为可选的独立 table；省略时仅绘制 PNG/矢量，绝不逐帧创建原生实例。
-- PNG 按 vg + 资源路径共享，预热/失败均锁存；release 只释放该 token 的原生对象。
-- destroy 由宿主 Stop 在销毁 vg 前统一调用，不能被某一个控制器抢先清掉共享贴图。
local Primitives = require("ui.fx.DarkEffectPrimitives")
local M = {}
local ROOT = "image/暗黑特效/"

---@class DarkSpriteContext
---@field vg NVGContextWrapper
---@field images table<string, integer>
---@field prepared boolean
---@field broken boolean
---@class DarkSpritePlayback
---@field vg NVGContextWrapper
---@field family string
---@field animation string
---@field attempted boolean
---@field nativeFailed boolean
---@field pngFailed boolean
---@field overlayFailed boolean
---@field instance SpineInstance|nil
---@field sweepSlot SpineSlot|nil
---@field lastElapsed number
---@field lastCx number?
---@field lastCy number?
---@field lastSx number?
---@field lastSy number?
---@field animationDuration number
---@field released boolean
---@type table<any, DarkSpriteContext>
local contexts = {}
---@type table<table, DarkSpritePlayback>
local playbacks = {}
-- 弱键墓碑阻止旧 draw 快照在 stop/回调重入后复活；不持有已完成的业务记录。
---@type table<table, boolean>
local retired = setmetatable({}, { __mode = "k" })

local REGIONS = {
    "seal_plate", "gate_leaf", "rift_light", "smoke_flame", "soul_flame", "seal_shard",
    "rune_ring", "ember", "copper_wing", "nameplate", "impact_glow", "rune_strip",
    "ash_flake", "light_sweep",
}
local REQUIRED = {
    level = { "seal_plate", "rune_ring", "smoke_flame", "impact_glow", "rune_strip", "ember", "light_sweep" },
    job = { "gate_leaf", "rift_light", "rune_ring", "smoke_flame", "impact_glow", "ember", "light_sweep" },
    revive = { "ash_flake", "soul_flame", "smoke_flame", "rune_ring", "seal_plate", "rune_strip", "impact_glow" },
    success = { "seal_plate", "seal_shard", "rune_ring", "copper_wing", "rune_strip", "impact_glow", "ember", "light_sweep" },
    failure = { "seal_plate", "seal_shard", "rune_ring", "smoke_flame", "impact_glow", "ash_flake", "light_sweep" },
    power = { "nameplate", "copper_wing", "rune_ring", "rift_light", "smoke_flame", "rune_strip", "ember" },
}
local WHITE = { 255, 255, 255 }
local ASH = { 164, 157, 143 }
local BLOOD = { 207, 96, 77 }

---@param value any
---@return boolean
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function clamp(value)
    return math.max(0, math.min(1, value))
end

local function smooth(value)
    local t = clamp(value)
    return t * t * (3 - 2 * t)
end

local function stage(p, from, to)
    return smooth((p - from) / (to - from))
end

local function validBox(cx, cy, width, height)
    return finite(cx) and finite(cy) and finite(width) and finite(height)
        and math.abs(cx) <= 1e6 and math.abs(cy) <= 1e6
        and width >= 1e-4 and height >= 1e-4 and width <= 1e6 and height <= 1e6
end

local function phase(elapsed, duration, alpha)
    local a = alpha == nil and 1 or alpha
    if not finite(elapsed) or not finite(duration) or not finite(a) or duration <= 0
        or elapsed <= 0 or elapsed >= duration then return 0, 0 end
    local p = elapsed / duration
    return p, clamp(a) * stage(p, 0, .10) * (1 - stage(p, .80, 1))
end

---@param object any
---@param name string
---@return boolean
local function hasMethod(object, name)
    local ok, method = pcall(function() return object[name] end)
    return ok and type(method) == "function"
end

---@param entry DarkSpritePlayback
local function disposeNative(entry)
    -- 先摘掉引用；只执行一种原生释放，实测 Unload 后再 Dispose 会原生崩溃。
    -- 优先卸载骨架/贴图并交 GC 收对象；缺 Unload 的旧扩展才调用 Dispose。
    local instance = entry.instance
    entry.instance, entry.sweepSlot = nil, nil
    if not instance then return end
    if hasMethod(instance, "Unload") then
        local ok, err = pcall(function() instance:Unload() end)
        if not ok then print("[DarkEffectSprites] 骨架卸载失败: " .. tostring(err)) end
    elseif hasMethod(instance, "Dispose") then
        local ok, err = pcall(function() instance:Dispose() end)
        if not ok then print("[DarkEffectSprites] 骨架释放失败: " .. tostring(err)) end
    end
end

---@param token? table
function M.release(token)
    if type(token) ~= "table" then return end
    retired[token] = true
    local entry = playbacks[token]
    playbacks[token] = nil
    if not entry or entry.released then return end
    entry.released = true
    disposeNative(entry)
end

-- Save/Restore 失败属于最终绘图故障；不可在未知状态栈上继续尝试另一后端。
---@param vg NVGContextWrapper
---@param painter fun()
---@return boolean drawn
---@return any reason
---@return boolean restored
local function isolated(vg, painter)
    local saved, saveError = pcall(nvgSave, vg)
    if not saved then return false, saveError, false end
    local drawn, drawError = pcall(painter)
    local restored, restoreError = pcall(nvgRestore, vg)
    if not restored then
        return false, tostring(drawError) .. " [NanoVG restore failed: " .. tostring(restoreError) .. "]", false
    end
    return drawn, drawError, true
end

---@param vg NVGContextWrapper
---@return DarkSpriteContext
local function contextFor(vg)
    local existing = contexts[vg]
    if existing then return existing end
    local created = { vg = vg, images = {}, prepared = false, broken = false }
    contexts[vg] = created
    return created
end

local function imageAPI()
    return type(nvgCreateImage) == "function" and type(nvgBeginPath) == "function"
        and type(nvgMoveTo) == "function" and type(nvgLineTo) == "function"
        and type(nvgClosePath) == "function" and type(nvgFillPaint) == "function"
        and type(nvgFill) == "function" and type(nvgSave) == "function"
        and type(nvgRestore) == "function" and type(nvgTranslate) == "function"
        and type(nvgScale) == "function"
        and ((type(nvgImagePatternTinted) == "function" and type(nvgRGBA) == "function")
            or type(nvgImagePattern) == "function")
end

---@param vg? NVGContextWrapper
function M.preload(vg)
    if not vg then return end
    local context = contextFor(vg)
    if context.prepared then return end
    context.prepared = true -- 在任何原生调用前锁存，缺 API/缺图也不逐帧重试。
    if not imageAPI() then
        context.broken = true
        print("[DarkEffectSprites] 图片 API 不完整，使用矢量兜底")
        return
    end
    local loaded = 0
    for _, name in ipairs(REGIONS) do
        local path = ROOT .. name .. ".png"
        context.images[path] = 0
        local ok, image = pcall(function() return nvgCreateImage(vg, path, 0) end)
        if ok and finite(image) and image > 0 and image == math.floor(image) then
            context.images[path] = math.floor(image)
            loaded = loaded + 1
        else
            print("[DarkEffectSprites] 图片预热失败，不重试: " .. path)
        end
    end
    print("[DarkEffectSprites] 图片预热 " .. loaded .. "/" .. #REGIONS)
end

---@param context DarkSpriteContext
---@param animation string
---@return boolean
local function imagesReady(context, animation)
    if context.broken then return false end
    local required = REQUIRED[animation]
    if not required then return false end
    for _, name in ipairs(required) do
        if (context.images[ROOT .. name .. ".png"] or 0) <= 0 then return false end
    end
    return true
end

---@param vg NVGContextWrapper
---@param family string
---@param animation string
---@param token? table
---@return DarkSpritePlayback|nil
local function playbackFor(vg, family, animation, token)
    if type(token) ~= "table" or retired[token] then return nil end
    local existing = playbacks[token]
    if existing then
        -- token 只能代表一条播放；跨 context/动画不得再次加载同一个原生实例。
        if existing.vg ~= vg or existing.family ~= family or existing.animation ~= animation then
            existing.nativeFailed, existing.pngFailed = true, true
            disposeNative(existing)
        end
        return existing
    end
    local created = {
        vg = vg, family = family, animation = animation, attempted = false,
        nativeFailed = false, pngFailed = false, overlayFailed = false, instance = nil,
        lastElapsed = 0, animationDuration = 0, released = false,
    }
    playbacks[token] = created
    return created
end

---@param entry DarkSpritePlayback
local function attemptNative(entry)
    if entry.attempted or entry.released then return end
    entry.attempted = true
    if type(nvgSpineCreate) ~= "function" or type(nvgSpineRender) ~= "function" then
        entry.nativeFailed = true
        return
    end
    local ok, err = pcall(function()
        local instance = nvgSpineCreate(entry.vg)
        if not instance then error("SpineInstance 创建失败", 0) end
        entry.instance = instance
        for _, name in ipairs({ "Load", "SetAnimation", "GetAnimationDuration", "Update", "SetPosition", "SetScale", "SetColor" }) do
            if not hasMethod(instance, name) then error("Spine API 缺失: " .. name, 0) end
        end
        if not hasMethod(instance, "Unload") and not hasMethod(instance, "Dispose") then
            error("Spine 缺少释放 API", 0)
        end
        if instance:Load(ROOT .. entry.family .. "_fx.json") ~= true then error("Spine Load 失败", 0) end
        if entry.released then return end
        if entry.family == "power" then
            if not hasMethod(instance, "FindSlot") then error("Spine API 缺失: FindSlot", 0) end
            local sweepSlot = instance:FindSlot("sweep")
            if not sweepSlot or not sweepSlot:IsValid() then error("Spine 战力扫光槽缺失", 0) end
            entry.sweepSlot = sweepSlot
        end
        -- 无 listener，完成由原控制器墙钟派发，原生动画不参与业务回调。
        if instance:SetAnimation(0, entry.animation, false) ~= true then error("Spine SetAnimation 失败", 0) end
        local seconds = instance:GetAnimationDuration(0)
        if not finite(seconds) or seconds <= 0 then error("Spine 动画时长无效", 0) end
        entry.animationDuration = seconds
        if hasMethod(instance, "SetSpeed") then instance:SetSpeed(1) end
        if hasMethod(instance, "SetTimeScale") then instance:SetTimeScale(1) end
        if hasMethod(instance, "SetPremultipliedAlpha") then instance:SetPremultipliedAlpha(false) end
    end)
    if not ok then
        entry.nativeFailed = true
        disposeNative(entry)
        print("[DarkEffectSprites] 骨架单次降级 " .. entry.animation .. ": " .. tostring(err))
    end
end

---@param vg NVGContextWrapper
---@param entry DarkSpritePlayback
---@param cx number
---@param cy number
---@param sx number
---@param sy number
---@param elapsed number
---@param duration number
---@param alpha number
---@return boolean
local function drawNative(vg, entry, cx, cy, sx, sy, elapsed, duration, alpha)
    attemptNative(entry)
    local instance = entry.instance
    if entry.released or entry.nativeFailed or not instance then return false end
    local ok, err, restored = isolated(vg, function()
        -- Spine 的 Y-up 在骨架上翻转；不再乘 DPR，不读取任何全局 fit。
        local transformChanged = entry.lastCx ~= cx or entry.lastCy ~= cy or entry.lastSx ~= sx or entry.lastSy ~= sy
        instance:SetScale(sx, -sy)
        instance:SetPosition(cx, cy)
        instance:SetColor(1, 1, 1, alpha)
        local delta = math.max(0, elapsed - entry.lastElapsed)
        if delta > 0 then
            entry.lastElapsed = elapsed -- 先记采样，重复 draw/同帧多宿主不会重复推进。
            instance:Update(delta * entry.animationDuration / duration)
        elseif transformChanged then
            -- 同时间改变队数/窗口尺寸仍须刷新骨骼，不重播动画、不增加 track time。
            if hasMethod(instance, "UpdateWorldTransform") then instance:UpdateWorldTransform()
            else instance:Update(0) end
        end
        entry.lastCx, entry.lastCy, entry.lastSx, entry.lastSy = cx, cy, sx, sy
        if not entry.released then
            -- 动画 Update 会重写槽透明度，必须在渲染前屏蔽横穿文字区的 Spine 扫光。
            if entry.sweepSlot then entry.sweepSlot:SetColor(1, 1, 1, 0) end
            nvgSpineRender(vg, instance)
        end
    end)
    if ok then return true end
    entry.nativeFailed = true
    disposeNative(entry)
    if not restored then error(err, 0) end
    print("[DarkEffectSprites] 骨架绘图单次降级 " .. entry.animation .. ": " .. tostring(err))
    return false
end

-- 图片路径为旋转四边形；反射通过 ImagePattern 的负 X 比例实现，不增加嵌套状态帧。
-- 每层 alpha 乘入 tint；旧铜/骨白/魂焰的真实纹理不被统一换色，也不改 globalAlpha/scissor。
---@param vg NVGContextWrapper
---@param context DarkSpriteContext
---@param name string
---@param x number
---@param y number
---@param width number
---@param height number
---@param angle number
---@param alpha number
---@param flip? boolean
---@param tint? number[]
local function sprite(vg, context, name, x, y, width, height, angle, alpha, flip, tint)
    if alpha <= 0 or width <= 0 or height <= 0 then return end
    local image = context.images[ROOT .. name .. ".png"] or 0
    if image <= 0 then error("图片层缺失: " .. name, 0) end
    local c, s = math.cos(angle), math.sin(angle)
    local hx, hy = width * .5, height * .5
    nvgBeginPath(vg)
    nvgMoveTo(vg, x - hx * c + hy * s, y - hx * s - hy * c)
    nvgLineTo(vg, x + hx * c + hy * s, y + hx * s - hy * c)
    nvgLineTo(vg, x + hx * c - hy * s, y + hx * s + hy * c)
    nvgLineTo(vg, x - hx * c - hy * s, y - hx * s + hy * c)
    nvgClosePath(vg)
    local sign = flip and -1 or 1
    local ox, oy = x - sign * hx * c + hy * s, y - sign * hx * s - hy * c
    if type(nvgImagePatternTinted) == "function" and type(nvgRGBA) == "function" then
        local rgb = tint or WHITE
        local color = nvgRGBA(rgb[1], rgb[2], rgb[3], math.floor(clamp(alpha) * 255 + .5))
        ---@cast color NVGcolor
        local paint = nvgImagePatternTinted(vg, ox, oy, sign * width, height, angle, image, color)
        ---@cast paint NVGpaint
        nvgFillPaint(vg, paint)
    else
        local paint = nvgImagePattern(vg, ox, oy, sign * width, height, angle, image, clamp(alpha))
        ---@cast paint NVGpaint
        nvgFillPaint(vg, paint)
    end
    nvgFill(vg)
end

-- preparation/impact/sustain/fade 为各层独立时间线；固定轨迹，不触碰战斗随机数。
local function level(vg, context, p, a)
    local bind, lift = stage(p, .06, .30), stage(p, .30, .76)
    local impact = stage(p, .20, .32) * (1 - stage(p, .38, .54))
    local burn = stage(p, .26, .43) * (1 - stage(p, .72, .96))
    sprite(vg, context, "smoke_flame", 0, 30 - lift * 34, 140, 220, 0, a * burn * .43)
    sprite(vg, context, "rune_ring", 0, 68, 140 + bind * 16, 48, -p * .6, a * (1 - lift * .4) * .8)
    sprite(vg, context, "seal_plate", 0, 59 - impact * 3, 64 + bind * 24, 64 + bind * 24, 0, a * .95)
    sprite(vg, context, "impact_glow", 0, 15, 125, 190, 0, a * (impact * .65 + burn * .12))
    for i = 1, 2 do
        local side = i == 1 and -1 or 1
        sprite(vg, context, "smoke_flame", side * (23 - lift * 7), 12 - lift * 58,
            52, 140 + lift * 85, side * .10, a * burn * .86, side < 0)
    end
    sprite(vg, context, "rune_strip", 0, 21 - lift * 47, 29, 126, 0, a * burn * .93)
    sprite(vg, context, "light_sweep", -42 + lift * 82, 52 - lift * 100, 132, 22,
        -1.05, a * (impact * .83 + burn * .21))
    for i = 1, 8 do
        local q = clamp((p - .24 - i * .021) / .48)
        local life = smooth(q * 9) * (1 - stage(q, .68, 1))
        local side = i % 2 == 0 and 1 or -1
        sprite(vg, context, "ember", side * (18 + i * 4 + q * 15), 72 - q * (126 + i * 7),
            6 + i % 3, 13 + i % 3 * 2, side * (.2 + q * .65), a * life * .88)
    end
end

local function job(vg, context, p, a)
    local open = stage(p, .13, .57)
    local light = stage(p, .19, .34) * (1 - stage(p, .71, .95))
    local impact = stage(p, .22, .35) * (1 - stage(p, .40, .56))
    sprite(vg, context, "smoke_flame", 0, 0, 158, 286, 0, a * light * .36)
    sprite(vg, context, "rune_ring", 0, 104, 158, 53, p * .52, a * .76)
    sprite(vg, context, "rift_light", 0, -5, 12 + open * 35, 312, 0, a * light)
    sprite(vg, context, "impact_glow", 0, -16, 97, 274, 0, a * impact * .58)
    for i = 1, 2 do
        local side = i == 1 and -1 or 1
        sprite(vg, context, "gate_leaf", side * (29 + open * 37), 0,
            58 * (1 - open * .47), 312, 0, a, side > 0)
        sprite(vg, context, "light_sweep", side * (9 + open * 26), -13, 236, 12,
            math.pi * .5, a * light * (.38 + impact * .4), side > 0)
    end
    for i = 1, 6 do
        local q = clamp((p - .29 - i * .021) / .44)
        local life = smooth(q * 8) * (1 - stage(q, .69, 1))
        local side = i % 2 == 0 and 1 or -1
        sprite(vg, context, "ember", side * (8 + q * (35 + i * 4)), -94 + i * 28 - q * 23,
            7, 16, side * q * 1.4, a * life)
    end
end

local function revive(vg, context, p, a)
    local gather, rise = stage(p, .06, .51), stage(p, .45, .82)
    local soul = stage(p, .38, .58) * (1 - stage(p, .81, .98))
    sprite(vg, context, "rune_ring", 0, 75, 149, 53, -p * .7, a * (.7 - rise * .3))
    sprite(vg, context, "seal_plate", 0, 75, 66, 34, 0, a * soul * .67, false, ASH)
    sprite(vg, context, "smoke_flame", 0, 31 - rise * 42, 139, 213, -.05, a * soul * .29, false, ASH)
    for i = 1, 10 do
        local side = i % 2 == 0 and 1 or -1
        local x = side * ((44 + i * 3) * (1 - gather) + math.sin(gather * math.pi) * 12)
        local y = (-105 + i * 22) * (1 - gather) + gather * 43 - math.sin(gather * math.pi) * (i % 3) * 11
        sprite(vg, context, "ash_flake", x, y, 10 + i % 4 * 2, 10 + i % 3 * 2,
            side * (1 - gather) * 1.1, a * (1 - stage(p, .46, .65)) * .85)
    end
    sprite(vg, context, "impact_glow", 0, -8, 90, 190, 0, a * soul * .33, false, ASH)
    sprite(vg, context, "soul_flame", 0, 34 - rise * 58, 67 + rise * 13, 139 + rise * 58,
        0, a * soul)
    sprite(vg, context, "rune_strip", 0, 12 - rise * 35, 17, 111, 0, a * soul * .58, false, ASH)
end

local function success(vg, context, p, a)
    local gather, stamp = stage(p, .08, .41), stage(p, .38, .55)
    local impact = stage(p, .35, .47) * (1 - stage(p, .56, .71))
    sprite(vg, context, "rune_ring", 0, 0, 173, 173, p * .38, a * (.48 + stamp * .3))
    sprite(vg, context, "seal_plate", 0, 0, 122, 122, 0, a * (.25 + stamp * .72))
    for i = 1, 4 do
        local side = i % 2 == 0 and 1 or -1
        local row = i <= 2 and -1 or 1
        sprite(vg, context, "seal_shard", side * (48 - gather * 22), row * (43 - gather * 20),
            33, 49, side * (1 - gather) * .6, a * (1 - stage(p, .42, .61)))
    end
    sprite(vg, context, "impact_glow", 0, -6, 160, 160, 0, a * impact * .67)
    for i = 1, 2 do
        local side = i == 1 and -1 or 1
        sprite(vg, context, "copper_wing", side * (63 + stamp * 5), 3, 49, 29,
            side * (1 - stamp) * .15, a * stamp * .93, side > 0)
    end
    sprite(vg, context, "rune_strip", 0, -3, 37, 108, 0, a * stamp)
    sprite(vg, context, "light_sweep", -38 + stamp * 76, 27 - stamp * 57, 144, 23, -.35, a * impact * .82)
    for i = 1, 6 do
        local q = clamp((p - .16 - i * .016) / .37)
        local side = i % 2 == 0 and 1 or -1
        local life = smooth(q * 8) * (1 - stage(q, .70, 1))
        sprite(vg, context, "ember", side * (68 - q * 51), -49 + i * 15 - q * 8,
            6, 15, side * q, a * life * .9)
    end
end

local function failure(vg, context, p, a)
    local fracture, fall = stage(p, .12, .36), stage(p, .31, .86)
    local dim = 1 - stage(p, .43, .90)
    local impact = stage(p, .14, .25) * (1 - stage(p, .36, .53))
    sprite(vg, context, "rune_ring", 0, fall * 12, 159, 153 - fall * 106,
        -.18 - fracture * .26, a * dim * .68, false, ASH)
    sprite(vg, context, "seal_plate", 0, 0, 121, 121, -.06,
        a * (1 - stage(p, .22, .43)), false, ASH)
    sprite(vg, context, "impact_glow", 0, -6, 160, 145, 0, a * impact * .54, false, BLOOD)
    sprite(vg, context, "smoke_flame", 0, -17 - fall * 27, 149, 144,
        .13, a * fracture * dim * .44, false, ASH)
    for i = 1, 6 do
        local side = i % 2 == 0 and 1 or -1
        local x = side * (13 + i * 4 + fracture * 8 + fall * (12 + i * 3))
        local y = -43 + i * 12 - fracture * (9 - i) + fall * fall * (22 + i * 3)
        sprite(vg, context, "seal_shard", x, y, 23 + i % 3 * 4, 35 + i % 2 * 6,
            side * fall * (.23 + i * .12), a * fracture * dim, side > 0, ASH)
    end
    for i = 1, 2 do
        local side = i == 1 and -1 or 1
        sprite(vg, context, "light_sweep", side * (8 + fracture * 16), -10, 106, 11,
            side * .9, a * impact * .66, side > 0, BLOOD)
    end
    for i = 1, 5 do
        local side = i % 2 == 0 and 1 or -1
        sprite(vg, context, "ash_flake", side * (12 + fall * i * 11), 23 + fall * fall * 66 - i * 7,
            8, 8, side * fall * 2, a * dim * fracture * .7, false, ASH)
    end
end

local function power(vg, context, p, a)
    local split = stage(p, .09, .35)
    local impact = stage(p, .20, .34) * (1 - stage(p, .44, .58))
    -- 铭牌中部留给 UI 文字；烟、符轮、魂隙集中于两端，不铺整屏亮雾。
    sprite(vg, context, "nameplate", 0, 0, 740, 340, 0, a * .97)
    for i = 1, 2 do
        local side = i == 1 and -1 or 1
        sprite(vg, context, "smoke_flame", side * 315, -8, 81, 142, side * .08, a * impact * .36, side > 0)
        sprite(vg, context, "rune_ring", side * 304, 0, 82, 82, side * p * .62, a * split * .55)
        sprite(vg, context, "copper_wing", side * (302 + split * 10), 0,
            116, 77, side * (1 - split) * .08, a, side > 0)
        sprite(vg, context, "rift_light", side * 310, 0, 19, 132, 0, a * impact * .58, side > 0)
        sprite(vg, context, "rune_strip", side * 294, 0, 19, 103, 0, a * split * .65, side > 0)
    end
    -- 不在数字阅读区绘制横向扫光，只保留铭牌两侧动效。
    for i = 1, 8 do
        local q = clamp((p - .18 - i * .026) / .45)
        local life = smooth(q * 8) * (1 - stage(q, .70, 1))
        local side = i % 2 == 0 and 1 or -1
        sprite(vg, context, "ember", side * (312 + i * 2 + q * 15), 29 - q * (48 + i * 4),
            5 + i % 2 * 2, 12 + i % 3, side * q, a * life * .82)
    end
end

-- Spine 主体之外的程序补层：少量旧铜光片/骨白灰屑/血红火星，不重复整套 PNG。
-- 每片都按归一化时间轨迹运动，隐藏后的第一帧直接采样，不累加粒子或随机数。
local function accents(vg, family, animation, p, alpha)
    local impact = stage(p, .18, .32) * (1 - stage(p, .43, .60))
    local shade = animation == "revive" and ASH or (animation == "failure" and BLOOD or { 223, 160, 91 })
    for i = 1, 6 do
        local q = clamp((p - .18 - i * .027) / .56)
        local life = smooth(q * 8) * (1 - stage(q, .70, 1))
        local side = i % 2 == 0 and 1 or -1
        local x, y = side * (16 + i * 5 + q * 19), 67 - q * (100 + i * 9)
        if family == "power" then x, y = side * (316 + i * 2 + q * 12), 27 - q * (39 + i * 5)
        elseif family == "result" then x, y = side * (35 + q * (18 + i * 3)), -32 + i * 10 - q * 23 end
        if animation == "failure" then y = y + q * q * 58
        elseif animation == "revive" then x, y = x * (1 - q), y * (1 - q) + q * 18 end
        local opacity = alpha * life * .52
        if opacity > 0 then
            local color = nvgRGBA(shade[1], shade[2], shade[3], math.floor(clamp(opacity) * 255 + .5))
            ---@cast color NVGcolor
            nvgBeginPath(vg)
            nvgMoveTo(vg, x - 1.4, y)
            nvgLineTo(vg, x + side * 1.2, y - 4 - q * 3)
            nvgLineTo(vg, x + 1.4, y + 1.2)
            nvgLineTo(vg, x, y + 3)
            nvgClosePath(vg)
            nvgFillColor(vg, color)
            nvgFill(vg)
        end
    end
    if impact > 0 and family ~= "power" then
        local wide = family == "card" and 74 or 63
        local y = family == "card" and (21 - p * 52) or -7
        local color = nvgRGBA(227, 202, 162, math.floor(clamp(alpha * impact * .34) * 255 + .5))
        ---@cast color NVGcolor
        nvgBeginPath(vg)
        nvgMoveTo(vg, -wide, y + 6)
        nvgLineTo(vg, wide * .76, y - 12)
        nvgLineTo(vg, wide, y - 10)
        nvgLineTo(vg, -wide * .64, y + 8)
        nvgClosePath(vg)
        nvgFillColor(vg, color)
        nvgFill(vg)
    end
end

---@param vg NVGContextWrapper
---@param entry DarkSpritePlayback
---@param cx number
---@param cy number
---@param sx number
---@param sy number
---@param p number
---@param alpha number
local function drawAccents(vg, entry, cx, cy, sx, sy, p, alpha)
    if entry.overlayFailed or entry.released then return end
    if type(nvgRGBA) ~= "function" or type(nvgFillColor) ~= "function"
        or type(nvgBeginPath) ~= "function" or type(nvgMoveTo) ~= "function"
        or type(nvgLineTo) ~= "function" or type(nvgClosePath) ~= "function"
        or type(nvgFill) ~= "function" or type(nvgTranslate) ~= "function" or type(nvgScale) ~= "function" then
        entry.overlayFailed = true
        return
    end
    local ok, err, restored = isolated(vg, function()
        nvgTranslate(vg, cx, cy)
        nvgScale(vg, sx, sy)
        accents(vg, entry.family, entry.animation, p, alpha)
    end)
    if ok then return end
    entry.overlayFailed = true
    if not restored then error(err, 0) end
    print("[DarkEffectSprites] 程序补层单次停用: " .. tostring(err))
end

---@param vg NVGContextWrapper
---@param context DarkSpriteContext
---@param family string
---@param animation string
---@param cx number
---@param cy number
---@param sx number
---@param sy number
---@param p number
---@param alpha number
---@return boolean drawn
---@return any reason
---@return boolean restored
local function drawImages(vg, context, family, animation, cx, cy, sx, sy, p, alpha)
    return isolated(vg, function()
        nvgTranslate(vg, cx, cy)
        nvgScale(vg, sx, sy)
        if family == "card" then
            if animation == "level" then level(vg, context, p, alpha)
            elseif animation == "job" then job(vg, context, p, alpha)
            else revive(vg, context, p, alpha) end
        elseif family == "result" then
            if animation == "success" then success(vg, context, p, alpha)
            else failure(vg, context, p, alpha) end
        else power(vg, context, p, alpha) end
    end)
end

---@param vg NVGContextWrapper
---@param family string
---@param animation string
---@param cx number
---@param cy number
---@param width number
---@param height number
---@param elapsed number
---@param duration number
---@param alpha number?
---@param token? table
---@return boolean
local function drawRich(vg, family, animation, cx, cy, width, height, elapsed, duration, alpha, token)
    if type(token) == "table" and retired[token] then return true end
    local p, a = phase(elapsed, duration, alpha)
    if a <= 0 then return true end
    local baseW = family == "power" and 760 or 200
    local baseH = family == "card" and 350 or (family == "power" and 340 or 200)
    local sx, sy = width / baseW, height / baseH
    local entry = playbackFor(vg, family, animation, token)
    if entry and drawNative(vg, entry, cx, cy, sx, sy, elapsed, duration, a) then
        drawAccents(vg, entry, cx, cy, sx, sy, p, a)
        return true
    end
    if entry and entry.released then return true end
    M.preload(vg)
    local context = contextFor(vg)
    if (not entry or not entry.pngFailed) and imagesReady(context, animation) then
        local ok, err, restored = drawImages(vg, context, family, animation, cx, cy, sx, sy, p, a)
        if ok then return true end
        if entry then entry.pngFailed = true else context.broken = true end
        if not restored then error(err, 0) end
        print("[DarkEffectSprites] 图片绘图单次降级 " .. animation .. ": " .. tostring(err))
    end
    return false
end

--- 原 drawCard 参数不变，尾参 token 可选；旧调用无需持有原生对象。
---@param vg NVGContextWrapper
---@param kind DarkCardEffectKind
---@param cx number
---@param cy number
---@param width number
---@param height number
---@param elapsed number
---@param duration number
---@param alpha? number
---@param token? table
function M.drawCard(vg, kind, cx, cy, width, height, elapsed, duration, alpha, token)
    if not vg or not validBox(cx, cy, width, height)
        or (kind ~= "level" and kind ~= "job" and kind ~= "revive") then return end
    if not drawRich(vg, "card", kind, cx, cy, width, height, elapsed, duration, alpha, token) then
        Primitives.drawCard(vg, kind, cx, cy, width, height, elapsed, duration, alpha)
    end
end

---@param vg NVGContextWrapper
---@param isSuccess boolean
---@param cx number
---@param cy number
---@param size number
---@param elapsed number
---@param duration number
---@param alpha? number
---@param token? table
function M.drawResult(vg, isSuccess, cx, cy, size, elapsed, duration, alpha, token)
    if type(isSuccess) ~= "boolean" or not vg or not validBox(cx, cy, size, size) then return end
    local animation = isSuccess and "success" or "failure"
    if not drawRich(vg, "result", animation, cx, cy, size, size, elapsed, duration, alpha, token) then
        Primitives.drawResult(vg, isSuccess, cx, cy, size, elapsed, duration, alpha)
    end
end

---@param vg NVGContextWrapper
---@param cx number
---@param cy number
---@param width number
---@param height number
---@param elapsed number
---@param duration number
---@param alpha? number
---@param token? table
function M.drawPower(vg, cx, cy, width, height, elapsed, duration, alpha, token)
    if not vg or not validBox(cx, cy, width, height) then return end
    if not drawRich(vg, "power", "power", cx, cy, width, height, elapsed, duration, alpha, token) then
        Primitives.drawPower(vg, cx, cy, width, height, elapsed, duration, alpha)
    end
end

function M.destroy()
    local oldPlaybacks, oldContexts = playbacks, contexts
    playbacks, contexts = {}, {} -- 清理旧批次不触碰释放期间可能重入的新 context/token。
    for token, entry in pairs(oldPlaybacks) do
        retired[token] = true
        entry.released = true
        disposeNative(entry)
    end
    for _, context in pairs(oldContexts) do
        context.broken = true
        local images = context.images
        context.images = {}
        local deleted = {} ---@type table<number, boolean>
        for _, image in pairs(images) do
            if image > 0 and not deleted[image] and type(nvgDeleteImage) == "function" then
                deleted[image] = true
                local ok, err = pcall(nvgDeleteImage, context.vg, image)
                if not ok then print("[DarkEffectSprites] 图片释放失败: " .. tostring(err)) end
            end
        end
    end
end

return M
