-- 神器拖放/悬停专项回归：真实 Panel、Details、Handler、Equip/Unequip、Store/Dispatcher/PDM。
-- 仅绘图/图片加载边界使用 spy；通过公共 API 和真实内存桥观察行为，不访问私有 state。
-- 不读写存档、不伪造进度存档。所有等级/关卡数据只存在独立 uid 的内存夹具。
-- Runtime: .cli/UrhoXRuntime tests/artifact_drag_hover_test.lua -tapcode_dir=/workspace
--          -tool_mode -graphicsheadless -nosound
-- 图形 spy 不是实机视觉验收；执行结果请保存到 screenshots/。

local TAG = "[artifact_drag_hover_test]"
local assertions, cases, failures = 0, 0, 0

local function eq(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": actual=" .. tostring(actual) .. ", expected=" .. tostring(expected))
end

local function check(value, label)
    assertions = assertions + 1
    assert(value, label)
end

function Start()
    local restores = {}
    local cleanups = {}
    local function replace(owner, key, value)
        local old = owner[key]
        restores[#restores + 1] = function() owner[key] = old end
        owner[key] = value
    end
    local ok, err = pcall(function()
        local Dispatcher = require("runtime.ClientDispatcher")
        local Store = require("core.PlayerStore")
        local PDM = require("rules.character.PlayerDataManager")
        local Schema = require("shared.artifact.ArtifactSchema")
        local Defs = require("shared.artifact.ArtifactDefs")
        local Service = require("rules.artifact.ArtifactService")
        local Handler = require("rules.artifact.ArtifactHandler")
        local Protocol = require("shared.Protocol")
        local ExpTable = require("config.ExpTable")
        local Asset = require("config.ArtifactAssetUtil")
        local Dark = require("core.DarkIcon")
        local BF = require("systems.ButtonFeedback")
        local uid = 984217
        local clock = { elapsedTime = 100 }
        replace(_G, "time", clock)

        -- 绘图 spy 记录真实 drawIcon 实例及最终坐标；仿射变换仅用于观测公共绘制输出。
        -- 不读 Panel/Details 的闭包、upvalue、debug 接口。
        local paint = { icons = {}, texts = {}, panels = {}, outlines = {}, colors = {}, stack = {},
            sx = 1, sy = 1, tx = 0, ty = 0, stroke = {} }
        local function noop() end
        local function screen(x, y)
            return paint.tx + x * paint.sx, paint.ty + y * paint.sy
        end
        local function clearPaint()
            paint.icons, paint.texts, paint.panels, paint.outlines, paint.colors, paint.stack = {}, {}, {}, {}, {}, {}
            paint.sx, paint.sy, paint.tx, paint.ty = 1, 1, 0, 0
        end
        for _, name in ipairs({ "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgFillColor",
            "nvgBeginPath", "nvgRect", "nvgFill", "nvgCircle", "nvgStrokeWidth", "nvgStroke",
            "nvgIntersectScissor", "nvgGlobalAlpha", "nvgFillPaint" }) do
            replace(_G, name, noop)
        end
        replace(_G, "nvgCreateImage", function() return -1 end)
        replace(_G, "nvgRGBA", function(r, g, b, a) return { r = r, g = g, b = b, a = a } end)
        replace(_G, "nvgStrokeColor", function(_, color)
            paint.stroke = color
            paint.colors[#paint.colors + 1] = color
        end)
        replace(_G, "nvgRoundedRect", function(_, x, y, w, h)
            local sx, sy = screen(x, y)
            paint.outlines[#paint.outlines + 1] = { x = sx, y = sy, w = w, h = h }
        end)
        replace(_G, "nvgText", function(_, x, y, text)
            local sx, sy = screen(x, y)
            paint.texts[#paint.texts + 1] = { x = sx, y = sy, text = text }
        end)
        replace(_G, "nvgTextBounds", function(_, _, _, text)
            return utf8.len(tostring(text or "")) * 14
        end)
        replace(_G, "nvgSave", function()
            paint.stack[#paint.stack + 1] = { sx = paint.sx, sy = paint.sy, tx = paint.tx, ty = paint.ty }
        end)
        replace(_G, "nvgRestore", function()
            local last = table.remove(paint.stack)
            check(last ~= nil, "绘图 save/restore 不失衡")
            paint.sx, paint.sy, paint.tx, paint.ty = last.sx, last.sy, last.tx, last.ty
        end)
        replace(_G, "nvgTranslate", function(_, x, y)
            paint.tx, paint.ty = paint.tx + x * paint.sx, paint.ty + y * paint.sy
        end)
        replace(_G, "nvgScale", function(_, x, y)
            paint.sx, paint.sy = paint.sx * x, paint.sy * y
        end)
        replace(Dark, "drawNine", function(_, kind, x, y, w, h)
            local sx, sy = screen(x, y)
            if kind == "panel" then
                paint.panels[#paint.panels + 1] = { x = sx, y = sy, w = w * paint.sx, h = h * paint.sy }
            end
        end)
        replace(Dark, "drawQualityBg", noop)
        replace(Dark, "drawIconDark", noop)
        replace(BF, "begin", function() return false end)
        replace(BF, "finish", noop)
        replace(BF, "trigger", noop)
        local realDrawIcon = Asset.drawIcon
        replace(Asset, "drawIcon", function(vg, artifact, cx, cy, size, opts)
            if artifact then
                local x, y = screen(cx, cy)
                paint.icons[#paint.icons + 1] = { id = tostring(artifact.id), artifact = artifact,
                    x = x, y = y, size = size, selected = opts and opts.selected == true }
            end
            return realDrawIcon(vg, artifact, cx, cy, size, opts)
        end)

        -- 公共数据管线保持真实。PDM 只挂接内存表，MarkDirty 通过真实 Dispatcher.set 回推。
        Store.Cleanup()
        Dispatcher.reset()
        Store.Init()
        local pushes, equipCalls, unequipCalls, closeCalls = 0, 0, 0, 0
        PDM.Setup({ serverDispatcher = { pushModule = function(sentUid, name, data)
            eq(sentUid, uid, "PDM推送独立测试uid")
            eq(name, "artifacts", "装配只推神器模块")
            pushes = pushes + 1
            Dispatcher.set(name, data)
        end } })
        local realEquip, realUnequip = Service.Equip, Service.Unequip
        replace(Service, "Equip", function(...)
            equipCalls = equipCalls + 1
            return realEquip(...)
        end)
        replace(Service, "Unequip", function(...)
            unequipCalls = unequipCalls + 1
            return realUnequip(...)
        end)
        local Panel = require("ui.church.ChurchArtifactPanel")
        local Details = require("ui.character.hero.ArtifactDetailPanel")
        local vg = {} -- 全部底层绘图已 spy；仍运行真实 init、drawContent、Details.draw、drawDragOverlay。
        local sent, results, held = {}, {}, {}
        local bridge = { rejectNext = false, throwNext = false, holdAck = false }
        local context = { state = {} }
        context.getProtocol = function() return Protocol end
        context.getClient = function()
            return { sendAction = function(action, params)
                sent[#sent + 1] = { action = action, params = params }
                if bridge.throwNext then
                    bridge.throwNext = false
                    error("专项发送边界异常")
                end
                local handler = Handler.actionHandlers[action]
                check(type(handler) == "function", "动作必须到真实Handler")
                local player = PDM.GetModule(uid, "player")
                local originalLevel = player.level
                if bridge.rejectNext then player.level = 1 end
                local response = handler(uid, params)
                player.level = originalLevel
                bridge.rejectNext = false
                results[#results + 1] = response
                eq(response.action, action, "真实Handler回执保留动作")
                if action == Protocol.ACTION_TYPES.ARTIFACT_EQUIP then
                    if bridge.holdAck then held[#held + 1] = response
                    else Panel.onArtifactEquipResult(response.success, response) end
                end
            end }
        end
        Panel.setContext(context)
        Panel.init(vg)
        Details.setOnClose(function() closeCalls = closeCalls + 1 end)
        cleanups[#cleanups + 1] = function()
            Panel.reset()
            Details.setOnClose(nil)
            Panel.setContext(nil)
            PDM.RemovePlayer(uid, true)
            PDM.Setup({})
            Store.Cleanup()
            Dispatcher.reset()
        end

        local function data() return Store.Get("artifacts") end
        local function artifact(id)
            for _, item in ipairs(data().bag) do
                if tostring(item.id) == tostring(id) then return item end
            end
            error("夹具神器不存在 " .. tostring(id))
        end
        local function equipped(team, slot, sub)
            return Schema.getEquippedId(data(), slot, sub, team)
        end
        local function makeBattleProgress(maxStageId, clearedStages)
            return {
                maxStageId = maxStageId,
                currentStageId = 101,
                clearedStages = clearedStages or {},
                teamStageIds = { ["1"] = 101, ["2"] = 101, ["3"] = 101 },
            }
        end
        local function slotPoint(team, slot, sub)
            -- 行式界面四列从左到右的号位映射为4/3/2/1。
            local columnX = { 924, 700, 476, 252 }
            local rowY = { 465, 807, 1149 }
            return columnX[slot], rowY[team] + (sub == 1 and -85 or 85)
        end
        local function draw()
            clearPaint()
            Panel.drawContent(vg)
            eq(#paint.stack, 0, "真实面板绘图变换最终平衡")
        end
        local function bagPoint(id)
            draw()
            for _, icon in ipairs(paint.icons) do
                if icon.id == tostring(id) and icon.size == 160 and icon.y >= 1446 and icon.y <= 2086 then
                    return icon.x, icon.y
                end
            end
            error("背包可见图标未找到 " .. tostring(id))
        end
        local function detailRect()
            clearPaint()
            Details.draw(vg)
            eq(#paint.panels, 1, "真实详情只绘制一个面板")
            return paint.panels[1]
        end
        local function detailButton(kind)
            local rect = detailRect()
            local actionX = { equip = 133, ["slot-action"] = 265, refine = 397 }
            return rect.x + actionX[kind], rect.y + 797
        end
        local function reset(level, progress, count)
            Panel.reset()
            clock.elapsedTime = clock.elapsedTime + 10
            sent, results, held = {}, {}, {}
            bridge.rejectNext, bridge.throwNext, bridge.holdAck = false, false, false
            pushes, equipCalls, unequipCalls, closeCalls = 0, 0, 0, 0
            context.state = {}
            Dispatcher.clearModuleData()
            Store.ClearCache()
            Dispatcher.set("player", { level = level or 60 })
            Dispatcher.set("battle", progress or makeBattleProgress(2001))
            Dispatcher.set("currency", { privilegePoint = 20, gems = 0, goldenKey = 0 })
            local artifacts = Schema.Fields.artifacts.getDefault()
            for i = 1, count or 12 do
                local typeId = ((i - 1) % 6) + 1
                check(Defs.get(typeId) ~= nil, "夹具类型真实存在")
                artifacts.bag[#artifacts.bag + 1] = { id = tostring(100 + i), artifactId = typeId,
                    quality = 2, valueRatio = 4321 + i }
            end
            artifacts.nextId = 200
            Dispatcher.set("artifacts", artifacts)
            PDM.AttachLocalModules(uid, Dispatcher.getAll(), 1)
            check(Store.Get("artifacts") == Dispatcher.get("artifacts"), "Store监听真实Dispatcher")
            check(PDM.GetModule(uid, "artifacts") == Store.Get("artifacts"), "PDM挂接同一内存镜像")
            eq(PDM.IsLocalMode(uid), true, "夹具保持单机")
            draw()
        end
        local function pointerDrag(sx, sy, tx, ty)
            eq(Panel.handleDragBegin(sx, sy), true, "真实来源按下被接管")
            eq(Panel.hasPointer(), true, "按下持有pointer")
            eq(Panel.isItemDragging(), false, "按下尚未达到拖动阈值")
            eq(Panel.handleDragMove(tx, ty), true, "拖动更新被接管")
            eq(Panel.isItemDragging(), true, "跨阈值成为物品拖动")
            eq(Panel.handleDragEnd(tx, ty), true, "真实拖动松手必须返回dragged=true")
            eq(Panel.hasPointer(), false, "松手清理pointer")
            eq(Panel.isItemDragging(), false, "松手清理物品拖动")
        end
        local function bagDrag(id, team, slot, sub)
            local sx, sy = bagPoint(id)
            local tx, ty = slotPoint(team, slot, sub)
            pointerDrag(sx, sy, tx, ty)
        end
        local function slotDrag(fromTeam, fromSlot, fromSub, toTeam, toSlot, toSub)
            local sx, sy = slotPoint(fromTeam, fromSlot, fromSub)
            local tx, ty = slotPoint(toTeam, toSlot, toSub)
            pointerDrag(sx, sy, tx, ty)
        end
        local function actionCount(action)
            local count = 0
            for _, request in ipairs(sent) do if request.action == action then count = count + 1 end end
            return count
        end
        local function invariantNoConsume(label)
            eq(actionCount(Protocol.ACTION_TYPES.ARTIFACT_REFINE_VALUE), 0, label .. "不洗练")
            eq(actionCount(Protocol.ACTION_TYPES.ARTIFACT_REROLL), 0, label .. "不置换")
            eq(actionCount(Protocol.ACTION_TYPES.ARTIFACT_MERGE), 0, label .. "不合成")
            eq(Store.GetField("currency", "privilegePoint"), 20, label .. "不消耗特权点")
        end
        local function hoverAt(x, y, wait)
            Panel.handleHover(x, y)
            clock.elapsedTime = clock.elapsedTime + (wait or 0.301)
            Panel.handleHover(x, y)
        end
        local function run(name, fn)
            cases = cases + 1
            print(TAG .. " CASE " .. cases .. " " .. name)
            local success, reason = pcall(fn)
            if success then print(TAG .. " PASS " .. name)
            else
                failures = failures + 1
                print(TAG .. " FAIL " .. name .. ": " .. tostring(reason))
                log:Write(LOG_ERROR, TAG .. " " .. name .. ": " .. tostring(reason))
            end
        end

        run("背包拖到三队全部号位和子格", function()
            eq(Schema.TEAM_COUNT, 3, "三队规格")
            eq(Schema.SUB_SLOT_COUNT, 2, "30/60双格规格")
            for team = 1, 3 do
                for slot = 1, 4 do
                    for sub = 1, 2 do
                        reset()
                        bagDrag("112", team, slot, sub)
                        eq(#sent, 1, "安装只发一条动作")
                        eq(sent[1].action, Protocol.ACTION_TYPES.ARTIFACT_EQUIP, "拖放使用装备协议")
                        eq(sent[1].params.artifactId, "112", "协议传实例id")
                        eq(sent[1].params.teamIdx, team, "协议保留队伍")
                        eq(sent[1].params.slot, slot, "协议保留号位")
                        eq(sent[1].params.subSlot, sub, "协议保留子格")
                        eq(results[1].success, true, "真实服务装配成功")
                        eq(equipped(team, slot, sub), "112", "真实Store立即见装配")
                        eq(equipCalls, 1, "Handler调用真实Equip")
                        eq(pushes, 1, "成功装配回推一次")
                        eq(Details.isVisible(), false, "拖动不意外打开详情")
                        invariantNoConsume("三队装配")
                    end
                end
            end
        end)

        run("30和60门槛与锁队边界双层守卫", function()
            for _, gate in ipairs({
                { level = 29, sub = 1, allow = false }, { level = 30, sub = 1, allow = true },
                { level = 59, sub = 2, allow = false }, { level = 60, sub = 2, allow = true },
            }) do
                reset(gate.level)
                bagDrag("112", 1, 1, gate.sub)
                eq(#sent, gate.allow and 1 or 0, "等级边界UI预检")
                eq(equipped(1, 1, gate.sub), gate.allow and "112" or nil, "等级边界不误装")
                local response = Handler.actionHandlers[Protocol.ACTION_TYPES.ARTIFACT_EQUIP](uid,
                    { artifactId = "111", teamIdx = 1, slot = 2, subSlot = gate.sub })
                eq(response.success, gate.allow, "等级边界服务端守卫")
                if not gate.allow then check(response.reason:find(tostring(gate.sub == 1 and 30 or 60), 1, true),
                    "服务端拒绝有准确门槛") end
            end
            for _, gate in ipairs({
                { stage = 905, team = 2, allow = false }, { stage = 1001, team = 2, allow = true },
                { stage = 1905, team = 3, allow = false }, { stage = 2001, team = 3, allow = true },
            }) do
                -- 每章只有五关：使用真实下一章首关验证严格越界，不用不存在的906/1906。
                reset(60, makeBattleProgress(gate.stage))
                bagDrag("112", gate.team, 4, 2)
                eq(#sent, gate.allow and 1 or 0, "抵达关卡不等于通关")
                eq(equipped(gate.team, 4, 2), gate.allow and "112" or nil, "队伍锁定不误装")
                local response = Handler.actionHandlers[Protocol.ACTION_TYPES.ARTIFACT_EQUIP](uid,
                    { artifactId = "111", teamIdx = gate.team, slot = 3, subSlot = 1 })
                eq(response.success, gate.allow, "真实服务同样拒绝锁队")
            end
            reset(60, { maxStageId = 1905, clearedStages = { ["905"] = true, ["1905"] = true } })
            eq(ExpTable.getUnlockedTeamCount(Dispatcher.get("battle")), 3, "字符串通关键解锁三队")
            bagDrag("112", 3, 1, 1)
            eq(results[1].success, true, "真实通关键允许三队")
        end)

        run("同类型不同实例拒绝且目标替换合法", function()
            reset()
            eq(artifact("112").artifactId, artifact("106").artifactId, "同类型不同实例夹具")
            bagDrag("112", 1, 2, 1)
            bagDrag("106", 1, 2, 2)
            eq(#sent, 1, "同号位相同类型UI不发动作")
            eq(equipped(1, 2, 1), "112", "拒绝保留首格")
            eq(equipped(1, 2, 2), nil, "拒绝不写次格")
            check(context.state.floatText:find("相同类型", 1, true), "同类型明确拒绝文案")
            local response = Handler.actionHandlers[Protocol.ACTION_TYPES.ARTIFACT_EQUIP](uid,
                { artifactId = "106", teamIdx = 1, slot = 2, subSlot = 2 })
            eq(response.success, false, "真实Service拒绝同类型")
            bagDrag("106", 1, 2, 1)
            eq(equipped(1, 2, 1), "106", "同类型替换目标本身允许")
            eq(#sent, 2, "替换只增一条装备")
            eq(unequipCalls, 0, "替换不先卸下旧目标")
            bagDrag("111", 1, 2, 2)
            eq(equipped(1, 2, 2), "111", "不同类型可装相邻子格")
            bagDrag("110", 1, 2, 1)
            eq(equipped(1, 2, 1), "110", "不同类型覆盖已占目标")
            eq(equipped(1, 2, 2), "111", "覆盖不影响相邻子格")
            eq(Schema.findEquippedSlotAnyTeam(data(), "106"), nil, "被覆盖实例回背包但不销毁")
            check(artifact("106") ~= nil, "被替换实例仍在总bag")
        end)

        run("同队移位跨队拒绝与精准拖回背包", function()
            reset()
            bagDrag("112", 1, 1, 1)
            slotDrag(1, 1, 1, 1, 1, 2)
            eq(equipped(1, 1, 1), nil, "同队子格移位清原位")
            eq(equipped(1, 1, 2), "112", "同类型同实例移子格不误拒")
            slotDrag(1, 1, 2, 1, 4, 1)
            eq(equipped(1, 1, 2), nil, "同队号位移位清原位")
            for _, target in ipairs({ { team = 2, slot = 3, sub = 2 }, { team = 3, slot = 2, sub = 1 } }) do
                slotDrag(1, 4, 1, target.team, target.slot, target.sub)
                eq(equipped(1, 4, 1), "112", "跨队拒绝保留来源")
                eq(equipped(target.team, target.slot, target.sub), nil, "跨队拒绝不写目标")
                eq(#sent, 3, "跨队复用UI不派安装")
                check(context.state.floatText:find("先卸下", 1, true), "跨队复用明确提示先卸下")
            end
            eq(actionCount(Protocol.ACTION_TYPES.ARTIFACT_UNEQUIP), 0, "跨队拒绝不自动卸来源")
            local sx, sy = slotPoint(1, 4, 1)
            pointerDrag(sx, sy, 30, 1800)
            eq(#sent, 4, "同队移位与卸下动作准确")
            eq(sent[#sent].action, Protocol.ACTION_TYPES.ARTIFACT_UNEQUIP, "拖回背包发卸下")
            eq(sent[#sent].params.teamIdx, 1, "精准卸来源队")
            eq(sent[#sent].params.slot, 4, "精准卸来源号位")
            eq(sent[#sent].params.subSlot, 1, "精准卸来源子格")
            eq(Schema.findEquippedSlotAnyTeam(data(), "112"), nil, "卸下恢复背包")
            eq(unequipCalls, 1, "精准卸下走真实Unequip")
            local bx, by = bagPoint("112")
            check(bx >= 80 and by >= 1446, "卸下后真实图标回背包")
            bagDrag("112", 2, 3, 2)
            eq(equipped(2, 3, 2), "112", "明确卸后可装另一队")
            eq(equipped(1, 4, 1), nil, "迁移后原队保持空")
            invariantNoConsume("移位拒绝与卸下")
        end)

        run("拖动阈值轻抖动格缝外部取消与幂等清理", function()
            reset()
            local x, y = bagPoint("112")
            eq(Panel.handleDragBegin(x, y), true, "轻抖来源按下")
            Panel.handleDragMove(x + 14, y)
            eq(Panel.isItemDragging(), false, "14px不足阈值")
            eq(Panel.handleDragEnd(x + 14, y), false, "轻抖松手dragged=false供宿主点击")
            eq(#sent, 0, "轻抖不发送安装")
            eq(Panel.handleTabInput(x, y), true, "宿主轻抖回落真实点击")
            eq(Details.isPinned(), true, "轻抖点击仅pin")
            eq(Details.getSelection().artifactId, "112", "轻抖选中准确实例")
            Details.closeImmediate()
            eq(Panel.handleDragBegin(x, y), true, "阈值来源按下")
            Panel.handleDragMove(x + 15, y)
            eq(Panel.isItemDragging(), true, "15px恰好跨阈值")
            eq(Panel.handleDragEnd(x + 15, y), true, "已拖动即使落回背包返回true")
            eq(#sent, 0, "背包拖回自身不安装")
            for _, point in ipairs({ { x = 252, y = 465 }, -- 两子格之间10px格缝中心
                { x = 364, y = 380 }, -- 号位之间64px格缝中心
                { x = -1, y = 380 }, { x = 1081, y = 380 },
                { x = 540, y = 100 }, { x = 540, y = 2401 } }) do
                pointerDrag(x, y, point.x, point.y)
                eq(#sent, 0, "格缝/面板外取消不发送")
                eq(Schema.findEquippedSlotAnyTeam(data(), "112"), nil, "无落点保留未装实例")
            end
            eq(Panel.handleDragBegin(x, y), true, "显式取消前按下")
            Panel.handleDragMove(252, 380)
            Panel.cancelPointer()
            Panel.cancelPointer()
            eq(Panel.hasPointer(), false, "显式取消幂等")
            eq(Panel.isItemDragging(), false, "显式取消停止拖图")
            eq(Panel.handleDragEnd(252, 380), false, "取消后延迟松手不安装")
            eq(#sent, 0, "取消后动作仍空")
            invariantNoConsume("阈值与取消")
        end)

        run("拖图实际来源及合法非法目标反馈", function()
            reset(30)
            local x, y = bagPoint("112")
            local tx, ty = slotPoint(1, 4, 1)
            Panel.handleDragBegin(x, y)
            Panel.handleDragMove(tx, ty)
            clearPaint()
            Panel.drawDragOverlay(vg)
            eq(#paint.icons, 1, "拖放末层只画一个来源图标")
            eq(paint.icons[1].id, "112", "拖图使用实例id不是type")
            eq(paint.icons[1].x, tx, "拖图跟随实际X")
            eq(paint.icons[1].y, ty, "拖图跟随实际Y")
            eq(paint.icons[1].selected, true, "拖图带选中反馈")
            eq(#paint.outlines, 2, "目标高亮与来源选框都绘制")
            check(paint.colors[1].g > paint.colors[1].r, "合法目标采用绿色反馈")
            tx, ty = slotPoint(1, 4, 2)
            Panel.handleDragMove(tx, ty)
            clearPaint()
            Panel.drawDragOverlay(vg)
            eq(#paint.icons, 1, "锁格仍绘制拖图")
            eq(paint.outlines[1].y, ty - 80, "非法目标高亮对应次格")
            check(paint.colors[1].r > paint.colors[1].g, "锁定目标采用红色反馈")
            Panel.handleDragEnd(tx, ty)
            eq(#sent, 0, "锁格高亮后不提交")
            clearPaint()
            Panel.drawDragOverlay(vg)
            eq(#paint.icons, 0, "结束后拖图立即消失")
        end)

        run("实例身份而非类型及来源实时变化守卫", function()
            reset()
            eq(artifact("112").artifactId, artifact("106").artifactId, "同type实例对照")
            local x, y = bagPoint("112")
            hoverAt(x, y)
            eq(Details.getSelection().artifactId, "112", "hover首实例id")
            Details.dismissHover()
            x, y = bagPoint("106")
            hoverAt(x, y)
            eq(Details.getSelection().artifactId, "106", "同type另一实例更新选择")
            eq(Details.getSelection().artifact, artifact("106"), "详情引用准确实时实例")
            Details.dismissHover()
            bagDrag("106", 1, 1, 1)
            eq(sent[1].params.artifactId, "106", "装配不会把type当实例id")
            eq(equipped(1, 1, 1), "106", "装的是指定实例")
            eq(Schema.findEquippedSlotAnyTeam(data(), "112"), nil, "同type另一实例保持未装")
            x, y = slotPoint(1, 1, 1)
            Panel.handleDragBegin(x, y)
            Panel.handleDragMove(924, 550)
            local response = Handler.actionHandlers[Protocol.ACTION_TYPES.ARTIFACT_EQUIP](uid,
                { artifactId = "111", teamIdx = 1, slot = 1, subSlot = 1 })
            eq(response.success, true, "手势中真实来源已被覆盖")
            eq(Panel.handleDragEnd(924, 550), true, "过期来源手势被消费")
            eq(#sent, 1, "过期来源不额外发送")
            eq(equipped(1, 1, 1), "111", "过期拖动不卸新来源")
            eq(equipped(1, 4, 2), nil, "过期拖动不装旧实例")
            check(context.state.floatText:find("已变化", 1, true), "过期来源明确重试提示")
        end)

        run("send前登记同步成功可连续安装和失败重试", function()
            reset()
            bagDrag("112", 1, 1, 1)
            bagDrag("111", 1, 1, 2)
            bagDrag("110", 2, 2, 1)
            eq(#sent, 3, "同步回执释放pending连续三次安装")
            eq(equipCalls, 3, "连续安装三次真实Equip")
            eq(equipped(1, 1, 1), "112", "第一装配保留")
            eq(equipped(1, 1, 2), "111", "第二装配保留")
            eq(equipped(2, 2, 1), "110", "第三装配保留")
            bridge.rejectNext = true -- UI预检后让真实服务暂见Lv1，构造同步真实失败。
            bagDrag("109", 3, 3, 1)
            eq(results[#results].success, false, "真实Handler产生同步失败")
            eq(equipped(3, 3, 1), nil, "失败不改目标")
            bagDrag("109", 3, 3, 1)
            eq(#sent, 5, "同步失败后下一次拖放无需reset即可重试")
            eq(results[#results].success, true, "同步失败后重试成功")
            eq(equipped(3, 3, 1), "109", "重试目标真实落地")
            bridge.throwNext = true
            bagDrag("108", 3, 4, 2)
            eq(equipped(3, 4, 2), nil, "发送异常不改目标")
            bagDrag("108", 3, 4, 2)
            eq(#sent, 7, "发送异常释放pending允许重试")
            eq(equipped(3, 4, 2), "108", "异常后真实重试成功")
            invariantNoConsume("同步与失败重试")
        end)

        run("真实动作已发但回执未到避免重入", function()
            reset()
            bridge.holdAck = true
            bagDrag("112", 1, 1, 1)
            eq(#held, 1, "桥仅延迟UI回执不伪造服务结果")
            eq(equipped(1, 1, 1), "112", "服务已装配")
            local x, y = bagPoint("111")
            local tx, ty = slotPoint(1, 1, 2)
            eq(Panel.handleDragBegin(x, y), true, "pending时背包按下仍被接管")
            eq(Panel.isItemDragging(), false, "pending时不能创建第二个物品拖动")
            -- 禁止装配时按下走背包滚动分支；水平试拖避免改变后续查找的滚动位置。
            Panel.handleDragMove(x + 15, y)
            eq(Panel.isItemDragging(), false, "pending时跨阈值仍不能装配")
            Panel.handleDragEnd(tx, ty)
            eq(#sent, 1, "pending阻止第二请求重入")
            Panel.cancelPointer()
            bridge.holdAck = false
            eq(Panel.onArtifactEquipResult(held[1].success, held[1]), true, "当前请求身份匹配释放pending")
            bagDrag("111", 1, 1, 2)
            eq(#sent, 2, "回执到达才开放下一次安装")
            eq(equipped(1, 1, 2), "111", "下一次安装真实成功")
        end)

        run("hover精确延迟静止多tick离开详情内保持", function()
            reset()
            local x, y = bagPoint("112")
            Panel.handleHover(x, y)
            eq(Details.isVisible(), false, "进入格子不立即打开")
            clock.elapsedTime = clock.elapsedTime + 0.299
            Panel.handleHover(x, y)
            eq(Details.isVisible(), false, "0.299秒尚不开")
            clock.elapsedTime = clock.elapsedTime + 0.002
            Panel.handleHover(x, y)
            eq(Details.isVisible(), true, "跨0.3秒静止打开")
            eq(Details.isPinned(), false, "hover详情初始未pin")
            eq(Details.getSelection().hover, true, "hover标志保留")
            eq(Details.getSelection().location, "bag", "hover来源背包")
            local selected = Details.getSelection().artifact
            local rect = detailRect()
            for _ = 1, 12 do
                clock.elapsedTime = clock.elapsedTime + 0.1
                Panel.handleHover(x, y)
                Details.update(0.1)
                eq(Details.isVisible(), true, "静止多tick不闪退")
                eq(Details.getSelection().artifact, selected, "静止多tick实例不变")
                eq(closeCalls, 0, "静止不反复关闭再打开")
            end
            local stable = detailRect()
            eq(stable.x, rect.x, "静止详情X稳定")
            eq(stable.y, rect.y, "静止详情Y稳定")
            Panel.handleHover(rect.x + 260, rect.y + 80)
            clock.elapsedTime = clock.elapsedTime + 1
            Panel.handleHover(rect.x + 260, rect.y + 80)
            eq(Details.isVisible(), true, "从来源移动到详情内部保持")
            eq(Details.getSelection().artifactId, "112", "详情内不换成下方其它格子")
            Panel.handleHover(-10, -10)
            eq(Details.isVisible(), false, "离开格子和详情立即dismissHover")
            eq(Details.getSelection(), nil, "离开选择立即清理")
            eq(closeCalls, 1, "离开只关闭一次")
            invariantNoConsume("hover多tick")
            eq(#sent, 0, "悬停全过程无动作")
        end)

        run("来源间移动延迟重计与pin公开生命周期", function()
            reset()
            local x, y = bagPoint("112")
            Panel.handleHover(x, y)
            clock.elapsedTime = clock.elapsedTime + 0.2
            local bx, by = bagPoint("111")
            Panel.handleHover(bx, by)
            clock.elapsedTime = clock.elapsedTime + 0.2
            Panel.handleHover(bx, by)
            eq(Details.isVisible(), false, "换来源后旧停留时间不继承")
            clock.elapsedTime = clock.elapsedTime + 0.101
            Panel.handleHover(bx, by)
            eq(Details.getSelection().artifactId, "111", "新来源独立到时打开")
            Details.pin()
            eq(Details.isPinned(), true, "公开pin生效")
            eq(Details.getSelection().hover, false, "pin清hover标志")
            Details.dismissHover()
            Panel.handleHover(-10, -10)
            eq(Details.isVisible(), true, "pin后离开不关闭")
            Panel.handleHover(x, y)
            clock.elapsedTime = clock.elapsedTime + 1
            Panel.handleHover(x, y)
            eq(Details.getSelection().artifactId, "111", "pin不被其它来源hover替换")
            Details.closeImmediate()
            Details.closeImmediate()
            eq(Details.isVisible(), false, "closeImmediate幂等清理")
            eq(Details.isPinned(), false, "关闭清pin")
            eq(Details.getSelection(), nil, "关闭清来源")
            eq(closeCalls, 1, "关闭回调至多一次")
            invariantNoConsume("pin生命周期")
        end)

        run("悬停详情内按下松手点击pin不被拖动穿透", function()
            reset()
            local x, y = bagPoint("112")
            hoverAt(x, y)
            local rect = detailRect()
            local px, py = rect.x + 260, rect.y + 80
            eq(Details.containsPoint(px, py), true, "点击点在真实详情本体")
            eq(Panel.handleDragBegin(px, py), false, "详情本体pointer不被背包接管")
            eq(Panel.hasPointer(), false, "详情点击不创建物品或滚动手势")
            eq(Details.isVisible(), true, "详情按下不能先dismissHover")
            eq(Panel.handleDragEnd(px, py), false, "详情轻点击松手允许宿主tap")
            eq(Panel.handleTabInput(px, py), true, "真实详情点击被处理")
            eq(Details.isPinned(), true, "悬停本体真实点击pin")
            eq(Details.getSelection().artifactId, "112", "pin保持准确实例")
            eq(#sent, 0, "本体pin绝不发安装或洗练")
            invariantNoConsume("详情本体点击")
        end)

        run("真实详情按钮精确来源和点击安装失败连续重试", function()
            reset()
            local x, y = bagPoint("112")
            Panel.handleTabInput(x, y)
            eq(Details.isPinned(), true, "背包点击打开pin详情")
            local ex, ey = detailButton("equip")
            eq(Panel.handleTabInput(ex, ey), true, "详情安装按钮真实命中")
            eq(#sent, 0, "按钮先选目标不提前装配")
            eq(Details.isVisible(), false, "选择安装后详情关闭")
            bridge.rejectNext = true
            local tx, ty = slotPoint(1, 3, 1)
            Panel.handleTabInput(tx, ty)
            eq(#sent, 1, "点击目标发真实安装")
            eq(results[1].success, false, "点击安装真实服务同步失败")
            Panel.handleTabInput(tx, ty)
            eq(#sent, 2, "失败仍保留候选再次目标点击可重试")
            eq(results[2].success, true, "点击重试真实成功")
            Panel.handleTabInput(tx, ty)
            eq(Details.getSelection().artifactId, "112", "成功清pending后点击已装打开详情")
            eq(Details.getSelection().location, "slot", "详情装配来源")
            eq(Details.getSelection().teamIdx, 1, "详情装配队伍")
            eq(Details.getSelection().slot, 3, "详情装配号位")
            eq(Details.getSelection().subSlot, 1, "详情装配子格")
            for _, kind in ipairs({ "equip", "refine" }) do
                ex, ey = detailButton(kind)
                eq(Panel.handleTabInput(ex, ey), true, "已装详情旧操作区域点击被消费")
                eq(#sent, 2, "已装详情点击不新增业务动作")
                eq(actionCount(Protocol.ACTION_TYPES.ARTIFACT_UNEQUIP), 0, "已装详情不派取下动作")
                eq(equipped(1, 3, 1), "112", "只读详情保留原装配")
                eq(Details.isPinned(), true, "只读点击保持详情pin")
                eq(Details.getSelection().slot, 3, "只读详情保留准确号位")
            end
            invariantNoConsume("点击安装重试与已装详情只读")
        end)

        run("拖动经过洗练安装按钮及原格不执行点击", function()
            reset()
            local x, y = bagPoint("112")
            hoverAt(x, y)
            local ex, ey = detailButton("equip")
            local rx, ry = detailButton("refine")
            eq(Panel.handleDragBegin(x, y), true, "悬停来源原格仍可拖动")
            eq(Details.isVisible(), false, "来源开始拖动关闭详情")
            Panel.handleDragMove(rx, ry)
            Panel.handleHover(rx, ry)
            eq(Details.isVisible(), false, "拖动途经按钮不重开hover")
            eq(Panel.handleDragEnd(rx, ry), true, "按钮落点仍消费拖动，不派tap")
            eq(#sent, 0, "洗练按钮落点无任何动作")
            hoverAt(x, y)
            eq(Details.isVisible(), true, "下一次hover能重新打开")
            Panel.handleDragBegin(x, y)
            Panel.handleDragMove(ex, ey)
            eq(Panel.handleDragEnd(ex, ey), true, "安装按钮落点不派tap")
            eq(#sent, 0, "安装按钮落点不登记待装或直接安装")
            local tx, ty = slotPoint(1, 1, 1)
            Panel.handleTabInput(tx, ty)
            eq(#sent, 0, "按钮拖放后目标点击没有隐含pending")
            invariantNoConsume("拖拽按钮边界")
        end)

        run("滚动后公共绘图hover点击peek命中同一实例", function()
            reset(60, nil, 40)
            local x, y = bagPoint("140")
            hoverAt(x, y)
            eq(Details.getSelection().artifactId, "140", "滚动前首实例")
            Details.dismissHover()
            -- 190px=一行，真实滚轮步长60；不直接设置私有scrollY。
            Panel.handleScroll(-190 / 60, 30, 1800)
            draw()
            local expected = artifact("135")
            local hitId
            for _, icon in ipairs(paint.icons) do
                if icon.size == 160 and icon.x == x and icon.y == y then hitId = icon.id end
            end
            eq(hitId, "135", "真实绘图一行滚动后同坐标变为第6实例")
            hoverAt(x, y)
            eq(Details.getSelection().artifactId, hitId, "hover peek与真实绘制命中一致")
            eq(Details.getSelection().artifact, expected, "hover peek不按类型复用旧实例")
            Details.dismissHover()
            eq(Panel.handleTabInput(x, y), true, "滚动后真实点击被处理")
            eq(Details.getSelection().artifactId, hitId, "点击peek与hover绘图同实例")
            Details.closeImmediate()
            local tx, ty = slotPoint(1, 1, 1)
            pointerDrag(x, y, tx, ty)
            eq(sent[1].params.artifactId, hitId, "滚动后拖放仍使用同实例")
            eq(equipped(1, 1, 1), hitId, "滚动实例真实装配")
            invariantNoConsume("滚动一致性")
        end)

        run("背包空隙滚动不被识别物品及clip外不peek", function()
            reset(60, nil, 40)
            eq(Panel.handleDragBegin(255, 1700), true, "背包列间缝接管滚动")
            eq(Panel.hasPointer(), true, "滚动手势持有pointer")
            eq(Panel.isItemDragging(), false, "列缝无物品来源")
            Panel.handleDragMove(255, 1510)
            eq(Panel.isItemDragging(), false, "列缝移动仍是滚动")
            eq(Panel.handleDragEnd(255, 1510), false, "滚动不是item dragged")
            eq(#sent, 0, "滚动绝不安装")
            Panel.cancelPointer()
            draw()
            hoverAt(160, 1445)
            eq(Details.isVisible(), false, "clip顶外即便图标露出也不peek")
            hoverAt(160, 2111)
            eq(Details.isVisible(), false, "clip底外不peek")
            eq(Panel.handleDragBegin(160, 1445), false, "clip顶外不开始物品拖动")
            eq(Panel.hasPointer(), false, "clip外不持有pointer")
            invariantNoConsume("空隙滚动与clip")
        end)

        run("详情第六参兼容位置精度刷新与旧模态关闭", function()
            reset()
            local a = artifact("112")
            Details.show(a, "slot", 4, 2, 3, { hover = true, anchor = { x = 844, y = 1154, w = 160, h = 160 } })
            local selected = Details.getSelection()
            eq(selected.artifactId, "112", "第六参不污染实例id")
            eq(selected.teamIdx, 3, "第六参保留第5参team")
            eq(selected.slot, 4, "第六参保留slot")
            eq(selected.subSlot, 2, "第六参保留subSlot")
            eq(selected.hover, true, "第六参hover正确")
            local rect = detailRect()
            check(rect.x >= 16 and rect.x + rect.w <= 1064, "靠右锚点夹紧横向边界")
            check(rect.y >= 16 and rect.y + rect.h <= 2384, "锚点详情夹紧纵向边界")
            eq(Details.containsPoint(rect.x + 10, rect.y + 10), true, "绘制与命中相同平移")
            eq(Details.containsPoint(rect.x - 1, rect.y + 10), false, "平移边界外不误命中")
            Details.pin()
            Details.show(a, "slot", 4, 2, 3, { hover = true, anchor = { x = 0, y = 0, w = 160, h = 160 } })
            eq(Details.isPinned(), true, "同实例重复hover不得解pin")
            local pinnedRect = detailRect()
            eq(pinnedRect.x, rect.x, "同实例hover不移动pin详情X")
            eq(pinnedRect.y, rect.y, "同实例hover不移动pin详情Y")
            Details.closeImmediate()
            Details.show(a, "bag") -- 旧调用保留居中模态及开合动画。
            clock.elapsedTime = clock.elapsedTime + 1
            Details.update(1)
            eq(Details.isPinned(), true, "旧show默认pin")
            eq(Details.handleTap(-1, -1), true, "旧模态外点击消费不穿透")
            clock.elapsedTime = clock.elapsedTime + 1
            Details.update(1)
            eq(Details.isVisible(), false, "旧模态关闭动画完成")
            eq(Details.getSelection(), nil, "旧模态动画结束清选择")
            invariantNoConsume("详情兼容")
        end)

        run("悬停跨格缝桥接150ms及跨栏即时清理", function()
            reset()
            local x, y = bagPoint("112")
            hoverAt(x, y)
            local rect = detailRect()
            local gapX, gapY = 246, y -- 原格右边240与详情左边252之间12px空隙。
            eq(Details.containsPoint(gapX, gapY), false, "桥接点确实在详情外")
            Panel.handleHover(gapX, gapY)
            eq(Details.isVisible(), true, "进入格缝保留悬停详情")
            clock.elapsedTime = clock.elapsedTime + 0.149
            Panel.handleHover(gapX, gapY)
            eq(Details.isVisible(), true, "149ms宽限内详情保持")
            Panel.handleHover(rect.x + 10, rect.y + 80)
            clock.elapsedTime = clock.elapsedTime + 1
            Panel.handleHover(rect.x + 10, rect.y + 80)
            eq(Details.getSelection().artifactId, "112", "穿越格缝进入详情保留实例")
            eq(closeCalls, 0, "桥接成功不闪关再开")
            Panel.handleHover(-1, -1)
            eq(Details.isVisible(), false, "跨栏离开不适用桥接宽限")
            hoverAt(x, y)
            Panel.handleHover(gapX, gapY)
            clock.elapsedTime = clock.elapsedTime + 0.151
            Panel.handleHover(gapX, gapY)
            eq(Details.isVisible(), false, "格缝停留超过150ms真正离开")
            eq(closeCalls, 2, "两次真正离开各关闭一次")
            invariantNoConsume("悬停格缝桥接")
            eq(#sent, 0, "桥接完全不发业务动作")
        end)

        run("背包来源中途已装配及已装槽位外部落点保护", function()
            reset()
            local x, y = bagPoint("112")
            Panel.handleDragBegin(x, y)
            Panel.handleDragMove(924, 550)
            local response = Handler.actionHandlers[Protocol.ACTION_TYPES.ARTIFACT_EQUIP](uid,
                { artifactId = "112", teamIdx = 2, slot = 2, subSlot = 2 })
            eq(response.success, true, "真实动作在手势中已安装背包来源")
            eq(Panel.handleDragEnd(924, 550), true, "过期背包手势仍被消费")
            eq(#sent, 0, "背包已不再可见时不盲装到新队")
            eq(equipped(2, 2, 2), "112", "中途装配来源不被误卸")
            eq(equipped(1, 4, 2), nil, "中途装配后过期目标不写入")
            local sx, sy = slotPoint(2, 2, 2)
            for _, point in ipairs({ { x = -1, y = 1800 }, { x = 1081, y = 1800 },
                { x = 30, y = 1445 }, { x = 30, y = 2111 }, { x = 252, y = 465 } }) do
                pointerDrag(sx, sy, point.x, point.y)
                eq(equipped(2, 2, 2), "112", "槽位拖到clip外/格缝不卸来源")
                eq(#sent, 0, "无效卸下区域不派业务动作")
            end
            invariantNoConsume("过期背包来源与外部卸下保护")
        end)

        check(cases >= 19, "防空通过：至少19组场景必须执行")
        check(assertions >= 600, "防空通过：至少600次断言必须执行")
        eq(failures, 0, "所有专项场景必须通过")
    end)
    for i = #cleanups, 1, -1 do
        local cleaned, reason = pcall(cleanups[i])
        if not cleaned then print(TAG .. " CLEANUP FAIL: " .. tostring(reason)) end
    end
    for i = #restores, 1, -1 do restores[i]() end
    if not ok then
        print(TAG .. " FAIL: " .. tostring(err) .. " (" .. assertions .. " assertions, " .. cases .. " cases)")
        log:Write(LOG_ERROR, TAG .. " FAIL: " .. tostring(err))
    else
        print(TAG .. " ALL PASS: " .. assertions .. " assertions, " .. cases .. " cases")
    end
    -- 退出置于pcall之外，测试异常也不会挂住Runtime。
    engine:Exit()
end
