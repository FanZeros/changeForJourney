-- 远征升级暗金横卡：无旧 Spine、无白色光条，首次与再次展示共用状态机。
-- UI 组件复用宿主帧；只在自定义图形层绘制轻量金色光晕和余烬。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local Progress = require("config.ExpeditionProgress")
local ExpTable = require("config.ExpTable")
local ClientDispatcher = require("runtime.ClientDispatcher")
local GameState = require("core.GameState")
local I18n = require("core.I18n")

local Popup = {}
local ENTER_DURATION, EXIT_DURATION, AUTO_CLOSE_SEC = 0.4, 0.3, 5
---@class ExpeditionPopupState
---@field open boolean
---@field phase string
---@field timer number
---@field elapsed number
---@field remaining number
---@field fromLevel number
---@field level number
---@field unlocks table[]
---@type ExpeditionPopupState
local state = {
    open = false, phase = "closed", timer = 0, elapsed = 0, remaining = AUTO_CLOSE_SEC,
    fromLevel = 1, level = 1, unlocks = {},
}
---@type Panel?
local card = nil
---@type Label?
local titleLabel = nil
---@type Label?
local levelLabel = nil
---@type Label?
local pointsLabel = nil
---@type Label?
local summaryLabel = nil
---@type Panel?
local unlockPanel = nil
---@type Button?
local rewardsButton = nil
---@type Label?
local hintLabel = nil
---@type fun()?
local onViewRewards = nil
local contentDirty = true
local contentLanguage = ""
local presentationVersion = 0
local wasBlocked = false

function Popup.getPresentationVersion()
    Popup.isPresentationBlocked()
    return presentationVersion
end

-- 与宿主最终层级和输入共用阻塞条件，遮挡时连进入/退出动画也不偷跑。
-- 绘制与输入查询也记录切换，开场分支提前返回Update时仍会作废旧按压。
function Popup.isPresentationBlocked()
    local blocked = require("ui.hud.popup.OfflineRewardPanel").isOpen()
        or require("ui.hud.popup.UpdateNoticePopup").isOpen()
        or require("ui.story.gate.DarkTitleScreenGate").isOpen()
        or require("ui.story.gate.LetterIntro").isOpen()
        or require("ui.story.ScenarioDialogue").isActive()
        or require("ui.story.SamsaraRecordPanel").isOpen()
        or require("ui.dev.CEPanel").isOpen()
    if blocked ~= wasBlocked then
        presentationVersion = presentationVersion + 1
        wasBlocked = blocked
    end
    return blocked
end

local function normalizedLevel(value)
    local number = tonumber(value) or 1
    if number ~= number or math.abs(number) == math.huge then number = 1 end
    return math.max(1, math.min(ExpTable.PLAYER_MAX_LEVEL, math.floor(number)))
end

local function ensureCard()
    Surface.init()
    if card then return end
    titleLabel = UI.Label {
        text = "", fontSize = 23, height = 42, width = "100%",
        textAlign = "center", fontColor = {244, 232, 204, 255},
    }
    levelLabel = UI.Label {
        text = "Lv.1", fontSize = 48, height = 82, width = "100%",
        textAlign = "center", fontColor = {240, 199, 94, 255},
    }
    pointsLabel = UI.Label {
        text = "", fontSize = 17, height = 32, width = "100%", textAlign = "center",
        fontColor = {168, 208, 153, 255},
    }
    summaryLabel = UI.Label {
        text = "", fontSize = 14, height = 28, width = "100%", textAlign = "center",
        fontColor = {216, 201, 163, 255},
    }
    unlockPanel = UI.Panel {
        width = "100%", height = 126, gap = 6, justifyContent = "center",
        pointerEvents = "none",
    }
    rewardsButton = UI.Button {
        text = "查看远征奖励", fontSize = 15, fontWeight = "normal", width = 320, height = 46,
        backgroundColor = {110, 78, 24, 255}, borderColor = {201, 151, 59, 255},
        borderWidth = 1, borderRadius = 6, textColor = {244, 232, 204, 255},
        pointerEvents = "none",
    }
    hintLabel = UI.Label {
        text = "", fontSize = 12, height = 24, width = "100%", textAlign = "center",
        fontColor = {150, 138, 110, 255},
    }
    card = UI.Panel {
        width = 780, height = 466, padding = 22, gap = 6, alignItems = "center",
        backgroundGradient = { direction = "to-bottom", from = {30, 26, 21, 255}, to = {13, 11, 9, 255} },
        borderWidth = 1.5, borderColor = {201, 151, 59, 255}, borderRadius = 12,
        pointerEvents = "none", overflow = "hidden",
        children = {
            titleLabel, levelLabel, pointsLabel, summaryLabel,
            UI.Divider { color = {110, 78, 24, 255}, thickness = 1, spacing = 0, width = "100%", height = 2 },
            unlockPanel, rewardsButton, hintLabel,
        },
    }
    print("[LevelUpPopup] 暗金横卡组件已就绪")
end

local function updateContent()
    if contentLanguage ~= I18n.get() then contentDirty = true end
    if not contentDirty or not card or not titleLabel or not levelLabel or not pointsLabel
        or not summaryLabel or not rewardsButton or not unlockPanel then return end
    titleLabel:SetText(I18n.lookup("远征等级提升"))
    levelLabel:SetText("Lv." .. state.level)
    pointsLabel:SetText(I18n.format("Lv.%d → Lv.%d    远征点上限 +%d", state.fromLevel, state.level,
        math.max(0, state.level - state.fromLevel)))
    local snapshot = Progress.build({ level = GameState.getLevel(), exp = GameState.getExp() },
        ClientDispatcher.get("task"), ClientDispatcher.get("battle"))
    local reached = {}
    for _, row in ipairs(snapshot.rows) do
        if row.level > state.fromLevel and row.level <= state.level then
            reached[#reached + 1] = "Lv." .. row.level
        end
    end
    local milestoneText = table.concat(reached, " / ", 1, math.min(4, #reached))
    if #reached > 4 then milestoneText = I18n.format("%s 等 %d 项", milestoneText, #reached) end
    summaryLabel:SetText(#reached > 0 and I18n.format("到达奖励里程碑 %s", milestoneText)
        or I18n.lookup("每次成长都将记入远征勋记"))
    rewardsButton:SetText(snapshot.claimableCount > 0
        and I18n.format("查看奖励 · %d 项可领", snapshot.claimableCount) or I18n.lookup("查看远征奖励"))
    unlockPanel:ClearChildren()
    -- 固定三行，超出时摘要计数；完整明细始终在常驻奖励页查看。
    for index = 1, math.min(3, #state.unlocks) do
        local entry = state.unlocks[index]
        unlockPanel:AddChild(UI.Label {
            text = Progress.unlockLabel(entry), fontSize = 14, height = 28, width = "100%",
            textAlign = "center", fontColor = {216, 201, 163, 255},
        })
    end
    if #state.unlocks > 3 then
        unlockPanel:AddChild(UI.Label {
            text = I18n.format("另有 %d 项解锁，可前往奖励页查看", #state.unlocks - 3),
            fontSize = 11, height = 22, width = "100%", textAlign = "center",
            fontColor = {150, 138, 110, 255},
        })
    end
    contentDirty = false
    contentLanguage = I18n.get()
end

-- 宿主逻辑坐标与输入同源；默认设计空间兼容旧调用。
local function geometry(width, height)
    width, height = width or 1080, height or 2400
    local scale = math.min(1, math.max(0.01, (width - 36) / 780), math.max(0.01, (height - 36) / 466))
    return (width - 780 * scale) * 0.5, (height - 466 * scale) * 0.5, scale
end

function Popup.init(_vg)
    ensureCard()
end

-- 保留旧接口：新横卡不需要异步资源预加载。
function Popup.preload(_vg)
    ensureCard()
end

function Popup.setOnViewRewards(callback)
    onViewRewards = callback
end

function Popup.show(newLevel, _unlocks, fromLevel)
    local target = normalizedLevel(newLevel)
    local from = normalizedLevel(fromLevel or math.max(1, target - 1))
    if state.open then
        from = math.min(from, state.fromLevel)
        target = math.max(target, state.level)
    end
    state.fromLevel, state.level = from, target
    state.unlocks = Progress.getRangeUnlocks(from, target)
    state.open, state.phase, state.timer, state.elapsed = true, "enter", 0, 0
    state.remaining = AUTO_CLOSE_SEC
    presentationVersion = presentationVersion + 1
    wasBlocked = Popup.isPresentationBlocked()
    contentDirty = true
    ensureCard()
    updateContent()
    require("systems.GameSFX").play("level_up")
    print("[LevelUpPopup] 升级摘要 " .. from .. "→" .. target .. " 解锁=" .. #state.unlocks)
end

function Popup.isOpen()
    return state.open
end

local function startExit()
    state.phase, state.timer = "exit", 0
end

function Popup.update(dt)
    if not state.open then return end
    if Popup.isPresentationBlocked() then return end
    dt = math.max(0, tonumber(dt) or 0)
    state.timer, state.elapsed = state.timer + dt, state.elapsed + dt
    if state.phase == "enter" and state.timer >= ENTER_DURATION then
        state.phase, state.timer = "idle", 0
    elseif state.phase == "idle" then
        state.remaining = math.max(0, state.remaining - dt)
        if state.remaining <= 0 then startExit() end
    elseif state.phase == "exit" and state.timer >= EXIT_DURATION then
        state.open, state.phase = false, "closed"
        print("[LevelUpPopup] 已关闭")
    end
end

function Popup.handleInput(x, y, width, height)
    if not state.open then return false end
    if Popup.isPresentationBlocked() then return true end
    if state.phase ~= "idle" then return true end
    local left, top, scale = geometry(width, height)
    local localX, localY = (x - left) / scale, (y - top) / scale
    -- Yoga 已完成布局时按按钮实际矩形命中；首次尚未绘制也不透传底层。
    local bounds = rewardsButton and rewardsButton:GetAbsoluteLayout()
    if onViewRewards and bounds and localX >= bounds.x and localX <= bounds.x + bounds.w
        and localY >= bounds.y and localY <= bounds.y + bounds.h then
        state.open, state.phase = false, "closed"
        print("[LevelUpPopup] 前往远征奖励")
        onViewRewards()
        return true
    end
    startExit()
    return true
end

local function drawGlow(vg, x, y, scale, alpha)
    local cx, cy = x + 390 * scale, y + 233 * scale
    local radius = 300 * scale
    nvgBeginPath(vg)
    nvgRect(vg, cx - radius * 1.5, cy - radius, radius * 3, radius * 2)
    local glowInner = nvgRGBA(201, 151, 59, math.floor(alpha * 30))
    local glowOuter = nvgRGBA(201, 151, 59, 0)
    ---@cast glowInner NVGcolor
    ---@cast glowOuter NVGcolor
    nvgFillPaint(vg, nvgRadialGradient(vg, cx, cy, 60 * scale, radius, glowInner, glowOuter))
    nvgFill(vg)
    -- 固定数量余烬，不分配粒子对象、不使用 additive/白色背景。
    for index = 1, 14 do
        local phase = (state.elapsed * 0.16 + index * 0.071) % 1
        local px = x + ((index * 137) % 780) * scale
        local py = y + (466 - phase * 520) * scale
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, (index % 2 + 1) * scale)
        nvgFillColor(vg, nvgRGBA(201, 151, 59, math.floor((1 - phase) * alpha * 88)))
        nvgFill(vg)
    end
end

function Popup.draw(vg, width, height)
    if not state.open or not vg or Popup.isPresentationBlocked() then return end
    ensureCard()
    updateContent()
    local currentCard = card --[[@as Panel?]]
    local currentHint = hintLabel --[[@as Label?]]
    if not currentCard or not currentHint then return end
    local left, top, scale = geometry(width, height)
    local alpha, slide = 1.0, 0.0
    if state.phase == "enter" then
        local progress = math.min(1, state.timer / ENTER_DURATION)
        local eased = 1 - (1 - progress) ^ 3
        alpha, slide = 0.72 + 0.28 * eased, 22 * (1 - eased)
    elseif state.phase == "exit" then
        local progress = math.min(1, state.timer / EXIT_DURATION)
        alpha, slide = 1 - progress, -16 * progress
    end
    currentHint:SetText(I18n.format("%d 秒后自动关闭 · 点击空白继续", math.ceil(state.remaining)))
    nvgSave(vg)
    drawGlow(vg, left, top, scale, alpha)
    nvgTranslate(vg, left, top + slide * scale)
    nvgScale(vg, scale, scale)
    nvgGlobalAlpha(vg, alpha)
    Surface.draw(currentCard, vg, 780, 466)
    nvgRestore(vg)
end

function Popup.destroy()
    state.open, state.phase = false, "closed"
    if card then card:Destroy() end
    card, titleLabel, levelLabel, pointsLabel, summaryLabel = nil, nil, nil, nil, nil
    unlockPanel, rewardsButton, hintLabel = nil, nil, nil
    contentLanguage = ""
    contentDirty = true
end

return Popup
