-- Tap神器全队唯一/请求身份回归适配：真实生产装配链，所有夹具只在内存中。
-- 不启动main、不加载/读写存档；绘图spy只定位GitHub当前布局和锚定详情按钮。
local TAG = "[artifact_team_unique_test]"
local assertions, cases = 0, 0
local function check(value, label)
    assertions = assertions + 1
    assert(value, label)
end
local function eq(actual, expected, label)
    check(actual == expected, label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local function signature(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local rows = {}
    for k, v in pairs(value) do rows[#rows + 1] = signature(k) .. "=" .. signature(v) end
    table.sort(rows)
    return "{" .. table.concat(rows, ",") .. "}"
end

function Start()
    local restores, cleanups = {}, {}
    local function replace(owner, key, value)
        local old = owner[key]
        restores[#restores + 1] = function() owner[key] = old end
        owner[key] = value
    end
    local function run(name, fn)
        cases = cases + 1
        fn()
        print(TAG .. " PASS " .. name)
    end
    local ok, err = pcall(function()
        local Schema = require("shared.artifact.ArtifactSchema")
        local Service = require("rules.artifact.ArtifactService")
        local Handler = require("rules.artifact.ArtifactHandler")
        local PDM = require("rules.character.PlayerDataManager")
        local Protocol = require("shared.Protocol")
        local Dispatcher = require("runtime.ClientDispatcher")
        local Store = require("core.PlayerStore")
        local GameState = require("core.GameState")
        local function artifact(id, typeId)
            return { id = tostring(id), artifactId = typeId or 5, quality = 2, valueRatio = 4321 }
        end
        local function fresh()
            local data = Schema.Fields.artifacts.getDefault()
            data.bag = { artifact(1), artifact(2), artifact(3, 6), artifact(4, 7), artifact(5, 8) }
            data.nextId = 6
            Schema.normalizeModule(data)
            return data
        end
        local function countRefs(data, id)
            local count = 0
            for t = 1, Schema.TEAM_COUNT do
                for s = 1, Schema.SLOT_COUNT do
                    for ss = 1, Schema.SUB_SLOT_COUNT do
                        if tostring(Schema.getEquippedId(data, s, ss, t) or "") == tostring(id) then
                            count = count + 1
                        end
                    end
                end
            end
            return count
        end
        run("旧档重复引用迁移保bag且幂等", function()
            for _, mode in ipairs({ "long", "et", "e" }) do
                local data = fresh()
                local teams = {
                    ["1"] = { ["1"] = { ["1"] = 1, ["2"] = 3 }, ["2"] = { ["1"] = "1" } },
                    ["2"] = { ["1"] = { ["1"] = "1", ["2"] = "2" }, ["2"] = { ["1"] = "3" } },
                    ["3"] = { ["1"] = { ["1"] = "1" }, ["4"] = { ["2"] = "4" } },
                }
                if mode == "long" then data.equippedByTeam = teams
                elseif mode == "et" then data.et = teams
                else data.e = { ["1"] = 1, ["2"] = { ["1"] = "1", ["2"] = 3 } } end
                Schema.normalizeModule(data)
                eq(countRefs(data, 1), 1, mode .. "只保首处")
                eq(Schema.getEquippedId(data, 1, 1, 1), "1", mode .. "首处为队1第一格")
                eq(#data.bag, 5, mode .. "bag实体未删")
                eq(data.bag[5].valueRatio, 4321, mode .. "roll未变")
                local before = signature(data)
                Schema.normalizeModule(data)
                eq(signature(data), before, mode .. "迁移幂等")
                local restored = cjson.decode(cjson.encode(Schema.dehydrateModule(data)))
                Schema.normalizeModule(restored)
                eq(countRefs(restored, 1), 1, mode .. "JSON往返唯一")
                eq(#restored.bag, 5, mode .. "JSON往返保bag")
                if mode ~= "e" then
                    eq(Schema.getEquippedId(data, 1, 2, 2), "2", "不同实例同类型可分队")
                    eq(Schema.getEquippedId(data, 4, 2, 3), "4", "无冲突队3保留")
                end
            end
        end)
        run("混合键逐格合并及setter全队兜底", function()
            for _, mode in ipairs({ "long", "et", "e" }) do
                for _, op in ipairs({ "normalize", "set", "unset" }) do
                    local data = fresh()
                    local numeric = { [1] = { [1] = "1" }, ["1"] = { ["2"] = "3" },
                        [2] = { [1] = "4", ["1"] = "5" } }
                    local textual = { ["1"] = { ["1"] = "2" }, ["3"] = { ["2"] = "5" } }
                    local teams = { [1] = numeric, ["1"] = textual, ["2"] = { ["4"] = { ["1"] = "2" } } }
                    if mode == "long" then data.equippedByTeam = teams
                    elseif mode == "et" then data.et = teams else data.e = numeric end
                    if op == "normalize" then Schema.normalizeModule(data)
                    elseif op == "set" then Schema.setEquippedId(data, 1, 1, "1", 1)
                    else Schema.setEquippedId(data, 1, 1, nil, 1) end
                    Schema.normalizeModule(data)
                    eq(Schema.getEquippedId(data, 1, 2, 1), "3", "互补子格保留")
                    eq(Schema.getEquippedId(data, 1, 1, 1), op ~= "unset" and "1" or nil, "数字键优先/目标清理")
                    eq(Schema.getEquippedId(data, 2, 1, 1), "4", "数字子格冲突优先")
                    eq(#data.bag, 5, "混合键不删bag")
                    if mode ~= "e" then
                        eq(Schema.getEquippedId(data, 3, 2, 1), "5", "字符串team独有slot保留")
                        eq(Schema.getEquippedId(data, 4, 1, 2), "2", "其他队互补引用保留")
                    end
                    local before = signature(data)
                    Schema.normalizeModule(data)
                    eq(signature(data), before, "再次normalize幂等")
                end
            end
            local data = fresh()
            data.equippedByTeam = { ["1"] = { ["2"] = { ["1"] = 1 } }, ["2"] = { ["3"] = 1 } }
            local bagRef = data.bag
            Schema.setEquippedId(data, 4, 2, "1", 3)
            eq(countRefs(data, 1), 1, "setter清数字/字符串/标量旧引用")
            eq(Schema.getEquippedId(data, 4, 2, 3), "1", "setter新位置优先")
            eq(data.bag, bagRef, "setter不重建bag")
            Schema.setEquippedId(data, 3, 1, "1", 3)
            eq(Schema.getEquippedId(data, 4, 2, 3), nil, "同队移位清旧位")
        end)

        local uid = 984218
        local modules = { artifacts = fresh(), player = { level = 60 }, battle = { maxStageId = 1906 } }
        local pushes, flushes = 0, 0
        PDM.Setup({ serverDispatcher = { pushModule = function(sentUid, name)
            eq(sentUid, uid, "服务测试独立uid")
            eq(name, "artifacts", "只推神器模块")
            pushes = pushes + 1
        end } })
        PDM.AttachLocalModules(uid, modules)
        local realFlush = PDM.FlushImmediate
        replace(PDM, "FlushImmediate", function(sentUid) flushes = flushes + 1 return realFlush(sentUid) end)
        cleanups[#cleanups + 1] = function() PDM.RemovePlayer(uid, true) PDM.RemovePlayer(1, true) PDM.Setup({}) end
        local equipHandler = Handler.actionHandlers[Protocol.ACTION_TYPES.ARTIFACT_EQUIP]
        run("真实Service跨队拒绝零状态零推送", function()
            eq(Service.Equip(uid, "1", 1, 1, 1), true, "队1首装")
            eq(Service.Equip(uid, "3", 2, 1, 2), true, "队2已有目标")
            local before, p, f = signature(modules), pushes, flushes
            local success, reason = Service.Equip(uid, "1", 2, 1, 2)
            eq(success, false, "拒绝跨队复用")
            check(tostring(reason or ""):find("先卸下", 1, true), "明确先卸下")
            eq(signature(modules), before, "拒绝不改原队或目标")
            eq(pushes, p, "拒绝不标脏推送")
            eq(flushes, f, "拒绝不Flush")
            eq(Service.Equip(uid, "2", 1, 1, 2), true, "同类型另实例分队合法")
            eq(Service.Equip(uid, "1", 4, 2, 1), true, "同队换槽")
            eq(Schema.getEquippedId(modules.artifacts, 1, 1, 1), nil, "同队清原位")
            eq(Service.Unequip(uid, 4, 2, 1), true, "明确卸原队")
            eq(Service.Equip(uid, "1", 4, 2, 3), true, "卸后可装另队")
            for _, mode in ipairs({ "long", "et", "e" }) do
                local raw = { bag = { artifact(1), artifact(2) }, nextId = 3 }
                if mode == "long" then raw.equippedByTeam = { ["1"] = { ["2"] = { ["1"] = 1 } } }
                elseif mode == "et" then raw.et = { ["1"] = { ["2"] = 1 } }
                else raw.e = { ["2"] = { ["1"] = "1" } } end
                modules.artifacts = raw
                local bagRef = raw.bag
                before, p, f = signature(raw), pushes, flushes
                eq(Service.Equip(uid, "1", 1, 1, 2), false, mode .. "未迁移旧档拒绝")
                eq(signature(raw), before, mode .. "拒绝不normalize旧档")
                eq(raw.bag, bagRef, mode .. "拒绝保表身份")
                eq(pushes, p, "旧档拒绝不推送")
                eq(flushes, f, "旧档拒绝不Flush")
            end
            modules.artifacts = fresh()
            Service.Equip(uid, "1", 1, 1, 1)
            local params = { artifactId = "1", teamIdx = 2, slot = 1, subSlot = 1, requestId = "rejected" }
            local response = equipHandler(uid, params)
            eq(response.success, false, "真实Handler拒绝")
            for _, key in ipairs({ "requestId", "artifactId", "teamIdx", "slot", "subSlot" }) do
                eq(response[key], params[key], "失败回显" .. key)
            end
            params.artifactId, params.requestId = "2", "accepted"
            response = equipHandler(uid, params)
            eq(response.success, true, "真实Handler合法另实例")
            eq(response.requestId, "accepted", "成功回显requestId")
            modules.artifacts = fresh()
            modules.artifacts.bag = { artifact(1), artifact(2), artifact(3) }
            Schema.normalizeModule(modules.artifacts)
            Schema.setEquippedId(modules.artifacts, 1, 1, "1", 2)
            before = signature(modules.artifacts)
            eq(Service.Merge(uid, { "1", "2", "3" }), false, "队2占用不能合成")
            eq(Service.Reroll(uid, { "1", "2" }), false, "队2占用不能置换")
            eq(signature(modules.artifacts), before, "消耗拒绝保bag")
        end)

        -- 生产链保真：UI -> GameAction -> LocalActionBridge -> Handler/Service
        -- -> ClientMessageHandler -> ChurchResults。存档与无关页面隔离，不替换这些入口。
        local function noop() end
        local isolated, storageCalls = {}, 0
        local realRequire = require
        replace(_G, "require", function(path) return isolated[path] or realRequire(path) end)
        isolated["boot.StandaloneSave"] = { Flush = function()
            storageCalls = storageCalls + 1 error("test forbids save access")
        end }
        replace(require("rules.redeem.RedeemService"), "Init", noop)
        local clock = { elapsedTime = 100 }
        replace(_G, "time", clock)
        local paint = { slots = {}, icons = {}, buttons = {}, texts = {}, stack = {}, tx = 0, ty = 0, sx = 1, sy = 1 }
        local function screen(x, y) return paint.tx + x * paint.sx, paint.ty + y * paint.sy end
        local DrawUtil = require("core.DrawUtil")
        replace(DrawUtil, "drawTextStroke", function(_, _, _, text) paint.texts[#paint.texts + 1] = text end)
        replace(DrawUtil, "drawImageCentered", noop)
        replace(DrawUtil, "drawRoundedRectCentered", noop)
        local BF = require("systems.ButtonFeedback")
        replace(BF, "begin", function() return false end)
        replace(BF, "finish", noop)
        replace(BF, "trigger", noop)
        local Asset = require("config.ArtifactAssetUtil")
        replace(Asset, "preloadIcons", noop)
        replace(Asset, "drawIcon", function(_, item, x, y, size)
            if item then
                local sx, sy = screen(x, y)
                paint.icons[#paint.icons + 1] = { id = tostring(item.id), x = sx, y = sy, size = size }
            end
        end)
        replace(require("ui.widget.ImageCache"), "init", noop)
        for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFill", "nvgStroke",
            "nvgStrokeColor", "nvgStrokeWidth", "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgFillColor",
            "nvgGlobalAlpha", "nvgIntersectScissor" }) do replace(_G, name, noop) end
        replace(_G, "nvgCreateImage", function() return -1 end)
        replace(_G, "nvgRGBA", function() return {} end)
        replace(_G, "nvgTextBounds", function(_, _, _, text) return utf8.len(text) * 14 end)
        replace(_G, "nvgText", function(_, _, _, text) paint.texts[#paint.texts + 1] = text end)
        replace(_G, "nvgSave", function()
            paint.stack[#paint.stack + 1] = { tx = paint.tx, ty = paint.ty, sx = paint.sx, sy = paint.sy }
        end)
        replace(_G, "nvgRestore", function()
            local last = table.remove(paint.stack)
            paint.tx, paint.ty, paint.sx, paint.sy = last.tx, last.ty, last.sx, last.sy
        end)
        replace(_G, "nvgTranslate", function(_, x, y) paint.tx, paint.ty = paint.tx + x * paint.sx, paint.ty + y * paint.sy end)
        replace(_G, "nvgScale", function(_, x, y) paint.sx, paint.sy = paint.sx * x, paint.sy * y end)
        replace(require("core.DarkIcon"), "drawNine", function(_, kind, x, y, w, h)
            local sx, sy = screen(x + w * 0.5, y + h * 0.5)
            if kind == "slot" then paint.slots[#paint.slots + 1] = { x = sx, y = sy }
            elseif kind == "btn" then paint.buttons[#paint.buttons + 1] = { x = sx, y = sy } end
        end)
        local Panel = require("ui.church.ChurchArtifactPanel")
        local Detail = require("ui.character.hero.ArtifactDetailPanel")
        local churchState = { open = true }
        local router = require("ui.church.ChurchResults").bind({ state = churchState,
            getProtocol = function() return Protocol end, ArtifactPanel = Panel,
            ArtifactDrawPanel = {}, CharacterPanel = {}, clearPowerCache = noop })
        local receipts = {}
        isolated["ui.church.ChurchPage"] = { onActionResult = function(response)
            receipts[#receipts + 1] = copy(response)
            router.onActionResult(response)
        end }
        for _, path in ipairs({ "ui.hud.popup.RewardPopup", "ui.loot.LootBox", "ui.loot.LootBoxPage",
            "ui.blacksmith.BlacksmithPage", "ui.backpack.BackpackPanel", "ui.church.talent.TalentPage",
            "ui.tavern.TavernPage", "ui.market.MarketPage", "ui.dungeon.DungeonPage", "ui.dungeon.DungeonBattleScene",
            "ui.dev.GMConsolePanel", "ui.hud.TopBar", "ui.battle.scene.BattleScene", "ui.character.panel.CharacterPanel",
            "ui.character.equip.EquipmentDetail", "ui.hud.popup.RedeemCodePanel", "systems.LootBoxSystem", "systems.TutorialManager" }) do isolated[path] = {} end
        isolated["ui.hud.BottomNav"] = { refreshTownBadge = noop }
        local Action = require("runtime.GameAction")
        local Bridge = require("runtime.LocalActionBridge")
        local Messages = require("runtime.ClientMessageHandler")
        Messages.setup({ sendAction = Action.sendAction, ui = {} })
        local watcher = { update = noop, subscribed = false }
        replace(_G, "SubscribeToEvent", function(event, callback)
            if event == "Update" then watcher.update, watcher.subscribed = callback, true end
        end)
        Store.Cleanup()
        Dispatcher.reset()
        Store.Init()
        Bridge.init()
        local uiLevel = 60
        replace(GameState, "getLevel", function() return uiLevel end)
        local sender = Action.sendAction
        local requests = {}
        local context = { state = churchState, getProtocol = function() return Protocol end,
            getClient = function() return { sendAction = function(action, params)
                requests[#requests + 1] = copy(params)
                return sender(action, params)
            end } end }
        Panel.setContext(context)
        Panel.init({})
        cleanups[#cleanups + 1] = function()
            Panel.reset() Panel.setContext(nil) Detail.setEquipActionStateGetter(nil)
            Store.Cleanup() Dispatcher.reset() GameState.setLocalPlayerSync(nil)
        end
        local function data() return Store.Get("artifacts") end
        local function draw()
            paint.slots, paint.icons, paint.buttons, paint.texts = {}, {}, {}, {}
            Panel.drawContent({})
        end
        local function clickSlot(team, slot, sub)
            draw()
            local cell = paint.slots[((team - 1) * Schema.SLOT_COUNT + slot - 1) * Schema.SUB_SLOT_COUNT + sub]
            check(cell ~= nil, "使用当前公开绘制定位槽位")
            Panel.handleTabInput(cell.x, cell.y)
        end
        local function equipButton()
            paint.buttons, paint.texts = {}, {}
            Detail.draw({})
            local button = paint.buttons[1]
            check(button ~= nil, "使用当前锚定详情绘制定位按钮")
            Panel.handleTabInput(button.x, button.y)
        end
        local function selectBag(id)
            draw()
            local point = {}
            local bottomSlot = paint.slots[Schema.TEAM_COUNT * Schema.SLOT_COUNT * Schema.SUB_SLOT_COUNT]
            for _, icon in ipairs(paint.icons) do
                if icon.id == tostring(id) and icon.size == 160 and icon.y > bottomSlot.y then point = icon break end
            end
            check(point.x ~= nil, "公开绘制中找到未装实例" .. id)
            Panel.handleTabInput(point.x, point.y)
            eq(Detail.getSelection().artifactId, tostring(id), "GitHub锚定详情保持实例身份")
            equipButton()
        end
        local function reset()
            Panel.reset()
            uiLevel, churchState.open = 60, true
            clock.elapsedTime = clock.elapsedTime + 10
            Dispatcher.set("artifacts", fresh())
            Dispatcher.set("battle", { maxStageId = 1906 })
            Dispatcher.set("player", { level = 60 })
            sender, requests, receipts = Action.sendAction, {}, {}
        end
        local function advance(dt)
            watcher.update("Update", { TimeStep = { GetFloat = function() return dt end } })
        end
        local function deliver(request, success)
            local response = copy(request)
            response.action, response.success, response.reason = Protocol.ACTION_TYPES.ARTIFACT_EQUIP, success, "fixture rejection"
            Messages.handleActionResult(response)
        end
        run("第二队生产同步安装成功立即解锁", function()
            reset()
            selectBag("1") clickSlot(1, 1, 1)
            eq(Schema.getEquippedId(data(), 1, 1, 1), "1", "首件生产落地")
            eq(receipts[1].success, true, "真实生产成功回执")
            check(churchState.floatText ~= "正在安装神器", "同步send返回不覆盖成功提示")
            selectBag("2") clickSlot(2, 1, 1)
            eq(#requests, 2, "首件同步成功后第二件可发")
            eq(Schema.getEquippedId(data(), 1, 1, 2), "2", "第二队生产安装落地")
            eq(countRefs(data(), "1"), 1, "首件全队唯一")
            eq(countRefs(data(), "2"), 1, "第二件全队唯一")
            selectBag("3") clickSlot(2, 2, 1)
            eq(#requests, 3, "第二队成功之后继续解锁")
        end)
        run("失败回执及发送false/抛错后重试", function()
            for _, mode in ipairs({ "service_reject", "legacy_receipt", "send_false", "send_throw" }) do
                reset() selectBag("1")
                sender = function(action)
                    if mode == "service_reject" then
                        uiLevel = 1 return Action.sendAction(action, requests[#requests])
                    elseif mode == "legacy_receipt" then deliver({}, false) return true
                    elseif mode == "send_false" then return false else error("fixture send error") end
                end
                clickSlot(2, 1, 1)
                eq(Schema.getEquippedId(data(), 1, 1, 2), nil, mode .. "失败不写目标")
                if mode == "service_reject" then
                    eq(receipts[1].success, false, "真实Handler等级失败")
                    eq(receipts[1].requestId, requests[1].requestId, "生产失败保请求身份")
                end
                uiLevel = 60 Dispatcher.set("player", { level = 60 }) sender = Action.sendAction
                clickSlot(2, 1, 1)
                eq(#requests, 2, mode .. "立即重试")
                eq(Schema.getEquippedId(data(), 1, 1, 2), "1", mode .. "重试生产落地")
            end
        end)
        run("异步成功失败/闭页回执按身份释放", function()
            for _, closed in ipairs({ false, true }) do
                for _, success in ipairs({ false, true }) do
                    reset() selectBag("1") sender = function() return true end
                    clickSlot(2, 1, 1) clickSlot(2, 1, 1)
                    eq(#requests, 1, "等待回执禁止重发")
                    churchState.open = not closed
                    local before = churchState.floatText
                    if success then
                        Messages.handleActionResult(equipHandler(1, requests[1]))
                    else deliver(requests[1], false) end
                    if closed then eq(churchState.floatText, before, "闭页收尾不覆盖提示") end
                    churchState.open, sender = true, Action.sendAction
                    if success then selectBag("2") end
                    clickSlot(2, 2, 1)
                    eq(#requests, 2, "回执释放后可发")
                    eq(Schema.getEquippedId(data(), 2, 1, 2), success and "2" or "1", "收尾后真实落地")
                end
            end
        end)
        run("超时同目标重试不接受迟到成功失败回执", function()
            reset() selectBag("1") sender = function() return true end
            clickSlot(2, 1, 1)
            check(watcher.subscribed, "真实WaitForChange注册Update")
            advance(6) clickSlot(2, 1, 1)
            eq(#requests, 2, "超时允许同目标重试")
            check(requests[1].requestId ~= requests[2].requestId, "同目标请求身份不同")
            for _, success in ipairs({ true, false }) do
                local before = churchState.floatText
                deliver(requests[1], success)
                eq(churchState.floatText, before, "迟到回执不盖新提示")
                clickSlot(2, 1, 1)
                eq(#requests, 2, "迟到回执不解锁新请求")
            end
            deliver(requests[2], false) sender = Action.sendAction clickSlot(2, 1, 1)
            eq(#requests, 3, "当前失败正确释放")
            eq(Schema.getEquippedId(data(), 1, 1, 2), "1", "当前失败后生产落地")
        end)
        run("旧timer取消/reset后身份不复用", function()
            reset() selectBag("1") sender = function() return true end
            clickSlot(2, 1, 1) advance(4) deliver(requests[1], false)
            clickSlot(2, 1, 1) advance(2) clickSlot(2, 1, 1)
            eq(#requests, 2, "取消旧timer不提前清新pending")
            local old = copy(requests[1])
            Panel.reset()
            local before = churchState.floatText
            deliver(old, true)
            eq(churchState.floatText, before, "reset后旧回执不展示")
            selectBag("1") clickSlot(2, 1, 1)
            eq(#requests, 3, "reset后新请求可发")
            check(requests[3].requestId ~= old.requestId, "reset不复用请求身份")
            deliver(old, false) clickSlot(2, 1, 1)
            eq(#requests, 3, "reset前旧回执不影响新请求")
        end)
        run("GitHub钉住详情实时占用与旧取下防误卸", function()
            reset() selectBag("1")
            Schema.setEquippedId(data(), 1, 1, "1", 1)
            clickSlot(2, 1, 1)
            eq(#requests, 0, "候选被别队占用不发送")
            check(churchState.floatText:find("先卸下", 1, true), "UI跨队明确拒绝")
            eq(Schema.getEquippedId(data(), 1, 1, 1), "1", "不误卸原队")
            Panel.reset() clickSlot(1, 1, 1)
            eq(Detail.isPinned(), true, "保留GitHub点击钉住详情")
            paint.texts = {} Detail.draw({})
            check(table.concat(paint.texts, "|"):find("队伍1", 1, true), "详情显示实际占用队")
            equipButton()
            eq(Schema.getEquippedId(data(), 1, 1, 1), nil, "正常取下精确来源")
            Schema.setEquippedId(data(), 1, 1, "1", 2) clickSlot(2, 1, 1)
            Schema.setEquippedId(data(), 1, 1, "2", 2)
            paint.texts = {} Detail.draw({})
            check(table.concat(paint.texts, "|"):find("位置已变", 1, true), "旧详情实时禁用")
            local count = #requests
            equipButton()
            eq(#requests, count, "旧详情不发误卸动作")
            eq(Schema.getEquippedId(data(), 1, 1, 2), "2", "保留替换实体")
            eq(storageCalls, 0, "生产链零存档调用")
        end)
        check(cases >= 9 and assertions >= 170, "防空通过：执行全部迁移场景")
    end)
    for i = #cleanups, 1, -1 do pcall(cleanups[i]) end
    for i = #restores, 1, -1 do restores[i]() end
    if ok then print(TAG .. " ALL PASS: " .. assertions .. " assertions, " .. cases .. " cases")
    else print(TAG .. " FAIL: " .. tostring(err)) log:Write(LOG_ERROR, TAG .. " " .. tostring(err)) end
    engine:Exit()
end
