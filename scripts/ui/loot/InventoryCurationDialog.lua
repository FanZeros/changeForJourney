-- 一键优选展示与手势。只提交服务端 token，不生成名单，不修改装备/存档。
-- UI 组件沿用 SweepDialog 的 DesignWidgetSurface；宿主仍持有整次输入与绘制层级。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local Store = require("core.PlayerStore")
local Text = require("core.I18nInventoryCuration")
local I18n = require("core.I18n")
local EquipmentSystem = require("systems.EquipmentSystem")
local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")
local M = {}
local PREVIEW, APPLY, CANCEL = "PreviewInventoryCuration", "ApplyInventoryCuration", "CancelInventoryCuration"
local S = { open = false, source = "", phase = "idle", generation = 0, requestId = 0,
    token = nil, preview = {}, reason = "", started = 0, revisions = {} }
local host = {} ---@type table
local press = nil ---@type table?
local root = nil ---@type Panel?
local title = nil ---@type Label?
local body = nil ---@type Label?
local status = nil ---@type Label?
local metrics = {} ---@type Label[]
local confirm = nil ---@type Button?
local cancel = nil ---@type Button?
local presented = nil ---@type table?
local W, H = 900, 800
local C = { bone = {244,237,224,255}, gold = {231,192,116,255}, dim = {184,173,153,255} }
local keys = { "equipment", "lootbox", "heroes" }
local function now() return time and time.elapsedTime or 0 end
local function send(action, params)
    return require("runtime.GameAction").sendAction(action, params)
end
local function cancelToken(token)
    if token ~= nil then send(CANCEL, { token = token }) end
end
local function changed()
    for _, key in ipairs(keys) do
        if S.revisions[key] ~= Store.GetRevision(key) or S.revisions[key .. "Ref"] ~= Store.Get(key) then return true end
    end
    return false
end
local function snapshot()
    for _, key in ipairs(keys) do
        S.revisions[key], S.revisions[key .. "Ref"] = Store.GetRevision(key), Store.Get(key)
    end
end
local function invalidate()
    local token = S.token
    S.token, S.phase, S.reason = nil, "invalid", "数据已改变，请重新预览后确认。"
    S.generation = S.generation + 1
    if press then press.cancelled = true end
    cancelToken(token)
end
function M.bindHost(options) host = options or {} end
function M.isOpen() return S.open end
function M.hasPress() return press ~= nil end
function M.close()
    local token = S.token
    S.open, S.token, presented = false, nil, nil
    S.generation = S.generation + 1
    if press then press.cancelled = true end
    cancelToken(token)
end
-- 仅释放自己的 Yoga 树；Surface/UI 为其他混合弹窗共享，不能全局 Shutdown。
-- 保留取消的按压墓碑，让 Stop/清档前的同源 Up 不能穿透到新页面。
function M.reset()
    M.close()
    if root then root:Destroy() end
    root, title, body, status, confirm, cancel = nil, nil, nil, nil, nil, nil
    metrics, S.preview, S.revisions, host = {}, {}, {}, {}
    S.phase, S.reason, S.source = "idle", "", ""
end
function M.cancelSource(source)
    if S.open and S.source == source then M.close() end
end
local function requestPreview()
    local token = S.token
    S.token, S.phase, S.reason, S.preview = nil, "loading", "", {}
    S.generation, S.requestId = S.generation + 1, S.requestId + 1
    S.started = now()
    if press then press.cancelled = true end
    snapshot()
    cancelToken(token)
    local requestId = S.requestId
    local ok, handled = pcall(send, PREVIEW, { requestId = requestId })
    if not ok or not handled then
        if S.open and S.requestId == requestId then
            S.phase, S.reason = "invalid", "优选失败，未移动装备，请重新预览。"
        end
    end
end
function M.open(source)
    if S.open then return false end
    if host.blocked and host.blocked() then return false end
    -- 输入回调中初始化共享UI上下文，不能首度在NanoVGRender内变更render order。
    Surface.init()
    S.open, S.source = true, source
    requestPreview()
    return true
end
-- Update 与 Render 都观测；瞬时遮挡/关闭/ABA 后不复活旧 Down。
function M.observe()
    if press and host.frameKey and press.frame ~= host.frameKey() then press.cancelled = true end
    if not S.open then return end
    if (host.blocked and host.blocked()) or (host.sourceValid and not host.sourceValid(S.source)) then
        M.close(); return
    end
    if (S.phase == "ready" or S.phase == "loading") and changed() then invalidate() end
    if S.phase == "loading" and now() - S.started > 15 then invalidate() end
end
function M.onActionResult(data)
    local action = data.action
    if action ~= PREVIEW and action ~= APPLY and action ~= CANCEL then return false end
    if action == CANCEL then return true end
    if action == PREVIEW and (not S.open or S.phase ~= "loading" or data.requestId ~= S.requestId) then
        if data.success then cancelToken(data.token) end
        return true
    end
    if action == APPLY and (not S.open or S.phase ~= "applying" or data.requestId ~= S.requestId) then return true end
    M.observe()
    if not S.open then
        if action == PREVIEW and data.success then cancelToken(data.token) end
        return true
    end
    if action == PREVIEW and S.phase ~= "loading" then cancelToken(data.token); return true end
    S.generation = S.generation + 1
    if press then press.cancelled = true end
    if data.success ~= true then
        S.token, S.phase = nil, "invalid"
        S.reason = (data.reason == "save_failed" or data.reason == "整理存档失败，可重试")
            and "存档失败，未移动装备，请重试。"
            or data.reason == "整理预览已失效，请重新预览" and "数据已改变，请重新预览后确认。"
            or "优选失败，未移动装备，请重新预览。"
        return true
    end
    S.preview = data
    if action == PREVIEW then
        S.token, S.phase = data.token, "ready"
        if not S.token then invalidate() end
    else
        S.token, S.phase = nil, "done"
        S.reason = "整理完成：移入 %d 件，转存 %d 件"
    end
    return true
end
local function createLabel(size, color, height)
    return UI.Label { text = "", width = "100%", height = height, fontSize = size,
        fontFamily = "sans", fontColor = color, whiteSpace = "normal", wordBreak = "break-word",
        lineHeight = 1.2, verticalAlign = "middle", pointerEvents = "none" }
end
local function ensureTree()
    if root then return end
    Surface.init()
    title = createLabel(28, C.gold, 60)
    body = createLabel(18, C.dim, 340)
    status = createLabel(24, C.gold, 78)
    local countRow = UI.Panel { width = "100%", height = 95, flexDirection = "row", gap = 10 }
    for i = 1, 3 do
        local value = createLabel(20, C.bone, 95)
        value:SetStyle({ width = 262, textAlign = "center", backgroundColor = {42,34,27,255},
            borderWidth = 1, borderColor = {88,69,43,255}, borderRadius = 8 })
        metrics[i] = value
        countRow:AddChild(value)
    end
    confirm = UI.Button { width = 395, height = 76, text = "", fontSize = 28, textColor = C.bone,
        backgroundColor = {82,62,33,255}, borderColor = C.gold, borderWidth = 1, borderRadius = 8 }
    cancel = UI.Button { width = 395, height = 76, text = "", fontSize = 28, textColor = C.bone,
        backgroundColor = {43,36,29,255}, borderColor = {135,99,49,255}, borderWidth = 1, borderRadius = 8 }
    root = UI.Panel { width = W, height = H, padding = 40, gap = 16,
        backgroundColor = {25,22,19,255}, borderWidth = 3, borderColor = {135,99,49,255}, borderRadius = 18,
        children = {title, countRow, body, status,
            UI.Panel { height = 76, width = "100%", flexDirection = "row", gap = 24, children = {cancel, confirm} }} }
end
local function layout(width, height)
    local scale = math.min(1, (width - 32) / W, (height - 32) / H)
    scale = math.max(0.01, scale)
    return (width - W * scale) * 0.5, (height - H * scale) * 0.5, scale
end
function M.draw(vg, width, height)
    M.observe()
    if not S.open then return end
    ensureTree()
    title:SetText(Text.text("优选预览"))
    local p = S.preview
    local countKeys = {"移入仓库：%d 件", "转存遗匣：%d 件", "原位保护：%d 件"}
    local values = {p.moveInCount or 0, p.moveOutCount or 0, p.protectedCount or 0}
    for i = 1, 3 do metrics[i]:SetText(Text.text(countKeys[i], values[i])) end
    body:SetText(Text.text("仓库容量：%d 件", EquipmentSystem.MAX_INVENTORY) .. "\n"
        .. Text.text("同部位、同类型装备按通用评分优选，不代表特定英雄的最佳配装。") .. "\n"
        .. Text.text("整理全部仓库与遗匣，不受筛选或排序影响。仓库中的已穿戴、锁定、套装、投入、腐化及待洗练装备原位保护。") .. "\n"
        .. Text.text("只转存，不分解。整理转存到遗匣的装备受保护，不参与回收。"))
    local busy = S.phase == "loading" or S.phase == "applying"
    local noChange = S.phase == "ready" and values[1] + values[2] == 0
    local caption = S.phase == "loading" and "正在生成预览…"
        or S.phase == "applying" and "正在整理…" or noChange and "没有需要移动的装备" or S.reason
    status:SetText(S.phase == "done" and Text.text(caption, values[1], values[2]) or Text.text(caption))
    confirm:SetDisabled(busy or noChange or S.phase == "done")
    confirm:SetText(Text.text(S.phase == "invalid" and "重新预览" or busy and "正在整理…" or "确认优选"))
    cancel:SetText(Text.text(S.phase == "done" and "关闭" or "取消"))
    local tree = root
    if not tree then return end
    local x, y, scale = layout(width, height)
    nvgSave(vg)
    nvgBeginPath(vg); nvgRect(vg, 0, 0, width, height)
    nvgFillColor(vg, nvgRGBA(0,0,0,195)); nvgFill(vg)
    nvgTranslate(vg, x, y); nvgScale(vg, scale, scale)
    Surface.draw(tree, vg, W, H)
    nvgRestore(vg)
    presented = {generation = S.generation, language = I18n.get(), width = width, height = height}
end
local function hit(x, y, width, height)
    local ox, oy, scale = layout(width, height)
    local dx, dy = (x - ox) / scale, (y - oy) / scale
    if not root or not presented or presented.generation ~= S.generation
        or presented.language ~= I18n.get() or presented.width ~= width or presented.height ~= height then return nil end
    for _, entry in ipairs({{name="cancel", widget=cancel}, {name="confirm", widget=confirm}}) do
        local bounds = entry.widget:GetAbsoluteLayout()
        if dx >= bounds.x and dx <= bounds.x + bounds.w and dy >= bounds.y and dy <= bounds.y + bounds.h then
            return entry.name
        end
    end
    return nil
end
-- 物理框架签名包括 DPR/letterbox；变换恢复也不恢复旧按压。
function M.pointer(kind, button, x, y, source, width, height, frameKey)
    M.observe()
    if not S.open and not press then return false end
    if kind == "down" then
        if press then return true end
        if not S.open then return true end
        if button ~= MOUSEB_LEFT then return true end
        press = {source = source, x = x, y = y, w = width, h = height, frame = frameKey,
            generation = S.generation, language = I18n.get(), target = hit(x,y,width,height), cancelled = false}
        if host.cancelUnderlying then host.cancelUnderlying() end
        return true
    end
    if not press then return S.open end
    local p = press
    if p.source ~= source then return true end
    if p.w ~= width or p.h ~= height or p.frame ~= frameKey or p.generation ~= S.generation
        or p.language ~= I18n.get() or not S.open or math.abs(x-p.x) + math.abs(y-p.y) >= 15 then
        p.cancelled = true
    end
    if kind ~= "up" or button ~= MOUSEB_LEFT then return true end
    press = nil
    if p.cancelled or not p.target or p.target ~= hit(x,y,width,height) then return true end
    if p.target == "cancel" then M.close(); return true end
    if S.phase == "invalid" then requestPreview(); return true end
    if S.phase ~= "ready" or not S.token then return true end
    if (S.preview.moveInCount or 0) + (S.preview.moveOutCount or 0) == 0 then return true end
    local token = S.token
    S.phase, S.started, S.requestId = "applying", now(), S.requestId + 1
    S.generation = S.generation + 1
    local ok, handled = pcall(send, APPLY, {token = token, requestId = S.requestId})
    if not ok or not handled then invalidate() end
    return true
end
function M.cancelPress()
    if press then press.cancelled = true end
end
function M.consumeScroll()
    M.observe()
    if S.open or press then M.cancelPress(); return true end
    return false
end
-- 老页面只增加轻量入口，按钮绝不接管既有筛选、拖拽或右键。
function M.drawEntry(vg, cx, cy, width, height)
    DarkIcon.drawNine(vg, "btn", cx-width*0.5, cy-height*0.5, width, height, {accent="gold"})
    local caption = Text.text("一键优选")
    nvgFontFace(vg, "sans"); nvgFontSize(vg, 34)
    local captionWidth = nvgTextBounds(vg,0,0,caption)
    local size = math.min(34, 34 * (width-24) / math.max(1, captionWidth))
    DrawUtil.drawTextStroke(vg,cx,cy,caption,size,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE,244,237,224,2)
end
return M
