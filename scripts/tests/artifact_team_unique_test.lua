-- Tap神器全队唯一/请求身份回归适配：真实生产装配链，所有夹具只在内存中。
-- 不启动main、不加载/读写存档；绘图spy只定位当前槽位、拖动来源和只读详情。
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
        -- 模块导入可能触发酒馆历史检查；只允许查询为不存在，绝不回退到玩家文件。
        local storageAccess = 0
        replace(_G, "File", function()
            storageAccess = storageAccess + 1
            error("神器专项禁止玩家文件读写", 0)
        end)
        replace(_G, "fileSystem", { FileExists = function(_, path)
            if path == "gacha_history.json" then return false end
            storageAccess = storageAccess + 1
            error("神器专项禁止未知文件查询: " .. tostring(path), 0)
        end })
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
        local modules = { artifacts = fresh(), player = { level = 60 }, battle = { maxStageId = 1906 } } ---@type table
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
        run("真实Service跨队原位交换且失败零状态零推送", function()
            eq(Service.Equip(uid, "1", 1, 1, 1), true, "队1首装")
            eq(Service.Equip(uid, "3", 2, 1, 2), true, "队2已有目标")
            local bagRef, equippedRef = modules.artifacts.bag, modules.artifacts.equippedByTeam
            local sourceRow, targetRow = equippedRef[1][1], equippedRef[2][2]
            local before, p, f = signature(modules), pushes, flushes
            local success, reason, result = Service.Equip(uid, "1", 2, 1, 2)
            eq(success, true, "跨队直接交换")
            eq(reason, nil, "合法交换无需先卸下")
            eq(Schema.getEquippedId(modules.artifacts, 1, 1, 1), "3", "旧目标回来源队原位")
            eq(Schema.getEquippedId(modules.artifacts, 2, 1, 2), "1", "指定实例移到目标")
            eq(modules.artifacts.bag, bagRef, "交换保bag引用")
            eq(modules.artifacts.equippedByTeam, equippedRef, "交换保装配表引用")
            eq(equippedRef[1][1], sourceRow, "交换保来源行引用")
            eq(equippedRef[2][2], targetRow, "交换保目标行引用")
            eq(result.cause, "artifact_equip", "成功交换explicit cause")
            eq(pushes, p + 1, "交换只推一次完整最终状态")
            eq(flushes, f + 1, "沿原Flush规则一次")
            eq(Service.Equip(uid, "2", 1, 1, 2), true, "同类型另实例分队合法")
            eq(Service.Equip(uid, "1", 4, 2, 1), true, "跨队空位移动")
            eq(Schema.getEquippedId(modules.artifacts, 2, 1, 2), nil, "空位移动清原位")
            eq(Service.Unequip(uid, 4, 2, 1), true, "明确卸来源")
            eq(Service.Equip(uid, "1", 4, 2, 3), true, "卸后可装另队")
            for _, mode in ipairs({ "long", "et", "e" }) do
                local raw = { bag = { artifact(1), artifact(2) }, nextId = 3 }
                if mode == "long" then raw.equippedByTeam = { ["2"] = { ["2"] = { ["1"] = 1 } } }
                elseif mode == "et" then raw.et = { ["2"] = { ["2"] = 1 } }
                else raw.e = { ["2"] = { ["2"] = "1" } } end
                modules.artifacts = raw
                modules.player.level, modules.battle.maxStageId = mode == "e" and 30 or 60, 905
                local originalBag = raw.bag
                before, p, f = signature(raw), pushes, flushes
                eq(Service.Equip(uid, "1", 1, 1, 1), false, mode .. "未迁移旧档来源锁定拒绝")
                eq(signature(raw), before, mode .. "拒绝不normalize旧档")
                eq(raw.bag, originalBag, mode .. "拒绝保表身份")
                eq(pushes, p, "旧档拒绝不推送")
                eq(flushes, f, "旧档拒绝不Flush")
            end
            modules.player.level, modules.battle.maxStageId = 60, 1906
            modules.artifacts = fresh()
            Service.Equip(uid, "1", 1, 1, 1)
            Schema.setEquippedId(modules.artifacts, 1, 2, "2", 2)
            local params = { artifactId = "1", teamIdx = 2, slot = 1, subSlot = 1, requestId = "rejected" }
            local response = equipHandler(uid, params)
            eq(response.success, false, "真实Handler同type拒绝")
            for _, key in ipairs({ "requestId", "artifactId", "teamIdx", "slot", "subSlot" }) do
                eq(response[key], params[key], "失败回显" .. key)
            end
            params.artifactId, params.requestId = "3", "accepted"
            response = equipHandler(uid, params)
            eq(response.success, true, "真实Handler合法另类型")
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
        run("两方向同type/资格/实例完整校验与同格幂等", function()
            local function fixture()
                modules.artifacts = fresh()
                modules.player.level, modules.battle.maxStageId = 60, 1906
                Schema.setEquippedId(modules.artifacts, 1, 1, "1", 1)
                Schema.setEquippedId(modules.artifacts, 2, 1, "3", 2)
            end
            for _, mode in ipairs({ "source_type", "target_type", "source_level", "source_team", "target_missing", "source_duplicate", "target_duplicate", "bag_duplicate" }) do
                fixture()
                if mode == "source_type" then Schema.setEquippedId(modules.artifacts, 1, 2, "4", 1)
                    for _, a in ipairs(modules.artifacts.bag) do if a.id == "4" then a.artifactId = 6 end end
                elseif mode == "target_type" then Schema.setEquippedId(modules.artifacts, 2, 2, "2", 2)
                elseif mode == "source_level" then
                    Schema.setEquippedId(modules.artifacts, 1, 2, "1", 1) modules.player.level = 30
                elseif mode == "source_team" then
                    Schema.setEquippedId(modules.artifacts, 1, 1, "1", 3) modules.battle.maxStageId = 1001
                elseif mode == "target_missing" then modules.artifacts.equippedByTeam[2][2][1] = "999"
                elseif mode == "source_duplicate" then modules.artifacts.equippedByTeam[2][3] = { [1] = "1" }
                elseif mode == "target_duplicate" then modules.artifacts.equippedByTeam[1][3] = { [1] = "3" }
                elseif mode == "bag_duplicate" then modules.artifacts.bag[#modules.artifacts.bag + 1] = artifact(1) end
                local before, p, f = signature(modules), pushes, flushes
                eq(Service.Equip(uid, "1", 2, 1, 2), false, mode .. "交换拒绝")
                eq(signature(modules), before, mode .. "失败不半交换/不迁移")
                eq(pushes, p, mode .. "失败零推送")
                eq(flushes, f, mode .. "失败零Flush")
            end
            fixture()
            local before, p, f = signature(modules), pushes, flushes
            local success, _, result = Service.Equip(uid, "1", 1, 1, 1)
            eq(success, true, "同格重试成功")
            eq(result.changed, false, "同格不产生操作delta")
            eq(result.cause, nil, "同格无提升cause")
            eq(signature(modules), before, "同格不改模块")
            eq(pushes, p, "同格不重复推送")
            eq(flushes, f, "同格不重复Flush")
            Schema.setEquippedId(modules.artifacts, 1, 2, "3", 1)
            eq(Service.Equip(uid, "1", 1, 2, 1), true, "同号位不同type两格互换")
            eq(Schema.getEquippedId(modules.artifacts, 1, 1, 1), "3", "同号位旧目标回原子格")
            eq(Schema.getEquippedId(modules.artifacts, 1, 2, 1), "1", "同号位来源移目标子格")
            for id = 1, 5 do eq(countRefs(modules.artifacts, id), (id == 1 or id == 3) and 1 or 0, "最终实例唯一" .. id) end
        end)

        run("真实Service推送贯通正式队伍缓存与神器正增特效", function()
            local CP = require("ui.character.panel.CharacterPanel")
            local Power = require("ui.character.panel.CharacterPower")
            local Effect = require("ui.fx.SpinePowerUpEffect")
            local Bus = require("core.EventBus")
            local Events = require("config.GameEvents")
            local Draw = require("ui.character.panel.CharacterPanelDraw2")
            local Detail = require("ui.character.detail.CharacterDetail")
            local Tri = require("ui.battle.tri.BattleTriPage")
            local Scene = require("ui.battle.scene.BattleScene")
            local Nav = require("ui.hud.BottomNav")
            local function noop() end
            replace(Draw, "initImages", noop)
            replace(Detail, "init", noop)
            replace(Tri, "refreshHeroProgressTeams", noop)
            replace(Scene, "refreshAllyStats", noop)
            replace(Nav, "setBadge", noop)
            replace(Nav, "refreshTownBadge", noop)
            local clock = { elapsedTime = 200 }
            replace(_G, "time", clock)
            local fullRefreshes = 0
            local bind = Power.bind
            replace(Power, "bind", function(deps)
                local bound = bind(deps)
                local refresh = bound.refreshPowerCache
                bound.refreshPowerCache = function(cause)
                    fullRefreshes = fullRefreshes + 1
                    return refresh(cause)
                end
                bound.refreshNavBadge = noop -- 仅隔离与正式战力无关的角标/纹理预热。
                return bound
            end)
            Store.Cleanup() Dispatcher.reset() Store.Init()
            local heroes = { roster = { [1] = { level = 30 }, [2] = { level = 30 }, [3] = { level = 30 } },
                deployed = { 1, 0, 0, 0 }, teams = { { slots = { 1, 0, 0, 0 } },
                    { slots = { 2, 0, 0, 0 } }, { slots = { 3, 0, 0, 0 } } } }
            Dispatcher.set("equipment", { inventory = {}, equipped = {} })
            Dispatcher.set("talents", { litNodes = {} })
            Dispatcher.set("battle", { maxStageId = 2001 })
            Dispatcher.set("player", { level = 60 })
            local artifacts = fresh()
            artifacts.bag = { artifact(1, 5), artifact(3, 5) }
            artifacts.bag[1].quality, artifacts.bag[2].quality = 1, 6
            Dispatcher.set("artifacts", artifacts)
            Dispatcher.set("heroes", heroes)
            CP.init(nil) CP.setHeroesData(Dispatcher.get("heroes"))
            local snapshots = {}
            local function observe(data) snapshots[#snapshots + 1] = copy(data) end
            Bus.on(Events.TEAM_POWER_CHANGED, observe)
            cleanups[#cleanups + 1] = function() Effect.destroy() Bus.off(Events.TEAM_POWER_CHANGED, observe) end
            Effect.init()
            Dispatcher.set("artifacts", Dispatcher.get("artifacts"), { normalized = true })
            clock.elapsedTime = clock.elapsedTime + 3
            local live = Dispatcher.getAll()
            PDM.AttachLocalModules(uid, live)
            PDM.Setup({ serverDispatcher = { pushModule = function(sentUid, name, value)
                eq(sentUid, uid, "真实评分链独立uid")
                Dispatcher.set(name, value, { normalized = true })
            end } })
            local function row(team)
                for _, value in ipairs(Effect.getDisplayRows()) do if value.teamIdx == team then return value end end
            end
            local oldPower, count, scores = CP.getTotalPower(1), #snapshots, fullRefreshes
            local response = equipHandler(uid, { artifactId = "1", teamIdx = 1, slot = 1, subSlot = 1, requestId = "power1" })
            eq(response.success, true, "真实Handler安装成功")
            eq(fullRefreshes, scores + 1, "同步神器推送完整评分恰好一次")
            eq(#snapshots, count + 1, "完整队伍事件恰好一次")
            eq(snapshots[#snapshots].cause, "artifact_equip", "成功cause不是伪level_up")
            eq(assert(row(1)).base, oldPower, "旧正式队伍缓存作为显示基准")
            eq(assert(row(1)).power, CP.getTotalPower(1), "新正式队伍缓存作为显示终值")
            check(assert(row(1)).delta > 0, "实际神器安装正式战力正增")
            eq(Schema.takeEquipNotificationCause(live.artifacts), nil, "cause已消费且不残留")
            eq(equipHandler(uid, { artifactId = "3", teamIdx = 2, slot = 1, subSlot = 1 }).success, true, "高品质神器装另一队")
            clock.elapsedTime = clock.elapsedTime + 6 Effect.update(0)
            local old1, old2 = CP.getTotalPower(1), CP.getTotalPower(2)
            scores, count = fullRefreshes, #snapshots
            response = equipHandler(uid, { artifactId = "3", teamIdx = 1, slot = 1, subSlot = 1, requestId = "swap" })
            eq(response.success, true, "真实Handler跨队交换成功")
            eq(fullRefreshes, scores + 1, "两队交换仍一次完整评分")
            eq(#snapshots, count + 1, "两队交换发完整事件一次")
            check(CP.getTotalPower(1) > old1 and CP.getTotalPower(2) < old2, "真实公式两队一增一减")
            eq(assert(row(1)).delta, CP.getTotalPower(1) - old1, "增队只显示自己的精确delta")
            eq(row(2), nil, "减队不伪装一队总净增")
            eq(snapshots[#snapshots].powers[2], CP.getTotalPower(2), "完整事件仍带减队真实新值")
            scores, count = fullRefreshes, #snapshots
            response = equipHandler(uid, { artifactId = "3", teamIdx = 1, slot = 1, subSlot = 1, requestId = "retry" })
            eq(response.success, true, "同位置重试成功回执")
            eq(fullRefreshes, scores, "重试不重复评分使delta归零")
            eq(#snapshots, count, "重试不发伪变化")
            eq(response.cause, nil, "重试无cause")
            local before = signature(live.artifacts)
            response = equipHandler(uid, { artifactId = "missing", teamIdx = 2, slot = 2, subSlot = 1 })
            eq(response.success, false, "实例失败真实回执")
            eq(signature(live.artifacts), before, "失败保完整装配")
            eq(fullRefreshes, scores, "失败不评分")
            Dispatcher.set("artifacts", live.artifacts, { normalized = true })
            eq(snapshots[#snapshots].cause, nil, "普通再推送不复用成功cause")
            local scopeOk = pcall(Schema.withEquipNotification, live.artifacts, function() error("notification boundary") end)
            eq(scopeOk, false, "发布异常仍明确传回")
            eq(Schema.takeEquipNotificationCause(live.artifacts), nil, "发布异常finally清cause")
            eq(live.artifacts.cause, nil, "cause不写玩家模块")
            eq(Schema.dehydrateModule(copy(live.artifacts)).cause, nil, "cause不进入存档结构")
            Effect.destroy() Bus.off(Events.TEAM_POWER_CHANGED, observe)
            Store.Cleanup() Dispatcher.reset()
            PDM.RemovePlayer(uid, true)
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
        local paint = { slots = {}, icons = {}, buttons = {}, texts = {}, panels = {}, stack = {}, tx = 0, ty = 0, sx = 1, sy = 1 }
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
        for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgFill", "nvgStroke",
            "nvgStrokeColor", "nvgStrokeWidth", "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgFillColor",
            "nvgGlobalAlpha", "nvgIntersectScissor" }) do replace(_G, name, noop) end
        replace(_G, "nvgRoundedRect", function(_, x, y, w, h)
            local sx, sy = screen(x, y)
            paint.panels[#paint.panels + 1] = { x = sx, y = sy, w = w * paint.sx, h = h * paint.sy }
        end)
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
            local sx, sy = screen(x, y)
            if kind == "panel" then
                paint.panels[#paint.panels + 1] = { x = sx, y = sy, w = w * paint.sx, h = h * paint.sy }
            elseif kind == "slot" then
                paint.slots[#paint.slots + 1] = { x = sx + w * paint.sx * 0.5, y = sy + h * paint.sy * 0.5 }
            elseif kind == "btn" then
                paint.buttons[#paint.buttons + 1] = { x = sx + w * paint.sx * 0.5, y = sy + h * paint.sy * 0.5 }
            end
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
        local PlayerStore = require("core.PlayerStore")
        local PlayerStoreUpdate = PlayerStore.Update
        local watcher = { update = noop }
        replace(PlayerStore, "Update", function(dt)
            PlayerStoreUpdate(dt)
            watcher.update("Update", { TimeStep = { GetFloat = function() return dt end } })
        end)
        Store.Cleanup()
        Dispatcher.reset()
        Store.Init()
        Bridge.init()
        Messages.setup({ sendAction = Action.sendAction, ui = {} })
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
            paint.slots, paint.icons, paint.buttons, paint.texts, paint.panels = {}, {}, {}, {}, {}
            Panel.drawContent({})
        end
        local function tapSlot(team, slot, sub)
            draw()
            local cell = paint.slots[((team - 1) * Schema.SLOT_COUNT + slot - 1) * Schema.SUB_SLOT_COUNT + sub]
            check(cell ~= nil, "使用当前公开绘制定位槽位")
            Panel.handleTabInput(cell.x, cell.y)
        end
        local function slotDetailPoint(xOffset)
            paint.buttons, paint.texts, paint.panels = {}, {}, {}
            Detail.draw({})
            eq(#paint.buttons, 0, "已装神器详情不绘制安装/取下/洗练按钮")
            local panel = paint.panels[1]
            check(panel ~= nil, "已装详情公开绘制存在")
            return panel.x + (xOffset or 265), panel.y + 797
        end
        local selectedArtifactId = ""
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
            paint.buttons, paint.texts, paint.panels = {}, {}, {}
            Detail.draw({})
            eq(#paint.buttons, 0, "背包详情不再绘制安装和洗练按钮")
            local panel = paint.panels[1]
            check(panel ~= nil, "背包只读详情公开绘制存在")
            local count = #requests
            for _, xOffset in ipairs({ 133, 397 }) do
                Panel.handleTabInput(panel.x + xOffset, panel.y + 797)
                eq(#requests, count, "背包旧操作区不发送安装/洗练")
                eq(Detail.isPinned(), true, "背包旧操作区只保留钉住详情")
            end
            selectedArtifactId = tostring(id) -- 测试手势来源，不写生产pending。
        end
        local function dragSelectedToSlot(team, slot, sub)
            draw()
            local point = {}
            for _, icon in ipairs(paint.icons) do
                if icon.id == selectedArtifactId and icon.size == 160 then point = icon break end
            end
            check(point.x ~= nil, "公开绘制中找到当前拖动来源" .. selectedArtifactId)
            local cell = paint.slots[((team - 1) * Schema.SLOT_COUNT + slot - 1) * Schema.SUB_SLOT_COUNT + sub]
            check(cell ~= nil, "公开绘制定位拖放目标槽位")
            Panel.handleDragBegin(point.x, point.y)
            Panel.handleDragMove(point.x + 15, point.y)
            if Panel.isItemDragging() then
                Panel.handleDragMove(cell.x, cell.y)
                eq(Panel.handleDragEnd(cell.x, cell.y), true, "来源拖到目标按真实装配手势处理")
            else
                -- 请求pending时只会建立滚动手势；水平试拖不改变后续来源坐标。
                Panel.handleDragEnd(point.x + 15, point.y)
            end
            Panel.cancelPointer()
        end
        local function reset()
            Panel.reset()
            uiLevel = 60
            churchState.open = true
            clock.elapsedTime = clock.elapsedTime + 10
            Dispatcher.set("artifacts", fresh())
            Dispatcher.set("battle", { maxStageId = 906, clearedStages = { ["905"] = true } })
            Dispatcher.set("player", { level = 60 })
            sender, requests, receipts = Action.sendAction, {}, {}
        end
        local function advance(dt)
            PlayerStore.Update(dt)
        end
        local function deliver(request, success)
            local response = copy(request)
            response.action, response.success, response.reason = Protocol.ACTION_TYPES.ARTIFACT_EQUIP, success, "fixture rejection"
            Messages.handleActionResult(response)
        end
        run("第二队生产同步安装成功立即解锁", function()
            reset()
            selectBag("1") dragSelectedToSlot(1, 1, 1)
            eq(Schema.getEquippedId(data(), 1, 1, 1), "1", "首件生产落地")
            eq(receipts[1].success, true, "真实生产成功回执")
            check(churchState.floatText ~= "正在安装神器", "同步send返回不覆盖成功提示")
            selectBag("2") dragSelectedToSlot(2, 1, 1)
            eq(#requests, 2, "首件同步成功后第二件可发")
            eq(Schema.getEquippedId(data(), 1, 1, 2), "2", "第二队生产安装落地")
            eq(countRefs(data(), "1"), 1, "首件全队唯一")
            eq(countRefs(data(), "2"), 1, "第二件全队唯一")
            selectBag("3") dragSelectedToSlot(2, 2, 1)
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
                dragSelectedToSlot(2, 1, 1)
                eq(Schema.getEquippedId(data(), 1, 1, 2), nil, mode .. "失败不写目标")
                if mode == "service_reject" then
                    eq(receipts[1].success, false, "真实Handler等级失败")
                    eq(receipts[1].requestId, requests[1].requestId, "生产失败保请求身份")
                end
                uiLevel = 60 Dispatcher.set("player", { level = 60 }) sender = Action.sendAction
                dragSelectedToSlot(2, 1, 1)
                eq(#requests, 2, mode .. "立即重试")
                eq(Schema.getEquippedId(data(), 1, 1, 2), "1", mode .. "重试生产落地")
            end
        end)
        run("异步成功失败/闭页回执按身份释放", function()
            for _, closed in ipairs({ false, true }) do
                for _, success in ipairs({ false, true }) do
                    reset() selectBag("1") sender = function() return true end
                    dragSelectedToSlot(2, 1, 1) dragSelectedToSlot(2, 1, 1)
                    eq(#requests, 1, "等待回执禁止重发")
                    churchState.open = not closed
                    local before = churchState.floatText
                    if success then
                        Messages.handleActionResult(equipHandler(1, requests[1]))
                    else deliver(requests[1], false) end
                    if closed then eq(churchState.floatText, before, "闭页收尾不覆盖提示") end
                    churchState.open, sender = true, Action.sendAction
                    if success then selectBag("2") end
                    dragSelectedToSlot(2, 2, 1)
                    eq(#requests, 2, "回执释放后可发")
                    eq(Schema.getEquippedId(data(), 2, 1, 2), success and "2" or "1", "收尾后真实落地")
                end
            end
        end)
        run("超时同目标重试不接受迟到成功失败回执", function()
            reset() selectBag("1") sender = function() return true end
            dragSelectedToSlot(2, 1, 1)
            check(type(PlayerStore.Update) == "function", "PlayerStore.Update由主循环驱动等待")
            advance(6) dragSelectedToSlot(2, 1, 1)
            eq(#requests, 2, "超时允许同目标重试")
            check(requests[1].requestId ~= requests[2].requestId, "同目标请求身份不同")
            for _, success in ipairs({ true, false }) do
                local before = churchState.floatText
                deliver(requests[1], success)
                eq(churchState.floatText, before, "迟到回执不盖新提示")
                dragSelectedToSlot(2, 1, 1)
                eq(#requests, 2, "迟到回执不解锁新请求")
            end
            deliver(requests[2], false) sender = Action.sendAction dragSelectedToSlot(2, 1, 1)
            eq(#requests, 3, "当前失败正确释放")
            eq(Schema.getEquippedId(data(), 1, 1, 2), "1", "当前失败后生产落地")
        end)
        run("旧timer取消/reset后身份不复用", function()
            reset() selectBag("1") sender = function() return true end
            dragSelectedToSlot(2, 1, 1) advance(4) deliver(requests[1], false)
            dragSelectedToSlot(2, 1, 1) advance(2) dragSelectedToSlot(2, 1, 1)
            eq(#requests, 2, "取消旧timer不提前清新pending")
            local old = copy(requests[1])
            Panel.reset()
            local before = churchState.floatText
            deliver(old, true)
            eq(churchState.floatText, before, "reset后旧回执不展示")
            selectBag("1") dragSelectedToSlot(2, 1, 1)
            eq(#requests, 3, "reset后新请求可发")
            check(requests[3].requestId ~= old.requestId, "reset不复用请求身份")
            deliver(old, false) dragSelectedToSlot(2, 1, 1)
            eq(#requests, 3, "reset前旧回执不影响新请求")
        end)
        run("GitHub钉住详情实时占用与已装详情只读", function()
            reset() selectBag("1")
            Schema.setEquippedId(data(), 1, 1, "1", 1)
            dragSelectedToSlot(2, 1, 1)
            eq(#requests, 1, "实时来源已装后仍可直接跨队移动")
            check(not churchState.floatText:find("先卸下", 1, true), "UI不再要求先卸下")
            eq(Schema.getEquippedId(data(), 1, 1, 1), nil, "跨队移动清原位")
            eq(Schema.getEquippedId(data(), 1, 1, 2), "1", "实时来源移动目标落地")
            Panel.reset() tapSlot(2, 1, 1)
            eq(Detail.isPinned(), true, "保留GitHub点击钉住详情")
            paint.texts = {} Detail.draw({})
            local positionText = table.concat(paint.texts, "|")
            check(positionText:find("队伍2 · 前锋 · 第1格", 1, true), "已装详情保留位置提示")
            for _, xOffset in ipairs({ 133, 397 }) do
                local slotX, slotY = slotDetailPoint(xOffset)
                Panel.handleTabInput(slotX, slotY)
                eq(Schema.getEquippedId(data(), 1, 1, 2), "1", "已装详情旧操作区不改变装配")
                eq(#requests, 1, "已装详情旧操作区不派取下/洗练")
            end
            local slotX, slotY = slotDetailPoint(397)
            Schema.setEquippedId(data(), 1, 1, "1", 2) tapSlot(2, 1, 1)
            Schema.setEquippedId(data(), 1, 1, "2", 2)
            paint.texts = {} Detail.draw({})
            check(table.concat(paint.texts, "|"):find("位置已变", 1, true), "旧详情实时禁用")
            local count = #requests
            Panel.handleTabInput(slotX, slotY)
            eq(#requests, count, "旧已装详情位置无操作")
            eq(Schema.getEquippedId(data(), 1, 1, 2), "2", "保留替换实体")
            eq(storageCalls, 0, "生产链零存档调用")
        end)
        eq(storageAccess, 0, "全程无玩家文件访问或未知文件查询")
        check(cases >= 9 and assertions >= 170, "防空通过：执行全部迁移场景")
    end)
    for i = #cleanups, 1, -1 do pcall(cleanups[i]) end
    for i = #restores, 1, -1 do restores[i]() end
    if ok then print(TAG .. " ALL PASS: " .. assertions .. " assertions, " .. cases .. " cases")
    else print(TAG .. " FAIL: " .. tostring(err)) log:Write(LOG_ERROR, TAG .. " " .. tostring(err)) end
    engine:Exit()
end
