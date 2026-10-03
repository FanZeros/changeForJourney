-- 远征里程碑视图：只读快照；领取与滚动全部由 TaskPage 宿主处理。
-- 新界面只使用 UI 组件，借设计坐标桥绘制到宿主已有 NanoVG 帧。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local Progress = require("config.ExpeditionProgress")
local TaskConfig = require("config.TaskConfig")
local ResourceDefs = require("config.ResourceDefs")
local NumberUtil = require("core.NumberUtil")

local View = {}
local COLOR = {
    text = { 244, 232, 204, 255 }, muted = { 164, 159, 145, 255 },
    gold = { 255, 226, 150, 255 }, border = { 105, 80, 44, 255 },
    active = { 65, 47, 24, 255 }, locked = { 32, 28, 26, 255 },
    claimed = { 30, 40, 35, 255 }, green = { 156, 190, 161, 255 },
}

---@class ExpeditionTrackRowWidgets
---@field panel Panel
---@field level Label
---@field title Label
---@field reward Label
---@field icon Panel
---@field unlocks Label
---@field button Button
---@field signature string?
---@type ExpeditionTrackRowWidgets[]
local rowWidgets = {}
---@type Panel?
local summaryRoot = nil
---@type Panel?
local contentRoot = nil
local contentKey = ""
local summaryKey = ""

-- 字号沿用宿主设计稿，UI 的 pt 在桥中换算为原字号像素。
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
    root:AddChild(label("level", 28, 18, 420, 48, 44, COLOR.gold))
    local claimable = label("claimable", width - 330, 20, 300, 44, 30, COLOR.gold)
    claimable:SetStyle({ textAlign = "right" })
    root:AddChild(claimable)
    root:AddChild(label("exp", 28, 66, width - 56, 38, 28, COLOR.muted))
    root:AddChild(UI.ProgressBar {
        id = "progress", position = "absolute", left = 28, top = 110,
        width = width - 56, height = 22, value = 0, max = 1, showLabel = false,
        fillColor = { 192, 151, 70, 255 }, borderColor = COLOR.border,
        borderWidth = 2, borderRadius = 10, pointerEvents = "none",
    })
    root:AddChild(label("next", 28, 142, width - 56, 44, 30, COLOR.text))
    root:AddChild(label("current", 28, 188, width - 56, 32, 26, COLOR.gold))
    root:AddChild(label("ledger", 28, 220, width - 56, 24, 20, COLOR.muted))
    local stages = label("stages", 28, 248, width - 56, 68, 23, COLOR.muted)
    stages:SetStyle({ whiteSpace = "normal", maxLines = 2, lineHeight = 1.35 })
    root:AddChild(stages)
    return root
end

local function createRow(taskId, width, rowHeight, top)
    local panel = UI.Panel {
        id = taskId, position = "absolute", left = 0, top = top,
        width = width, height = rowHeight, pointerEvents = "none",
        backgroundColor = COLOR.locked, borderRadius = 14,
        borderWidth = 2, borderColor = { 72, 63, 49, 255 },
    }
    local level = label("level", 16, 24, 108, 86, 34, COLOR.gold)
    level:SetStyle({ textAlign = "center", backgroundColor = { 46, 39, 30, 255 }, borderRadius = 12 })
    local icon = UI.Panel {
        position = "absolute", left = 140, top = 26, width = 92, height = 92,
        backgroundFit = "contain", pointerEvents = "none",
    }
    local title = label("title", 256, 22, width - 498, 46, 34)
    local reward = label("reward", 256, 70, width - 498, 42, 29, COLOR.gold)
    local unlocks = label("unlocks", 140, 132, width - 168, rowHeight - 146, 28, COLOR.muted)
    unlocks:SetStyle({ whiteSpace = "normal", maxLines = 2, lineHeight = 1.4 })
    local button = UI.Button {
        position = "absolute", left = width - 216, top = 42, width = 188, height = 72,
        text = "未达成", disabled = true, fontFamily = "sans", fontWeight = "normal",
        fontSize = 30 * 0.75, borderRadius = 10, pointerEvents = "none",
        backgroundColor = { 176, 132, 48, 255 }, textColor = COLOR.text,
        disabledBackgroundColor = { 51, 47, 42, 255 }, disabledTextColor = COLOR.muted,
        borderWidth = 0, padding = 0, boxShadow = false,
    }
    panel:AddChild(level)
    panel:AddChild(icon)
    panel:AddChild(title)
    panel:AddChild(reward)
    panel:AddChild(unlocks)
    panel:AddChild(button)
    return { panel = panel, level = level, title = title, reward = reward,
        icon = icon, unlocks = unlocks, button = button }
end

local function unlockText(row)
    local names = {}
    for _, unlock in ipairs(row.unlocks or {}) do
        -- 等级行只展示该等级真正变动的规则，通关开放队伍单独列于顶部。
        if unlock.kind == "level" and unlock.level == row.level then
            names[#names + 1] = unlock.unlockName
        end
    end
    if #names == 0 then return "该等级无新增功能解锁" end
    return "等级成长 · " .. table.concat(names, "；")
end

local function updateSummary(snapshot)
    if not summaryRoot then return end
    local stageLines = {}
    for _, unlock in ipairs(snapshot.stageUnlocks or {}) do
        stageLines[#stageLines + 1] = (unlock.unlocked and "已开放 · " or "通关开放 · ") .. unlock.unlockName
    end
    local stageText = table.concat(stageLines, "\n")
    local key = table.concat({ tostring(snapshot.loading), tostring(snapshot.level), tostring(snapshot.exp),
        tostring(snapshot.maxExp), tostring(snapshot.ratio), tostring(snapshot.claimableCount),
        tostring(snapshot.nextLevel), tostring(snapshot.slotCount), tostring(snapshot.enhanceCap),
        tostring(snapshot.artifactSlotCount), stageText }, "|")
    if key == summaryKey then return end
    summaryKey = key
    local level = summaryRoot:FindById("level") --[[@as Label?]]
    local claimable = summaryRoot:FindById("claimable") --[[@as Label?]]
    local exp = summaryRoot:FindById("exp") --[[@as Label?]]
    local nextLevel = summaryRoot:FindById("next") --[[@as Label?]]
    local current = summaryRoot:FindById("current") --[[@as Label?]]
    local ledger = summaryRoot:FindById("ledger") --[[@as Label?]]
    local stages = summaryRoot:FindById("stages") --[[@as Label?]]
    local bar = summaryRoot:FindById("progress") --[[@as ProgressBar?]]
    local loading = snapshot.loading == true
    if level then level:SetText(loading and "远征等级 · 加载中" or ("远征等级 Lv." .. snapshot.level)) end
    if claimable then claimable:SetText(loading and "可领 —" or ("可领 " .. snapshot.claimableCount .. " 项")) end
    if exp then
        exp:SetText(loading and "经验进度加载中"
            or (snapshot.maxExp > 0 and ("经验 " .. NumberUtil.format(snapshot.exp)
                .. " / " .. NumberUtil.format(snapshot.maxExp)) or "经验进度 · 已达等级上限"))
    end
    if bar then bar:SetValue(loading and 0 or snapshot.ratio) end
    if nextLevel then
        nextLevel:SetText(loading and "下一里程碑 · 加载中"
            or (snapshot.nextLevel and ("下一里程碑 · Lv." .. snapshot.nextLevel) or "全部里程碑已达成"))
    end
    if current then
        current:SetText(loading and "当前成长 · 加载中" or ("每队 " .. tostring(snapshot.slotCount or "—")
            .. " 人 · 强化上限 Lv." .. tostring(snapshot.enhanceCap or "—")
            .. " · 神器 " .. tostring(snapshot.artifactSlotCount or "—") .. " 格"))
    end
    if ledger then ledger:SetText("永久勋记 · 等级顺序固定，已领取奖励保留记录") end
    if stages then stages:SetText(stageText) end
end

---@param widgets ExpeditionTrackRowWidgets
---@param row table
---@param loading boolean
local function updateRow(widgets, row, loading)
    local def = row.reward and ResourceDefs.DEFS[row.reward.type]
    local iconPath = def and def.iconPath or (row.reward and row.reward.icon)
    local rewardText, unlocksText = Progress.rewardLabel(row.reward), unlockText(row)
    local signature = table.concat({ row.taskId, tostring(row.level), row.status, tostring(loading),
        tostring(iconPath), rewardText, unlocksText }, "|")
    if widgets.signature == signature then return end
    widgets.signature = signature
    local claimable = not loading and row.status == TaskConfig.STATUS.CLAIMABLE
    local claimed = row.status == TaskConfig.STATUS.CLAIMED
    local textColor = claimed and COLOR.green or (claimable and COLOR.gold or COLOR.text)
    widgets.panel:SetStyle({
        backgroundColor = claimed and COLOR.claimed or (claimable and COLOR.active or COLOR.locked),
        borderColor = claimable and { 192, 151, 70, 255 } or { 72, 63, 49, 255 },
    })
    widgets.level:SetText("Lv." .. row.level)
    widgets.title:SetText("远征勋记")
    widgets.title:SetFontColor(textColor)
    widgets.reward:SetText(rewardText)
    widgets.reward:SetFontColor(claimed and COLOR.green or COLOR.gold)
    widgets.icon:SetStyle({ backgroundImage = iconPath,
        imageTint = claimed and { 170, 185, 172, 255 } or { 255, 255, 255, 255 } })
    widgets.unlocks:SetText(unlocksText)
    widgets.unlocks:SetFontColor(claimed and COLOR.green or COLOR.muted)
    widgets.button:SetText(loading and "加载中" or (claimed and "已领取" or (claimable and "领取" or "未达成")))
    widgets.button:SetDisabled(not claimable)
    widgets.button:SetStyle({ disabledBackgroundColor = claimed and { 55, 74, 60, 255 } or { 51, 47, 42, 255 },
        disabledTextColor = claimed and COLOR.green or COLOR.muted })
end

---@param snapshot table 远征展示模型，不改写任何玩家数据。
---@param layout table 宿主设计区域，包含固定摘要与列表滚动偏移。
function View.update(snapshot, layout)
    Surface.init()
    if not summaryRoot then summaryRoot = createSummary(layout.w, layout.summaryH) end
    summaryRoot:SetStyle({ width = layout.w, height = layout.summaryH })
    updateSummary(snapshot)
    local ids = {}
    for _, row in ipairs(snapshot.rows) do ids[#ids + 1] = row.taskId end
    local key = table.concat(ids, "|") .. ":" .. layout.w .. ":" .. layout.rowH .. ":" .. layout.gap
    if not contentRoot or key ~= contentKey then
        if contentRoot then contentRoot:Destroy() end
        contentKey = key
        rowWidgets = {}
        contentRoot = UI.Panel {
            width = layout.w, height = #snapshot.rows * (layout.rowH + layout.gap),
            pointerEvents = "none",
        }
        for index, row in ipairs(snapshot.rows) do
            local widgets = createRow(row.taskId, layout.w, layout.rowH, (index - 1) * (layout.rowH + layout.gap))
            rowWidgets[index] = widgets
            contentRoot:AddChild(widgets.panel)
        end
    end
    for index, row in ipairs(snapshot.rows) do updateRow(rowWidgets[index], row, snapshot.loading == true) end
end

---@param vg NVGContextWrapper
---@param snapshot table
---@param layout table 包含 x/y/w/h/rowH/gap/summaryY/summaryH/scrollY。
function View.draw(vg, snapshot, layout)
    if not vg then return end
    View.update(snapshot, layout)
    -- 仅变换与裁剪子树，不能新建 NanoVG 帧或重置宿主的全局缩放。
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
