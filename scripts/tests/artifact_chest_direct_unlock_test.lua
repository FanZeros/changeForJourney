-- 神器宝箱直接开放回归：真实抽取服务/Handler/面板，内存夹具不读写玩家存档。
local assertions = 0
local function eq(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end

function Start()
    local restores = {}
    local function replace(owner, key, value)
        local old = owner[key]
        restores[#restores + 1] = function() owner[key] = old end
        owner[key] = value
    end
    local ok, err = pcall(function()
        local PDM = require("rules.character.PlayerDataManager")
        local Schema = require("shared.artifact.ArtifactSchema")
        local Defs = require("shared.artifact.ArtifactDefs")
        local Service = require("rules.artifact.ArtifactService")
        local Handler = require("rules.artifact.ArtifactHandler")
        local Protocol = require("shared.Protocol")
        local TaskService = require("rules.task.TaskService")
        local PlayerStore = require("core.PlayerStore")
        local GameState = require("core.GameState")
        local DrawUtil = require("core.DrawUtil")
        local BF = require("systems.ButtonFeedback")
        local uid, now = 987654, 1791021600
        local today = math.floor((now + 28800) / 86400)
        ---@type table
        local modules = {}
        local dirty, taskDraws, flushes = 0, 0, 0
        replace(os, "time", function() return now end)
        replace(PDM, "GetModule", function(_, name) return modules[name] end)
        replace(PDM, "MarkDirty", function() dirty = dirty + 1 end)
        replace(PDM, "FlushImmediate", function() flushes = flushes + 1 end)
        replace(TaskService, "UpdateProgress", function(_, event, count)
            eq(event, "artifact_draw", "抽取任务事件不变")
            taskDraws = taskDraws + count
        end)
        replace(PlayerStore, "Get", function(name) return modules[name] end)
        replace(GameState, "getGoldenKey", function() return modules.currency.goldenKey end)
        replace(GameState, "getGems", function() return modules.currency.gems end)
        local function reset(battle, keys, gems, size)
            modules = {
                battle = battle,
                player = { level = 1 },
                currency = { goldenKey = keys or 0, gems = gems or 0 },
                artifacts = Schema.Fields.artifacts.getDefault(),
            }
            for i = 1, size or 0 do
                modules.artifacts.bag[i] = { id = tostring(i), artifactId = 1, quality = 1, valueRatio = 5000 }
            end
            modules.artifacts.nextId = (size or 0) + 1
            dirty, taskDraws, flushes = 0, 0, 0
        end
        local function reject(count, payment, message)
            local data = modules.artifacts
            local bagSize, total, freeDay = #data.bag, data.totalDraws, data.dailyFreeDrawDayId
            local keys, gems = modules.currency.goldenKey, modules.currency.gems
            local d, tasks, f = dirty, taskDraws, flushes
            local success, reason = Service.Draw(uid, count, payment)
            eq(success, false, message .. "拒绝")
            eq(#data.bag, bagSize, message .. "不发神器")
            eq(data.totalDraws, total, message .. "不推进抽数")
            eq(data.dailyFreeDrawDayId, freeDay, message .. "不消耗免费次数")
            eq(modules.currency.goldenKey, keys, message .. "不扣钥匙")
            eq(modules.currency.gems, gems, message .. "不扣黑晶")
            eq(dirty, d, message .. "不标脏")
            eq(taskDraws, tasks, message .. "不推进任务")
            eq(flushes, f, message .. "不请求落盘")
            assert(reason and #reason > 0, message .. "必须有拒绝原因")
        end

        -- nil/普通/噩梦边界/旧档字符串键均不再构成宝箱解锁条件。
        local progressCases = {
            { label = "无战斗模块" },
            { label = "空进度", battle = {} },
            { label = "普通新档", battle = { currentStageId = 101, maxStageId = 101 } },
            { label = "噩梦之前", battle = { currentStageId = 4699, maxStageId = 4699 } },
            { label = "抵达噩梦", battle = { currentStageId = 4701, maxStageId = 4701 } },
            { label = "旧档字符串进度", battle = { currentStageId = "101", maxStageId = "101" } },
        }
        for _, case in ipairs(progressCases) do
            reset(case.battle)
            local response = Handler.actionHandlers[Protocol.ACTION_TYPES.ARTIFACT_DRAW](uid,
                { count = 1, payType = "free_daily" })
            eq(response.success, true, case.label .. "可直接抽取")
            eq(response.action, Protocol.ACTION_TYPES.ARTIFACT_DRAW, "Handler回包动作不变")
            eq(#modules.artifacts.bag, 1, case.label .. "获得一件神器")
            eq(modules.artifacts.totalDraws, 1, case.label .. "抽数正确")
            eq(modules.artifacts.dailyFreeDrawDayId, today, case.label .. "记录今日免费")
            eq(modules.currency.gems, 0, case.label .. "免费不扣黑晶")
            eq(modules.currency.goldenKey, 0, case.label .. "免费不扣钥匙")
            eq(taskDraws, 1, case.label .. "只推进一次任务")
            reject(1, "free_daily", case.label .. "当天重复免费")
            now = now + 86400
            eq(Service.Draw(uid, 1, "free_daily"), true, case.label .. "次日恢复免费")
            now = now - 86400
        end
        reset({ maxStageId = 101 })
        reject(10, "free_daily", "免费十连")
        reject(1, "key", "钥匙不足")
        reject(1, "diamond", "黑晶不足")
        reject(2, "key", "非法抽数")
        reset({}, 10, 100)
        local success, _, result = Service.Draw(uid, 10, "key")
        assert(success and result, "抽取成功必须返回奖励")
        eq(success, true, "低进度钥匙十连成功")
        eq(result.keysUsed, 10, "十连消耗十把钥匙")
        eq(modules.currency.goldenKey, 0, "十连钥匙余额正确")
        eq(modules.currency.gems, 100, "钥匙十连不扣黑晶")
        eq(#modules.artifacts.bag, 10, "十连获得十件")
        eq(modules.artifacts.drawStats.ten, 1, "十连统计正确")
        eq(taskDraws, 10, "十连任务计数正确")
        reset({}, 3, 4200)
        success, _, result = Service.Draw(uid, 10, "diamond")
        assert(success and result, "抽取成功必须返回奖励")
        eq(success, true, "低进度混合支付成功")
        eq(result.keysUsed, 3, "优先使用已有钥匙")
        eq(result.diamondCost, 7 * Defs.KEY_DIAMOND_PRICE, "只补购缺少的七把")
        eq(modules.currency.gems, 0, "补购黑晶余额正确")
        eq(modules.currency.goldenKey, 0, "补购钥匙余额正确")
        reset({}, 3, 4199)
        reject(10, "diamond", "补购差一黑晶")

        for _, boundary in ipairs({
            { size = 299, count = 1, allowed = true },
            { size = 300, count = 1, allowed = false },
            { size = 290, count = 10, allowed = true },
            { size = 291, count = 10, allowed = false },
        }) do
            reset({}, 10, 6000, boundary.size)
            if boundary.allowed then
                eq(Service.Draw(uid, boundary.count, "key"), true, "容量边界可抽 " .. boundary.size)
                eq(#modules.artifacts.bag, 300, "恰好装满300件")
            else
                reject(boundary.count, "key", "容量超限 " .. boundary.size)
            end
        end
        reset({}, 0, 0, 300)
        reject(1, "free_daily", "满包免费单抽")
        reset({}, 1)
        modules.artifacts.pityRare = Defs.PITY_RARE - 1
        success, _, result = Service.Draw(uid, 1, "key")
        assert(success and result, "抽取成功必须返回奖励")
        eq(success, true, "直接开放后稀有保底可抽")
        eq(result.artifacts[1].quality, 3, "稀有保底仍生效")
        reset({}, 1)
        modules.artifacts.pityEpic = Defs.PITY_EPIC - 1
        success, _, result = Service.Draw(uid, 1, "key")
        assert(success and result, "抽取成功必须返回奖励")
        eq(success, true, "直接开放后史诗保底可抽")
        eq(result.artifacts[1].quality, 4, "史诗保底仍生效")

        -- 压缩旧档往返不添加解锁字段，不重置已用免费次数、实例和装配。
        local saved = {
            av = 1, b = { { 7, 1, 2, 5678 } }, et = { ["1"] = { ["1"] = { ["1"] = 7 } } },
            n = 8, r = 11, p = 51, t = 71,
            s = { total = 71, single = 1, ten = 7, byQuality = { ["2"] = 71 }, byArtifactId = { ["1"] = 71 } },
            df = today,
        }
        Schema.normalizeModule(saved)
        local lean = Schema.dehydrateModule(saved)
        local restored = cjson.decode(cjson.encode(lean))
        Schema.normalizeModule(restored)
        eq(restored.bag[1].id, "7", "旧档实例ID保留")
        eq(restored.bag[1].valueRatio, 5678, "旧档数值保留")
        eq(Schema.getEquippedId(restored, 1, 1, 1), "7", "旧档装配保留")
        eq(restored.pityRare, 11, "旧档稀有保底保留")
        eq(restored.pityEpic, 51, "旧档史诗保底保留")
        eq(restored.totalDraws, 71, "旧档总抽数保留")
        eq(restored.drawStats.ten, 7, "旧档十连统计保留")
        eq(restored.dailyFreeDrawDayId, today, "旧档免费日标记保留")
        reset({ maxStageId = 101 }, 1)
        modules.artifacts = restored
        reject(1, "free_daily", "旧档已用免费")
        eq(Service.Draw(uid, 1, "key"), true, "旧低进度档无需迁移即可付费抽取")
        eq(modules.battle.maxStageId, 101, "不伪造噩梦进度")
        eq(Service.Equip(uid, "7", 1, 1, 1), false, "Lv1仍不能装配神器")
        modules.player.level = 30
        eq(Service.Equip(uid, "7", 1, 1, 1), true, "Lv30首格装配不变")
        eq(Service.Equip(uid, "7", 1, 2, 1), false, "Lv30次格仍锁")
        modules.player.level = 60
        eq(Service.Equip(uid, "7", 1, 2, 1), true, "Lv60次格装配不变")
        eq(Service.Equip(uid, "7", 1, 1, 2), false, "低进度队2仍锁")

        -- 真实面板的绘制/点击函数；仅替换绘图底层，非完整实机视觉验收。
        local texts, buttons, actions = {}, {}, {}
        local function noop() end
        replace(DrawUtil, "drawTextStroke", function(_, _, _, text) texts[#texts + 1] = text end)
        replace(DrawUtil, "drawImageCentered", noop)
        replace(BF, "begin", function(_, id) buttons[id] = true return {} end)
        replace(BF, "finish", noop)
        replace(BF, "trigger", noop)
        for _, name in ipairs({ "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgFillColor",
            "nvgBeginPath", "nvgRoundedRect", "nvgFill" }) do replace(_G, name, noop) end
        replace(_G, "nvgText", function(_, _, _, text) texts[#texts + 1] = text end)
        replace(_G, "nvgTextBounds", function(_, _, _, text) return #text * 10 end)
        replace(_G, "nvgRGBA", function() return {} end)
        replace(_G, "time", { elapsedTime = 100 })
        local Panel = require("ui.church.ChurchArtifactDrawPanel")
        Panel.setContext({
            state = {}, getProtocol = function() return Protocol end,
            getClient = function() return { sendAction = function(action, params)
                actions[#actions + 1] = { action = action, params = params }
            end } end,
        })
        for _, case in ipairs(progressCases) do
            reset(case.battle)
            Panel.reset()
            eq(Panel.isArtifactChestUnlocked(), true, case.label .. "面板查询直接开放")
            texts, buttons, actions = {}, {}, {}
            Panel.drawContent({})
            eq(buttons.church_artifact_draw_1, true, case.label .. "绘制单抽按钮")
            eq(buttons.church_artifact_draw_10, true, case.label .. "绘制十连按钮")
            for _, text in ipairs(texts) do
                eq(text:find("噩梦", 1, true), nil, "面板没有噩梦锁文案")
            end
            eq(Panel.handleTabInput(323, 1381), true, case.label .. "单抽点击被处理")
            eq(#actions, 1, case.label .. "单抽动作发出")
            eq(actions[1].params.payType, "free_daily", "未用每日免费优先")
            eq(actions[1].action, Protocol.ACTION_TYPES.ARTIFACT_DRAW, "面板抽取协议不变")
            eq(actions[1].params.count, 1, "面板单抽次数正确")
        end
        reset({}, 10)
        modules.artifacts.dailyFreeDrawDayId = today
        actions = {}
        Panel.reset()
        Panel.handleTabInput(783, 1381)
        eq(#actions, 1, "低进度十连动作发出")
        eq(actions[1].params.count, 10, "十连次数正确")
        eq(actions[1].params.payType, "diamond", "十连保持原支付方式")
        reset({}, 0, 6000)
        actions = {}
        Panel.reset()
        Panel.handleTabInput(783, 1381)
        eq(Panel.isKeyConfirmVisible(), true, "钥匙不足仍弹补购确认")
        eq(#actions, 0, "未确认不抽取")
        time.elapsedTime = 101
        Panel.handleTabInput(0, 0)
        time.elapsedTime = 102
        Panel.drawKeyConfirmDialog({})
        eq(Panel.isKeyConfirmVisible(), false, "点击框外可取消补购")
        eq(#actions, 0, "取消补购不发送抽取")
        Panel.reset()
        Panel.handleTabInput(783, 1381)
        time.elapsedTime = 103
        Panel.handleTabInput(540, 1301)
        eq(#actions, 1, "确认补购后才发送抽取")
        eq(actions[1].params.count, 10, "补购保持十连次数")
        Panel.reset()
        Panel.setContext(nil)
    end)
    for i = #restores, 1, -1 do restores[i]() end
    if not ok then
        log:Write(LOG_ERROR, "[artifact_chest_direct_unlock_test] " .. tostring(err))
    else
        print("[artifact_chest_direct_unlock_test] ALL PASS: " .. assertions .. " assertions")
    end
    engine:Exit()
end
