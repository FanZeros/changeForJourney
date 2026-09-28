
-- ============================================================================
-- KeywordText - 可点击关键词富文本组件（NanoVG）
-- ----------------------------------------------------------------------------
-- 把描述文本按 KeywordConfig 词表拆段：普通文本用常规色，关键词用金色+下划线，
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
--   * 排版结果按 text+width+fontSize 缓存，同一段文本只测量一次。
--   * 换行规则与 attrTip 一致：逐字符测量；关键词作为整体不拆行。
--   * 测量依赖全局 nvgTextBounds；无引擎环境（回归测试）时退化为等宽估算。
-- ============================================================================

local KW = require("config.KeywordConfig")
local GameConfig = require("config.GameConfig")

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

local KeywordText = {}
KeywordText.__index = KeywordText

-- ======================== 视觉常量 ========================

local KEYWORD_COLOR   = { 0xFF, 0xD7, 0x6E }           -- 金色（与 attrTip 标题一致）
local KEYWORD_HOVER   = { 0xFF, 0xEF, 0x9E }           -- 悬停更亮
local DEFAULT_TEXT    = { 0xE8, 0xDC, 0xC8 }           -- 常规描述色
local UNDERLINE_W     = 2

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

--- 单行文本宽度测量；无引擎环境（测试）时用等宽估算兜底
---@param vg any
---@param fontSize number
---@param s string
---@return number
local function measure(vg, fontSize, s)
    if vg and nvgTextBounds then
        nvgFontSize(vg, fontSize)
        ---@diagnostic disable-next-line: missing-parameter
        local w = nvgTextBounds(vg, 0, 0, s)
        ---@type number
        local result = tonumber(w) or 0
        return result
    end
    -- 测试兜底：CJK 约 1em，ASCII 约 0.55em
    local w = 0
    for _, c in utf8.codes(s) do
        w = w + (c > 0x7F and fontSize or fontSize * 0.55)
    end
    return w
end

-- ======================== 文本拆段 ========================

--- 把文本拆成 { text=..., keyword=bool } 段序列；关键词长词优先
---@param text string
---@return table[]
local function splitSegments(text)
    local keys = KW.sortedKeys()
    local segs = {}
    local plain = {}
    local i = 1
    local n = #text
    while i <= n do
        local matched = nil
        for _, k in ipairs(keys) do
            local kl = #k
            if i + kl - 1 <= n and text:sub(i, i + kl - 1) == k then
                matched = k
                break
            end
        end
        if matched then
            if #plain > 0 then
                segs[#segs + 1] = { text = table.concat(plain), keyword = false }
                plain = {}
            end
            segs[#segs + 1] = { text = matched, keyword = true }
            i = i + #matched
        else
            -- 逐 codepoint 推进，避免半个汉字
            local c = utf8.codepoint(text, i) --[[@as integer?]]
            if not c then
                i = i + 1
            else
                local ch = utf8.char(c)
                plain[#plain + 1] = ch
                i = i + #ch  -- 按 UTF-8 字节数推进
            end
        end
    end
    if #plain > 0 then
        segs[#segs + 1] = { text = table.concat(plain), keyword = false }
    end
    return segs
end

-- ======================== 排版（缓存） ========================

--- 排版为行列表：lines[i] = { pieces = { {text, keyword, w} }, width }
---@param vg any
---@param text string
---@param width number
---@param fontSize number
---@return table
local function layoutText(vg, text, width, fontSize)
    local segs = splitSegments(text)
    local lines = {}
    local cur = { pieces = {}, width = 0 }
    lines[#lines + 1] = cur

    local function pushLine()
        cur = { pieces = {}, width = 0 }
        lines[#lines + 1] = cur
    end

    local function addPiece(s, isKw)
        local w = measure(vg, fontSize, s)
        cur.pieces[#cur.pieces + 1] = { text = s, keyword = isKw, w = w }
        cur.width = cur.width + w
    end

    for _, seg in ipairs(segs) do
        if seg.keyword then
            local kwW = measure(vg, fontSize, seg.text)
            if cur.width > 0 and cur.width + kwW > width then
                pushLine()
            end
            addPiece(seg.text, true)
        else
            -- 普通段逐字符折行；支持显式 \n
            -- ⚠️ bufW 单独累计：addPiece 会把整段测量宽度并入 cur.width，
            --    若累计期就写 cur.width 会双重计入 → 提前折行且行宽虚高
            local s = seg.text
            local i, n = 1, #s
            local buf = {}
            local bufW = 0
            local function flushBuf()
                if #buf > 0 then
                    addPiece(table.concat(buf), false)
                    buf = {}
                    bufW = 0
                end
            end
            while i <= n do
                local c = utf8.codepoint(s, i) --[[@as integer?]]
                if not c then break end
                local ch = utf8.char(c)
                i = i + #ch
                if ch == "\n" then
                    flushBuf()
                    pushLine()
                else
                    local chW = measure(vg, fontSize, ch)
                    if cur.width + bufW + chW > width and (cur.width > 0 or bufW > 0) then
                        flushBuf()
                        pushLine()
                    end
                    buf[#buf + 1] = ch
                    bufW = bufW + chW
                end
            end
            flushBuf()
        end
    end
    return { lines = lines, fontSize = fontSize }
end

-- ======================== 实例 ========================

---@class KeywordTextInstance
---@field popup table|nil { name, desc, cx, topY }
---@field hoverIdx integer|nil
---@field hotspots table[] 当前帧的关键词热区 { x1, y1, x2, y2, name }

--- 创建实例
---@param opts table|nil { textColor = {r,g,b}, popupMaxW = number }
---@return KeywordTextInstance
function KeywordText.new(opts)
    local self = setmetatable({}, KeywordText)
    opts = opts or {}
    self.textColor  = opts.textColor or DEFAULT_TEXT
    self.popupMaxW  = opts.popupMaxW or POP_MAX_W
    self.popup      = nil
    self.hoverIdx   = nil
    self.hotspots   = {}
    self._cache     = {}
    self._cacheKeys = {}
    self._lastLayoutH = 0
    return self --[[@as KeywordTextInstance]]
end

--- 取（或构建）排版缓存
---@param vg any
---@param text string
---@param width number
---@param fontSize number
---@return table
function KeywordText:_layout(vg, text, width, fontSize)
    local key = text .. "\0" .. width .. "\0" .. fontSize
    local hit = self._cache[key]
    if hit then return hit end
    local layout = layoutText(vg, text, width, fontSize)
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
---@return number 总高度
function KeywordText:draw(vg, text, x, y, width, fontSize, lineHeight, centerCX)
    local layout = self:_layout(vg, text, width, fontSize)
    local lh = lineHeight or math.floor(fontSize * 1.35 + 0.5)

    self.hotspots = {}
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    for li, line in ipairs(layout.lines) do
        local ly = y + (li - 1) * lh
        local cx = x
        if centerCX then
            cx = centerCX - line.width * 0.5
        end
        for _, p in ipairs(line.pieces) do
            if p.keyword then
                local idx = #self.hotspots + 1
                self.hotspots[idx] = { x1 = cx, y1 = ly, x2 = cx + p.w, y2 = ly + fontSize, name = p.text }
                local hovered = (self.hoverIdx == idx)
                local col = hovered and KEYWORD_HOVER or KEYWORD_COLOR
                nvgFontSize(vg, fontSize)
                nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 255))
                nvgText(vg, cx, ly, p.text, nil)
                -- 下划线
                local uy = ly + fontSize - 2
                nvgBeginPath(vg)
                nvgMoveTo(vg, cx, uy)
                nvgLineTo(vg, cx + p.w, uy)
                nvgStrokeColor(vg, nvgRGBA(col[1], col[2], col[3], hovered and 255 or 190))
                nvgStrokeWidth(vg, UNDERLINE_W)
                nvgStroke(vg)
            else
                nvgFontSize(vg, fontSize)
                local tc = self.textColor
                nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], tc[4] or 255))
                nvgText(vg, cx, ly, p.text, nil)
            end
            cx = cx + p.w
        end
    end

    self._lastLayoutH = #layout.lines * lh
    return self._lastLayoutH
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
    local lh = lineHeight or math.floor(fontSize * 1.35 + 0.5)
    ---@type any[]
    local lines = layout.lines
    local lineCount = #lines
    return lineCount * lh, lineCount
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

--- 悬停更新（可选调用；坐标与热区同空间）
---@param dx number
---@param dy number
function KeywordText:setHover(dx, dy)
    local mx, my = self:_map(dx, dy)
    local hitIdx = nil
    for i, h in ipairs(self.hotspots) do
        if mx >= h.x1 and mx <= h.x2 and my >= h.y1 - 4 and my <= h.y2 + 4 then
            hitIdx = i
            break
        end
    end
    self.hoverIdx = hitIdx
end

--- 弹窗是否打开
---@return boolean
function KeywordText:isOpen()
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
end

--- 点击输入。返回 true 表示消费事件。
--- 规则：弹窗开着 → 任意点击先关弹窗；否则命中关键词 → 弹窗。
---@param dx number
---@param dy number
---@return boolean
function KeywordText:handleInput(dx, dy)
    if self.popup then
        self.popup = nil
        return true
    end
    local mx, my = self:_map(dx, dy)
    for _, h in ipairs(self.hotspots) do
        if mx >= h.x1 and mx <= h.x2 and my >= h.y1 - 4 and my <= h.y2 + 4 then
            local def = KW.get(h.name)
            if def then
                local anchorCX = (h.x1 + h.x2) * 0.5
                local anchorY  = h.y1
                if self._popupXform then
                    anchorCX, anchorY = self._popupXform(anchorCX, anchorY)
                end
                self.popup = {
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
    local tip = self.popup
    if not tip then return end

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, POP_NAME_FONT)
    ---@diagnostic disable-next-line: missing-parameter
    local nameW = nvgTextBounds(vg, 0, 0, tip.name)

    -- 说明文本折行（弹窗内不再嵌套关键词，纯文本渲染）
    nvgFontSize(vg, POP_DESC_FONT)
    local descWrapW = self.popupMaxW - POP_PAD_X * 2
    local descRows = {}
    for para in (tip.desc .. "\n"):gmatch("([^\n]*)\n") do
        local cur = ""
        if para == "" then
            descRows[#descRows + 1] = ""
        else
            for _, codepoint in utf8.codes(para) do
                local ch = utf8.char(codepoint)
                local testLine = cur .. ch
                if measure(vg, POP_DESC_FONT, testLine) > descWrapW and cur ~= "" then
                    descRows[#descRows + 1] = cur
                    cur = ch
                else
                    cur = testLine
                end
            end
            if cur ~= "" then descRows[#descRows + 1] = cur end
        end
    end

    local descH = #descRows * POP_LINE_H
    local tipW = math.min(math.max(nameW + POP_PAD_X * 2, self.popupMaxW), self.popupMaxW)
    local tipH = POP_PAD_TOP + POP_NAME_FONT + 8 + descH + POP_PAD_BOT

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
    nvgText(vg, tipLeft + POP_PAD_X, tipTopY + POP_PAD_TOP, tip.name, nil)

    nvgFontSize(vg, POP_DESC_FONT)
    nvgFillColor(vg, nvgRGBA(0xE8, 0xE0, 0xD4, 255))
    local textY = tipTopY + POP_PAD_TOP + POP_NAME_FONT + 8
    for i, line in ipairs(descRows) do
        nvgText(vg, tipLeft + POP_PAD_X, textY + (i - 1) * POP_LINE_H, line, nil)
    end
end

return KeywordText
