-- 三队战力提升：保留旧模块路径，表现改为全窗居中的暗铁铭牌与新 UI 文字。
-- 只展示正式缓存的净增加值，不改变公式、编队或当前波的战斗快照。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local EventBus = require("core.EventBus")
local GameEvents = require("config.GameEvents")
local I18n = require("core.I18n")
local Effects = require("ui.fx.DarkEffectPrimitives")

local Effect = {}
local TEAM_COUNT, STABILIZE_DELAY, DURATION = 3, 2, 3.2
local WIDTH, HEADER_H, ROW_H = 760, 66, 76
---@class TeamPowerPresentation
---@field power number
---@field base number
---@field delta number
---@field startedAt number
---@type table<number, TeamPowerPresentation>
local active = {}
---@type table<number, number>
local previous = {}
local initialized, disabled = false, false
---@type number
local stabilizeUntil = 0
---@type Panel?
local card = nil
---@type Label?
local title = nil
---@type Panel[]
local rowPanels = {}
---@type Label[]
local teamLabels = {}
---@type Label[]
local valueLabels = {}

local TEXT = {
    zh_CN = { title = "战力提升", team = "小队 %d", value = "%s   +%s" },
    zh_TW = { title = "戰力提升", team = "小隊 %d", value = "%s   +%s" },
    en = { title = "POWER INCREASED", team = "TEAM %d", value = "%s   +%s" },
    ja = { title = "戦力上昇", team = "部隊 %d", value = "%s   +%s" },
    ko = { title = "전투력 상승", team = "팀 %d", value = "%s   +%s" },
}

local function now()
    local value = time.elapsedTime
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return 0 end
    return value
end

local function finitePositive(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge and value > 0
end

local function powerValue(value)
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge or value < 0 then
        return nil
    end
    return math.floor(value + 0.5)
end

local function formatPower(value)
    local full = string.format("%.0f", value)
    -- 极端大值采用科学记数，避免有限但数百位的字符串越出铭牌。
    if #full > 18 then return string.format("%.3e", value) end
    return full
end

local function clearExpired()
    local current = now()
    for team = 1, TEAM_COUNT do
        local row = active[team]
        if row and current - row.startedAt >= DURATION then active[team] = nil end
    end
end

local function onTeamPowerChanged(data)
    if not initialized or type(data) ~= "table" or type(data.powers) ~= "table" then return end
    -- 开机player同步可能先发布空队，不能把标题停留后的首次读档当作战力增长。
    if data.ready == false then
        previous, active = {}, {}
        return
    end
    clearExpired()
    local current = now()
    for team = 1, TEAM_COUNT do
        local power = powerValue(data.powers[team])
        if power then
            local old = previous[team]
            previous[team] = power
            if current < stabilizeUntil or old == nil then
                active[team] = nil
            elseif power ~= old then
                local row = active[team]
                if row then
                    -- 连续穿卸／升阶显示本段净提升，不把下降前旧增量叠入新结果。
                    row.power, row.delta = power, math.max(0, power - row.base)
                    if row.delta == 0 then active[team] = nil
                    elseif power > old then row.startedAt = current end
                elseif power > old then
                    active[team] = { power = power, base = old, delta = power - old, startedAt = current }
                    print(string.format("[TeamPowerEffect] 小队%d 战力%s→%s (+%s)", team,
                        formatPower(old), formatPower(power), formatPower(power - old)))
                end
            end
        end
    end
end

local function ensureCard()
    if card then return end
    Surface.init()
    title = UI.Label {
        text = "", height = 42, fontSize = 22, alignSelf = "center", whiteSpace = "nowrap",
        textAlign = "center", verticalAlign = "middle", fontColor = {216, 201, 163, 255},
        pointerEvents = "none",
    }
    ---@type Widget[]
    local children = { title }
    for team = 1, TEAM_COUNT do
        local teamLabel = UI.Label {
            text = "", height = 25, fontSize = 13, alignSelf = "center", whiteSpace = "nowrap",
            textAlign = "center", verticalAlign = "middle", fontColor = {150, 138, 110, 255},
            pointerEvents = "none",
        }
        local valueLabel = UI.Label {
            text = "", height = 43, fontSize = 27, alignSelf = "center", whiteSpace = "nowrap",
            textAlign = "center", verticalAlign = "middle", fontColor = {240, 199, 94, 255},
            pointerEvents = "none",
        }
        local panel = UI.Panel {
            width = "100%", height = ROW_H, alignItems = "center", pointerEvents = "none",
            children = { teamLabel, valueLabel },
        }
        ---@cast teamLabel Label
        ---@cast valueLabel Label
        teamLabels[team] = teamLabel
        valueLabels[team] = valueLabel
        rowPanels[team] = panel
        children[#children + 1] = panel
    end
    card = UI.Panel {
        width = WIDTH, height = HEADER_H + ROW_H, padding = {12, 90, 12, 90},
        alignItems = "center", pointerEvents = "none", children = children,
    }
    print("[TeamPowerEffect] 三队暗铁铭牌已就绪，无 Spine 资源依赖")
end

-- 文字使用自动宽度单行Label，不设控件opacity/transform/clip。
-- 透明度逐色相乘；正常绘制不建立UI嵌套状态帧，不改写任何引擎全局入口。
local function drawSurface(root, vg, width, height)
    Surface.draw(root, vg, width, height)
end

local function fade(elapsed)
    return math.max(0, math.min(1, elapsed / 0.24, (DURATION - elapsed) / 0.45))
end

function Effect.resetSession()
    previous, active = {}, {}
    stabilizeUntil = now() + STABILIZE_DELAY
    disabled = false
end

function Effect.init()
    if initialized then EventBus.off(GameEvents.TEAM_POWER_CHANGED, onTeamPowerChanged) end
    initialized = true
    Effect.resetSession()
    EventBus.on(GameEvents.TEAM_POWER_CHANGED, onTeamPowerChanged)
end

-- 生命周期只由真实时钟决定；标题、塔／副本或未 draw 都能结束稳定期和播放。
function Effect.update(_dt)
    if initialized then clearExpired() end
end

function Effect.isPlaying()
    clearExpired()
    return not disabled and next(active) ~= nil
end

-- 返回副本，便于回归核对；调用者不能修改内部基准或计时。
function Effect.getDisplayRows()
    clearExpired()
    local rows = {}
    for team = 1, TEAM_COUNT do
        local row = active[team]
        if row then rows[#rows + 1] = {
            teamIdx = team, power = row.power, delta = row.delta,
            elapsed = math.max(0, now() - row.startedAt),
        } end
    end
    return rows
end

---@return number left
---@return number top
---@return number scale
---@return number height
function Effect.getGeometry(width, height)
    if not finitePositive(width) or not finitePositive(height) then return 0, 0, 0, 0 end
    local count = #Effect.getDisplayRows()
    local cardHeight = HEADER_H + ROW_H * math.max(1, count)
    local scale = math.max(0.01, math.min(1, (width - 40) / WIDTH, (height - 40) / cardHeight))
    return (width - WIDTH * scale) * 0.5, (height - cardHeight * scale) * 0.5, scale, cardHeight
end

--- 宿主 finishFrame 的逻辑屏幕空间调用，不借任何左栏／中栏 Viewport。
function Effect.draw(vg, width, height)
    if not vg or not Effect.isPlaying() then return end
    local screenWidth = width or 1080
    local screenHeight = height or 2400
    if not finitePositive(screenWidth) or not finitePositive(screenHeight) then return end
    local rows = Effect.getDisplayRows()
    local left, top, scale, cardHeight = Effect.getGeometry(screenWidth, screenHeight)
    local elapsed = DURATION
    for _, row in ipairs(rows) do elapsed = math.min(elapsed, row.elapsed) end
    -- 铭牌使用最新一队的时间轴；各行文字保留自己的淡入／淡出。
    local alpha = math.min(1, elapsed / 0.24, (DURATION - elapsed) / 0.45)
    local saved = false
    local ok, caught = pcall(function()
        ensureCard()
        local currentCard, currentTitle = card, title
        if not currentCard or not currentTitle then return end
        local text = TEXT[I18n.get()] or TEXT.zh_CN
        currentTitle:SetText(text.title)
        currentCard:SetHeight(cardHeight)
        currentTitle:SetFontColor({216, 201, 163, math.floor(fade(elapsed) * 255 + 0.5)})
        for team = 1, TEAM_COUNT do rowPanels[team]:Hide() end
        for _, row in ipairs(rows) do
            rowPanels[row.teamIdx]:Show()
            local rowAlpha = math.floor(fade(row.elapsed) * 255 + 0.5)
            teamLabels[row.teamIdx]:SetFontColor({150, 138, 110, rowAlpha})
            valueLabels[row.teamIdx]:SetFontColor({240, 199, 94, rowAlpha})
            teamLabels[row.teamIdx]:SetText(string.format(text.team, row.teamIdx))
            local value = string.format(text.value, formatPower(row.power), formatPower(row.delta))
            -- 先设字号再更新文本，让自动宽度按本帧字号测量；避免缩字后沿用旧宽度。
            -- 两个18位整数仍保留完整值，用18号字收进580宽内容区，不截断战力。
            valueLabels[row.teamIdx]:SetFontSize(#value > 36 and 18 or (#value > 30 and 20 or 27))
            valueLabels[row.teamIdx]:SetText(value)
        end
        nvgSave(vg)
        saved = true
        nvgTranslate(vg, left, top)
        nvgScale(vg, scale, scale)
        Effects.drawPower(vg, WIDTH * 0.5, cardHeight * 0.5, WIDTH, cardHeight, elapsed, DURATION, math.max(0, alpha))
        drawSurface(currentCard, vg, WIDTH, cardHeight)
    end)
    local failure = ok and "" or tostring(caught)
    if saved then
        local restored, restoreError = pcall(nvgRestore, vg)
        if not restored then
            ok = false
            failure = tostring(restoreError)
        end
    end
    if not ok and not disabled then
        disabled = true
        active = {}
        print("[TeamPowerEffect] 绘制已安全停用，业务继续: " .. failure)
    end
end

function Effect.preload(_vg)
    -- 兼容旧调用；程序化效果无贴图／骨架需要预加载。
end

function Effect.destroy()
    EventBus.off(GameEvents.TEAM_POWER_CHANGED, onTeamPowerChanged)
    initialized = false
    previous, active = {}, {}
    if card then card:Destroy() end
    card, title = nil, nil
    rowPanels, teamLabels, valueLabels = {}, {}, {}
    disabled = false
end

return Effect
