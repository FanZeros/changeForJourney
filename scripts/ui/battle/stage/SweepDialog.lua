-- 扫荡弹窗：主线与资源副本一券一场；预估参考远征六指标，不含首通大奖。
-- 复用新 UI 组件与现有 DesignWidgetSurface，宿主仍负责帧、缩放和模态输入。
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
local Format = require("ui.battle.stage.StageSelectRewardPreview")
local BF = require("systems.ButtonFeedback")
local DrawUtil = require("core.DrawUtil")
local I18n = require("core.I18n")

local M = {}
local D = { x = 65, y = 570, w = 950, h = 1250, cx = 540, cy = 1195,
    confirmY = 1700, stepY = 1510, sliderX = 340, sliderW = 400,
    teamX = 438, teamY = 968, teamW = 170, teamH = 48, teamStep = 194 }
local state = { open = false, openTime = 0, count = 1, teamIdx = 1, stageId = nil,
    sliderDragging = false, lastPreview = -1, preview = nil, reason = "", kind = "main" }
local root = nil ---@type Panel?
local title = nil ---@type Label?
local stageLabel = nil ---@type Label?
local quantity = nil ---@type Label?
local ticketLabel = nil ---@type Label?
local statusLabel = nil ---@type Label?
local confirmButton = nil ---@type Button?
local metrics = {} ---@type Label[]
local teamButtons = {} ---@type Button[]
local categoryButtons = {} ---@type Button[]
local imageVg = nil ---@type any
local sweepImage = -1
local lastLanguage = ""
local categories = { "main", "gold_mine", "equipment_vault", "black_diamond" }
local names = { main = "主线", gold_mine = "金币副本", equipment_vault = "装备副本", black_diamond = "黑晶副本" }
local C = { bone = { 244, 237, 224, 255 }, dim = { 159, 151, 140, 255 }, gold = { 231, 192, 116, 255 } }

local function label(text, x, y, width, size, color)
    return UI.Label { text = I18n.lookup(text), position = "absolute", left = x, top = y,
        width = width, height = 50, fontSize = size or 30, fontColor = color or C.bone,
        fontFamily = "sans", fontWeight = "normal", verticalAlign = "middle" }
end

local function button(text, x, y, width, height)
    return UI.Button { text = I18n.lookup(text), position = "absolute", left = x, top = y,
        width = width, height = height, fontSize = 30, fontFamily = "sans", fontWeight = "normal",
        textColor = C.bone, backgroundColor = { 61, 48, 33, 255 },
        borderWidth = 1, borderColor = { 126, 93, 47, 255 }, borderRadius = 8 }
end

local function destroyTree()
    if root then root:Destroy() end
    root, title, stageLabel, quantity, ticketLabel, statusLabel, confirmButton = nil, nil, nil, nil, nil, nil, nil
    metrics, teamButtons, categoryButtons = {}, {}, {}
end

local function ensureTree()
    if root then return end
    Surface.init()
    root = UI.Panel { width = D.w, height = D.h, backgroundColor = { 25, 22, 19, 250 },
        borderWidth = 3, borderColor = { 135, 99, 49, 255 }, borderRadius = 22 }
    title = label("关卡扫荡", 45, 75, 810, 52, C.gold)
    root:AddChild(title)
    root:AddChild(button("×", 835, 25, 70, 65))
    root:AddChild(label("1张券 = 重打1场 · 不含首通大奖", 45, 165, 855, 26, C.dim))
    for i, kind in ipairs(categories) do
        local b = button(names[kind], 45 + (i - 1) * 217, 250, 205, 52)
        categoryButtons[i] = b; root:AddChild(b)
    end
    stageLabel = label("尚无可扫荡关卡", 45, 302, 850, 35, C.gold); root:AddChild(stageLabel)
    root:AddChild(label("扫荡小队", 104, 370, 210, 32, C.dim))
    for team = 1, 3 do
        local b = button("小队" .. team, D.teamX - D.x - D.teamW * 0.5 + (team - 1) * D.teamStep,
            D.teamY - D.y - D.teamH * 0.5, D.teamW, D.teamH)
        b:SetStyle({ fontSize = 28 }); teamButtons[team] = b; root:AddChild(b)
    end
    root:AddChild(label("本次收益预估", 45, 432, 850, 32, C.bone))
    local definitions = {
        { "金币 / 黑晶", "gold" }, { "远征经验", nil }, { "每名队员经验", nil },
        { "随机装备 / 件", nil }, { "卷轴合计 / 张", "random_scroll" }, { "扫荡券掉落 / 张", "sweep_ticket" },
    }
    for i, def in ipairs(definitions) do
        local x, y = 45 + ((i - 1) % 3) * 289, 492 + math.floor((i - 1) / 3) * 137
        local card = UI.Panel { position = "absolute", left = x, top = y, width = 277, height = 125,
            backgroundColor = { 37, 31, 25, 255 }, borderRadius = 10, borderWidth = 1,
            borderColor = { 79, 65, 45, 255 } }
        if def[2] then
            card:AddChild(UI.Panel { position = "absolute", left = 12, top = 12, width = 35, height = 35,
                backgroundImage = ResourceDefs.DEFS[def[2]].iconPath, backgroundFit = "contain" })
        end
        card:AddChild(label(def[1], def[2] and 52 or 12, 7, def[2] and 211 or 250, 26, C.dim))
        local value = label("0", 12, 57, 250, 36, C.gold)
        metrics[i] = value; card:AddChild(value); root:AddChild(card)
    end
    root:AddChild(label("随机数量为平均期望，单次可能为0；六种卷轴均匀掉落。", 45, 770, 860, 19, C.dim))
    quantity = label("扫荡次数：1", 300, 842, 480, 38); root:AddChild(quantity)
    root:AddChild(button("−", 175, 898, 84, 84))
    root:AddChild(button("+", 691, 898, 84, 84))
    ticketLabel = label("", 175, 994, 650, 31, C.gold); root:AddChild(ticketLabel)
    confirmButton = button("扫荡", 270, 1080, 410, 100); root:AddChild(confirmButton)
    statusLabel = label("", 45, 1181, 860, 19, C.dim); root:AddChild(statusLabel)
end

local function getModules()
    return Store.Get("battle") or {}, Store.Get("dungeon") or {}, Store.Get("heroes") or {}
end

local function teamCount(team)
    local battle, _, heroes = getModules()
    local ids = Rules.getTeam(heroes, battle, team)
    return ids and #ids or 0
end

local function selectTarget(kind, preferred)
    local battle, dungeon = getModules()
    state.kind = kind
    state.stageId = nil
    if kind == "main" then
        -- 分类主线不能被本队资源位置带回副本，最高已通回退仍由统一规则负责。
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
        local sub = dungeon[kind]
        local highest = DC.getHighestClearedFloor(sub, kind)
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
        Store.Get("artifacts"), Store.Get("talents"), state.teamIdx, state.stageId, state.count)
    -- 未找到目标时不能让Service隐式回退到其他分类。
    if not state.stageId then preview, err = nil, "请先通关该分类的关卡" end
    state.preview, state.reason = preview, err or ""
    state.lastPreview = time.elapsedTime
end

local function maxCount()
    if not state.stageId or not Rules.isCleared(state.stageId, Store.Get("battle"), Store.Get("dungeon")) then return 0 end
    return math.min(Rules.MAX_COUNT, math.max(0, math.floor(GameState.getSweepTicket() or 0)))
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
    state.sliderDragging = false
    local battle, dungeon = getModules()
    local tasks = battle.teamStageIds or {}
    local current = preferredStageId or tasks[tostring(team)] or tasks[team] or (team == 1 and battle.currentStageId)
    local resource = current and DC.decodeStageId(current)
    selectTarget(resource or "main", tonumber(current))
    refresh()
    print(string.format("[SweepDialog] 打开 队%d 分类=%s 关卡=%s 券=%d", team,
        state.kind, tostring(state.stageId), GameState.getSweepTicket() or 0))
end

function M.close()
    state.open, state.sliderDragging = false, false
end
function M.isOpen() return state.open end

function M.drawButton(vg)
    if sweepImage < 0 then return end
    DrawUtil.drawImageCentered(vg, sweepImage, 971, 2115, 130, 144, 1)
    DrawUtil.drawTextStroke(vg, 971, 2175, "扫荡", 32, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
end

function M.draw(vg)
    if not state.open then return end
    local limit = maxCount()
    local count = math.max(1, math.min(state.count, math.max(1, limit)))
    if state.count ~= count then state.count = count; state.lastPreview = -1 end
    if time.elapsedTime - state.lastPreview >= 0.5 or I18n.get() ~= lastLanguage then refresh() end
    if I18n.get() ~= lastLanguage then destroyTree(); lastLanguage = I18n.get() end
    ensureTree()
    local preview = state.preview or {}
    title:SetText(I18n.lookup(state.kind == "main" and "主线扫荡" or "副本扫荡"))
    stageLabel:SetText(state.stageId and I18n.lookup(SC.getStageDisplayName(state.stageId)) or I18n.lookup("尚无可扫荡关卡"))
    local values = { state.kind == "black_diamond" and preview.diamond or preview.gold,
        preview.playerExp, preview.heroExp, preview.equipCount, preview.scrollCount, 0 }
    for i = 1, 6 do metrics[i]:SetText(Format.formatEstimate(values[i] or 0)) end
    quantity:SetText(I18n.format("扫荡次数：%d", state.count))
    ticketLabel:SetText(I18n.format("消耗 %d 张扫荡券（拥有 %d 张）", state.count, GameState.getSweepTicket() or 0))
    local unlocked = ET.getUnlockedTeamCount(Store.Get("battle"))
    for team, b in ipairs(teamButtons) do
        b:SetText(I18n.format("小队%d(%d人)", team, teamCount(team)))
        b:SetDisabled(team > unlocked)
        b:SetStyle({ borderColor = team == state.teamIdx and C.gold or C.dim })
    end
    for i, b in ipairs(categoryButtons) do
        b:SetStyle({ borderColor = categories[i] == state.kind and C.gold or C.dim })
    end
    local canConfirm = limit >= state.count and state.preview ~= nil
    confirmButton:SetDisabled(not canConfirm)
    confirmButton:SetText(I18n.lookup(canConfirm and "扫荡" or (state.reason ~= "" and "无法扫荡" or "扫荡券不足")))
    statusLabel:SetText(I18n.lookup(state.reason ~= "" and state.reason or "扫荡不返券；可用券不限每日次数，挂机收益不变。"))
    local t = math.min(1, math.max(0, (time.elapsedTime - state.openTime) / 0.18))
    local scale = t * (1 + 0.08 * math.sin(t * math.pi))
    if scale <= 0.01 then return end
    nvgSave(vg)
    nvgTranslate(vg, D.cx, D.cy); nvgScale(vg, scale * 0.8, scale * 0.8)
    nvgTranslate(vg, D.x - D.cx, D.y - D.cy)
    Surface.draw(root, vg, D.w, D.h)
    -- 滑条仍为自定义矢量图形；文字/按钮全部使用UI组件。
    local fraction = limit > 1 and (state.count - 1) / (limit - 1) or 0
    nvgBeginPath(vg); nvgRoundedRect(vg, 275, 928, 400, 24, 12)
    nvgFillColor(vg, nvgRGBA(75, 65, 50, 255)); nvgFill(vg)
    nvgBeginPath(vg); nvgCircle(vg, 275 + fraction * 400, 940, 18)
    nvgFillColor(vg, nvgRGBA(231, 192, 116, 255)); nvgFill(vg)
    nvgRestore(vg)
end

function M.handleInput(x, y)
    if not state.open then return false end
    x, y = designPoint(x, y)
    if inside(x, y, D.x + 870, D.y + 57.5, 70, 65) then M.close(); return true end
    state.count = math.max(1, math.min(state.count, math.max(1, maxCount())))
    for i, kind in ipairs(categories) do
        if inside(x, y, D.x + 45 + (i - 1) * 217 + 102.5, D.y + 276, 205, 52) then
            selectTarget(kind); refresh(); return true
        end
    end
    for team = 1, 3 do
        if inside(x, y, D.teamX + (team - 1) * D.teamStep, D.teamY, D.teamW, D.teamH) then
            if team <= ET.getUnlockedTeamCount(Store.Get("battle")) then
                state.teamIdx = team; state.lastPreview = -1; refresh()
            end
            return true
        end
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
            BF.trigger("sweep_dlg_confirm")
            if M.onSweep then M.onSweep(state.count, state.teamIdx, state.stageId) end
        else print("[SweepDialog] 拒绝扫荡: " .. state.reason) end
        return true
    end
    if not inside(x, y, D.cx, D.cy, D.w, D.h) then M.close() end
    return true
end

function M.handleDragBegin(x, y)
    if not state.open then return false end
    x, y = designPoint(x, y)
    if maxCount() > 1 and inside(x, y, 540, D.stepY, 436, 56) then
        state.sliderDragging = true; sliderCount(x)
    end
    return true
end
function M.handleDragMove(x, _y)
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
