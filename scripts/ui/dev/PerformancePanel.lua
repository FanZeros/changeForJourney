-- 性能诊断：沿用 scaffold-2d 的组件树，通过 DesignWidgetSurface 复用宿主帧。
-- 宿主负责逻辑坐标转换、模态输入优先级及 Update/Draw；本模块不订阅事件。
-- 不访问玩家档、不上传。关闭只隐藏面板，采集生命周期由 Monitor 独立持有。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local Panel = {}

---@class PerformancePanelMonitor
---@field start fun()
---@field stop fun()
---@field isEnabled fun(): boolean
---@field mark fun()
---@field snapshot fun(): table
---@field getReport fun(): string
---@field export fun(): boolean, string
---@field excludeCurrent? fun(reason: string)

---@type PerformancePanelMonitor?
local monitor = nil
---@type Panel?
local root = nil
---@type Panel?
local card = nil
---@type Label?
local summary = nil
---@type Label?
local status = nil
---@type Label?
local pageCaption = nil
---@type Label[]
local bodyLabels = {}
---@type table<string, Button>
local buttons = {}
---@type table?
local press = nil
---@type table<string|number, boolean>
local activePointers = {}
local S = { open = false, enabled = false, timer = 0, page = 1, report = "", reportMode = false,
    width = 0, height = 0, rows = 1, columns = 20, presented = false, generation = 0,
    summaryText = "尚未开始采集", notice = "报告仅保存在本机，不会自动上传。" }
---@type string[]
local details = { "开始采集后关闭本面板，复现卡顿，再返回生成报告。" }
---@type string[]
local pages = { "" }
local C = { bone = {244,237,224,255}, gold = {231,192,116,255}, dim = {184,173,153,255},
    surface = {25,22,19,255}, raised = {42,34,27,255}, border = {135,99,49,255} }
---@type NVGContextWrapper?
local measureContext = nil
local bodyFont, bodyWidth = 20, 800
local summaryFont, summaryWidth = 18, 800
local treeButtonH, treeFont = 70, 24
local initialized = false

local function number(value)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return 0 end
    return value
end
local function integer(value) return string.format("%.0f", number(value)) end
local function decimal(value) return string.format("%.1f", number(value)) end
local function notice(text)
    S.notice = text
    if status then status:SetText(text) end
end
local function getMonitor()
    if monitor then return monitor end
    -- init 不要求 core 文件已落地；只在用户打开/操作面板时解析，可在之后重试。
    local ok, result = pcall(require, "core.PerformanceMonitor")
    if ok and type(result) == "table" and type(result.start) == "function"
        and type(result.stop) == "function" and type(result.isEnabled) == "function"
        and type(result.mark) == "function" and type(result.snapshot) == "function"
        and type(result.getReport) == "function" and type(result.export) == "function" then
        monitor = result --[[@as PerformancePanelMonitor]]
        return monitor
    end
    notice("性能采集模块尚未就绪，请稍后重新打开。")
    return nil
end

-- 只在数据更新/resize时测量宿主字体，不在每帧排序或编码。无法测量时保守按字符分块。
local function wrap(text, columns, font, width)
    local lines, line, used = {}, {}, 0
    local context = measureContext
    if context then
        nvgSave(context); nvgFontFace(context, "sans"); nvgFontSize(context, UI.Theme.FontSize(font or bodyFont))
    end
    local index = 1
    while index <= #text do
        local byte = text:byte(index)
        local length = byte < 0x80 and 1 or byte < 0xE0 and 2 or byte < 0xF0 and 3 or 4
        local char = text:sub(index, index + length - 1)
        if char == "\n" then
            lines[#lines + 1] = table.concat(line)
            line, used = {}, 0
        elseif char ~= "\r" then
            char = char == "\t" and "    " or char
            local cost = #char == 4 and char == "    " and 4 or 1
            local exceeded = used + cost > columns
            if context then exceeded = nvgTextBounds(context, 0, 0, table.concat(line) .. char) > (width or bodyWidth) end
            if exceeded and #line > 0 then
                lines[#lines + 1] = table.concat(line)
                line, used = {}, 0
            end
            line[#line + 1] = char
            used = used + cost
        end
        index = index + length
    end
    lines[#lines + 1] = table.concat(line)
    if context then nvgRestore(context) end
    return lines
end

local function displayPage()
    local current = pages[S.page] or ""
    local index = 1
    for line in (current .. "\n"):gmatch("(.-)\n") do
        if bodyLabels[index] then bodyLabels[index]:SetText(line) end
        index = index + 1
    end
    for i = index, #bodyLabels do bodyLabels[i]:SetText("") end
    if pageCaption then
        pageCaption:SetText((S.reportMode and "报告 " or "概览 ") .. S.page .. " / " .. #pages)
    end
    if buttons.previous then buttons.previous:SetDisabled(S.page <= 1) end
    if buttons.next then buttons.next:SetDisabled(S.page >= #pages) end
end
local function paginate(reset)
    local text = S.reportMode and S.report or table.concat(details, "\n")
    local lines = wrap(text, S.columns)
    pages = {}
    for first = 1, #lines, S.rows do
        pages[#pages + 1] = table.concat(lines, "\n", first, math.min(#lines, first + S.rows - 1))
    end
    if #pages == 0 then pages[1] = "暂无数据" end
    S.page = reset and 1 or math.max(1, math.min(S.page, #pages))
    displayPage()
end
local function refreshSummary()
    local m = getMonitor()
    if not m then return end
    local ok, snapshot = pcall(m.snapshot)
    if not ok or type(snapshot) ~= "table" then notice("读取性能概览失败，已有数据未清除。"); return end
    local enabledOK, enabled = pcall(m.isEnabled)
    S.enabled = enabledOK and enabled == true
    local frame = snapshot.frameMs or {}
    local slow = snapshot.slowFrames or {}
    S.summaryText = (S.enabled and "采集中" or "已停止") .. "  ·  " .. decimal(snapshot.elapsedSeconds)
        .. " 秒 / " .. integer(snapshot.frames) .. " 帧 / " .. decimal(snapshot.fps) .. " FPS\n"
        .. "帧间隔 ms  P50 " .. decimal(frame.p50) .. "  P95 " .. decimal(frame.p95)
        .. "  P99 " .. decimal(frame.p99) .. "\n本轮最大 " .. decimal(frame.max) .. " ms\n"
        .. "慢帧 >33/50/100ms  " .. integer(slow.over33) .. "/" .. integer(slow.over50)
        .. "/" .. integer(slow.over100) .. "  ·  Lua " .. decimal(number(snapshot.luaMemoryKB) / 1024) .. " MB\n"
        .. "资源 " .. decimal(number(snapshot.resourceMemoryBytes) / 1048576) .. " MB  ·  批次 "
        .. integer(snapshot.batches) .. "  ·  图元 " .. integer(snapshot.primitives)
    if summary then summary:SetText(table.concat(wrap(S.summaryText, 32, summaryFont, summaryWidth), "\n")) end
    if buttons.start then buttons.start:SetText(S.enabled and "重新开始" or "开始采集") end
    if buttons.stop then buttons.stop:SetDisabled(not S.enabled) end
    if buttons.mark then buttons.mark:SetDisabled(not S.enabled) end
    details = { "区段 CPU / 墙钟耗时（ms；墙钟并非 GPU 时间）" }
    for _, section in ipairs(snapshot.sections or {}) do
        details[#details + 1] = tostring(section.name or "未知区段") .. "  ×" .. integer(section.calls)
            .. "  CPU " .. decimal(section.totalCpuMs) .. " / 峰值 " .. decimal(section.maxCpuMs)
        details[#details + 1] = "  墙钟 " .. decimal(section.totalWallMs) .. " / 峰值 " .. decimal(section.maxWallMs)
    end
    details[#details + 1] = "最近慢帧（完整数据见报告）"
    local recent = snapshot.recentSlow or {}
    for i = math.max(1, #recent - 3), #recent do
        local entry = recent[i]
        details[#details + 1] = "#" .. integer(entry.frame) .. "  " .. decimal(entry.intervalMs)
            .. "ms  " .. tostring(entry.context or "")
        for j, top in ipairs(entry.top or {}) do
            if j > 3 then break end
            details[#details + 1] = "  " .. tostring(top.name or "") .. " CPU " .. decimal(top.cpuMs)
                .. " / 墙钟 " .. decimal(top.wallMs)
        end
    end
    details[#details + 1] = "标记 " .. #(snapshot.marks or {}) .. " 次；排除后台间隔 "
        .. integer(snapshot.excludedGaps) .. "；排除面板帧 " .. integer(snapshot.excludedPanelFrames)
    if not S.reportMode then paginate(false) end
end
local function stopForReport()
    local m = getMonitor()
    if not m then return nil end
    local ok = pcall(m.stop)
    if not ok then notice("停止采集失败，未生成或导出报告。"); return nil end
    S.enabled = false
    return m
end
local function generateReport()
    local m = stopForReport()
    if not m then return nil end
    local ok, text = pcall(m.getReport)
    if not ok or type(text) ~= "string" or #text == 0 then
        notice("报告生成失败；采集已停止，数据仍保留。")
        return nil
    end
    S.report, S.reportMode = text, true
    refreshSummary()
    paginate(true)
    return text
end
local function action(name)
    if name == "close" then Panel.close(); return end
    if name == "previous" or name == "next" then
        S.page = math.max(1, math.min(#pages, S.page + (name == "next" and 1 or -1)))
        displayPage()
        return
    end
    if name == "generate" then
        if generateReport() then notice("已停止采集并生成报告，可翻页截图、复制或保存本地。") end
        return
    end
    if name == "copy" then
        local text = generateReport()
        if not text then return end
        -- 必须在同一个 Up 用户手势栈里调用；包含方法查找，绑定缺失也会落入 pcall。
        local ok, confirmed = pcall(function()
            if not ui or type(ui.SetClipboardText) ~= "function" then return false end
            ui.useSystemClipboard = true
            ui:SetClipboardText(text)
            -- void SetClipboardText 返回不代表成功：只有系统回读完全相等才确认。
            local read = ui["GetClipboardText"]
            return type(read) == "function" and read(ui) == text
        end)
        if ok and confirmed == true then
            notice("已复制报告到系统剪贴板。")
        else
            notice("无法确认系统剪贴板写入；请翻页截图或保存本地。")
        end
        return
    end
    if name == "save" then
        local text = generateReport()
        if not text then return end
        local m = monitor
        if not m then return end
        local ok, saved, path = pcall(m.export)
        if ok and saved == true and type(path) == "string" and #path > 0 then
            notice("已保存本地：" .. path .. "（网页刷新可能丢失）")
        else
            notice("保存失败：" .. (ok and type(path) == "string" and path or "本地文件不可用")
                .. "；可翻页截图或复制。")
        end
        return
    end
    local m = getMonitor()
    if not m then return end
    if name == "start" then
        local ok = pcall(m.start)
        if ok then
            S.report, S.reportMode, S.timer = "", false, 0
            refreshSummary()
            paginate(true)
            notice("已重新开始采集（重置旧数据）。关闭面板后复现卡顿，再返回生成报告。")
        else notice("开启采集失败，未改变玩家状态。") end
    elseif name == "stop" then
        if pcall(m.stop) then refreshSummary(); notice("采集已停止；数据保留，可生成报告。")
        else notice("停止采集失败，请重试。") end
    elseif name == "mark" then
        local ok, enabled = pcall(m.isEnabled)
        if not ok or not enabled then notice("请先开启采集再标记卡顿。"); return end
        if pcall(m.mark) then notice("已标记最近完成的有效帧；不记录玩家数据。")
        else notice("标记失败，请重试。") end
    end
end
local function label(text, size, color, height, nowrap)
    return UI.Label { text = text, width = "100%", height = height, fontSize = size,
        fontFamily = "sans", fontWeight = "normal", fontColor = color,
        whiteSpace = nowrap and "nowrap" or "normal", wordBreak = "break-word",
        lineHeight = 1.2, verticalAlign = "top", pointerEvents = "none" }
end
local function button(name, text)
    local widget = UI.Button { text = text, flexGrow = 1, flexShrink = 1, flexBasis = 0,
        height = treeButtonH, fontSize = treeFont, padding = 4, fontFamily = "sans", fontWeight = "normal", textColor = C.bone,
        backgroundColor = {43,36,29,255}, hoverBackgroundColor = {63,48,30,255},
        pressedBackgroundColor = {82,62,33,255}, disabledBackgroundColor = {32,29,25,255},
        disabledTextColor = {115,105,88,255}, borderColor = C.border, borderWidth = 1, borderBottomWidth = 1, borderRadius = 8,
        pointerEvents = "none" }
    buttons[name] = widget
    return widget
end
function Panel.init()
    if initialized then return end
    Surface.init()
    initialized = true
end


-- 不在 Render 首次初始化 Surface：init 在宿主初始化或快捷键 open 执行。
function Panel.open()
    Panel.init()
    if S.open then return end
    S.open, S.presented, S.timer = true, false, 0
    S.generation = S.generation + 1
    Panel.resetPointer()
    local m = getMonitor()
    if m then
        local ok, enabled = pcall(m.isEnabled)
        if ok and enabled and type(m.excludeCurrent) == "function" then
            pcall(m.excludeCurrent, "panel")
        end
    end
    refreshSummary()
end
function Panel.close()
    S.open, S.presented = false, false
    S.generation = S.generation + 1
    -- 外部关闭时仍吞掉旧按压尾部；不调用 Monitor.stop。
    if press then press.cancelled = true end
end
function Panel.isOpen() return S.open end
function Panel.resetPointer()
    press, activePointers = nil, {}
    S.presented = false
end
function Panel.update(dt)
    if not S.open then return end
    S.timer = S.timer + math.max(0, number(dt))
    if S.timer < 1 then return end
    S.timer = S.timer % 1
    refreshSummary()
end

local function resize(width, height)
    if root and S.width == width and S.height == height then return end
    S.width, S.height, S.presented = width, height, false
    S.generation = S.generation + 1
    if press then press.cancelled = true end
    -- Runtime内置UI可能早于参考副本：不事后改Label fontSize/whiteSpace，避免旧缓存保留旧字高/flow。
    -- 仅首帧/resize重建，报告、采集状态和当前页保留；命中继续直接读实际绝对布局。
    if root then root:Destroy() end
    buttons, bodyLabels = {}, {}
    local w, h = math.min(960, width - 24), math.min(1450, height - 24)
    local unit = math.max(0.35, math.min(1, w / 960, h / 850))
    local padding, gap = math.max(10, 28*unit), math.max(6, 12*unit)
    treeButtonH, treeFont = math.max(36, 70*unit), math.max(10, 22*unit)
    bodyFont, summaryFont = math.max(10, 20*unit), math.max(10, 18*unit)
    bodyWidth = math.max(12, w-padding*2-24)
    summaryWidth = bodyWidth
    local infoFont = math.max(10,18*unit)
    local helpText = "F8 打开/关闭；Esc 关闭。\n开始采集 → 关闭本面板复现卡顿 → F8 返回生成报告。\n关闭不会停止采集；生成、复制、保存会先停止。"
    local helpLines = wrap(helpText, 28, infoFont, bodyWidth)
    local summaryLines = wrap(S.summaryText, 32, summaryFont, summaryWidth)
    local helpH = (#helpLines+0.5)*UI.Theme.FontSize(infoFont)*1.3
    local summaryH = (math.max(6,#summaryLines)+0.5)*UI.Theme.FontSize(summaryFont)*1.3+16
    local statusH = 3.5*UI.Theme.FontSize(infoFont)*1.3
    local help = label(table.concat(helpLines,"\n"),infoFont,C.dim,helpH)
    summary = label(table.concat(summaryLines,"\n"),summaryFont,C.bone,summaryH)
    local summaryBox = UI.Panel { width="100%",height=summaryH+16,padding=8,backgroundColor=C.raised,
        borderRadius=8,children={summary} }
    status = label(S.notice,infoFont,C.gold,statusH)
    local title = UI.Label {text="性能诊断",height=treeButtonH,fontSize=math.max(14,32*unit),
        flexGrow=1,flexShrink=1,flexBasis=0,fontFamily="sans",fontWeight="normal",fontColor=C.gold,
        whiteSpace="nowrap",verticalAlign="middle",pointerEvents="none"}
    local close = button("close","关闭")
    close:SetStyle({flexGrow=0,flexBasis="auto",width=math.max(60,120*unit)})
    pageCaption = UI.Label {text="",height=treeButtonH,fontSize=math.max(10,20*unit),
        flexGrow=1,flexShrink=1,flexBasis=0,fontFamily="sans",fontWeight="normal",fontColor=C.dim,
        whiteSpace="nowrap",textAlign="center",verticalAlign="middle",pointerEvents="none"}
    local lineH = UI.Theme.FontSize(bodyFont)*1.3
    local available = h-padding*2-gap*7-treeButtonH*4-helpH-(summaryH+16)-statusH-4
    S.rows = math.max(1,math.floor((available-24)/lineH))
    S.columns = math.max(6,math.floor(bodyWidth/UI.Theme.FontSize(bodyFont)))
    local body = UI.Panel {id="body",width="100%",flexGrow=1,flexBasis=0,flexShrink=1,
        padding=12,overflow="hidden",backgroundColor={18,16,14,255},borderRadius=8}
    for i=1,S.rows do
        local row=label("",bodyFont,C.bone,lineH,true)
        bodyLabels[i]=row;body:AddChild(row)
    end
    card = UI.Panel {width=w,height=h,position="absolute",left=(width-w)*0.5,top=(height-h)*0.5,
        padding=padding,gap=gap,backgroundColor=C.surface,borderColor=C.border,borderWidth=2,borderRadius=18,
        children={
            UI.Panel {width="100%",height=treeButtonH,flexDirection="row",gap=gap,children={title,close}},
            help,summaryBox,
            UI.Panel {width="100%",height=treeButtonH,flexDirection="row",gap=gap,
                children={button("start",S.enabled and "重新开始" or "开始采集"),button("stop","停止"),button("mark","标记卡顿")}},
            UI.Panel {width="100%",height=treeButtonH,flexDirection="row",gap=gap,
                children={button("generate","生成报告"),button("copy","复制报告"),button("save","保存本地")}},
            status,body,
            UI.Panel {width="100%",height=treeButtonH,flexDirection="row",gap=gap,
                children={button("previous","上一页"),pageCaption,button("next","下一页")}},
        }}
    root = UI.Panel {width=width,height=height,backgroundColor={0,0,0,195},pointerEvents="none",children={card}}
    buttons.stop:SetDisabled(not S.enabled);buttons.mark:SetDisabled(not S.enabled)
    paginate(false)
end
---@param vg NVGContextWrapper
---@param logicalW number
---@param logicalH number
function Panel.draw(vg, logicalW, logicalH)
    if not S.open or not initialized or not vg or logicalW <= 24 or logicalH <= 24 then return end
    measureContext = vg
    resize(logicalW, logicalH)
    if not root then return end
    nvgSave(vg)
    Surface.draw(root, vg, logicalW, logicalH)
    nvgRestore(vg)
    S.presented = true
end
local function hit(x, y)
    if not S.presented then return nil end
    for name, widget in pairs(buttons) do
        if not widget:IsDisabled() then
            local bounds = widget:GetAbsoluteLayout()
            if bounds.w > 0 and bounds.h > 0 and x >= bounds.x and x <= bounds.x + bounds.w
                and y >= bounds.y and y <= bounds.y + bounds.h then return name end
        end
    end
    return nil
end
---@param kind "down"|"move"|"up"
---@param x number Host logical coordinates (not physical pixels)
---@param y number
---@param id "mouse"|integer Mouse is a distinct identity from every touch ID, including 0.
---@return boolean consumed
function Panel.handlePointer(kind, x, y, id)
    if not S.open and not press and next(activePointers) == nil then return false end
    if id ~= "mouse" and (type(id) ~= "number" or id % 1 ~= 0) then return true end
    if kind == "down" then
        if press or next(activePointers) ~= nil then
            if press then press.cancelled = true end
            activePointers[id] = true
            return true
        end
        if not S.open then return true end
        activePointers[id] = true
        press = { id = id, x = x, y = y, target = hit(x,y), generation = S.generation, cancelled = false }
        return true
    end
    local p = press
    if p and p.id == id then
        local dx, dy = x-p.x, y-p.y
        if not S.open or p.generation ~= S.generation or dx*dx + dy*dy > 12*12 then p.cancelled = true end
    end
    if kind ~= "up" then return true end
    activePointers[id] = nil
    if not p or p.id ~= id then return true end
    press = nil
    if p.cancelled or not p.target or p.target ~= hit(x,y) then return true end
    -- 所有按钮只在同源 Down→Up 后执行；复制不能延后到 update/draw。
    action(p.target)
    return true
end
return Panel
