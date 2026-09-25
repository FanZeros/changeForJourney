-- procedural damage glyphs
local M = {}

local function rgb(vg, r, g, b, a)
    nvgFillColor(vg, nvgRGBA(r, g, b, a or 255))
    nvgStrokeColor(vg, nvgRGBA(r, g, b, a or 255))
end

local function poly(vg, cx, cy, s, pts)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + pts[1] * s, cy + pts[2] * s)
    for i = 3, #pts, 2 do
        nvgLineTo(vg, cx + pts[i] * s, cy + pts[i + 1] * s)
    end
    nvgClosePath(vg)
end

local GLYPHS = {
    ["撕咬"] = function(vg, x, y, s)
        rgb(vg, 255, 176, 82)
        poly(vg, x, y, s, { -0.72, -0.18, -0.18, -0.52, 0.18, -0.52, 0.72, -0.18, 0.18, 0.58, -0.18, 0.58 })
        nvgFill(vg)
        rgb(vg, 45, 22, 12)
        for i = -1, 1 do
            poly(vg, x + i * s * 0.28, y - s * 0.04, s, { -0.08, -0.34, 0.08, -0.34, 0.02, 0.30, -0.02, 0.30 })
            nvgFill(vg)
        end
    end,
    ["斩击"] = function(vg, x, y, s)
        rgb(vg, 236, 236, 228)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - s * 0.62, y + s * 0.46)
        nvgLineTo(vg, x + s * 0.62, y - s * 0.46)
        nvgStrokeWidth(vg, math.max(2, s * 0.16))
        nvgStroke(vg)
    end,
    ["粉碎"] = function(vg, x, y, s)
        rgb(vg, 188, 178, 164)
        poly(vg, x, y, s, { -0.18, -0.72, 0.18, -0.72, 0.18, -0.08, 0.62, 0.18, -0.62, 0.18, -0.18, -0.08 })
        nvgFill(vg)
    end,
    ["穿刺"] = function(vg, x, y, s)
        rgb(vg, 214, 214, 206)
        poly(vg, x, y, s, { 0.72, 0, 0.08, -0.28, 0.08, 0.28 })
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - s * 0.62, y)
        nvgLineTo(vg, x + s * 0.08, y)
        nvgStrokeWidth(vg, math.max(2, s * 0.12))
        nvgStroke(vg)
    end,
    ["业火"] = function(vg, x, y, s)
        rgb(vg, 255, 92, 28)
        poly(vg, x, y, s, { 0, -0.72, 0.30, -0.08, 0.16, -0.08, 0.42, 0.62, -0.42, 0.62, -0.16, -0.08, -0.30, -0.08 })
        nvgFill(vg)
    end,
    ["冥霜"] = function(vg, x, y, s)
        rgb(vg, 146, 226, 255)
        for i = 0, 5 do
            local a = i * math.pi / 3
            nvgBeginPath(vg)
            nvgMoveTo(vg, x, y)
            nvgLineTo(vg, x + math.cos(a) * s * 0.62, y + math.sin(a) * s * 0.62)
            nvgStrokeWidth(vg, math.max(2, s * 0.08))
            nvgStroke(vg)
        end
    end,
    ["雷殛"] = function(vg, x, y, s)
        rgb(vg, 255, 230, 70)
        poly(vg, x, y, s, { 0.08, -0.72, -0.34, 0.02, 0.02, 0.02, -0.12, 0.72, 0.38, -0.08, -0.02, -0.08 })
        nvgFill(vg)
    end,
    ["暗影"] = function(vg, x, y, s)
        rgb(vg, 126, 92, 188)
        nvgBeginPath(vg)
        nvgCircle(vg, x, y, s * 0.50)
        nvgFill(vg)
        rgb(vg, 18, 12, 28)
        nvgBeginPath(vg)
        nvgCircle(vg, x + s * 0.18, y - s * 0.08, s * 0.34)
        nvgFill(vg)
    end,
    ["烛照"] = function(vg, x, y, s)
        rgb(vg, 255, 214, 92)
        nvgBeginPath(vg)
        nvgCircle(vg, x, y, s * 0.24)
        nvgFill(vg)
        for i = 0, 7 do
            local a = i * math.pi / 4
            nvgBeginPath(vg)
            nvgMoveTo(vg, x + math.cos(a) * s * 0.36, y + math.sin(a) * s * 0.36)
            nvgLineTo(vg, x + math.cos(a) * s * 0.66, y + math.sin(a) * s * 0.66)
            nvgStrokeWidth(vg, math.max(2, s * 0.08))
            nvgStroke(vg)
        end
    end,
    ["暴击"] = function(vg, x, y, s)
        rgb(vg, 255, 214, 70, 150)
        for i = 0, 7 do
            local a = i * math.pi / 4
            nvgBeginPath(vg)
            nvgMoveTo(vg, x + math.cos(a) * s * 0.42, y + math.sin(a) * s * 0.42)
            nvgLineTo(vg, x + math.cos(a) * s * 0.78, y + math.sin(a) * s * 0.78)
            nvgStrokeWidth(vg, math.max(2, s * 0.07))
            nvgStroke(vg)
        end
        rgb(vg, 255, 70, 48, 210)
        nvgBeginPath(vg)
        nvgCircle(vg, x, y, s * 0.34)
        nvgStrokeWidth(vg, math.max(2, s * 0.08))
        nvgStroke(vg)
    end,
}

local CRIT_LABELS = {
    ["暴击"] = true, ["超暴击"] = true, ["已读暴击"] = true,
    ["暴击撕咬"] = true, ["暴击飞弹"] = true, ["暴击爆炸"] = true, ["暴击惩戒"] = true,
}

local ALIASES = {
    ["火焰"] = "业火", ["冰霜"] = "冥霜", ["闪电"] = "雷殛", ["神圣"] = "烛照",
    ["暴击撕咬"] = "撕咬", ["暴击飞弹"] = "飞弹", ["暴击爆炸"] = "飞弹爆炸", ["暴击惩戒"] = "惩戒",
    ["超暴击"] = "雷殛", ["已读暴击"] = "斩击",
    ["飞弹"] = "穿刺", ["飞弹爆炸"] = "业火", ["爆炸"] = "业火",
    ["喷水"] = "水脉", ["水脉"] = "冥霜", ["圣核"] = "烛照", ["星门"] = "暗影",
    ["环绕"] = "暗影", ["连射"] = "穿刺", ["连斩"] = "斩击", ["通宵斩"] = "斩击",
    ["散射"] = "穿刺", ["斩杀"] = "斩击", ["收工"] = "斩击", ["狩猎"] = "穿刺",
    ["超车"] = "雷殛", ["氮气"] = "雷殛", ["弹射"] = "雷殛", ["必杀"] = "雷殛",
    ["奥术"] = "暗影", ["蚀骨"] = "暗影", ["错位"] = "暗影", ["爆缝"] = "业火",
    ["燃烧结算"] = "业火", ["硝烟"] = "业火", ["晶碎"] = "冥霜", ["残响"] = "暗影",
    ["虫壳"] = "粉碎", ["铁壁"] = "粉碎", ["无面"] = "暗影", ["拾骸"] = "粉碎",
    ["激励"] = "烛照", ["惩戒"] = "烛照", ["化劲"] = "冥霜", ["押韵"] = "烛照",
}

function M.split(text)
    if type(text) ~= "string" then return nil, false, tostring(text or "") end
    local crit = false
    local label, rest = text:match("^(%S+)%s+([%+%-].*)$")
    if not label then return nil, false, text end
    if CRIT_LABELS[label] or label:find("暴击", 1, true) then
        crit = true
        local base = label:gsub("^暴击", "")
        label = base ~= "" and base or nil
    end
    local key = label and (ALIASES[label] or label) or nil
    if not key or not GLYPHS[key] or key == "暴击" then
        return nil, crit, rest
    end
    return key, crit, rest
end

function M.drawCrit(vg, x, y, size, alpha)
    local fn = GLYPHS["暴击"]
    if not fn or size < 8 then return end
    nvgSave(vg)
    nvgGlobalAlpha(vg, math.max(0, math.min(1, (alpha or 255) / 255)))
    fn(vg, x, y, size)
    nvgRestore(vg)
end

function M.draw(vg, key, x, y, size, alpha)
    local fn = GLYPHS[key]
    if not fn or size < 8 then return 0 end
    nvgSave(vg)
    nvgGlobalAlpha(vg, math.max(0, math.min(1, (alpha or 255) / 255)))
    fn(vg, x, y, size)
    nvgRestore(vg)
    return size
end

return M
