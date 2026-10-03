-- 远征展示模型回归：真实配置与规则，断言不改玩家档、不改变任何原奖励。
function Start()
    local assertions = 0
    local function check(value, label)
        assertions = assertions + 1
        assert(value, label)
    end
    local ok, err = pcall(function()
        local Progress = require("config.ExpeditionProgress")
        local Config = require("config.TaskConfig")
        local Exp = require("config.ExpTable")
        local levels = {5, 10, 20, 30, 50, 80, 100, 150, 200}
        local kinds = {"essence", "adventure_ticket", "enhance_star", "arcane_dust", "sweep_ticket",
            "stellar_ticket", "diamond", "gold", "essence"}
        local amounts = {150, 2, 2, 600, 1, 1, 840, 120000, 6000}
        local task = { achClaimed = { a_plv_10 = true }, achProg = { player_level = 1 } }
        local model = Progress.build({level = 30, exp = 25}, task, {maxStageId = 905})
        check(#model.rows == 9, "九个既有里程碑")
        check(model.claimableCount == 3, "按提交玩家等级计可领，不读陈旧进度")
        check(model.nextLevel == 50, "下个里程碑")
        check(model.focusIndex == 1, "优先首个未领已达")
        for i, row in ipairs(model.rows) do
            check(row.level == levels[i], "保持等级排序 " .. i)
            check(row.taskId == "a_plv_" .. levels[i], "稳定台账ID " .. i)
            check(row.reward.type == kinds[i] and row.reward.amount == amounts[i], "保留原奖励 " .. i)
            local def = Config.findById(row.taskId)
            check(def.reward == row.reward, "同源奖励 " .. i)
        end
        check(model.rows[2].status == Config.STATUS.CLAIMED, "原已领状态保留")
        check(model.rows[1].status == Config.STATUS.CLAIMABLE, "未领可补领")
        check(model.rows[5].status == Config.STATUS.LOCKED, "未达成不可领")
        check(task.achProg.player_level == 1 and task.achClaimed.a_plv_10 == true, "展示无写入")
        check(model.stageUnlocks[1].unlocked == false, "等级高/刚到9-5不假开放小队")
        local completed = Progress.build({level=200}, {}, {clearedStages = {["905"] = true}})
        check(completed.stageUnlocks[1].unlocked == true and completed.stageUnlocks[2].unlocked == false,
            "通关条件单列")
        check(completed.maxExp == 0 and completed.exp == 0 and completed.ratio == 1, "满级进度")
        local claimed = {}
        for _, lv in ipairs(levels) do claimed["a_plv_" .. lv] = true end
        local done = Progress.build({level=200}, {achClaimed=claimed}, {})
        check(done.claimableCount == 0 and done.focusIndex == 9 and done.nextLevel == nil, "全部已领定位历史末端")
        local before = Progress.build({level=4}, {}, {})
        check(before.nextLevel == 5 and before.focusIndex == 1 and before.claimableCount == 0, "新档下一奖励")
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
    end)
    if not ok then print("[FAIL] expedition_progress_test: " .. tostring(err)) end
    if ok then print("[expedition_progress_test] ALL PASS assertions=" .. assertions) end
    engine:Exit()
end
