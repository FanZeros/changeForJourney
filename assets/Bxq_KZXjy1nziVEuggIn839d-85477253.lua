-- ============================================================================
-- GMConsolePanel - GM 后台控制台面板
-- 入口：玩家信息界面的 GM 按钮（仅白名单玩家可见）
-- 坐标系: 设计分辨率 1080×2400，所有位置为中心点坐标
-- Tabs: [当前在线] [服务器] [玩家] [邮件] [日志]
-- ============================================================================

local cjson = cjson
local DrawUtil        = require("core.DrawUtil")
local BF              = require("systems.ButtonFeedback")
local ResourceDefs    = require("config.ResourceDefs")
local hitTest         = DrawUtil.hitTest

local Protocol = require("shared.Protocol")

-- 延迟获取 Client（避免循环依赖: Client→PlayerInfoPanel→GMConsolePanel→Client）
local Client_
local function getClient()
    if not Client_ then Client_ = require("network.Client") end
    return Client_
end

local GMConsolePanel = {}

-- ======================== 状态 ========================

local state = {
    open      = false,
    animTime  = 0,
    closing   = false,
    closeTime = 0,
    -- 当前选中的功能 tab (1=当前在线,2=服务器,3=玩家,4=邮件,5=日志)
    selectedTab = 1,
    -- 输入框内容 & 焦点
    inputUID   = "",
    inputParam = "",
    focusField = nil,  -- nil / "uid" / "param" / "mailTitle" / "mailContent" / "mailRewards" / "mailServerRange"
    cursorBlink = 0,
    -- 邮件编辑字段
    mailTitle   = "",
    mailContent = "",
    mailRewards = "diamond*100",  -- 格式: "编号*数量,编号*数量"
    mailServerRange = "",  -- 区服范围: "1-3" 或 "1,2,3" 或空(全服)
    -- 结果显示
    resultText = "",
    resultTimer = 0,
    -- 在线玩家列表（由 GM_SERVER_STATUS 响应填充）
    onlinePlayers = {},  -- { uid1, uid2, ... }
    onlineCount   = 0,
    -- 服务器状态数据
    serverInfo = nil,  -- { onlineCount, uptimeSeconds, maintenanceMode, ... }
    -- 日志数据
    logEntries = {},
    -- 查询结果
    queryResult = nil,
    -- 滚动偏移
    scrollY = 0,
    -- 请求中标记
    loading = false,
}

-- ======================== 面板配色（对齐 DebugPanel）========================

local BG_COLOR      = { 30, 30, 45, 220 }
local BORDER_COLOR  = { 100, 100, 120, 180 }
local TITLE_COLOR   = { 255, 200, 60, 255 }

-- ======================== 布局常量 ========================

local ANIM_OPEN_DUR  = 0.25
local ANIM_CLOSE_DUR = 0.15

-- 全屏黑色遮罩
local MASK_ALPHA = 160

-- 弹窗区域
local BG = {
    CX = 540, CY = 1100, W = 1000, H = 1600,
    RADIUS = 14,
}

-- 标题
local TTL = {
    X = 540, Y = 380, FONT = 48,
}

-- Tab 按钮区域
local TAB = {
    START_X = 100,
    Y = 470,
    W = 160, H = 60, GAP = 12,
    FONT = 30,
}

-- 内容区域起始
local CONTENT_TOP = 540
local CONTENT_BOTTOM = 1820
local CONTENT_LEFT = 100
local CONTENT_RIGHT = 980

-- 输入框
local INPUT = {
    W = 520, H = 66, R = 8,
    FONT = 32,
}

-- 操作按钮
local BTN = {
    W = 210, H = 68, R = 10,
    FONT = 32,
    SMALL_W = 150, SMALL_H = 56,
}

-- 列表项
local LIST_ITEM = {
    H = 80,
    GAP = 6,
}

-- ======================== Tab 定义 ========================

local TAB_NAMES = { "当前在线", "服务器", "玩家", "邮件", "日志" }
local TAB_ONLINE = 1
local TAB_SERVER = 2
local TAB_PLAYER = 3
local TAB_MAIL   = 4
local TAB_LOG    = 5

-- ============================================================================
-- 内部辅助
-- ============================================================================

local function showResult(text)
    state.resultText = text or ""
    state.resultTimer = 5.0
    print("[GMConsole] 结果: " .. state.resultText)
end

local function setFocus(field)
    state.focusField = field
    state.cursorBlink = 0
    if field then
        input:SetScreenKeyboardVisible(true)
    else
        input:SetScreenKeyboardVisible(false)
    end
end

--- UTF-8 安全删除最后一个字符
local function utf8RemoveLast(s)
    if #s == 0 then return s end
    local i = #s
    while i > 0 do
        local byte = s:byte(i)
        if byte < 0x80 or byte >= 0xC0 then
            return s:sub(1, i - 1)
        end
        i = i - 1
    end
    return ""
end

--- UTF-8 字符数（非字节数）
local function utf8Len(s)
    local count = 0
    local i = 1
    while i <= #s do
        local byte = s:byte(i)
        if byte < 0x80 then i = i + 1
        elseif byte < 0xE0 then i = i + 2
        elseif byte < 0xF0 then i = i + 3
        else i = i + 4 end
        count = count + 1
    end
    return count
end

--- 奖励类型映射 — 统一从 ResourceDefs 中央注册表获取

--- 解析奖励字符串 "1*1000,diamond*500,101*10" → { {type="gold",amount=1000}, {type="shard",heroId=1,amount=10}, ... }
--- 支持数字ID（如 "1"）、英文type（如 "diamond"）、英雄碎片编号（101-123 / shard_16 / h16）
local function normalizeRewardInput(str)
    if not str then return "" end
    return str:gsub("＊", "*"):gsub("×", "*"):gsub("，", ",")
end

local function parseRewards(str)
    local rewards = {}
    str = normalizeRewardInput(str)
    if str == "" then return rewards end
    for item in str:gmatch("[^,]+") do
        local t, a = item:match("^%s*([%w_]+)%s*[*xX]%s*(%d+)%s*$")
        if t and a then
            local reward = ResourceDefs.normalizeMailReward(t, tonumber(a))
            if reward then
                rewards[#rewards + 1] = reward
            end
        end
    end
    return rewards
end

--- 解析区服范围字符串 "1-3" 或 "1,2,3" → {1,2,3}；空字符串返回 nil（表示全服）
local function parseServerRange(str)
    if not str or str == "" then return nil end
    local ids = {}
    -- 支持 "1-3" 范围格式
    local rangeFrom, rangeTo = str:match("^%s*(%d+)%s*[%-~]%s*(%d+)%s*$")
    if rangeFrom and rangeTo then
        local from = tonumber(rangeFrom)
        local to   = tonumber(rangeTo)
        if from and to and from <= to then
            for i = from, to do
                ids[#ids + 1] = i
            end
        end
        return #ids > 0 and ids or nil
    end
    -- 支持 "1,2,3" 逗号分隔格式
    for item in str:gmatch("[^,]+") do
        local n = tonumber(item:match("^%s*(%d+)%s*$"))
        if n then
            ids[#ids + 1] = n
        end
    end
    return #ids > 0 and ids or nil
end

--- 绘制通用输入框（邮件页复用）
local function drawFieldBox(vg, label, value, x, y, w, h, focused, alpha)
    -- 标签
    nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(180, 180, 200, alpha))
    nvgText(vg, x, y - 4, label, nil)

    -- 输入框背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, INPUT.R)
    if focused then
        nvgFillColor(vg, nvgRGBA(50, 55, 80, alpha))
        nvgStrokeColor(vg, nvgRGBA(100, 180, 255, alpha))
    else
        nvgFillColor(vg, nvgRGBA(40, 40, 55, alpha))
        nvgStrokeColor(vg, nvgRGBA(80, 80, 100, alpha))
    end
    nvgFill(vg)
    nvgStrokeWidth(vg, focused and 2 or 1)
    nvgStroke(vg)

    -- 文字内容
    nvgFontSize(vg, INPUT.FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local display = value
    if display == "" and not focused then
        nvgFillColor(vg, nvgRGBA(100, 100, 120, alpha))
        display = "点击输入..."
    else
        nvgFillColor(vg, nvgRGBA(230, 230, 240, alpha))
    end
    -- 截断过长文本
    local maxChars = math.floor((w - 20) / 12)
    if #display > maxChars then
        display = display:sub(1, maxChars) .. "…"
    end
    nvgText(vg, x + 10, y + h * 0.5, display, nil)

    -- 光标
    if focused then
        local blinkOn = (math.floor(state.cursorBlink * 2) % 2 == 0)
        if blinkOn then
            local tw = nvgTextBounds(vg, 0, 0, value)
            local cx = math.min(x + 10 + tw, x + w - 10)
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx, y + 8)
            nvgLineTo(vg, cx, y + h - 8)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, alpha))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end
    end
end

--- 格式化时长（秒→可读字符串）
local function formatUptime(seconds)
    if not seconds or seconds <= 0 then return "0s" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format("%dh %dm", h, m)
    elseif m > 0 then
        return string.format("%dm %ds", m, s)
    else
        return string.format("%ds", s)
    end
end

--- 请求服务器状态（包含在线列表）
local function requestServerStatus()
    state.loading = true
    getClient().sendAction(Protocol.ACTION_TYPES.GM_SERVER_STATUS, {})
end

--- 请求操作日志
local function requestLogs()
    state.loading = true
    getClient().sendAction(Protocol.ACTION_TYPES.GM_QUERY_LOG, { count = 50 })
end

-- ============================================================================
-- Public API
-- ============================================================================

--- 初始化
function GMConsolePanel.init(vg)
    -- 订阅文本输入事件
    SubscribeToEvent("TextInput", "HandleGMConsoleTextInput")
    print("[GMConsolePanel] init OK")
end

--- 打开面板（必须通过服务端 GM 鉴权，禁止客户端直接调用绕过入口按钮）
function GMConsolePanel.open()
    if not getClient().isGM() then
        print("[GMConsolePanel] open() rejected: not GM")
        return
    end
    if state.open then return end
    state.open = true
    state.closing = false
    state.animTime = time.elapsedTime
    state.resultText = ""
    state.resultTimer = 0
    state.focusField = nil
    state.scrollY = 0
    -- 默认打开时请求在线状态
    autoRefreshTimer_ = 0
    requestServerStatus()
    print("[GMConsolePanel] 打开")
end

--- 关闭面板
function GMConsolePanel.close()
    if not state.open or state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    setFocus(nil)
    print("[GMConsolePanel] 关闭")
end

--- 是否打开
function GMConsolePanel.isOpen()
    return state.open
end

--- 服务端返回结果回调
function GMConsolePanel.onActionResult(data)
    if not state.open then return end
    if not data or not data.action then return end

    local act = data.action
    state.loading = false

    -- GM_SERVER_STATUS → 填充在线列表和服务器信息
    -- 服务端返回结构: { success=true, status={ onlinePlayers=[{uid,name,serverId,serverName}], onlineCount, ... } }
    if act == Protocol.ACTION_TYPES.GM_SERVER_STATUS then
        if data.success and data.status then
            local s = data.status
            -- 优先使用新的 onlinePlayers（含名称和区服），兼容旧 onlineUIDs
            if s.onlinePlayers then
                state.onlinePlayers = s.onlinePlayers
            elseif s.onlineUIDs then
                -- 兼容：旧格式转为新格式
                state.onlinePlayers = {}
                for _, uid in ipairs(s.onlineUIDs) do
                    state.onlinePlayers[#state.onlinePlayers + 1] = { uid = uid, name = "未知", serverName = "" }
                end
            else
                state.onlinePlayers = {}
            end
            state.onlineCount = s.onlineCount or #state.onlinePlayers
            state.serverInfo = {
                onlineCount = s.onlineCount or 0,
                uptimeSeconds = s.uptimeSeconds or 0,
                maintenanceMode = s.maintenanceMode or false,
                serverTime = s.serverTime or 0,
            }
            showResult("状态已刷新: " .. state.onlineCount .. " 人在线")
        else
            showResult("获取状态失败: " .. (data.reason or "未知"))
        end
        return
    end

    -- GM_QUERY_LOG → 填充日志
    if act == Protocol.ACTION_TYPES.GM_QUERY_LOG then
        if data.success then
            state.logEntries = data.logs or {}
            showResult("日志已加载: " .. #state.logEntries .. " 条")
        else
            showResult("获取日志失败: " .. (data.reason or "未知"))
        end
        return
    end

    -- GM_QUERY_PLAYER → 玩家查询结果
    -- 服务端返回结构: { success=true, playerInfo={ uid, nickname, level, ... } }
    if act == Protocol.ACTION_TYPES.GM_QUERY_PLAYER then
        if data.success then
            state.queryResult = data.playerInfo
            showResult("查询成功")
        else
            showResult("查询失败: " .. (data.reason or "玩家不在线"))
            state.queryResult = nil
        end
        return
    end

    -- GM_KICK_PLAYER
    if act == Protocol.ACTION_TYPES.GM_KICK_PLAYER then
        showResult(data.success and "踢出成功" or ("踢出失败: " .. (data.reason or "")))
        return
    end

    -- GM_BAN_PLAYER
    if act == Protocol.ACTION_TYPES.GM_BAN_PLAYER then
        showResult(data.success and "封禁成功" or ("封禁失败: " .. (data.reason or "")))
        return
    end

    -- GM_UNBAN_PLAYER
    if act == Protocol.ACTION_TYPES.GM_UNBAN_PLAYER then
        showResult(data.success and "解封成功" or ("解封失败: " .. (data.reason or "")))
        return
    end

    -- GM_RESET_MODULE
    if act == Protocol.ACTION_TYPES.GM_RESET_MODULE then
        showResult(data.success and "重置成功" or ("重置失败: " .. (data.reason or "")))
        return
    end

    -- GM_REPAIR_SAVE
    if act == Protocol.ACTION_TYPES.GM_REPAIR_SAVE then
        if data.success then
            local r = data.report or {}
            if r.repairExecuted then
                showResult("修复完成! 恢复英雄数: " .. (r.repairedRosterCount or "?"))
            elseif r.needsRepair then
                local sigCount = r.corruptionSignals and #r.corruptionSignals or 0
                showResult("[诊断] 检测到" .. sigCount .. "个损坏信号，需要修复")
            else
                showResult("[诊断] 无损坏信号: " .. (r.repairReason or ""))
            end
            local StageConfig = require("config.StageConfig")
            local function fmtStage(sid)
                if not sid or sid == 0 then return "未开始" end
                return StageConfig.formatProgressDisplay(sid)
            end
            state.queryResult = {
                uid = r.targetUid,
                level = r.playerLevel,
                heroCount = r.rosterCount,
                stage = fmtStage(r.maxStageId),
                maxStage = fmtStage(r.maxStageId),
                gold = r.gold,
                _repairReport = true,
                queued = r.queued,
                needsRepair = r.needsRepair,
                repairExecuted = r.repairExecuted,
                recoveredHeroCount = r.recoveredHeroCount or 0,
                corruptionSignals = r.corruptionSignals,
            }
        else
            showResult("修复失败: " .. (data.reason or ""))
        end
        return
    end

    -- GM_SEND_MAIL
    if act == Protocol.ACTION_TYPES.GM_SEND_MAIL then
        showResult(data.success and "邮件已发送" or ("发送失败: " .. (data.reason or "")))
        return
    end

    -- GM_BROADCAST_MAIL
    if act == Protocol.ACTION_TYPES.GM_BROADCAST_MAIL then
        showResult(data.success and "全服邮件已发送" or ("发送失败: " .. (data.reason or "")))
        return
    end

    -- GM_ANNOUNCEMENT
    if act == Protocol.ACTION_TYPES.GM_ANNOUNCEMENT then
        showResult(data.success and "公告操作成功" or ("公告操作失败: " .. (data.reason or "")))
        return
    end

    -- GM_MAINTENANCE
    -- 服务端返回结构: { success=true, maintenanceMode=bool, kickedCount=number }
    if act == Protocol.ACTION_TYPES.GM_MAINTENANCE then
        if data.success then
            showResult("维护模式已" .. (data.maintenanceMode and "开启" or "关闭") ..
                (data.kickedCount and data.kickedCount > 0 and (", 踢出 " .. data.kickedCount .. " 人") or ""))
            if state.serverInfo then
                state.serverInfo.maintenanceMode = data.maintenanceMode or false
            end
        else
            showResult("操作失败: " .. (data.reason or ""))
        end
        return
    end

    -- 通用 fallback
    if data.action and data.action:find("^gm_") then
        showResult(data.success and "操作成功" or ("操作失败: " .. (data.reason or "")))
    end
end

--- 点击处理
function GMConsolePanel.handleInput(dx, dy)
    if not state.open or state.closing then return false end
    if not getClient().isGM() then
        GMConsolePanel.close()
        return false
    end

    -- 弹窗外点击关闭
    if not hitTest(dx, dy, BG.CX, BG.CY, BG.W, BG.H) then
        GMConsolePanel.close()
        return true
    end

    -- 关闭按钮（右上角 X）
    local closeX, closeY = BG.CX + BG.W * 0.5 - 50, BG.CY - BG.H * 0.5 + 50
    if hitTest(dx, dy, closeX, closeY, 80, 80) then
        GMConsolePanel.close()
        return true
    end

    -- Tab 点击
    for i = 1, #TAB_NAMES do
        local tabX = TAB.START_X + (i - 1) * (TAB.W + TAB.GAP) + TAB.W * 0.5
        if hitTest(dx, dy, tabX, TAB.Y, TAB.W, TAB.H) then
            state.selectedTab = i
            state.scrollY = 0
            BF.trigger("gm_tab_" .. i)
            setFocus(nil)
            -- 切换 tab 时自动请求数据
            if i == TAB_ONLINE or i == TAB_SERVER then
                autoRefreshTimer_ = 0
                requestServerStatus()
            elseif i == TAB_LOG then
                requestLogs()
            end
            return true
        end
    end

    -- 分发到各 tab 的内容区点击
    local tab = state.selectedTab
    if tab == TAB_ONLINE then
        return handleOnlineTabInput(dx, dy)
    elseif tab == TAB_SERVER then
        return handleServerTabInput(dx, dy)
    elseif tab == TAB_PLAYER then
        return handlePlayerTabInput(dx, dy)
    elseif tab == TAB_MAIL then
        return handleMailTabInput(dx, dy)
    elseif tab == TAB_LOG then
        -- 日志 tab 无交互按钮（只查看）
        return true
    end

    return true  -- 消费事件防穿透
end

-- ======================== 各 Tab 内容区点击处理 ========================

--- 当前在线 Tab 点击
function handleOnlineTabInput(dx, dy)
    -- 刷新按钮
    local refreshX, refreshY = CONTENT_RIGHT - 70, CONTENT_TOP + 30
    if hitTest(dx, dy, refreshX, refreshY, 120, 50) then
        BF.trigger("gm_refresh")
        autoRefreshTimer_ = 0
        requestServerStatus()
        return true
    end

    -- 在线玩家列表 - 点击某个玩家 → 填充 UID
    local listTop = CONTENT_TOP + 80
    for i, player in ipairs(state.onlinePlayers) do
        local itemY = listTop + (i - 1) * (LIST_ITEM.H + LIST_ITEM.GAP) + LIST_ITEM.H * 0.5 - state.scrollY
        if itemY > CONTENT_TOP and itemY < CONTENT_BOTTOM then
            if hitTest(dx, dy, BG.CX, itemY, BG.W - 80, LIST_ITEM.H) then
                state.inputUID = tostring(player.uid)
                local displayName = player.name or "未知"
                showResult("已选中: " .. displayName .. " (UID: " .. state.inputUID .. ")")
                -- 自动切换到玩家 tab 方便操作
                state.selectedTab = TAB_PLAYER
                BF.trigger("gm_player_select_" .. i)
                return true
            end
        end
    end

    return true
end

--- 服务器 Tab 点击
function handleServerTabInput(dx, dy)
    -- 维护模式切换按钮
    local btnY = CONTENT_TOP + 200
    local btnX = 540
    if hitTest(dx, dy, btnX, btnY, BTN.W, BTN.H) then
        BF.trigger("gm_maintenance_toggle")
        local currentMode = state.serverInfo and state.serverInfo.maintenanceMode or false
        getClient().sendAction(Protocol.ACTION_TYPES.GM_MAINTENANCE, {
            enabled = not currentMode,
            reason = "GM 手动切换",
        })
        showResult("正在切换维护模式...")
        return true
    end

    -- 刷新按钮
    local refreshY = CONTENT_TOP + 300
    if hitTest(dx, dy, btnX, refreshY, BTN.W, BTN.H) then
        BF.trigger("gm_server_refresh")
        requestServerStatus()
        return true
    end

    return true
end

--- 玩家 Tab 点击
function handlePlayerTabInput(dx, dy)
    -- UID 输入框
    local uidBoxCX = 350
    local uidBoxCY = CONTENT_TOP + 50
    if hitTest(dx, dy, uidBoxCX, uidBoxCY, INPUT.W, INPUT.H) then
        setFocus("uid")
        return true
    end

    -- 查询按钮
    local queryBtnX = 700
    local queryBtnY = CONTENT_TOP + 50
    if hitTest(dx, dy, queryBtnX, queryBtnY, BTN.SMALL_W, BTN.SMALL_H) then
        BF.trigger("gm_query")
        if state.inputUID == "" then
            showResult("请输入 UID")
        else
            state.loading = true
            getClient().sendAction(Protocol.ACTION_TYPES.GM_QUERY_PLAYER, {
                targetUid = tonumber(state.inputUID) or 0,
            })
        end
        return true
    end

    -- 操作按钮行（踢出 / 封禁 / 重置模块）
    local row1Y = CONTENT_TOP + 140
    local btns = {
        { x = 220, label = "踢出", action = "kick" },
        { x = 430, label = "封禁", action = "ban" },
        { x = 640, label = "解封", action = "unban" },
        { x = 850, label = "重置模块", action = "reset" },
    }
    for _, btn in ipairs(btns) do
        if hitTest(dx, dy, btn.x, row1Y, BTN.SMALL_W, BTN.SMALL_H) then
            BF.trigger("gm_player_" .. btn.action)
            if state.inputUID == "" then
                showResult("请先输入目标 UID")
            else
                local targetUid = tonumber(state.inputUID) or 0
                if btn.action == "kick" then
                    getClient().sendAction(Protocol.ACTION_TYPES.GM_KICK_PLAYER, {
                        targetUid = targetUid,
                        reason = "GM 踢出",
                    })
                elseif btn.action == "ban" then
                    getClient().sendAction(Protocol.ACTION_TYPES.GM_BAN_PLAYER, {
                        targetUid = targetUid,
                        duration = 3600,  -- 默认1小时
                        reason = "GM 封禁",
                    })
                elseif btn.action == "unban" then
                    getClient().sendAction(Protocol.ACTION_TYPES.GM_UNBAN_PLAYER, {
                        targetUid = targetUid,
                    })
                elseif btn.action == "reset" then
                    if state.inputParam == "" then
                        setFocus("param")
                        showResult("请输入模块名(如 currency/heroes)")
                    else
                        getClient().sendAction(Protocol.ACTION_TYPES.GM_RESET_MODULE, {
                            targetUid = targetUid,
                            moduleName = state.inputParam,
                        })
                    end
                end
            end
            return true
        end
    end

    -- 参数输入框（用于重置模块等需要额外参数的操作）
    local paramBoxCY = CONTENT_TOP + 230
    if hitTest(dx, dy, uidBoxCX, paramBoxCY, INPUT.W, INPUT.H) then
        setFocus("param")
        return true
    end

    -- 清除按钮
    local clearBtnX = 700
    local clearBtnY = CONTENT_TOP + 230
    if hitTest(dx, dy, clearBtnX, clearBtnY, BTN.SMALL_W, BTN.SMALL_H) then
        state.inputUID = ""
        state.inputParam = ""
        state.queryResult = nil
        setFocus(nil)
        showResult("已清除")
        return true
    end

    -- 修复存档按钮行（诊断 + 执行修复）
    local repairRowY = CONTENT_TOP + 320
    local repairBtnW = 200
    local repairGap = 30
    local repairTotalW = repairBtnW * 2 + repairGap
    local repairStartX = CONTENT_LEFT + (CONTENT_RIGHT - CONTENT_LEFT - repairTotalW) * 0.5
    -- 诊断按钮
    if hitTest(dx, dy, repairStartX + repairBtnW * 0.5, repairRowY + BTN.SMALL_H * 0.5, repairBtnW, BTN.SMALL_H) then
        BF.trigger("gm_repair_diag")
        if state.inputUID == "" then
            showResult("请先输入目标 UID")
        else
            state.loading = true
            getClient().sendAction(Protocol.ACTION_TYPES.GM_REPAIR_SAVE, {
                targetUid = tonumber(state.inputUID) or 0,
                dryRun = true,
            })
        end
        return true
    end
    -- 执行修复按钮
    local repairExecX = repairStartX + repairBtnW + repairGap
    if hitTest(dx, dy, repairExecX + repairBtnW * 0.5, repairRowY + BTN.SMALL_H * 0.5, repairBtnW, BTN.SMALL_H) then
        BF.trigger("gm_repair_exec")
        if state.inputUID == "" then
            showResult("请先输入目标 UID")
        else
            state.loading = true
            getClient().sendAction(Protocol.ACTION_TYPES.GM_REPAIR_SAVE, {
                targetUid = tonumber(state.inputUID) or 0,
                dryRun = false,
            })
        end
        return true
    end

    -- 点击面板内其他区域 → 取消焦点
    setFocus(nil)
    return true
end

--- 邮件 Tab 点击
function handleMailTabInput(dx, dy)
    -- 输入框点击区域（与 drawMailTab 布局对齐）
    local fieldX = CONTENT_LEFT + 10
    local fieldW = CONTENT_RIGHT - CONTENT_LEFT - 20
    local titleY = CONTENT_TOP + 60
    local contentY = titleY + 100
    local rewardsY = contentY + 130

    -- 标题输入框
    if hitTest(dx, dy, fieldX + fieldW * 0.5, titleY + INPUT.H * 0.5, fieldW, INPUT.H) then
        setFocus("mailTitle")
        return true
    end
    -- 正文输入框
    if hitTest(dx, dy, fieldX + fieldW * 0.5, contentY + 80 * 0.5, fieldW, 80) then
        setFocus("mailContent")
        return true
    end
    -- 奖励输入框
    if hitTest(dx, dy, fieldX + fieldW * 0.5, rewardsY + INPUT.H * 0.5, fieldW, INPUT.H) then
        setFocus("mailRewards")
        return true
    end
    -- 区服范围输入框
    local serverRangeY = rewardsY + 100
    if hitTest(dx, dy, fieldX + fieldW * 0.5, serverRangeY + INPUT.H * 0.5, fieldW, INPUT.H) then
        setFocus("mailServerRange")
        return true
    end

    -- 操作按钮区域
    local btnY = serverRangeY + INPUT.H + 50
    local btnW = 240
    local btnH = BTN.H
    local btnGap = 30
    local totalBtnW = btnW * 3 + btnGap * 2
    local btnStartX = CONTENT_LEFT + (CONTENT_RIGHT - CONTENT_LEFT - totalBtnW) * 0.5 + btnW * 0.5

    -- 发送单人邮件
    if hitTest(dx, dy, btnStartX, btnY + btnH * 0.5, btnW, btnH) then
        BF.trigger("gm_mail_send")
        if state.inputUID == "" then
            showResult("请先在[玩家]页输入目标 UID")
        elseif state.mailTitle == "" then
            showResult("请输入邮件标题")
        else
            getClient().sendAction(Protocol.ACTION_TYPES.GM_SEND_MAIL, {
                targetUid = tonumber(state.inputUID) or 0,
                title = state.mailTitle,
                body = state.mailContent,
                rewards = parseRewards(state.mailRewards),
            })
            showResult("正在发送邮件...")
        end
        return true
    end

    -- 发送全服邮件
    local btn2X = btnStartX + btnW + btnGap
    if hitTest(dx, dy, btn2X, btnY + btnH * 0.5, btnW, btnH) then
        BF.trigger("gm_mail_broadcast")
        if state.mailTitle == "" then
            showResult("请输入邮件标题")
        else
            local serverIds = parseServerRange(state.mailServerRange)
            getClient().sendAction(Protocol.ACTION_TYPES.GM_BROADCAST_MAIL, {
                title = state.mailTitle,
                content = state.mailContent,
                rewards = parseRewards(state.mailRewards),
                expireDays = 7,
                serverIds = serverIds,  -- nil=全服; {1,2,3}=指定区服
            })
            local targetStr = serverIds and ("区服" .. state.mailServerRange) or "全服"
            showResult("正在发送全服邮件 → " .. targetStr .. " ...")
        end
        return true
    end

    -- 发送公告
    local btn3X = btn2X + btnW + btnGap
    if hitTest(dx, dy, btn3X, btnY + btnH * 0.5, btnW, btnH) then
        BF.trigger("gm_mail_announcement")
        if state.mailTitle == "" then
            showResult("请输入公告标题")
        else
            getClient().sendAction(Protocol.ACTION_TYPES.GM_ANNOUNCEMENT, {
                action = "add",
                data = {
                    id = "gm_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
                    title = state.mailTitle,
                    content = state.mailContent,
                },
            })
            showResult("正在发布公告...")
        end
        return true
    end

    -- 点击其他区域取消焦点
    setFocus(nil)
    return true
end

--- 拖拽处理（滚动列表）
function GMConsolePanel.handleDragBegin(dx, dy)
    if not state.open or state.closing then return false end
    if not getClient().isGM() then
        GMConsolePanel.close()
        return false
    end
    return hitTest(dx, dy, BG.CX, BG.CY, BG.W, BG.H)
end

function GMConsolePanel.handleDragMove(dx, dy)
    -- dy 为屏幕坐标增量（向上拖为正），用于滚动列表
    local contentH = 0
    if state.selectedTab == TAB_ONLINE then
        contentH = #state.onlinePlayers * (LIST_ITEM.H + LIST_ITEM.GAP)
    elseif state.selectedTab == TAB_LOG then
        contentH = #state.logEntries * 56
    end
    local viewH = CONTENT_BOTTOM - CONTENT_TOP - 80  -- 减去标题区域
    local maxScroll = math.max(0, contentH - viewH)
    state.scrollY = math.max(0, math.min(maxScroll, state.scrollY - dy))
    return true
end

function GMConsolePanel.handleDragEnd(dx, dy)
    return true
end

local lastDrawTime_ = 0
local autoRefreshTimer_ = 0
local AUTO_REFRESH_INTERVAL = 10.0  -- 在线列表自动刷新间隔（秒）

--- 绘制
function GMConsolePanel.draw(vg, dt)
    if not state.open then return end
    if not getClient().isGM() then
        GMConsolePanel.close()
        return
    end

    -- 自行计算 dt
    if not dt or dt <= 0 then
        local now = time.elapsedTime
        dt = now - lastDrawTime_
        if dt > 0.1 then dt = 0.016 end
        lastDrawTime_ = now
    end

    -- 在线 Tab 自动刷新（解决玩家重连后 GM 看不到的问题）
    if state.selectedTab == TAB_ONLINE and not state.loading then
        autoRefreshTimer_ = autoRefreshTimer_ + dt
        if autoRefreshTimer_ >= AUTO_REFRESH_INTERVAL then
            autoRefreshTimer_ = 0
            requestServerStatus()
        end
    end

    -- 光标闪烁
    state.cursorBlink = state.cursorBlink + dt

    -- 轮询退格键、粘贴键和回车键
    if state.focusField then
        if input:GetKeyPress(KEY_BACKSPACE) then
            local f = state.focusField
            if f == "uid" then
                state.inputUID = utf8RemoveLast(state.inputUID)
            elseif f == "param" then
                state.inputParam = utf8RemoveLast(state.inputParam)
            elseif f == "mailTitle" then
                state.mailTitle = utf8RemoveLast(state.mailTitle)
            elseif f == "mailContent" then
                state.mailContent = utf8RemoveLast(state.mailContent)
            elseif f == "mailRewards" then
                state.mailRewards = utf8RemoveLast(state.mailRewards)
            elseif f == "mailServerRange" then
                state.mailServerRange = utf8RemoveLast(state.mailServerRange)
            end
            state.cursorBlink = 0
        end
        -- Ctrl+V 粘贴
        if input:GetKeyPress(KEY_V) and input:GetQualifierDown(QUAL_CTRL) then
            local clip = ui:GetClipboardText()
            if clip and #clip > 0 then
                local f = state.focusField
                if f == "uid" then
                    state.inputUID = (state.inputUID .. clip):sub(1, 20)
                elseif f == "param" then
                    state.inputParam = (state.inputParam .. clip):sub(1, 50)
                elseif f == "mailTitle" then
                    state.mailTitle = (state.mailTitle .. clip):sub(1, 120)
                elseif f == "mailContent" then
                    state.mailContent = (state.mailContent .. clip):sub(1, 600)
                elseif f == "mailRewards" then
                    state.mailRewards = (state.mailRewards .. clip):sub(1, 300)
                elseif f == "mailServerRange" then
                    state.mailServerRange = (state.mailServerRange .. clip):sub(1, 30)
                end
                state.cursorBlink = 0
            end
        end
        if input:GetKeyPress(KEY_TAB) then
            -- Tab 在邮件页切换字段
            if state.selectedTab == TAB_MAIL then
                local mailFields = { "mailTitle", "mailContent", "mailRewards", "mailServerRange" }
                local idx = 1
                for i, f in ipairs(mailFields) do
                    if state.focusField == f then idx = i break end
                end
                local next = mailFields[(idx % #mailFields) + 1]
                setFocus(next)
            else
                if state.focusField == "uid" then setFocus("param")
                else setFocus("uid") end
            end
        end
        if input:GetKeyPress(KEY_RETURN) then
            setFocus(nil)
        end
    end

    -- 关闭动画完成检查
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        if elapsed >= ANIM_CLOSE_DUR then
            state.open = false
            state.closing = false
            return
        end
    end

    -- 计算动画进度
    local progress = 1.0
    if state.closing then
        progress = 1.0 - (time.elapsedTime - state.closeTime) / ANIM_CLOSE_DUR
    else
        local elapsed = time.elapsedTime - state.animTime
        if elapsed < ANIM_OPEN_DUR then
            progress = elapsed / ANIM_OPEN_DUR
        end
    end
    progress = 1.0 - (1.0 - progress) * (1.0 - progress)

    local alpha = math.floor(progress * 255)

    -- 1. 全屏遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(progress * MASK_ALPHA)))
    nvgFill(vg)

    -- 缩放动画
    local scale = 0.85 + 0.15 * progress
    nvgSave(vg)
    nvgTranslate(vg, BG.CX, BG.CY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -BG.CX, -BG.CY)

    -- 2. 圆角矩形背景（DebugPanel 风格）
    local bgX = BG.CX - BG.W * 0.5
    local bgY = BG.CY - BG.H * 0.5
    nvgGlobalAlpha(vg, progress)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bgX, bgY, BG.W, BG.H, BG.RADIUS)
    nvgFillColor(vg, nvgRGBA(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], BG_COLOR[4]))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, bgX, bgY, BG.W, BG.H, BG.RADIUS)
    nvgStrokeColor(vg, nvgRGBA(BORDER_COLOR[1], BORDER_COLOR[2], BORDER_COLOR[3], BORDER_COLOR[4]))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 3. 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TTL.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3], TITLE_COLOR[4]))
    nvgText(vg, TTL.X, TTL.Y, "GM 控制台", nil)

    -- 4. 关闭按钮 (X)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 50)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 100, 100, alpha))
    nvgText(vg, BG.CX + BG.W * 0.5 - 50, BG.CY - BG.H * 0.5 + 50, "X", nil)

    -- 5. Tab 按钮
    for i = 1, #TAB_NAMES do
        local tabX = TAB.START_X + (i - 1) * (TAB.W + TAB.GAP) + TAB.W * 0.5
        local isSelected = (i == state.selectedTab)

        local _bft = BF.begin(vg, "gm_tab_" .. i, tabX, TAB.Y, TAB.W, TAB.H)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, tabX - TAB.W * 0.5, TAB.Y - TAB.H * 0.5, TAB.W, TAB.H, 8)
        if isSelected then
            nvgFillColor(vg, nvgRGBA(60, 140, 200, alpha))
        else
            nvgFillColor(vg, nvgRGBA(50, 50, 65, alpha))
        end
        nvgFill(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, TAB.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isSelected then
            nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
        else
            nvgFillColor(vg, nvgRGBA(180, 180, 190, alpha))
        end
        nvgText(vg, tabX, TAB.Y, TAB_NAMES[i], nil)

        BF.finish(vg, _bft)
    end

    -- 6. 内容区域裁剪
    nvgSave(vg)
    nvgScissor(vg, CONTENT_LEFT, CONTENT_TOP, CONTENT_RIGHT - CONTENT_LEFT, CONTENT_BOTTOM - CONTENT_TOP)

    -- 分 Tab 绘制内容
    local tab = state.selectedTab
    if tab == TAB_ONLINE then
        drawOnlineTab(vg, alpha)
    elseif tab == TAB_SERVER then
        drawServerTab(vg, alpha)
    elseif tab == TAB_PLAYER then
        drawPlayerTab(vg, alpha)
    elseif tab == TAB_MAIL then
        drawMailTab(vg, alpha)
    elseif tab == TAB_LOG then
        drawLogTab(vg, alpha)
    end

    nvgRestore(vg)  -- 取消裁剪

    -- 7. 结果提示（底部）
    if state.resultTimer > 0 then
        state.resultTimer = state.resultTimer - dt
        local resultAlpha = math.min(1.0, state.resultTimer / 0.5) * alpha
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 32)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 255, 100, math.floor(resultAlpha)))
        nvgText(vg, 540, CONTENT_BOTTOM + 30, state.resultText, nil)
    end

    -- loading 提示
    if state.loading then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 32)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 100, alpha))
        nvgText(vg, 540, CONTENT_BOTTOM + 60, "请求中...", nil)
    end

    nvgGlobalAlpha(vg, 1.0)
    nvgRestore(vg)
end

-- ======================== Tab 内容绘制 ========================

--- 绘制「当前在线」Tab
function drawOnlineTab(vg, alpha)
    local y = CONTENT_TOP + 10

    -- 标题行
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 34)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
    nvgText(vg, CONTENT_LEFT + 10, y, "在线玩家 (" .. state.onlineCount .. ")", nil)

    -- 刷新按钮
    local refreshX = CONTENT_RIGHT - 70
    local _bfr = BF.begin(vg, "gm_refresh", refreshX, y + 15, 120, 40)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, refreshX - 60, y, 120, 40, 6)
    nvgFillColor(vg, nvgRGBA(60, 100, 160, alpha))
    nvgFill(vg)
    nvgFontSize(vg, 32)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
    nvgText(vg, refreshX, y + 20, "刷新", nil)
    BF.finish(vg, _bfr)

    y = y + 60

    -- 玩家列表
    if #state.onlinePlayers == 0 then
        nvgFontSize(vg, 34)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 150, 150, alpha))
        nvgText(vg, 540, y + 100, state.loading and "加载中..." or "暂无在线玩家", nil)
    else
        -- 裁剪区域：防止列表项溢出内容区
        nvgSave(vg)
        nvgScissor(vg, CONTENT_LEFT, y, CONTENT_RIGHT - CONTENT_LEFT, CONTENT_BOTTOM - y)

        for i, player in ipairs(state.onlinePlayers) do
            local itemY = y + (i - 1) * (LIST_ITEM.H + LIST_ITEM.GAP) - state.scrollY
            -- 可见性检查
            if itemY + LIST_ITEM.H > y and itemY < CONTENT_BOTTOM then
                -- 背景条
                nvgBeginPath(vg)
                nvgRoundedRect(vg, CONTENT_LEFT + 10, itemY, CONTENT_RIGHT - CONTENT_LEFT - 20, LIST_ITEM.H, 8)
                nvgFillColor(vg, nvgRGBA(40, 40, 50, math.floor(alpha * 0.7)))
                nvgFill(vg)

                -- 玩家名称（主要信息）
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 34)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(220, 220, 255, alpha))
                local displayName = player.name or "未知"
                nvgText(vg, CONTENT_LEFT + 30, itemY + LIST_ITEM.H * 0.35,
                    displayName, nil)

                -- UID + 区服（次要信息，小字）
                nvgFontSize(vg, 34)
                nvgFillColor(vg, nvgRGBA(160, 160, 180, alpha))
                local serverInfo = player.serverName or ""
                local subText = "UID: " .. tostring(player.uid)
                if serverInfo ~= "" then
                    subText = subText .. "  |  " .. serverInfo
                end
                nvgText(vg, CONTENT_LEFT + 30, itemY + LIST_ITEM.H * 0.7,
                    subText, nil)

                -- 在线状态指示灯（绿色圆点）
                nvgBeginPath(vg)
                nvgCircle(vg, CONTENT_RIGHT - 50, itemY + LIST_ITEM.H * 0.5, 8)
                nvgFillColor(vg, nvgRGBA(80, 220, 80, alpha))
                nvgFill(vg)

                -- 右侧提示"点击选中"
                nvgFontSize(vg, 34)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(140, 140, 140, alpha))
                nvgText(vg, CONTENT_RIGHT - 70, itemY + LIST_ITEM.H * 0.5, "点击选中", nil)
            end
        end

        nvgRestore(vg)

        -- 滚动指示器（右侧滚动条）
        local totalCount = #state.onlinePlayers
        local contentH = totalCount * (LIST_ITEM.H + LIST_ITEM.GAP)
        local viewH = CONTENT_BOTTOM - y
        if contentH > viewH then
            local scrollBarH = math.max(40, viewH * viewH / contentH)
            local scrollTrackH = viewH - scrollBarH
            local scrollRatio = state.scrollY / math.max(1, contentH - viewH)
            local scrollBarY = y + scrollRatio * scrollTrackH

            -- 滚动条轨道
            nvgBeginPath(vg)
            nvgRoundedRect(vg, CONTENT_RIGHT - 12, y, 6, viewH, 3)
            nvgFillColor(vg, nvgRGBA(60, 60, 70, math.floor(alpha * 0.4)))
            nvgFill(vg)

            -- 滚动条滑块
            nvgBeginPath(vg)
            nvgRoundedRect(vg, CONTENT_RIGHT - 12, scrollBarY, 6, scrollBarH, 3)
            nvgFillColor(vg, nvgRGBA(150, 150, 180, math.floor(alpha * 0.8)))
            nvgFill(vg)

            -- 底部页码提示
            local itemsPerPage = math.floor(viewH / (LIST_ITEM.H + LIST_ITEM.GAP))
            local currentPage = math.floor(state.scrollY / (LIST_ITEM.H + LIST_ITEM.GAP) / itemsPerPage) + 1
            local totalPages = math.ceil(totalCount / itemsPerPage)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 26)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(140, 140, 160, alpha))
            nvgText(vg, 540, CONTENT_BOTTOM + 5,
                currentPage .. "/" .. totalPages .. " 页  (上下滑动翻页)", nil)
        end
    end
end

--- 绘制「服务器」Tab
function drawServerTab(vg, alpha)
    local y = CONTENT_TOP + 20
    local info = state.serverInfo

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 34)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    -- 在线人数
    nvgFillColor(vg, nvgRGBA(200, 200, 200, alpha))
    nvgText(vg, CONTENT_LEFT + 20, y, "在线人数:", nil)
    nvgFillColor(vg, nvgRGBA(100, 255, 100, alpha))
    nvgText(vg, CONTENT_LEFT + 200, y, info and tostring(info.onlineCount) or "--", nil)
    y = y + 60

    -- 运行时长
    nvgFillColor(vg, nvgRGBA(200, 200, 200, alpha))
    nvgText(vg, CONTENT_LEFT + 20, y, "运行时长:", nil)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
    nvgText(vg, CONTENT_LEFT + 200, y, info and formatUptime(info.uptimeSeconds) or "--", nil)
    y = y + 60

    -- 维护模式状态
    nvgFillColor(vg, nvgRGBA(200, 200, 200, alpha))
    nvgText(vg, CONTENT_LEFT + 20, y, "维护模式:", nil)
    local isMaintenanceOn = info and info.maintenanceMode or false
    if isMaintenanceOn then
        nvgFillColor(vg, nvgRGBA(255, 80, 80, alpha))
        nvgText(vg, CONTENT_LEFT + 200, y, "已开启", nil)
    else
        nvgFillColor(vg, nvgRGBA(100, 255, 100, alpha))
        nvgText(vg, CONTENT_LEFT + 200, y, "已关闭", nil)
    end
    y = y + 80

    -- 维护模式切换按钮
    local btnX = 540
    local btnY = y + BTN.H * 0.5
    local _bfm = BF.begin(vg, "gm_maintenance_toggle", btnX, btnY, BTN.W, BTN.H)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX - BTN.W * 0.5, y, BTN.W, BTN.H, BTN.R)
    if isMaintenanceOn then
        nvgFillColor(vg, nvgRGBA(60, 160, 60, alpha))
    else
        nvgFillColor(vg, nvgRGBA(160, 60, 60, alpha))
    end
    nvgFill(vg)
    nvgFontSize(vg, BTN.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
    nvgText(vg, btnX, btnY, isMaintenanceOn and "关闭维护" or "开启维护", nil)
    BF.finish(vg, _bfm)
    y = y + BTN.H + 30

    -- 刷新按钮
    local refBtnY = y + BTN.H * 0.5
    local _bfs = BF.begin(vg, "gm_server_refresh", btnX, refBtnY, BTN.W, BTN.H)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX - BTN.W * 0.5, y, BTN.W, BTN.H, BTN.R)
    nvgFillColor(vg, nvgRGBA(60, 100, 160, alpha))
    nvgFill(vg)
    nvgFontSize(vg, BTN.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
    nvgText(vg, btnX, refBtnY, "刷新状态", nil)
    BF.finish(vg, _bfs)
end

--- 绘制「玩家」Tab
function drawPlayerTab(vg, alpha)
    local y = CONTENT_TOP + 20

    -- UID 输入框
    local uidBoxX = CONTENT_LEFT + 20
    local uidBoxW = INPUT.W
    local uidFocused = (state.focusField == "uid")

    nvgBeginPath(vg)
    nvgRoundedRect(vg, uidBoxX, y, uidBoxW, INPUT.H, INPUT.R)
    nvgFillColor(vg, nvgRGBA(25, 25, 30, math.floor(alpha * 0.9)))
    nvgFill(vg)
    if uidFocused then
        nvgStrokeColor(vg, nvgRGBA(255, 200, 50, alpha))
        nvgStrokeWidth(vg, 3)
    else
        nvgStrokeColor(vg, nvgRGBA(80, 80, 80, alpha))
        nvgStrokeWidth(vg, 2)
    end
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, INPUT.FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local uidCenterY = y + INPUT.H * 0.5
    if state.inputUID == "" then
        nvgFillColor(vg, nvgRGBA(100, 100, 100, alpha))
        nvgText(vg, uidBoxX + 15, uidCenterY, "输入目标 UID...", nil)
    else
        nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
        local display = state.inputUID
        if uidFocused and math.floor(state.cursorBlink * 2) % 2 == 0 then
            display = display .. "|"
        end
        nvgText(vg, uidBoxX + 15, uidCenterY, display, nil)
    end

    -- 查询按钮
    local qBtnX = uidBoxX + uidBoxW + 20
    local _bfq = BF.begin(vg, "gm_query", qBtnX + BTN.SMALL_W * 0.5, y + INPUT.H * 0.5, BTN.SMALL_W, BTN.SMALL_H)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, qBtnX, y + (INPUT.H - BTN.SMALL_H) * 0.5, BTN.SMALL_W, BTN.SMALL_H, 6)
    nvgFillColor(vg, nvgRGBA(60, 120, 180, alpha))
    nvgFill(vg)
    nvgFontSize(vg, 34)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
    nvgText(vg, qBtnX + BTN.SMALL_W * 0.5, y + INPUT.H * 0.5, "查询", nil)
    BF.finish(vg, _bfq)

    y = y + INPUT.H + 20

    -- 操作按钮行
    local actionBtns = {
        { label = "踢出", color = { 160, 80, 60 } },
        { label = "封禁", color = { 180, 60, 60 } },
        { label = "解封", color = { 60, 140, 60 } },
        { label = "重置", color = { 140, 100, 60 } },
    }
    local btnGap = 15
    local totalW = #actionBtns * BTN.SMALL_W + (#actionBtns - 1) * btnGap
    local startX = CONTENT_LEFT + (CONTENT_RIGHT - CONTENT_LEFT - totalW) * 0.5

    for i, ab in ipairs(actionBtns) do
        local bx = startX + (i - 1) * (BTN.SMALL_W + btnGap)
        local _bfa = BF.begin(vg, "gm_player_" .. ab.label, bx + BTN.SMALL_W * 0.5, y + BTN.SMALL_H * 0.5, BTN.SMALL_W, BTN.SMALL_H)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, y, BTN.SMALL_W, BTN.SMALL_H, 8)
        nvgFillColor(vg, nvgRGBA(ab.color[1], ab.color[2], ab.color[3], alpha))
        nvgFill(vg)
        nvgFontSize(vg, 34)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
        nvgText(vg, bx + BTN.SMALL_W * 0.5, y + BTN.SMALL_H * 0.5, ab.label, nil)
        BF.finish(vg, _bfa)
    end

    y = y + BTN.SMALL_H + 20

    -- 参数输入框
    local paramFocused = (state.focusField == "param")
    nvgBeginPath(vg)
    nvgRoundedRect(vg, uidBoxX, y, uidBoxW, INPUT.H, INPUT.R)
    nvgFillColor(vg, nvgRGBA(25, 25, 30, math.floor(alpha * 0.9)))
    nvgFill(vg)
    if paramFocused then
        nvgStrokeColor(vg, nvgRGBA(255, 200, 50, alpha))
        nvgStrokeWidth(vg, 3)
    else
        nvgStrokeColor(vg, nvgRGBA(80, 80, 80, alpha))
        nvgStrokeWidth(vg, 2)
    end
    nvgStroke(vg)

    local paramCenterY = y + INPUT.H * 0.5
    if state.inputParam == "" then
        nvgFillColor(vg, nvgRGBA(100, 100, 100, alpha))
        nvgText(vg, uidBoxX + 15, paramCenterY, "参数 (模块名等)...", nil)
    else
        nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
        local display = state.inputParam
        if paramFocused and math.floor(state.cursorBlink * 2) % 2 == 0 then
            display = display .. "|"
        end
        nvgText(vg, uidBoxX + 15, paramCenterY, display, nil)
    end

    -- 清除按钮
    local clrX = uidBoxX + uidBoxW + 20
    local _bfc = BF.begin(vg, "gm_clear", clrX + BTN.SMALL_W * 0.5, paramCenterY, BTN.SMALL_W, BTN.SMALL_H)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, clrX, y + (INPUT.H - BTN.SMALL_H) * 0.5, BTN.SMALL_W, BTN.SMALL_H, 6)
    nvgFillColor(vg, nvgRGBA(100, 50, 50, alpha))
    nvgFill(vg)
    nvgFontSize(vg, 34)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
    nvgText(vg, clrX + BTN.SMALL_W * 0.5, paramCenterY, "清除", nil)
    BF.finish(vg, _bfc)

    y = y + INPUT.H + 30

    -- 修复存档按钮行（诊断 + 执行修复）
    do
        local repairBtnW = 200
        local repairGap = 30
        local repairTotalW = repairBtnW * 2 + repairGap
        local repairStartX = CONTENT_LEFT + (CONTENT_RIGHT - CONTENT_LEFT - repairTotalW) * 0.5

        -- 诊断按钮（蓝色）
        local _bfrd = BF.begin(vg, "gm_repair_diag", repairStartX + repairBtnW * 0.5, y + BTN.SMALL_H * 0.5, repairBtnW, BTN.SMALL_H)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, repairStartX, y, repairBtnW, BTN.SMALL_H, 8)
        nvgFillColor(vg, nvgRGBA(50, 100, 160, alpha))
        nvgFill(vg)
        nvgFontSize(vg, 34)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
        nvgText(vg, repairStartX + repairBtnW * 0.5, y + BTN.SMALL_H * 0.5, "诊断存档", nil)
        BF.finish(vg, _bfrd)

        -- 执行修复按钮（琥珀色）
        local execX = repairStartX + repairBtnW + repairGap
        local _bfre = BF.begin(vg, "gm_repair_exec", execX + repairBtnW * 0.5, y + BTN.SMALL_H * 0.5, repairBtnW, BTN.SMALL_H)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, execX, y, repairBtnW, BTN.SMALL_H, 8)
        nvgFillColor(vg, nvgRGBA(180, 120, 40, alpha))
        nvgFill(vg)
        nvgFontSize(vg, 34)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
        nvgText(vg, execX + repairBtnW * 0.5, y + BTN.SMALL_H * 0.5, "修复存档", nil)
        BF.finish(vg, _bfre)
    end

    y = y + BTN.SMALL_H + 20

    -- 查询结果展示
    -- 服务端返回扁平结构: { uid, level, exp, stage, gold, gems, heroCount, createTime, banned, banReason }
    if state.queryResult then
        nvgFontSize(vg, 32)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

        local data = state.queryResult
        local lines = {
            { label = "UID",      value = tostring(data.uid or "?") },
            { label = "冒险等级", value = "Lv." .. tostring(data.level or 0) .. "  (经验: " .. tostring(data.exp or 0) .. ")" },
            { label = "当前关卡", value = tostring(data.stage or "未知") },
            { label = "最高关卡", value = tostring(data.maxStage or "未知") },
            { label = "金币",     value = tostring(data.gold or 0) },
            { label = "钻石",     value = tostring(data.gems or 0) },
            { label = "英雄数",   value = tostring(data.heroCount or 0) },
        }

        -- 根据是普通查询还是修复报告，显示不同信息
        if data._repairReport then
            if data.queued then
                lines[#lines + 1] = { label = "修复状态", value = "已加入跨实例修复队列", color = "warn" }
                lines[#lines + 1] = { label = "说明", value = "修复结果将通过邮件通知", color = "dim" }
            else
                lines[#lines + 1] = { label = "恢复标记英雄", value = tostring(data.recoveredHeroCount or 0), color = "warn" }
                if data.needsRepair then
                    lines[#lines + 1] = { label = "诊断结果", value = "需要修复", color = "red" }
                elseif data.repairExecuted then
                    lines[#lines + 1] = { label = "诊断结果", value = "已修复", color = "green" }
                else
                    lines[#lines + 1] = { label = "诊断结果", value = "正常", color = "green" }
                end
            end
            -- 显示损坏信号详情
            if data.corruptionSignals and #data.corruptionSignals > 0 then
                for si, sig in ipairs(data.corruptionSignals) do
                    lines[#lines + 1] = { label = "损坏#" .. si, value = sig, color = "red" }
                end
            end
        else
            lines[#lines + 1] = { label = "封禁状态", value = data.banned and ("已封禁: " .. (data.banReason or "")) or "正常" }
        end

        for i, item in ipairs(lines) do
            local lineY = y + (i - 1) * 36
            -- 标签（灰色）
            nvgFillColor(vg, nvgRGBA(160, 160, 180, alpha))
            nvgText(vg, CONTENT_LEFT + 20, lineY, item.label .. ": ", nil)
            -- 值（根据 color 选择颜色）
            local labelW = nvgTextBounds(vg, 0, 0, item.label .. ": ")
            if item.color == "red" then
                nvgFillColor(vg, nvgRGBA(255, 100, 100, alpha))
            elseif item.color == "green" then
                nvgFillColor(vg, nvgRGBA(100, 255, 130, alpha))
            elseif item.color == "warn" then
                nvgFillColor(vg, nvgRGBA(255, 200, 80, alpha))
            else
                nvgFillColor(vg, nvgRGBA(240, 240, 255, alpha))
            end
            nvgText(vg, CONTENT_LEFT + 20 + labelW, lineY, item.value, nil)
        end
    end
end

--- 绘制「邮件」Tab
function drawMailTab(vg, alpha)
    nvgFontFace(vg, "sans")

    local fieldX = CONTENT_LEFT + 10
    local fieldW = CONTENT_RIGHT - CONTENT_LEFT - 20

    -- === 标题输入框 ===
    local titleY = CONTENT_TOP + 60
    drawFieldBox(vg, "邮件/公告标题", state.mailTitle, fieldX, titleY, fieldW, INPUT.H, state.focusField == "mailTitle", alpha)

    -- === 正文输入框（更高）===
    local contentY = titleY + 100
    local contentH = 80
    drawFieldBox(vg, "正文内容", state.mailContent, fieldX, contentY, fieldW, contentH, state.focusField == "mailContent", alpha)

    -- === 奖励输入框 ===
    local rewardsY = contentY + 130
    drawFieldBox(vg, "奖励 (编号*数量, 如 7*10,101*5 碎片, h16*5, diamond*100)", state.mailRewards, fieldX, rewardsY, fieldW, INPUT.H, state.focusField == "mailRewards", alpha)

    -- === 区服范围输入框 ===
    local serverRangeY = rewardsY + 100
    drawFieldBox(vg, "区服范围 (空=全服, 格式: 1-3 或 1,2,3)", state.mailServerRange, fieldX, serverRangeY, fieldW, INPUT.H, state.focusField == "mailServerRange", alpha)

    -- === 操作按钮 ===
    local btnY = serverRangeY + INPUT.H + 50
    local btnW = 240
    local btnH = BTN.H
    local btnGap = 30
    local totalBtnW = btnW * 3 + btnGap * 2
    local btnStartX = CONTENT_LEFT + (CONTENT_RIGHT - CONTENT_LEFT - totalBtnW) * 0.5

    local mailActions = {
        { label = "单人邮件", color = { 70, 120, 180 }, id = "gm_mail_send" },
        { label = "全服邮件", color = { 70, 150, 100 }, id = "gm_mail_broadcast" },
        { label = "发布公告", color = { 150, 100, 70 }, id = "gm_mail_announcement" },
    }

    for i, act in ipairs(mailActions) do
        local bx = btnStartX + (i - 1) * (btnW + btnGap)
        local bcx = bx + btnW * 0.5
        local bcy = btnY + btnH * 0.5

        local _bf = BF.begin(vg, act.id, bcx, bcy, btnW, btnH)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, btnY, btnW, btnH, BTN.R)
        nvgFillColor(vg, nvgRGBA(act.color[1], act.color[2], act.color[3], alpha))
        nvgFill(vg)

        nvgFontSize(vg, 34)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
        nvgText(vg, bcx, bcy, act.label, nil)
        BF.finish(vg, _bf)
    end

    -- === 操作提示 ===
    local hintY = btnY + btnH + 20
    nvgFontSize(vg, 32)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(120, 120, 140, alpha))
    nvgText(vg, fieldX, hintY, "单人邮件需在[玩家]页先输入目标 UID | Tab 键切换输入框", nil)

    -- === 奖励预览 ===
    local previewY = hintY + 30
    local rewards = parseRewards(state.mailRewards)
    if #rewards > 0 then
        nvgFillColor(vg, nvgRGBA(100, 180, 100, alpha))
        local previewStr = "奖励预览: "
        for i, r in ipairs(rewards) do
            if i > 1 then previewStr = previewStr .. ", " end
            previewStr = previewStr .. ResourceDefs.getRewardDisplayName(r) .. " x" .. r.amount
        end
        nvgText(vg, fieldX, previewY, previewStr, nil)
    elseif state.mailRewards ~= "" then
        nvgFillColor(vg, nvgRGBA(200, 100, 100, alpha))
        nvgText(vg, fieldX, previewY, "奖励格式有误 (正确: 1*1000,101*10, h16*10, diamond*100)", nil)
    end
end

--- 绘制「日志」Tab
function drawLogTab(vg, alpha)
    local y = CONTENT_TOP + 10

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 32)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
    nvgText(vg, CONTENT_LEFT + 10, y, "操作日志 (最近50条)", nil)
    y = y + 50

    if #state.logEntries == 0 then
        nvgFontSize(vg, 32)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 150, 150, alpha))
        nvgText(vg, 540, y + 80, state.loading and "加载中..." or "暂无日志", nil)
    else
        nvgFontSize(vg, 34)
        for i, entry in ipairs(state.logEntries) do
            local itemY = y + (i - 1) * 56 - state.scrollY
            if itemY + 56 > CONTENT_TOP and itemY < CONTENT_BOTTOM then
                -- 时间
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(140, 180, 255, alpha))
                local timeStr = entry.timeStr or os.date("%H:%M:%S", entry.time or 0)
                nvgText(vg, CONTENT_LEFT + 10, itemY, timeStr, nil)

                -- 操作内容
                nvgFillColor(vg, nvgRGBA(200, 200, 200, alpha))
                local actionStr = string.format("uid=%s %s %s",
                    tostring(entry.operator or "?"),
                    tostring(entry.action or "?"),
                    entry.result or "")
                nvgText(vg, CONTENT_LEFT + 10, itemY + 26, actionStr, nil)

                -- 分隔线
                nvgBeginPath(vg)
                nvgMoveTo(vg, CONTENT_LEFT + 10, itemY + 52)
                nvgLineTo(vg, CONTENT_RIGHT - 10, itemY + 52)
                nvgStrokeColor(vg, nvgRGBA(60, 60, 60, alpha))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
            end
        end
    end
end

-- ============================================================================
-- 全局事件处理（文本输入）
-- ============================================================================

---@param eventType string
---@param eventData TextInputEventData
function HandleGMConsoleTextInput(eventType, eventData)
    -- GM 面板未打开时，转发给兑换码面板
    if not state.open or state.closing then
        ---@diagnostic disable-next-line: undefined-global
        HandleRedeemTextInput(eventType, eventData)
        return
    end
    if not state.focusField then return end

    local char = eventData["Text"]:GetString()
    if not char or #char == 0 then return end

    local f = state.focusField
    if f == "uid" then
        if utf8Len(state.inputUID) < 20 then
            state.inputUID = state.inputUID .. char
        end
    elseif f == "param" then
        if utf8Len(state.inputParam) < 50 then
            state.inputParam = state.inputParam .. char
        end
    elseif f == "mailTitle" then
        if utf8Len(state.mailTitle) < 40 then
            state.mailTitle = state.mailTitle .. char
        end
    elseif f == "mailContent" then
        if utf8Len(state.mailContent) < 200 then
            state.mailContent = state.mailContent .. char
        end
    elseif f == "mailRewards" then
        if utf8Len(state.mailRewards) < 100 then
            state.mailRewards = state.mailRewards .. char
        end
    elseif f == "mailServerRange" then
        if utf8Len(state.mailServerRange) < 20 then
            state.mailServerRange = state.mailServerRange .. char
        end
    end
    state.cursorBlink = 0
end

return GMConsolePanel
