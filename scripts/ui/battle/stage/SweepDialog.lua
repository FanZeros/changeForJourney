-- 扫荡弹窗：固定入口小队，纯读展示重复战斗收益与扫荡后的等级。
-- 复用新 UI 组件、已有加减图标和 DesignWidgetSurface，宿主负责帧与模态输入。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local Rules = require("shared.sweep.SweepRewards")
local Service = require("rules.sweep.SweepService")
local SC = require("config.StageConfig")
local DC = require("config.DungeonConfig")
local ET = require("config.ExpTable")
local Store = require("core.PlayerStore")
local GameState = require("core.GameState")
local ResourceDefs = require("config.ResourceDefs")
local HeroAssets = require("config.HeroAssetUtil")
local HeroConfig = require("config.HeroConfig")
local Format = require("ui.battle.stage.StageSelectRewardPreview")
local BF = require("systems.ButtonFeedback")
local DrawUtil = require("core.DrawUtil")
local I18n = require("core.I18n")

local M = {}
local D = { x = 65, y = 570, w = 950, h = 1250, cx = 540, cy = 1195,
    confirmY = 1700, stepY = 1510, sliderX = 340, sliderW = 400,
    categoryY = 731, maxX = 857, maxY = 1435 }
local state = { open = false, openTime = 0, count = 1, teamIdx = 1, stageId = nil,
    sliderDragging = false, lastPreview = -1, preview = nil, reason = "", kind = "main",
    requestId = nil, failure = "" } ---@type table
-- 不重用页面身份；先登记再发送，兼容同步拒绝回执和关闭后重开的迟到回执。
local requestSequence = 0
local workProgress = nil ---@type ProgressBar?
local pendingTree = nil ---@type Panel?
local pendingLabel = nil ---@type Label?
local pendingProgress = nil ---@type ProgressBar?
local root = nil ---@type Panel?
local stageLabel = nil ---@type Label?
local quantity = nil ---@type Label?
local ticketLabel = nil ---@type Label?
local statusLabel = nil ---@type Label?
local confirmButton = nil ---@type Button?
local maxButton = nil ---@type Button?
local minusIcon = nil ---@type Panel?
local plusIcon = nil ---@type Panel?
local metrics = {} ---@type Label[]
local categoryButtons = {} ---@type Button[]
local playerView = {} ---@type table
local memberViews = {} ---@type table[]
local imageVg = nil ---@type any
local sweepImage = -1
local lastLanguage = ""
local categories = { "main", "gold_mine", "equipment_vault", "black_diamond" }
local names = { main = "主线", gold_mine = "金币副本", equipment_vault = "装备副本", black_diamond = "黑晶副本" }
local C = { bone = { 244, 237, 224, 255 }, dim = { 159, 151, 140, 255 }, gold = { 231, 192, 116, 255 },
    green = { 149, 190, 129, 255 }, track = { 52, 45, 35, 255 }, border = { 88, 69, 43, 255 } }

local function sweepWork()
    local bridge = require("runtime.LocalActionBridge")
    local work = bridge.getSweepState and bridge.getSweepState() or nil
    local pending = bridge.isSweepPending and bridge.isSweepPending() or false
    return state.requestId ~= nil or pending, work
end

local function workStatus(work)
    local phase = work and work.phase or "queued"
    -- 展示组装/归并排序可能多轮重置计数；只标明整理，避免误作全程百分比倒退。
    if phase == "presentation" or phase == "present" then return I18n.lookup("整理奖励"), 0, false end
    local caption = phase == "commit" and "正在结算" or (phase == "generate" and "生成奖励" or "处理中")
    local completed, total = tonumber(work and work.completed), tonumber(work and work.total)
    if completed and total and completed == completed and total == total
        and total > 0 and total < math.huge and completed >= 0 and completed < math.huge then
        local done = math.floor(math.min(completed, total))
        local all = math.floor(total)
        if all > 0 then return I18n.format("%s · %d / %d", I18n.lookup(caption), done, all), done / all, true end
    end
    return I18n.lookup(caption), 0, false
end

local function label(text, x, y, width, size, color)
    return UI.Label { text = I18n.lookup(text), position = "absolute", left = x, top = y,
        width = width, height = 50, fontSize = size or 30, fontColor = color or C.bone,
        fontFamily = "sans", fontWeight = "normal", verticalAlign = "middle", maxLines = 1 }
end

local function button(text, x, y, width, height)
    return UI.Button { text = I18n.lookup(text), position = "absolute", left = x, top = y,
        width = width, height = height, fontSize = 28, fontFamily = "sans", fontWeight = "normal",
        textColor = C.bone, backgroundColor = { 61, 48, 33, 255 },
        borderWidth = 1, borderColor = C.border, borderRadius = 8 }
end

local function progressBar(x, y, width, color)
    return UI.ProgressBar { position = "absolute", left = x, top = y, width = width, height = 14,
        value = 0, max = 1, showLabel = false, backgroundColor = C.track,
        fillColor = color, borderRadius = 7, pointerEvents = "none" }
end

local function destroyTree()
    if root then root:Destroy() end
    if pendingTree then pendingTree:Destroy() end
    pendingTree, pendingLabel, pendingProgress = nil, nil, nil
    root, stageLabel, quantity, ticketLabel, statusLabel, confirmButton = nil, nil, nil, nil, nil, nil
    maxButton, minusIcon, plusIcon, workProgress = nil, nil, nil, nil
    metrics, categoryButtons, playerView, memberViews = {}, {}, {}, {}
end

local function ensureTree()
    if root then return end
    Surface.init()
    root = UI.Panel { width = D.w, height = D.h, backgroundColor = { 25, 22, 19, 250 },
        borderWidth = 3, borderColor = { 135, 99, 49, 255 }, borderRadius = 22 }
    root:AddChild(label("扫荡", 45, 38, 780, 52, C.gold))
    root:AddChild(button("×", 835, 25, 70, 65))
    root:AddChild(UI.Panel { position = "absolute", left = 45, top = 111, width = 860, height = 2,
        backgroundColor = C.border })
    for i, kind in ipairs(categories) do
        local b = button(names[kind], 45 + (i - 1) * 217, 135, 205, 52)
        categoryButtons[i] = b
        root:AddChild(b)
    end
    stageLabel = label("尚无可扫荡关卡", 45, 202, 860, 34, C.gold)
    root:AddChild(stageLabel)
    local rewardsTitle = label("本次收益预估", 45, 255, 855, 28)
    rewardsTitle:SetStyle({ height = 34 })
    root:AddChild(rewardsTitle)
    local definitions = {
        { "金币", "gold" }, { "黑晶", "diamond" }, { "远征经验" },
        { "每名队员经验" }, { "随机装备 / 件" }, { "卷轴合计 / 张", "random_scroll" },
    }
    for i, def in ipairs(definitions) do
        local x, y = 45 + ((i - 1) % 3) * 289, 310 + math.floor((i - 1) / 3) * 100
        local card = UI.Panel { position = "absolute", left = x, top = y, width = 277, height = 90,
            backgroundColor = { 37, 31, 25, 255 }, borderRadius = 10, borderWidth = 1, borderColor = C.border }
        if def[2] then
            card:AddChild(UI.Panel { position = "absolute", left = 12, top = 9, width = 32, height = 32,
                backgroundImage = ResourceDefs.DEFS[def[2]].iconPath, backgroundFit = "contain" })
        end
        local caption = label(def[1], def[2] and 50 or 12, 0, def[2] and 211 or 250, 22, C.dim)
        caption:SetStyle({ height = 40 })
        card:AddChild(caption)
        local value = label("0", 12, 37, 250, 32, C.gold)
        metrics[i] = value
        card:AddChild(value)
        root:AddChild(card)
    end
    local expedition = UI.Panel { position = "absolute", left = 45, top = 520, width = 855, height = 108,
        backgroundColor = { 40, 33, 23, 255 }, borderWidth = 1, borderColor = C.border, borderRadius = 10 }
    expedition:AddChild(label("远征等级", 18, 2, 190, 28, C.gold))
    playerView.level = label("", 215, 2, 615, 30)
    playerView.bar = progressBar(18, 57, 819, C.gold)
    playerView.exp = label("", 18, 72, 819, 20, C.dim)
    playerView.exp:SetStyle({ height = 30, textAlign = "right" })
    expedition:AddChild(playerView.level)
    expedition:AddChild(playerView.bar)
    expedition:AddChild(playerView.exp)
    root:AddChild(expedition)
    local membersTitle = label("队员等级", 45, 635, 855, 28)
    membersTitle:SetStyle({ height = 32 })
    root:AddChild(membersTitle)
    for i = 1, ET.TEAM_MAX_SLOTS do
        local x, y = 45 + (i - 1) * 217, 671
        local card = UI.Panel { position = "absolute", left = x, top = y, width = 202, height = 158,
            backgroundColor = { 35, 30, 24, 255 }, borderWidth = 1, borderColor = C.border, borderRadius = 10 }
        local view = { card = card }
        view.icon = UI.Panel { position = "absolute", left = 77, top = 8, width = 48, height = 48,
            backgroundFit = "contain" }
        view.name = label("", 12, 58, 178, 22)
        view.name:SetStyle({ height = 28, textAlign = "center" })
        view.level = label("", 12, 88, 178, 16, C.green)
        view.level:SetStyle({ height = 28, textAlign = "center" })
        view.bar = progressBar(12, 119, 178, C.green)
        view.exp = label("", 12, 135, 178, 16, C.dim)
        view.exp:SetStyle({ height = 22, textAlign = "center" })
        card:AddChild(view.icon)
        card:AddChild(view.name)
        card:AddChild(view.level)
        card:AddChild(view.bar)
        card:AddChild(view.exp)
        memberViews[i] = view
        root:AddChild(card)
    end
    quantity = label("扫荡次数：1", 175, 842, 515, 36)
    root:AddChild(quantity)
    maxButton = button("最大", 715, 841, 155, 48)
    root:AddChild(maxButton)
    minusIcon = UI.Panel { position = "absolute", left = 175, top = 898, width = 84, height = 84,
        backgroundImage = "image/按钮/UI_AN_JIAN.png", backgroundFit = "contain" }
    plusIcon = UI.Panel { position = "absolute", left = 691, top = 898, width = 84, height = 84,
        backgroundImage = "image/按钮/UI_AN_JIA.png", backgroundFit = "contain" }
    root:AddChild(minusIcon)
    root:AddChild(plusIcon)
    root:AddChild(UI.Panel { position = "absolute", left = 175, top = 1003, width = 38, height = 38,
        backgroundImage = ResourceDefs.DEFS.sweep_ticket.iconPath, backgroundFit = "contain" })
    ticketLabel = label("", 222, 994, 655, 27, C.gold)
    root:AddChild(ticketLabel)
    confirmButton = button("扫荡", 270, 1080, 410, 100)
    confirmButton:SetStyle({ fontSize = 38, backgroundImage = "image/按钮/UI_AN_HUANG.png", backgroundFit = "fill" })
    root:AddChild(confirmButton)
    workProgress = progressBar(270, 1184, 410, C.gold)
    workProgress:SetStyle({ height = 8 })
    workProgress:SetVisible(false)
    root:AddChild(workProgress)
    statusLabel = label("", 45, 1196, 860, 22, C.dim)
    statusLabel:SetStyle({ height = 36 })
    root:AddChild(statusLabel)
end

local function getModules()
    return Store.Get("battle") or {}, Store.Get("dungeon") or {}, Store.Get("heroes") or {}
end

local function selectTarget(kind, preferred)
    local battle, dungeon = getModules()
    state.kind, state.stageId = kind, nil
    if kind == "main" then
        local source = {}
        for key, value in pairs(battle) do source[key] = value end
        source.teamStageIds = {}
        source.currentStageId = battle.maxStageId
        state.stageId = Rules.resolveDefaultStage(source, dungeon, state.teamIdx,
            preferred and not SC.isResourceStage(preferred) and preferred or battle.maxStageId)
    else
        if preferred and DC.decodeStageId(preferred) == kind and Rules.isCleared(preferred, battle, dungeon) then
            state.stageId = preferred
            state.lastPreview = -1
            return
        end
        local highest = DC.getHighestClearedFloor(dungeon[kind], kind)
        for floor = highest, 1, -1 do
            local id = DC.getStageId(kind, floor)
            if Rules.isCleared(id, battle, dungeon) then state.stageId = id; break end
        end
    end
    state.lastPreview = -1
end

local function refresh()
    local battle, dungeon, heroes = getModules()
    local preview, err = Service.Preview(heroes, battle, dungeon, Store.Get("equipment") or {},
        Store.Get("artifacts"), Store.Get("talents"), state.teamIdx, state.stageId, state.count, Store.Get("player"))
    if not state.stageId then preview, err = nil, "请先通关该分类的关卡" end
    state.preview, state.reason = preview, err or ""
    state.lastPreview = time.elapsedTime
end

local function ownedTickets()
    local value = tonumber(GameState.getSweepTicket()) or 0
    if value ~= value or value == math.huge or value == -math.huge then return 0 end
    return math.max(0, math.tointeger(math.floor(value)) or 0)
end

local function maxCount()
    if not state.stageId or not Rules.isCleared(state.stageId, Store.Get("battle"), Store.Get("dungeon")) then return 0 end
    return ownedTickets()
end

local function inside(x, y, cx, cy, w, h)
    return math.abs(x - cx) <= w * 0.5 and math.abs(y - cy) <= h * 0.5
end
local function designPoint(x, y)
    return D.cx + (x - D.cx) / 0.8, D.cy + (y - D.cy) / 0.8
end
local function sliderCount(x)
    local limit = maxCount()
    if limit < 1 then return end
    local fraction = math.max(0, math.min(1, (x - D.sliderX) / D.sliderW))
    state.count = math.floor(fraction * (limit - 1) + 0.5) + 1
    state.lastPreview = -1
end

local function updateProgress(view, progress)
    if not progress then
        view.level:SetText("—")
        view.exp:SetText("—")
        view.bar:SetValue(0)
        return
    end
    local before = progress.beforeLevel or progress.level
    view.level:SetText(string.format("Lv.%d → Lv.%d", before, progress.level))
    local maxExp = progress.maxExp or 0
    view.bar:SetValue(maxExp > 0 and math.min(1, math.max(0, (progress.exp or 0) / maxExp)) or (progress.capped and 1 or 0))
    view.exp:SetText(progress.capped and I18n.lookup("满级")
        or (Format.formatEstimate(progress.exp or 0) .. " / " .. Format.formatEstimate(maxExp)))
end

function M.init(vg)
    if imageVg == vg and sweepImage >= 0 then nvgDeleteImage(vg, sweepImage) end
    imageVg = vg
    sweepImage = nvgCreateImage(vg, "image/通用图标/UI_ICON_SD.png", 0) or -1
    destroyTree()
end

function M.open(teamIdx, preferredStageId)
    if state.open then return end
    local team = teamIdx or require("ui.character.panel.CharacterPanel").getActiveTeamIdx() or 1
    team = math.tointeger(tonumber(team) or 0)
    if not team or team < 1 or team > ET.TEAM_COUNT then return end
    state.open, state.openTime, state.count, state.teamIdx = true, time.elapsedTime, 1, team
    state.sliderDragging, state.requestId, state.failure = false, nil, ""
    local battle = Store.Get("battle") or {}
    local tasks = battle.teamStageIds or {}
    local current = preferredStageId or tasks[tostring(team)] or tasks[team] or (team == 1 and battle.currentStageId)
    local resource = current and DC.decodeStageId(current)
    selectTarget(resource or "main", tonumber(current))
    refresh()
    print(string.format("[SweepDialog] 固定队%d 分类=%s 关卡=%s 券=%d", team,
        state.kind, tostring(state.stageId), ownedTickets()))
end

function M.close()
    state.open, state.sliderDragging, state.requestId, state.failure = false, false, nil, ""
end
function M.isOpen() return state.open end

-- 只有本次页面发出的匹配回执才能结束等待或关闭页面；无id旧回执只展示奖励。
function M.onActionResult(data)
    if not state.open or state.requestId == nil or data.sweepRequestId ~= state.requestId then return false end
    state.requestId, state.sliderDragging = nil, false
    if data.success == true then
        M.close()
    else
        state.failure = data.reason or "扫荡失败，请重试"
        state.lastPreview = -1
    end
    return true
end

function M.drawButton(vg)
    if sweepImage < 0 then return end
    DrawUtil.drawImageCentered(vg, sweepImage, 971, 2115, 130, 144, 1)
    DrawUtil.drawTextStroke(vg, 971, 2175, "扫荡", 32, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
end

function M.draw(vg)
    if not state.open then return end
    local busy, work = sweepWork()
    local limit = maxCount()
    if not busy then
        local count = math.max(1, math.min(state.count, math.max(1, limit)))
        if state.count ~= count then state.count = count; state.lastPreview = -1 end
        if time.elapsedTime - state.lastPreview >= 0.5 or I18n.get() ~= lastLanguage then refresh() end
    end
    if I18n.get() ~= lastLanguage then destroyTree(); lastLanguage = I18n.get() end
    ensureTree()
    local preview = state.preview or {} ---@type table
    stageLabel:SetText(state.stageId and I18n.lookup(SC.getStageDisplayName(state.stageId)) or I18n.lookup("尚无可扫荡关卡"))
    local values = { preview.gold or 0, preview.diamond or 0, preview.playerExp or 0,
        preview.heroExp or 0, preview.equipCount or 0, preview.scrollCount or 0 }
    for i = 1, 6 do metrics[i]:SetText(Format.formatEstimate(values[i])) end
    quantity:SetText(I18n.format("扫荡次数：%d", state.count))
    ticketLabel:SetText(I18n.format("消耗 %d 张扫荡券（拥有 %d 张）", state.count, ownedTickets()))
    updateProgress(playerView, preview.playerProgress)
    local progress = preview.heroProgress or {}
    for i, view in ipairs(memberViews) do
        local member = progress[i]
        view.card:SetVisible(member ~= nil)
        if member then
            local config = HeroConfig.get(member.heroId)
            view.name:SetText(I18n.lookup(config and config.name or tostring(member.heroId)))
            if view.heroId ~= member.heroId then
                view.heroId = member.heroId
                view.icon:SetStyle({ backgroundImage = HeroAssets.getIconPath(member.heroId) })
            end
            updateProgress(view, member)
        end
    end
    for i, b in ipairs(categoryButtons) do
        local active = categories[i] == state.kind
        b:SetDisabled(busy)
        b:SetStyle({ borderColor = active and C.gold or C.border,
            backgroundColor = active and { 82, 62, 33, 255 } or { 40, 34, 27, 255 } })
    end
    minusIcon:SetStyle({ opacity = not busy and state.count > 1 and 1 or 0.4 })
    plusIcon:SetStyle({ opacity = not busy and state.count < limit and 1 or 0.4 })
    maxButton:SetDisabled(busy or limit <= 1 or state.count == limit)
    local canConfirm = not busy and limit >= state.count and state.preview ~= nil
    confirmButton:SetDisabled(not canConfirm)
    confirmButton:SetText(I18n.lookup(busy and "处理中" or (canConfirm and "扫荡"
        or (state.reason ~= "" and "无法扫荡" or "扫荡券不足"))))
    local status, fractionDone, hasProgress = workStatus(work)
    statusLabel:SetText(busy and status or I18n.lookup(state.failure ~= "" and state.failure or state.reason))
    workProgress:SetVisible(busy and hasProgress)
    workProgress:SetValue(busy and fractionDone or 0)
    local t = math.min(1, math.max(0, (time.elapsedTime - state.openTime) / 0.18))
    local scale = t * (1 + 0.08 * math.sin(t * math.pi))
    if scale <= 0.01 then return end
    nvgSave(vg)
    nvgTranslate(vg, D.cx, D.cy); nvgScale(vg, scale * 0.8, scale * 0.8)
    nvgTranslate(vg, D.x - D.cx, D.y - D.cy)
    local drawRoot = root --[[@as Panel]]
    Surface.draw(drawRoot, vg, D.w, D.h)
    local fraction = limit > 1 and (state.count - 1) / (limit - 1) or 0
    nvgBeginPath(vg); nvgRoundedRect(vg, 275, 928, 400, 24, 12)
    nvgFillColor(vg, nvgRGBA(75, 65, 50, 255)); nvgFill(vg)
    if fraction > 0 then
        nvgBeginPath(vg); nvgRoundedRect(vg, 275, 928, fraction * 400, 24, 12)
        nvgFillColor(vg, nvgRGBA(172, 131, 63, 255)); nvgFill(vg)
    end
    nvgBeginPath(vg); nvgCircle(vg, 275 + fraction * 400, 940, 18)
    nvgFillColor(vg, nvgRGBA(231, 192, 116, 255)); nvgFill(vg)
    nvgRestore(vg)
end

-- 专属等待帧也服务旧入口/外部关页；不打开页面、不认领旧任务、不读预估或玩家档。
function M.drawPending(vg)
    local busy, work = sweepWork()
    if not busy then return end
    if state.open then M.draw(vg); return end
    if I18n.get() ~= lastLanguage then destroyTree(); lastLanguage = I18n.get() end
    if not pendingTree then
        Surface.init()
        pendingTree = UI.Panel { width = 820, height = 220, backgroundColor = { 25, 22, 19, 250 },
            borderWidth = 3, borderColor = C.border, borderRadius = 18 }
        pendingLabel = label("处理中", 35, 32, 750, 30, C.gold)
        pendingTree:AddChild(pendingLabel)
        pendingProgress = progressBar(35, 112, 750, C.gold)
        pendingTree:AddChild(pendingProgress)
        pendingTree:AddChild(label("扫荡处理中，请稍候", 35, 145, 750, 24, C.dim))
    end
    local status, fraction, hasProgress = workStatus(work)
    pendingLabel:SetText(status)
    pendingProgress:SetValue(fraction)
    pendingProgress:SetVisible(hasProgress)
    nvgSave(vg)
    nvgTranslate(vg, D.cx - 328, D.cy - 88)
    nvgScale(vg, 0.8, 0.8)
    Surface.draw(pendingTree, vg, 820, 220)
    nvgRestore(vg)
end

function M.handleInput(x, y)
    if not state.open then return false end
    if sweepWork() then state.sliderDragging = false; return true end
    x, y = designPoint(x, y)
    if inside(x, y, D.x + 870, D.y + 57.5, 70, 65) then M.close(); return true end
    state.count = math.max(1, math.min(state.count, math.max(1, maxCount())))
    for i, kind in ipairs(categories) do
        if inside(x, y, D.x + 45 + (i - 1) * 217 + 102.5, D.categoryY, 205, 52) then
            selectTarget(kind); refresh(); return true
        end
    end
    if inside(x, y, D.maxX, D.maxY, 155, 48) then
        state.count = math.max(1, maxCount()); state.lastPreview = -1; return true
    end
    if inside(x, y, 282, D.stepY, 84, 84) then
        state.count = math.max(1, state.count - 1); state.lastPreview = -1; return true
    end
    if inside(x, y, 798, D.stepY, 84, 84) then
        state.count = math.max(1, math.min(maxCount(), state.count + 1)); state.lastPreview = -1; return true
    end
    if maxCount() > 1 and inside(x, y, 540, D.stepY, 436, 56) then sliderCount(x); return true end
    if inside(x, y, 540, D.confirmY, 410, 100) then
        refresh()
        if state.preview and maxCount() >= state.count then
            requestSequence = requestSequence + 1
            local requestId = "sweep-ui:" .. tostring(requestSequence)
            state.requestId, state.failure, state.sliderDragging = requestId, "", false
            BF.trigger("sweep_dlg_confirm")
            local ok, accepted = pcall(function()
                if not M.onSweep then return false end
                return M.onSweep(state.count, state.teamIdx, state.stageId, requestId)
            end)
            -- 业务失败回执可能同步返回；不能覆盖它的理由或误清回调里新开的页面。
            if state.open and state.requestId == requestId and (not ok or accepted == false) then
                state.requestId, state.failure = nil, "扫荡请求未受理，请重试"
                if not ok then print("[SweepDialog] 请求异常: " .. tostring(accepted)) end
            end
        else print("[SweepDialog] 拒绝扫荡: " .. state.reason) end
        return true
    end
    if not inside(x, y, D.cx, D.cy, D.w, D.h) then M.close() end
    return true
end

function M.handleDragBegin(x, y)
    if not state.open then return false end
    if sweepWork() then state.sliderDragging = false; return true end
    x, y = designPoint(x, y)
    if maxCount() > 1 and inside(x, y, 540, D.stepY, 436, 56) then
        state.sliderDragging = true; sliderCount(x)
    end
    return true
end
function M.handleDragMove(x, _y)
    if sweepWork() then state.sliderDragging = false; return state.open end
    if not state.sliderDragging then return false end
    local dx = D.cx + (x - D.cx) / 0.8
    sliderCount(dx); return true
end
function M.handleDragEnd()
    local dragging = state.sliderDragging
    state.sliderDragging = false
    return dragging
end
function M.handleButtonInput(x, y, teamIdx, stageId)
    if state.open then return false end
    if inside(x, y, 971, 2115, 130, 144) then M.open(teamIdx, stageId); return true end
    return false
end

---@type function|nil
M.onSweep = nil
return M
