-- 招募说明显示层：实际字宽折行，规则和奖励共享一个滚动区。
-- 不改卡池权重/保底/交易；文案从原有配置和规则读取。
local I18n = require("core.I18n")
local HC = require("config.HeroConfig")
local GachaConfig = require("config.GachaConfig")
local UrGachaConfig = require("config.UrGachaConfig")
local M = {}
local layoutCache = {}
local cachedVg = nil
local TEXT = { 216, 201, 180 }
local HIGHLIGHT = { 230, 169, 84 }
local QUALITY_TAG = { [0] = "杂项", [1] = "普通", [2] = "稀有", [3] = "史诗" }
local STELLAR_TAG = { [1] = "普通", [2] = "稀有", [3] = "史诗", [4] = "传说" }
local QUALITY_COLOR = { [0] = {162,255,148}, [1] = {114,242,245},
    [2] = {239,121,255}, [3] = {255,237,0} }
local STELLAR_COLOR = { [1] = QUALITY_COLOR[0], [2] = QUALITY_COLOR[2],
    [3] = QUALITY_COLOR[3], [4] = QUALITY_COLOR[3] }
local RESOURCE_NAMES = { gold = "金币", essence = "精粹", enhance_star = "强化星石",
    sweep_ticket = "扫荡券", degrade_protect = "退级保护石", break_protect = "点金石" }
local LINE_H, FONT, STROKE = 46, 40, 5

local function isStellar(poolId)
    return poolId == "stellar" or poolId == UrGachaConfig.POOL_ID
end
local function segment(text, color)
    return { text = text, r = color[1], g = color[2], b = color[3] }
end
local function paragraph(parts)
    local result = {}
    for index, text in ipairs(parts) do
        result[#result + 1] = segment(tostring(text), index % 2 == 0 and HIGHLIGHT or TEXT)
    end
    return result
end
local function ruleParagraphs(poolId)
    if isStellar(poolId) then
        local pity = UrGachaConfig.Pity
        return {
            paragraph({ "每", pity.SR_THRESHOLD, "次招募必定获得", "稀有", "级星辰远征队员" }),
            paragraph({ "每", pity.SSR_THRESHOLD, "次招募必定获得", "史诗", "级星辰远征队员" }),
            paragraph({ "每", pity.UR_THRESHOLD, "次招募必定获得", "传说", "级星辰远征队员" }),
            {}, paragraph({ "各品质基础概率：" }),
            paragraph({ "普通: ", string.format("%.0f%%", UrGachaConfig.Probability[UrGachaConfig.QUALITY_R] or 0) }),
            paragraph({ "稀有: ", string.format("%.0f%%", UrGachaConfig.Probability[UrGachaConfig.QUALITY_SR] or 0) }),
            paragraph({ "史诗: ", string.format("%.0f%%", UrGachaConfig.Probability[UrGachaConfig.QUALITY_SSR] or 0) }),
            paragraph({ "传说: ", string.format("%.0f%%", UrGachaConfig.Probability[UrGachaConfig.QUALITY_UR] or 0) }),
        }
    end
    return {
        paragraph({ "每", "80", "次招募必定获得", "史诗", "级远征队员" }),
        paragraph({ "第", "61", "抽起史诗概率逐抽提升" }),
        {}, paragraph({ "各品质基础概率：" }),
        paragraph({ "杂项: ", "55%" }), paragraph({ "普通: ", "25%" }),
        paragraph({ "稀有: ", "15%" }), paragraph({ "史诗: ", "5%" }),
    }
end

-- 先翻译完整语义段，再折行；折行碎片走displayText，不能再经全局hook翻译。
-- 有完整句译文时优先使用，并按译后的数字/品质标回高亮，不强拼原语序。
local function translatedSegments(segments)
    local sourceParts = {}
    for _, seg in ipairs(segments) do sourceParts[#sourceParts + 1] = seg.text end
    local source = table.concat(sourceParts)
    local translated = I18n.lookup(source)
    if translated ~= source then
        local result, position = {}, 1
        for _, seg in ipairs(segments) do
            if seg.r == HIGHLIGHT[1] and seg.g == HIGHLIGHT[2] then
                local token = I18n.lookup(seg.text)
                local first, last = translated:find(token, position, true)
                if token ~= "" and first then
                    if first > position then result[#result + 1] = segment(translated:sub(position, first - 1), TEXT) end
                    result[#result + 1] = segment(token, HIGHLIGHT)
                    position = last + 1
                end
            end
        end
        if position <= #translated then result[#result + 1] = segment(translated:sub(position), TEXT) end
        return result
    end
    local result = {}
    for _, seg in ipairs(segments) do
        result[#result + 1] = { text = I18n.lookup(seg.text), r = seg.r, g = seg.g, b = seg.b }
    end
    return result
end

-- 使用完整同色run测量，保留kerning；英文词优先整体，超长名字/单词再逐UTF-8字折。
local function wrap(vg, segments, width)
    local rows, current = {}, {}
    local function sameColor(a, b) return a.r == b.r and a.g == b.g and a.b == b.b end
    local function candidate(text, color)
        local result = {}
        for _, seg in ipairs(current) do
            result[#result + 1] = { text = seg.text, r = seg.r, g = seg.g, b = seg.b }
        end
        local last = result[#result]
        if last and sameColor(last, color) then last.text = last.text .. text
        else result[#result + 1] = { text = text, r = color.r, g = color.g, b = color.b } end
        local total = 0
        for _, seg in ipairs(result) do
            seg.width = I18n.displayBounds(vg, 0, 0, seg.text)
            total = total + seg.width
        end
        return result, total
    end
    local function flush()
        if #current > 0 then rows[#rows + 1] = current; current = {} end
    end
    local function append(token, color)
        if token == "\n" then flush(); return end
        local proposed, total = candidate(token, color)
        if total <= width then current = proposed; return end
        flush()
        proposed, total = candidate(token, color)
        if total <= width then current = proposed; return end
        for _, code in utf8.codes(token) do
            local char = utf8.char(code)
            proposed, total = candidate(char, color)
            if total > width and #current > 0 then flush(); proposed = candidate(char, color) end
            current = proposed
        end
    end
    for _, seg in ipairs(segments) do
        local word = ""
        for _, code in utf8.codes(seg.text) do
            local char = utf8.char(code)
            if code < 128 and char:match("[%w%p]") then word = word .. char
            else
                if word ~= "" then append(word, seg); word = "" end
                append(char, seg)
            end
        end
        if word ~= "" then append(word, seg) end
    end
    flush()
    return rows
end

function M.clearCache()
    layoutCache = {}
    cachedVg = nil
end

local function buildLayout(vg, poolId, width)
    if cachedVg ~= vg then layoutCache = {}; cachedVg = vg end
    local key = I18n.get() .. "\0" .. tostring(poolId) .. "\0" .. width
    if layoutCache[key] then return layoutCache[key] end
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local result = { rows = {}, height = 0 }
    local function addParagraph(segments, stroke)
        local rows = wrap(vg, translatedSegments(segments), width - STROKE * 2)
        if #rows == 0 then result.height = result.height + LINE_H * 0.5; return end
        for _, row in ipairs(rows) do
            result.rows[#result.rows + 1] = { segments = row, y = result.height, stroke = stroke }
            result.height = result.height + LINE_H
        end
    end
    for _, parts in ipairs(ruleParagraphs(poolId)) do addParagraph(parts, false) end
    result.height = result.height + 24
    addParagraph({ segment("可获得的奖励：", TEXT) }, false)
    result.height = result.height + 8
    local stellar = isStellar(poolId)
    local order = stellar and { UrGachaConfig.QUALITY_UR, UrGachaConfig.QUALITY_SSR,
        UrGachaConfig.QUALITY_SR, UrGachaConfig.QUALITY_R } or { 3, 2, 1, 0 }
    local tags, colors = stellar and STELLAR_TAG or QUALITY_TAG, stellar and STELLAR_COLOR or QUALITY_COLOR
    for _, quality in ipairs(order) do
        local group = stellar and UrGachaConfig.getPoolGroup(quality) or GachaConfig.getPoolGroup(quality)
        if group then
            local color = colors[quality]
            local names = {}
            for _, item in ipairs(group.items) do
                local name
                if item.type == "hero" or (not stellar and item.type == "shard") then
                    local hero = HC.HEROES[item.heroId]
                    name = hero and hero.name or ("英雄" .. tostring(item.heroId))
                    if item.type == "shard" then name = name .. "碎片" end
                elseif not stellar then name = RESOURCE_NAMES[item.resType] or item.resType end
                if name then
                    if #names > 0 then names[#names + 1] = segment("  ", color) end
                    names[#names + 1] = segment("[" .. tags[quality] .. "]" .. name, color)
                end
            end
            if #names > 0 then addParagraph(names, true); result.height = result.height + 10 end
        end
    end
    result.height = result.height + STROKE * 2
    layoutCache[key] = result
    return result
end

-- rect与原弹窗同设计空间，保留宿主鼠标滚轮/拖拽输入，只修复内容滚动范围。
function M.draw(vg, poolId, rect, scroll)
    local layout = buildLayout(vg, poolId, rect.w)
    local maxScroll = math.max(0, layout.height - rect.h)
    local actualScroll = math.max(0, math.min(maxScroll, scroll))
    nvgSave(vg)
    nvgIntersectScissor(vg, rect.x, rect.y, rect.w, rect.h)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    for _, row in ipairs(layout.rows) do
        local y = rect.y + STROKE + row.y - actualScroll
        if y + LINE_H > rect.y and y < rect.y + rect.h then
            local x = rect.x + STROKE
            for _, seg in ipairs(row.segments) do
                if row.stroke then
                    nvgFillColor(vg, nvgRGBA(48, 48, 48, 255))
                    for index = 0, 7 do
                        local angle = index * math.pi * 0.25
                        I18n.displayText(vg, x + math.cos(angle) * STROKE,
                            y + math.sin(angle) * STROKE, seg.text, nil)
                    end
                end
                nvgFillColor(vg, nvgRGBA(seg.r, seg.g, seg.b, 255))
                I18n.displayText(vg, x, y, seg.text, nil)
                x = x + seg.width
            end
        end
    end
    nvgRestore(vg)
    if maxScroll > 0 then
        local trackX = rect.x + rect.w + 10
        local thumbH = math.max(32, rect.h * rect.h / layout.height)
        local thumbY = rect.y + (rect.h - thumbH) * actualScroll / maxScroll
        nvgBeginPath(vg)
        nvgRoundedRect(vg, trackX, rect.y, 5, rect.h, 2.5)
        nvgFillColor(vg, nvgRGBA(48, 41, 34, 210)); nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, trackX, thumbY, 5, thumbH, 2.5)
        nvgFillColor(vg, nvgRGBA(155, 120, 76, 240)); nvgFill(vg)
    end
    return actualScroll
end

return M
