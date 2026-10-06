-- 暗铁门契程序化特效；纯绘图模块，不加载资源、不持有时钟或业务状态。
-- 坐标沿用调用者的 NanoVG 设计空间/DPR 变换与裁剪，不创建 context/fonts。
-- elapsed/duration 单位为秒；所有阶段均用 p = elapsed / duration 归一化。
-- 非法尺寸/时长、非有限输入和 p 不在 (0,1) 内时不绘制。
-- alpha 默认 1，限制到 [0,1]，逐一乘入所有填色、描边和渐变颜色。
-- 保守局部包络，包含倒角描边，不含设备抗锯齿边缘；外层变换后同比缩放：
--   power：|x-cx| <= .54*w，|y-cy| <= .66*h；文字由调用者绘制。
--   card： |x-cx| <= .55*w，|y-cy| <= .52*h；典型卡片 198 x 351。
--   result：|x-cx| <= .62*size，|y-cy| <= .62*size。
-- 每次公开调用只有一层 Save/Restore，不修改 globalAlpha/scissor。
-- 绘制失败仍恢复自己的 Save 帧，然后传播原错；Restore 失败也传播。
-- controller 负责日志与生命周期收尾，本模块不 print、不吞异常。
local P = require("core.DarkIcon").Palette
local M = {}

---@alias DarkCardEffectKind 'level'|'job'|'revive'

---@param value number?
---@return boolean
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

---@param value number
---@return number
local function clamp(value)
    return math.max(0, math.min(1, value))
end

---@param value number
---@return number
local function smooth(value)
    local t = clamp(value)
    return t * t * (3 - 2 * t)
end

---@param p number
---@param from number
---@param to number
---@return number
local function stage(p, from, to)
    return smooth((p - from) / (to - from))
end

---@param elapsed number
---@param duration number
---@param alpha number?
---@return number p
---@return number opacity
local function phase(elapsed, duration, alpha)
    local a = alpha == nil and 1 or alpha
    if not finite(elapsed) or not finite(duration) or not finite(a) or duration <= 0 then return 0, 0 end
    if elapsed <= 0 or elapsed >= duration then return 0, 0 end
    local p = elapsed / duration
    return p, clamp(a) * stage(p, 0, .10) * (1 - stage(p, .80, 1))
end

---@param cx number
---@param cy number
---@param w number
---@param h number
---@return boolean
local function validBox(cx, cy, w, h)
    -- 进入原生栅格器前限制浮点量级；不偷偷改写调用者尺寸。
    return finite(cx) and finite(cy) and finite(w) and finite(h)
        and math.abs(cx) <= 1e6 and math.abs(cy) <= 1e6
        and w >= 1e-4 and h >= 1e-4 and w <= 1e6 and h <= 1e6
end

---@param rgb number[]
---@param a number
---@return NVGcolor
local function color(rgb, a)
    local c = nvgRGBA(rgb[1], rgb[2], rgb[3], math.floor(clamp(a) * 255 + .5))
    ---@cast c NVGcolor
    return c
end

---@param vg NVGContextWrapper
---@param rgb number[]
---@param a number
local function fill(vg, rgb, a)
    nvgFillColor(vg, color(rgb, a))
    nvgFill(vg)
end

---@param vg NVGContextWrapper
---@param rgb number[]
---@param a number
---@param width number
local function stroke(vg, rgb, a, width)
    nvgStrokeColor(vg, color(rgb, a))
    nvgStrokeWidth(vg, width)
    nvgStroke(vg)
end

---@param vg NVGContextWrapper
---@param y0 number
---@param y1 number
---@param upper number[]
---@param lower number[]
---@param a number
local function metal(vg, y0, y1, upper, lower, a)
    local c0 = color(upper, a)
    local c1 = color(lower, a)
    ---@cast c0 NVGcolor
    ---@cast c1 NVGcolor
    local paint = nvgLinearGradient(vg, 0, y0, 0, y1, c0, c1)
    ---@cast paint NVGpaint
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    stroke(vg, P.OUTLINE, a, 2.4)
end

---@param vg NVGContextWrapper
---@param points number[] 交替 x/y 坐标；全部形状为模块内固定常量。
---@param x number
---@param y number
---@param sx number
---@param sy number
---@param angle number
local function path(vg, points, x, y, sx, sy, angle)
    local c, s = math.cos(angle), math.sin(angle)
    nvgBeginPath(vg)
    for i = 1, #points, 2 do
        local px, py = points[i] * sx, points[i + 1] * sy
        local tx, ty = x + px * c - py * s, y + px * s + py * c
        if i == 1 then nvgMoveTo(vg, tx, ty) else nvgLineTo(vg, tx, ty) end
    end
    nvgClosePath(vg)
end

---@param vg NVGContextWrapper
---@param points number[]
---@param x number
---@param y number
---@param sx number
---@param sy number
---@param angle number
---@param rgb number[]
---@param a number
local function solid(vg, points, x, y, sx, sy, angle, rgb, a)
    path(vg, points, x, y, sx, sy, angle)
    fill(vg, rgb, a)
end

---@param vg NVGContextWrapper
---@param x0 number
---@param y0 number
---@param x1 number
---@param y1 number
---@param rgb number[]
---@param a number
---@param width number
local function line(vg, x0, y0, x1, y1, rgb, a, width)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x0, y0)
    nvgLineTo(vg, x1, y1)
    stroke(vg, rgb, a, width)
end

local CHIP = {-4,-3, 3,-5, 5,2, -2,4}
local RIVET = {0,-2.5, 2.5,0, 0,2.5, -2.5,0}
local PLAQUE = {-188,-38, -178,-49, 178,-49, 188,-38, 188,38, 178,49, -178,49, -188,38}
local PLAQUE_FACE = {-175,-46, 175,-46, 182,-38, 182,38, 175,46, -175,46, -182,38, -182,-38}
local WING = {142,-13, 160,-28, 191,-33, 183,-19, 196,-13, 176,4, 151,8}
local WING_LOWER = {144,10, 174,7, 192,21, 175,20, 183,32, 151,24}
local CLAMP = {-27,-9, 16,-9, 28,0, 16,12, -27,12, -34,2}
local CLAMP_INSET = {-22,-5, 12,-5, 19,0, 11,5, -22,5}
local LOCK = {-19,-19, 19,-19, 25,-12, 25,13, 0,30, -25,13, -25,-12}
local DOOR = {4,-115, 40,-111, 57,-87, 57,94, 41,120, 4,130, 9,34, 4,19}
local DOOR_FACE = {17,-99, 34,-96, 44,-79, 44,83, 33,106, 17,111}
local HINGE = {47,-10, 62,-7, 62,6, 47,10}
local CROWN = {-69,-125, -56,-143, 0,-164, 56,-143, 69,-125, 47,-130, 0,-146, -47,-130}
local FOOT = {-54,122, 54,122, 64,136, 35,144, -35,144, -64,136}
local RIFT = {-4,-128, 11,-82, 2,-37, 14,-1, 3,39, 8,88, -5,118, -13,59, -6,25, -16,-14, -9,-55}
local GLYPH = {-3,-25, 4,-25, 4,-9, 17,-9, 17,-2, 4,-2, 4,20, -4,28, -12,17, -6,13, -3,17, -3,-2, -17,-2, -17,-9, -3,-9}
-- 四块铸模以实体接缝拼合，不使用普通圆形奖章。
local SEAL = {-42,-62, 42,-62, 63,-41, 63,36, 0,69, -63,36, -63,-41}
---@type number[][]
local QUARTERS = {
    {-40,-57, -3,-57, -3,-4, -58,-4, -58,-38},
    {3,-57, 40,-57, 58,-38, 58,-4, 3,-4},
    {-58,2, -3,2, -3,61, -58,32},
    {3,2, 58,2, 58,32, 3,61},
}
---@type number[][]
local FRACTURES = {
    {-42,-57, -5,-57, -12,-21, -32,-7, -58,-37},
    {2,-57, 40,-57, 58,-38, 31,-12, 7,-18},
    {-58,-28, -35,-1, -13,3, -24,25, -58,31},
    {34,-7, 58,-29, 58,32, 35,41, 16,12},
    {-20,29, -4,9, 13,27, 6,61, -13,50},
    {17,32, 31,47, 12,57, 11,40},
}

---@param vg NVGContextWrapper
---@param cx number
---@param cy number
---@param sx number
---@param sy number
local function begin(vg, cx, cy, sx, sy)
    nvgTranslate(vg, cx, cy)
    nvgScale(vg, sx, sy)
    nvgLineJoin(vg, NVG_BEVEL)
    nvgLineCap(vg, NVG_BUTT)
end

---@param vg NVGContextWrapper
---@param painter fun()
local function isolated(vg, painter)
    -- Save 失败未建立帧，直接传播，不进行猜测性 Restore。
    nvgSave(vg)
    local drawn, drawError = pcall(painter)
    local restored, restoreError = pcall(nvgRestore, vg)
    if not restored then
        if not drawn then
            error(tostring(drawError) .. " [NanoVG restore failed: " .. tostring(restoreError) .. "]", 0)
        end
        error(restoreError, 0)
    end
    if not drawn then error(drawError, 0) end
end

---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param w number
---@param h number
---@param bend number
---@param a number
local function furnaceFlame(vg, x, y, w, h, bend, a)
    if a <= 0 then return end
    nvgBeginPath(vg)
    nvgMoveTo(vg, x - w * .45, y + h * .26)
    nvgBezierTo(vg, x - w * .72, y, x - w * .2, y - h * .14, x - w * .32, y - h * .4)
    nvgLineTo(vg, x - w * .02, y - h * .22)
    nvgLineTo(vg, x + bend, y - h * .66)
    nvgBezierTo(vg, x + w * .1, y - h * .22, x + w * .68, y - h * .09, x + w * .47, y + h * .24)
    nvgBezierTo(vg, x + w * .24, y + h * .42, x - w * .23, y + h * .42, x - w * .45, y + h * .26)
    nvgClosePath(vg)
    metal(vg, y - h * .5, y + h * .4, P.EMBER, P.BLOOD_DK, a)
end

---@param vg NVGContextWrapper
---@param p number
---@param a number
---@param lift number
local function riseEmbers(vg, p, a, lift)
    for i = 1, 8 do
        local q = clamp((p - .25 - i * .027) / .40)
        local alive = smooth(q * 8) * (1 - smooth((q - .65) / .35))
        local side = i % 2 == 0 and 1 or -1
        local x = side * (13 + i * 6 + q * (7 + i))
        local y = 71 - q * lift - i * 6
        solid(vg, CHIP, x, y, .24 + i * .035, .5, side * q * 2, P.EMBER, a * alive * .8)
    end
end

-- Power：.00-.10 显现，.18-.45 铜翼分裂，.45-.78 持牌/余烬，.80-1 退场。
-- 铭牌覆盖约 .94*w x .98*h，中央 .84*w x .90*h 无饰件；支持标题+三队文字。
---@param vg NVGContextWrapper
---@param cx number
---@param cy number
---@param w number
---@param h number
---@param elapsed number
---@param duration number
---@param alpha number?
function M.drawPower(vg, cx, cy, w, h, elapsed, duration, alpha)
    if not vg or not validBox(cx, cy, w, h) then return end
    local p, a = phase(elapsed, duration, alpha)
    if a <= 0 then return end
    isolated(vg, function()
        begin(vg, cx, cy, w / 400, h / 100)
        local split = stage(p, .18, .45)
        path(vg, PLAQUE, 0, 0, 1, 1, 0)
        metal(vg, -49, 49, P.METAL_L, P.METAL_D, a * .94)
        solid(vg, PLAQUE_FACE, 0, 0, 1, 1, 0, P.BG_DEEP, a * .93)
        line(vg, -173, -48, 173, -48, P.GOLD_DK, a, 1.4)
        line(vg, -172, 48, 172, 48, P.METAL_L, a * .65, 1.2)
        for i = 1, 2 do
            local side = i == 1 and -1 or 1
            path(vg, WING, side * (57 + split * 9), -split * 3, side * .72, 1, 0)
            metal(vg, -36, 8, P.GOLD, P.GOLD_DK, a)
            path(vg, WING_LOWER, side * (57 + split * 11), split * 4, side * .72, 1, 0)
            metal(vg, 8, 38, P.METAL_L, P.GOLD_DK, a)
            line(vg, side * (175 + split * 9), -13, side * (192 + split * 9), -24, P.BONE_DIM, a * .6, 1.3)
            for j = 1, 2 do
                solid(vg, RIVET, side * 177, j == 1 and -34 or 34, 1, 1, 0, P.BONE_DIM, a * .75)
            end
        end
        for i = 1, 8 do
            local q = clamp((p - .2 - i * .04) / .39)
            local life = smooth(q * 8) * (1 - smooth((q - .55) / .45))
            local side = i % 2 == 0 and 1 or -1
            solid(vg, CHIP, side * (172 + i * 2.4 + q * 13), 5 - q * (28 + i * 3), .4, .5, side * q, P.EMBER, a * life * .9)
        end
    end)
end

---@param vg NVGContextWrapper
---@param p number
---@param a number
local function level(vg, p, a)
    local bind = stage(p, .12, .42)
    local burn = stage(p, .32, .51) * (1 - stage(p, .70, .94))
    -- 四个实体封爪向锁芯收束，再随点火向上下略微回弹。
    for i = 1, 4 do
        local side = i % 2 == 0 and 1 or -1
        local row = i <= 2 and -1 or 1
        local x = side * (58 - bind * 28)
        local y = 67 + row * (29 - bind * 18) + burn * row * 6
        path(vg, CLAMP, x, y, side * .78, .7, 0)
        metal(vg, y - 7, y + 9, P.METAL_L, P.METAL_D, a)
        solid(vg, CLAMP_INSET, x, y, side * .78, .7, 0, P.GOLD_DK, a * .8)
    end
    path(vg, LOCK, 0, 66 - bind * 7, .90, .90, 0)
    metal(vg, 42, 88, P.GOLD, P.METAL_D, a)
    solid(vg, GLYPH, 0, 59, .6, .6, 0, P.BONE, a * bind)
    -- 分叉高焰向上拉长，根部仍留封印附近，不使用扩散圆盘。
    local lift = stage(p, .37, .73)
    furnaceFlame(vg, -24, 38 - lift * 25, 28, 75 + lift * 58, -12, a * burn * .62)
    furnaceFlame(vg, 26, 35 - lift * 38, 25, 82 + lift * 54, 16, a * burn * .66)
    furnaceFlame(vg, 0, 30 - lift * 44, 50, 102 + lift * 79, 8, a * burn * .96)
    solid(vg, GLYPH, 0, 8 - lift * 38, .36, 1.25, 0, P.BONE, a * burn * .82)
    riseEmbers(vg, p, a, 193)
end

---@param vg NVGContextWrapper
---@param p number
---@param a number
local function job(vg, p, a)
    local open = stage(p, .12, .52)
    local light = stage(p, .24, .43) * (1 - stage(p, .70, .94))
    solid(vg, CROWN, 0, 0, 1, 1, 0, P.METAL_L, a * .85)
    solid(vg, FOOT, 0, 0, 1, 1, 0, P.GOLD_DK, a * .85)
    solid(vg, RIFT, 0, 0, 1.4 + open * .7, 1, 0, P.BLOOD, a * light * .22)
    solid(vg, RIFT, 0, 0, .6 + open * .5, 1, 0, P.EMBER, a * light * .83)
    -- 两扇门向外平移并收窄呈转轴透视；铸纹跟随门叶，外缘由铰链承托。
    for i = 1, 2 do
        local side = i == 1 and -1 or 1
        local x = side * open * 37
        local sx = side * (1 - open * .38)
        path(vg, DOOR, x, 0, sx, 1, 0)
        metal(vg, -112, 130, P.METAL_L, P.METAL_D, a)
        solid(vg, DOOR_FACE, x, 0, sx, 1, 0, P.METAL_D, a * .94)
        line(vg, x + sx * 12, -100, x + sx * 12, 108, P.GOLD, a * .82, 2.5)
        for j = 1, 3 do
            local y = -67 + (j - 1) * 68
            path(vg, HINGE, x, y, sx, 1, 0)
            metal(vg, y - 10, y + 10, P.STEEL_M, P.STEEL_D, a)
            line(vg, x + sx * 23, y - 12, x + sx * 37, y + 2, P.BONE_DIM, a * (.25 + light * .65), 1.8)
            line(vg, x + sx * 37, y + 2, x + sx * 28, y + 18, P.GOLD, a * (.2 + light * .6), 1.8)
        end
    end
    solid(vg, GLYPH, 0, -12, .9, 1.3, 0, P.BONE, a * light * open)
    for i = 1, 6 do
        local q = clamp((p - .3 - i * .032) / .38)
        local life = smooth(q * 7) * (1 - smooth((q - .65) / .35))
        local side = i % 2 == 0 and 1 or -1
        solid(vg, CHIP, side * (7 + q * (30 + i * 5)), -95 + i * 27 - q * 22, .42, .62, side * q * 1.7, P.GOLD, a * life)
    end
end

---@param vg NVGContextWrapper
---@param p number
---@param a number
local function revive(vg, p, a)
    local gather = stage(p, .08, .55)
    local soul = stage(p, .45, .65) * (1 - stage(p, .79, .98))
    -- 灰片沿不等长弯曲轨迹内聚，不使用顺时针径向爆发，也不复用换色升级火焰。
    for i = 1, 10 do
        local side = i % 2 == 0 and 1 or -1
        local sx = side * (44 + i * 3.8)
        local sy = -104 + i * 23
        local x = sx * (1 - gather) + side * math.sin(gather * math.pi) * 15
        local y = sy * (1 - gather) + gather * 37 - math.sin(gather * math.pi) * (i % 3) * 13
        local opacity = a * (1 - stage(p, .50, .67)) * .72
        path(vg, CHIP, x, y, 1.1, 1.8, side * (1 - gather) * 1.3)
        metal(vg, y - 8, y + 8, P.STEEL_M, P.STEEL_D, opacity)
    end
    -- 灰片重组成中空、双尖、拖尾的魂焰，不靠橙红火焰换色表现复活。
    local rise = stage(p, .49, .80)
    local top = -43 - rise * 94
    nvgBeginPath(vg)
    nvgMoveTo(vg, -20, 69)
    nvgBezierTo(vg, -48, 25, -41, -21, -25, top + 31)
    nvgLineTo(vg, -11, top + 52)
    nvgBezierTo(vg, -8, top + 21, 13, top + 5, 6, top)
    nvgBezierTo(vg, 47, top + 20, 8, top + 73, 29, -7)
    nvgBezierTo(vg, 49, 24, 24, 44, 18, 72)
    nvgLineTo(vg, 3, 47)
    nvgLineTo(vg, -7, 77)
    nvgClosePath(vg)
    metal(vg, top, 77, P.BONE_DIM, P.METAL_D, a * soul)
    line(vg, -8, -27 - rise * 37, -3, 41, P.BONE, a * soul * .82, 3)
    line(vg, 7, -23 - rise * 29, 13, 27, P.BONE, a * soul * .65, 2)
    solid(vg, CHIP, -17, -5 - rise * 29, 1.1, .35, -.22, P.BG_DEEP, a * soul)
    solid(vg, CHIP, 15, -8 - rise * 29, 1, .35, .18, P.BG_DEEP, a * soul)
    solid(vg, LOCK, 0, 72, .8, .38, 0, P.METAL_M, a * soul * .7)
end

-- 卡片阶段均为归一化比例，不是绝对秒数：
-- level：.12-.42 封印收束/.32-.73 向上点火；job：.12-.52 开门/.24-.76 裂光铸纹；
-- revive：.08-.55 灰片内聚/.45-.80 魂焰成形。均在 .80-1 整体退场。
---@param vg NVGContextWrapper
---@param kind DarkCardEffectKind
---@param cx number
---@param cy number
---@param w number
---@param h number
---@param elapsed number
---@param duration number
---@param alpha number?
function M.drawCard(vg, kind, cx, cy, w, h, elapsed, duration, alpha)
    if kind ~= "level" and kind ~= "job" and kind ~= "revive" then return end
    if not vg or not validBox(cx, cy, w, h) then return end
    local p, a = phase(elapsed, duration, alpha)
    if a <= 0 then return end
    isolated(vg, function()
        begin(vg, cx, cy, w / 200, h / 350)
        if kind == "level" then level(vg, p, a)
        elseif kind == "job" then job(vg, p, a)
        else revive(vg, p, a) end
    end)
end

-- 结果：成功 .10-.50 熔片内聚/.46-.63 熔印定形；失败 .12-.35 裂印，
-- .30-.80 不规则碎片旋转外散、下坠并熄灭，绝不复用红色成功图形。
---@param vg NVGContextWrapper
---@param success boolean
---@param cx number
---@param cy number
---@param size number
---@param elapsed number
---@param duration number
---@param alpha number?
function M.drawResult(vg, success, cx, cy, size, elapsed, duration, alpha)
    if type(success) ~= "boolean" or not vg or not validBox(cx, cy, size, size) then return end
    local p, a = phase(elapsed, duration, alpha)
    if a <= 0 then return end
    isolated(vg, function()
        begin(vg, cx, cy, size / 200, size / 200)
        if success then
            local cast = stage(p, .10, .50)
            local stamp = stage(p, .46, .63)
            path(vg, SEAL, 0, 0, 1, 1, 0)
            metal(vg, -62, 69, P.BLOOD_DK, P.METAL_D, a * .36)
            for i = 1, 4 do
                local side = i % 2 == 0 and 1 or -1
                local row = i <= 2 and -1 or 1
                local x, y = side * (1 - cast) * 23, row * (1 - cast) * 21
                path(vg, QUARTERS[i], x, y, 1, 1, side * (1 - cast) * .08)
                metal(vg, -57 + y, 61 + y, P.GOLD, P.METAL_D, a)
            end
            line(vg, -45, -47, 45, -47, P.BONE_DIM, a * stamp, 2)
            solid(vg, GLYPH, 0, -3, 1.2, 1.45, 0, P.BONE, a * stamp)
            furnaceFlame(vg, 0, -59, 19, 34, 4, a * stamp * (1 - stage(p, .67, .85)))
            for i = 1, 6 do
                local q = clamp((p - .26 - i * .025) / .36)
                local side = i % 2 == 0 and 1 or -1
                local life = smooth(q * 8) * (1 - smooth((q - .65) / .35))
                solid(vg, CHIP, side * (64 - q * 50), -43 + i * 14 - q * 9, .42, .55, side * q, P.EMBER, a * life)
            end
        else
            local breakage = stage(p, .12, .35)
            local fall = stage(p, .30, .80)
            local dim = 1 - stage(p, .46, .87)
            for i = 1, 6 do
                local side = i % 2 == 0 and 1 or -1
                local dx = side * (breakage * (4 + i * 1.7) + fall * (9 + i * 2))
                local dy = fall * fall * (22 + i * 2.3) - breakage * (8 - i)
                local turn = side * fall * (.19 + i * .04)
                path(vg, FRACTURES[i], dx, dy, 1, 1, turn)
                metal(vg, -57 + dy, 65 + dy, P.METAL_L, P.METAL_D, a * dim)
            end
            local fire = stage(p, .12, .24) * (1 - stage(p, .37, .60))
            line(vg, -9 - breakage * 8, -51, -19 - breakage * 8, -12, P.BLOOD, a * fire, 3)
            line(vg, 2 + breakage * 6, -21, 17 + breakage * 6, 6, P.EMBER, a * fire, 2)
            line(vg, -8, 14 + fall * 18, 2, 37 + fall * 25, P.BLOOD_DK, a * dim, 3)
            for i = 1, 4 do
                local side = i % 2 == 0 and 1 or -1
                solid(vg, CHIP, side * (14 + fall * i * 10), 17 + fall * fall * 70 - i * 9, .35, .4, side * fall * 2, P.STEEL_D, a * dim * .7)
            end
        end
    end)
end

return M
