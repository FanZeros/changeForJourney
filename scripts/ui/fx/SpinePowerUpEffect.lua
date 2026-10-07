-- 三队战力提升：图片铭牌、Spine 分层仪式与新 UI 数字滚动。
-- 大号只显示小队总战力；辅助行保留权威旧→新与净增，动画值不回写战力、编队或当前波快照。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local EventBus = require("core.EventBus")
local GameEvents = require("config.GameEvents")
local I18n = require("core.I18n")
local Effects = require("ui.fx.DarkEffectSprites")

local Effect = {}
local TEAM_COUNT, STABILIZE_DELAY, DURATION = 3, 2, 3.2
local WIDTH, HEADER_H, ROW_H = 760, 218, 96
local COUNT_DELAY, COUNT_TIME = .12, .93
---@class TeamPowerPresentation
---@field power number
---@field base number
---@field delta number
---@field startedAt number
---@field tweenAt number
---@field fromPower number
---@field fromDelta number
---@type table<number, TeamPowerPresentation>
local active = {}
---@type table<number, number>
local previous = {}
local initialized, disabled = false, false
---@type number
local stabilizeUntil = 0
local plaqueToken = {}
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
---@type Label[]
local rangeLabels = {}

local TEXT = {
    zh_CN = { title = "战力提升", team = "小队 %d" },
    zh_TW = { title = "戰力提升", team = "小隊 %d" },
    en = { title = "POWER INCREASED", team = "TEAM %d" },
    ja = { title = "戦力上昇", team = "部隊 %d" },
    ko = { title = "전투력 상승", team = "팀 %d" },
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
    -- 避免 integer 上界自加后溢出；大数保留原有限值，由格式化处理显示。
    if math.type(value) == "integer" then return value end
    return math.floor(value + 0.5)
end

local function formatPower(value)
    local full = math.type(value) == "integer" and tostring(value) or string.format("%.0f", value)
    if #full > 18 then return string.format("%.3e", value) end
    return full
end

local function clamp(value)
    return math.max(0, math.min(1, value))
end

---@param row TeamPowerPresentation
---@param current number
local function sample(row, current)
    local available = math.max(.000001, row.startedAt + DURATION - row.tweenAt)
    local delay = math.min(COUNT_DELAY, available * .12)
    -- 下降不延长提示，但计数压入原到期前，并预留15%时间显示准确终值。
    local countTime = math.min(COUNT_TIME, (available - delay) * .85)
    local progress = clamp((current - row.tweenAt - delay) / countTime)
    -- 减速滚动：末帧直接返回权威整数，不能因浮点插值显示少一或越过目标。
    if progress >= 1 then return row.power, row.delta, progress end
    if progress <= 0 then return row.fromPower, row.fromDelta, progress end
    local ease = 1 - (1 - progress) ^ 3
    local function interpolate(from, target)
        if from == target then return target end
        -- 大integer之间的小增量先算整数步幅，避免先转double丢失低位。
        if math.type(from) == "integer" and math.type(target) == "integer" then
            local distance = math.abs(target - from)
            if distance < 9007199254740992 then
                local step = math.floor(distance * ease + .5)
                return from < target and from + step or from - step
            end
        end
        -- 凸组合避免 target-from 的超大浮点差溢出；只改显示值。
        local value = from * (1 - ease) + target * ease
        return math.max(math.min(from, target), math.min(math.max(from, target), math.floor(value + .5)))
    end
    return interpolate(row.fromPower, row.power), interpolate(row.fromDelta, row.delta), progress
end

local function releasePlaque()
    Effects.release(plaqueToken)
    plaqueToken = {}
end

local function clearExpired()
    local current = now()
    local hadRows = next(active) ~= nil
    for team = 1, TEAM_COUNT do
        local row = active[team]
        if row and current - row.startedAt >= DURATION then active[team] = nil end
    end
    if hadRows and next(active) == nil then releasePlaque() end
end

local function onTeamPowerChanged(data)
    if not initialized or type(data) ~= "table" or type(data.powers) ~= "table" then return end
    if data.ready == false then
        previous, active = {}, {}
        releasePlaque()
        return
    end
    clearExpired()
    local current = now()
    local restartPlaque = false
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
                    local displayed, gain = sample(row, current)
                    row.power, row.delta = power, math.max(0, power - row.base)
                    if row.delta == 0 then
                        active[team] = nil
                    else
                        -- 连续成长从当前画面接续，不退回最初值；下降不重新延长生命周期。
                        row.fromPower, row.fromDelta, row.tweenAt = displayed, gain, current
                        if power > old then
                            row.startedAt = current
                            restartPlaque = true
                        end
                    end
                elseif power > old then
                    restartPlaque = true
                    active[team] = {
                        power = power, base = old, delta = power - old, startedAt = current,
                        tweenAt = current, fromPower = old, fromDelta = 0,
                    }
                    print(string.format("[TeamPowerEffect] 小队%d 战力%s→%s (+%s)", team,
                        formatPower(old), formatPower(power), formatPower(power - old)))
                end
            end
        end
    end
    -- 最新行重启铭牌需换播放token，不能让已推进的Spine倒退时间。
    if restartPlaque or next(active) == nil then releasePlaque() end
end

local function ensureCard()
    if card then return end
    Surface.init()
    title = UI.Label {
        text = "", height = 54, fontSize = 23, alignSelf = "center", whiteSpace = "nowrap",
        textAlign = "center", verticalAlign = "middle", fontColor = {216, 201, 163, 255},
        pointerEvents = "none",
    }
    ---@type Widget[]
    local children = { title }
    for team = 1, TEAM_COUNT do
        local teamLabel = UI.Label {
            text = "", height = 23, fontSize = 13, alignSelf = "center", whiteSpace = "nowrap",
            textAlign = "center", verticalAlign = "middle", fontColor = {150, 138, 110, 255},
            pointerEvents = "none",
        }
        local valueLabel = UI.Label {
            text = "", height = 44, fontSize = 27, alignSelf = "center", whiteSpace = "nowrap",
            textAlign = "center", verticalAlign = "middle", fontColor = {240, 199, 94, 255},
            pointerEvents = "none",
        }
        local rangeLabel = UI.Label {
            text = "", height = 22, fontSize = 12, alignSelf = "center", whiteSpace = "nowrap",
            textAlign = "center", verticalAlign = "middle", fontColor = {162, 152, 134, 255},
            pointerEvents = "none",
        }
        local panel = UI.Panel {
            width = "100%", height = ROW_H, alignItems = "center", pointerEvents = "none",
            children = { teamLabel, valueLabel, rangeLabel },
        }
        ---@cast teamLabel Label
        ---@cast valueLabel Label
        ---@cast rangeLabel Label
        teamLabels[team], valueLabels[team], rangeLabels[team] = teamLabel, valueLabel, rangeLabel
        rowPanels[team] = panel
        children[#children + 1] = panel
    end
    card = UI.Panel {
        width = WIDTH, height = HEADER_H + ROW_H, padding = {82, 90, 82, 90},
        alignItems = "center", pointerEvents = "none", children = children,
    }
    print("[TeamPowerEffect] 三队图片铭牌与数字滚动已就绪")
end

local function fade(elapsed)
    return math.max(0, math.min(1, elapsed / 0.24, (DURATION - elapsed) / 0.45))
end

function Effect.resetSession()
    previous, active = {}, {}
    releasePlaque()
    stabilizeUntil = now() + STABILIZE_DELAY
    disabled = false
end

function Effect.init()
    if initialized then EventBus.off(GameEvents.TEAM_POWER_CHANGED, onTeamPowerChanged) end
    initialized = true
    Effect.resetSession()
    EventBus.on(GameEvents.TEAM_POWER_CHANGED, onTeamPowerChanged)
end

-- 同帧多次update/draw/query只采样真实时钟；隐藏时不会积压实例或延长提示。
function Effect.update(_dt)
    if initialized then clearExpired() end
end

function Effect.isPlaying()
    clearExpired()
    return not disabled and next(active) ~= nil
end

function Effect.getDisplayRows()
    clearExpired()
    local rows, current = {}, now()
    for team = 1, TEAM_COUNT do
        local row = active[team]
        if row then
            local displayed, gain, progress = sample(row, current)
            local settle = clamp((current - row.tweenAt - COUNT_DELAY - COUNT_TIME) / .28)
            rows[#rows + 1] = {
                teamIdx = team, power = row.power, base = row.base, delta = row.delta,
                displayPower = displayed, displayDelta = gain, progress = progress,
                pulse = progress >= 1 and math.sin(settle * math.pi) or 0,
                elapsed = math.max(0, current - row.startedAt),
            }
        end
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

--- 全窗逻辑坐标的finishFrame调用；图片与文字共享宿主transform，不借三栏Viewport。
function Effect.draw(vg, width, height)
    if not vg or not Effect.isPlaying() then return end
    local screenWidth, screenHeight = width or 1080, height or 2400
    if not finitePositive(screenWidth) or not finitePositive(screenHeight) then return end
    local rows = Effect.getDisplayRows()
    local left, top, scale, cardHeight = Effect.getGeometry(screenWidth, screenHeight)
    local elapsed = DURATION
    for _, row in ipairs(rows) do elapsed = math.min(elapsed, row.elapsed) end
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
            local team = row.teamIdx
            rowPanels[team]:Show()
            local rowAlpha = math.floor(fade(row.elapsed) * 255 + 0.5)
            teamLabels[team]:SetFontColor({150, 138, 110, rowAlpha})
            local pulse = row.pulse
            valueLabels[team]:SetFontColor({240 + math.floor(pulse * 15),
                199 + math.floor(pulse * 31), 94 + math.floor(pulse * 72), rowAlpha})
            rangeLabels[team]:SetFontColor({162, 152, 134, math.floor(rowAlpha * .82)})
            teamLabels[team]:SetText(string.format(text.team, team))
            local value = formatPower(row.displayPower)
            -- 按终值预算字号，防止数位增长时UI来回抖动；先字号后文本以刷新真实自动宽度。
            local finalValue = formatPower(row.power)
            local fontSize = #finalValue > 36 and 18 or (#finalValue > 30 and 20 or 27)
            valueLabels[team]:SetFontSize(fontSize + pulse * 1.4)
            valueLabels[team]:SetText(value)
            -- 辅助行始终使用权威快照，不随displayDelta从0滚动；连续增减只在真实回执后更新。
            rangeLabels[team]:SetText(formatPower(row.base) .. "  →  " .. formatPower(row.power)
                .. "  ·  +" .. formatPower(row.delta))
        end
        nvgSave(vg)
        saved = true
        nvgTranslate(vg, left, top)
        nvgScale(vg, scale, scale)
        Effects.drawPower(vg, WIDTH * .5, cardHeight * .5, WIDTH, cardHeight, elapsed,
            DURATION, fade(elapsed), plaqueToken)
        Surface.draw(currentCard, vg, WIDTH, cardHeight)
    end)
    local failure = ok and "" or tostring(caught)
    if saved then
        local restored, restoreError = pcall(nvgRestore, vg)
        if not restored then ok, failure = false, tostring(restoreError) end
    end
    if not ok and not disabled then
        disabled, active = true, {}
        releasePlaque()
        print("[TeamPowerEffect] 绘制已安全停用，业务继续: " .. failure)
    end
end

function Effect.preload(vg)
    Effects.preload(vg)
end

function Effect.destroy()
    EventBus.off(GameEvents.TEAM_POWER_CHANGED, onTeamPowerChanged)
    initialized = false
    previous, active = {}, {}
    releasePlaque()
    if card then card:Destroy() end
    card, title = nil, nil
    rowPanels, teamLabels, valueLabels, rangeLabels = {}, {}, {}, {}
    disabled = false
end

return Effect
