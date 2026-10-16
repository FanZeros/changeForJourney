-- 独立 Runtime 专项；不启动 main/Standalone，不读玩家档，不委托原生 File/FileSystem。
-- 真实链：Link -> GameAction -> LocalActionBridge -> EquipmentHandler/Service ->
-- PDM.MarkDirty -> Dispatcher/PlayerStore -> CMH -> 仓库 Link 回执适配。
-- 仓库不是完整 BackpackPanel/Horizon 输入；Shift 判定由外层负责，本文件直接测专用入口。
-- 详情两种布局执行真实 EquipmentDetail.draw/handleInput、真实字体与同步桥；
-- 装饰性套装角标和其他页面为显式替身，不作为 GPU/设备交互验收。
-- /workspace/.cli/UrhoXRuntime tests/equipment_lock_shortcut_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
local vg = nil ---@type NVGContextWrapper?
local checks, groups = 0, 0
local function check(value, why)
    checks = checks + 1
    assert(value, why)
end
local function noop() end
local function group(name, fn)
    fn()
    groups = groups + 1
    print("[equipment_lock_shortcut_test] PASS " .. name)
end

local function run()
    local F = require("tests.InventoryCurationFixture")
    local h = F.new()
    h.allowBootFixture = true -- 只允许真实 Bridge；下面不 require 任何 Boot/存档入口。
    -- Fixture 的源码加载器只通过 cache:GetFile 读 .lua；被测生产模块不能另开资源文件。
    h.env.cache = { GetFile = function() error("production cache file access forbidden") end,
        GetResource = function() error("production cache resource access forbidden") end }
    local unexpectedIo = 0
    h.env.io = setmetatable({}, { __index = function() unexpectedIo = unexpectedIo + 1; error("io forbidden") end })
    h.env.os.execute = function() unexpectedIo = unexpectedIo + 1; error("execute forbidden") end
    h.env.os.remove = function() unexpectedIo = unexpectedIo + 1; error("remove forbidden") end
    h.env.os.rename = function() unexpectedIo = unexpectedIo + 1; error("rename forbidden") end
    local toasts, sent, results, routed, dispatchErrors = {}, {}, {}, {}, {}
    local active = {} -- CMH 的仓库 seam；只委托真实 Link，不伪造状态机或业务结果。
    local tutorialEvents = 0
    local namedSfx, uiClicks = {}, {}
    h.mocks["systems.TutorialManager"] = {
        isActive = function() return false end, isBuildingUnlocked = function() return true end,
        notifyEvent = function() tutorialEvents = tutorialEvents + 1 end,
    }
    -- BF.trigger("ed_equip") 的通用点击音不是 GameSFX.play("install")；分开记录，
    -- 禁止所有命名业务音效，只有详情真实按钮允许其原有 playUIClick(2)。
    h.mocks["systems.GameSFX"] = {
        play = function(name) namedSfx[#namedSfx + 1] = tostring(name) end,
        playUIClick = function(kind) uiClicks[#uiClicks + 1] = kind end,
    }
    h.mocks["core.UiToast"] = { show = function(text) toasts[#toasts + 1] = text end }
    local filter = { open = false }
    h.mocks["ui.widget.SetFilterDialog"] = { isOpen = function() return filter.open end,
        close = function() filter.open = false end }
    h.mocks["ui.widget.EquipmentSetIcon"] = { drawBadge = noop, draw = function() return false end,
        isEnabled = function() return false end }
    h.mocks["ui.backpack.BackpackPanel"] = { onActionResult = function(data)
        routed[#routed + 1] = F.copy(data)
        assert(active.api, "CMH missing Link adapter")
        active.api.onActionResult(data)
    end }
    for _, name in ipairs({ "ui.hud.popup.RewardPopup", "ui.loot.LootBox", "ui.loot.LootBoxPage",
        "ui.blacksmith.BlacksmithPage", "ui.church.ChurchPage", "ui.church.talent.TalentPage",
        "ui.tavern.TavernPage", "ui.market.MarketPage", "ui.dungeon.DungeonPage",
        "ui.dungeon.DungeonBattleScene", "ui.dev.GMConsolePanel", "ui.hud.TopBar",
        "ui.character.panel.CharacterPanel", "ui.hud.popup.RedeemCodePanel" }) do
        h.mocks[name] = { onActionResult = noop }
    end
    -- 只截断无关 handler pack；EquipmentHandler、EquipmentService 和 PDM 均为原生产源码。
    for _, name in ipairs({ "battle.Battle", "hero.Hero", "gacha.Gacha", "blacksmith.Blacksmith",
        "task.Task", "redeem.Redeem", "awakening.Awakening", "advancement.Advancement",
        "talent.Talent", "signin.SignIn", "gm.GM", "market.Market", "loot.Loot", "sweep.Sweep",
        "artifact.Artifact", "dungeon.Dungeon", "offline.Offline", "tower.Tower" }) do
        h.mocks["rules." .. name .. "Handler"] = { actionHandlers = {} }
    end
    h.mocks["rules.task.TaskService"] = { SetPersistCallback = noop }
    h.mocks["rules.dungeon.DungeonService"] = { SetPersistCallback = noop }
    h.mocks["rules.redeem.RedeemService"] = { Init = noop }

    local modules = F.modules(h, 12)
    for _, name in ipairs({ "talents", "artifacts", "slotEnhance", "task", "redeem", "signin",
        "market", "tavern", "dungeon", "global_profile", "quotas" }) do modules[name] = {} end
    h:attach(modules)
    local Store = h.require("core.PlayerStore")
    local State = h.require("core.GameState")
    State.syncPlayerData(modules.player)
    State.syncFromCurrency(modules.currency)
    local AT = h.require("shared.Protocol").ACTION_TYPES
    local Text, Lang = h.require("core.I18nInventoryCuration"), h.require("core.I18n")
    local Action = h.require("runtime.GameAction")
    local Handler = h.require("rules.equipment.EquipmentHandler")
    local handlerCalls, dirtyCalls, notifications = {}, {}, {}
    local realHandler = Handler.actionHandlers[AT.TOGGLE_EQUIP_LOCK]
    Handler.actionHandlers[AT.TOGGLE_EQUIP_LOCK] = function(uid, params)
        handlerCalls[#handlerCalls + 1] = F.copy(params)
        return realHandler(uid, params)
    end
    local PDM = h.require("rules.character.PlayerDataManager")
    local mark = PDM.MarkDirty
    PDM.MarkDirty = function(uid, name)
        dirtyCalls[#dirtyCalls + 1] = name
        return mark(uid, name)
    end
    local Msg = h.require("runtime.ClientMessageHandler")
    Msg.setup({ sendAction = Action.sendAction, ui = {} })
    local receive = Msg.handleActionResult
    Msg.handleActionResult = function(data)
        results[#results + 1] = F.copy(data)
        local ok, err = pcall(receive, data)
        if not ok then dispatchErrors[#dispatchErrors + 1] = tostring(err); error(err) end
    end
    local Bridge = h.require("runtime.LocalActionBridge")
    Bridge.init() -- 安装真实 pushModule，替换 Fixture 的“仅提交后通知”优选约束。
    Store.Subscribe("equipment", function(data)
        notifications[#notifications + 1] = { locked = data.inventory["1"] and data.inventory["1"].locked,
            data = data }
    end)
    local realSend = Action.sendAction
    Action.sendAction = function(action, params)
        sent[#sent + 1] = { action = action, params = F.copy(params) }
        check(action == AT.TOGGLE_EQUIP_LOCK, "lock must not send wear/decompose/recycle action")
        return realSend(action, params)
    end
    local Detail = h.require("ui.character.equip.EquipmentDetail")
    local Link = h.require("ui.backpack.BackpackEquipLink")
    local GRID = { FIRST_ROW_TOP = 470, CLIP_BOTTOM = 1980, CELL_SIZE = 160, GAP = 30, COLS = 5 }
    local columns = { 160, 350, 540, 730, 920 }
    local list = {}
    for i = 1, 12 do list[i] = F.copy(modules.equipment.inventory[tostring(i)]) end
    local function makeLink(send, equipment)
        local state = { open = true, closing = false, tab = "equip", scrollY = 0,
            scrollMax = 1000, scrollVel = 0 }
        local item = { open = false }
        local api = Link.bind({ state = state, GRID = GRID, CELL_COL_CX = columns,
            EquipmentDetail = Detail, SetFilterDialog = h.mocks["ui.widget.SetFilterDialog"],
            getEquipList = function() return list end,
            getEquipmentData = function() return equipment or Store.Get("equipment") end,
            getHeroesData = function() return modules.heroes end,
            getCharacterDetail = function() return { isEquipTab = function() return false end } end,
            getLeftPage = function() return nil end, getHostMode = function() return "left" end,
            itemDetState = item, SCROLL_WHEEL_STEP = 190,
            clampScroll = function() state.scrollY = math.max(0, math.min(state.scrollMax, state.scrollY)) end,
            toast = function(text) toasts[#toasts + 1] = text end,
            sendAction = send,
        })
        return { api = api, state = state, item = item }
    end
    local firstX, firstY = 160, 550
    local function click(f) return f.api.handleLockRightClick(firstX, firstY) end
    local function toastIs(source) check(toasts[#toasts] == Text.text(source), "expected toast " .. source) end
    local function snapshotEquipment()
        local copy = F.copy(modules.equipment)
        for _, equip in pairs(copy.inventory) do equip.locked = nil end
        return copy
    end
    local protectedEquipment = snapshotEquipment()
    local protectedBox, protectedHeroes = F.copy(modules.lootbox), F.copy(modules.heroes)
    local function unchangedExceptLock()
        F.same(snapshotEquipment(), protectedEquipment)
        F.same(modules.lootbox, protectedBox)
        F.same(modules.heroes, protectedHeroes)
        check(tutorialEvents == 0, "lock cannot trigger equip tutorial event")
        check(#namedSfx == 0, "lock cannot trigger install/recycle or any other named business SFX")
    end

    group("real synchronous Link -> Handler -> MarkDirty -> CMH -> Link, lock then unlock", function()
        active = makeLink(nil)
        local source = modules.equipment.inventory["1"]
        local d0, n0, r0, h0 = #dirtyCalls, #notifications, #routed, #handlerCalls
        check(source.locked == nil, "fresh deterministic unlocked item")
        check(click(active), "real shortcut consumed cell")
        check(source.locked == true and Store.Get("equipment").inventory["1"] == source,
            "sync shared instance flips exactly once, not optimistic double flip")
        check(#sent == 1 and #handlerCalls == h0 + 1, "one real action and handler")
        check(#dirtyCalls == d0 + 1 and dirtyCalls[#dirtyCalls] == "equipment", "one real MarkDirty")
        check(#notifications == n0 + 1 and notifications[#notifications].locked == true,
            "real PlayerStore subscriber receives authoritative locked value")
        check(#routed == r0 + 1 and #results == 1, "CMH forwards matching result once")
        ---@type table
        local request = assert(sent[1].params)
        ---@type table
        local result = assert(results[1])
        check(request.lockRequestId ~= nil and result.lockRequestId == request.lockRequestId
            and tostring(result.seq) == tostring(request.seq) and result.success and result.locked,
            "real handler echoes request identity and authoritative result")
        toastIs("装备已锁定")
        check(click(active), "second immediate click accepted after synchronous ack")
        check(source.locked == nil and #sent == 2 and #handlerCalls == h0 + 2,
            "second action unlocks once, nil compact storage preserved")
        check(#dirtyCalls == d0 + 2 and #notifications == n0 + 2 and #routed == r0 + 2,
            "unlock publishes and routes exactly once")
        check(results[2].locked == false and results[2].lockRequestId ~= result.lockRequestId,
            "new click has distinct identity and false authoritative lock")
        toastIs("装备已解锁")
        unchangedExceptLock()
    end)

    group("real service rejection through CMH failure routing releases in-flight lock", function()
        local original = modules.equipment.inventory["1"]
        active = makeLink(function(action, params)
            modules.equipment.inventory["1"] = nil -- 源在命中和权威处理之间消失。
            local handled = Action.sendAction(action, params)
            modules.equipment.inventory["1"] = original
            return handled
        end)
        local d0, n0, r0 = #dirtyCalls, #notifications, #routed
        check(click(active), "real rejected request consumed")
        local result = results[#results]
        check(result.success == false and result.reason == "装备不存在"
            and result.lockRequestId == sent[#sent].params.lockRequestId and result.seq == 1,
            "real handler failure retains seq and lockRequestId")
        check(#routed == r0 + 1, "CMH failure reaches Backpack adapter")
        check(#dirtyCalls == d0 and #notifications == n0 and original.locked == nil,
            "service rejection neither mutates nor publishes")
        toastIs("锁定失败，请重试")
        -- 同一个 Link 不等三秒；若失败路由漏接，这里会被 pendingLock 吞掉。
        local s0 = #sent
        check(click(active) and #sent == s0 + 1, "failure unlocks same Link for immediate retry")
        check(#dirtyCalls == d0, "repeated true refusal still no dirty")
        unchangedExceptLock()
    end)

    group("real Bridge catches pre-mutation service exception and releases same Link immediately", function()
        local Service = h.require("rules.equipment.EquipmentService")
        local toggle = Service.ToggleEquipLock
        active = makeLink(nil)
        local source = assert(modules.equipment.inventory["1"])
        local start, s0, h0, d0, n0, r0, t0 = h.clock, #sent, #handlerCalls,
            #dirtyCalls, #notifications, #routed, #toasts
        local throws = 0
        check(source.locked == nil, "exception fixture starts unlocked")
        local before = F.copy(modules.equipment)
        -- 只在任何突变/MarkDirty前抛异常；不声称已修改后throw具有原子回滚语义。
        Service.ToggleEquipLock = function()
            throws = throws + 1
            error("expected equipment_lock_shortcut_test pre-mutation service exception")
        end
        local ok, err = pcall(function()
            check(click(active), "Bridge handles throwing real Handler call")
        end)
        Service.ToggleEquipLock = toggle -- 任何断言失败也先恢复真实Service方法。
        assert(ok, err)
        check(throws == 1 and #sent == s0 + 1 and #handlerCalls == h0 + 1,
            "one real Handler invocation reaches injected Service exception")
        check(#dirtyCalls == d0 and #notifications == n0 and source.locked == nil,
            "pre-mutation exception performs no MarkDirty, publish or lock mutation")
        F.same(modules.equipment, before)
        ---@type table
        local result = assert(results[#results])
        ---@type table
        local request = assert(sent[#sent].params)
        check(result.action == AT.TOGGLE_EQUIP_LOCK and result.success == false
            and result.reason == "本地处理失败" and result.seq == request.seq
            and result.lockRequestId == request.lockRequestId,
            "real Bridge exception response retains lock action, seq and lockRequestId")
        check(#routed == r0 + 1 and #toasts == t0 + 1,
            "CMH exception failure routes once and finishes pending immediately")
        toastIs("锁定失败，请重试")
        check(h.clock == start, "failure completed without timeout clock advance")
        check(click(active) and #sent == s0 + 2 and source.locked == true,
            "restored real service succeeds on immediate retry through same Link")
        check(#dirtyCalls == d0 + 1 and #notifications == n0 + 1 and #routed == r0 + 2,
            "retry has one authoritative dirty/push/result")
        toastIs("装备已锁定")
        check(click(active) and #sent == s0 + 3 and source.locked == nil,
            "same Link second success unlocks fixture once")
        check(#dirtyCalls == d0 + 2 and #notifications == n0 + 2 and #routed == r0 + 3,
            "unlock has one authoritative dirty/push/result")
        toastIs("装备已解锁")
        unchangedExceptLock()
    end)

    local function asyncLink()
        local queued = {}
        local f = makeLink(function(action, params)
            check(action == AT.TOGGLE_EQUIP_LOCK, "mock branch only lock action")
            queued[#queued + 1] = F.copy(params)
            return true
        end)
        return f, queued
    end
    local function ack(f, request, changes)
        local data = { action = AT.TOGGLE_EQUIP_LOCK, seq = request.seq,
            lockRequestId = request.lockRequestId, success = true, locked = true }
        for key, value in pairs(changes or {}) do data[key] = value end
        f.api.onActionResult(data)
    end
    group("single in-flight and strict id + seq; unrelated, stale and duplicate acknowledgements", function()
        local f, q = asyncLink()
        local t0 = #toasts
        check(click(f) and #q == 1, "async submitted once")
        check(click(f) and f.api.handleLockRightClick(350, 550) and #q == 1,
            "one pending lock across same/different cells")
        ack(f, q[1], { action = AT.EQUIP_ITEM })
        ack(f, q[1], { lockRequestId = q[1].lockRequestId + 99 })
        ack(f, q[1], { lockRequestId = tostring(q[1].lockRequestId) })
        ack(f, q[1], { seq = 2 })
        check(#toasts == t0 and click(f) and #q == 1, "wrong action/id/type/seq cannot finish request")
        ack(f, q[1], { seq = tostring(q[1].seq) })
        toastIs("装备已锁定")
        check(#toasts == t0 + 1, "matching numeric/string seq completes exactly once")
        ack(f, q[1]); check(#toasts == t0 + 1, "duplicate result ignored")
        check(click(f) and #q == 2 and q[2].lockRequestId ~= q[1].lockRequestId, "new request id")
        ack(f, q[1], { success = false })
        check(click(f) and #q == 2 and #toasts == t0 + 1, "old same-seq failure cannot release new request")
        ack(f, q[2], { locked = false }); toastIs("装备已解锁")
        check(modules.equipment.inventory["1"].locked == nil, "mock ack does not optimistically mutate inventory")
    end)
    group("timeout on closed page, boundary, late ack and retry", function()
        local f, q = asyncLink()
        check(click(f), "timeout request submitted")
        local start, t0 = h.clock, #toasts
        h:setTime(start + 2.999); f.api.update()
        check(#toasts == t0 and click(f) and #q == 1, "not expired before three seconds")
        f.state.open = false
        h:setTime(start + 3); f.api.update()
        check(#toasts == t0 + 1, "closed page update expires at three seconds")
        toastIs("锁定请求超时，请重试")
        ack(f, q[1]); check(#toasts == t0 + 1, "late timed-out ack ignored")
        f.state.open = true
        check(click(f) and #q == 2, "retry after timeout")
        ack(f, q[1]); check(click(f) and #q == 2, "late old success cannot release new in-flight")
        ack(f, q[2], { success = false }); toastIs("锁定失败，请重试")
        check(click(f) and #q == 3, "matching rejection releases immediately")
        ack(f, q[3])
    end)
    group("handled=false and synchronous ack before false return", function()
        local calls = 0
        local f = makeLink(function() calls = calls + 1; return false end)
        local t0 = #toasts
        check(click(f) and calls == 1 and #toasts == t0 + 1, "unhandled produces one retry message")
        toastIs("锁定请求未处理，请重试")
        check(click(f) and calls == 2, "unhandled releases pending immediately")
        local sync = {}
        local syncCalls = 0
        sync = makeLink(function(_, params)
            syncCalls = syncCalls + 1
            ack(sync, params)
            return false
        end)
        t0 = #toasts
        check(click(sync) and #toasts == t0 + 1, "sync ack consumed pending before handled=false")
        toastIs("装备已锁定")
        check(click(sync) and syncCalls == 2, "sync completion permits next call")
    end)
    group("empty/gaps/closed/closing/tabs/filter/item detail reject without action", function()
        local f, q = asyncLink()
        local t0 = #toasts
        check(not f.api.handleLockRightClick(160, 469), "above clip")
        check(not f.api.handleLockRightClick(160, 1981), "below clip")
        check(not f.api.handleLockRightClick(255, 550), "horizontal cell gap")
        check(not f.api.handleLockRightClick(160, 645), "vertical row gap")
        check(not f.api.handleLockRightClick(920, 930), "empty last-row slot")
        f.state.open = false; check(not click(f), "closed page")
        f.state.open, f.state.closing = true, true; check(not click(f), "closing animation")
        f.state.closing = false
        for _, tab in ipairs({ "item", "decompose" }) do
            f.state.tab = tab; check(not click(f), "tab " .. tab)
        end
        f.state.tab = "equip"
        filter.open = true; check(not click(f), "set filter dialog")
        filter.open = false; f.item.open = true; check(not click(f), "item detail overlay")
        f.item.open = false
        check(#q == 0 and #toasts == t0, "all non-targets no action or success toast")
        check(click(f) and #q == 1, "normal cell resumes after gates removed")
        ack(f, q[1])
    end)
    group("real scroll geometry, stale list source and numeric inventory keys", function()
        Detail.close()
        local f, q = asyncLink()
        check(f.api.handleScroll(-1, 160, 550) and f.state.scrollY == 190, "real Link scrolling changes offset")
        check(click(f) and #q == 1 and q[1].seq == 6, "screen first row now hits seq6, not seq1")
        ack(f, q[1])
        check(not f.api.handleLockRightClick(160, 469) and #q == 1, "scrolled hidden cells cannot hit above clip")
        local absent = makeLink(function() error("stale list must not dispatch") end,
            { inventory = {}, equipped = {} })
        local t0 = #toasts
        check(click(absent) and #toasts == t0, "list ghost consumed but missing inventory not submitted")
        local numericQueue = {}
        local numeric = makeLink(function(_, params) numericQueue[#numericQueue + 1] = F.copy(params); return true end,
            { inventory = { [1] = F.copy(modules.equipment.inventory["1"]) }, equipped = {} })
        check(click(numeric) and #numericQueue == 1 and numericQueue[1].seq == 1, "numeric inventory key accepted")
        ack(numeric, numericQueue[1])
    end)
    group("five-language new lock hints nonempty and not missing-translation fallback", function()
        local hints = { "装备已锁定", "装备已解锁", "锁定失败，请重试",
            "锁定请求超时，请重试", "锁定请求未处理，请重试" }
        for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
            check(Lang.set(lang) and Lang.get() == lang, "set actual language " .. lang)
            for _, source in ipairs(hints) do
                local text = Text.text(source)
                check(type(text) == "string" and text:match("%S") ~= nil, "nonempty " .. lang .. "/" .. source)
                if lang ~= "zh_CN" then check(text ~= source, "translated, not fallback " .. lang .. "/" .. source) end
            end
            -- 文案不仅可查；真实 Link 对匹配回执仍选择当前语言。
            local f, q = asyncLink()
            check(click(f), "localized request")
            ack(f, q[1]); toastIs("装备已锁定")
        end
        Lang.set("zh_CN")
    end)

    group("real EquipmentDetail large/compact draw hotspot -> handleInput -> synchronous Bridge once", function()
        check(#uiClicks == 0, "Link shortcut/mocks do not trigger any UI click SFX")
        local uiClickStart = #uiClicks
        -- 观察真实绘制的锁图片及当前变换取得屏幕中心；不注入 detState/hotspot、不重写 Draw。
        local lockImage, lockDraws = -1, {}
        local nativeCreate, nativePattern = nvgCreateImage, nvgImagePattern
        h.env.nvgCreateImage = function(context, path, flags)
            local image = nativeCreate(context, path, flags)
            if path == "image/通用图标/UI_ICON_SUO.png" then lockImage = image end
            return image
        end
        h.env.nvgImagePattern = function(context, x, y, w, height, angle, image, alpha)
            if image == lockImage and lockImage >= 0 then
                local matrix = {}
                local returned = nvgCurrentTransform(context, matrix)
                if type(returned) == "table" then matrix = returned end
                assert(#matrix >= 6, "real NanoVG affine transform unavailable")
                local cx, cy = x + w * 0.5, y + height * 0.5
                lockDraws[#lockDraws + 1] = { x = matrix[1] * cx + matrix[3] * cy + matrix[5],
                    y = matrix[2] * cx + matrix[4] * cy + matrix[6], alpha = alpha }
            end
            return nativePattern(context, x, y, w, height, angle, image, alpha)
        end
        Detail.init(vg)
        check(lockImage >= 0, "real lock image loaded for both button paths")
        active = makeLink(nil)
        local function draw()
            lockDraws = {}
            nvgBeginFrame(vg, 1080, 2400, 1)
            Detail.draw(vg)
            nvgEndFrame(vg)
            check(#lockDraws == 1, "actual detail main panel renders one lock icon")
            return lockDraws[1]
        end
        for _, compact in ipairs({ false, true }) do
            Detail.open(1, nil, nil, compact, "backpack", 400, 500)
            h:setTime(h.clock + 1) -- 大面板同帧门禁与动画正常结束，不改生产时序。
            local point = draw()
            check(math.abs(point.alpha - 0.4) < 0.001, "real draw reflects initial unlocked state")
            for step = 1, 2 do
                local s0, d0, n0, r0, h0 = #sent, #dirtyCalls, #notifications, #routed, #handlerCalls
                check(Detail.handleInput(point.x, point.y), "real drawn lock hotspot consumed")
                check(#sent == s0 + 1 and #handlerCalls == h0 + 1 and #dirtyCalls == d0 + 1
                    and #notifications == n0 + 1 and #routed == r0 + 1,
                    "detail one click -> one handler/dirty/push/CMH route")
                local locked = step == 1
                check((modules.equipment.inventory["1"].locked == true) == locked,
                    "detail shared instance not flipped again after synchronous send")
                check(Detail.isOpen(), "locking does not close detail or invoke wear/decompose")
                point = draw()
                check(math.abs(point.alpha - (locked and 1 or 0.4)) < 0.001,
                    "next real draw reflects authoritative lock/unlock")
            end
            Detail.close()
            h:setTime(h.clock + 1)
            if not compact then
                nvgBeginFrame(vg, 1080, 2400, 1); Detail.draw(vg); nvgEndFrame(vg)
            end
        end
        h.env.nvgCreateImage, h.env.nvgImagePattern = nativeCreate, nativePattern
        check(#uiClicks == uiClickStart + 4, "four real detail lock clicks retain exactly four BF generic UI clicks")
        for index = uiClickStart + 1, #uiClicks do
            check(uiClicks[index] == 2, "detail lock click uses BF generic click type2, not deny/install sound")
        end
        unchangedExceptLock()
    end)
    check(#dispatchErrors == 0, "Bridge pcall did not hide CMH exception")
    check(h.fileCalls == 0 and h.fsCalls == 0 and unexpectedIo == 0,
        "File/FS/io sealed: zero virtual save or native delegation")
    check(h.randomCalls == 0, "no RNG consumption")
    for _, request in ipairs(sent) do check(request.action == AT.TOGGLE_EQUIP_LOCK, "all real sends are lock only") end
    for _, name in ipairs(dirtyCalls) do check(name == "equipment", "no reward/lootbox/currency dirty") end
    print("[equipment_lock_shortcut_test] IO File=" .. h.fileCalls .. " FS=" .. h.fsCalls
        .. " denied=" .. unexpectedIo .. " nativeDelegation=0; realActions=" .. #sent)
end

local function finish(ok, err)
    if ok then
        print("[equipment_lock_shortcut_test] ALL PASS " .. groups .. " groups " .. checks .. " assertions")
    else
        print("[equipment_lock_shortcut_test] [FAIL] " .. tostring(err) .. " after " .. checks .. " assertions")
    end
    engine:Exit()
end
function Start()
    local ok, err = pcall(function()
        vg = assert(nvgCreate(1), "NanoVG context unavailable")
        check(nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0, "real sans font loaded")
        SubscribeToEvent(vg, "NanoVGRender", "RunEquipmentLockShortcutTest")
    end)
    if not ok then finish(false, err) end
end
function RunEquipmentLockShortcutTest()
    UnsubscribeFromEvent("NanoVGRender")
    local ok, err = pcall(run)
    finish(ok, err)
end
function Stop()
    if vg then nvgDelete(vg); vg = nil end
end
