-- ============================================================================
-- TowerBuffPick - 通天塔三选一强化面板
-- 全屏遮罩 + 标题 + 3个强化卡片供玩家点击选择
-- ============================================================================

local DrawUtil = require("core.DrawUtil")
local BF       = require("systems.ButtonFeedback")
local Protocol = require("shared.Protocol")
local KeywordText = require("ui.widget.KeywordText")
local ChoiceView = require("ui.tower.TowerChoiceView")
local OathEffect = require("ui.tower.TowerOathEffect")

local Panel = {}

-- 关键词热区使用当前设计空间；draw/handleClick 共用布局及反变换。
local kwCards = {}
for i = 1, 3 do
    kwCards[i] = KeywordText.new({ textColor = { 231, 219, 195 } })
end

-- 绘制与命中共用固定设计区，装饰动画只作用于图形，不移动可点击卡片。
local cardRect = ChoiceView.cardRect
local overlayFit = ChoiceView.fit

-- ======================== 状态 ========================

local state = {
    open = false,
    visible = false,
    openedAt = 0,
    version = 0,
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
---@type NVGContextWrapper?
local vg_ = nil
---@type table[]
local effectTokens = {}

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
    OathEffect.preload(vg)
end

local function releaseEffects()
    for _, token in ipairs(effectTokens) do OathEffect.release(token) end
    effectTokens = {}
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
    releaseEffects()
    for i = 1, 3 do effectTokens[i] = {} end
    state.open, state.visible = true, true
    state.openedAt = time.elapsedTime or 0
    state.version = state.version + 1
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
    state.open, state.visible = false, false
    state.version = state.version + 1
    releaseEffects()
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

-- 取消仅收起弹窗，保留本次待选身份；右侧「继续择契」返回同一组卡。
function Panel.isVisible()
    return state.open and state.visible
end

function Panel.hide()
    if not state.open or state.pending then return false end
    state.visible = false
    state.version = state.version + 1
    for i = 1, 3 do kwCards[i]:clear() end
    return true
end

function Panel.show()
    if not state.open then return false end
    state.visible = true
    state.version = state.version + 1
    return true
end

function Panel.getPresentationKey()
    return tostring(state.version) .. ":" .. tostring(state.pending)
end

function Panel.destroy()
    Panel.close()
    ChoiceView.destroyWidgets()
    OathEffect.destroy()
    towerBuffInited_, vg_ = false, nil
end

-- ======================== 渲染 ========================

function Panel.draw(vg, width, height)
    if not Panel.isVisible() then return end
    local landscape = width ~= nil and height ~= nil
    local fit, ox, oy = overlayFit(width, height)
    if fit <= 0 then return end
    local ok, caught
    nvgSave(vg)
    ok, caught = xpcall(function()
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, width or 1080, height or 2400)
        nvgFillColor(vg, nvgRGBA(7, 8, 10, 218))
        nvgFill(vg)
        if landscape then
            nvgTranslate(vg, ox, oy)
            nvgScale(vg, fit, fit)
        end
        ChoiceView.drawHeader(vg, state, landscape)
        local elapsed = math.max(0, (time.elapsedTime or 0) - state.openedAt)
        for i, choice in ipairs(state.choices) do
            if i <= 3 then
                ChoiceView.drawCard(vg, i, choice, state, landscape, kwCards[i], elapsed, effectTokens[i])
            end
        end
        ChoiceView.drawFooter(vg, state, landscape)
        for i = 1, 3 do ChoiceView.drawKeywordPopup(vg, kwCards[i], i, landscape) end
    end, debug.traceback)
    nvgRestore(vg)
    if not ok then error(caught, 0) end
end

-- ======================== 输入处理 ========================

function Panel.handleClick(dx, dy, width, height)
    if not Panel.isVisible() then return false end
    if state.pending then return true end
    local landscape = width ~= nil and height ~= nil
    if landscape then
        local fit, ox, oy = overlayFit(width, height)
        if fit <= 0 then return true end
        dx, dy = (dx - ox) / fit, (dy - oy) / fit
    end

    -- 关键词优先：任一卡片解释气泡开着 → 任意点击先关气泡（不选卡）
    for i = 1, 3 do
        if kwCards[i]:isOpen() then
            kwCards[i]:closePopup()
            return true
        end
    end
    local cancelX, cancelY, cancelW, cancelH = ChoiceView.cancelRect(landscape)
    if DrawUtil.hitTest(dx, dy, cancelX, cancelY, cancelW, cancelH) then
        Panel.hide()
        return true
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
