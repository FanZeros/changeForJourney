
-- ============================================================================
-- KeywordText - 可点击关键词富文本组件（NanoVG）
-- ----------------------------------------------------------------------------
-- 把描述文本按 KeywordConfig 词表拆段：普通文本用常规色，关键词用金色高亮（无下划线），
-- 点击关键词弹出解释气泡（风格与属性说明气泡 attrTip 一致）。
--
-- 用法：
--   local KeywordText = require("ui.widget.KeywordText")
--   local kt = KeywordText.new()
--   -- 绘制帧内：
--   kt:draw(vg, desc, x, y, width, fontSize)   -- 画文本（同时刷新点击热区）
--   kt:drawPopup(vg)                            -- 帧末最上层画弹窗
--   -- 输入：
--   if kt:handleInput(dx, dy) then return true end
--   kt:setHover(dx, dy)  -- 可选，悬停加亮
--   kt:clear()           -- 面板关闭/切角色时清状态
--
-- 说明：
--   * 完整句子先本地化再分段，所有片段用raw绘制/测量，未知整句不局部翻译。
--   * 英文普通词和关键词尽量整体折行；超宽关键词按UTF-8拆行且片段共用原key。
--   * 缓存包含语言/源文/宽度/字号；切换语言或测量上下文使缓存与交互失效。
--   * 无绘制上下文（回归测试）时只布局/生成热区，使用确定性宽度估算。
-- ============================================================================

local KW = require("config.KeywordConfig")
local GameConfig = require("config.GameConfig")
local I18n = require("core.I18n")
local KeywordLocale = require("core.I18nKeywords")
local AD = require("systems.AttributeDef")

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

local KeywordText = {}
KeywordText.__index = KeywordText

-- ======================== 视觉常量 ========================

local KEYWORD_COLOR   = { 0xFF, 0xD7, 0x6E }           -- 金色（与 attrTip 标题一致）
local KEYWORD_HOVER   = { 0xFF, 0xEF, 0x9E }           -- 悬停更亮
local DEFAULT_TEXT    = { 0xE8, 0xDC, 0xC8 }           -- 常规描述色

local POP_PAD_X       = 24
local POP_PAD_TOP     = 16
local POP_PAD_BOT     = 18
local POP_RADIUS      = 16
local POP_ARROW_W     = 20
local POP_ARROW_H     = 12
local POP_GAP         = 6
local POP_MAX_W       = 546
local POP_NAME_FONT   = 30
local POP_DESC_FONT   = 28
local POP_LINE_H      = 36
local POP_BG          = { 0x2a, 0x1f, 0x18, 235 }

local CACHE_LIMIT     = 16   -- 布局缓存条数上限

-- ======================== 测量工具 ========================

--- 单行显示文本测量；必须绕过I18n全局hook，避免分段后发生二次翻译。
---@param vg any
---@param fontSize number
---@param s string
---@return number width, number inkLeft, number inkTop, number inkHeight
local function measure(vg, fontSize, s)
    if vg and nvgTextBounds then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        nvgTextLetterSpacing(vg, 0)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local bounds = {}
        local measured = I18n.displayBounds(vg, 0, 0, s, bounds)
        local advance = tonumber(measured) or 0
        local left = math.min(0, bounds[1] or 0)
        local right = math.max(advance, bounds[3] or advance)
        return right - left, left, bounds[2] or 0,
            math.max(0, (bounds[4] or fontSize) - (bounds[2] or 0))
    end
    -- 无绘制上下文时的确定性估算；不调用任何引擎绘制API。
    local w = 0
    for _, c in utf8.codes(s) do
        w = w + (c > 0x7F and fontSize or fontSize * 0.55)
    end
    return w, 0, 0, fontSize
end

-- 字体栅格测量依赖当前缩放；同一上下文缩放后不能继续用旧片段宽高。
local function measurementScale(vg, fontSize)
    if not vg then return "" end
    local transform = {}
    if nvgCurrentTransform then
        local ok, returned = pcall(nvgCurrentTransform, vg, transform)
        if type(returned) == "table" then transform = returned end
        if not ok then transform = {} end
    end
    -- frame 的 pixelRatio 不在矩阵内；真实字形探针同时区分 DPR 与字体栅格变化。
    local width, left, top, height = measure(vg, fontSize, "Ag国0123456789%")
    return table.concat({ tostring(transform[1]), tostring(transform[2]),
        tostring(transform[3]), tostring(transform[4]),
        tostring(width), tostring(left), tostring(top), tostring(height) }, ":")
end

-- ======================== 文本拆段 ========================

--- 英文匹配使用完整词边界，不能把Echoist/echoing/前缀变量认成Echo。
--- Latin扩展、连字符和下划线视为单词组成部分；日/韩助词不阻挡机制名。
local function isLatinWord(c)
    if not c then return false end
    return (c >= 48 and c <= 57) or (c >= 65 and c <= 90)
        or (c >= 97 and c <= 122) or c == 95 or c == 45
        or (c >= 0xC0 and c <= 0x2AF) or (c >= 0x300 and c <= 0x36F)
end

local function hasWordBoundary(text, at, count, term)
    if not term:find("[A-Za-z]", 1) then return true end
    local before = utf8.offset(text, -1, at)
    local left = before and utf8.codepoint(text, before) or nil
    local after = at + count
    local right = after <= #text and utf8.codepoint(text, after) or nil
    return not isLatinWord(left) and not isLatinWord(right)
end

--- 先翻完整句子再拆显示段；未知全文保持原文，绝不逐子串翻译。
--- 原key仅保存在key字段；text始终是实际显示文本，不反推翻译后的业务key。
---@param source string
---@return table[], string
local function splitSegments(source)
    local lang = I18n.get()
    local text = KeywordLocale.lookup(source, lang) or I18n.lookup(source)
    local terms = KeywordLocale.terms(lang)
    local lowered = text:lower()
    local segs, plain = {}, {}
    local i = 1
    while i <= #text do
        local matched = nil ---@type table|nil
        for _, term in ipairs(terms) do
            local count = #term.text
            if lowered:sub(i, i + count - 1) == term.text:lower()
                and hasWordBoundary(text, i, count, term.text) then
                matched = term
                break
            end
        end
        if matched then
            if #plain > 0 then
                segs[#segs + 1] = { text = table.concat(plain), keyword = false }
                plain = {}
            end
            local count = #matched.text
            segs[#segs + 1] = { text = text:sub(i, i + count - 1), keyword = true, key = matched.key }
            i = i + count
        else
            local nextIndex = utf8.offset(text, 2, i) or (#text + 1)
            plain[#plain + 1] = text:sub(i, nextIndex - 1)
            i = nextIndex
        end
    end
    if #plain > 0 then segs[#segs + 1] = { text = table.concat(plain), keyword = false } end
    return segs, text
end

-- 显示样式只作用于片段颜色，不改文本或业务 key（神器数值/比例沿用旧色）。
local function styledSegments(segs, styles)
    if not styles or #styles == 0 then return segs end
    local result = {}
    for _, seg in ipairs(segs) do
        if seg.keyword then
            result[#result + 1] = seg
        else
            local at = 1
            while at <= #seg.text do
                local first, last, color
                for _, style in ipairs(styles) do
                    if style.text and style.text ~= "" then
                        local s, e = seg.text:find(style.text, at, true)
                        if s and (not first or s < first or (s == first and e > last)) then
                            first, last, color = s, e, style.color
                        end
                    end
                end
                if not first then
                    result[#result + 1] = { text = seg.text:sub(at) }
                    break
                end
                if first > at then result[#result + 1] = { text = seg.text:sub(at, first - 1) } end
                result[#result + 1] = { text = seg.text:sub(first, last), color = color }
                at = last + 1
            end
        end
    end
    return result
end

-- ======================== 排版（缓存） ========================

--- UTF-8安全折行：英文普通词尽量整体换行，超宽词/关键词才逐codepoint拆行。
--- 显式换行、空行和全部显示字符保持；拆开的关键词片段共享原业务key。
---@param vg any
---@param segs table[]
---@param width number
---@param fontSize number
---@return table
local function layoutSegments(vg, segs, width, fontSize)
    width = math.max(1, width)
    local lines = {}
    local cur = { pieces = {}, width = 0 }
    lines[1] = cur
    local function pushLine()
        cur = { pieces = {}, width = 0 }
        lines[#lines + 1] = cur
    end
    local pieceColor = nil ---@type table|nil
    local function addPiece(s, key)
        if s == "" then return end
        local w, inkLeft, inkTop, inkHeight = measure(vg, fontSize, s)
        cur.pieces[#cur.pieces + 1] = { text = s, keyword = key ~= nil, key = key, w = w,
            inkLeft = inkLeft, inkTop = inkTop, inkHeight = inkHeight, color = pieceColor }
        cur.width = cur.width + w
    end
    local function addToken(token, key)
        local w = measure(vg, fontSize, token)
        if cur.width > 0 and cur.width + w > width then pushLine() end
        if w <= width then
            addPiece(token, key)
            return
        end
        -- 超宽token只沿UTF-8边界拆分；单个字形大于width时仍保留该字形。
        local buf = ""
        for _, code in utf8.codes(token) do
            local ch = utf8.char(code)
            local candidate = buf .. ch
            if buf ~= "" and cur.width + measure(vg, fontSize, candidate) > width then
                addPiece(buf, key)
                pushLine()
                buf = ch
            else
                buf = candidate
            end
        end
        addPiece(buf, key)
    end
    for _, seg in ipairs(segs) do
        pieceColor = seg.color
        if seg.keyword then
            addToken(seg.text, seg.key)
        else
            local word = ""
            local function flushWord()
                if word ~= "" then addToken(word, nil); word = "" end
            end
            for _, code in utf8.codes(seg.text) do
                local ch = utf8.char(code)
                if isLatinWord(code) or ch == "'" then
                    word = word .. ch
                else
                    flushWord()
                    if ch == "\n" then pushLine() else addToken(ch, nil) end
                end
            end
            flushWord()
        end
    end
    -- 合并相邻同类型片段，以完整实际绘制片段重新测宽，避免kerning造成热区漂移。
    for _, line in ipairs(lines) do
        local pieces = {}
        for _, piece in ipairs(line.pieces) do
            local previous = pieces[#pieces]
            if previous and not previous.keyword and not piece.keyword and previous.color == piece.color then
                -- 普通文字可以合并，关键词不合并（相邻不同出现次数仍有独立热区）。
                local combined = previous.text .. piece.text
                local combinedW, inkLeft, inkTop, inkHeight = measure(vg, fontSize, combined)
                if line.width - previous.w - piece.w + combinedW <= width then
                    line.width = line.width - previous.w - piece.w + combinedW
                    previous.text, previous.w = combined, combinedW
                    previous.inkLeft, previous.inkTop, previous.inkHeight = inkLeft, inkTop, inkHeight
                else
                    pieces[#pieces + 1] = piece
                end
            else
                pieces[#pieces + 1] = piece
            end
        end
        line.pieces = pieces
    end
    return { lines = lines, fontSize = fontSize }
end

local function layoutMetrics(layout, fontSize, lineHeight)
    local lh = lineHeight or math.floor(fontSize * 1.35 + 0.5)
    local inkHeight = fontSize
    for _, line in ipairs(layout.lines) do
        for _, piece in ipairs(line.pieces) do
            inkHeight = math.max(inkHeight, piece.inkHeight or fontSize)
        end
    end
    lh = math.max(lh, inkHeight)
    return lh, math.max(#layout.lines * lh, (#layout.lines - 1) * lh + inkHeight)
end

local function layoutText(vg, text, width, fontSize, opts)
    -- 属性全名无需做机制子串扫描；本地化仅发生一次。
    local segs, display
    if opts and opts.attributeKey then
        display = I18n.lookup(text)
        segs = { { text = display, keyword = true, key = "attribute:" .. opts.attributeKey } }
    else
        segs, display = splitSegments(text)
    end
    segs = styledSegments(segs, opts and opts.styles)
    local layout = layoutSegments(vg, segs, width, fontSize)
    layout.displayText = display
    return layout
end

-- ======================== 实例 ========================

---@class KeywordTextInstance
---@field popup table|nil { key, name, desc, cx, topY }
---@field hoverIdx integer|nil
---@field hotspots table[] 当前显示帧热区 { x1,y1,x2,y2,name=原key,text=显示片段 }

--- 创建实例
---@param opts table|nil { textColor = {r,g,b}, popupMaxW = number }
---@return KeywordTextInstance
function KeywordText.new(opts)
    local self = setmetatable({}, KeywordText)
    self:init(opts or {})
    return self --[[@as KeywordTextInstance]]
end

function KeywordText:init(opts)
    self.textColor = opts.textColor or DEFAULT_TEXT
    self.popupMaxW = opts.popupMaxW or POP_MAX_W
    self.popup = nil ---@type table|nil
    self.hoverIdx = nil ---@type integer|nil
    self.hotspots = {}
    self._cache = {} ---@type table<string, table>
    self._cacheKeys = {} ---@type string[]
    self._lastLayoutH = 0
    self._layoutLanguage = ""
    self._layoutContext = nil ---@type any
    self._drawIndex = 0
    self._drawIdentities = {} ---@type string[]
end

function KeywordText:_syncLanguage()
    local language = I18n.get()
    if self._layoutLanguage ~= language then
        self._layoutLanguage = language
        self:clear()
    end
end

--- 取（或构建）排版缓存
---@param vg any
---@param text string
---@param width number
---@param fontSize number
---@return table
function KeywordText:_layout(vg, text, width, fontSize, opts)
    self:_syncLanguage()
    -- nil估算布局不能污染后续真实NanoVG字体测量；切换上下文时也必须失效。
    if self._layoutContext ~= vg then
        self._layoutContext = vg
        self._cache, self._cacheKeys = {}, {}
        self.hotspots, self.hoverIdx, self.popup = {}, nil, nil
        self._drawIndex = 0
        self._drawIdentities = {}
    end
    local styleKeys = { opts and opts.attributeKey or "" }
    for _, style in ipairs(opts and opts.styles or {}) do
        styleKeys[#styleKeys + 1] = style.text .. ":" .. table.concat(style.color, ",")
    end
    local key = I18n.get() .. "\0" .. text .. "\0" .. width .. "\0" .. fontSize
        .. "\0" .. measurementScale(vg, fontSize) .. "\0" .. table.concat(styleKeys, "\0")
    local hit = self._cache[key]
    if hit then return hit end
    local layout = layoutText(vg, text, width, fontSize, opts)
    self._cache[key] = layout
    self._cacheKeys[#self._cacheKeys + 1] = key
    if #self._cacheKeys > CACHE_LIMIT then
        local old = table.remove(self._cacheKeys, 1)
        if old then self._cache[old] = nil end
    end
    return layout
end

--- 绘制文本并刷新关键词热区（弹窗请用 drawPopup 在帧末画）
---@param vg any
---@param text string
---@param x number 左上角 X（居左对齐时使用）
---@param y number 左上角 Y
---@param width number 折行宽度
---@param fontSize number
---@param lineHeight number|nil 行高（默认 fontSize*1.35）
---@param centerCX number|nil 传入则每行以该 X 居中（x 仅参与折行宽度计算）
---@param keepHotspots boolean|nil 为 true 时追加热区（同一帧多段文本共用一个实例）
---@param opts table|nil 仅显示选项 { keywordColor, alpha, clip={x,y,w,h}, interactive=false, styles }
---@return number 总高度
function KeywordText:draw(vg, text, x, y, width, fontSize, lineHeight, centerCX, keepHotspots, opts)
    local layout = self:_layout(vg, text, width, fontSize, opts)
    local lh, height = layoutMetrics(layout, fontSize, lineHeight)

    if not keepHotspots then
        self.hotspots = {}
        self._drawIndex = 0
    end
    -- 同帧多段各自保存身份，避免总览首尾段每帧互相清掉弹窗。
    self._drawIndex = self._drawIndex + 1
    local clip = opts and opts.clip
    local identity = table.concat({ text, tostring(x), tostring(y), tostring(width),
        tostring(fontSize), tostring(lh), tostring(centerCX), tostring(opts and opts.attributeKey),
        tostring(opts and opts.interactive), clip and table.concat(clip, ",") or "" }, "\0")
    if identity ~= self._drawIdentities[self._drawIndex] then
        self._drawIdentities[self._drawIndex] = identity
        self.popup, self.hoverIdx = nil, nil
    end
    if vg then
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    end

    for li, line in ipairs(layout.lines) do
        local ly = y + (li - 1) * lh
        local cx = x
        if centerCX then
            cx = centerCX - line.width * 0.5
        end
        for _, p in ipairs(line.pieces) do
            if p.keyword then
                local x1, y1, x2 = cx, ly, cx + p.w
                local y2 = ly + math.max(fontSize, p.inkHeight or fontSize)
                if clip then
                    x1, y1 = math.max(x1, clip[1]), math.max(y1, clip[2])
                    x2, y2 = math.min(x2, clip[1] + clip[3]), math.min(y2, clip[2] + clip[4])
                end
                local idx = #self.hotspots + 1
                if x2 > x1 and y2 > y1 and not (opts and opts.interactive == false) then
                    self.hotspots[idx] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2,
                        name = p.key, key = p.key, text = p.text, clip = clip,
                        sourceName = opts and opts.attributeKey and text or nil }
                end
                if vg then
                    local col = opts and opts.keywordColor
                        or (self.hoverIdx == idx and KEYWORD_HOVER or KEYWORD_COLOR)
                    nvgFontSize(vg, fontSize)
                    nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], opts and opts.alpha or col[4] or 255))
                    I18n.displayText(vg, cx - (p.inkLeft or 0), ly - (p.inkTop or 0), p.text, nil)
                end
            elseif vg then
                nvgFontSize(vg, fontSize)
                local tc = p.color or self.textColor
                nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], opts and opts.alpha or tc[4] or 255))
                I18n.displayText(vg, cx - (p.inkLeft or 0), ly - (p.inkTop or 0), p.text, nil)
            end
            cx = cx + p.w
        end
    end

    self._lastLayoutH = height
    return self._lastLayoutH
end

--- 多行表格一帧起点：保留布局缓存和当前气泡，空表也会清旧热区。
function KeywordText:beginFrame()
    self:_syncLanguage()
    self.hotspots = {}
    self._drawIndex = 0
end

--- 固定高度属性名：整行按原属性key点击，数值/徽章仍由调用者绘制。
---@param vg any
---@param text string
---@param attributeKey string|nil
---@param x number 左对齐起点或右对齐终点
---@param centerY number
---@param maxW number
---@param fontSize number
---@param opts table|nil { right, keywordColor, alpha, clip, interactive }
---@return number width, number fontSize
function KeywordText:drawAttribute(vg, text, attributeKey, x, centerY, maxW, fontSize, opts)
    opts = opts or {}
    local style = {}
    for key, value in pairs(opts) do style[key] = value end
    local meta = attributeKey and AD.META[attributeKey]
    if meta and AD.getDesc(attributeKey) ~= "" then style.attributeKey = attributeKey end
    local size = fontSize
    local layout = self:_layout(vg, text, 100000, size, style)
    local width = layout.lines[1].width
    while width > maxW and size > 8 do
        size = size - 1
        layout = self:_layout(vg, text, 100000, size, style)
        width = layout.lines[1].width
    end
    local left = opts.right and x - width or x
    self:draw(vg, text, left, centerY - size * 0.5, math.max(maxW, width), size, size, nil, true, style)
    return width, size
end

--- 帧末移除已经不再绘制的尾段，防止旧热区对应的弹窗继续显示。
function KeywordText:_finishDraw()
    if #self._drawIdentities > self._drawIndex then
        for i = #self._drawIdentities, self._drawIndex + 1, -1 do
            self._drawIdentities[i] = nil
        end
        self.popup, self.hoverIdx = nil, nil
    end
end

--- 最近一次 draw 的总高度
---@return number
function KeywordText:lastHeight()
    return self._lastLayoutH
end

--- 测量排版高度（不绘制、不清热区；用于自适应字号场景）
---@param vg any
---@param text string
---@param width number
---@param fontSize number
---@param lineHeight number|nil 行高（默认 fontSize*1.35）
---@return number height, integer lineCount
function KeywordText:measureHeight(vg, text, width, fontSize, lineHeight)
    local layout = self:_layout(vg, text, width, fontSize)
    local _, height = layoutMetrics(layout, fontSize, lineHeight)
    ---@type any[]
    local lines = layout.lines
    local lineCount = #lines
    return height, lineCount
end

--- 设置热区坐标变换：把输入坐标映射到热区空间（热区在缩放/平移变换内绘制时用）
---@param f fun(dx: number, dy: number): number, number
function KeywordText:setTransform(f)
    self._xform = f
end

--- 设置弹窗锚点变换：把热区空间的锚点坐标映射到 drawPopup 的绘制空间
---（文本在缩放变换内绘制、而解释弹窗要在变换外绘制时用）
---@param f fun(cx: number, topY: number): number, number
function KeywordText:setPopupTransform(f)
    self._popupXform = f
end

--- 应用坐标变换（未设置则原样返回）
---@param dx number
---@param dy number
---@return number, number
function KeywordText:_map(dx, dy)
    if self._xform then return self._xform(dx, dy) end
    return dx, dy
end

local function containsHotspot(h, x, y)
    local clip = h.clip
    if clip and (x < clip[1] or x > clip[1] + clip[3] or y < clip[2] or y > clip[2] + clip[4]) then
        return false
    end
    return x >= h.x1 and x <= h.x2 and y >= h.y1 - 4 and y <= h.y2 + 4
end

local function hotspotDefinition(key, sourceName)
    local attributeKey = key:match("^attribute:(.+)$")
    if attributeKey then return KeywordLocale.getAttribute(attributeKey, I18n.get(), sourceName) end
    return KeywordLocale.get(key, I18n.get())
end

--- 悬停更新（可选调用；坐标与热区同空间）
---@param dx number
---@param dy number
function KeywordText:setHover(dx, dy)
    self:_syncLanguage()
    local mx, my = self:_map(dx, dy)
    local hitIdx = nil
    for i, h in ipairs(self.hotspots) do
        if containsHotspot(h, mx, my) then
            hitIdx = i
            break
        end
    end
    self.hoverIdx = hitIdx
end

--- 弹窗是否打开
---@return boolean
function KeywordText:isOpen()
    self:_syncLanguage()
    return self.popup ~= nil
end

--- 关闭弹窗
function KeywordText:closePopup()
    self.popup = nil
end

--- 清空全部交互状态（面板关闭/切角色时调用）
function KeywordText:clear()
    self.popup = nil
    self.hoverIdx = nil
    self.hotspots = {}
    self._cache = {}
    self._cacheKeys = {}
    self._lastLayoutH = 0
    self._drawIndex = 0
    self._drawIdentities = {} ---@type string[]
end

--- 点击输入。返回 true 表示消费事件。
--- 规则：弹窗开着 → 任意点击先关弹窗；否则命中关键词 → 弹窗。
---@param dx number
---@param dy number
---@return boolean
function KeywordText:handleInput(dx, dy)
    self:_syncLanguage()
    if self.popup then
        self.popup = nil
        return true
    end
    local mx, my = self:_map(dx, dy)
    for _, h in ipairs(self.hotspots) do
        if containsHotspot(h, mx, my) then
            local def = hotspotDefinition(h.name, h.sourceName)
            if def then
                local anchorCX = (h.x1 + h.x2) * 0.5
                local anchorY  = h.y1
                if self._popupXform then
                    anchorCX, anchorY = self._popupXform(anchorCX, anchorY)
                end
                self.popup = {
                    key   = h.name,
                    name  = def.title,
                    desc  = def.desc,
                    cx    = anchorCX,
                    topY  = anchorY,
                }
                local ok, SFX = pcall(require, "systems.GameSFX")
                if ok and SFX and SFX.play then SFX.play("click") end
                print("[KeywordText] 打开关键词: " .. h.name)
                return true
            end
        end
    end
    return false
end

--- 帧末最上层绘制弹窗（风格与 attrTip 一致）
---@param vg any
function KeywordText:drawPopup(vg)
    self:_syncLanguage()
    self:_finishDraw()
    local tip = self.popup
    if not tip or not vg then return end

    nvgFontFace(vg, "sans")
    local tipW = math.max(POP_PAD_X * 2 + 1, math.min(self.popupMaxW, DESIGN_W - 32))
    local wrapW = tipW - POP_PAD_X * 2
    -- 标题和正文都按显示文本排版，不再走全局lookup，也不嵌套关键词。
    local titleLayout = layoutSegments(vg, { { text = tip.name } }, wrapW, POP_NAME_FONT)
    local descLayout = layoutSegments(vg, { { text = tip.desc } }, wrapW, POP_DESC_FONT)
    local titleH = #titleLayout.lines * (POP_NAME_FONT + 4)
    local descH = #descLayout.lines * POP_LINE_H
    local tipH = POP_PAD_TOP + titleH + 8 + descH + POP_PAD_BOT

    -- 默认弹在热区上方；空间不够翻到下方
    local arrowTipY = tip.topY - POP_GAP
    local tipBottomY = arrowTipY - POP_ARROW_H
    local tipTopY = tipBottomY - tipH
    local arrowUp = false  -- true = 箭头朝上（弹窗在下方）
    if tipTopY < 8 then
        arrowUp = true
        local belowTop = tip.topY + POP_NAME_FONT + 24
        arrowTipY = belowTop + POP_GAP
        tipTopY = arrowTipY + POP_ARROW_H
        tipBottomY = arrowTipY
    end

    local tipLeft = tip.cx - tipW * 0.5
    local tipRight = tip.cx + tipW * 0.5
    if tipLeft < 16 then
        tipLeft, tipRight = 16, 16 + tipW
    end
    if tipRight > DESIGN_W - 16 then
        tipRight, tipLeft = DESIGN_W - 16, DESIGN_W - 16 - tipW
    end
    local arrowCX = math.max(tipLeft + POP_ARROW_W + POP_RADIUS,
                     math.min(tip.cx, tipRight - POP_ARROW_W - POP_RADIUS))

    nvgBeginPath(vg)
    nvgRoundedRect(vg, tipLeft, tipTopY, tipW, tipH, POP_RADIUS)
    nvgFillColor(vg, nvgRGBA(POP_BG[1], POP_BG[2], POP_BG[3], POP_BG[4]))
    nvgFill(vg)

    nvgBeginPath(vg)
    if arrowUp then
        nvgMoveTo(vg, arrowCX - POP_ARROW_W, tipTopY)
        nvgLineTo(vg, arrowCX, tipTopY - POP_ARROW_H)
        nvgLineTo(vg, arrowCX + POP_ARROW_W, tipTopY)
    else
        nvgMoveTo(vg, arrowCX - POP_ARROW_W, tipBottomY)
        nvgLineTo(vg, arrowCX, arrowTipY)
        nvgLineTo(vg, arrowCX + POP_ARROW_W, tipBottomY)
    end
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(POP_BG[1], POP_BG[2], POP_BG[3], POP_BG[4]))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, tipLeft, tipTopY, tipW, tipH, POP_RADIUS)
    nvgStrokeColor(vg, nvgRGBA(0xC4, 0x8A, 0x3A, 160))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgFontSize(vg, POP_NAME_FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(0xFF, 0xD7, 0x6E, 255))
    for i, line in ipairs(titleLayout.lines) do
        local cx = tipLeft + POP_PAD_X
        for _, piece in ipairs(line.pieces) do
            I18n.displayText(vg, cx, tipTopY + POP_PAD_TOP + (i - 1) * (POP_NAME_FONT + 4), piece.text, nil)
            cx = cx + piece.w
        end
    end

    nvgFontSize(vg, POP_DESC_FONT)
    nvgFillColor(vg, nvgRGBA(0xE8, 0xE0, 0xD4, 255))
    local textY = tipTopY + POP_PAD_TOP + titleH + 8
    for i, line in ipairs(descLayout.lines) do
        local cx = tipLeft + POP_PAD_X
        for _, piece in ipairs(line.pieces) do
            I18n.displayText(vg, cx, textY + (i - 1) * POP_LINE_H, piece.text, nil)
            cx = cx + piece.w
        end
    end
end

return KeywordText
