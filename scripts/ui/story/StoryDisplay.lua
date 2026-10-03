-- 剧情显示边界：全文本地化 → 原样测量折行 → UTF-8 打字 → 原样绘制。
-- 此模块不修改业务文本；语言变化自动清空全文/布局缓存。
local I18n = require("core.I18n")
local Story = require("core.I18nStory")
local M = {}
local language = ""
---@type table<string, string>
local texts = {}
---@type table<string, StoryDisplayRow[]>
local layouts = {}
local layoutCount = 0

local function refresh()
    local current = I18n.get()
    if language ~= current then
        language, texts, layouts, layoutCount = current, {}, {}, 0
    end
    return current
end

--- 用完整译文固定折行；字数增长只影响行前缀，不使已显示单词跳行。
---@param vg any
---@param displayText string
---@param width number
---@param height number
---@param preferredFont number
---@param minimumFont number
---@param lineHeight number
---@return number
---@return StoryDisplayRow[]
function M.fitLayout(vg, displayText, width, height, preferredFont, minimumFont, lineHeight)
    local font = preferredFont
    local rows = M.layoutText(vg, displayText, width, font)
    while font > minimumFont and #rows * font * lineHeight > height do
        font = math.max(minimumFont, font - 1)
        rows = M.layoutText(vg, displayText, width, font)
    end
    return font, rows
end

---@param source string
---@return string
function M.text(source)
    if type(source) ~= "string" or source == "" then return "" end
    local lang = refresh()
    if texts[source] == nil then
        local translated = I18n.lookup(source)
        texts[source] = translated ~= source and translated or (Story.lookup(source, lang) or source)
    end
    return texts[source]
end

---@param vg any
---@param displayText string 已翻译完整句，不在本函数内二次翻译
---@param width number
---@param fontSize number
---@return StoryDisplayRow[]
function M.layoutText(vg, displayText, width, fontSize)
    refresh()
    local key = tostring(vg) .. "|" .. tostring(width) .. "|" .. tostring(fontSize) .. "|" .. displayText
    if layouts[key] then return layouts[key] end
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    local rows = Story.wrap(displayText, width, function(part)
        return I18n.displayBounds(vg, 0, 0, part)
    end)
    if layoutCount >= 128 then layouts, layoutCount = {}, 0 end
    layouts[key] = rows
    layoutCount = layoutCount + 1
    return rows
end

---@param vg any
---@param source string 完整源文
---@param width number
---@param fontSize number
---@return StoryDisplayRow[]
function M.layout(vg, source, width, fontSize)
    return M.layoutText(vg, M.text(source), width, fontSize)
end

---@param vg any
---@param x number
---@param y number
---@param rows StoryDisplayRow[] 完整译文已经折行
---@param count number 已显示码点数
---@param lineHeight number
function M.drawRows(vg, x, y, rows, count, lineHeight)
    for i, row in ipairs(rows) do
        local part = Story.rowPrefix(row, count)
        if part ~= "" then I18n.displayText(vg, x, y + (i - 1) * lineHeight, part, nil) end
    end
end

---@param vg any
---@param x number
---@param y number
---@param source string
function M.draw(vg, x, y, source)
    I18n.displayText(vg, x, y, M.text(source), nil)
end

return M
