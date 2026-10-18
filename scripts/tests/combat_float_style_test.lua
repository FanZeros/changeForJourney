-- 克制重击样片模型专项：纯内存，不加载正式战斗和玩家档。
local Style = require("tests.float_preview.ImpactStyle")
local count = 0
local function check(condition, message)
    count = count + 1
    assert(condition, message)
end
local function run()
    local state, target = Style.newState(), {}
    local meta = { channel = "damage", atkType = 1 }
    local first = Style.add(state, target, 120, 10, 20, meta)
    check(first ~= nil and first.amount == 120, "首击立即显示真实输入数值")
    Style.update(state, 0.1)
    local merged = Style.add(state, target, 80, 10, 20, meta)
    check(merged == first and first.amount == 200, "短窗合并不丢数")
    check(first.age == 0.1 and first.pulse == 0.09, "合并脉冲不重置年龄")
    local crit = Style.add(state, target, 300, 10, 20, { channel = "damage", atkType = 1, isCrit = true })
    check(crit ~= first and crit.style == "crit", "暴击与普通分批")
    local heal = Style.add(state, target, 70, 10, 20, { channel = "heal", atkType = 8 })
    check(heal.text == "+70" and heal.style == "heal", "治疗通道和加号")
    local shield = Style.add(state, {}, 30, 10, 20, { channel = "shield", atkType = 5 })
    check(shield.style == "shield", "吸盾不当治疗")
    local dot = Style.add(state, target, 60, 10, 20, { channel = "damage", atkType = 1, isDot = true })
    check(dot ~= first, "DOT与普通伤害分批")
    local tailState, tailTarget = Style.newState(), {}
    local tailFirst = Style.add(tailState, tailTarget, 200, 10, 20, meta)
    Style.update(tailState, 0.38)
    local late = Style.add(tailState, tailTarget, 40, 10, 20, meta)
    check(late ~= tailFirst and late.amount == 40 and tailFirst.amount == 200, "收尾前不吞新数")
    local age = late.age
    Style.update(tailState, 0)
    check(late.age == age, "暂停时动画冻结")
    for i = 1, 80 do Style.add(state, {}, i, 0, 0, meta) end
    check(#state.entries == 15, "每样片战线活动数有界")
    Style.update(state, 4)
    check(#state.entries == 0 and next(state.index) == nil, "大dt到期清理索引")
    check(#state.pool <= 15, "对象池有界")
    for _, ft in ipairs(state.pool) do check(next(ft) == nil, "池不持有目标或上一批字段") end
    Style.add(state, target, 10, 0, 0, meta)
    Style.reset(state)
    check(#state.entries == 0 and next(state.index) == nil, "重播释放目标")
    for _, amount in ipairs({ 0, -1, math.huge, 0 / 0 }) do
        check(Style.add(state, target, amount, 0, 0, meta) == nil, "拒绝非法数值")
    end
    for _, style in ipairs({ "damage", "crit", "heal", "shield" }) do
        local preset = Style.PRESETS[style]
        for i = 0, 200 do
            local pose = Style.pose({ style = style, age = preset.duration * i / 200, side = -1 })
            for _, key in ipairs({ "x", "y", "sx", "sy", "alpha", "angle", "out" }) do
                local v = pose[key]
                check(v == v and v ~= math.huge and v ~= -math.huge, "动画值有限 " .. key)
            end
            check(pose.sx > 0 and pose.sy > 0, "缩放不反转")
            check(pose.alpha >= 0 and pose.alpha <= 1, "透明度范围")
            check(math.abs(pose.x) <= 20 and math.abs(pose.y) <= 5, "不长距离上浮")
        end
        local hold = Style.pose({ style = style, age = 0.24 })
        check(math.abs(hold.sx - 1) < 0.001 and math.abs(hold.sy - 1) < 0.001,
            "驻留阶段不持续缩小")
        local done = Style.pose({ style = style, age = preset.duration })
        check(done.alpha == 0 and done.out == 1, "退出终值收敛")
    end
    local other = Style.newState()
    Style.add(other, target, 80, 0, 0, meta)
    Style.reset(state)
    check(#other.entries == 1 and other.entries[1].amount == 80, "战线状态隔离")
    local tracks, trackTarget = Style.newState(), {}
    for kind = 1, 4 do Style.add(tracks, trackTarget, kind, 0, 0, { channel = "damage", atkType = kind }) end
    local slots = {}
    for _, ft in ipairs(tracks.entries) do
        check(not slots[ft.slot], "同目标轨道不重复")
        slots[ft.slot] = true
    end
    check(#tracks.entries == 3 and tracks.index[trackTarget]["damage:1:normal:direct:full"] == nil,
        "目标满轨只淘汰该目标最旧批次")
    local overflow, overflowTarget = Style.newState(), {}
    local big = Style.add(overflow, overflowTarget, 1e308, 0, 0, meta)
    local bigNext = Style.add(overflow, overflowTarget, 1e308, 0, 0, meta)
    check(big ~= bigNext and big.amount == 1e308 and bigNext.amount == 1e308,
        "浮点合并溢出时分批，不改输入")
    Style.reset(overflow)
    local integer = Style.add(overflow, overflowTarget, math.maxinteger, 0, 0, meta)
    local integerNext = Style.add(overflow, overflowTarget, 1, 0, 0, meta)
    check(integer ~= integerNext and integer.amount == math.maxinteger and integerNext.amount == 1,
        "整数合并不回绕为负数")
    local beforeAge = integerNext.age
    Style.update(overflow, 0 / 0); Style.update(overflow, math.huge)
    check(integerNext.age == beforeAge, "非法dt不污染年龄")
    Style.update(overflow, 4)
    check(#overflow.entries == 0 and next(overflow.index) == nil, "非法dt后仍正常到期")
    local lifecycle, lifeTarget = Style.newState(), {}
    local old = Style.add(lifecycle, lifeTarget, 10, 0, 0, meta)
    Style.update(lifecycle, 0.38)
    local new = Style.add(lifecycle, lifeTarget, 20, 0, 0, meta)
    Style.update(lifecycle, 0.28)
    check(next(old) == nil and lifecycle.index[lifeTarget][new.key] == new,
        "旧批到期不擦新批索引")
    local pulse, position, slot = new.pulse, new.x, new.slot
    Style.update(lifecycle, 0)
    check(new.pulse == pulse and new.x == position and new.slot == slot,
        "零dt冻结脉冲位置轨道")
    for i = 1, 20 do Style.add(lifecycle, {}, i, 0, 0, meta) end
    check(lifecycle.index[lifeTarget] == nil and #lifecycle.entries == 15,
        "预算淘汰立即释放旧目标索引")
    local identities = {}
    for i, ft in ipairs(lifecycle.entries) do
        check(ft.amount == i + 5 and not identities[ft], "预算保留最后十五批且身份唯一")
        identities[ft] = true
    end
    for _, ft in ipairs(lifecycle.pool) do check(not identities[ft] and next(ft) == nil, "活动与对象池身份不重叠") end
    for _, key in ipairs({ "boot.Standalone", "core.GameState", "boot.StandaloneSave", "ui.battle.combat.BattleCombat" }) do
        check(package.loaded[key] == nil, "未加载生产状态 " .. key)
    end
end
function Start()
    local ok, err = pcall(run)
    if ok then print("[FloatStyleTest] ALL PASS assertions=" .. count .. " productionState=not_loaded")
    else print("[FloatStyleTest] FAIL " .. tostring(err)); log:Write(LOG_ERROR, tostring(err)) end
    engine:Exit()
end
