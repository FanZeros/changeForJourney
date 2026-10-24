-- 神器专属抽卡动画：只播放业务已结算的1/10张真实回执。
-- 时间轴复用 RecruitTimeline；品质来自 ArtifactDefs，绝不归一化/随机/扣费/保存/发奖。
-- 宿主负责1080×2400模式A缩放、NanoVG帧和输入路由，本模块没有全局事件或模态栈。
local Timeline = require("ui.tavern.RecruitTimeline")
local Motion = require("ui.tavern.RecruitMotion")
local ArtifactDefs = require("shared.artifact.ArtifactDefs")
local Presentation = require("ui.church.ArtifactDrawPresentation")
local RepeatDrawButton = require("ui.widget.RepeatDrawButton")
local GameSFX = require("systems.GameSFX")
local Anim = {}

---@class ArtifactDrawReceipt
---@field type string
---@field id string 实例ID，不是类型ID
---@field artifactId number|string 类型ID，保留回执原值
---@field name? string
---@field quality number
---@field value number
---@field valueRatio? number
---@field threatClearValue? number
---@field threatClearRatio? number
---@class ArtifactDrawCostPart
---@field type? string
---@field amount number
---@field icon? number
---@class ArtifactDrawCost
---@field parts ArtifactDrawCostPart[]
---@field enough? boolean
---@field freeText? string
---@class ArtifactDrawOptions
---@field getCost? fun(count: number): ArtifactDrawCost
---@field onContinue? fun(count: number): any false=未发送，可再次尝试；其他返回等待新回执
---@class ArtifactDrawState
---@field phase string
---@field rewards ArtifactDrawReceipt[]
---@field count number
---@field chestType string
---@field highestQ number
---@field introStart number
---@field cardStart number
---@field fadeStart number
---@field now number
---@field ready boolean
---@field waiting boolean
---@field settledCue boolean
---@field legendaryCue boolean
---@field fronts table<number, boolean>
---@field onClose? function
---@field getCost? function
---@field onContinue? function
---@field quote? ArtifactDrawCost
---@type ArtifactDrawState
local state = { phase = "idle", rewards = {}, count = 1, chestType = "normal", highestQ = 1,
    introStart = 0, cardStart = 0, fadeStart = 0, now = 0, ready = false, waiting = false,
    settledCue = false, legendaryCue = false, fronts = {} }
---@type any
local cachedVg = nil
---@type function[]
local closeQueue = {}
-- 不属于state：同步onContinue→start或onClose→start后仍挡同一输入事件的返回条。
local lastInputTime = -math.huge
local CUES = { "artifact_draw_charge", "artifact_draw_reveal", "artifact_draw_legendary", "artifact_draw_settle" }

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function contextValid(vg)
    local kind = type(vg)
    return vg ~= nil and (kind == "userdata" or kind == "table" or (kind == "number" and finite(vg) and vg >= 0))
end
local function engineTime()
    local t = time and time.elapsedTime
    return finite(t) and t or nil
end
local function clock()
    return math.max(state.now, engineTime() or state.now)
end
local function cue(method, key)
    local fn = GameSFX[method]
    if type(fn) == "function" then pcall(fn, key) end
end
local function stopCues()
    for _, key in ipairs(CUES) do cue("stopCue", key) end
end
local presentationErrorLogged = false
local function status(s)
    local ok = pcall(Presentation.setStatus, s.phase, s.ready, s.waiting, s.chestType,
        s.ready and s.phase == "cards" and s.onContinue ~= nil and not s.waiting)
    if not ok and not presentationErrorLogged then
        presentationErrorLogged = true
        print("[ArtifactDrawAnim] 字幕不可用，保留真实结果")
    end
end

-- 仅列出的合法标量复制进私有快照，不携带调用方表/未知字段引用，不改品质、数值或顺序。
local function snapshot(rewards, count)
    if type(rewards) ~= "table" then return nil end
    local actual = #rewards
    if actual ~= 1 and actual ~= 10 then return nil end
    if count ~= nil and (not finite(count) or count ~= actual) then return nil end
    -- 稀疏/超长数字键不是1或10张实际回执，不按Lua未定义的#结果静默截断。
    for key in pairs(rewards) do
        if type(key) == "number" and (not finite(key) or key % 1 ~= 0 or key < 1 or key > actual) then return nil end
    end
    local copied = {}
    for i = 1, actual do
        local r = rewards[i]
        if type(r) ~= "table" or r.type ~= "artifact" or type(r.id) ~= "string" or r.id == ""
            or not finite(r.quality) or r.quality % 1 ~= 0 or r.quality < 1 or r.quality > 6
            or not finite(r.value) or (r.name ~= nil and type(r.name) ~= "string") then return nil end
        local kind = type(r.artifactId)
        if kind ~= "number" and kind ~= "string" then return nil end
        local typeId = tonumber(r.artifactId)
        if not finite(typeId) or typeId % 1 ~= 0 or not ArtifactDefs.get(typeId) then return nil end
        for _, field in ipairs({ "valueRatio", "threatClearValue", "threatClearRatio" }) do
            if r[field] ~= nil and not finite(r[field]) then return nil end
        end
        -- 双属性回执必须有真实Y值，不能使用定义中点/比例反算来补假值。
        local def = ArtifactDefs.get(typeId)
        if def and def.threatClearRanges and r.threatClearValue == nil then return nil end
        copied[i] = { type = r.type, id = r.id, artifactId = r.artifactId, name = r.name,
            quality = r.quality, value = r.value, valueRatio = r.valueRatio,
            threatClearValue = r.threatClearValue, threatClearRatio = r.threatClearRatio }
    end
    return copied
end

local function copyQuote(value)
    if type(value) ~= "table" or (value.parts ~= nil and type(value.parts) ~= "table")
        or (value.enough ~= nil and type(value.enough) ~= "boolean")
        or (value.freeText ~= nil and type(value.freeText) ~= "string") then return nil end
    local parts = {}
    for i, part in ipairs(value.parts or {}) do
        if type(part) ~= "table" or not finite(part.amount) or part.amount < 0
            or (part.type ~= nil and type(part.type) ~= "string")
            or (part.icon ~= nil and (not finite(part.icon) or part.icon % 1 ~= 0)) then return nil end
        parts[i] = { type = part.type, amount = part.amount, icon = part.icon }
    end
    return { parts = parts, enough = value.enough, freeText = value.freeText }
end

local function refreshCost(s)
    if state ~= s or not s.getCost then return end
    local ok, result = pcall(s.getCost, s.count)
    -- 纯报价回调也可能同步start/close，旧返回不可覆盖新state或新UI报价。
    if state ~= s then return end
    s.quote = ok and copyQuote(result) or nil
    pcall(Presentation.setCost, s.quote, s.count)
end

local function settle(s)
    if s.settledCue then return end
    s.settledCue = true
    cue("stopCue", "artifact_draw_charge")
    cue("stopCue", "artifact_draw_reveal")
    if s.highestQ >= 4 and not s.legendaryCue then
        s.legendaryCue = true
        cue("play", "artifact_draw_legendary")
    end
    cue("play", "artifact_draw_settle")
end

-- 仅Update/输入边界触发声音，每次update合并所有新翻开的牌，最多一声reveal。
local function advance(s, now)
    if state ~= s or s.phase == "idle" or s.phase == "fadeOut" then return end
    s.now = math.max(s.now, now)
    if s.phase == "intro" and now >= s.cardStart then
        s.phase = "cards"
        cue("stopCue", "artifact_draw_charge")
    end
    if s.phase ~= "cards" then return end
    local elapsed = now - s.cardStart
    local newlyHighest = 0
    for i, item in ipairs(s.rewards) do
        local pose = Timeline.card(elapsed, i)
        if pose.front and not s.fronts[i] then
            s.fronts[i] = true
            newlyHighest = math.max(newlyHighest, item.quality)
        end
    end
    -- 比较绝对计划终点，避免(终点-cardStart)的浮点相消令边界晚一帧。
    local ready = now >= s.cardStart + Timeline.cardSpan(#s.rewards)
    if ready then
        s.ready = true
        -- 暂停/大dt越过整批只播settle+最高品质，不在一帧补播十声翻牌。
        settle(s)
    elseif newlyHighest > 0 then
        cue("stopCue", "artifact_draw_reveal")
        if newlyHighest >= 4 and not s.legendaryCue then
            s.legendaryCue = true
            cue("play", "artifact_draw_legendary")
        else
            cue("play", "artifact_draw_reveal")
        end
    end
    status(s)
end

local function revealAll(s, now)
    s.now, s.phase, s.ready = now, "cards", true
    s.cardStart = now - Timeline.cardSpan(#s.rewards)
    for i = 1, #s.rewards do s.fronts[i] = true end
    lastInputTime = now
    -- 跳过停旧蓄能/翻面，只一次settle与尚未播过的最高品质cue。
    settle(s)
    refreshCost(s)
    if state == s then status(s) end
    print("[ArtifactDrawAnim] 揭晓全部 count=" .. tostring(#s.rewards))
end

local function fade(s, now)
    s.now, s.phase, s.fadeStart = now, "fadeOut", now
    lastInputTime = now
    stopCues()
    status(s)
end

--- 初始化预热，不创建NanoVG帧；重复init同VG保缓存。
---@param vg any
---@return boolean
function Anim.init(vg)
    if not contextValid(vg) then return false end
    local ok, initialized = pcall(Presentation.init, vg)
    if not ok or initialized ~= true then
        pcall(Presentation.destroy)
        cachedVg = nil
        print("[ArtifactDrawAnim] 初始化表现不可用")
        return false
    end
    cachedVg = vg
    for _, key in ipairs(CUES) do cue("preload", key) end
    return true
end

---@param rewards ArtifactDrawReceipt[]
---@param onClose? function
---@param count? number 省略时按真实回执数，显式值必须等于实际1或10
---@param chestType? string normal/advanced
---@param opts? ArtifactDrawOptions
---@return boolean
function Anim.start(rewards, onClose, count, chestType, opts)
    if (onClose ~= nil and type(onClose) ~= "function")
        or (opts ~= nil and type(opts) ~= "table") then return false end
    opts = opts or {}
    if (opts.getCost ~= nil and type(opts.getCost) ~= "function")
        or (opts.onContinue ~= nil and type(opts.onContinue) ~= "function") then return false end
    chestType = chestType or "normal"
    if chestType ~= "normal" and chestType ~= "advanced" then return false end
    local copied = snapshot(rewards, count)
    if not copied then
        print("[ArtifactDrawAnim] 拒绝非法/不完整神器回执")
        return false
    end
    if not cachedVg then return false end
    local now = engineTime()
    if not now then return false end
    local highest = 1
    for _, item in ipairs(copied) do highest = math.max(highest, item.quality) end
    local fresh = { phase = "intro", rewards = copied, count = #copied, chestType = chestType,
        highestQ = highest, introStart = now, cardStart = now + Timeline.INTRO_DURATION,
        fadeStart = 0, now = now, ready = false, waiting = false, fronts = {},
        settledCue = false, legendaryCue = false, onClose = onClose,
        getCost = opts.getCost, onContinue = opts.onContinue }
    -- 控件/资源准备先完成再发布playing；准备异常不得让fallback弹窗叠半启动overlay。
    local previous = state
    local ok, prepared = pcall(Presentation.prepare, copied, #copied, chestType)
    if not ok or prepared ~= true then
        stopCues()
        previous.phase, previous.rewards = "idle", {}
        previous.onContinue, previous.getCost = nil, nil
        pcall(Presentation.clear)
        print("[ArtifactDrawAnim] 准备失败，由宿主显示已发奖回执")
        return false
    end
    stopCues()
    -- 覆盖仅排队旧close，最终关闭一次取走整批；不丢旧回执刷新回调。
    if previous.onClose then closeQueue[#closeQueue + 1] = previous.onClose; previous.onClose = nil end
    state = fresh
    presentationErrorLogged = false
    status(fresh)
    refreshCost(fresh)
    if state ~= fresh then return true end
    cue("play", "artifact_draw_charge")
    print("[ArtifactDrawAnim] 开匣 count=" .. tostring(#copied) .. " chest=" .. chestType .. " q=" .. tostring(highest))
    return true
end

---@return boolean
function Anim.isPlaying() return state.phase ~= "idle" end

---@param dt number
function Anim.update(dt)
    if not finite(dt) or dt < 0 or state.phase == "idle" then return end
    local s = state
    -- 使用绝对计划时间；引擎时钟不可用时才以finite dt推进，不因暂停返回重排错峰。
    local source = engineTime()
    local now = source and math.max(s.now, source) or (s.now + dt)
    s.now = now
    if s.phase == "fadeOut" then
        if now - s.fadeStart >= Timeline.FADE_DURATION then Anim.close() end
        return
    end
    advance(s, now)
    refreshCost(s)
    if state == s then pcall(Presentation.refreshLanguage) end
end

---@param dx number 宿主设计坐标
---@param dy number 宿主设计坐标
---@return boolean 是否消费
function Anim.handleInput(dx, dy)
    if not finite(dx) or not finite(dy) or state.phase == "idle" then return false end
    local s, now = state, clock()
    if lastInputTime == now then return true end
    if s.phase == "fadeOut" then return true end
    if not s.ready then
        if now < s.cardStart + Timeline.cardSpan(#s.rewards) then
            -- 包括继续区域：第一次只揭晓，不根据点击位置关闭/重抽。
            revealAll(s, now)
            return true
        end
        -- 全计划已结束但宿主尚未Update：按真实时间落定，不额外要求跳过。
        advance(s, now)
    end
    if s.onContinue and RepeatDrawButton.hit(dx, dy, Presentation.REPEAT_CX, Presentation.REPEAT_CY,
        Presentation.REPEAT_W, Presentation.REPEAT_H) then
        lastInputTime = now
        if s.waiting then return true end
        s.waiting = true
        status(s)
        local fn = s.onContinue
        local ok, sent = pcall(fn, s.count)
        -- 回执可以在回调中同步start；旧回调返回不覆写新state/输入屏障/报价。
        if state ~= s then return true end
        if not ok or sent == false then
            s.waiting = false
            status(s)
            if not ok then print("[ArtifactDrawAnim] 继续请求异常，保留旧结果") end
        end
        return true
    end
    fade(s, now)
    return true
end

--- 中缝返回与同事件路由共用屏障。尚未ready时只揭晓；ready才淡退。
---@return boolean 是否消费
function Anim.dismiss()
    if state.phase == "idle" or state.phase == "fadeOut" then return false end
    local s, now = state, clock()
    if lastInputTime == now then return false end
    if not s.ready and now < s.cardStart + Timeline.cardSpan(#s.rewards) then
        revealAll(s, now)
    else
        if not s.ready then advance(s, now) end
        fade(s, now)
    end
    return true
end

-- 关闭先切idle并取走旧回调，再隔离调用；回调同步start后的新结果保持完整。
function Anim.close()
    local s = state
    local callbacks = closeQueue
    closeQueue = {}
    if s.onClose then callbacks[#callbacks + 1] = s.onClose end
    s.onClose, s.onContinue, s.getCost = nil, nil, nil
    stopCues()
    state = { phase = "idle", rewards = {}, count = 1, chestType = "normal", highestQ = 1,
        introStart = 0, cardStart = 0, fadeStart = 0, now = s.now, ready = false, waiting = false,
        settledCue = false, legendaryCue = false, fronts = {} }
    pcall(Presentation.clear)
    -- 先取走整批callback，重入close不能重复消费；一个callback失败不吞其余。
    for _, callback in ipairs(callbacks) do
        local ok = pcall(callback)
        if not ok then print("[ArtifactDrawAnim] 关闭回调异常") end
    end
    if s.phase ~= "idle" then print("[ArtifactDrawAnim] 关闭") end
end

--- Stop清理，不触发onClose/剧情/宿主刷新，不清任何全局缓存。
function Anim.destroy()
    stopCues()
    state.onClose, state.onContinue, state.getCost = nil, nil, nil
    closeQueue = {}
    state = { phase = "idle", rewards = {}, count = 1, chestType = "normal", highestQ = 1,
        introStart = 0, cardStart = 0, fadeStart = 0, now = 0, ready = false, waiting = false,
        settledCue = false, legendaryCue = false, fronts = {} }
    cachedVg, lastInputTime = nil, -math.huge
    Presentation.destroy()
end

local function cardPosition(count, index)
    if count == 1 then return 540, 1110, 740, 1260 end
    local col = (index - 1) % 5
    local row = math.floor((index - 1) / 5)
    return 128 + col * 206, 760 + row * 640, 188, 520
end

--- 纯视觉采样，不推进state，不调getCost/音效/业务。每层Save/Restore严格配对。
---@param vg any
function Anim.draw(vg)
    local s = state
    if s.phase == "idle" or not contextValid(vg) or vg ~= cachedVg then return end
    local now = clock()
    local alpha = s.phase == "fadeOut" and math.max(0, 1 - (now - s.fadeStart) / Timeline.FADE_DURATION) or 1
    if alpha <= 0.001 then return end
    nvgSave(vg); nvgGlobalAlpha(vg, alpha)
    Presentation.drawBackground(vg, s.chestType)
    if s.phase == "intro" then
        Presentation.drawIntro(vg, now - s.introStart, s.chestType, s.highestQ)
    else
        local elapsed = now - s.cardStart
        for i, item in ipairs(s.rewards) do
            local pose = Timeline.card(elapsed, i)
            if pose.visible then
                local cx, cy, width, height = cardPosition(s.count, i)
                local y = cy + pose.offsetY
                local localElapsed = elapsed - (i - 1) * Timeline.CARD_DELAY
                if pose.front then Presentation.drawCardGlow(vg, cx, y, width, height, item.quality, pose.glow, localElapsed) end
                nvgSave(vg); nvgTranslate(vg, cx, y)
                nvgScale(vg, pose.scaleX * pose.scale, pose.scale); nvgTranslate(vg, -cx, -y)
                local faceAlpha = alpha * pose.alpha
                nvgGlobalAlpha(vg, faceAlpha)
                if pose.front then
                    Presentation.drawFront(vg, item, cx, y, width, height)
                    Presentation.drawCardText(vg, i, cx, y, width, height, faceAlpha)
                else
                    Presentation.drawBack(vg, cx, y, width, height, 1)
                    Motion.drawBackEdge(vg, cx, y, width, height, localElapsed / Timeline.CARD_DURATION, 1)
                end
                nvgRestore(vg)
            end
        end
    end
    nvgRestore(vg)
    Presentation.drawLabels(vg, alpha)
end

return Anim
