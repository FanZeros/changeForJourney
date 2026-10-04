-- 远征逐级轨道隔离回归：真实 TaskPage / View / Progress / 配置 / I18n。
-- UI、动作和 NanoVG 全部内存 mock；不初始化 PlayerStore、不发奖、不读写玩家存档。
-- 圆球/渐变仅验证声明属性与树结构，不代表 GPU 像素或视觉验收通过。
local assertions = 0
local function check(value, message)
    assert(value, message)
    assertions = assertions + 1
    print("[expedition_track_ui_test] PASS " .. message)
end

---@class ExpeditionTestWidget
---@field props table
---@field children ExpeditionTestWidget[]
---@field destroyed boolean
---@field fontSizeSets integer
local Widget = {}
function Widget:AddChild(child)
    self.children[#self.children + 1] = child
    return self
end
function Widget:FindById(id)
    if self.props.id == id then return self end
    for _, child in ipairs(self.children) do
        local found = child:FindById(id)
        if found then return found end
    end
    return nil
end
function Widget:SetFontColor(value) self.props.fontColor = value end
function Widget:SetValue(value) self.props.value = value end
function Widget:SetDisabled(value) self.props.disabled = value end
function Widget:SetStyle(style)
    if style.fontSize ~= nil then self.fontSizeSets = self.fontSizeSets + 1 end
    for key, value in pairs(style) do self.props[key] = value end
end
function Widget:Destroy()
    self.destroyed = true
    for _, child in ipairs(self.children) do child:Destroy() end
end

---@class ExpeditionTestDraw
---@field root ExpeditionTestWidget
---@field x number
---@field y number
---@field w number
---@field h number

local function runTests()
    local originalRequire = require
    -- 恢复所有新加载/替换的模块，不把 mock 闭包留给同进程后续测试。
    local savedModules = {}
    for name, value in pairs(package.loaded) do savedModules[name] = value end
    local I18n = originalRequire("core.I18n")
    local originalLanguage = I18n.get()
    -- 先加载真实纯数据词典，不安装绘图 hook、不加载设置/存档服务。
    I18n.set("en")
    I18n.lookup("远征勋记")
    I18n.set("zh_CN")
    local savedGlobals, globalNames = {}, {}
    local function replaceGlobal(name, value)
        globalNames[#globalNames + 1] = name
        savedGlobals[name] = rawget(_G, name)
        rawset(_G, name, value)
    end
    ---@type ExpeditionTestWidget[]
    local widgets = {}
    local setterCalls, imageCreates = 0, 0
    -- 宿主测宽使用可控的字体度量；只验证调用/缩字数学，不模拟GPU像素。
    local vg = {}
    local fontState = { face = "", size = 0 }
    ---@type {value: string, size: number, measured: number}[]
    local measurements = {}
    ---@type table<string, number>
    local widthOverrides = {}
    ---@type table<string, string>
    local translationOverrides = {}
    ---@param value string
    ---@param size number
    local function measuredWidth(value, size)
        local characters = 0
        for _ in utf8.codes(value) do characters = characters + 1 end
        return widthOverrides[value] or (characters * size * 0.5)
    end
    ---@param props table?
    ---@return ExpeditionTestWidget
    local function createWidget(props)
        props = props or {}
        local widget = setmetatable({ props = props, children = {}, destroyed = false, fontSizeSets = 0 }, { __index = Widget })
        function widget:SetText(value)
            setterCalls = setterCalls + 1
            self.props.text = value
        end
        for _, child in ipairs(props.children or {}) do widget:AddChild(child) end
        widgets[#widgets + 1] = widget
        return widget
    end
    ---@type table<string, any>
    local modules = { player = { level = 30, exp = 42 }, task = {
        achProg = { player_level = 0 }, achClaimed = { a_plv_5 = true },
    }, battle = { clearedStages = { ["905"] = true } }, currency = { gold = 123, gems = 456 } }
    ---@type {action: string, params: table}[]
    local actions = {}
    local texts, clips, rects = {}, {}, {}
    ---@type ExpeditionTestDraw[]
    local draws = {}
    local refreshes, uiInits = 0, 0
    ---@type {x: number, y: number}
    local transform = { x = 0, y = 0 }
    ---@type {x: number, y: number}[]
    local stack = {}
    local noop = function() end
    ---@type table<string, any>
    local mocks = {
        ["urhox-libs/UI"] = { Panel = createWidget, Label = createWidget,
            Button = createWidget, ProgressBar = createWidget },
        ["ui.widget.DesignWidgetSurface"] = {
            init = function() uiInits = uiInits + 1 end,
            draw = function(root, _, w, h)
                draws[#draws + 1] = { root = root, x = transform.x, y = transform.y, w = w, h = h }
            end,
        },
        -- 真实词典只读代理；仅长译文用内存覆盖，不修改I18n或ResourceDefs共享数据。
        ["core.I18n"] = setmetatable({ lookup = function(value)
            return translationOverrides[value] or I18n.lookup(value)
        end }, { __index = I18n }),
        ["core.DrawUtil"] = {
            drawTextStroke = function(_, _, _, value) texts[#texts + 1] = value end,
            seamSlideX = function() return 0 end, drawImageCentered = noop,
        },
        ["core.DarkIcon"] = { draw = noop, drawQualityBg = noop },
        ["ui.town.TownPageChrome"] = {
            OPEN_DUR = 0.22, CLOSE_DUR = 0.22,
            slideProgress = function() return 1 end,
            hitBack = function(x, y) return x == 0 and y == 0 end,
            drawNamePlate = noop, drawBack = noop,
        },
        ["runtime.ClientDispatcher"] = { get = function(name) return modules[name] end },
        ["runtime.GameAction"] = { sendAction = function(action, params)
            actions[#actions + 1] = { action = action, params = params }
            return true
        end },
        ["rules.task.TaskService"] = { RefreshAchievements = function(playerId)
            check(playerId == 1, "打开页沿用既有成就刷新入口")
            refreshes = refreshes + 1
        end },
    }
    -- 白名单只放纯配置与被测模块；遗漏 mock 必须失败，禁止进入真实业务服务。
    ---@type table<string, boolean>
    local allowed = {
        ["config.ExpeditionProgress"] = true, ["config.TaskConfig"] = true,
        ["config.ResourceDefs"] = true, ["core.NumberUtil"] = true,
        ["config.ExpTable"] = true, ["config.StageConfig"] = true,
        ["shared.artifact.ArtifactSchema"] = true, ["shared.artifact.ArtifactDefs"] = true,
        ["shared.Protocol"] = true,
        ["ui.story.task.TaskPage"] = true, ["ui.story.task.ExpeditionTrackView"] = true,
    }
    for _, suffix in ipairs({ "Normal", "Hard", "Nightmare", "Hell", "Purgatory", "Torment", "Torment2",
        "Torment3", "Torment4", "Torment5", "Annihilation", "Annihilation2", "Annihilation3",
        "Annihilation4", "Annihilation5" }) do allowed["config.StageConfig_" .. suffix] = true end
    local progressBuilds = 0
    ---@type table?
    local progressProxy = nil
    local function isolatedRequire(name)
        if mocks[name] then return mocks[name] end
        assert(allowed[name], "测试禁止加载真实副作用模块 " .. tostring(name))
        local module = originalRequire(name)
        if name == "config.ExpeditionProgress" then
            if not progressProxy then
                progressProxy = setmetatable({ build = function(...)
                    progressBuilds = progressBuilds + 1
                    return module.build(...)
                end }, { __index = module })
            end
            return progressProxy
        end
        return module
    end
    replaceGlobal("require", isolatedRequire)
    ---@type {elapsedTime: number}
    local clock = { elapsedTime = 100 }
    replaceGlobal("time", clock)
    local function forbiddenIO() error("隔离测试禁止访问文件/玩家存档") end
    replaceGlobal("File", forbiddenIO)
    replaceGlobal("GetFileSystem", forbiddenIO)
    for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgFillColor", "nvgFill",
        "nvgGlobalAlpha", "nvgTextAlign" }) do replaceGlobal(name, noop) end
    replaceGlobal("nvgFontFace", function(context, face)
        assert(context == vg, "测宽/绘制必须复用draw传入的宿主vg")
        fontState.face = face
    end)
    replaceGlobal("nvgFontSize", function(context, size)
        assert(context == vg, "测宽必须收到draw传入的宿主vg")
        fontState.size = size
    end)
    replaceGlobal("nvgRoundedRect", function(_, x, y, w, h, radius)
        rects[#rects + 1] = { x = x, y = y, w = w, h = h, radius = radius }
    end)
    replaceGlobal("nvgTextBox", function(_, _, _, _, value) texts[#texts + 1] = value end)
    replaceGlobal("nvgTextBounds", function(context, x, y, value, bounds)
        assert(context == vg and fontState.face == "sans" and x == 0 and y == 0 and bounds == nil,
            "测宽必须使用宿主vg/sans/原点及nil bounds")
        local measured = measuredWidth(value, fontState.size)
        measurements[#measurements + 1] = { value = value, size = fontState.size, measured = measured }
        return measured
    end)
    replaceGlobal("nvgSave", function() stack[#stack + 1] = { x = transform.x, y = transform.y } end)
    replaceGlobal("nvgRestore", function()
        assert(#stack > 0, "绘制不能多次恢复宿主变换栈")
        transform = table.remove(stack)
    end)
    replaceGlobal("nvgTranslate", function(_, x, y)
        transform.x = transform.x + x
        transform.y = transform.y + y
    end)
    replaceGlobal("nvgIntersectScissor", function(_, x, y, w, h)
        clips[#clips + 1] = { x = transform.x + x, y = transform.y + y, w = w, h = h }
    end)
    replaceGlobal("nvgCreateImage", function() imageCreates = imageCreates + 1 return 1 end)
    replaceGlobal("nvgCreateFont", function() error("视图禁止另建宿主字体") end)
    replaceGlobal("nvgRGBA", function(r, g, b, a) return { r, g, b, a } end)
    replaceGlobal("nvgBeginFrame", function() error("视图禁止新建宿主 NanoVG 帧") end)
    replaceGlobal("nvgEndFrame", function() error("视图禁止结束宿主 NanoVG 帧") end)
    for _, name in ipairs({ "NVG_ALIGN_LEFT", "NVG_ALIGN_RIGHT", "NVG_ALIGN_CENTER",
        "NVG_ALIGN_MIDDLE", "NVG_ALIGN_BOTTOM", "NVG_ALIGN_TOP" }) do
        -- 沿用引擎真实枚举；这里只 mock 绘制，不处理原生输入。
        assert(rawget(_G, name) ~= nil, "缺失宿主 NanoVG 枚举 " .. name)
    end
    -- 强制重新加载纯配置，防止已缓存 Progress 持有真实业务依赖。
    for name in pairs(allowed) do package.loaded[name] = nil end

    local ok, err = pcall(function()
        local Page = isolatedRequire("ui.story.task.TaskPage")
        local Progress = isolatedRequire("config.ExpeditionProgress")
        local TaskConfig = isolatedRequire("config.TaskConfig")
        local ResourceDefs = isolatedRequire("config.ResourceDefs")
        local NumberUtil = isolatedRequire("core.NumberUtil")
        local Protocol = isolatedRequire("shared.Protocol")
        local STATUS = TaskConfig.STATUS
        local MAX_LEVEL, STEP, ROW_H, GAP = 200, 204, 184, 20
        local LIST_Y, LIST_H, MAX_SCROLL = 646, 1544, 39256
        local milestones = { 5, 10, 20, 30, 50, 80, 100, 150, 200 }
        local function snapshot() return Progress.build(modules.player, modules.task, modules.battle) end
        local function bonusId(level) return "a_plv_bonus_v1_" .. level end
        local function scrollOf(content) return LIST_Y - content.y end
        local function rowFor(content, level)
            return assert(content.root:FindById(bonusId(level)), "可见窗口缺少等级 " .. level)
        end
        local function rowY(content, level) return content.y + (level - 1) * STEP + ROW_H * 0.5 end
        local function drawRaw()
            draws, texts, clips, rects = {}, {}, {}, {}
            Page.draw(vg)
            check(#stack == 0 and transform.x == 0 and transform.y == 0, "绘制完整恢复宿主变换栈")
            return draws[1], draws[2]
        end
        ---@return ExpeditionTestDraw, ExpeditionTestDraw
        local function draw()
            local summary, content = drawRaw()
            assert(summary and content, "远征页必须绘制摘要和内容树")
            return summary, content
        end
        local function noActionAt(x, y, message)
            local count = #actions
            Page.handleInput(x, y)
            check(#actions == count, message)
        end
        local function assertAction(action, expected, message)
            local sent = assert(actions[#actions], message .. "缺少动作")
            check(sent.action == action, message .. "动作类型")
            local count, wanted = 0, 0
            for key, value in pairs(expected) do
                wanted = wanted + 1
                check(sent.params[key] == value, message .. "参数 " .. key)
            end
            for _ in pairs(sent.params) do count = count + 1 end
            check(count == wanted, message .. "无额外参数")
        end
        local function nodeCount(root)
            local count = 1
            for _, child in ipairs(root.children) do count = count + nodeCount(child) end
            return count
        end
        local function assertSummary(summary)
            check(summary.x == 48 and summary.y == 470 and summary.w == 984 and summary.h == 152,
                "摘要使用summaryY470/H152设计坐标")
            local ids = { level = true, exp = true, progress = true, claimable = true }
            check(#summary.root.children == 4, "摘要仅保留四个控件")
            for _, child in ipairs(summary.root.children) do
                check(ids[child.props.id] and child.props.top + child.props.height <= 152,
                    "摘要字段在高度内 " .. child.props.id)
            end
            for _, id in ipairs({ "next", "current", "stages", "ledger" }) do
                check(not summary.root:FindById(id), "摘要移除旧字段 " .. id)
            end
        end
        local function fittedMeasures()
            local count = 0
            for _, entry in ipairs(measurements) do
                if entry.size == 25 or entry.size == 18 then count = count + 1 end
            end
            return count
        end
        local function fontSizeSets()
            local count = 0
            for _, widget in ipairs(widgets) do count = count + widget.fontSizeSets end
            return count
        end
        local function assertFitted(widget, value, size, message)
            local measured = measuredWidth(value, size)
            local expected = (measured > 150 and size * 150 / measured or size) * 0.75
            local found = false
            for _, entry in ipairs(measurements) do
                if entry.value == value and entry.size == size and entry.measured == measured then found = true end
            end
            check(found and widget.fontSizeSets > 0 and math.abs(widget.props.fontSize - expected) < 1e-9,
                message .. "宿主原字号测宽后显式SetStyle缩字")
            check(widget.props.width == 154 and measured * (widget.props.fontSize / 0.75) / size <= 150 + 1e-9
                and widget.props.autoFitText == nil and widget.props.minFontSize == nil
                and (widget.props.whiteSpace == nil or widget.props.whiteSpace == "nowrap")
                and (widget.props.maxLines == nil or widget.props.maxLines == 1),
                message .. "单行宽度最多150且无无效autoFit/最小字号截断")
        end
        local function assertVisible(summary, content, model, loading)
            local scroll = scrollOf(content)
            local first = math.max(1, math.floor(scroll / STEP) + 1)
            local last = math.min(MAX_LEVEL, math.ceil((scroll + LIST_H) / STEP) + 1)
            check(content.x == 48 and content.w == 984 and content.h == MAX_LEVEL * STEP,
                "内容高度仍为200*204而非可见行高度")
            check(#content.root.children == last - first + 1 and #content.root.children <= 10,
                "只创建floor/ceil范围内少量行 " .. first .. ".." .. last)
            check(clips[2].x == 48 and clips[2].y == 470 and clips[2].h == 152
                and clips[3].x == 48 and clips[3].y == LIST_Y and clips[3].w == 984 and clips[3].h == LIST_H,
                "摘要与列表裁剪保持独立且列表y646/h1544")
            local glowing = 0
            for index, panel in ipairs(content.root.children) do
                local level = first + index - 1
                local row = model.rows[level]
                check(panel.props.id == bonusId(level) and panel.props.top == (level - 1) * STEP
                    and panel.props.height == ROW_H + GAP and #panel.children == 4,
                    "逐级行位置/step/四层结构 Lv." .. level)
                local line, halo, sphere, card = panel.children[1], panel.children[2], panel.children[3], panel.children[4]
                check(line.props.id == "line" and halo.props.id == "halo"
                    and sphere.props.id == "sphere" and card.props.id == "card", "先连接线后光晕圆球卡片 Lv." .. level)
                check(sphere.props.width == 96 and sphere.props.height == 96 and sphere.props.borderRadius == 48
                    and sphere.props.backgroundGradient.direction == "to-bottom-right"
                    and sphere.props.backgroundGradient.from[1] ~= sphere.props.backgroundGradient.to[1],
                    "圆球采用圆形与明暗渐变声明 Lv." .. level)
                check(#sphere.children == 1 and sphere.children[1].props.id == "level"
                    and sphere.children[1].props.text == tostring(level), "等级文字只在球内 Lv." .. level)
                check(line.props.left + line.props.width * 0.5 == sphere.props.left + sphere.props.width * 0.5,
                    "连接线与圆球中心同轴 Lv." .. level)
                local centerY = sphere.props.top + sphere.props.height * 0.5
                local expectedTop = level == 1 and centerY or 0
                local expectedBottom = level == MAX_LEVEL and centerY or STEP
                check(line.props.top == expectedTop and line.props.top + line.props.height == expectedBottom,
                    "首尾连接止于球心/中间延续step Lv." .. level)
                if index > 1 then
                    local prev = content.root.children[index - 1]
                    local prevLine = prev:FindById("line")
                    check(prev.props.top + prevLine.props.top + prevLine.props.height == panel.props.top + line.props.top,
                        "相邻圆球线段无缝连接 Lv." .. level)
                end
                check(not panel:FindById("unlock") and not panel:FindById("unlocks")
                    and not panel:FindById("ledger"), "节点不再显示解锁/旧台账区 Lv." .. level)
                check(card.props.top == 8 and card.props.height == ROW_H - 16
                    and #card.children == 3 + #row.tasks * 4, "卡片包含标题/当前/领取及各项名称/数量/图标/状态 Lv." .. level)
                check(card:FindById("title").props.text == "Lv." .. level .. " · " .. I18n.lookup("等级奖励"),
                    "逐级标题正确 Lv." .. level)
                local current = not loading and row.current
                check(card:FindById("current").props.text == (current and I18n.lookup("当前等级") or ""),
                    "当前等级标记正确 Lv." .. level)
                if halo.props.opacity > 0 then glowing = glowing + 1 end
                check((halo.props.opacity > 0) == current, "仅真实当前等级发光 Lv." .. level)
                for rewardIndex, task in ipairs(row.tasks) do
                    local nameWidget = card:FindById("reward_" .. rewardIndex)
                    local amountWidget = card:FindById("amount_" .. rewardIndex)
                    check(nameWidget.props.text == I18n.lookup(ResourceDefs.DEFS[task.reward.type].name)
                        and amountWidget.props.text == "× " .. NumberUtil.format(task.reward.amount)
                        and card:FindById("icon_" .. rewardIndex).props.backgroundImage == ResourceDefs.DEFS[task.reward.type].iconPath,
                        "奖励真实名称/数量分离且同源图标 Lv." .. level .. " 项" .. rewardIndex)
                    check(nameWidget.props.top == 50 and nameWidget.props.height == 34,
                        "奖励名称25号基准/34高独立区域 Lv." .. level .. " 项" .. rewardIndex)
                    assertFitted(nameWidget, nameWidget.props.text, 25, "奖励名称 Lv." .. level .. " 项" .. rewardIndex)
                    check(amountWidget.props.top == 84 and amountWidget.props.height == 32
                        and amountWidget.props.fontSize == 27 * 0.75
                        and amountWidget.props.left == nameWidget.props.left and amountWidget.props.width == 154
                        and nameWidget.props.top + nameWidget.props.height == amountWidget.props.top,
                        "数量独立27号32高不受名称折行挤占 Lv." .. level .. " 项" .. rewardIndex)
                    local expectedState = task.status == STATUS.CLAIMED and I18n.lookup("已领取")
                        or (task.taskId == row.taskId and I18n.lookup("每级额外奖励") or I18n.lookup("远征勋记"))
                    local stateWidget = card:FindById("state_" .. rewardIndex)
                    check(stateWidget.props.text == expectedState,
                        "奖励独立台账状态 Lv." .. level .. " 项" .. rewardIndex)
                    check(stateWidget.props.top == 116 and stateWidget.props.height == 32
                        and amountWidget.props.top + amountWidget.props.height == stateWidget.props.top
                        and stateWidget.props.top + stateWidget.props.height <= card.props.height,
                        "奖励状态单行18号基准/32高且留在卡片内 Lv." .. level .. " 项" .. rewardIndex)
                    assertFitted(stateWidget, expectedState, 18, "奖励状态 Lv." .. level .. " 项" .. rewardIndex)
                end
                check(not card:FindById("reward_" .. (#row.tasks + 1))
                    and not card:FindById("amount_" .. (#row.tasks + 1)), "不产生多余奖励名称或数量控件 Lv." .. level)
                local claim = card:FindById("claim")
                local expectedClaim = loading and "加载中" or (row.status == STATUS.CLAIMED and "已领取"
                    or (row.status == STATUS.CLAIMABLE and "领取" or "未达成"))
                check(claim.props.text == I18n.lookup(expectedClaim)
                    and claim.props.disabled == (loading or row.status ~= STATUS.CLAIMABLE), "聚合行领取状态正确 Lv." .. level)
            end
            local currentVisible = not loading and model.level >= first and model.level <= last
            check(glowing == (currentVisible and 1 or 0), "可见树当前等级唯一发光/不可见时无发光")
            local alive = 0
            for _, widget in ipairs(widgets) do
                if not widget.destroyed then
                    alive = alive + 1
                    assert(widget.props.pointerEvents == "none", "控件输入必须由手工宿主消费")
                    if widget.props.fontFamily then
                        assert(widget.props.fontFamily == "sans" and widget.props.fontWeight == "normal", "控件必须复用宿主sans字体")
                    end
                end
            end
            check(alive == nodeCount(summary.root) + nodeCount(content.root) and alive < 160,
                "旧可见树递归销毁且活跃树少于160控件，无隐藏200行")
        end
        local function stableDraw(message)
            local setters, created, images = setterCalls, #widgets, imageCreates
            local measured, styles = fittedMeasures(), fontSizeSets()
            local summary, content = draw()
            check(setterCalls == setters and #widgets == created and imageCreates == images,
                message .. "不重复SetText/建树/载图")
            -- TaskPage整页按钮仍按帧测宽；这里只限制名称25/状态18的签名刷新测宽。
            check(fittedMeasures() == measured and fontSizeSets() == styles,
                message .. "不重复名称/状态测宽或SetStyle字号")
            return summary, content
        end
        local function scrollTo(content, value)
            Page.handleScroll((scrollOf(content) - value) / 48)
            return draw()
        end
        local function claimLevel(content, level)
            local count = #actions
            Page.handleInput(300, rowY(content, level))
            check(#actions == count + 1, "行点击只发送一次逐级领取 Lv." .. level)
            assertAction(Protocol.ACTION_TYPES.CLAIM_ALL_TASKS, { scope = "level", level = level }, "逐级领取 Lv." .. level)
        end

        check(not pcall(isolatedRequire, "runtime.PlayerStore"), "隔离require拒绝真实PlayerStore")
        check(not pcall(File), "隔离文件入口拒绝存档访问")
        Page.init(vg)
        check(uiInits == 1 and not Page.isOpen(), "初始化只建UI上下文不自动打开页")
        check(Page.getExpeditionClaimableCount() == 30 and Page.hasClaimable(), "可领数按等级聚合，旧Lv5已领仍有新增奖励")
        local initialPlayer = modules.player
        for _, case in ipairs({ { name = "nil", normalized = 1 }, { name = "NaN", value = 0 / 0, normalized = 1 },
            { name = "+inf", value = math.huge, normalized = 1 }, { name = "-inf", value = -math.huge, normalized = 1 },
            { name = "0", value = 0, normalized = 1 }, { name = "201", value = 201, normalized = 200 },
            { name = "30.7", value = 30.7, normalized = 30 } }) do
            modules.player = { level = case.value, exp = 42 }
            local normalized = snapshot()
            check(normalized.level == case.normalized
                and Page.getExpeditionClaimableCount() == normalized.claimableCount,
                "红点等级规范化与Progress.build一致 " .. case.name)
            local buildsBefore, settersBefore, widgetsBefore = progressBuilds, setterCalls, #widgets
            for _ = 1, 3 do
                check(not Page.isOpen() and Page.getExpeditionClaimableCount() == normalized.claimableCount
                    and Page.hasClaimable(), "关闭页面查询红点只计数 " .. case.name)
            end
            check(progressBuilds == buildsBefore and setterCalls == settersBefore and #widgets == widgetsBefore,
                "关闭页面红点查询不调用Progress.build/SetText/建树 " .. case.name)
        end
        modules.player = initialPlayer
        local model = snapshot()
        check(#model.rows == MAX_LEVEL and #TaskConfig.LEVEL_TASKS == MAX_LEVEL
            and model.focusIndex == 30 and model.claimableCount == 30, "真实模型200逐级行/当前等级focus/聚合可领数")
        local totalTasks, currentCount = 0, 0
        for level = 1, MAX_LEVEL do
            local row = model.rows[level]
            local tasks = TaskConfig.LEVEL_TASKS[level]
            check(row.level == level and row.taskId == bonusId(level) and #row.tasks == #tasks,
                "200模型每级只有一个聚合row Lv." .. level)
            local bonus = TaskConfig.findById(bonusId(level))
            check(bonus.target == level and bonus.reward.type == "diamond" and bonus.reward.amount == 100,
                "每级新增独立100黑晶奖励 Lv." .. level)
            for index, task in ipairs(tasks) do
                totalTasks = totalTasks + 1
                check(row.tasks[index].taskId == task.id and row.tasks[index].reward == task.reward,
                    "模型聚合真实任务不重写配置 Lv." .. level .. " 项" .. index)
            end
            check(row.status == (level <= 30 and STATUS.CLAIMABLE or STATUS.LOCKED), "玩家真实等级而非achProg控制可领 Lv." .. level)
            if row.current then currentCount = currentCount + 1 end
        end
        check(totalTasks == 209 and currentCount == 1 and model.rows[30].current, "九里程碑加200新任务聚合200行/唯一当前等级")
        check(model.rows[5].tasks[1].status == STATUS.CLAIMED and model.rows[5].tasks[2].status == STATUS.CLAIMABLE,
            "旧里程碑已领与新增100黑晶可领分别保留")

        Page.open("level")
        local summary, content = draw()
        check(Page.isOpen() and refreshes == 1 and scrollOf(content) == (30 - 2) * STEP,
            "打开定位当前Lv30上一级而非首个可领奖励")
        assertSummary(summary)
        assertVisible(summary, content, model, false)
        check(summary.root:FindById("level").props.text == "远征等级 Lv.30"
            and summary.root:FindById("exp").props.text:find("42", 1, true)
            and summary.root:FindById("claimable").props.text == "可领 30 项"
            and summary.root:FindById("progress").props.value == model.ratio, "摘要读取真实等级/经验/聚合可领数/ratio")
        local tabs = {}
        for _, rect in ipairs(rects) do if rect.y == 360 and rect.h == 72 then tabs[#tabs + 1] = rect end end
        check(#tabs == 3, "宿主保留三个页签")
        for index, center in ipairs({ 270, 540, 810 }) do
            check(tabs[index].w == 244 and tabs[index].x + tabs[index].w * 0.5 == center, "页签宽244中心" .. center)
            if index > 1 then check(tabs[index].x - tabs[index - 1].x - tabs[index - 1].w == 26, "页签间距26") end
        end
        for _, x in ipairs({ 393, 405, 417, 663, 675, 687 }) do
            noActionAt(x, 396, "页签间距不领取 x=" .. x)
            local _, after = draw()
            check(after.root == content.root and scrollOf(after) == scrollOf(content), "页签间距不切换或重定位 x=" .. x)
        end
        stableDraw("相同快照重复draw")
        clock.elapsedTime = 101
        stableDraw("当前光晕呼吸只改opacity")
        noActionAt(300, 600, "摘要不命中领奖")
        noActionAt(300, 634, "摘要列表间距不命中领奖")
        noActionAt(300, LIST_Y + ROW_H + GAP * 0.5, "20高行间距不命中领奖")
        noActionAt(47, rowY(content, 30), "列表左边界外不领取")
        noActionAt(1033, rowY(content, 30), "列表右边界外不领取")
        noActionAt(300, 2191, "列表底部clip外不领取")
        claimLevel(content, 30)
        check(not modules.task.achClaimed.a_plv_30 and not modules.task.achClaimed[bonusId(30)]
            and modules.currency.gold == 123 and modules.currency.gems == 456, "行点击不直接写永久台账/发奖")
        local count = #actions
        Page.handleInput(860, 300)
        check(#actions == count + 1, "整页一键领取只发送一次动作")
        assertAction(Protocol.ACTION_TYPES.CLAIM_ALL_TASKS, { scope = "level" }, "整页批领只有scope")
        -- 手动模拟权威快照到达，而非让动作 mock 发奖。
        local root, position = content.root, scrollOf(content)
        modules.task.achClaimed.a_plv_30 = true
        summary, content = draw()
        check(content.root == root and scrollOf(content) == position
            and rowFor(content, 30):FindById("state_1").props.text == "已领取"
            and not rowFor(content, 30):FindById("claim").props.disabled, "旧项领取后新增项仍可领且不跳滚动")
        claimLevel(content, 30)
        modules.task.achClaimed[bonusId(30)] = true
        summary, content = draw()
        check(content.root == root and scrollOf(content) == position
            and rowFor(content, 30):FindById("claim").props.text == "已领取", "等级全部领取后原位置与树不变")
        assertVisible(summary, content, snapshot(), false)
        check(rowFor(content, 30):FindById("halo").props.opacity > 0, "当前等级已领仍然发光")
        noActionAt(300, rowY(content, 30), "已领聚合行不再发动作")
        stableDraw("领取快照更新后重复draw")
        Page.openExpedition()
        _, content = draw()
        check(scrollOf(content) == (30 - 2) * STEP, "openExpedition不受首个可领变化影响")
        Page.open()
        _, content = draw()
        check(content and scrollOf(content) == position, "无参数open保留level页签并定位当前等级")

        modules.player = { level = 200, exp = 42 }
        modules.task.achClaimed = {}
        for _, level in ipairs(milestones) do modules.task.achClaimed["a_plv_" .. level] = true end
        check(Page.getExpeditionClaimableCount() == 200, "满级旧九项已领仍有200逐级新增可领")
        Page.openExpedition()
        summary, content = draw()
        check(scrollOf(content) == MAX_SCROLL and MAX_SCROLL == MAX_LEVEL * STEP - LIST_H, "满级定位受39256最大滚动限制")
        assertSummary(summary)
        assertVisible(summary, content, snapshot(), false)
        check(summary.root:FindById("exp").props.text == I18n.lookup("经验进度 · 已达等级上限"), "满级经验不出现零分母")
        for _, level in ipairs(milestones) do
            summary, content = scrollTo(content, math.min(MAX_SCROLL, math.max(0, (level - 2) * STEP)))
            local panel = rowFor(content, level)
            check(#snapshot().rows[level].tasks == 2 and panel:FindById("state_1").props.text == "已领取"
                and panel:FindById("state_2").props.text == "每级额外奖励"
                and panel:FindById("reward_2").props.text == I18n.lookup(ResourceDefs.DEFS.diamond.name)
                and panel:FindById("amount_2").props.text == "× 100"
                and not panel:FindById("claim").props.disabled, "九个里程碑分别展示旧已领及新增100可领 Lv." .. level)
            assertVisible(summary, content, snapshot(), false)
        end
        -- 英文长名称不能吞掉独立数量；校验真实旧奖励840/120k及新增100。
        I18n.set("en")
        for _, case in ipairs({ { level = 100, amount = 840, text = "× 840" },
            { level = 150, amount = 120000, text = "× 120k" } }) do
            summary, content = scrollTo(content, (case.level - 2) * STEP)
            local panel = rowFor(content, case.level)
            local reward = TaskConfig.findById("a_plv_" .. case.level).reward
            check(reward.amount == case.amount
                and panel:FindById("reward_1").props.text == I18n.lookup(ResourceDefs.DEFS[reward.type].name)
                and panel:FindById("amount_1").props.text == case.text
                and panel:FindById("reward_2").props.text == I18n.lookup(ResourceDefs.DEFS.diamond.name)
                and panel:FindById("amount_2").props.text == "× 100",
                "英文真实奖励名称与数量独立保留 " .. case.text .. " / × 100 Lv." .. case.level)
            assertVisible(summary, content, snapshot(), false)
            stableDraw("英文独立数量" .. case.text .. "重复draw")
        end
        I18n.set("zh_CN")
        summary, content = draw()
        for level = 1, MAX_LEVEL do
            for _, task in ipairs(TaskConfig.LEVEL_TASKS[level]) do modules.task.achClaimed[task.id] = true end
        end
        Page.openExpedition()
        summary, content = draw()
        check(scrollOf(content) == MAX_SCROLL and Page.getExpeditionClaimableCount() == 0, "全200等级已领保持终点定位/零可领")
        assertVisible(summary, content, snapshot(), false)
        noActionAt(300, rowY(content, 200), "全部已领终点行不领取")
        noActionAt(860, 300, "全部已领整页不领取")
        local oldRoot = content.root
        Page.handleScroll(1000)
        summary, content = draw()
        check(scrollOf(content) == 0 and oldRoot.destroyed, "滚轮到首端并销毁旧窗口树")
        assertVisible(summary, content, snapshot(), false)
        check(rowFor(content, 1):FindById("line").props.top == 92, "首球连接线不向虚构Lv0延伸")
        Page.handleScroll(-1000)
        summary, content = draw()
        check(scrollOf(content) == MAX_SCROLL, "滚轮下界统一为39256")
        check(rowFor(content, 200):FindById("line").props.height == 92, "尾球连接线不向虚构Lv201延伸")

        modules.task.achClaimed = {}
        for _, level in ipairs({ 1, 2, 5, 30, 100, 199, 200 }) do
            modules.player.level = level
            Page.openExpedition()
            summary, content = draw()
            check(scrollOf(content) == math.min(MAX_SCROLL, math.max(0, (level - 2) * STEP)), "打开上一级定位公式 Lv." .. level)
            assertVisible(summary, content, snapshot(), false)
        end
        modules.player = { level = 1, exp = 0 }
        modules.task.achClaimed = { [bonusId(1)] = true }
        Page.openExpedition()
        summary, content = draw()
        check(scrollOf(content) == 0 and Page.getExpeditionClaimableCount() == 0, "Lv1已领时无其他可领但仍保留逐级列表")
        noActionAt(300, rowY(content, 2), "未来未达成行不领取")
        noActionAt(860, 300, "无可领奖励整页不发送动作")
        assertVisible(summary, content, snapshot(), false)

        modules.player = { level = 30, exp = 0 }
        modules.task.achClaimed = {}
        Page.openExpedition()
        _, content = draw()
        local dragScroll = scrollOf(content)
        Page.handleDragBegin(300, 950)
        Page.handleDragMove(300, 880)
        Page.handleDragEnd(300, 880)
        noActionAt(300, 950, "纵向拖动释放拦误领")
        summary, content = draw()
        check(scrollOf(content) == dragScroll + 70, "列表纵向拖动在原定位上增加70")
        assertVisible(summary, content, snapshot(), false)
        Page.handleDragBegin(300, 950)
        Page.handleDragMove(320, 950)
        Page.handleDragEnd(320, 950)
        noActionAt(540, 396, "横向拖动释放不误切页签或领取")
        _, content = draw()
        check(scrollOf(content) == dragScroll + 70, "横向滑动不改变列表位置")
        Page.handleDragBegin(300, 600)
        Page.handleDragMove(300, 550)
        Page.handleDragEnd(300, 550)
        noActionAt(860, 300, "摘要拖动释放不误触整页领取")
        _, content = draw()
        check(scrollOf(content) == dragScroll + 70, "摘要起拖不会滚动列表")
        local tapY = rowY(content, 30)
        Page.handleDragBegin(300, tapY)
        Page.handleDragMove(303, tapY - 3)
        Page.handleDragEnd(303, tapY - 3)
        claimLevel(content, 30)

        modules.player = nil
        Page.openExpedition()
        summary, content = draw()
        check(scrollOf(content) == 0 and Page.getExpeditionClaimableCount() == 0
            and summary.root:FindById("level").props.text == I18n.lookup("远征等级 · 加载中")
            and summary.root:FindById("progress").props.value == 0, "缺玩家数据仅加载态/零可领/零进度不提前定位")
        assertVisible(summary, content, snapshot(), true)
        stableDraw("玩家加载中重复draw")
        noActionAt(300, rowY(content, 1), "玩家加载中不逐级领取")
        noActionAt(860, 300, "玩家加载中不整页领取")
        modules.player = { level = 30, exp = 42 }
        summary, content = draw()
        check(scrollOf(content) == (30 - 2) * STEP, "玩家加载完成后只定位当前等级上一级")
        stableDraw("加载完成相同快照")
        modules.task = nil
        Page.openExpedition()
        summary, content = draw()
        check(scrollOf(content) == 0 and rowFor(content, 1):FindById("claim").props.text == "加载中",
            "台账未加载按钮禁用且定位等待")
        assertVisible(summary, content, snapshot(), true)
        stableDraw("台账加载中重复draw")
        noActionAt(300, rowY(content, 1), "台账加载中不逐级领取")
        noActionAt(860, 300, "台账加载中不整页领取")
        modules.task = { achProg = { hero_count = 4, clear_101 = 1 }, achClaimed = {} }
        summary, content = draw()
        check(scrollOf(content) == (30 - 2) * STEP, "台账加载完成再定位且不使用achProg替代等级")
        stableDraw("台账加载完成重复draw")

        Page.open("clear")
        local clearSummary, clearContent = drawRaw()
        check(not clearSummary and not clearContent and table.concat(texts, "|"):find("通关", 1, true), "clear保留原功绩绘制页")
        count = #actions
        Page.handleInput(300, 570)
        check(#actions == count + 1, "clear只发送一次单领奖励动作")
        assertAction(Protocol.ACTION_TYPES.CLAIM_TASK, { taskId = "a_clear_101" }, "clear保留既有单领协议")
        Page.handleInput(860, 300)
        assertAction(Protocol.ACTION_TYPES.CLAIM_ALL_TASKS, { scope = "clear" }, "clear保留批领scope")
        Page.open("hero")
        drawRaw()
        count = #actions
        Page.handleInput(300, 570)
        check(#actions == count + 1, "hero只发送一次单领奖励动作")
        assertAction(Protocol.ACTION_TYPES.CLAIM_TASK, { taskId = "a_hero_4" }, "hero保留既有单领协议")
        Page.handleInput(860, 300)
        assertAction(Protocol.ACTION_TYPES.CLAIM_ALL_TASKS, { scope = "hero" }, "hero保留批领scope")
        Page.handleInput(540, 396)
        summary, content = draw()
        check(summary and content and scrollOf(content) == (30 - 2) * STEP, "中心540点击切入逐级远征页")

        modules.task.achClaimed = { a_plv_30 = true }
        Page.openExpedition()
        summary, content = draw()
        local sourceUnlock = Progress.getRangeUnlocks(1, 60)[1].unlockName
        local sourceTask = TaskConfig.findById("a_plv_30")
        local sourceName, sourceDesc = sourceTask.name, sourceTask.desc
        for _, language in ipairs({ "zh_TW", "en", "ja", "ko", "zh_CN" }) do
            I18n.set(language)
            root, position = content.root, scrollOf(content)
            summary, content = draw()
            check(content.root == root and scrollOf(content) == position, language .. "切语言不建树或跳滚动")
            check(summary.root:FindById("level").props.text == I18n.format("远征等级 Lv.%d", 30)
                and summary.root:FindById("claimable").props.text == I18n.format("可领 %d 项", 30), language .. "摘要即时更新译文")
            local panel = rowFor(content, 30)
            check(panel:FindById("title").props.text == "Lv.30 · " .. I18n.lookup("等级奖励")
                and panel:FindById("current").props.text == I18n.lookup("当前等级"), language .. "逐级标题与当前等级翻译")
            check(panel:FindById("reward_1").props.text == I18n.lookup(ResourceDefs.DEFS[sourceTask.reward.type].name)
                and panel:FindById("amount_1").props.text == "× " .. NumberUtil.format(sourceTask.reward.amount)
                and panel:FindById("reward_2").props.text == I18n.lookup(ResourceDefs.DEFS.diamond.name)
                and panel:FindById("amount_2").props.text == "× 100"
                and panel:FindById("state_1").props.text == I18n.lookup("已领取")
                and panel:FindById("state_2").props.text == I18n.lookup("每级额外奖励")
                and panel:FindById("claim").props.text == I18n.lookup("领取"), language .. "多项奖励/各自台账/领取同步翻译")
            check(Progress.getRangeUnlocks(1, 60)[1].unlockName == sourceUnlock
                and sourceTask.name == sourceName and sourceTask.desc == sourceDesc, language .. "不改写共享配置/解锁缓存原文")
            stableDraw(language .. "同语言同数据重复draw")
        end
        -- 任意长译文通过只读I18n代理注入，测宽独立于字符数，禁止写生产配置/词典。
        for index, case in ipairs({ { width = 149, length = 7 }, { width = 150, length = 21 },
            { width = 151, length = 3 }, { width = 900, length = 64 }, { width = 9000, length = 1024 } }) do
            local longName = "Resource " .. string.rep("W", case.length)
            local longBonusState = "Extra reward " .. string.rep("S", case.length)
            local longClaimedState = "Claimed reward " .. string.rep("C", case.length)
            translationOverrides[ResourceDefs.DEFS.diamond.name] = longName
            translationOverrides[ResourceDefs.DEFS[sourceTask.reward.type].name] = longName
            translationOverrides["每级额外奖励"] = longBonusState
            translationOverrides["已领取"] = longClaimedState
            widthOverrides[longName], widthOverrides[longBonusState], widthOverrides[longClaimedState]
                = case.width, case.width, case.width
            I18n.set(index % 2 == 1 and "en" or "ja")
            root, position = content.root, scrollOf(content)
            local measuredBefore = fittedMeasures()
            summary, content = draw()
            check(content.root == root and scrollOf(content) == position and fittedMeasures() > measuredBefore,
                "任意长译文签名刷新时测宽但不重建/跳滚动 width=" .. case.width)
            local panel = rowFor(content, 30)
            for rewardIndex, stateText in ipairs({ longClaimedState, longBonusState }) do
                local nameWidget = panel:FindById("reward_" .. rewardIndex)
                local stateWidget = panel:FindById("state_" .. rewardIndex)
                check(nameWidget.props.text == longName and stateWidget.props.text == stateText,
                    "任意长名称/状态完整保留不截字 width=" .. case.width .. " 项" .. rewardIndex)
                assertFitted(nameWidget, longName, 25, "任意长名称 width=" .. case.width .. " 项" .. rewardIndex)
                assertFitted(stateWidget, stateText, 18, "任意长状态 width=" .. case.width .. " 项" .. rewardIndex)
                if case.width <= 150 then
                    check(nameWidget.props.fontSize == 25 * 0.75 and stateWidget.props.fontSize == 18 * 0.75,
                        "测宽不超150时保持基准字号 width=" .. case.width .. " 项" .. rewardIndex)
                elseif case.width >= 900 then
                    check(nameWidget.props.fontSize < 15 * 0.75 and stateWidget.props.fontSize < 15 * 0.75,
                        "极长译文继续缩字而非最小15号裁切 width=" .. case.width .. " 项" .. rewardIndex)
                end
            end
            check(panel:FindById("amount_1").props.text == "× " .. NumberUtil.format(sourceTask.reward.amount)
                and panel:FindById("amount_2").props.text == "× 100"
                and panel:FindById("amount_1").props.fontSize == 27 * 0.75
                and panel:FindById("amount_2").props.fontSize == 27 * 0.75,
                "任意长名称/状态缩字不挤掉独立数量 width=" .. case.width)
            stableDraw("任意长译文width=" .. case.width .. "同快照")
        end
        translationOverrides, widthOverrides = {}, {}
        I18n.set("zh_CN")
        summary, content = draw()
        check(ResourceDefs.DEFS.diamond.name == "黑晶" and sourceTask.name == sourceName
            and sourceTask.desc == sourceDesc, "长译文测宽测试不改写真实资源/任务配置")
        assertVisible(summary, content, snapshot(), false)
        stableDraw("恢复真实词典后同快照")
        Page.close()
        noActionAt(300, rowY(content, 30), "关闭动画期间不领取")
        check(not Page.handleDragBegin(300, 950) and not Page.handleScroll(-1), "关闭动画期间不再滚动")
        clock.elapsedTime = 102
        Page.update(1)
        check(not Page.isOpen() and not Page.handleInput(300, 950), "动画结束完整关闭且不消费输入")
        check(modules.currency.gold == 123 and modules.currency.gems == 456
            and modules.task.achClaimed.a_plv_30 and not modules.task.achClaimed[bonusId(30)]
            and modules.task.achProg.hero_count == 4 and modules.task.achProg.clear_101 == 1,
            "全程动作只记录不发奖/写业务进度或玩家台账")
    end)

    I18n.set(originalLanguage)
    local loadedNames = {}
    for name in pairs(package.loaded) do loadedNames[#loadedNames + 1] = name end
    for _, name in ipairs(loadedNames) do package.loaded[name] = savedModules[name] end
    for name, value in pairs(savedModules) do package.loaded[name] = value end
    for _, name in ipairs(globalNames) do rawset(_G, name, savedGlobals[name]) end
    if not ok then error(err) end
    check(require == originalRequire and I18n.get() == originalLanguage, "退出恢复原require与语言")
    for _, name in ipairs(globalNames) do
        assert(rawget(_G, name) == savedGlobals[name], "未恢复测试全局 " .. name)
    end
    for name, value in pairs(package.loaded) do
        assert(value == savedModules[name], "模块缓存泄漏 " .. name)
    end
    check(true, "退出恢复全部替换全局与模块缓存，无mock污染")
end

function Start()
    local ok, err = pcall(runTests)
    if ok then print("[expedition_track_ui_test] ALL PASS assertions=" .. assertions)
    else
        print("[expedition_track_ui_test] FAIL " .. tostring(err))
        log:Write(LOG_ERROR, tostring(err))
    end
    engine:Exit()
end
