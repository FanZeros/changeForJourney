-- ============================================================================
-- TaskPage - 城镇任务左栏页。模式 A：1080×2400，沿用 TownPageChrome。
-- 通关与队员保留原功绩页；远征使用等级升序的永久里程碑轨道。
-- ============================================================================

local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")
local TownPageChrome = require("ui.town.TownPageChrome")
local TaskConfig = require("config.TaskConfig")
local ClientDispatcher = require("runtime.ClientDispatcher")
local GameAction = require("runtime.GameAction")
local Protocol = require("shared.Protocol")
local ExpeditionProgress = require("config.ExpeditionProgress")
local ExpeditionTrackView = require("ui.story.task.ExpeditionTrackView")
local DesignWidgetSurface = require("ui.widget.DesignWidgetSurface")

local TaskPage = {}
local W, H = 1080, 2400
local OPEN_DUR, CLOSE_DUR = TownPageChrome.OPEN_DUR, TownPageChrome.CLOSE_DUR
local text = DrawUtil.drawTextStroke
local LIST = { x = 48, y = 470, w = 984, h = 1720, rowH = 200, gap = 36 }
local LEVEL_LIST = {
    x = 48, y = 826, w = 984, h = 1364, rowH = 248, gap = 28,
    summaryY = 470, summaryH = 328,
}
local TABS = {
    { key = "clear", name = "通关", cx = 270, w = 280 },
    { key = "level", name = "远征", cx = 540, w = 280 },
    { key = "hero", name = "队员", cx = 810, w = 280 },
}
local DIFF_MARK = { normal = "普通", hard = "困难", nightmare = "噩梦" }
local CLAIM_ALL = { cx = 860, cy = 300, w = 240, h = 64 }

local state = {
    open = false, closing = false, openTime = 0, closeTime = 0,
    tab = "clear", scrollY = 0, maxScrollY = 0,
    dragging = false, dragStartX = 0, dragStartY = 0, dragStartScroll = 0, dragMoved = false,
    dragScrollable = false, focusPending = false,
}
local iconCache = {}
local imgName = -1
local inited = false

local function rewardIcon(vg, path)
    if not path or path == "" then return -1 end
    local cached = iconCache[path]
    if cached then return cached end
    local handle = nvgCreateImage(vg, path, 0) or -1
    iconCache[path] = handle
    return handle
end

local function clampScroll()
    state.scrollY = math.max(0, math.min(state.maxScrollY, state.scrollY))
end

local function taskData()
    return ClientDispatcher.get("task")
end

-- 缺少玩家或台账时仅显示加载态，不使用默认等级推导可领奖励。
local function expeditionSnapshot()
    local player, data = ClientDispatcher.get("player"), taskData()
    local snapshot = ExpeditionProgress.build(player, data, ClientDispatcher.get("battle"))
    snapshot.loading = type(player) ~= "table" or type(data) ~= "table"
    if snapshot.loading then snapshot.claimableCount = 0 end
    return snapshot
end

-- 绘制、命中、拖拽与滚轮共用同一份设计坐标布局。
local function getListLayout()
    return state.tab == "level" and LEVEL_LIST or LIST
end

local function progressOf(task)
    local data = taskData()
    if not data then return 0, false end
    local cat = TaskConfig.getCategory(task.id)
    local current = 0
    local claimed = false
    if cat == "daily" then
        current = (data.dailyProg or {})[task.condKey] or 0
        claimed = (data.dailyClaimed or {})[task.id] == true
    elseif cat == "weekly" then
        current = (data.weeklyProg or {})[task.condKey] or 0
        claimed = (data.weeklyClaimed or {})[task.id] == true
    else
        current = (data.achProg or {})[task.condKey] or 0
        claimed = (data.achClaimed or {})[task.id] == true
    end
    return current, claimed
end

local function statusOf(task)
    local current, claimed = progressOf(task)
    if claimed then return TaskConfig.STATUS.CLAIMED, current end
    if current >= task.target then return TaskConfig.STATUS.CLAIMABLE, current end
    return TaskConfig.STATUS.LOCKED, current
end

local function sortRows(rows)
    local claimable, active, claimed = {}, {}, {}
    for _, task in ipairs(rows) do
        local status = statusOf(task)
        if status == TaskConfig.STATUS.CLAIMABLE then
            claimable[#claimable + 1] = task
        elseif status == TaskConfig.STATUS.CLAIMED then
            claimed[#claimed + 1] = task
        else
            active[#active + 1] = task
        end
    end
    local out = {}
    for _, task in ipairs(claimable) do out[#out + 1] = task end
    for _, task in ipairs(active) do out[#out + 1] = task end
    for _, task in ipairs(claimed) do out[#out + 1] = task end
    return out
end

local function listForKey(tabKey)
    local out = {}
    for _, task in ipairs(TaskConfig.ACHIEVEMENT) do
        if tabKey == "level" or tabKey == "hero" then
            if task.group == tabKey then
                out[#out + 1] = task
            end
        elseif task.difficulty == "normal" or task.difficulty == "hard" or task.difficulty == "nightmare" then
            out[#out + 1] = task
        end
    end
    return out
end

local function claimableForKey(tabKey)
    if tabKey == "level" then return expeditionSnapshot().claimableCount end
    local count = 0
    for _, task in ipairs(listForKey(tabKey)) do
        if statusOf(task) == TaskConfig.STATUS.CLAIMABLE then
            count = count + 1
        end
    end
    return count
end

local function listForTab()
    if state.tab == "level" then return expeditionSnapshot().rows end
    return sortRows(listForKey(state.tab))
end

local function tabScope()
    return state.tab == "clear" and "clear" or state.tab
end

local function claimableInTab()
    return claimableForKey(state.tab)
end

local function refreshScroll(count)
    local layout = getListLayout()
    local content = count * (layout.rowH + layout.gap)
    state.maxScrollY = math.max(0, content - layout.h)
    clampScroll()
end

-- 只在进入远征页或首份加载完成时定位，不因领取刷新重排、跳动历史。
local function focusExpedition(snapshot)
    if state.tab ~= "level" or not state.focusPending then return end
    refreshScroll(#snapshot.rows)
    if snapshot.loading then return end
    local layout = getListLayout()
    local index = math.max(1, math.min(#snapshot.rows, snapshot.focusIndex or 1))
    state.scrollY = (index - 1) * (layout.rowH + layout.gap)
    clampScroll()
    state.focusPending = false
end

local function selectTab(tabKey)
    if tabKey ~= "clear" and tabKey ~= "level" and tabKey ~= "hero" then return false end
    state.tab = tabKey
    state.scrollY = 0
    state.dragging, state.dragMoved, state.dragScrollable = false, false, false
    state.focusPending = tabKey == "level"
    if state.focusPending then focusExpedition(expeditionSnapshot()) else refreshScroll(#listForTab()) end
    return true
end

function TaskPage.init(vg)
    if inited then return end
    -- 必须在初始化阶段创建 UI 上下文，不能在渲染回调中更改渲染顺序。
    DesignWidgetSurface.init()
    inited = true
    imgName = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_MC.png", 0) or -1
    print("[TaskPage] init")
end

---@param tabKey string? 指定 clear、level 或 hero；省略时保留当前页签。
function TaskPage.open(tabKey)
    local ok, TaskService = pcall(require, "rules.task.TaskService")
    if ok and TaskService and TaskService.RefreshAchievements then
        TaskService.RefreshAchievements(1)
    end
    state.open = true
    state.closing = false
    state.openTime = time.elapsedTime
    state.closeTime = 0
    selectTab(tabKey or state.tab)
    print("[TaskPage] open " .. state.tab)
end

function TaskPage.openExpedition()
    TaskPage.open("level")
end

function TaskPage.getExpeditionClaimableCount()
    return claimableForKey("level")
end

function TaskPage.close()
    if not state.open or state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    print("[TaskPage] close")
end

function TaskPage.isOpen()
    return state.open
end

function TaskPage.getSeamAnim()
    return state.openTime, state.closeTime, OPEN_DUR, CLOSE_DUR
end

function TaskPage.hasClaimable()
    if TaskPage.getExpeditionClaimableCount() > 0 then return true end
    local lists = { TaskConfig.DAILY, TaskConfig.WEEKLY, TaskConfig.ACHIEVEMENT }
    for _, list in ipairs(lists) do
        for _, task in ipairs(list) do
            if task.group ~= "level" then
                local status = statusOf(task)
                if status == TaskConfig.STATUS.CLAIMABLE then return true end
            end
        end
    end
    return false
end

local function finishClose()
    state.open = false
    state.closing = false
    state.dragging = false
end

function TaskPage.update(_dt)
    if not state.open then return end
    if state.closing and time.elapsedTime - state.closeTime >= CLOSE_DUR then
        finishClose()
    end
end

local function drawRow(vg, task, y)
    local layout = getListLayout()
    local status, current = statusOf(task)
    local shown = math.min(current, task.target)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, layout.x, y - layout.rowH * 0.5, layout.w, layout.rowH, 12)
    local claimed = status == TaskConfig.STATUS.CLAIMED
    local nameR, nameG, nameB = 244, 232, 204
    local descR, descG, descB = 196, 176, 138
    if status == TaskConfig.STATUS.CLAIMABLE then
        nvgFillColor(vg, nvgRGBA(72, 52, 18, 235))
        nameR, nameG, nameB = 255, 226, 150
        descR, descG, descB = 226, 196, 120
    elseif claimed then
        nvgFillColor(vg, nvgRGBA(36, 48, 42, 210))
        nameR, nameG, nameB = 138, 156, 142
        descR, descG, descB = 112, 128, 116
    else
        nvgFillColor(vg, nvgRGBA(32, 28, 24, 230))
    end
    nvgFill(vg)
    local title = task.name or "远征委托"
    if task.difficulty and DIFF_MARK[task.difficulty] then
        title = "[" .. DIFF_MARK[task.difficulty] .. "] " .. title
    end
    text(vg, layout.x + 28, y - 58, title, 36,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, nameR, nameG, nameB, 2)
    text(vg, layout.x + 28, y - 8, task.desc or "", 28,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, descR, descG, descB, 2)
    text(vg, layout.x + 28, y + 46, "进度 " .. shown .. "/" .. task.target, 26,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 150, 176, 138, 2)
    local reward = task.reward
    if reward then
        local rcx = layout.x + layout.w - 300
        local rcy = y - 8
        DarkIcon.drawQualityBg(vg, reward.quality or 1, rcx, rcy, 124, 124, claimed and 0.55 or 1)
        local icon = rewardIcon(vg, reward.icon)
        if icon >= 0 then
            DrawUtil.drawImageCentered(vg, icon, rcx, rcy, 96, 96, claimed and 0.55 or 1)
        end
        text(vg, rcx + 55, rcy + 55, require("core.NumberUtil").format(reward.amount or 0), 26,
            NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM, 255, 244, 220, 2)
    end
    local label = "未完成"
    local r, g, b = 120, 116, 108
    if status == TaskConfig.STATUS.CLAIMABLE then
        label, r, g, b = "领取", 176, 132, 48
    elseif status == TaskConfig.STATUS.CLAIMED then
        label, r, g, b = "已领", 92, 118, 98
    end
    nvgBeginPath(vg)
    nvgRoundedRect(vg, layout.x + layout.w - 210, y - 36, 180, 72, 10)
    nvgFillColor(vg, nvgRGBA(r, g, b, 230))
    nvgFill(vg)
    -- 按钮文字：可领取=亮色，不可领=棕色
    local lr, lg, lb = 255, 244, 220
    if status ~= TaskConfig.STATUS.CLAIMABLE then
        lr, lg, lb = 0x8b, 0x95, 0xa5
    end
    text(vg, layout.x + layout.w - 120, y, label, 30, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, lr, lg, lb, 2)
end

function TaskPage.draw(vg)
    TaskPage.update(0)
    if not state.open or not vg then return end
    local progress = TownPageChrome.slideProgress(state, OPEN_DUR, CLOSE_DUR)
    local ox = DrawUtil.seamSlideX(-1, state.openTime, state.closeTime, OPEN_DUR, CLOSE_DUR, W)
    nvgSave(vg)
    nvgIntersectScissor(vg, 0, 0, W, H)
    nvgTranslate(vg, ox, 0)
    nvgGlobalAlpha(vg, progress)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(18, 16, 22, 255))
    nvgFill(vg)
    TownPageChrome.drawNamePlate(vg, imgName, "功绩", { scale = 0.72 })
    text(vg, 300, 300, "终焉功绩", 40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 216, 201, 163, 2)
    local claimCount = claimableInTab()
    nvgBeginPath(vg)
    nvgRoundedRect(vg, CLAIM_ALL.cx - CLAIM_ALL.w * 0.5, CLAIM_ALL.cy - CLAIM_ALL.h * 0.5,
        CLAIM_ALL.w, CLAIM_ALL.h, 10)
    nvgFillColor(vg, claimCount > 0 and nvgRGBA(176, 132, 48, 230) or nvgRGBA(62, 56, 48, 200))
    nvgFill(vg)
    local claimLabel = claimCount > 0 and ("一键领取 " .. claimCount) or "一键领取"
    -- 按钮文字：有可领=亮色，无可领=灰蓝色
    local caR, caG, caB = 255, 244, 220
    if claimCount <= 0 then caR, caG, caB = 0x8b, 0x95, 0xa5 end
    text(vg, CLAIM_ALL.cx, CLAIM_ALL.cy, claimLabel, 28,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, caR, caG, caB, 2)
    for _, tab in ipairs(TABS) do
        local on = state.tab == tab.key
        local half = (tab.w or 168) * 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tab.cx - half, 360, tab.w or 168, 72, 10)
        nvgFillColor(vg, on and nvgRGBA(176, 132, 48, 230) or nvgRGBA(42, 36, 28, 220))
        nvgFill(vg)
        text(vg, tab.cx, 396, tab.name, 30, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 245, 232, 200, 2)
        local badgeCount = claimableForKey(tab.key)
        if badgeCount > 0 then
            local badgeX = tab.cx + half - 8
            local badgeY = 368
            DarkIcon.draw(vg, "reddot", badgeX, badgeY, 42, 1)
            text(vg, badgeX, badgeY, badgeCount > 99 and "99+" or tostring(badgeCount), 24,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 244, 220, 2)
        end
    end
    local snapshot = state.tab == "level" and expeditionSnapshot() or nil
    local rows = snapshot and snapshot.rows or listForTab()
    local layout = getListLayout()
    refreshScroll(#rows)
    if snapshot then
        focusExpedition(snapshot)
        ExpeditionTrackView.draw(vg, snapshot, {
            x = layout.x, y = layout.y, w = layout.w, h = layout.h,
            rowH = layout.rowH, gap = layout.gap,
            summaryY = LEVEL_LIST.summaryY, summaryH = LEVEL_LIST.summaryH,
            scrollY = state.scrollY, loading = snapshot.loading,
        })
    else
        nvgSave(vg)
        nvgIntersectScissor(vg, layout.x, layout.y, layout.w, layout.h)
        if #rows == 0 then
            text(vg, 540, 900, "暂无功绩", 42, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 186, 168, 132, 2)
        else
            for i, task in ipairs(rows) do
                local y = layout.y + layout.rowH * 0.5 + (i - 1) * (layout.rowH + layout.gap) - state.scrollY
                if y + layout.rowH > layout.y and y - layout.rowH < layout.y + layout.h then
                    drawRow(vg, task, y)
                end
            end
        end
        nvgRestore(vg)
    end
    TownPageChrome.drawBack(vg)
    nvgRestore(vg)
end

local function rowAt(x, y)
    local layout = getListLayout()
    local snapshot = state.tab == "level" and expeditionSnapshot() or nil
    if snapshot then focusExpedition(snapshot) end
    if x < layout.x or x > layout.x + layout.w or y < layout.y or y > layout.y + layout.h then
        return nil
    end
    local rows = snapshot and snapshot.rows or listForTab()
    refreshScroll(#rows)
    local index = math.floor((y - layout.y + state.scrollY) / (layout.rowH + layout.gap)) + 1
    if index < 1 or index > #rows then return nil end
    local rowY = layout.y + layout.rowH * 0.5 + (index - 1) * (layout.rowH + layout.gap) - state.scrollY
    if math.abs(y - rowY) > layout.rowH * 0.5 then return nil end
    return rows[index], snapshot
end

function TaskPage.handleInput(dx, dy)
    if not state.open or state.closing then return false end
    -- 宿主即使把滑动释放误判为点按，也必须先消费，不能触发领取或换页。
    if state.dragMoved then
        state.dragMoved = false
        return true
    end
    if TownPageChrome.hitBack(dx, dy) then
        TaskPage.close()
        return true
    end
    for _, tab in ipairs(TABS) do
        if math.abs(dx - tab.cx) <= (tab.w or 168) * 0.5 and math.abs(dy - 396) <= 36 then
            selectTab(tab.key)
            print("[TaskPage] tab " .. tab.key)
            return true
        end
    end
    if math.abs(dx - CLAIM_ALL.cx) <= CLAIM_ALL.w * 0.5 and math.abs(dy - CLAIM_ALL.cy) <= CLAIM_ALL.h * 0.5 then
        if claimableInTab() > 0 then
            print("[TaskPage] claim all " .. tabScope())
            GameAction.sendAction(Protocol.ACTION_TYPES.CLAIM_ALL_TASKS, { scope = tabScope() })
        else
            print("[TaskPage] claim all empty")
        end
        return true
    end
    local task, snapshot = rowAt(dx, dy)
    if not task then return true end
    if snapshot then
        if not snapshot.loading and task.status == TaskConfig.STATUS.CLAIMABLE then
            print("[TaskPage] claim " .. task.taskId)
            GameAction.sendAction(Protocol.ACTION_TYPES.CLAIM_TASK, { taskId = task.taskId })
        end
    elseif statusOf(task) == TaskConfig.STATUS.CLAIMABLE then
        print("[TaskPage] claim " .. task.id)
        GameAction.sendAction(Protocol.ACTION_TYPES.CLAIM_TASK, { taskId = task.id })
    end
    return true
end

function TaskPage.handleDragBegin(dx, dy)
    if not state.open or state.closing then return false end
    if state.tab == "level" then focusExpedition(expeditionSnapshot()) end
    refreshScroll(#listForTab())
    local layout = getListLayout()
    state.dragging = true
    state.dragMoved = false
    state.dragScrollable = dx >= layout.x and dx <= layout.x + layout.w
        and dy >= layout.y and dy <= layout.y + layout.h
    state.dragStartX, state.dragStartY = dx, dy
    state.dragStartScroll = state.scrollY
    return true
end

function TaskPage.handleDragMove(dx, dy)
    if not state.open or state.closing or not state.dragging then return false end
    local delta = state.dragStartY - dy
    if math.abs(delta) > 8 or math.abs(dx - state.dragStartX) > 8 then state.dragMoved = true end
    if state.dragScrollable then
        state.scrollY = state.dragStartScroll + delta
        clampScroll()
    end
    return true
end

function TaskPage.handleDragEnd(_dx, _dy)
    if not state.open then return false end
    state.dragging = false
    state.dragScrollable = false
    return true
end

function TaskPage.handleScroll(wheel)
    if not state.open or state.closing then return false end
    if state.tab == "level" then focusExpedition(expeditionSnapshot()) end
    refreshScroll(#listForTab())
    state.scrollY = state.scrollY - wheel * 48
    clampScroll()
    return true
end

return TaskPage
