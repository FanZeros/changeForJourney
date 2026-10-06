-- ============================================================================
-- TowerBuffPick - 通天塔三选一强化面板
-- 全屏遮罩 + 标题 + 3个强化卡片供玩家点击选择
-- ============================================================================

local DrawUtil = require("core.DrawUtil")
local BF       = require("systems.ButtonFeedback")
local Protocol = require("shared.Protocol")
local KeywordText = require("ui.widget.KeywordText")

local Panel = {}

-- 关键词热区使用当前设计空间；draw/handleClick 共用布局及反变换。
local kwCards = {}
for i = 1, 3 do
    kwCards[i] = KeywordText.new({ textColor = { 0x5f, 0x37, 0x37 } })
end

-- ======================== 设计分辨率 ========================

local DESIGN_W = 1080
local DESIGN_H = 2400

-- ======================== 布局常量 ========================

-- 1. 全屏遮罩
local MASK_A = 128  -- 纯黑50%

-- 2. 标题 "通天塔"（左对齐 X=82）
local TITLE = { X = 82, Y = 410, FONT = 50, SW = 6 }

-- 3. 层数 "第X层"（斜体，与通天塔左对齐 X=82）
local FLOOR_TEXT = { X = 82, Y = 500, FONT = 80, SW = 6, SKEW = -12 }

-- 4. 提示 "选择一项强化"
local HINT = { X = 869, Y = 515, FONT = 50, SW = 6 }

-- 5. 强化卡片布局（以第一张卡片为基准）
local CARD = {
    CX = 540, FIRST_CY = 744,  -- 第一张卡片中心
    W = 998, H = 321,
    GAP = 47,                    -- 卡片间距
    -- 名称（相对卡片左上角偏移）
    NAME_X = 103, NAME_Y_OFF = 47,  -- 相对card top
    NAME_FONT = 50, NAME_SW = 5,
    NAME_STROKE_R = 0x3f, NAME_STROKE_G = 0x3f, NAME_STROKE_B = 0x3f,
    -- 品质文本
    QUALITY_X = 949, QUALITY_Y_OFF = 46,
    QUALITY_FONT = 50, QUALITY_SW = 5,
    -- 介绍文本段落区域（中心Y=782相对屏幕，转为相对card top的偏移）
    DESC_CX = 540, DESC_Y_OFF = 140,  -- 区域顶边相对card top
    DESC_W = 864, DESC_H = 117,
    DESC_FONT = 38,
    DESC_R = 0x5f, DESC_G = 0x37, DESC_B = 0x37,
}
CARD.STEP = CARD.H + CARD.GAP  -- 368

local function cardRect(index, landscape)
    if landscape then return 360 + (index - 1) * 600, 620, 550, 540 end
    return CARD.CX, CARD.FIRST_CY + (index - 1) * CARD.STEP, CARD.W, CARD.H
end

local function overlayFit(width, height)
    local fit = math.min(width / 1920, height / 1080)
    return fit, (width - 1920 * fit) * 0.5, (height - 1080 * fit) * 0.5
end

-- 品质显示映射（强化品质1/2/3 → 稀有/史诗/传说）
local QUALITY_DISPLAY = {
    [1] = { name = "稀有", r = 0x72, g = 0xf2, b = 0xf5 },  -- 蓝色
    [2] = { name = "史诗", r = 0xef, g = 0x79, b = 0xff },  -- 紫色
    [3] = { name = "传说", r = 0xff, g = 0xed, b = 0x00 },  -- 金色
}

-- ======================== 图片句柄 ========================

local imgCardBg = {}  -- UI_TTTSXY_1/2/3.png

-- ======================== 状态 ========================

local state = {
    open = false,
    floor = 1,
    choices = {},     -- { {id, quality, name, desc}, ... } 最多3个
    onPick = nil,     -- function(buffId, requestId) 请求前锁 Scene，不代表选择成功
    request = {},    -- Service 签发 runId/selectionId/floor/wave
    pending = false,
    pendingRequest = nil,
    pendingTime = 0,
    retryBuffId = nil, -- 结果未知（发送异常/超时）只能同卡重试
    onError = nil,
}

-- NanoVG 上下文
local vg_ = nil

-- ======================== sendAction 注入 ========================

---@type fun(action: string, params: table): boolean|nil
local sendAction_ = nil
local requestSerial = 0
local PENDING_TIMEOUT = 5.0

function Panel.setSendAction(fn)
    sendAction_ = fn
end

-- ======================== Public API ========================

local towerBuffInited_ = false

function Panel.init(vg)
    vg_ = vg
    if towerBuffInited_ then return end
    towerBuffInited_ = true
    for i = 1, 3 do
        imgCardBg[i] = nvgCreateImage(vg, "image/界面底板/副本秘境/UI_TTTSXY_" .. i .. ".png", 0)
    end
end

--- 打开面板，展示三选一
---@param floor number 当前层数
---@param choices table[] 强化选项列表 { {id, quality, name, desc}, ... }
---@param onPick function|nil 请求前回调 function(buffId, requestId)，false 阻止发送
---@param request table|nil 当次选择身份，由 Service 签发
---@param onError function|nil 发送失败/超时的匹配失败回执回调
function Panel.open(floor, choices, onPick, request, onError)
    if not towerBuffInited_ and vg_ then
        Panel.init(vg_)
    end
    state.open = true
    state.floor = floor or 1
    state.choices = choices or {}
    state.onPick = onPick
    state.onError = onError
    state.request = {}
    for key, value in pairs(request or {}) do state.request[key] = value end
    state.pending = false
    state.pendingRequest = nil
    state.pendingTime = 0
    state.retryBuffId = nil
    for i = 1, 3 do kwCards[i]:clear() end   -- 清上次打开的关键词状态
    print("[TowerBuffPick] open floor=" .. state.floor .. " choices=" .. #state.choices)
end

function Panel.close()
    state.open = false
    state.choices = {}
    state.onPick = nil
    state.onError = nil
    state.request = {}
    state.pending = false
    state.pendingRequest = nil
    state.pendingTime = 0
    state.retryBuffId = nil
    for i = 1, 3 do kwCards[i]:clear() end
end

-- 失败只释放对应请求，不能让旧失败/超时覆盖新请求。
function Panel.setPending(pending, requestId, retryOnly)
    if pending == true then return false end
    local request = state.pendingRequest
    if not request or request.requestId ~= requestId then return false end
    state.retryBuffId = (retryOnly == true or state.retryBuffId ~= nil) and request.buffId or nil
    state.pending = false
    state.pendingRequest = nil
    state.pendingTime = 0
    return true
end

local function failRequest(request, reason, retryOnly)
    if state.pendingRequest ~= request then return end
    request.success = false
    request.reason = reason
    request.retryOnly = retryOnly
    local errorFn = state.onError
    if errorFn then
        local ok, err = pcall(errorFn, request)
        if not ok then print("[TowerBuffPick] ERROR failure callback: " .. tostring(err)) end
    end
    -- 同步回执可能关闭/重开面板，必须按本地请求对象而不是只按 selectionId 检查。
    if state.pendingRequest == request then
        Panel.setPending(false, request.requestId, retryOnly)
    end
    print("[TowerBuffPick] request failed selection=" .. tostring(request.selectionId)
        .. " request=" .. tostring(request.requestId) .. " reason=" .. tostring(reason))
end

-- 交付结果未知时只能重试同卡；新 requestId 让迟到旧回执无法消费 retry。
function Panel.update(dt)
    if not state.open or not state.pending or not state.pendingRequest then return end
    state.pendingTime = state.pendingTime + dt
    if state.pendingTime >= PENDING_TIMEOUT then
        failRequest(state.pendingRequest, "强化回执超时，请重试所选强化", true)
    end
end

function Panel.isOpen()
    return state.open
end

-- ======================== 渲染 ========================

function Panel.draw(vg, width, height)
    if not state.open then return end
    local landscape = width ~= nil and height ~= nil
    nvgSave(vg)
    if landscape then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, width, height)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, MASK_A))
        nvgFill(vg)
        local fit, ox, oy = overlayFit(width, height)
        nvgTranslate(vg, ox, oy)
        nvgScale(vg, fit, fit)
    end

    -- 1. 旧调用保留竖版；横屏只拟合1920×1080内容，不缩整张竖版画布。
    if not landscape then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, MASK_A))
        nvgFill(vg)
    end

    -- 2. 标题
    DrawUtil.drawTextStroke(vg, landscape and 90 or TITLE.X, landscape and 100 or TITLE.Y, "通天塔",
        TITLE.FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, TITLE.SW,
        { strokeColor = { 0, 0, 0 } })

    -- 3. 层数 "第X层"（斜体，左对齐与通天塔对齐）
    nvgSave(vg)
    nvgTranslate(vg, landscape and 90 or FLOOR_TEXT.X, landscape and 205 or FLOOR_TEXT.Y)
    nvgSkewX(vg, FLOOR_TEXT.SKEW * math.pi / 180)
    DrawUtil.drawTextStroke(vg, 0, 0, "第" .. state.floor .. "层",
        FLOOR_TEXT.FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, FLOOR_TEXT.SW,
        { strokeColor = { 0, 0, 0 } })
    nvgRestore(vg)

    -- 4. 提示 "选择一项强化"
    DrawUtil.drawTextStroke(vg, landscape and 1430 or HINT.X, landscape and 205 or HINT.Y, "选择一项强化",
        HINT.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, HINT.SW,
        { strokeColor = { 0, 0, 0 } })

    -- 5. 强化卡片
    for i, choice in ipairs(state.choices) do
        local cardCX, cardCY, cardW, cardH = cardRect(i, landscape)
        local cardTop = cardCY - cardH * 0.5
        local cardLeft = cardCX - cardW * 0.5

        -- 按钮反馈与点击使用同一张卡的范围。
        local _bf = BF.begin(vg, "tower_buff_" .. i, cardCX, cardCY, cardW, cardH)

        -- 5.1) 卡片背景（按品质选图）
        local bgIdx = math.min(math.max(choice.quality or 1, 1), 3)
        local bgImg = imgCardBg[bgIdx]
        if bgImg and bgImg > 0 then
            DrawUtil.drawImageCentered(vg, bgImg, cardCX, cardCY, cardW, cardH, 1.0)
        end

        -- 5.2) 强化名称（左对齐）
        local nameY = cardTop + (landscape and 85 or CARD.NAME_Y_OFF)
        DrawUtil.drawTextStroke(vg, landscape and (cardLeft + 35) or CARD.NAME_X, nameY, choice.name or "",
            landscape and 40 or CARD.NAME_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            255, 255, 255, CARD.NAME_SW,
            { strokeColor = { CARD.NAME_STROKE_R, CARD.NAME_STROKE_G, CARD.NAME_STROKE_B } })

        -- 5.3) 品质文本（右侧）
        local qDisplay = QUALITY_DISPLAY[choice.quality] or QUALITY_DISPLAY[1]
        local qualityY = cardTop + (landscape and 145 or CARD.QUALITY_Y_OFF)
        DrawUtil.drawTextStroke(vg, landscape and (cardLeft + cardW - 35) or CARD.QUALITY_X, qualityY, qDisplay.name,
            landscape and 32 or CARD.QUALITY_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
            qDisplay.r, qDisplay.g, qDisplay.b, CARD.QUALITY_SW,
            { strokeColor = { CARD.NAME_STROKE_R, CARD.NAME_STROKE_G, CARD.NAME_STROKE_B } })

        -- 5.4) 介绍文本段落区域（关键词可点击）
        local descY = cardTop + (landscape and 220 or CARD.DESC_Y_OFF)
        local descLeft = landscape and (cardLeft + 35) or (CARD.DESC_CX - CARD.DESC_W * 0.5)
        local descW, descH = landscape and (cardW - 70) or CARD.DESC_W, landscape and 240 or CARD.DESC_H
        nvgSave(vg)
        nvgIntersectScissor(vg, descLeft, descY, descW, descH)
        kwCards[i]:draw(vg, choice.desc or "", descLeft, descY, descW, landscape and 34 or CARD.DESC_FONT)
        nvgRestore(vg)

        BF.finish(vg, _bf)
    end

    -- 6. 关键词解释气泡（最上层，盖住所有卡片）
    for i = 1, 3 do
        kwCards[i]:drawPopup(vg)
    end
    nvgRestore(vg)
end

-- ======================== 输入处理 ========================

function Panel.handleClick(dx, dy, width, height)
    if not state.open then return false end
    if state.pending then return true end
    local landscape = width ~= nil and height ~= nil
    if landscape then
        local fit, ox, oy = overlayFit(width, height)
        dx, dy = (dx - ox) / fit, (dy - oy) / fit
    end

    -- 关键词优先：任一卡片解释气泡开着 → 任意点击先关气泡（不选卡）
    for i = 1, 3 do
        if kwCards[i]:isOpen() then
            kwCards[i]:closePopup()
            return true
        end
    end
    -- 命中关键词 → 弹解释（必须先于整卡 hitTest，否则点 desc 关键词会误选卡）
    for i = 1, 3 do
        if kwCards[i]:handleInput(dx, dy) then
            return true
        end
    end

    -- 检测点击了哪张卡片
    for i, choice in ipairs(state.choices) do
        local cardCX, cardCY, cardW, cardH = cardRect(i, landscape)
        if DrawUtil.hitTest(dx, dy, cardCX, cardCY, cardW, cardH) then
            BF.trigger("tower_buff_" .. i)
            print("[TowerBuffPick] picked #" .. i .. " buffId=" .. (choice.id or "nil") .. " name=" .. (choice.name or ""))

            if not sendAction_ then
                print("[TowerBuffPick] no action sender, keep selection open")
                return true
            end
            if state.retryBuffId and choice.id ~= state.retryBuffId then
                print("[TowerBuffPick] receipt uncertain, retry only buffId=" .. state.retryBuffId)
                return true
            end
            -- 本地桥同步回包：发送前同时锁 Panel/Scene，绝不先做成功逻辑。
            local request = {}
            for key, value in pairs(state.request) do request[key] = value end
            request.buffId = choice.id
            requestSerial = requestSerial + 1
            request.requestId = requestSerial
            state.pending = true
            state.pendingRequest = request
            state.pendingTime = 0
            if state.onPick then
                local ok, accepted = pcall(state.onPick, choice.id, request.requestId)
                if not ok or accepted == false then
                    failRequest(request, "强化请求未发送，请重试", false)
                    print("[TowerBuffPick] request rejected: " .. tostring(accepted))
                    return true
                end
            end
            local sent, result = pcall(sendAction_, Protocol.ACTION_TYPES.TOWER_PICK_BUFF, request)
            if not sent or result == false then
                -- sender 抛错可能已提交，只有 false 明确未发送；不覆盖已同步消费的成功。
                failRequest(request, "强化请求发送失败，请重试", not sent)
                print("[TowerBuffPick] send failed: " .. tostring(result))
            end

            return true
        end
    end

    -- 点击空白区域不关闭（强制选择）
    return true
end

return Panel
