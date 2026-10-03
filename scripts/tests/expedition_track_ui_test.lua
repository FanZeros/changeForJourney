-- 远征轨道隔离回归：真实 TaskPage 与 View，数据、动作及绘图全部内存 mock。
-- 不初始化 PlayerStore，不调用真实领取服务，不读取或写入玩家存档。
local assertions = 0
local function check(value, message)
    assert(value, message)
    assertions = assertions + 1
    print("[expedition_track_ui_test] PASS " .. message)
end

local function runTests()
    local originalRequire = require
    local savedGlobals, globalNames = {}, {}
    local savedModules = {
        ["ui.story.task.TaskPage"] = package.loaded["ui.story.task.TaskPage"],
        ["ui.story.task.ExpeditionTrackView"] = package.loaded["ui.story.task.ExpeditionTrackView"],
    }
    local function replaceGlobal(name, value)
        globalNames[#globalNames + 1] = name
        savedGlobals[name] = rawget(_G, name)
        rawset(_G, name, value)
    end
    local widgets = {}
    local setterCalls = 0
    local function createWidget(props)
        props = props or {}
        local widget = { props = props, children = {}, destroyed = false }
        function widget:AddChild(child) self.children[#self.children + 1] = child return self end
        function widget:FindById(id)
            if self.props.id == id then return self end
            for _, child in ipairs(self.children) do
                local found = child:FindById(id)
                if found then return found end
            end
            return nil
        end
        function widget:SetText(value) setterCalls = setterCalls + 1 self.props.text = value end
        function widget:SetFontColor(value) self.props.fontColor = value end
        function widget:SetValue(value) self.props.value = value end
        function widget:SetDisabled(value) self.props.disabled = value end
        function widget:SetStyle(style) for key, value in pairs(style) do self.props[key] = value end end
        function widget:Destroy() self.destroyed = true end
        for _, child in ipairs(props.children or {}) do widget:AddChild(child) end
        widgets[#widgets + 1] = widget
        return widget
    end
    local modules = { player = { level = 30, exp = 42 }, task = {
        achProg = { player_level = 0 }, achClaimed = { a_plv_5 = true },
    }, battle = { clearedStages = { ["905"] = true } }, currency = { gold = 123, gems = 456 } }
    local actions, texts, draws, clips = {}, {}, {}, {}
    local refreshes, uiInits = 0, 0
    local transform = { x = 0, y = 0 }
    local stack = {}
    local noop = function() end
    local mocks = {
        ["urhox-libs/UI"] = { Panel = createWidget, Label = createWidget,
            Button = createWidget, ProgressBar = createWidget },
        ["ui.widget.DesignWidgetSurface"] = {
            init = function() uiInits = uiInits + 1 end,
            draw = function(root, _, w, h)
                draws[#draws + 1] = { root = root, x = transform.x, y = transform.y, w = w, h = h }
            end,
        },
        ["core.I18n"] = {
            lookup = function(value) return value end,
            format = function(value, ...) return string.format(value, ...) end,
            difficulty = function(value) return value end,
        },
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
    -- 只允许无副作用配置与被测模块；漏掉 mock 会直接失败，不落入真实存档链。
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
    local function isolatedRequire(name)
        if mocks[name] then return mocks[name] end
        assert(allowed[name], "测试禁止加载真实副作用模块 " .. tostring(name))
        return originalRequire(name)
    end
    replaceGlobal("require", isolatedRequire)
    replaceGlobal("time", { elapsedTime = 100 })
    for _, name in ipairs({ "nvgBeginPath", "nvgRoundedRect", "nvgRect", "nvgFillColor",
        "nvgFill", "nvgGlobalAlpha", "nvgFontFace", "nvgFontSize" }) do replaceGlobal(name, noop) end
    replaceGlobal("nvgTextBounds", function(_, _, _, value) return #value * 5 end)
    replaceGlobal("nvgSave", function() stack[#stack + 1] = { x = transform.x, y = transform.y } end)
    replaceGlobal("nvgRestore", function() transform = table.remove(stack) or { x = 0, y = 0 } end)
    replaceGlobal("nvgTranslate", function(_, x, y) transform.x = transform.x + x transform.y = transform.y + y end)
    replaceGlobal("nvgIntersectScissor", function(_, x, y, w, h) clips[#clips + 1] = { x = x, y = y, w = w, h = h } end)
    replaceGlobal("nvgCreateImage", function() return 1 end)
    replaceGlobal("nvgRGBA", function(r, g, b, a) return { r, g, b, a } end)
    replaceGlobal("nvgBeginFrame", function() error("视图禁止新建宿主 NanoVG 帧") end)
    replaceGlobal("nvgEndFrame", function() error("视图禁止结束宿主 NanoVG 帧") end)
    for index, name in ipairs({ "NVG_ALIGN_LEFT", "NVG_ALIGN_RIGHT", "NVG_ALIGN_CENTER",
        "NVG_ALIGN_MIDDLE", "NVG_ALIGN_BOTTOM" }) do replaceGlobal(name, index) end
    package.loaded["ui.story.task.TaskPage"] = nil
    package.loaded["ui.story.task.ExpeditionTrackView"] = nil

    local ok, err = pcall(function()
        local Page = isolatedRequire("ui.story.task.TaskPage")
        local Progress = isolatedRequire("config.ExpeditionProgress")
        local TaskConfig = isolatedRequire("config.TaskConfig")
        local ResourceDefs = isolatedRequire("config.ResourceDefs")
        local Protocol = isolatedRequire("shared.Protocol")
        local vg = {}
        local function draw()
            draws, texts, clips = {}, {}, {}
            Page.draw(vg)
            check(#stack == 0, "绘制完整恢复宿主变换栈")
            return draws[1], draws[2]
        end
        local function assertOrdered(content)
            local expected = { 5, 10, 20, 30, 50, 80, 100, 150, 200 }
            check(content and #content.root.children == 9, "轨道始终保留九个永久里程碑")
            for index, level in ipairs(expected) do
                local row = content.root.children[index]
                check(row.props.id == "a_plv_" .. level, "等级升序节点 Lv." .. level)
                check(row:FindById("reward").props.text == Progress.rewardLabel(TaskConfig.findById(row.props.id).reward),
                    "节点真实奖励名称数量 Lv." .. level)
            end
        end
        local function lastAction(action, key, value)
            local sent = actions[#actions]
            return sent and sent.action == action and sent.params[key] == value
        end
        local function firstRowY(content) return content.y + 124 end
        local function scrollOf(content) return 826 - content.y end
        local function noActionAt(x, y, label)
            local count = #actions
            Page.handleInput(x, y)
            check(#actions == count, label)
        end
        Page.init(vg)
        check(uiInits == 1, "TaskPage初始化先建UI上下文避免渲染回调更改顺序")
        check(not Page.isOpen(), "初始化不自动打开轨道")
        check(Page.getExpeditionClaimableCount() == 3, "可领数按真实玩家等级与永久台账计算")
        check(Page.hasClaimable(), "公共红点查询包含远征可领奖励")
        Page.open("level")
        check(Page.isOpen() and refreshes == 1, "open(level)直接打开远征页")
        local summary, content = draw()
        assertOrdered(content)
        check(scrollOf(content) == 276, "定位首个可领取Lv10而非重排已领Lv5")
        check(summary.root:FindById("level").props.text == "远征等级 Lv.30", "顶部展示真实远征等级")
        check(summary.root:FindById("exp").props.text:find("42", 1, true), "顶部展示经验数值")
        check(summary.root:FindById("next").props.text == "下一里程碑 · Lv.50", "顶部展示下一里程碑")
        check(summary.root:FindById("claimable").props.text == "可领 3 项", "顶部展示可领数")
        check(summary.root:FindById("progress").props.value == Progress.build(modules.player, modules.task, modules.battle).ratio,
            "顶部经验进度使用模型ratio")
        local currentText = summary.root:FindById("current").props.text
        check(currentText:find("每队 4 人", 1, true) and currentText:find("神器 1 格", 1, true), "顶部显示当前槽位及神器真实成长")
        local stageWidget = summary.root:FindById("stages")
        check(stageWidget.props.top + stageWidget.props.height <= summary.h, "通关开放说明受摘要高度约束")
        check(stageWidget.props.text:find("通关", 1, true) and not stageWidget.props.text:find("等级", 1, true), "队伍开放明确按通关而非等级")
        check(content.root.children[1]:FindById("level").props.text == "Lv.5", "已领历史等级不隐藏")
        local icon = content.root.children[2].children[2]
        local rewardDef = TaskConfig.findById("a_plv_10").reward
        check(icon.props.backgroundImage == ResourceDefs.DEFS[rewardDef.type].iconPath, "奖励图标复用ResourceDefs同源")
        check(content.root.children[1].children[6].props.text == "已领取", "已领取节点保留明确状态")
        check(content.root.children[2].children[6].props.text == "领取", "可领节点展示领取按钮")
        check(content.root.children[5].children[6].props.text == "未达成", "未来节点展示未达成")
        for _, widget in ipairs(widgets) do
            check(widget.props.pointerEvents == "none", "新控件输入只由手工宿主消费")
            if widget.props.fontFamily then check(widget.props.fontWeight == "normal", "新控件复用宿主sans字体") end
        end
        local setters = setterCalls
        draw()
        check(setterCalls == setters, "相同快照不会逐帧重复SetText")
        noActionAt(300, 600, "摘要区域不命中列表领奖")
        noActionAt(300, 826 + 248 + 14, "里程碑间距不命中领奖")
        noActionAt(47, 950, "列表左边界外不命中领奖")
        local actionCount = #actions
        Page.handleInput(300, 950)
        check(#actions == actionCount + 1 and lastAction(Protocol.ACTION_TYPES.CLAIM_TASK, "taskId", "a_plv_10"),
            "单领完整复用CLAIM_TASK协议taskId")
        check(not modules.task.achClaimed.a_plv_10 and modules.currency.gold == 123 and modules.currency.gems == 456,
            "视图不直接发奖或写已领台账")
        Page.handleInput(860, 300)
        check(lastAction(Protocol.ACTION_TYPES.CLAIM_ALL_TASKS, "scope", "level"), "一键领取完整复用scope=level协议")
        modules.task.achClaimed.a_plv_10 = true
        summary, content = draw()
        assertOrdered(content)
        check(scrollOf(content) == 276 and content.root.children[2].children[6].props.text == "已领取", "领取刷新不跳位置且保留原行")
        noActionAt(300, 950, "已领取不再发领取动作")

        Page.openExpedition()
        summary, content = draw()
        check(scrollOf(content) == 552, "openExpedition定位下一首个可领Lv20")
        Page.open()
        summary, content = draw()
        check(content ~= nil, "无参数open保留当前level页签")
        modules.player.level = 1
        modules.task.achClaimed = {}
        Page.openExpedition()
        summary, content = draw()
        check(scrollOf(content) == 0 and content.root.children[1].children[6].props.text == "未达成", "无可领定位下一未达节点")
        noActionAt(300, 950, "未达成节点不发领奖动作")
        noActionAt(860, 300, "无可领奖励时一键领取不发动作")
        check(Page.getExpeditionClaimableCount() == 0, "未达成返回零可领数")
        modules.player.level = 200
        for _, level in ipairs({ 5, 10, 20, 30, 50, 80, 100, 150, 200 }) do modules.task.achClaimed["a_plv_" .. level] = true end
        Page.openExpedition()
        summary, content = draw()
        check(scrollOf(content) == 1120, "全部已领定位最后节点并受最大滚动限制")
        check(summary.root:FindById("next").props.text == "全部里程碑已达成", "全里程碑达成显示终点")
        check(summary.root:FindById("exp").props.text:find("等级上限", 1, true), "满级经验展示不出现零分母")
        check(summary.root:FindById("current").props.text:find("神器 2 格", 1, true), "非里程碑神器Lv60成长持续可见")
        Page.handleScroll(1000)
        _, content = draw()
        check(scrollOf(content) == 0, "滚轮上界使用统一列表布局")
        Page.handleScroll(-1000)
        _, content = draw()
        check(scrollOf(content) == 1120, "滚轮下界使用统一列表布局")

        modules.player = { level = 30, exp = 0 }
        modules.task.achClaimed = {}
        Page.openExpedition()
        summary, content = draw()
        Page.handleDragBegin(300, 950)
        Page.handleDragMove(300, 880)
        Page.handleDragEnd(300, 880)
        noActionAt(300, 950, "纵向拖动释放dragMoved拦误领")
        _, content = draw()
        check(scrollOf(content) == 70, "拖动使用列表统一scroll和clip坐标")
        Page.handleDragBegin(300, 950)
        Page.handleDragMove(320, 950)
        Page.handleDragEnd(320, 950)
        noActionAt(300, 950, "横向滑动释放同样拦误领")
        Page.handleDragBegin(300, 600)
        Page.handleDragMove(300, 550)
        Page.handleDragEnd(300, 550)
        noActionAt(860, 300, "摘要拖动释放不误触一键领取")
        _, content = draw()
        check(scrollOf(content) == 70, "摘要起拖不会滚动里程碑列表")
        Page.handleDragBegin(300, 950)
        Page.handleDragMove(303, 947)
        Page.handleDragEnd(303, 947)
        Page.handleInput(300, 950)
        check(lastAction(Protocol.ACTION_TYPES.CLAIM_TASK, "taskId", "a_plv_5"), "阈值内正常点按仍能单领")

        modules.player = nil
        Page.openExpedition()
        summary, content = draw()
        check(Page.getExpeditionClaimableCount() == 0 and summary.root:FindById("level").props.text:find("加载中", 1, true),
            "缺玩家数据仅加载不可领")
        noActionAt(300, 950, "玩家加载时不单领")
        noActionAt(860, 300, "玩家加载时不一键领取")
        modules.player = { level = 30, exp = 42 }
        modules.task.achClaimed = { a_plv_5 = true }
        summary, content = draw()
        check(scrollOf(content) == 276, "加载完成后才定位首个可领取")
        modules.task = nil
        Page.openExpedition()
        summary, content = draw()
        check(content.root.children[2].children[6].props.text == "加载中", "台账未加载按钮明确禁用")
        noActionAt(300, 950, "台账加载时不单领")
        noActionAt(860, 300, "台账加载时不一键领取")
        modules.task = { achProg = { hero_count = 4, clear_101 = 1 }, achClaimed = {} }
        Page.open("clear")
        summary, content = draw()
        check(summary == nil and content == nil and table.concat(texts, "|"):find("通关", 1, true), "clear保留原功绩绘制页")
        Page.handleInput(300, 570)
        check(lastAction(Protocol.ACTION_TYPES.CLAIM_TASK, "taskId", "a_clear_101"), "clear保留既有单领协议")
        Page.open("hero")
        draw()
        Page.handleInput(300, 570)
        check(lastAction(Protocol.ACTION_TYPES.CLAIM_TASK, "taskId", "a_hero_4"), "hero保留既有单领协议")
        Page.handleInput(860, 300)
        check(lastAction(Protocol.ACTION_TYPES.CLAIM_ALL_TASKS, "scope", "hero"), "hero保留既有批领scope")
        Page.handleInput(540, 396)
        summary, content = draw()
        check(content and summary, "手工tab切换进入level专用轨道")
        Page.close()
        noActionAt(300, 950, "关闭动画期间不接收领取")
        check(not Page.handleDragBegin(300, 950) and not Page.handleScroll(-1), "关闭期间不再滚动")
        time.elapsedTime = 101
        Page.update(1)
        check(not Page.isOpen() and not Page.handleInput(300, 950), "动画结束完整关闭且不消费输入")
        check(uiInits > 0 and modules.currency.gold == 123 and modules.currency.gems == 456, "全程只读测试数据无实际发奖")
    end)

    package.loaded["ui.story.task.TaskPage"] = savedModules["ui.story.task.TaskPage"]
    package.loaded["ui.story.task.ExpeditionTrackView"] = savedModules["ui.story.task.ExpeditionTrackView"]
    for _, name in ipairs(globalNames) do rawset(_G, name, savedGlobals[name]) end
    if not ok then error(err) end
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
