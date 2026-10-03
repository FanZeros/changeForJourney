-- 装备动态文案的严格兼容入口。仅解析已登记原文模板；不做任意中文子串替换。
-- 不 require core.I18n，避免 I18n 注册词典时形成循环依赖。
local D = require("core.I18nEquipment")
local M = {}

local SLOT_NAMES = { "武器", "副手", "护甲", "头盔", "鞋子", "饰品" }
local SLOT_PACKS = {
    zh_TW = { "武器", "副手", "護甲", "頭盔", "鞋子", "飾品" },
    en = { "Weapon", "Off hand", "Armor", "Helmet", "Boots", "Accessory" },
    ja = { "武器", "サブ", "鎧", "兜", "靴", "装飾品" },
    ko = { "무기", "보조", "갑옷", "투구", "신발", "장신구" },
}
local LIST_SEPARATOR = { zh_TW = "、", en = ", ", ja = "、", ko = ", " }

local function formatted(pack, source, ...)
    local template = pack[source]
    if not template then return nil end
    local ok, result = pcall(string.format, template, ...)
    return ok and result or nil
end

local function knownPart(pack, text)
    if pack[text] then return pack[text] end
    local count = text:match("^(%d+) 条随机词条$")
    if count then return formatted(pack, "%d 条随机词条", tonumber(count)) end
    local a, b = text:match("^词条倍率 ×(%d+%.%d%d) → ×(%d+%.%d%d)$")
    if a then return formatted(pack, "词条倍率 ×%.2f → ×%.2f", tonumber(a), tonumber(b)) end
    a = text:match("^词条倍率 ×(%d+%.%d%d)$")
    if a then return formatted(pack, "词条倍率 ×%.2f", tonumber(a)) end
    count = text:match("^副属性轮转强化 (%d+) 次$")
    if count then return formatted(pack, "副属性轮转强化 %d 次", tonumber(count)) end
    return nil
end

local function knownList(pack, text, lang)
    local parts = {}
    local position = 1
    while position <= #text do
        local first, last = text:find("、", position, true)
        local source = text:sub(position, first and first - 1 or #text)
        local translated = knownPart(pack, source)
        if not translated then return nil end
        parts[#parts + 1] = translated
        if not last then break end
        position = last + 1
        if position > #text then return nil end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, LIST_SEPARATOR[lang])
end

--- 完整原文→译文；未登记文本、路径、未知语言和非字符串返回 nil，由 I18n 原样回退。
---@param text any
---@param lang string
---@return string|nil
function M.lookup(text, lang)
    local pack = D[lang]
    if not pack or type(text) ~= "string" or text == "" then return nil end
    if pack[text] then return pack[text] end
    local part = knownPart(pack, text)
    if part then return part end

    local name = text:match("^(.-) 升阶$")
    if name and pack[name] then return formatted(pack, "%s 升阶", pack[name]) end

    local a, b, suffix = text:match("^腐化状态：诅咒 (%d+)/(%d+) 层(.*)$")
    if a then
        local source = "腐化状态：诅咒 %d/%d 层"
        if suffix == "（需神圣石洗除）" then
            source = "腐化状态：诅咒 %d/%d 层（需神圣石洗除）"
        elseif suffix ~= "" then
            return nil
        end
        return formatted(pack, source, tonumber(a), tonumber(b))
    end
    local count = text:match("^已洗除 1 层诅咒，剩余 (%d+) 层$")
    if count then return formatted(pack, "已洗除 1 层诅咒，剩余 %d 层", tonumber(count)) end

    local affix, fromGrade, toGrade = text:match("^词缀「(.-)」品级 ([DCBAS]) → ([DCBAS])$")
    if affix and pack[affix] then
        return formatted(pack, "词缀「%s」品级 %s → %s", pack[affix], fromGrade, toGrade)
    end
    local prefix, list = text:match("^(将新增 )(.*)$")
    if not prefix then prefix, list = text:match("^(升阶获得：)(.*)$") end
    if prefix then
        local translated = knownList(pack, list, lang)
        if not translated then return nil end
        return formatted(pack, prefix == "将新增 " and "将新增 %s" or "升阶获得：%s", translated)
    end

    local refund = text:match("^返还卷轴 (.+)$")
    if refund then
        local translatedParts = {}
        local position = 1
        local seen = {}
        while position <= #refund do
            local first, last = refund:find(" ", position, true)
            local token = refund:sub(position, first and first - 1 or #refund)
            local source, amount = token:match("^([^+]+)%+(%d+)$")
            if not source or seen[source] then return nil end
            local translatedName = nil ---@type string|nil
            for i, slotName in ipairs(SLOT_NAMES) do
                if source == slotName then translatedName = SLOT_PACKS[lang][i]; break end
            end
            if not translatedName then return nil end
            seen[source] = true
            translatedParts[#translatedParts + 1] = translatedName .. "+" .. amount
            if not last then break end
            position = last + 1
            if position > #refund then return nil end
        end
        return formatted(pack, "返还卷轴 %s", table.concat(translatedParts, " "))
    end
    return nil
end

--- 显示列表分隔符，不翻译参数或业务表。
---@param lang string
---@return string
function M.separator(lang)
    return LIST_SEPARATOR[lang] or "、"
end

return M
