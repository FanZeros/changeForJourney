-- 远征奖励轨道：每级一个圆球，当前等级发光；只读快照，不发奖、不写台账。
-- 使用 UI 组件与设计坐标桥，复用宿主已有 NanoVG 帧，只创建可见节点。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local Progress = require("config.ExpeditionProgress")
local TaskConfig = require("config.TaskConfig")
local ResourceDefs = require("config.ResourceDefs")
local NumberUtil = require("core.NumberUtil")
local I18n = require("core.I18n")

local View = {}
local COLOR = {
    text = { 244, 232, 204, 255 }, muted = { 164, 159, 145, 255 },
    gold = { 255, 226, 150, 255 }, border = { 105, 80, 44, 255 },
    active = { 53, 41, 27, 255 }, locked = { 29, 26, 25, 255 },
    claimed = { 28, 34, 30, 255 }, green = { 156, 190, 161, 255 },
}

---@class ExpeditionRewardWidgets
---@field icon Panel
---@field text Label
---@field amount Label
---@field state Label
---@class ExpeditionTrackRowWidgets
---@field panel Panel
---@field sphere Panel
---@field halo Panel
---@field level Label
---@field title Label
---@field card Panel
---@field current Label
---@field line Panel
---@field button Button
---@field rewards ExpeditionRewardWidgets[]
---@field signature string?
---@type ExpeditionTrackRowWidgets[]
local rowWidgets = {}
---@type Panel?
local summaryRoot = nil
---@type Panel?
local contentRoot = nil
local contentKey, summaryKey = "", ""
local firstVisible, lastVisible = 1, 1

local function label(id, x, y, width, height, size, color)
    return UI.Label {
        id = id, text = "", position = "absolute", left = x, top = y,
        width = width, height = height, fontSize = size * 0.75,
        fontFamily = "sans", fontWeight = "normal", fontColor = color or COLOR.text,
        verticalAlign = "middle", pointerEvents = "none", flexShrink = 1,
    }
end

local function createSummary(width, height)
    local root = UI.Panel {
        width = width, height = height, pointerEvents = "none",
        backgroundColor = { 38, 31, 26, 255 }, borderRadius = 16,
        borderWidth = 2, borderColor = COLOR.border,
    }
    root:AddChild(label("level", 28, 16, 540, 48, 44, COLOR.gold))
    local claimable = label("claimable", width - 330, 20, 300, 44, 30, COLOR.gold)
    claimable:SetStyle({ textAlign = "right" })
    root:AddChild(claimable)
    root:AddChild(label("exp", 28, 66, width - 56, 34, 28, COLOR.muted))
    root:AddChild(UI.ProgressBar {
        id = "progress", position = "absolute", left = 28, top = 112,
        width = width - 56, height = 18, value = 0, max = 1, showLabel = false,
        fillColor = { 192, 151, 70, 255 }, borderColor = COLOR.border,
        borderWidth = 1, borderRadius = 9, pointerEvents = "none",
    })
    return root
end

local function createRow(row, width, rowHeight, step, top)
    local panel = UI.Panel {
        id = row.taskId, position = "absolute", left = 0, top = top,
        width = width, height = step, pointerEvents = "none",
    }
    -- 连接线先画，圆球和光晕后画；首尾不延伸出虚构等级。
    local line = UI.Panel {
        id = "line", position = "absolute", left = 94, top = row.level == 1 and 92 or 0,
        width = 4, height = row.level == #TaskConfig.LEVEL_TASKS and 92 or (row.level == 1 and step - 92 or step),
        backgroundColor = COLOR.border, pointerEvents = "none",
    }
    local halo = UI.Panel {
        id = "halo", position = "absolute", left = 16, top = 12, width = 160, height = 160,
        borderRadius = 80, opacity = 0, pointerEvents = "none",
        backgroundGradient = { type = "radial", innerRadius = 28, outerRadius = 80,
            from = { 225, 171, 67, 110 }, to = { 225, 171, 67, 0 } },
    }
    local sphere = UI.Panel {
        id = "sphere", position = "absolute", left = 48, top = 44, width = 96, height = 96,
        borderRadius = 48, borderWidth = 2, borderColor = COLOR.border, pointerEvents = "none",
        backgroundGradient = { direction = "to-bottom-right", from = { 66, 55, 40, 255 }, to = { 23, 21, 20, 255 } },
    }
    local level = label("level", 0, 0, 96, 96, 42, COLOR.gold)
    level:SetStyle({ textAlign = "center" })
    sphere:AddChild(level)
    local card = UI.Panel {
        id = "card", position = "absolute", left = 190, top = 8, width = width - 190, height = rowHeight - 16,
        backgroundColor = COLOR.locked, borderRadius = 12, borderWidth = 1,
        borderColor = { 72, 63, 49, 255 }, pointerEvents = "none",
    }
    local title = label("title", 20, 10, 350, 40, 30, COLOR.text)
    local current = label("current", width - 404, 10, 192, 40, 23, COLOR.gold)
    current:SetStyle({ textAlign = "right" })
    local rewards = {}
    for index = 1, #row.tasks do
        local x = 20 + (index - 1) * 230
        local icon = UI.Panel {
            id = "icon_" .. index, position = "absolute", left = x, top = 62,
            width = 62, height = 62, backgroundFit = "contain", pointerEvents = "none",
        }
        local rewardText = label("reward_" .. index, x + 72, 50, 154, 34, 25, COLOR.gold)
        local amount = label("amount_" .. index, x + 72, 84, 154, 32, 27, COLOR.gold)
        local rewardState = label("state_" .. index, x + 72, 116, 154, 32, 18, COLOR.muted)
        card:AddChild(icon)
        card:AddChild(rewardText)
        card:AddChild(amount)
        card:AddChild(rewardState)
        rewards[index] = { icon = icon, text = rewardText, amount = amount, state = rewardState }
    end
    local button = UI.Button {
        id = "claim", position = "absolute", left = width - 380, top = 88, width = 164, height = 58,
        text = "未达成", disabled = true, fontFamily = "sans", fontWeight = "normal",
        fontSize = 25 * 0.75, borderRadius = 8, pointerEvents = "none",
        backgroundColor = { 176, 132, 48, 255 }, textColor = COLOR.text,
        disabledBackgroundColor = { 51, 47, 42, 255 }, disabledTextColor = COLOR.muted,
        borderWidth = 0, padding = 0, boxShadow = false,
    }
    card:AddChild(title)
    card:AddChild(current)
    card:AddChild(button)
    panel:AddChild(line)
    panel:AddChild(halo)
    panel:AddChild(sphere)
    panel:AddChild(card)
    return { panel = panel, sphere = sphere, halo = halo, level = level, title = title,
        card = card, current = current, line = line, button = button, rewards = rewards }
end

local function updateSummary(snapshot)
    if not summaryRoot then return end
    local key = table.concat({ I18n.get(), tostring(snapshot.loading), tostring(snapshot.level), tostring(snapshot.exp),
        tostring(snapshot.maxExp), tostring(snapshot.ratio), tostring(snapshot.claimableCount) }, "|")
    if key == summaryKey then return end
    summaryKey = key
    local level = summaryRoot:FindById("level") --[[@as Label?]]
    local claimable = summaryRoot:FindById("claimable") --[[@as Label?]]
    local exp = summaryRoot:FindById("exp") --[[@as Label?]]
    local bar = summaryRoot:FindById("progress") --[[@as ProgressBar?]]
    local loading = snapshot.loading == true
    if level then level:SetText(loading and I18n.lookup("远征等级 · 加载中") or I18n.format("远征等级 Lv.%d", snapshot.level)) end
    if claimable then claimable:SetText(loading and I18n.lookup("可领 —") or I18n.format("可领 %d 项", snapshot.claimableCount)) end
    if exp then
        exp:SetText(loading and I18n.lookup("经验进度加载中")
            or (snapshot.maxExp > 0 and I18n.format("经验 %s / %s", NumberUtil.format(snapshot.exp),
                NumberUtil.format(snapshot.maxExp)) or I18n.lookup("经验进度 · 已达等级上限")))
    end
    if bar then bar:SetValue(loading and 0 or snapshot.ratio) end
end

-- 文本按真实宿主字体测宽，显式缩字；名称和数量分行，避免译文挤掉数量。
---@param widget Label
local function fittedText(widget, vg, value, size)
    widget:SetText(value)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, size)
    local measured = nvgTextBounds(vg, 0, 0, value, nil)
    local fontSize = measured > 150 and size * 150 / measured or size
    widget:SetStyle({ fontSize = fontSize * 0.75 })
end

---@param widgets ExpeditionTrackRowWidgets
---@param row table
---@param loading boolean
---@param vg NVGContextWrapper
local function updateRow(widgets, row, loading, vg)
    local parts = { I18n.get(), row.taskId, row.status, tostring(row.current), tostring(loading) }
    for _, task in ipairs(row.tasks) do
        parts[#parts + 1] = task.status .. Progress.rewardLabel(task.reward)
    end
    local signature = table.concat(parts, "|")
    if widgets.signature == signature then return end
    widgets.signature = signature
    local claimable = not loading and row.status == TaskConfig.STATUS.CLAIMABLE
    local claimed = row.status == TaskConfig.STATUS.CLAIMED
    local current = not loading and row.current
    widgets.card:SetStyle({ backgroundColor = claimed and COLOR.claimed or (claimable and COLOR.active or COLOR.locked),
        borderColor = current and COLOR.gold or (claimable and COLOR.border or { 72, 63, 49, 255 }),
        borderWidth = current and 2 or 1 })
    widgets.sphere:SetStyle({ borderColor = current and COLOR.gold or COLOR.border,
        backgroundGradient = { direction = "to-bottom-right",
            from = current and { 218, 172, 81, 255 } or (claimable and { 107, 82, 42, 255 } or { 66, 55, 40, 255 }),
            to = current and { 103, 68, 25, 255 } or { 23, 21, 20, 255 } } })
    widgets.line:SetStyle({ backgroundColor = (claimable or claimed or current) and { 148, 112, 52, 255 } or COLOR.border })
    widgets.level:SetText(tostring(row.level))
    widgets.level:SetFontColor(current and { 255, 246, 214, 255 } or (claimed and COLOR.green or COLOR.gold))
    widgets.title:SetText("Lv." .. row.level .. " · " .. I18n.lookup("等级奖励"))
    widgets.current:SetText(current and I18n.lookup("当前等级") or "")
    for index, task in ipairs(row.tasks) do
        local rewardWidgets = widgets.rewards[index]
        local def = ResourceDefs.DEFS[task.reward.type]
        local done = task.status == TaskConfig.STATUS.CLAIMED
        rewardWidgets.icon:SetStyle({ backgroundImage = def and def.iconPath or task.reward.icon,
            imageTint = done and { 165, 175, 165, 255 } or { 255, 255, 255, 255 } })
        fittedText(rewardWidgets.text, vg, I18n.lookup(def and def.name or task.reward.type), 25)
        rewardWidgets.amount:SetText("× " .. NumberUtil.format(task.reward.amount))
        rewardWidgets.text:SetFontColor(done and COLOR.green or COLOR.gold)
        rewardWidgets.amount:SetFontColor(done and COLOR.green or COLOR.gold)
        fittedText(rewardWidgets.state, vg, done and I18n.lookup("已领取")
            or (task.taskId == row.taskId and I18n.lookup("每级额外奖励") or I18n.lookup("远征勋记")), 18)
    end
    widgets.button:SetText(I18n.lookup(loading and "加载中" or (claimed and "已领取" or (claimable and "领取" or "未达成"))))
    widgets.button:SetDisabled(not claimable)
end

function View.update(snapshot, layout, vg)
    Surface.init()
    if not summaryRoot then summaryRoot = createSummary(layout.w, layout.summaryH) end
    updateSummary(snapshot)
    local step = layout.rowH + layout.gap
    firstVisible = math.max(1, math.floor((layout.scrollY or 0) / step) + 1)
    lastVisible = math.min(#snapshot.rows, math.ceil(((layout.scrollY or 0) + layout.h) / step) + 1)
    local key = layout.w .. ":" .. step .. ":" .. firstVisible .. ":" .. lastVisible
    if not contentRoot or key ~= contentKey then
        if contentRoot then contentRoot:Destroy() end
        contentKey, rowWidgets = key, {}
        contentRoot = UI.Panel { width = layout.w, height = #snapshot.rows * step, pointerEvents = "none" }
        for index = firstVisible, lastVisible do
            local widgets = createRow(snapshot.rows[index], layout.w, layout.rowH, step, (index - 1) * step)
            rowWidgets[#rowWidgets + 1] = widgets
            contentRoot:AddChild(widgets.panel)
        end
    end
    for index = firstVisible, lastVisible do
        local widgets = rowWidgets[index - firstVisible + 1]
        local row = snapshot.rows[index]
        updateRow(widgets, row, snapshot.loading == true, vg)
        -- 只更新当前可见圆球的轻呼吸透明度，不重复创建字体、贴图或控件。
        widgets.halo:SetStyle({ opacity = not snapshot.loading and row.current
            and (0.78 + math.sin(time.elapsedTime * 2.4) * 0.18) or 0 })
    end
end

function View.draw(vg, snapshot, layout)
    if not vg then return end
    View.update(snapshot, layout, vg)
    nvgSave(vg)
    nvgIntersectScissor(vg, layout.x, layout.summaryY, layout.w, layout.summaryH)
    nvgTranslate(vg, layout.x, layout.summaryY)
    if summaryRoot then Surface.draw(summaryRoot, vg, layout.w, layout.summaryH) end
    nvgRestore(vg)
    nvgSave(vg)
    nvgIntersectScissor(vg, layout.x, layout.y, layout.w, layout.h)
    nvgTranslate(vg, layout.x, layout.y - (layout.scrollY or 0))
    if contentRoot then Surface.draw(contentRoot, vg, layout.w, #snapshot.rows * (layout.rowH + layout.gap)) end
    nvgRestore(vg)
end

return View
