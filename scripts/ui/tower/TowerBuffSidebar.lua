-- 塔三栏的新UI组件树。路线只读；强化按ID计次数，描述不自行合并百分比。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local Layout = require("ui.tower.TowerLayout")
local Config = require("config.TowerConfig")
local Presentation = require("ui.tower.TowerPresentation")
local OathEffect = require("ui.tower.TowerOathEffect")

local Sidebar = {}
local function withState(vg, draw)
    nvgSave(vg)
    local ok, err = xpcall(draw, debug.traceback)
    nvgRestore(vg)
    if not ok then error(err, 0) end
end
local C = {
    background = { 16, 15, 18, 255 }, surface = { 26, 23, 25, 255 },
    border = { 89, 69, 48, 255 }, text = { 231, 220, 200, 255 },
    muted = { 149, 137, 122, 255 }, gold = { 201, 151, 59, 255 },
    red = { 155, 54, 49, 255 },
}

---@type Panel?
local leftRoot = nil
---@type Panel?
local rightRoot = nil
---@type ScrollView?
local routeScroll = nil
---@type ScrollView?
local buffScroll = nil
---@type Panel?
local buffContent = nil
---@type Panel?
local collapsedSpace = nil
---@type Label?
local floorLabel = nil
---@type Label?
local waveLabel = nil
---@type Label?
local buffTitle = nil
---@type Button?
local toggleButton = nil
local collapsed = false
local presentationVersion = 0
---@type Label?
local routeTitle = nil
---@type Label?
local routeNote = nil
---@type Label?
local ruleNote = nil
---@type Button?
local actionButton = nil
---@type Button?
local pendingButton = nil
---@type Panel?
local confirmRoot = nil
---@type Button?
local confirmRetreat = nil
---@type Button?
local confirmCancel = nil
---@type Label?
local confirmTitle = nil
---@type Label?
local confirmNote = nil
local nodes = {} ---@type Panel[]
local nodeLabels = {} ---@type Label[]
local lastFloor, lastWave, lastPhase, lastLanguage, lastBuffKey = 0, 0, "", "", ""
local lastRouteViewport = 0
local action = nil ---@type string?
local lastSnapshot = {} ---@type table
local drag = nil ---@type table?

local function text(source, ...)
    return Presentation.text(source, ...)
end

local function label(source, size, color)
    return UI.Label { text = source, fontSize = size or 24, fontColor = color or C.text,
        fontFamily = "sans", width = "100%", whiteSpace = "normal", lineHeight = 1.25,
        pointerEvents = "none", flexShrink = 0 }
end

local function button(caption, width, color)
    return UI.Button { text = caption, width = width or "100%", height = 64,
        fontSize = 26, fontFamily = "sans", fontWeight = "normal",
        textColor = C.text, backgroundColor = color or C.surface,
        borderColor = C.border, borderWidth = 2, borderRadius = 4,
        pointerEvents = "none", flexShrink = 0 }
end

-- 新UI路线使用程序化连接线；文字与节点全部仍是UI组件。
local RouteCanvas = UI.Widget:Extend("TowerRouteCanvas")
function RouteCanvas:Render(vg)
    local l = self:GetAbsoluteLayout()
    nvgBeginPath(vg)
    for floor = 1, Config.MAX_FLOOR do
        local x = l.x + (floor % 2 == 0 and 300 or 126)
        local y = l.y + (floor - 1) * 88 + 36
        if floor == 1 then nvgMoveTo(vg, x, y) else nvgLineTo(vg, x, y) end
    end
    nvgStrokeWidth(vg, 3)
    nvgStrokeColor(vg, nvgRGBA(75, 63, 52, 255))
    nvgStroke(vg)
end

local Icon = UI.Widget:Extend("TowerBuffIcon")
function Icon:Init(props)
    UI.Widget.Init(self, props)
    self.buff = props.buff or {}
end
function Icon:Render(vg)
    local l = self:GetAbsoluteLayout()
    OathEffect.drawIcon(vg, Presentation.icon(self.buff), l.x + l.w * 0.5,
        l.y + l.h * 0.5, math.min(l.w, l.h), 1)
end

-- 独立显示快照，不返回Config定义引用，兼容重复ID但不改正式排除已拥有规则。
function Sidebar.aggregate(ids)
    local rows, byId = {}, {}
    for _, rawId in ipairs(ids or {}) do
        local id = tonumber(rawId)
        local def = id and Config.BUFFS_BY_ID[id]
        if def then
            local row = byId[id]
            if not row then
                row = { id = id, count = 0, name = def.name, desc = def.desc, quality = def.quality }
                rows[#rows + 1] = row
                byId[id] = row
            end
            row.count = row.count + 1
        end
    end
    return rows
end

local function ensureRoots()
    if leftRoot then return end
    Surface.init()
    floorLabel, waveLabel = label("", 38, C.gold), label("", 26)
    routeTitle, routeNote = label("", 32), label("", 18, C.muted)
    local route = RouteCanvas { width = "100%", height = Config.MAX_FLOOR * 88,
        pointerEvents = "none" }
    for floor = 1, Config.MAX_FLOOR do
        local x = floor % 2 == 0 and 300 or 126
        local nodeLabel = UI.Label { text = tostring(floor), fontSize = 24,
            textAlign = "center", verticalAlign = "middle", width = "100%", height = "100%",
            fontColor = C.muted, pointerEvents = "none" }
        local node = UI.Panel { position = "absolute", left = x - 34,
            top = (floor - 1) * 88 + 2, width = 68, height = 68,
            backgroundColor = C.surface, borderColor = C.border, borderWidth = 2,
            borderRadius = 6, pointerEvents = "none", children = { nodeLabel } }
        route:AddChild(node)
        nodes[floor], nodeLabels[floor] = node, nodeLabel
    end
    routeScroll = UI.ScrollView { width = "100%", flexGrow = 1, flexBasis = 0,
        scrollX = false, scrollY = true, bounces = false, showScrollbar = true,
        scrollbarInteractive = true, pointerEvents = "none", children = { route } }
    leftRoot = UI.Panel { width = 486, height = 1080, backgroundColor = C.background,
        borderRightWidth = 3, borderRightColor = C.border, padding = 24, gap = 14,
        overflow = "hidden", pointerEvents = "none",
        children = { routeTitle, floorLabel, waveLabel, routeScroll, routeNote } }

    buffTitle, ruleNote = label("", 25.6), label("", 14.4, C.muted)
    toggleButton = button("收起")
    toggleButton:SetStyle({ height = 44, fontSize = 20.8 })
    buffContent = UI.Panel { width = "100%", gap = 10, pointerEvents = "none" }
    buffScroll = UI.ScrollView { width = "100%", flexGrow = 1, flexBasis = 0,
        scrollX = false, scrollY = true, bounces = false, showScrollbar = true,
        scrollbarInteractive = true, pointerEvents = "none", children = { buffContent } }
    -- 收起只隐藏内容，不销毁列表；弹性占位保持底部恢复/撤退入口与三栏几何不变。
    collapsedSpace = UI.Panel { width = "100%", flexGrow = 1, flexBasis = 0,
        visible = false, pointerEvents = "none" }
    actionButton, pendingButton = button(""), button("")
    pendingButton:SetVisible(false)
    rightRoot = UI.Panel { width = 486, height = 1080, backgroundColor = C.background,
        borderLeftWidth = 3, borderLeftColor = C.border, padding = 19.2, gap = 10,
        overflow = "hidden", pointerEvents = "none",
        children = { buffTitle, toggleButton, buffScroll, collapsedSpace, ruleNote, pendingButton, actionButton } }

    confirmTitle, confirmNote = label("", 34), label("", 24, C.muted)
    confirmTitle:SetStyle({ textAlign = "center", height = 46 })
    confirmNote:SetStyle({ textAlign = "center", height = 42 })
    confirmRetreat, confirmCancel = button("", 180, C.red), button("", 180)
    confirmRetreat:SetStyle({ position = "absolute", left = 60, top = 190, height = 56 })
    confirmCancel:SetStyle({ position = "absolute", left = 320, top = 190, height = 56 })
    confirmRoot = UI.Panel { width = 560, height = 280, backgroundColor = C.surface,
        borderWidth = 2, borderColor = C.border, borderRadius = 8,
        paddingTop = 42, paddingHorizontal = 22, gap = 4, pointerEvents = "none",
        children = { confirmTitle, confirmNote, confirmRetreat, confirmCancel } }
    print("[TowerBuffSidebar] initialized read-only route112 and buff UI trees")
end

local function rebuildBuffs(snapshot)
    if not buffContent then return end
    local rows = Sidebar.aggregate(snapshot.buffIds)
    local children = buffContent:GetChildren()
    for i = #children, 1, -1 do children[i]:Destroy() end
    if #rows == 0 then
        buffContent:AddChild(label(text("暂无强化"), 19.2, C.muted))
    end
    for _, row in ipairs(rows) do
        local def = Config.BUFFS_BY_ID[row.id]
        local color = Presentation.rarityColor(def.quality)
        local name = label(Presentation.name(def), 20.8, C.text)
        name:SetStyle({ paddingRight = 2 })
        local quality = label(Presentation.rarity(def.quality) .. "  ×" .. row.count, 16, color)
        local desc = label(Presentation.description(def), 18.4, C.muted)
        local header = UI.Panel { width = "100%", flexDirection = "row", gap = 10,
            alignItems = "center", children = {
                Icon { width = 51.2, height = 51.2, buff = def, pointerEvents = "none" },
                UI.Panel { flexGrow = 1, flexShrink = 1, gap = 3, children = { name, quality } },
            } }
        buffContent:AddChild(UI.Panel { width = "100%", padding = 12.8, gap = 8,
            backgroundColor = C.surface, borderWidth = 1, borderColor = color,
            borderRadius = 4, pointerEvents = "none", children = { header, desc } })
    end
end

local function sync(snapshot, layout)
    ensureRoots()
    lastSnapshot = snapshot
    local language = require("core.I18n").get()
    local key = table.concat(snapshot.buffIds or {}, ",")
    local changedLanguage = language ~= lastLanguage
    if changedLanguage or key ~= lastBuffKey then
        rebuildBuffs(snapshot)
        lastBuffKey = key
    end
    if snapshot.floor ~= lastFloor or changedLanguage then
        for floor, node in ipairs(nodes) do
            local current = floor == snapshot.floor
            local passed = floor < snapshot.floor
            node:SetStyle({ borderColor = current and C.gold or C.border,
                borderWidth = current and 3 or 2,
                backgroundColor = current and { 66, 41, 32, 255 } or C.surface })
            nodeLabels[floor]:SetFontColor((current or passed) and C.text or C.muted)
        end
        if floorLabel then floorLabel:SetText(text("第%d层", snapshot.floor)) end
    end
    if snapshot.wave ~= lastWave or changedLanguage then
        if waveLabel then waveLabel:SetText(text("波次 %d/%d", snapshot.wave, Config.WAVES_PER_FLOOR)) end
    end
    if snapshot.phase ~= lastPhase or changedLanguage then
        action = snapshot.phase == "buff_pick" and "resume_pick"
            or (snapshot.phase == "battle" and "retreat" or nil)
        if actionButton then
            actionButton:SetText(text(action == "resume_pick" and "继续择契" or "撤退"))
            actionButton:SetDisabled(action == nil or snapshot.inputModal == true)
            actionButton:SetStyle({ backgroundColor = action == "retreat" and C.red or C.surface })
        end
    elseif actionButton then
        actionButton:SetDisabled(action == nil or snapshot.inputModal == true)
    end
    if pendingButton then
        local count = snapshot.pendingChoices or 0
        pendingButton:SetVisible(count > 0)
        pendingButton:SetText(text("待选暗契 ×%d", count))
        pendingButton:SetDisabled(snapshot.phase ~= "battle" or snapshot.inputModal == true)
    end
    if changedLanguage then
        routeTitle:SetText(text("塔之路线"))
        routeNote:SetText(text("本层路线仅供查看"))
        ruleNote:SetText(text("次数仅作记录，效果按原规则生效"))
        confirmTitle:SetText(text("确认撤退？"))
        confirmNote:SetText(text("本层进度将丢失"))
        confirmRetreat:SetText(text("撤退"))
        confirmCancel:SetText(text("取消"))
    end
    if buffTitle then buffTitle:SetText(text("已获强化") .. "  " .. #(snapshot.buffIds or {})) end
    if toggleButton then
        toggleButton:SetText(text(collapsed and "展开" or "收起"))
        toggleButton:SetDisabled(snapshot.inputModal == true)
    end
    leftRoot:SetHeight(layout.sideHeight)
    rightRoot:SetHeight(layout.sideHeight)
    lastLanguage, lastFloor, lastWave, lastPhase = language, snapshot.floor, snapshot.wave, snapshot.phase
end

function Sidebar.draw(vg, width, height, snapshot)
    local layout = Layout.compute(width, height)
    local reveal = lastFloor ~= snapshot.floor
    sync(snapshot, layout)
    for _, side in ipairs({ { root = leftRoot, rect = layout.left }, { root = rightRoot, rect = layout.right } }) do
        withState(vg, function()
            nvgIntersectScissor(vg, side.rect.x, side.rect.y, side.rect.w, side.rect.h)
            nvgTranslate(vg, side.rect.x, side.rect.y)
            nvgScale(vg, layout.sideScale, layout.sideScale)
            local root = side.root
            if root then
                -- detached子树不参与UI.Update；先更新真实布局后的滚动范围，不能用默认0范围裁掉输入。
                YGNodeCalculateLayout(root.node, 486, layout.sideHeight, YGDirectionLTR)
                local scroll = side.root == leftRoot and routeScroll or buffScroll
                if scroll and side.root == leftRoot then
                    scroll:UpdateContentSize()
                    local _, sy = scroll:GetScroll()
                    scroll:SetScroll(0, sy)
                end
                if side.root == leftRoot and routeScroll then
                    local viewport = routeScroll:GetLayout()
                    if reveal or lastRouteViewport ~= viewport.h then
                        routeScroll:SetScroll(0, math.max(0,
                            (snapshot.floor - 1) * 88 - viewport.h * 0.5 + 36))
                    end
                    lastRouteViewport = viewport.h
                end
                Surface.draw(root, vg, 486, layout.sideHeight)
                if side.root == rightRoot and buffScroll and not collapsed then
                    -- 新建/译文Label在真实Render时才测得多行高度；先测字后更新范围，
                    -- 不用初始化的一行高度提前钳制旧sy，收起状态完全不更新范围。
                    YGNodeCalculateLayout(root.node, 486, layout.sideHeight, YGDirectionLTR)
                    buffScroll:UpdateContentSize()
                    local _, sy = buffScroll:GetScroll()
                    buffScroll:SetScroll(0, sy)
                end
            end
        end)
    end
end

function Sidebar.drawConfirmation(vg, width, height)
    ensureRoots()
    if confirmTitle then confirmTitle:SetText(text("确认撤退？")) end
    if confirmNote then confirmNote:SetText(text("本层进度将丢失")) end
    if confirmRetreat then confirmRetreat:SetText(text("撤退")) end
    if confirmCancel then confirmCancel:SetText(text("取消")) end
    local dialog = Layout.confirm(Layout.compute(width, height))
    withState(vg, function()
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, width, height)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
        nvgFill(vg)
        nvgTranslate(vg, dialog.frame.x, dialog.frame.y)
        nvgScale(vg, dialog.scale, dialog.scale)
        local root = confirmRoot
        if root then Surface.draw(root, vg, 560, 280) end
    end)
end

-- 单调版本让宿主按压快照识别收起→展开的 ABA；不触碰玩法会话或择契身份。
function Sidebar.getPresentationKey()
    return tostring(presentationVersion) .. ":" .. tostring(collapsed)
end

function Sidebar.isCollapsed()
    return collapsed
end

function Sidebar.toggleCollapsed()
    ensureRoots()
    drag = nil
    collapsed = not collapsed
    presentationVersion = presentationVersion + 1
    if buffScroll then buffScroll:SetVisible(not collapsed) end
    if ruleNote then ruleNote:SetVisible(not collapsed) end
    if collapsedSpace then collapsedSpace:SetVisible(collapsed) end
    if toggleButton then toggleButton:SetText(text(collapsed and "展开" or "收起")) end
    return collapsed
end

local function widgetHit(widget, x, y)
    if not widget then return false end
    local r = widget:GetAbsoluteLayout()
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

function Sidebar.handleClick(x, y, width, height)
    local layout = Layout.compute(width, height)
    if Layout.panelAt(layout, x, y) ~= "right" then return nil end
    local dx, dy = Layout.toSide(layout, "right", x, y)
    if not lastSnapshot.inputModal and widgetHit(toggleButton, dx, dy) then return "toggle_buffs" end
    if not lastSnapshot.inputModal and (lastSnapshot.pendingChoices or 0) > 0
        and lastSnapshot.phase == "battle" and widgetHit(pendingButton, dx, dy) then
        return "resume_pick"
    end
    if action and not lastSnapshot.inputModal and widgetHit(actionButton, dx, dy) then return action end
    return nil
end

function Sidebar.handleScroll(wheel, x, y, width, height)
    local layout = Layout.compute(width, height)
    local side = Layout.panelAt(layout, x, y)
    local scroll = side == "left" and routeScroll or (side == "right" and not collapsed and buffScroll or nil)
    if scroll then
        local dx, dy = Layout.toSide(layout, side, x, y)
        if widgetHit(scroll, dx, dy) then scroll:ScrollBy(0, -wheel * 110) end
    end
    return true
end

function Sidebar.dragBegin(x, y, width, height)
    drag = nil
    local layout = Layout.compute(width, height)
    local side = Layout.panelAt(layout, x, y)
    local scroll = side == "left" and routeScroll or (side == "right" and not collapsed and buffScroll or nil)
    if scroll then
        local dx, dy = Layout.toSide(layout, side, x, y)
        if widgetHit(scroll, dx, dy) then
            drag = { scroll = scroll, side = side, lastY = y, layoutW = width, layoutH = height }
        end
    end
end

function Sidebar.dragMove(x, y, width, height)
    if not drag then return end
    if width ~= drag.layoutW or height ~= drag.layoutH then drag = nil return end
    local layout = Layout.compute(width, height)
    drag.scroll:ScrollBy(0, (drag.lastY - y) / layout.sideScale)
    drag.lastY = y
end

function Sidebar.dragEnd()
    drag = nil
end

function Sidebar.reset()
    drag, action = nil, nil
    collapsed = false
    presentationVersion = presentationVersion + 1
    if buffScroll then buffScroll:SetVisible(true) end
    if ruleNote then ruleNote:SetVisible(true) end
    if collapsedSpace then collapsedSpace:SetVisible(false) end
    if toggleButton then toggleButton:SetText(text("收起")) end
    lastSnapshot = {}
    lastFloor, lastWave, lastPhase, lastLanguage, lastBuffKey = 0, 0, "", "", ""
    lastRouteViewport = 0
    if routeScroll then routeScroll:SetScroll(0, 0) end
    if buffScroll then buffScroll:SetScroll(0, 0) end
end

-- 仅销毁自己拥有的树；共享Surface由宿主在全部塔UI销毁后shutdown。
function Sidebar.destroy()
    Sidebar.reset()
    if leftRoot then leftRoot:Destroy() end
    if rightRoot then rightRoot:Destroy() end
    if confirmRoot then confirmRoot:Destroy() end
    leftRoot, rightRoot, confirmRoot = nil, nil, nil
    routeScroll, buffScroll, buffContent, collapsedSpace = nil, nil, nil, nil
    toggleButton = nil
    floorLabel, waveLabel, buffTitle, routeTitle, routeNote, ruleNote = nil, nil, nil, nil, nil, nil
    actionButton, pendingButton, confirmRetreat, confirmCancel, confirmTitle, confirmNote = nil, nil, nil, nil, nil, nil
    nodes, nodeLabels = {}, {}
end

return Sidebar
