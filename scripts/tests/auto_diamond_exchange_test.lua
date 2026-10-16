-- 自动黑晶兑换回归：基于 sidebar_battle_pause / artifact_chest_direct_unlock / tavern_recruit_orders 脚手架。
-- 真实生产源码仅走 cache:GetFile 白名单 + load(env)，不 require main，不读写真实玩家档、不联网、不消费账号。
-- File/PDM/动画/控件底层是显式内存替身；确认、支付选择、请求锁与混合扣费均调用真实生产模块。
-- NanoVG/控件记录仅证明接线与设计坐标，不代表 GPU、截图或实机视觉验收。
-- 本脚本不构建；由主线程统一 LSP/官方 build，再按需从 tests/auto_diamond_exchange_test.lua 运行。
-- 可选 -auto-exchange-review：仅真实UI控件/Surface截图；用-screenshot-frame/-validate退出，不运行正常业务回归。
-- 建议截图1440×1600：左侧保留1080×2400设计空间×0.45，右侧四scope五语言按820×56近景显示。

local TAG = "[auto_diamond_exchange_test] "
local SCOPES = { "gacha_standard", "gacha_stellar", "artifact_normal", "artifact_advanced" }
local SOURCES = {}
for _, name in ipairs({
    "ui.hud.popup.SettingsPanel", "ui.widget.AutoDiamondExchangeOption", "ui.widget.DesignWidgetSurface",
    "ui.tavern.TavernPopups", "ui.tavern.TavernPage", "ui.tavern.TavernRecruitOrders",
    "ui.church.ChurchArtifactDrawPanel", "core.DrawUtil", "systems.GachaSystem",
    "rules.gacha.GachaService", "rules.gacha.UrGachaService", "rules.artifact.ArtifactService",
    "shared.artifact.ArtifactDefs", "shared.artifact.ArtifactSchema", "shared.Protocol",
    "config.GachaConfig", "config.UrGachaConfig", "config.HeroConfig", "config.ExpTable",
    "config.ClassConfig", "config.AdvancementConfig", "config.AwakeningConfig", "systems.AttributeDef",
    "config.StageConfig", "config.StageConfig_Normal", "config.StageConfig_Hard", "config.StageConfig_Nightmare",
    "config.StageConfig_Hell", "config.StageConfig_Purgatory", "config.StageConfig_Torment",
    "config.StageConfig_Torment2", "config.StageConfig_Torment3", "config.StageConfig_Torment4",
    "config.StageConfig_Torment5", "config.StageConfig_Annihilation", "config.StageConfig_Annihilation2",
    "config.StageConfig_Annihilation3", "config.StageConfig_Annihilation4", "config.StageConfig_Annihilation5",
}) do SOURCES[name] = name:gsub("%.", "/") .. ".lua" end

local nativeCache, nativeFile, nativeTime = cache, File, time
local originalLoaded = {} ---@type table<string, any>
for name in pairs(SOURCES) do originalLoaded[name] = package.loaded[name] end
local sources = {} ---@type table<string, string>
local reads = {} ---@type string[]
local fixtures = {} ---@type any[]
local checks, groups = 0, 0
local failures = {} ---@type string[]
local function noop() end
local function check(value, message)
    checks = checks + 1
    assert(value, message)
end
local function eq(actual, expected, message)
    check(actual == expected, message .. " 实际=" .. tostring(actual) .. " 预期=" .. tostring(expected))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function source(name)
    local path = assert(SOURCES[name], "拒绝未列入白名单的源码：" .. tostring(name))
    if not sources[name] then
        local file = assert(nativeCache:GetFile(path), "缺少真实生产源码：" .. path)
        local ok, text = pcall(function()
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            return table.concat(lines, "\n")
        end)
        file:Dispose()
        assert(ok, text)
        sources[name] = text
        reads[#reads + 1] = path
    end
    return sources[name]
end

-- 命中区域 oracle 独立于生产常量，边界含端点，边外 0.001 不切偏好。
-- 酒馆页：  x130..950, y2152..2208   (540,2180), 820×56
-- 所有确认：x130..950, y1382..1438   (540,1410), 820×56；购买(540,1301)，互不重叠。
-- 普通卡：  x130..950, y1048..1104   (540,1076), 820×56；抽取按钮 y915..1045。
-- 高级卡：  x130..950, y1868..1924   (540,1896), 820×56；抽取按钮 y1735..1865。
-- 卡片开关与按钮留3px净空；中心/边界不触发抽取；模态优先，不穿透底层高级卡。

local function fixture()
    local f = { deps = {}, forbidden = {}, actions = {}, receipts = {}, files = {}, fileCalls = {},
        writes = 0, dirty = 0, flushes = 0, taskCalls = {}, events = {}, surfaces = {}, widgets = {},
        messages = {}, now = 1800000000, clock = { elapsedTime = 100 }, sendMode = "pending",
        vg = {}, tx = 0, ty = 0, sx = 1, sy = 1, stack = {}, font = 24,
        memory = {}, host = { open = true, closing = false }, animPlaying = false, targetOpen = false,
    } ---@type any
    fixtures[#fixtures + 1] = f
    local env = {} ---@type any
    f.env = env
    for _, key in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select",
        "tonumber", "tostring", "type", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal" }) do
        env[key] = _G[key]
    end
    env.math, env.string, env.table, env.utf8 = copy(math), copy(string), copy(table), copy(utf8)
    -- 独立随机源仅稳定抽取结果；绝不替换真实概率/卡池/扣费算法，也不改变全局 random 状态。
    env.math.random = function(a, b)
        if a == nil then return 0.5 end
        if b == nil then return math.max(1, math.floor(a * 0.5)) end
        return math.floor((a + b) * 0.5)
    end
    env.cjson = { encode = cjson.encode, decode = cjson.decode, null = cjson.null }
    env._G, env.time, env.H_SEAM_BACK, env.print = env, f.clock, true, noop
    env.os = { time = function() return f.now end, clock = function() return f.clock.elapsedTime end,
        date = function() return { year = 2027, month = 1, day = 1, hour = 0, min = 0, sec = 0 } end }
    for _, key in ipairs({ "NVG_ALIGN_LEFT", "NVG_ALIGN_RIGHT", "NVG_ALIGN_CENTER", "NVG_ALIGN_TOP",
        "NVG_ALIGN_MIDDLE", "NVG_ALIGN_BOTTOM", "NVG_ALIGN_BASELINE", "NVG_ROUND", "NVG_IMAGE_NEAREST",
        "FILE_READ", "FILE_WRITE", "FILE_READWRITE", "YGDirectionLTR" }) do env[key] = _G[key] end
    local function denied(label)
        return function()
            f.forbidden[#f.forbidden + 1] = label
            error("隔离测试禁止：" .. label)
        end
    end
    local function blocked(label)
        return setmetatable({}, { __index = function(_, key) return denied(label .. "." .. tostring(key)) end })
    end
    env.cache, env.network, env.clientCloud, env.serverCloud = blocked("cache"), blocked("network"), blocked("clientCloud"), blocked("serverCloud")
    env.io, env.package, env.engine, env.sdk = blocked("io"), blocked("package"), blocked("engine"), blocked("sdk")
    env.loadfile, env.dofile, env.GetFileSystem = denied("loadfile"), denied("dofile"), denied("GetFileSystem")
    env.SubscribeToEvent, env.SendEvent = denied("全局事件订阅"), denied("全局事件发送")
    env.audio = { SetMasterGain = noop }
    -- 仅两种本地偏好/历史文件，全部在 Lua table；生产请求落盘也只能走下面内存 PDM。
    local function permittedFile(path)
        assert(path == "settings_volume.json" or path == "gacha_history.json", "拒绝非内存白名单文件：" .. tostring(path))
    end
    env.fileSystem = { FileExists = function(_, path) permittedFile(path); return f.files[path] ~= nil end }
    env.File = function(path, mode)
        permittedFile(path)
        assert(mode == FILE_READ or mode == FILE_WRITE, "内存File仅接受明确读/写模式")
        f.fileCalls[#f.fileCalls + 1] = { path = path, mode = mode }
        local opened = not f.fileOpenFailure
        return { IsOpen = function() return opened end, Close = function() opened = false end, Dispose = function() opened = false end,
            ReadString = function()
                assert(mode == FILE_READ and opened, "内存File读模式/生命周期错误")
                return f.files[path] or ""
            end,
            WriteString = function(_, data)
                assert(mode == FILE_WRITE and opened, "内存File写模式/生命周期错误")
                f.files[path] = data; f.writes = f.writes + 1
            end }
    end

    -- 显式绘图底层替身；没有实际 nvgCreate/nvgBeginFrame 或 GPU 资源。
    for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFillColor", "nvgFillPaint", "nvgFill",
        "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgFontFace", "nvgTextAlign", "nvgGlobalAlpha",
        "nvgScissor", "nvgIntersectScissor", "nvgResetScissor", "nvgFontBlur", "nvgMoveTo", "nvgLineTo",
        "nvgClosePath", "nvgCircle", "nvgLineCap", "nvgLineJoin", "nvgSkewX" }) do env[name] = noop end
    env.nvgSave = function() f.stack[#f.stack + 1] = { f.tx, f.ty, f.sx, f.sy } end
    env.nvgRestore = function()
        local old = assert(table.remove(f.stack), "NanoVG restore 无 save")
        f.tx, f.ty, f.sx, f.sy = table.unpack(old)
    end
    env.nvgTranslate = function(_, x, y) f.tx, f.ty = f.tx + x * f.sx, f.ty + y * f.sy end
    env.nvgScale = function(_, x, y) f.sx, f.sy = f.sx * x, f.sy * y end
    env.nvgFontSize = function(_, size) f.font = size end
    env.nvgTextBounds = function(_, _, _, text) return (utf8.len(text) or #text) * f.font * 0.6 end
    env.nvgText = function(_, x, y, text)
        f.texts = f.texts or {}; f.texts[#f.texts + 1] = { text = text, x = x, y = y }
    end
    env.nvgRGBA, env.nvgRGBAf = function(...) return { ... } end, function(...) return { ... } end
    env.nvgImagePattern, env.nvgImagePatternTinted = function() return {} end, function() return {} end
    env.nvgCreateImage = function(_, path)
        assert(type(path) == "string" and path:sub(1, 6) == "image/", "仅图片资源允许模拟句柄")
        f.imageCount = (f.imageCount or 0) + 1; return f.imageCount
    end
    env.nvgImageSize = function() return 1080, 2400 end
    env.YGNodeCalculateLayout = noop
    local function mock(name, fields)
        f.deps[name] = setmetatable(fields or {}, { __index = function(_, key)
            return denied("未声明叶子依赖 " .. name .. "." .. tostring(key))
        end })
        return f.deps[name]
    end
    -- 控件替身只实现属性更新和子树记录；不能用来模拟支付判断或 Action。
    local function widget(kind, props)
        local w = { kind = kind, props = copy(props or {}), children = (props or {}).children or {}, node = {} } ---@type any
        w.SetChecked = function(self, value) self.props.checked = value end
        w.SetDisabled = function(self, value) self.props.disabled = value end
        w.SetText = function(self, value) self.props.text = value end
        w.SetWidth = function(self, value) self.props.width = value end
        w.SetStyle = function(self, values) for key, value in pairs(values) do self.props[key] = value end end
        f.widgets[#f.widgets + 1] = w
        return w
    end
    mock("urhox-libs/UI", { Scale = { DEFAULT = "隔离默认缩放" },
        Init = function(options) f.uiOptions = options end, SetRoot = function(root) f.uiRoot = root end,
        Shutdown = noop, Panel = function(props) return widget("Panel", props) end,
        Label = function(props) return widget("Label", props) end, Checkbox = function(props) return widget("Checkbox", props) end,
        RenderWidgetSubtree = function(root)
            f.surfaces[#f.surfaces + 1] = { root = root, x = f.tx, y = f.ty, w = root.props.width * f.sx, h = root.props.height * f.sy }
        end })
    mock("urhox-libs/UI/Core/ImageCache", { Clear = noop, SetContext = noop })
    mock("config.GameConfig", { Design = { WIDTH = 1080, HEIGHT = 2400 } })
    mock("core.BattleLayout", {})
    mock("systems.UnitAttributes", {}) -- 不调用角色战斗属性工厂；角色配置/卡池本身仍真实。
    mock("systems.TalentEffect", {})
    local language = "zh_CN"
    mock("core.I18n", { LANGS = { { id = "zh_CN", label = "简体" }, { id = "zh_TW", label = "繁體" },
            { id = "en", label = "EN" }, { id = "ja", label = "日本語" }, { id = "ko", label = "한국어" } },
        get = function() return language end, set = function(value) language = value; return true end,
        t = function(text) return text end, lookup = function(text) return text end, format = string.format,
        displayText = env.nvgText, displayBounds = env.nvgTextBounds })
    mock("ui.hud.popup.RedeemCodePanel", { init = noop })
    mock("systems.GameBGM", { setMasterGain = noop })
    mock("core.DarkIcon", { Palette = { BONE = { 240, 230, 210 }, BONE_DIM = { 170, 160, 150 } },
        drawNine = noop, drawQualityBg = noop })
    mock("systems.ButtonFeedback", { begin = function() return false end, finish = noop, trigger = noop })
    mock("core.GameState", { getRecruitTicket = function() return f.memory.currency.recruitTicket end,
        getStellarRecruitTicket = function() return f.memory.currency.stellarRecruitTicket end,
        getGoldenKey = function() return f.memory.currency.goldenKey end, getGems = function() return f.memory.currency.gems end })
    mock("runtime.ClientDispatcher", { get = function(name) return f.memory[name] end, subscribe = noop })
    mock("core.PlayerStore", { Get = function(name) return f.memory[name] end })
    mock("rules.character.PlayerDataManager", {
        GetModule = function(uid, name) eq(uid, 987654, "服务只访问隔离uid"); return f.memory[name] end,
        MarkDirty = function() f.dirty = f.dirty + 1 end,
        FlushImmediate = function() f.flushes = f.flushes + 1 end })
    mock("rules.task.TaskService", { UpdateProgress = function(_, event, count) f.taskCalls[#f.taskCalls + 1] = { event, count } end,
        RefreshAchievements = noop })
    mock("rules.hero.HeroService", {}) -- 测试 roster 全员已拥有，禁止进入新英雄业务工厂。
    mock("rules.currency.CurrencyService", {}) -- 神器 Draw 直接使用真实服务内的混合扣费，不调用其他货币业务。
    mock("core.EventBus", {})
    mock("config.GameEvents", {})
    mock("ui.character.panel.CharacterPanel", {})
    mock("ui.tavern.TavernInfo", { clearCache = noop })
    mock("ui.tavern.RecruitAnim", { init = noop, setOnAgain = function(fn) f.again = fn end,
        isPlaying = function() return f.animPlaying end, draw = noop, update = noop,
        handleInput = function() return true end, close = function() f.animPlaying = false end,
        start = function(_, _, count, poolId) f.animCount, f.animPool, f.animPlaying = count, poolId, true end })
    mock("ui.tavern.TavernShopPage", { init = noop, resetScroll = noop, syncPurchasedFromStore = noop,
        drawContent = noop, update = noop, handleInput = function() return false end,
        isPendingBuy = function() return false end })
    mock("ui.tavern.TargetRecruitPanel", { init = noop, draw = noop, isOpen = function() return f.targetOpen end,
        close = function() f.targetOpen = false end, open = function() f.targetOpen = true end,
        handleInput = function() return true end })
    mock("systems.GameSFX", { playUIMove = noop })
    mock("systems.StoryPlayer", { onPlace = noop })
    mock("systems.TutorialManager", { notifyEvent = function(name) f.events[#f.events + 1] = name end,
        isActive = function() return false end, onRecruitCompleted = noop })
    mock("ui.character.hero.HeroScenario", { onRecruitResults = noop })
    mock("ui.hud.popup.RewardPopup", { show = function(_, _, options) f.repeatDraw = options.repeatDraw end })
    mock("ui.town.TownPageChrome", { easeOutCubic = function(t) return 1 - (1 - t) ^ 3 end,
        easeInCubic = function(t) return t ^ 3 end, drawNamePlate = noop, drawBack = noop,
        hitBack = function() return false end, drawTabBar = noop,
        tabSlide = function(state, mapping) return mapping[state.tab], mapping[state.tabFrom], 1 end,
        hitTab = function(x, y, items, w, h)
            for index, item in ipairs(items) do
                if math.abs(x - item.cx) <= w * 0.5 and math.abs(y - item.cy) <= h * 0.5 then return index end
            end
        end })
    env.require = function(name)
        if f.deps[name] ~= nil then return f.deps[name] end
        local chunk = assert(load(source(name), "@" .. SOURCES[name], "t", env))
        local result = chunk()
        assert(type(result) == "table", "生产模块必须返回table：" .. name)
        f.deps[name] = result
        return result
    end
    f.real = env.require
    function f.resetMemory(tickets, gems, keys)
        local roster = {}
        for id in pairs(f.real("config.HeroConfig").HEROES) do roster[id] = { level = 1, shards = 0, awakening = {} } end
        f.memory = { currency = { recruitTicket = tickets or 0, stellarRecruitTicket = tickets or 0,
                gems = gems or 0, goldenKey = keys or 0, gold = 12345, gachaPitySR = 0, gachaPitySSR = 0,
                urPityUR = 0, urPitySSR = 0, urPitySR = 0 }, heroes = { roster = roster },
            session = { firstGachaTenDone = true }, player = { level = 1 },
            battle = { maxStageId = 7001, clearedStages = { ["2305"] = true } },
            artifacts = f.real("shared.artifact.ArtifactSchema").Fields.artifacts.getDefault() }
        f.real("shared.artifact.ArtifactSchema").normalizeModule(f.memory.artifacts)
        f.memory.artifacts.dailyFreeDrawDayId = math.floor((f.now + 28800) / 86400)
        f.dirty, f.flushes, f.taskCalls = 0, 0, {}
    end
    f.resetMemory()
    f.protocol = f.real("shared.Protocol")
    f.settings = f.real("ui.hud.popup.SettingsPanel")
    check(type(f.settings.isAutoDiamondExchangeEnabled) == "function"
        and type(f.settings.setAutoDiamondExchangeEnabled) == "function", "生产自动兑换设置接口必须已实现，禁止跳过")
    f.settings.init(f.vg)
    function f.step(seconds)
        f.clock.elapsedTime = f.clock.elapsedTime + (seconds or 1)
        if f.page then f.page.update(seconds or 1) end
    end
    function f.send(action, params)
        f.actions[#f.actions + 1] = { action = action, params = copy(params) }
        if f.insideSend then f.insideSend(action, params) end
        if f.sendMode == "reject_send" then return false end
        if f.sendMode == "sync_fail" then
            if action == f.protocol.ACTION_TYPES.GACHA_PULL then
                f.page.onActionResult({ action = action, success = false, reason = "内存失败回执" })
            else f.panel.onArtifactDrawResult() end
            return true
        end
        if f.sendMode == "rules" then
            if f.beforeAuthority then f.beforeAuthority() end
            local ok, reason, result
            if action == f.protocol.ACTION_TYPES.GACHA_PULL then
                ok, reason, result = f.real("rules.gacha.GachaService").GachaPull(987654, params.count, params.payType, params.poolId)
            elseif action == f.protocol.ACTION_TYPES.ARTIFACT_DRAW then
                ok, reason, result = f.real("rules.artifact.ArtifactService").Draw(987654, params.count, params.payType, params.chestType)
            else error("不能发送补购/其他业务Action：" .. tostring(action)) end
            f.receipts[#f.receipts + 1] = { success = ok, reason = reason, result = result }
            -- 不伪造客户端成功流程；权威模式仅执行内存服务并释放真实 pending。
            if action == f.protocol.ACTION_TYPES.GACHA_PULL then
                f.page.onActionResult({ action = action, success = false, reason = reason or "内存权威调用已完成" })
            else f.panel.onArtifactDrawResult() end
        end
        return true
    end
    function f.tavern(pool)
        if not f.page then
            f.popups = f.real("ui.tavern.TavernPopups")
            local show = f.popups.showFloatText
            f.popups.showFloatText = function(text, x, y) f.messages[#f.messages + 1] = text; return show(text, x, y) end
            f.page = f.real("ui.tavern.TavernPage")
            f.page.setSendAction(f.send); f.page.init(f.vg); f.page.open(); f.step()
        end
        if pool then
            f.page.handleInput(pool == "stellar" and 815 or 275, 545)
            eq(f.page.getSelectedPoolId(), pool, "真实整牌入口选择卡池")
        end
        return f.page
    end
    function f.artifact()
        if not f.panel then
            f.panel = f.real("ui.church.ChurchArtifactDrawPanel")
            f.panel.setContext({ state = f.host, getProtocol = function() return f.protocol end,
                getClient = function() return { sendAction = f.send } end })
            f.panel.init(f.vg)
        end
        return f.panel
    end
    function f.release()
        if f.page then f.page.onActionResult({ action = f.protocol.ACTION_TYPES.GACHA_PULL, success = false, reason = "释放内存请求" }) end
        if f.panel then f.panel.onArtifactDrawResult() end
    end
    function f.safe()
        eq(#f.forbidden, 0, "未访问账号/网络/真实File/未声明依赖")
        for _, call in ipairs(f.fileCalls) do
            check(call.path == "settings_volume.json" or call.path == "gacha_history.json", "所有File调用均在内存白名单")
        end
    end
    return f
end

local function noActions(f, before, label)
    eq(#f.actions, before or 0, label .. "零新增Action")
    f.safe()
end
local function optionAt(f, cx, cy, scope, price)
    local found = nil ---@type any
    for _, entry in ipairs(f.surfaces) do
        if entry.x == cx - 410 and entry.y == cy - 28 and entry.w == 820 and entry.h == 56 then
            found = entry
        end
    end
    check(found ~= nil, scope .. "实际Surface位置/宽高符合设计oracle")
    local checkbox = nil ---@type any
    local labels = {} ---@type string[]
    local function visit(w)
        if w.kind == "Checkbox" then checkbox = w end
        if w.kind == "Label" then labels[#labels + 1] = w.props.text end
        for _, child in ipairs(w.children) do visit(child) end
    end
    visit(found.root)
    check(checkbox ~= nil and #labels == 2, "真实Widget建立Checkbox + 两个Label")
    eq(checkbox.props.checked, f.settings.isAutoDiamondExchangeEnabled(scope), scope .. "勾选值由真实设置同步")
    check(table.concat(labels, "|"):find(tostring(price), 1, true) ~= nil, "提示显示真实单价而非消费按钮")
    eq(f.uiOptions.scale, "隔离默认缩放", "真实DesignWidgetSurface使用UI.Scale.DEFAULT")
    eq(f.uiOptions.autoEvents, false, "没有创建宿主之外的自动事件输入通道")
    eq(#f.stack, 0, "宿主/Surface绘制save/restore平衡")
end
local function oneAction(f, before, action, count, payment, kind)
    eq(#f.actions, before + 1, "原入口恰好发送一个动作，不先买券/钥匙")
    local sent = f.actions[#f.actions]
    eq(sent.action, action, "动作仍使用既有协议")
    eq(sent.params.count, count, "抽数保持原请求")
    eq(sent.params.payType, payment, "真实doRecruitDirect/sendArtifactDraw收到明确支付类型")
    eq(sent.params.poolId or sent.params.chestType, kind, "请求保存真实池/档位")
end

local function preferences()
    local f = fixture()
    for _, scope in ipairs(SCOPES) do eq(f.settings.isAutoDiamondExchangeEnabled(scope), false, scope .. "独立默认关闭") end
    for _, scope in ipairs(SCOPES) do
        for _, other in ipairs(SCOPES) do f.settings.setAutoDiamondExchangeEnabled(other, false) end
        f.settings.setAutoDiamondExchangeEnabled(scope, true)
        for _, other in ipairs(SCOPES) do eq(f.settings.isAutoDiamondExchangeEnabled(other), other == scope, "开启一个scope不泄漏到其他scope") end
        local saved = f.files["settings_volume.json"]
        local data = cjson.decode(saved)
        for _, other in ipairs(SCOPES) do eq(data.autoDiamondExchange[other], other == scope, "四键完整且仅当前键保存true") end
        eq(data.showEquipmentPower, false, "原战力设置不被修改")
        eq(data.pauseBattleOnSidePanels, false, "原暂停设置不被修改")
        eq(data.language, "zh_CN", "语言不被修改")
        f.settings.setAutoDiamondExchangeEnabled(scope, false)
        eq(cjson.decode(f.files["settings_volume.json"]).autoDiamondExchange[scope], false, "关闭持久化")
        f.files["settings_volume.json"] = saved; f.settings.init(f.vg)
        eq(f.settings.isAutoDiamondExchangeEnabled(scope), true, "真实init恢复true")
        f.settings.setAutoDiamondExchangeEnabled(scope, false)
        f.settings.init(f.vg)
        eq(f.settings.isAutoDiamondExchangeEnabled(scope), false, "真实init恢复false")
    end
    for _, raw in ipairs({ "{}", "{", "null", "true", "\"旧档\"", "[]",
        '{"autoDiamondExchange":"true"}', '{"autoDiamondExchange":true}',
        '{"autoDiamondExchange":{"gacha_standard":"true","gacha_stellar":1,"artifact_normal":{},"artifact_advanced":"false","invalid":true}}' }) do
        for _, scope in ipairs(SCOPES) do f.settings.setAutoDiamondExchangeEnabled(scope, true) end
        f.files["settings_volume.json"] = raw; f.settings.init(f.vg)
        for _, scope in ipairs(SCOPES) do eq(f.settings.isAutoDiamondExchangeEnabled(scope), false, "旧/坏/非boolean档重置false：" .. raw) end
    end
    for _, scope in ipairs(SCOPES) do f.settings.setAutoDiamondExchangeEnabled(scope, true) end
    f.files["settings_volume.json"] = nil; f.settings.init(f.vg)
    for _, scope in ipairs(SCOPES) do eq(f.settings.isAutoDiamondExchangeEnabled(scope), false, "无档不继承前一份true") end
    for _, scope in ipairs(SCOPES) do
        for _, invalidValue in ipairs({ "true", 1, {}, false }) do
            f.settings.setAutoDiamondExchangeEnabled(scope, invalidValue)
            eq(f.settings.isAutoDiamondExchangeEnabled(scope), false, "setter严格==true，不接受truthy")
        end
    end
    for _, key in ipairs({ "", "standard", "stellar", "normal", "advanced", "gacha_invalid", "__index", 1, false, {} }) do
        f.settings.setAutoDiamondExchangeEnabled(key, true)
        eq(f.settings.isAutoDiamondExchangeEnabled(key), false, "非法scope无法授权")
    end
    f.settings.setAutoDiamondExchangeEnabled(nil, true)
    eq(f.settings.isAutoDiamondExchangeEnabled(nil), false, "nil scope默认关闭")
    for _, scope in ipairs(SCOPES) do eq(f.settings.isAutoDiamondExchangeEnabled(scope), false, "非法键不影响合法scope") end
    noActions(f, 0, "所有开关/保存/加载")
    eq(f.dirty + f.flushes, 0, "偏好加载保存不调用玩家PDM")
    local second = fixture()
    second.settings.setAutoDiamondExchangeEnabled("gacha_standard", true)
    eq(f.settings.isAutoDiamondExchangeEnabled("gacha_standard"), false, "模块env实例隔离")
end

local function widgetAndLayout()
    local f = fixture()
    local option = f.real("ui.widget.AutoDiamondExchangeOption")
    for _, language in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
        f.deps["core.I18n"].set(language)
        for index, scope in ipairs(SCOPES) do
            local price = index == 1 and 180 or (index == 2 and 900 or 150)
            f.surfaces = {}; option.draw(f.vg, scope, 540, 1410, 820, price, false)
            optionAt(f, 540, 1410, scope, price)
            for _, point in ipairs({ { 130, 1410 }, { 950, 1410 }, { 540, 1382 }, { 540, 1438 }, { 540, 1410 } }) do
                local old, writes = f.settings.isAutoDiamondExchangeEnabled(scope), f.writes
                check(option.handleInput(point[1], point[2], scope, 540, 1410, 820, false), "整行及边界可点击")
                eq(f.settings.isAutoDiamondExchangeEnabled(scope), not old, "整行只切当前偏好")
                eq(f.writes, writes + 1, "一次开关只保存一次")
            end
            for _, point in ipairs({ { 129.999, 1410 }, { 950.001, 1410 }, { 540, 1381.999 }, { 540, 1438.001 } }) do
                local old, writes = f.settings.isAutoDiamondExchangeEnabled(scope), f.writes
                eq(option.handleInput(point[1], point[2], scope, 540, 1410, 820, false), false, "边外不命中")
                eq(f.settings.isAutoDiamondExchangeEnabled(scope), old, "边外不改变偏好")
                eq(f.writes, writes, "边外不保存")
            end
            local old, writes = f.settings.isAutoDiamondExchangeEnabled(scope), f.writes
            check(option.handleInput(540, 1410, scope, 540, 1410, 820, true), "禁用行吞输入")
            eq(f.settings.isAutoDiamondExchangeEnabled(scope), old, "禁用不切偏好")
            eq(f.writes, writes, "禁用不保存")
        end
    end
    noActions(f, 0, "独立Widget多语言绘制/点击")
    for _, scope in ipairs(SCOPES) do f.settings.setAutoDiamondExchangeEnabled(scope, false) end
    local page = f.tavern("standard")
    f.surfaces = {}; page.draw(f.vg); optionAt(f, 540, 2180, "gacha_standard", 180)
    page.handleInput(540, 2180)
    check(f.settings.isAutoDiamondExchangeEnabled("gacha_standard"), "酒馆页桥点击实际行")
    page.handleInput(815, 545)
    f.surfaces = {}; page.draw(f.vg); optionAt(f, 540, 2180, "gacha_stellar", 900)
    eq(f.settings.isAutoDiamondExchangeEnabled("gacha_stellar"), false, "换池显示独立关闭")
    page.handleInput(540, 2180)
    page.handleInput(740, 2308)
    local writes = f.writes
    f.surfaces = {}; page.draw(f.vg)
    eq(#f.surfaces, 0, "商店不绘制招募开关")
    page.handleInput(540, 2180); eq(f.writes, writes, "商店不接收招募开关")
    local panel = f.artifact()
    f.surfaces = {}; panel.drawContent(f.vg)
    optionAt(f, 540, 1076, "artifact_normal", 150); optionAt(f, 540, 1896, "artifact_advanced", 150)
    panel.handleTabInput(540, 1076)
    eq(f.settings.isAutoDiamondExchangeEnabled("artifact_normal"), true, "普通卡实际行只切普通")
    eq(f.settings.isAutoDiamondExchangeEnabled("artifact_advanced"), false, "普通不影响高级")
    panel.handleTabInput(540, 1896)
    eq(f.settings.isAutoDiamondExchangeEnabled("artifact_advanced"), true, "高级卡实际行只切高级")
    noActions(f, 0, "页面开关/卡池切换/商店/宝箱开关")

    -- 页面滑入期间只禁用新增开关；点击移动中的勾框或旧静止热区不能误授权。
    local moving = fixture()
    local movingPage = moving.tavern("standard")
    movingPage.open()
    moving.clock.elapsedTime = moving.clock.elapsedTime + 0.30
    local movingWrites = moving.writes
    movingPage.handleInput(106, 2180); movingPage.handleInput(540, 2180)
    eq(moving.writes, movingWrites, "酒馆滑入动画不误切偏好")
    eq(moving.settings.isAutoDiamondExchangeEnabled("gacha_standard"), false, "滑入期间保持关闭")
    moving.step(0.2); movingPage.handleInput(540, 2180)
    eq(moving.settings.isAutoDiamondExchangeEnabled("gacha_standard"), true, "酒馆动画完成后开关可用")
    local movingPanel = moving.artifact()
    local ready = false
    movingPanel.setContext({ state = moving.host, getProtocol = function() return moving.protocol end,
        getClient = function() return { sendAction = moving.send } end,
        isAutoExchangeInputReady = function() return ready end })
    movingWrites = moving.writes
    for _, y in ipairs({ 1076, 1896 }) do movingPanel.handleTabInput(106, y); movingPanel.handleTabInput(540, y) end
    eq(moving.writes, movingWrites, "宝箱页签滑动期间所有开关保持禁用")
    ready = true; movingPanel.handleTabInput(540, 1076)
    eq(moving.settings.isAutoDiamondExchangeEnabled("artifact_normal"), true, "宝箱页签动画完成后开关可用")
    noActions(moving, 0, "页面与页签动画偏好保护")
end

local function tavernConfirmAndAuto()
    for _, pool in ipairs({ "standard", "stellar" }) do
        local scope, price = "gacha_" .. pool, pool == "standard" and 180 or 900
        for _, count in ipairs({ 1, 10 }) do
            local f = fixture(); local page = f.tavern(pool)
            f.resetMemory(count, 0)
            local canProceed, payment = f.popups.checkAndShowConfirm(count)
            eq(canProceed, true, "券足够可以直接招募")
            eq(payment, nil, "券足够不强制钻石")
            eq(f.popups.isRecruitConfirmOpen(), false, "券足够无modal")
            f.resetMemory(count - 1, price)
            canProceed, payment = f.popups.checkAndShowConfirm(count)
            eq(canProceed, false, "默认关闭缺券必须确认")
            eq(payment, nil, "确认前不提供自动支付许可")
            eq(f.popups.isRecruitConfirmOpen(), true, "默认缺券modal打开")
            f.step(); f.surfaces = {}; f.popups.drawAll(f.vg); optionAt(f, 540, 1410, scope, price)
            local snapshot, writes = copy(f.memory), f.writes
            page.handleInput(540, 1410)
            eq(f.settings.isAutoDiamondExchangeEnabled(scope), true, "确认框当前scope开启")
            eq(f.writes, writes + 1, "确认框切换仅保存偏好")
            eq(f.popups.isRecruitConfirmOpen(), true, "切偏好不会自动购买/关闭当前modal")
            check(same(f.memory, snapshot), "确认框开关不扣券/黑晶")
            noActions(f, 0, "当前modal开启偏好")
            page.handleInput(540, 1301)
            oneAction(f, 0, f.protocol.ACTION_TYPES.GACHA_PULL, count, "diamond", pool)
            f.release(); f.popups.resetAll()
            f.settings.setAutoDiamondExchangeEnabled(scope, false)
            local before = #f.actions
            page.handleInput(count == 10 and 766 or 314, 1902)
            check(f.popups.isRecruitConfirmOpen(), "关闭后原按钮恢复confirm")
            noActions(f, before, "关闭后的原入口")
            f.step(); page.handleInput(0, 0); f.step()
            eq(f.popups.isRecruitConfirmOpen(), false, "取消modal保持零消费")
            f.settings.setAutoDiamondExchangeEnabled(scope, true)
            f.resetMemory(count - 1, price - 1)
            local messagesBefore = #f.messages
            canProceed, payment = f.popups.checkAndShowConfirm(count)
            eq(canProceed, false, "自动余额差1仍拒绝")
            eq(payment, nil, "不足不授予diamond")
            eq(f.popups.isRecruitConfirmOpen(), false, "自动不足不弹modal")
            eq(#f.messages, messagesBefore + 1, "自动不足调用真实飘字一次")
            noActions(f, before, "自动余额不足")
            f.resetMemory(count - 1, price)
            canProceed, payment = f.popups.checkAndShowConfirm(count)
            eq(canProceed, true, "只够缺口价也允许，不能回退全额canPull报价")
            eq(payment, "diamond", "缺券自动必须明确diamond")
            eq(f.popups.isRecruitConfirmOpen(), false, "自动缺口够无modal")
            snapshot = copy(f.memory)
            page.handleInput(count == 10 and 766 or 314, 1902)
            oneAction(f, before, f.protocol.ACTION_TYPES.GACHA_PULL, count, "diamond", pool)
            check(same(f.memory, snapshot), "请求spy不修改任何内存币/奖励")
            f.release()
        end
    end
end

local function tavernEntrypointsAndGates()
    for _, pool in ipairs({ "standard", "stellar" }) do
        for _, count in ipairs({ 1, 10 }) do
            local f = fixture(); local page = f.tavern(pool)
            local scope, price = "gacha_" .. pool, pool == "standard" and 180 or 900
            f.resetMemory(count - 1, price); f.settings.setAutoDiamondExchangeEnabled(scope, true)
            local beforeCurrency = copy(f.memory)
            local reentered = false
            f.insideSend = function()
                check(page.isRecruitBusy(), "请求pending在send前设置")
                if not reentered then reentered = true; page.handleInput(count == 10 and 766 or 314, 1902) end
            end
            page.handleInput(count == 10 and 766 or 314, 1902)
            oneAction(f, 0, f.protocol.ACTION_TYPES.GACHA_PULL, count, "diamond", pool)
            check(same(f.memory, beforeCurrency), "动作spy不能直接修改币或奖励")
            local writes = f.writes
            page.handleInput(540, 2180); page.handleInput(314, 1902); page.handleInput(766, 1902)
            eq(f.writes, writes, "pending下开关不变")
            eq(#f.actions, 1, "pending重复输入不发送")
            eq(f.popups.isRecruitConfirmOpen(), false, "pending不打开新确认框")
            f.insideSend = nil; f.release()
            -- 使用真实RecruitAnim.setOnAgain注册的闭包，不另造继续业务。
            local before = #f.actions
            f.again(count, pool)
            oneAction(f, before, f.protocol.ACTION_TYPES.GACHA_PULL, count, "diamond", pool)
            f.release(); f.settings.setAutoDiamondExchangeEnabled(scope, false)
            before = #f.actions; f.again(count, pool)
            check(f.popups.isRecruitConfirmOpen(), "继续入口关闭后恢复confirm")
            noActions(f, before, "继续入口关时")
            f.popups.resetAll(); f.settings.setAutoDiamondExchangeEnabled(scope, true)
            f.sendMode = "reject_send"; page.handleInput(314, 1902)
            eq(page.isRecruitBusy(), false, "send返回false释放pending")
            f.sendMode = "sync_fail"; page.handleInput(314, 1902)
            eq(page.isRecruitBusy(), false, "同步失败回执不会留下pending")
            f.animPlaying = true; before = #f.actions
            page.handleInput(540, 2180); page.handleInput(314, 1902)
            noActions(f, before, "结果动画优先")
            f.animPlaying, f.targetOpen = false, true
            page.handleInput(540, 2180); page.handleInput(314, 1902)
            noActions(f, before, "指定UP模态优先")
        end
    end
    local f = fixture(); local page = f.tavern("stellar")
    f.settings.setAutoDiamondExchangeEnabled("gacha_stellar", true)
    f.resetMemory(0, 9000); f.memory.battle.maxStageId = 7000
    page.handleInput(314, 1902); page.handleInput(766, 1902); f.again(10, "stellar")
    noActions(f, 0, "已选星辰后权威解锁丢失不绕过")
    eq(f.popups.isRecruitConfirmOpen(), false, "锁定不打开补券确认")
    f.memory.battle.maxStageId = 7001; f.resetMemory(0, 9000)
    f.settings.setAutoDiamondExchangeEnabled("gacha_stellar", false)
    f.settings.setAutoDiamondExchangeEnabled("gacha_standard", true)
    page.handleInput(314, 1902)
    check(f.popups.isRecruitConfirmOpen(), "普通开启不授权星辰")
    noActions(f, 0, "两卡池授权隔离")
end

local function artifactConfirmAndAuto()
    for _, chest in ipairs({ "normal", "advanced" }) do
        for _, count in ipairs({ 1, 10 }) do
            local needed = count * (chest == "advanced" and 5 or 1)
            local scope, y = "artifact_" .. chest, chest == "normal" and 980 or 1800
            local f = fixture(); local panel = f.artifact()
            f.resetMemory(0, 150, needed - 1)
            panel.handleTabInput(count == 10 and 760 or 320, y)
            check(panel.isKeyConfirmVisible(), "关闭缺钥匙弹出既有modal")
            noActions(f, 0, "关时缺钥匙")
            f.step(); f.surfaces = {}; panel.drawKeyConfirmDialog(f.vg); optionAt(f, 540, 1410, scope, 150)
            local snapshot, writes = copy(f.memory), f.writes
            panel.handleTabInput(540, 1410)
            eq(f.settings.isAutoDiamondExchangeEnabled(scope), true, "宝箱modal切当前档偏好")
            eq(f.writes, writes + 1, "宝箱modal保存一次")
            check(panel.isKeyConfirmVisible(), "开启偏好不会购买或关闭当前modal")
            check(same(f.memory, snapshot), "宝箱modal偏好不扣费")
            noActions(f, 0, "宝箱modal授权")
            panel.handleTabInput(540, 1301)
            oneAction(f, 0, f.protocol.ACTION_TYPES.ARTIFACT_DRAW, count, "diamond", chest)
            f.release(); f.step(); panel.drawKeyConfirmDialog(f.vg); panel.reset()
            f.settings.setAutoDiamondExchangeEnabled(scope, false)
            panel.handleTabInput(count == 10 and 760 or 320, y)
            check(panel.isKeyConfirmVisible(), "关闭宝箱自动恢复确认")
            local before = #f.actions
            f.step(); panel.handleTabInput(0, 0); f.step(); panel.drawKeyConfirmDialog(f.vg)
            eq(panel.isKeyConfirmVisible(), false, "宝箱取消完成")
            noActions(f, before, "宝箱取消")
            f.settings.setAutoDiamondExchangeEnabled(scope, true)
            f.resetMemory(0, 149, needed - 1)
            panel.handleTabInput(count == 10 and 760 or 320, y)
            eq(panel.isKeyConfirmVisible(), false, "自动黑晶不足不弹modal")
            check(type(f.host.floatText) == "string" and #f.host.floatText > 0, "自动黑晶不足通过宿主提示")
            noActions(f, before, "宝箱黑晶差1")
            f.resetMemory(0, 150, needed - 1)
            panel.handleTabInput(count == 10 and 760 or 320, y)
            oneAction(f, before, f.protocol.ACTION_TYPES.ARTIFACT_DRAW, count, "diamond", chest)
            eq(panel.isKeyConfirmVisible(), false, "自动只够缺口直接抽，无modal")
            f.release()
        end
    end
end

local function artifactEntrypointsAndGates()
    for _, chest in ipairs({ "normal", "advanced" }) do
        for _, count in ipairs({ 1, 10 }) do
            local f = fixture(); local panel = f.artifact()
            local y, scope = chest == "normal" and 980 or 1800, "artifact_" .. chest
            local needed = count * (chest == "advanced" and 5 or 1)
            f.settings.setAutoDiamondExchangeEnabled(scope, true)
            f.resetMemory(0, 150, needed - 1)
            local reentered = false
            f.insideSend = function()
                if not reentered then reentered = true; panel.handleTabInput(count == 10 and 760 or 320, y) end
            end
            panel.handleTabInput(count == 10 and 760 or 320, y)
            oneAction(f, 0, f.protocol.ACTION_TYPES.ARTIFACT_DRAW, count, "diamond", chest)
            local writes = f.writes
            panel.handleTabInput(540, chest == "normal" and 1076 or 1896)
            eq(f.writes, writes, "宝箱pending禁用开关")
            panel.handleTabInput(320, 980); panel.handleTabInput(760, 1800)
            eq(#f.actions, 1, "宝箱pending不跨卡发送")
            eq(panel.isKeyConfirmVisible(), false, "pending不打开modal")
            f.insideSend = nil
            panel.onArtifactDrawSuccess({ chestType = chest, artifacts = { { id = "内存1", artifactId = 1, quality = 1, value = 1 } } })
            check(type(f.repeatDraw) == "table" and type(f.repeatDraw.onContinue) == "function", "真实成功处理注册原继续回调")
            local repeatDraw = f.repeatDraw
            panel.handleTabInput(540, chest == "normal" and 1200 or 400)
            local before = #f.actions
            repeatDraw.onContinue(count)
            oneAction(f, before, f.protocol.ACTION_TYPES.ARTIFACT_DRAW, count, "diamond", chest)
            f.release(); f.settings.setAutoDiamondExchangeEnabled(scope, false)
            before = #f.actions; repeatDraw.onContinue(count)
            check(panel.isKeyConfirmVisible(), "继续入口关闭偏好后恢复确认")
            noActions(f, before, "宝箱继续关闭")
            panel.reset(); f.settings.setAutoDiamondExchangeEnabled(scope, true)
            repeatDraw.onContinue(count)
            noActions(f, before, "过期generation继续无效")
            panel.onArtifactDrawSuccess({ chestType = chest, artifacts = { { id = "内存2", artifactId = 1, quality = 1 } } })
            f.host.open = false; f.repeatDraw.onContinue(count)
            noActions(f, before, "宿主关闭不允许继续")
            f.host.open, f.host.closing = true, true; f.repeatDraw.onContinue(count)
            noActions(f, before, "宿主关闭动画不允许继续")
        end
    end
    for _, enabled in ipairs({ false, true }) do
        local f = fixture(); local panel = f.artifact()
        for _, scope in ipairs({ "artifact_normal", "artifact_advanced" }) do f.settings.setAutoDiamondExchangeEnabled(scope, enabled) end
        f.resetMemory(0, 123, 50)
        f.memory.artifacts.dailyFreeDrawDayId = 0
        f.sendMode = "rules"
        panel.handleTabInput(320, 980)
        oneAction(f, 0, f.protocol.ACTION_TYPES.ARTIFACT_DRAW, 1, "free_daily", "normal")
        eq(f.memory.currency.gems, 123, "免费不扣黑晶")
        eq(f.memory.currency.goldenKey, 50, "免费优先，不消耗已有钥匙")
        local before = #f.actions
        panel.handleTabInput(760, 980)
        oneAction(f, before, f.protocol.ACTION_TYPES.ARTIFACT_DRAW, 10, "diamond", "normal")
        eq(f.memory.currency.gems, 123, "已有钥匙十连不花钻")
        eq(f.memory.currency.goldenKey, 40, "普通十连真实消耗10把")
        before = #f.actions; panel.handleTabInput(320, 1800)
        oneAction(f, before, f.protocol.ACTION_TYPES.ARTIFACT_DRAW, 1, "diamond", "advanced")
        eq(f.memory.currency.goldenKey, 35, "高级单抽真实消耗5把")
        eq(f.memory.currency.gems, 123, "高级已有钥匙不花钻")
    end
    local f = fixture(); local panel = f.artifact()
    f.resetMemory(0, 7500, 50); f.memory.battle = { maxStageId = 2305 }
    f.settings.setAutoDiamondExchangeEnabled("artifact_advanced", true)
    panel.handleTabInput(320, 1800); panel.handleTabInput(760, 1800)
    noActions(f, 0, "高级未通关不发送，即使钥匙/黑晶足够")
    eq(panel.isKeyConfirmVisible(), false, "未解锁不打开modal")
    f.resetMemory(0, 7500, 0)
    f.settings.setAutoDiamondExchangeEnabled("artifact_advanced", false)
    f.settings.setAutoDiamondExchangeEnabled("artifact_normal", true)
    panel.handleTabInput(320, 1800)
    check(panel.isKeyConfirmVisible(), "普通开启不授权高级")
    noActions(f, 0, "宝箱档位授权隔离")
end

local function authoritativePayments()
    -- 独立内存PDM里的真实规则，不把send spy/客户端报价桩当作扣费测试。
    for _, pool in ipairs({ "standard", "stellar" }) do
        local price = pool == "standard" and 180 or 900
        for _, count in ipairs({ 1, 10 }) do
            for _, tickets in ipairs({ 0, count - 1, count }) do
                local f = fixture(); local page = f.tavern(pool)
                local cost = (count - tickets) * price
                f.resetMemory(tickets, cost); f.settings.setAutoDiamondExchangeEnabled("gacha_" .. pool, true)
                f.sendMode = "rules"
                page.handleInput(count == 10 and 766 or 314, 1902)
                oneAction(f, 0, f.protocol.ACTION_TYPES.GACHA_PULL, count, tickets >= count and "ticket" or "diamond", pool)
                local receipt = f.receipts[1]
                eq(receipt.success, true, "真实GachaService/UrGachaService混合支付成功")
                eq(receipt.result.totalCost, cost, "只扣缺口×180/900")
                eq(#receipt.result.gachaResults, count, "真实卡池生成原抽数奖励")
                eq(f.memory.currency.gems, 0, "黑晶恰好扣缺口")
                eq(f.memory.currency[pool == "standard" and "recruitTicket" or "stellarRecruitTicket"], 0, "优先耗尽实际券")
                eq(f.memory.currency[pool == "standard" and "stellarRecruitTicket" or "recruitTicket"], tickets, "不消费另一卡池券")
                eq(f.flushes, 1, "一次业务请求只调用一次内存落盘")
            end
            for _, change in ipairs({ "gems", "tickets" }) do
                local f = fixture(); local page = f.tavern(pool)
                f.resetMemory(count - 1, price); f.settings.setAutoDiamondExchangeEnabled("gacha_" .. pool, true)
                f.sendMode = "rules"
                local snapshot = {}
                f.beforeAuthority = function()
                    if change == "gems" then f.memory.currency.gems = price - 1
                    else f.memory.currency[pool == "standard" and "recruitTicket" or "stellarRecruitTicket"] = 0; f.memory.currency.gems = count * price - 1 end
                    snapshot = copy(f.memory)
                end
                page.handleInput(count == 10 and 766 or 314, 1902)
                oneAction(f, 0, f.protocol.ACTION_TYPES.GACHA_PULL, count, "diamond", pool)
                eq(f.receipts[1].success, false, "客户端允许后权威" .. change .. "变化仍拒绝")
                check(same(f.memory, snapshot), "权威拒绝不扣币/发角色/推进保底或统计")
                eq(f.dirty + f.flushes + #f.taskCalls, 0, "权威拒绝不标脏/落盘/任务")
            end
        end
    end
    for _, chest in ipairs({ "normal", "advanced" }) do
        for _, count in ipairs({ 1, 10 }) do
            local needed = count * (chest == "normal" and 1 or 5)
            for _, keys in ipairs({ 0, needed - 1, needed }) do
                local f = fixture(); local panel = f.artifact()
                local cost = (needed - keys) * 150
                f.resetMemory(0, cost, keys); f.settings.setAutoDiamondExchangeEnabled("artifact_" .. chest, true)
                f.sendMode = "rules"
                panel.handleTabInput(count == 10 and 760 or 320, chest == "normal" and 980 or 1800)
                oneAction(f, 0, f.protocol.ACTION_TYPES.ARTIFACT_DRAW, count, "diamond", chest)
                local receipt = f.receipts[1]
                eq(receipt.success, true, "真实ArtifactService混合支付成功")
                eq(receipt.result.keysUsed, keys, "实际优先使用已有钥匙")
                eq(receipt.result.keyCost, needed, "普通1/10与高级5/50钥匙需求不变")
                eq(receipt.result.diamondCost, cost, "缺少每把统一150")
                eq(f.memory.currency.goldenKey, 0, "钥匙余额正确")
                eq(f.memory.currency.gems, 0, "黑晶余额正确")
                eq(#f.memory.artifacts.bag, count, "一次请求只生成原抽数神器")
                eq(f.flushes, 1, "神器抽取单次内存落盘")
            end
            local f = fixture(); local panel = f.artifact()
            f.resetMemory(0, 150, needed - 1); f.settings.setAutoDiamondExchangeEnabled("artifact_" .. chest, true)
            f.sendMode = "rules"
            local snapshot = {}
            f.beforeAuthority = function() f.memory.currency.gems = 149; snapshot = copy(f.memory) end
            panel.handleTabInput(count == 10 and 760 or 320, chest == "normal" and 980 or 1800)
            oneAction(f, 0, f.protocol.ACTION_TYPES.ARTIFACT_DRAW, count, "diamond", chest)
            eq(f.receipts[1].success, false, "神器权威余额变化拒绝")
            check(same(f.memory, snapshot), "神器拒绝不消费/发奖/变免费标记")
            eq(f.dirty + f.flushes + #f.taskCalls, 0, "神器拒绝不落盘/推进任务")
        end
    end
end

local function safety()
    for _, f in ipairs(fixtures) do f.safe() end
    eq(File, nativeFile, "全局File未替换")
    eq(cache, nativeCache, "全局cache未替换")
    eq(time, nativeTime, "全局时钟未修改")
    for name in pairs(SOURCES) do eq(package.loaded[name], originalLoaded[name], "全局package.loaded未注入：" .. name) end
    for _, path in ipairs(reads) do
        local allowed = false
        for _, permitted in pairs(SOURCES) do if path == permitted then allowed = true; break end end
        check(allowed and path:sub(-4) == ".lua", "nativeCache只读取白名单生产Lua源码")
    end
end

-- review仅增加真实绘制出口，正常8组回归继续使用上面的隔离绘图替身。
---@type NVGContextWrapper?
local reviewVG = nil
local reviewFixture = nil ---@type any
local reviewFrames = 0
local REVIEW_LANGUAGES = { "zh_CN", "zh_TW", "en", "ja", "ko" }
local REVIEW_PRICES = { 180, 900, 150, 150 }

local function wantsReview()
    for _, arg in ipairs(GetArguments()) do if arg == "-auto-exchange-review" then return true end end
    return false
end

local function startReview()
    local f = fixture()
    reviewFixture = f
    -- 仅允许引擎UI库与其ImageCache，不把生产Settings或main交给真实require。
    f.deps["urhox-libs/UI"] = require("urhox-libs/UI")
    f.deps["urhox-libs/UI/Core/ImageCache"] = require("urhox-libs/UI/Core/ImageCache")
    for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgTranslate", "nvgScale", "nvgGlobalAlpha" }) do
        f.env[name] = assert(_G[name], "review缺少真实绘图API：" .. name)
    end
    f.env.YGNodeCalculateLayout = YGNodeCalculateLayout
    f.send = function() error("review禁止发送任何Action") end
    reviewVG = assert(nvgCreate(1), "review无法创建NanoVG上下文")
    f.vg = reviewVG
    -- 宿主和真实UI采用同一sans名字/字体；仅在Start建立一次，不逐帧创建字体。
    assert(nvgCreateFont(reviewVG, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0, "review字体载入失败")
    f.option = f.real("ui.widget.AutoDiamondExchangeOption")
    f.surface = f.real("ui.widget.DesignWidgetSurface")
    f.option.init()
    f.settings.setAutoDiamondExchangeEnabled("gacha_standard", true)
    f.settings.setAutoDiamondExchangeEnabled("artifact_normal", true)
    f.reviewMemory, f.reviewWrites = copy(f.memory), f.writes
    SubscribeToEvent(reviewVG, "NanoVGRender", "HandleAutoExchangeReview")
    print(TAG .. "REVIEW READY：真实Checkbox/Label/Surface；设置仅内存，四scope五语言；请用截图/validate参数结束")
end

local function drawReview()
    local f, vg = reviewFixture, reviewVG
    -- 模式A：明确1440×1600审阅板；物理/DPR -> 逻辑分辨率，再等比映射审阅板。
    -- 左侧1080×2400页面固定0.45缩放；右侧不缩放820×56近景，不伪称完整游戏页面。
    local w, h, dpr = graphics:GetWidth(), graphics:GetHeight(), graphics:GetDPR()
    local logicalW, logicalH = w / dpr, h / dpr
    local scale = math.min(logicalW / 1440, logicalH / 1600)
    nvgBeginFrame(vg, logicalW, logicalH, dpr)
    nvgSave(vg)
    nvgTranslate(vg, (logicalW - 1440 * scale) * 0.5, (logicalH - 1600 * scale) * 0.5)
    nvgScale(vg, scale, scale)
    local function rect(x, y, width, height, color)
        nvgBeginPath(vg); nvgRoundedRect(vg, x, y, width, height, 10)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 255)); nvgFill(vg)
    end
    local function text(x, y, message, size)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, size)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(225, 217, 199, 255)); nvgText(vg, x, y, message, nil)
    end
    rect(0, 0, 1440, 1600, { 16, 16, 20 })
    text(24, 46, "自动兑换 · 真实UI隔离审阅", 32)
    text(24, 90, "左：设计位置×0.45   右：820×56近景 / 4scope × 5语言", 23)
    text(24, 130, "设置仅内存；没有玩家档、购买、招募、开箱或联网动作", 20)
    nvgSave(vg)
    nvgTranslate(vg, 24, 180); nvgScale(vg, 0.45, 0.45)
    rect(0, 0, 1080, 2400, { 25, 23, 26 })
    text(60, 130, "1080×2400设计空间", 38)
    f.deps["core.I18n"].set("zh_CN")
    for _, placement in ipairs({
        { index = 3, y = 1076, label = "普通神器卡 (540,1076)" },
        { index = 2, y = 1410, label = "星辰确认框选项 (540,1410)" },
        { index = 4, y = 1896, label = "高级神器卡 (540,1896)" },
        { index = 1, y = 2180, label = "常规招募页 (540,2180)" },
    }) do
        text(130, placement.y - 55, placement.label, 30)
        f.option.draw(vg, SCOPES[placement.index], 540, placement.y, 820, REVIEW_PRICES[placement.index], false)
    end
    nvgRestore(vg)
    text(24, 1308, "仅控件/坐标审阅，不模拟整页背景或业务", 19)
    for languageIndex, language in ipairs(REVIEW_LANGUAGES) do
        local top = 168 + (languageIndex - 1) * 290
        rect(552, top, 864, 280, { 28, 26, 29 })
        text(574, top + 22, language .. " · 常规 / 星辰 / 普通神器 / 高级神器", 20)
        f.deps["core.I18n"].set(language)
        for scopeIndex, scope in ipairs(SCOPES) do
            f.option.draw(vg, scope, 984, top + 68 + (scopeIndex - 1) * 60, 820, REVIEW_PRICES[scopeIndex], false)
        end
    end
    nvgRestore(vg)
    nvgEndFrame(vg)
    reviewFrames = reviewFrames + 1
    if reviewFrames == 1 then
        noActions(f, 0, "真实UI审阅首帧")
        check(same(f.memory, f.reviewMemory), "review绘制不改玩家内存数据")
        eq(f.writes, f.reviewWrites, "review绘制不重复保存设置")
        print(TAG .. "REVIEW FIRST FRAME PASS：真实UI已绘制；视觉质量由截图审阅，不以spy代替")
    end
end

function HandleAutoExchangeReview()
    local ok, err = pcall(drawReview)
    if not ok then
        log:Write(LOG_ERROR, TAG .. "REVIEW FAIL " .. tostring(err))
        engine:Exit()
        error(TAG .. "REVIEW FAIL " .. tostring(err))
    end
end

function Stop()
    if reviewFixture and reviewFixture.surface then reviewFixture.surface.shutdown() end
    if reviewVG then nvgDelete(reviewVG); reviewVG = nil end
end

function Start()
    if wantsReview() then
        local ok, err = pcall(startReview)
        if not ok then
            log:Write(LOG_ERROR, TAG .. "REVIEW INIT FAIL " .. tostring(err))
            engine:Exit(); error(TAG .. "REVIEW INIT FAIL " .. tostring(err))
        end
        return -- review必须留到NanoVGRender截图，由-screenshot-frame/-validate退出。
    end
    for _, test in ipairs({
        { "四scope严格默认/隔离/保存加载/非法档案", preferences },
        { "真实Widget与页面Surface/点击/多语言接线", widgetAndLayout },
        { "酒馆confirm开关/单抽十连自动缺口支付", tavernConfirmAndAuto },
        { "酒馆原继续入口/pending先行/同步回执/门禁", tavernEntrypointsAndGates },
        { "宝箱confirm开关/单抽十连自动缺口支付", artifactConfirmAndAuto },
        { "宝箱原继续入口/pending/免费/已有钥匙/解锁", artifactEntrypointsAndGates },
        { "真实三规则服务混合扣费与权威余额变化拒绝", authoritativePayments },
        { "所有夹具无真实存档/账号/网络/全局污染", safety },
    }) do
        groups = groups + 1
        local ok, err = pcall(test[2])
        if ok then print(TAG .. "PASS " .. test[1])
        else
            local message = test[1] .. "：" .. tostring(err)
            failures[#failures + 1] = message
            print(TAG .. "FAIL " .. message)
            log:Write(LOG_ERROR, TAG .. message)
        end
    end
    print(TAG .. string.format("SUMMARY groups=%d checks=%d failures=%d", groups, checks, #failures))
    if #failures == 0 then print(TAG .. "ALL PASS") end
    -- 无validate报告依赖；失败也退出，但随后抛错，不吞失败/不输出误导性的ALL PASS。
    engine:Exit()
    if #failures > 0 then error(TAG .. table.concat(failures, "\n")) end
end
