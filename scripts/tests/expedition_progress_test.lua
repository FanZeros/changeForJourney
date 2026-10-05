-- 远征展示模型回归：真实配置与规则，断言不改玩家档、不改变任何原奖励。
function Start()
    local assertions, cases = 0, 0
    local function check(value, label)
        assertions = assertions + 1
        assert(value, label)
    end
    local function runCase(label, fn)
        fn()
        cases = cases + 1
        print("[expedition_progress_test] PASS " .. label)
    end
    local function copy(value)
        if type(value) ~= "table" then return value end
        local out = {}
        for key, item in pairs(value) do out[key] = copy(item) end
        return out
    end
    local function same(actual, expected, label)
        if type(expected) ~= "table" then check(actual == expected, label); return end
        check(type(actual) == "table", label .. " table")
        for key, item in pairs(expected) do same(actual[key], item, label .. "." .. tostring(key)) end
        for key in pairs(actual) do check(expected[key] ~= nil, label .. " unexpected " .. tostring(key)) end
    end
    local ok, err = pcall(function()
        local Progress = require("config.ExpeditionProgress")
        local Config = require("config.TaskConfig")
        local Exp = require("config.ExpTable")
        local levels = {5, 10, 20, 30, 50, 80, 100, 150, 200}
        local kinds = {"essence", "adventure_ticket", "enhance_star", "arcane_dust", "sweep_ticket",
            "stellar_ticket", "diamond", "gold", "essence"}
        local amounts = {150, 2, 2, 600, 1, 1, 840, 120000, 6000}
        local configBefore = copy(Config.ACHIEVEMENT)
        local levelTasksBefore = copy(Config.LEVEL_TASKS)
        local originalByLevel = {}
        for i, lv in ipairs(levels) do originalByLevel[lv] = { type = kinds[i], amount = amounts[i] } end
        local function bonusId(lv) return "a_plv_bonus_v1_" .. lv end
        runCase("九个原礼包及200个独立bonus配置", function()
            check(Exp.PLAYER_MAX_LEVEL == 200, "最高等级200")
            check(#Config.LEVEL_TASKS == 200, "LEVEL_TASKS按级数组")
            local originalCount, bonusCount, totalBonus = 0, 0, 0
            local seen = {}
            for _, def in ipairs(Config.ACHIEVEMENT) do
                check(not seen[def.id], "ID唯一 " .. def.id)
                seen[def.id] = true
                if def.group == "level" then
                    check(def.condKey == "player_level", "等级奖励条件同源")
                    if def.id:match("^a_plv_%d+$") then originalCount = originalCount + 1
                    else
                        check(def.id == bonusId(def.target), "新增ID版本稳定")
                        check(def.reward.type == "diamond" and def.reward.amount == 100, "每级新增100黑晶")
                        bonusCount, totalBonus = bonusCount + 1, totalBonus + def.reward.amount
                    end
                end
            end
            check(originalCount == 9 and bonusCount == 200 and totalBonus == 20000, "原9项外加20000黑晶")
            for lv = 1, 200 do
                local defs = Config.LEVEL_TASKS[lv]
                local original = originalByLevel[lv]
                check(#defs == (original and 2 or 1), "每级所有任务 " .. lv)
                check(defs[#defs] == Config.findById(bonusId(lv)), "bonus同源且最后 " .. lv)
                for _, def in ipairs(defs) do
                    check(def.target == lv and def.group == "level", "按级索引无串级 " .. lv)
                    check(Config.findById(def.id) == def, "配置索引同表 " .. def.id)
                end
                if original then
                    local def = Config.findById("a_plv_" .. lv)
                    check(defs[1] == def, "原礼包第一项 " .. lv)
                    check(def.reward.type == original.type and def.reward.amount == original.amount,
                        "保留原奖励 " .. lv)
                end
            end
            local heroRewards = {
                a_hero_4 = {type="adventure_ticket", amount=3}, a_hero_6 = {type="enhance_star", amount=2},
                a_hero_10 = {type="arcane_dust", amount=400}, a_hero_16 = {type="sweep_ticket", amount=1},
                a_hero_20 = {type="stellar_ticket", amount=1}, a_adv1_1 = {type="diamond", amount=64},
                a_adv1_3 = {type="gold", amount=7200}, a_adv1_5 = {type="essence", amount=450},
                a_adv1_8 = {type="adventure_ticket", amount=1}, a_adv2_1 = {type="enhance_star", amount=4},
                a_adv2_2 = {type="arcane_dust", amount=240}, a_adv2_3 = {type="sweep_ticket", amount=1},
                a_adv2_5 = {type="stellar_ticket", amount=1}, a_awk_1 = {type="diamond", amount=72},
                a_awk_2 = {type="gold", amount=6400}, a_awk_3 = {type="essence", amount=360},
            }
            local heroCount = 0
            for _, def in ipairs(Config.ACHIEVEMENT) do
                if def.group == "hero" then
                    heroCount = heroCount + 1
                    local reward = heroRewards[def.id]
                    check(reward and def.reward.type == reward.type and def.reward.amount == reward.amount,
                        "新增奖励不推进hero轮换 " .. def.id)
                end
            end
            check(heroCount == 16, "全部16项hero奖励保留")
        end)
        runCase("Lv1/33/100/200逐级展示及状态无写入", function()
            for _, lv in ipairs({1, 33, 100, 200}) do
                local player = { level = lv, exp = 25, avatarHeroId = 25 }
                local task = { achClaimed = { a_retired_task = true }, achProg = { player_level = 1 } }
                local battle = { maxStageId = 905 }
                local before = copy({player=player, task=task, battle=battle})
                local model = Progress.build(player, task, battle)
                check(#model.rows == 200 and model.level == lv, "每级一个row " .. lv)
                check(model.claimableCount == lv, "可领等级数而非任务数 " .. lv)
                check(model.focusIndex == lv and model.nextLevel == (lv < 200 and lv + 1 or nil),
                    "焦点当前级下一节点连续 " .. lv)
                local currentCount, rewardCount = 0, 0
                for target, row in ipairs(model.rows) do
                    check(row.level == target and row.taskId == bonusId(target), "稳定bonus行ID " .. target)
                    check(row.current == (target == lv), "仅当前等级高亮 " .. target)
                    if row.current then currentCount = currentCount + 1 end
                    local defs = Config.LEVEL_TASKS[target]
                    check(#row.tasks == #defs and #row.rewards == #defs, "完整展示同级全部奖励 " .. target)
                    check(row.reward == Config.findById(bonusId(target)).reward, "主奖励为bonus100 " .. target)
                    check(row.status == (target <= lv and Config.STATUS.CLAIMABLE or Config.STATUS.LOCKED),
                        "行等级状态 " .. target)
                    for index, item in ipairs(row.tasks) do
                        local def = defs[index]
                        check(item.taskId == def.id and item.reward == def.reward, "taskId/reward同源 " .. def.id)
                        check(row.rewards[index] == def.reward, "rewards全部同源 " .. def.id)
                        check(item.status == row.status, "每项task状态 " .. def.id)
                        rewardCount = rewardCount + 1
                    end
                end
                check(currentCount == 1 and rewardCount == 209, "无丢项无额外节点")
                if lv == 200 then check(model.maxExp == 0 and model.exp == 0 and model.ratio == 1, "满级进度")
                else
                    check(model.maxExp == Exp.getPlayerExpForLevel(lv) and model.exp == 25,
                        "经验同源 " .. lv)
                end
                same({player=player, task=task, battle=battle}, before, "展示无写入 " .. lv)
            end
        end)
        local task = { achClaimed = { a_plv_10 = true }, achProg = { player_level = 1 } }
        local model = Progress.build({level = 30, exp = 25}, task, {maxStageId = 905})
        runCase("旧礼包/bonus反向部分已领与全领行聚合", function()
            check(model.claimableCount == 30, "旧礼包已领但bonus仍可领取该级")
            check(model.nextLevel == 31 and model.focusIndex == 30, "未领历史不抢当前焦点")
            check(model.rows[10].tasks[1].status == Config.STATUS.CLAIMED, "旧a_plv已领保留")
            check(model.rows[10].tasks[2].status == Config.STATUS.CLAIMABLE, "旧已领仍可领bonus")
            check(model.rows[10].status == Config.STATUS.CLAIMABLE, "部分已领仍可领行")
            check(model.rows[31].status == Config.STATUS.LOCKED, "未达成不可领")
            check(task.achProg.player_level == 1 and task.achClaimed.a_plv_10 == true, "不读取陈旧进度/不写档")
            local claimed = { [bonusId(10)] = true, [bonusId(33)] = true, a_retired_task = true }
            local reverse = Progress.build({level=33}, {achClaimed=claimed}, {})
            check(reverse.rows[10].tasks[1].status == Config.STATUS.CLAIMABLE, "bonus先领仍可原礼包")
            check(reverse.rows[10].tasks[2].status == Config.STATUS.CLAIMED, "bonus已领保留")
            check(reverse.rows[10].status == Config.STATUS.CLAIMABLE, "反向部分已领行可领")
            check(reverse.rows[33].status == Config.STATUS.CLAIMED and reverse.claimableCount == 32,
                "普通级bonus已领计为一个全领等级")
            claimed.a_plv_10 = true
            local both = Progress.build({level=33}, {achClaimed=claimed}, {})
            check(both.rows[10].status == Config.STATUS.CLAIMED and both.claimableCount == 31,
                "原礼包与bonus全领才减等级数")
            local originalsClaimed = {}
            for _, lv in ipairs(levels) do originalsClaimed["a_plv_" .. lv] = true end
            local legacy = Progress.build({level=200}, {achClaimed=originalsClaimed}, {})
            check(legacy.claimableCount == 200, "原9项全领不吞200个bonus")
            for lv = 1, 200 do originalsClaimed[bonusId(lv)] = true end
            local done = Progress.build({level=200}, {achClaimed=originalsClaimed}, {})
            check(done.claimableCount == 0 and done.focusIndex == 200 and done.nextLevel == nil,
                "全部209项已领仍定位当前末端")
            for _, row in ipairs(done.rows) do check(row.status == Config.STATUS.CLAIMED, "全领行 " .. row.level) end
            local before = Progress.build({level=4}, {}, {})
            check(before.nextLevel == 5 and before.focusIndex == 4 and before.claimableCount == 4,
                "新档连续节点含Lv1可补领")
        end)
        check(model.stageUnlocks[1].unlocked == false, "等级高/刚到9-5不假开放小队")
        local completed = Progress.build({level=200}, {}, {clearedStages = {["905"] = true}})
        check(completed.stageUnlocks[1].unlocked == true and completed.stageUnlocks[2].unlocked == false,
            "通关条件单列")
        check(completed.maxExp == 0 and completed.exp == 0 and completed.ratio == 1, "满级进度")
        for _, lv in ipairs({2,6,10,30,60,200}) do
            local unlocks = Progress.getLevelUnlocks(lv)
            local slots, artifacts = 0, 0
            for _, entry in ipairs(unlocks) do
                check(entry.kind == "level" and entry.level == lv, "结构化等级条件")
                if entry.id == "team_slots" then slots = slots + 1 end
                if entry.id:match("artifact_slot") then artifacts = artifacts + 1 end
                check(not entry.id:match("team_%d"), "小队不混入等级解锁")
            end
            check(slots == (lv == 2 and 1 or 0), "6/10级不假增第5槽 " .. lv)
            check(artifacts == ((lv == 30 or lv == 60) and 1 or 0), "神器格真实门槛 " .. lv)
        end
        local range = Progress.getRangeUnlocks(1,60)
        local byId = {}
        for _, entry in ipairs(range) do
            check(not byId[entry.id], "跨级成长去重")
            byId[entry.id] = entry
        end
        check(byId.team_slots and byId.artifact_slot_1 and byId.artifact_slot_2, "跨级不丢早期解锁")
        check(byId.enhance_cap.unlockName == "装备强化上限 Lv.60", "成长保留最终上限")
        check(byId.church.level == Exp.CHURCH_UNLOCK_LEVEL, "礼拜堂门槛同源")
        check(Progress.rewardLabel(Config.findById("a_plv_100").reward) == "黑晶 × 840", "黑晶未改币种")
        check(#Progress.getRangeUnlocks(60,30) == 0, "降级不庆祝解锁")
        local I18n = require("core.I18n")
        local dictionary = require("core.I18nExpedition")
        local function formatKinds(value)
            local kinds = {}
            for kind in value:gmatch("%%([ds])") do kinds[#kinds + 1] = kind end
            return table.concat(kinds)
        end
        for language, pack in pairs(dictionary) do
            I18n.set(language)
            for source, translated in pairs(pack) do
                check(type(translated) == "string" and translated ~= "", language .. "每条译文完整")
                check(formatKinds(source) == formatKinds(translated), language .. "参数类型及顺序保持")
                if language == "en" or language == "ko" then
                    check(not translated:find("[\228-\233]"), language .. "非汉字语言不残留中文")
                end
            end
            for _, row in ipairs(model.rows) do
                local label = Progress.rewardLabel(row.reward)
                check(label:find(" × ", 1, true) ~= nil, language .. "奖励数量保留")
            end
            local range = Progress.getRangeUnlocks(1,60)
            for _, entry in ipairs(range) do
                check(Progress.unlockLabel(entry) ~= "", language .. "每种真实解锁有译文")
                check(entry.unlockName == byId[entry.id].unlockName, language .. "语言不改缓存规则")
            end
        end
        I18n.set("zh_CN")
        same(Config.ACHIEVEMENT, configBefore, "所有展示与语言切换不改生产配置")
        same(Config.LEVEL_TASKS, levelTasksBefore, "按级配置展示前后完全不变")
    end)
    if not ok then print("[FAIL] expedition_progress_test: " .. tostring(err)) end
    if ok then print("[expedition_progress_test] ALL PASS cases=" .. cases .. " assertions=" .. assertions) end
    engine:Exit()
end
