-- 右栏展示层：共享设计几何、新UI按钮/标题与短促反馈；不修改编队或战力。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local I18n = require("core.I18n")
local NumberUtil = require("core.NumberUtil")

local M = {}
local SORT_X, SORT_Y, SORT_H, GAP = 112, 1000, 40, 8
local MODES = { "default", "team", "power", "level", "rarity", "direction" }
local WIDTHS = {132, 132, 132, 132, 156, 132}
local TEXT = {
    zh_CN = { default = "默认", team = "队伍", power = "战力", level = "等级", rarity = "稀有度",
        ascending = "升序 ↑", descending = "降序 ↓", fixed = "固定顺序", squad = "小队 %d", locked = "未解锁" },
    zh_TW = { default = "預設", team = "隊伍", power = "戰力", level = "等級", rarity = "稀有度",
        ascending = "升序 ↑", descending = "降序 ↓", fixed = "固定順序", squad = "小隊 %d", locked = "未解鎖" },
    en = { default = "Default", team = "Team", power = "Power", level = "Level", rarity = "Rarity",
        ascending = "Asc ↑", descending = "Desc ↓", fixed = "Fixed", squad = "TEAM %d", locked = "LOCKED" },
    ja = { default = "標準", team = "部隊", power = "戦力", level = "レベル", rarity = "レア度",
        ascending = "昇順 ↑", descending = "降順 ↓", fixed = "固定順", squad = "部隊 %d", locked = "未解放" },
    ko = { default = "기본", team = "팀", power = "전투력", level = "레벨", rarity = "희귀도",
        ascending = "오름차순 ↑", descending = "내림차순 ↓", fixed = "고정", squad = "팀 %d", locked = "잠김" },
}
---@type Panel?
local toolbar = nil
---@type Button[]
local buttons = {}
---@type boolean[]
local selectedButtons = {}
---@class RosterTeamHeader
---@field root Panel
---@field title Label
---@field count Label
---@field power Label
---@type RosterTeamHeader[]
local headers = {}
---@type string?
local sortHover = nil
---@type string?
local sortPressed = nil
---@type number?
local hoverTeam = nil
---@type number?
local hoverSlot = nil
---@type number?
local pressTeam = nil
---@type number?
local pressSlot = nil
---@class RosterTeamSnapshot
---@field ids number[]
---@field levels number[]
---@field power number
---@field changedAt table<number, number>
---@field powerAt number
---@field selectedAt number
---@type table<number, RosterTeamSnapshot>
local snapshots = {}
local previousActive = 0

local function now()
    local value = time.elapsedTime
    return type(value) == "number" and value == value and math.abs(value) < math.huge and value or 0
end

local function envelope(start, duration)
    if not start or start < 0 then return 0 end
    local p = (now() - start) / duration
    if p <= 0 or p >= 1 then return 0 end
    return math.sin(p * math.pi) * (1 - p * .35)
end

function M.reset()
    -- 这些子树由现有绘制宿主托管，不在Surface全局root下；重建前显式释放Yoga节点。
    if toolbar then toolbar:Destroy() end
    for _, header in pairs(headers) do header.root:Destroy() end
    snapshots, headers, toolbar, buttons, selectedButtons = {}, {}, nil, {}, {}
    previousActive = 0
    M.clearSortInteraction()
    M.clearTeamInteraction()
end

function M.hitTestSort(x, y)
    if y < SORT_Y or y >= SORT_Y + SORT_H then return nil end
    local left = SORT_X
    for i, key in ipairs(MODES) do
        local width = assert(WIDTHS[i])
        if x >= left and x < left + width then return key end
        left = left + width + GAP
    end
    return nil
end

function M.setSortInteraction(x, y, pressed)
    sortHover = M.hitTestSort(x, y)
    sortPressed = pressed and sortHover or nil
end

function M.clearSortInteraction()
    sortHover, sortPressed = nil, nil
end

function M.setTeamInteraction(team, slot, pressed)
    hoverTeam, hoverSlot = team, slot
    pressTeam, pressSlot = pressed and team or nil, pressed and slot or nil
end

function M.clearTeamInteraction()
    hoverTeam, hoverSlot, pressTeam, pressSlot = nil, nil, nil, nil
end

-- 同帧多宿主绘制只观察同一快照/墙钟，不用draw次数累计动画时间。
function M.observe(team, slots, power, active, levelFn, ready, locked)
    if ready == false or locked then snapshots[team] = nil; return end
    local row = snapshots[team]
    local first = not row
    if not row then
        row = { ids = {}, levels = {}, power = power, changedAt = {}, powerAt = -1, selectedAt = -1 }
        snapshots[team] = row
    end
    local current = now()
    if not first and power > row.power then row.powerAt = current end
    row.power = power
    if not first and previousActive ~= 0 and previousActive ~= active and team == active then row.selectedAt = current end
    for slot = 1, 4 do
        local entry = slots and slots[slot]
        local id = entry and entry.state == "occupied" and entry.heroId or 0
        local level = id ~= 0 and levelFn and levelFn(id) or 0
        if not first and (row.ids[slot] ~= id or (level > (row.levels[slot] or 0))) then
            row.changedAt[slot] = current
        end
        row.ids[slot], row.levels[slot] = id, level
    end
end

function M.finishObservation(active)
    previousActive = active
end

function M.getFeedback(team, slot)
    local row = snapshots[team]
    local hovered = hoverTeam == team and hoverSlot == slot
    local pressed = pressTeam == team and pressSlot == slot
    local pulse = row and envelope(slot and row.changedAt[slot] or row.selectedAt, .55) or 0
    local powerPulse = row and envelope(row.powerAt, .65) or 0
    return hovered, pressed, pulse, powerPulse
end

local function ensureToolbar()
    if toolbar then return toolbar end
    Surface.init()
    ---@type Widget[]
    local children = {}
    for i = 1, #MODES do
        local button = UI.Button {
            width = WIDTHS[i], height = SORT_H, flexShrink = 0, borderRadius = 6, borderWidth = 1,
            padding = 0, paddingHorizontal = 4, fontSize = 15, minFontSize = 12, text = "",
            textColor = {213, 201, 175, 255}, backgroundColor = {27, 23, 19, 245},
            hoverBackgroundColor = {45, 37, 27, 255}, pressedBackgroundColor = {19, 16, 13, 255},
            disabledBackgroundColor = {25, 23, 21, 220}, disabledTextColor = {124, 116, 99, 255},
            borderColor = {104, 88, 64, 200}, pointerEvents = "none",
        }
        buttons[i] = button
        children[#children + 1] = button
    end
    toolbar = UI.Panel { width = 856, height = SORT_H, flexDirection = "row", gap = GAP,
        pointerEvents = "none", children = children }
    print("[CharacterRosterUI] 排序栏与共享命中几何已就绪")
    return toolbar
end

function M.drawSort(vg, mode, ascending)
    local root = ensureToolbar()
    local pack = TEXT[I18n.get()] or TEXT.zh_CN
    local fixed = mode == "default" or mode == "team"
    for i, key in ipairs(MODES) do
        local button = assert(buttons[i])
        local selected = key == mode
        local label = key == "direction" and (fixed and pack.fixed or (ascending and pack.ascending or pack.descending))
            or pack[key]
        if button.props.text ~= label then button:SetText(label) end
        if button.props.disabled ~= (key == "direction" and fixed) then button:SetDisabled(key == "direction" and fixed) end
        button.state.hovered = not button.props.disabled and sortHover == key
        button.state.pressed = not button.props.disabled and sortPressed == key
        if selectedButtons[i] ~= selected then
            button:SetBackgroundColor(selected and {67, 49, 27, 255} or {27, 23, 19, 245})
            button:SetBorderColor(selected and {212, 175, 90, 255} or {104, 88, 64, 200})
            selectedButtons[i] = selected
        end
    end
    nvgSave(vg)
    nvgTranslate(vg, SORT_X, SORT_Y)
    Surface.draw(root, vg, 856, SORT_H)
    nvgRestore(vg)
end

local function ensureHeader(team)
    local header = headers[team]
    if header then return header end
    Surface.init()
    local title = UI.Label { width = 268, height = 44, fontSize = 22, minFontSize = 16,
        verticalAlign = "middle", text = "", whiteSpace = "nowrap", pointerEvents = "none" }
    local count = UI.Label { width = 72, height = 44, fontSize = 16,
        verticalAlign = "middle", textAlign = "center", text = "", pointerEvents = "none" }
    local power = UI.Label { width = 360, height = 44, fontSize = 20, minFontSize = 12,
        verticalAlign = "middle", textAlign = "right", text = "", whiteSpace = "nowrap", pointerEvents = "none" }
    local root = UI.Panel { width = 752, height = 44, flexDirection = "row", gap = 26,
        children = { title, count, power }, pointerEvents = "none" }
    header = {root = root, title = title, count = count, power = power}
    headers[team] = header
    return header
end

function M.drawHeader(vg, team, x, y, color, locked, count, power)
    local header = ensureHeader(team)
    local pack = TEXT[I18n.get()] or TEXT.zh_CN
    local label = locked and (string.format(pack.squad, team) .. " · " .. pack.locked) or string.format(pack.squad, team)
    if header.title.props.text ~= label then header.title:SetText(label) end
    local counts = locked and "" or tostring(count) .. "/4"
    if header.count.props.text ~= counts then header.count:SetText(counts) end
    local value = locked and "—" or NumberUtil.format(power)
    if header.power.props.text ~= value then header.power:SetText(value) end
    header.title:SetFontColor({color[1], color[2], color[3], locked and 155 or 255})
    header.count:SetFontColor({154, 143, 121, locked and 100 or 220})
    local _, _, _, pulse = M.getFeedback(team)
    header.power:SetFontColor({247, 219 + math.floor(pulse * 25), 119 + math.floor(pulse * 70), locked and 120 or 255})
    nvgSave(vg)
    nvgTranslate(vg, x, y)
    Surface.draw(header.root, vg, 752, 44)
    nvgRestore(vg)
end

function M.getSortGeometry()
    return SORT_X, SORT_Y, 856, SORT_H, MODES, WIDTHS, GAP
end

return M
