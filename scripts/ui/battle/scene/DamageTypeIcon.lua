-- 战斗数字专用矢量徽记：暗铁边、骨白切面、属性色高光。
-- 只负责语义解析/绘制，不读取角色状态、不加载图片，也不消费战斗随机数。
local AD = require("systems.AttributeDef")
local M = {}

---@class DamageNumberMeta
---@field channel? string damage / shield / heal（圣属性额伤也必须为 damage）
---@field atkType? number 本次结算的属性快照
---@field floatKind? string 兼容旧飘字 kind
---@field isCrit? boolean
---@field isBlocked? boolean
---@field isDot? boolean
---@field color? number[]
---@field fontSize? number

local COLORS = {
    [AD.ATK_SLASH] = { 244, 227, 184 },
    [AD.ATK_CRUSH] = { 222, 182, 128 },
    [AD.ATK_PIERCE] = { 212, 232, 218 },
    [AD.ATK_FIRE] = { 255, 148, 65 },
    [AD.ATK_ICE] = { 126, 218, 255 },
    [AD.ATK_LIGHTNING] = { 222, 198, 255 },
    [AD.ATK_SHADOW] = { 188, 144, 231 },
    [AD.ATK_HOLY] = { 255, 232, 148 },
}
local LEGACY_TYPES = {
    { "slash", AD.ATK_SLASH }, { "crush", AD.ATK_CRUSH }, { "pierce", AD.ATK_PIERCE },
    { "burn", AD.ATK_FIRE }, { "fire", AD.ATK_FIRE }, { "ice", AD.ATK_ICE },
    { "lightning", AD.ATK_LIGHTNING }, { "shadow", AD.ATK_SHADOW }, { "holy", AD.ATK_HOLY },
    { "phys", AD.ATK_SLASH }, { "magic", AD.ATK_SHADOW },
}
local function contains(kind, word) return kind:find(word, 1, true) ~= nil end

---@param meta? DamageNumberMeta
---@param kind? string
---@return DamageNumberMeta?
function M.resolve(meta, kind)
    meta = meta or {}
    kind = kind or meta.floatKind or ""
    local atkType = tonumber(meta.atkType)
    if not COLORS[atkType] then
        atkType = nil
        for _, item in ipairs(LEGACY_TYPES) do
            if contains(kind, item[1]) then atkType = item[2]; break end
        end
    end
    local channel = meta.channel
    if channel ~= "damage" and channel ~= "shield" and channel ~= "heal" then
        if contains(kind, "heal") then channel = "heal"
        elseif contains(kind, "shield") then channel = "shield"
        elseif atkType or contains(kind, "crit") or contains(kind, "block") then channel = "damage"
        else return nil end
    end
    -- 不用 AD.getAtkCategory 判断 channel：属性8既有治疗，也有圣核等正伤害。
    return {
        channel = channel,
        atkType = atkType or (channel == "heal" and AD.ATK_HOLY or AD.ATK_SLASH),
        isCrit = meta.isCrit or contains(kind, "crit"),
        isBlocked = meta.isBlocked or contains(kind, "block"),
        isDot = meta.isDot or contains(kind, "burn") or contains(kind, "dot"),
    }
end

---@param meta DamageNumberMeta
---@return number[]
function M.color(meta)
    if meta.channel == "shield" then return { 184, 196, 212 } end
    if meta.channel == "heal" then return { 90, 235, 130 } end
    if meta.isCrit then return { 255, 90, 82 } end
    return COLORS[meta.atkType] or COLORS[AD.ATK_SLASH]
end

local function polygon(vg, points)
    nvgBeginPath(vg)
    nvgMoveTo(vg, points[1], points[2])
    for i = 3, #points, 2 do nvgLineTo(vg, points[i], points[i + 1]) end
    nvgClosePath(vg)
end
local function finish(vg, color)
    nvgFillPaint(vg, nvgLinearGradient(vg, -12, -25, 18, 26,
        nvgRGBA(248, 239, 215, 255), nvgRGBA(color[1], color[2], color[3], 255)))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(27, 29, 35, 255))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)
end
local function line(vg, points, color, width)
    nvgBeginPath(vg)
    nvgMoveTo(vg, points[1], points[2])
    for i = 3, #points, 2 do nvgLineTo(vg, points[i], points[i + 1]) end
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], 255))
    nvgStrokeWidth(vg, width or 2)
    nvgStroke(vg)
end
local BONE = { 255, 248, 226 }
local function shield(vg, color)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -28)
    nvgLineTo(vg, 21, -17)
    nvgQuadTo(vg, 22, 16, 0, 29)
    nvgQuadTo(vg, -22, 16, -21, -17)
    nvgClosePath(vg)
    finish(vg, color)
    line(vg, { 0, -19, 0, 19 }, BONE, 2)
    line(vg, { -13, -12, 0, -18, 13, -12 }, BONE, 2)
end
local function cross(vg, color)
    polygon(vg, { -7, -23, 7, -23, 7, -7, 23, -7, 23, 7, 7, 7,
        7, 23, -7, 23, -7, 7, -23, 7, -23, -7, -7, -7 })
    finish(vg, color)
    line(vg, { -3, -17, -3, 17 }, BONE, 2)
end
local function star(vg, color)
    local points = {}
    for i = 0, 7 do
        local angle = i * math.pi / 4 - math.pi / 2
        local radius = i % 2 == 0 and 27 or 9
        points[#points + 1] = math.cos(angle) * radius
        points[#points + 1] = math.sin(angle) * radius
    end
    polygon(vg, points)
    finish(vg, color)
end

local SHAPES = {}
SHAPES[AD.ATK_SLASH] = function(vg, color)
    polygon(vg, { 18, -29, 19, -8, -5, 18, -14, 9 })
    finish(vg, color)
    line(vg, { 14, -20, -7, 12 }, BONE, 2)
    line(vg, { -18, 7, 0, 23 }, { 93, 81, 64 }, 5)
    line(vg, { -9, 16, -20, 29 }, color, 7)
end
SHAPES[AD.ATK_CRUSH] = function(vg, color)
    polygon(vg, { -23, -23, 20, -23, 24, -17, 20, -3, -23, -3, -26, -10 })
    finish(vg, color)
    line(vg, { -17, -18, 17, -18 }, BONE, 2)
    polygon(vg, { -5, -2, 5, -2, 7, 28, -7, 28 })
    finish(vg, { 139, 112, 80 })
end
SHAPES[AD.ATK_PIERCE] = function(vg, color)
    polygon(vg, { 0, -31, 13, -8, 0, 0, -13, -8 })
    finish(vg, color)
    line(vg, { 0, -24, 0, -1 }, BONE, 2)
    line(vg, { 0, 0, 0, 29 }, color, 6)
    line(vg, { -11, 5, 0, 12, 11, 5 }, BONE, 2)
end
SHAPES[AD.ATK_FIRE] = function(vg, color)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, 29)
    nvgQuadTo(vg, 32, 12, 14, -8)
    nvgQuadTo(vg, 16, -23, 0, -31)
    nvgQuadTo(vg, -1, -12, -13, -7)
    nvgQuadTo(vg, -31, 14, 0, 29)
    nvgClosePath(vg)
    finish(vg, color)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, 19)
    nvgQuadTo(vg, 12, 5, 0, -8)
    nvgQuadTo(vg, -10, 8, 0, 19)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(255, 247, 190, 255)); nvgFill(vg)
end
SHAPES[AD.ATK_ICE] = function(vg, color)
    polygon(vg, { 0, -29, 16, -4, 0, 28, -16, -4 })
    finish(vg, color)
    line(vg, { 0, -21, 0, 20 }, BONE, 2)
    line(vg, { -26, -11, 0, 2, 26, -11 }, color, 3)
    line(vg, { -26, 14, 0, 2, 26, 14 }, color, 3)
    line(vg, { -23, -18, -22, -9, -30, -5 }, BONE, 2)
    line(vg, { 23, -18, 22, -9, 30, -5 }, BONE, 2)
end
SHAPES[AD.ATK_LIGHTNING] = function(vg, color)
    polygon(vg, { 8, -31, -22, 4, -3, 4, -9, 31, 23, -9, 5, -9 })
    finish(vg, color)
    line(vg, { 3, -20, -11, 0, 3, 0 }, BONE, 2)
end
SHAPES[AD.ATK_SHADOW] = function(vg, color)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 13, -28)
    nvgQuadTo(vg, -35, -23, -23, 15)
    nvgQuadTo(vg, -13, 36, 17, 22)
    nvgQuadTo(vg, -11, 19, -7, -4)
    nvgQuadTo(vg, -5, -20, 13, -28)
    nvgClosePath(vg)
    finish(vg, color)
    polygon(vg, { 14, -8, 22, 1, 14, 10, 6, 1 })
    finish(vg, BONE)
end
SHAPES[AD.ATK_HOLY] = function(vg, color)
    star(vg, color)
    nvgBeginPath(vg); nvgCircle(vg, 0, 0, 6)
    nvgFillColor(vg, nvgRGBA(255, 251, 224, 255)); nvgFill(vg)
    line(vg, { -21, -20, -26, -25 }, color, 2)
    line(vg, { 21, -20, 26, -25 }, color, 2)
end

local function badge(vg, x, y, draw)
    nvgSave(vg)
    nvgTranslate(vg, x, y)
    nvgScale(vg, 0.34, 0.34)
    draw()
    nvgRestore(vg)
end

---@param meta DamageNumberMeta
function M.draw(vg, meta, x, y, size)
    nvgSave(vg)
    nvgTranslate(vg, x, y)
    nvgScale(vg, size / 72, size / 72)
    local color = COLORS[meta.atkType] or COLORS[AD.ATK_SLASH]
    if meta.channel == "shield" then shield(vg, { 175, 195, 219 })
    elseif meta.channel == "heal" then cross(vg, { 90, 235, 130 })
    else (SHAPES[meta.atkType] or SHAPES[AD.ATK_SLASH])(vg, color) end
    -- 角标不遮住属性主体；普通/暴击/格挡/DOT同一属性仍可累加。
    if meta.isCrit then badge(vg, 25, -24, function() star(vg, { 255, 83, 65 }) end) end
    if meta.isBlocked then badge(vg, 25, 24, function() shield(vg, { 196, 202, 217 }) end) end
    if meta.isDot then
        badge(vg, -24, 24, function()
            nvgBeginPath(vg); nvgCircle(vg, 0, 0, 24); finish(vg, color)
            nvgBeginPath(vg); nvgCircle(vg, -9, 0, 3); nvgCircle(vg, 0, 0, 3); nvgCircle(vg, 9, 0, 3)
            nvgFillColor(vg, nvgRGBA(27, 29, 35, 255)); nvgFill(vg)
        end)
    end
    -- alpha只由外层BattleDraw的nvgGlobalAlpha控制，颜色不得再乘透明度。
    nvgRestore(vg)
end

return M
