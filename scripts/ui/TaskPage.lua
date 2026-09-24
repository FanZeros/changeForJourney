-- ============================================================================
-- TaskPage - 城镇任务左栏页。模式 A：1080×2400，沿用 TownPageChrome。
-- 只展示关卡推进、签到、在线时间。
-- ============================================================================

local DrawUtil = require("core.DrawUtil")
local TownPageChrome = require("ui.TownPageChrome")
local TaskConfig = require("config.TaskConfig")
local ClientDispatcher = require("runtime.ClientDispatcher")
local GameAction = require("runtime.GameAction")
local Protocol = require("shared.Protocol")

local TaskPage = {}
local W, H = 1080, 2400
local OPEN_DUR, CLOSE_DUR = TownPageChrome.OPEN_DUR, TownPageChrome.CLOSE_DUR
local text = DrawUtil.drawTextStroke
local LIST = { x = 48, y = 430, w = 984, h = 1760, rowH = 210, gap = 16 }
local TABS = {
    { key = "normal", name = "普通", cx = 118, w = 168 },
    { key = "hard", name = "困难", cx = 302, w = 168 },
    { key = "nightmare", name = "噩梦", cx = 486, w = 168 },
    { key = "level", name = "远征", cx = 670, w = 168 },
    { key = "hero", name = "队员", cx = 854, w = 168 },
}

local state = {
    open = false, closing = false, openTime = 0, closeTime = 0,
    tab = "normal", scrollY = 0, maxScrollY = 0,
    dragging = false, dragStartY = 0, dragStartScroll = 0, dragMoved = false,
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

local function listForTab()
    local out = {}
    for _, task in ipairs(TaskConfig.ACHIEVEMENT) do
        if state.tab == "level" or state.tab == "hero" then
            if task.group == state.tab then
                out[#out + 1] = task
            end
        elseif task.difficulty == state.tab then
            out[#out + 1] = task
        end
    end
    return sortRows(out)
end

local function refreshScroll(count)
    local content = count * (LIST.rowH + LIST.gap)
    state.maxScrollY = math.max(0, content - LIST.h)
    clampScroll()
end

function TaskPage.init(vg)
    if inited then return end
    inited = true
    imgName = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_MC.png", 0) or -1
    print("[TaskPage] init")
end

function TaskPage.open()
    local ok, TaskService = pcall(require, "rules.task.TaskService")
    if ok and TaskService and TaskService.RefreshAchievements then
        TaskService.RefreshAchievements(1)
    end
    state.open = true
    state.closing = false
    state.openTime = time.elapsedTime
    state.closeTime = 0
    state.scrollY = 0
    print("[TaskPage] open")
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
    local lists = { TaskConfig.DAILY, TaskConfig.WEEKLY, TaskConfig.ACHIEVEMENT }
    for _, list in ipairs(lists) do
        for _, task in ipairs(list) do
            local status = statusOf(task)
            if status == TaskConfig.STATUS.CLAIMABLE then return true end
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
    local status, current = statusOf(task)
    local shown = math.min(current, task.target)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, LIST.x, y - LIST.rowH * 0.5, LIST.w, LIST.rowH, 12)
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
    text(vg, LIST.x + 28, y - 58, task.name or "远征委托", 36,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, nameR, nameG, nameB, 2)
    text(vg, LIST.x + 28, y - 8, task.desc or "", 28,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, descR, descG, descB, 2)
    text(vg, LIST.x + 28, y + 46, "进度 " .. shown .. "/" .. task.target, 26,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 150, 176, 138, 2)
    local reward = task.reward
    if reward then
        local icon = rewardIcon(vg, reward.icon)
        if icon >= 0 then
            DrawUtil.drawImageCentered(vg, icon, LIST.x + LIST.w - 300, y - 16, 64, 64, 1)
        end
        text(vg, LIST.x + LIST.w - 300, y + 42, "×" .. tostring(reward.amount or 0), 22,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 232, 210, 150, 2)
    end
    local label = "未完成"
    local r, g, b = 120, 116, 108
    if status == TaskConfig.STATUS.CLAIMABLE then
        label, r, g, b = "领取", 176, 132, 48
    elseif status == TaskConfig.STATUS.CLAIMED then
        label, r, g, b = "已领", 92, 118, 98
    end
    nvgBeginPath(vg)
    nvgRoundedRect(vg, LIST.x + LIST.w - 210, y - 36, 180, 72, 10)
    nvgFillColor(vg, nvgRGBA(r, g, b, 230))
    nvgFill(vg)
    text(vg, LIST.x + LIST.w - 120, y, label, 30, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 244, 220, 2)
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
    TownPageChrome.drawNamePlate(vg, imgName, "功绩")
    text(vg, 540, 250, "终焉功绩", 40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 216, 201, 163, 2)
    for _, tab in ipairs(TABS) do
        local on = state.tab == tab.key
        local half = (tab.w or 168) * 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tab.cx - half, 304, tab.w or 168, 72, 10)
        nvgFillColor(vg, on and nvgRGBA(176, 132, 48, 230) or nvgRGBA(42, 36, 28, 220))
        nvgFill(vg)
        text(vg, tab.cx, 340, tab.name, 30, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 245, 232, 200, 2)
    end
    local rows = listForTab()
    refreshScroll(#rows)
    nvgSave(vg)
    nvgIntersectScissor(vg, LIST.x, LIST.y, LIST.w, LIST.h)
    if #rows == 0 then
        text(vg, 540, 900, "暂无功绩", 42, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 186, 168, 132, 2)
    else
        for i, task in ipairs(rows) do
            local y = LIST.y + LIST.rowH * 0.5 + (i - 1) * (LIST.rowH + LIST.gap) - state.scrollY
            if y + LIST.rowH > LIST.y and y - LIST.rowH < LIST.y + LIST.h then
                drawRow(vg, task, y)
            end
        end
    end
    nvgRestore(vg)
    TownPageChrome.drawBack(vg)
    nvgRestore(vg)
end

local function rowAt(x, y)
    if x < LIST.x or x > LIST.x + LIST.w or y < LIST.y or y > LIST.y + LIST.h then
        return nil
    end
    local rows = listForTab()
    local index = math.floor((y - LIST.y + state.scrollY) / (LIST.rowH + LIST.gap)) + 1
    if index < 1 or index > #rows then return nil end
    local rowY = LIST.y + LIST.rowH * 0.5 + (index - 1) * (LIST.rowH + LIST.gap) - state.scrollY
    if math.abs(y - rowY) > LIST.rowH * 0.5 then return nil end
    return rows[index]
end

function TaskPage.handleInput(dx, dy)
    if not state.open or state.closing then return false end
    if TownPageChrome.hitBack(dx, dy) then
        TaskPage.close()
        return true
    end
    for _, tab in ipairs(TABS) do
        if math.abs(dx - tab.cx) <= (tab.w or 168) * 0.5 and math.abs(dy - 340) <= 36 then
            state.tab = tab.key
            state.scrollY = 0
            print("[TaskPage] tab " .. tab.key)
            return true
        end
    end
    local task = rowAt(dx, dy)
    if not task then return true end
    local status = statusOf(task)
    if status == TaskConfig.STATUS.CLAIMABLE then
        print("[TaskPage] claim " .. task.id)
        GameAction.sendAction(Protocol.ACTION_TYPES.CLAIM_TASK, { taskId = task.id })
    end
    return true
end

function TaskPage.handleDragBegin(dx, dy)
    if not state.open then return false end
    state.dragging = true
    state.dragMoved = false
    state.dragStartY = dy
    state.dragStartScroll = state.scrollY
    return true
end

function TaskPage.handleDragMove(_dx, dy)
    if not state.dragging then return false end
    local delta = state.dragStartY - dy
    if math.abs(delta) > 8 then state.dragMoved = true end
    state.scrollY = state.dragStartScroll + delta
    clampScroll()
    return true
end

function TaskPage.handleDragEnd(_dx, _dy)
    if not state.open then return false end
    state.dragging = false
    return true
end

function TaskPage.handleScroll(wheel)
    if not state.open then return false end
    state.scrollY = state.scrollY - wheel * 48
    clampScroll()
    return true
end

return TaskPage
