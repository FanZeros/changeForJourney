-- 传说觉醒联动回归：真实属性/天赋/伤害管线，拥有数据仅内存，禁止玩家文件访问。
local assertions, failures = 0, 0
local function check(value, message)
    assertions = assertions + 1
    if not value then failures = failures + 1; print("[传说觉醒][FAIL] " .. message) end
end
local function near(a, b) return math.abs(a - b) < 1e-8 end
local function awake(stage)
    local out = { _awk3Migrated = true }
    for i = 1, stage do out[i] = true end
    return out
end

function Start()
    print("[传说觉醒] 开始：阶段/历史成长/有界爆发/真实伤害/独立战线")
    local nativeRequire, nativeFile, nativeFS, nativeFs = require, File, FileSystem, fileSystem
    local storageCalls = 0
    local function denyStorage()
        storageCalls = storageCalls + 1
        error("传说觉醒专项禁止文件存储访问")
    end
    rawset(_G, "File", denyStorage)
    rawset(_G, "FileSystem", denyStorage)
    rawset(_G, "fileSystem", setmetatable({}, { __index = function() return denyStorage end }))
    local owned = {}
    local sends = 0
    local cp = {
        getOwnedHero = function(id) return owned[id] end,
        patchExtraTalent = function(id, extra) owned[id].extraTalent = extra end,
        finishExtraTalentBatch = function() end,
    }
    local mocks = {
        ["ui.character.panel.CharacterPanel"] = cp,
        ["runtime.ClientDispatcher"] = { get = function(key)
            if key == "heroes" then return { roster = owned } end
        end },
        ["runtime.GameAction"] = { sendAction = function() sends = sends + 1 end },
    }
    rawset(_G, "require", function(name) return mocks[name] or nativeRequire(name) end)
    local ok, err = pcall(function()
        local AC = require("config.AwakeningConfig")
        local AD = require("systems.AttributeDef")
        local UA = require("systems.UnitAttributes")
        local HC = require("config.HeroConfig")
        local ETS = require("systems.ExtraTalentSystem")
        local TAL = require("systems.TalentManager")
        local BC = require("ui.battle.combat.BattleCombat")
        local PS = require("ui.battle.combat.ProjectileSystem")
        local SEM = require("systems.StatusEffectManager")
        local I18n = require("core.I18n")
        local dict = require("core.I18nDictExtra")
        local states = {}
        local function unit(id, stage, count)
            owned[id] = { awakening = awake(stage), extraTalent = ETS.normalize({
                stacks = count or 0, swordStacks = id == 16 and count or 0,
                gateStacks = id == 20 and count or 0,
            }) }
            return assert(HC.createHero(id, 1, nil, awake(stage), owned[id].extraTalent,
                { litNodes = {}, silent = true }))
        end
        local function enemy(hp)
            local attrs = UA.create({ [AD.MAX_HP] = hp or 1000000 })
            attrs:fillHp(); attrs:recalc()
            local u = attrs:toBattleUnit("专项敌人", 1)
            u.heroId = 0
            return u
        end
        local function living(list)
            local out = {}
            for _, u in ipairs(list) do if u.hp > 0 then out[#out + 1] = u end end
            return out
        end
        local testRefs = {}
        local deps = {
            getTAL_BCS = function() return testRefs end,
            hasAwaken = function(u, n) return AC.hasNode(u.awakeningNodes, n) end,
            hasAwakenStage = function(u, n) return AC.hasStage(u.awakeningNodes, n) end,
            getState = function(u) return states[u] end,
            ensureState = function(u)
                states[u] = states[u] or { heroId = u.heroId }
                return states[u]
            end,
            getAliveEnemies = living, talentLog = function() end,
            AD = AD, SEM = SEM,
            calcTalentFixedDamage = function(_, _, damage) return math.floor(damage + 0.5), false end,
        }
        local swords = require("systems.talents.TalentLuoxing").bind(deps)
        local gates = require("systems.talents.TalentMelissa").bind(deps)
        local ping = require("systems.talents.TalentFourNew").bind(deps)

        -- 独立数值oracle：不调用被测公式生成期望，原阶段门禁与额外次数分开检查。
        for stage = 0, 3 do
            for _, count in ipairs({ 0, 39, 40, 199, 200, 10000 }) do
                local a, target = unit(16, stage, count), enemy()
                local s = { heroId = 16, flyingSwordDamage = 1000 }
                states[a] = s
                for volley = 1, 3 do
                    s.flyingSwordDamage = 1000
                    local normal, rain, value = 0, 0, 0
                    math.randomseed(731)
                    local fired = swords.fireLuoxingFlyingSwords(a, s, { target }, true,
                        function(_, damage, _, prefix, _, opts)
                            if prefix == "剑冢剑雨" then
                                rain = rain + 1
                                check(not opts.recordOnHit and not opts.flyingSwordOnHit, "剑雨不生成记录或飞回")
                            else
                                normal = normal + 1
                                check((opts.recordOnHit ~= nil) == (stage >= 2), "保留觉醒2伤害记录")
                                check((opts.flyingSwordOnHit ~= nil) == (stage >= 2), "保留觉醒2飞回")
                                if stage >= 2 then
                                    check(opts.flyingSwordOnHit.chance == (stage == 3 and 0.5 or 0.25), "飞回概率保留")
                                end
                            end
                            value = damage
                        end)
                    local min, max = stage >= 1 and 4 or 3, stage >= 2 and 7 or 6
                    local extra = stage >= 2 and math.min(5, math.floor(count / 40)) or 0
                    check(fired and normal >= min + extra and normal <= max + extra, "飞剑柄数范围与成长门槛")
                    local coeff = (stage >= 1 and 0.6 or 0.5) + (stage >= 1 and count * 0.002 or 0) * (stage == 3 and 2 or 1)
                    check(value == math.floor(1000 * coeff + 0.5), "飞剑成长只在III双倍")
                    check(rain == (stage == 3 and volley == 3 and normal or 0), "每第三有效轮等量剑雨")
                    check(owned[16].extraTalent.swordStacks == count, "飞剑不改历史剑冢")
                end
                s.flyingSwordDamage, s.flyingSwordCarryover = 0, 0
                local oldVolley = s.flyingSwordVolley
                check(not swords.fireLuoxingFlyingSwords(a, s, { target }, true, function() end)
                    and s.flyingSwordVolley == oldVolley, "空窗口不增加爆发轮次")
            end
        end
        for stage = 0, 3 do
            for _, count in ipairs({ 0, 39, 40, 79, 80, 10000 }) do
                local a = unit(20, stage, count)
                local s = { heroId = 20 }
                states[a] = s
                gates.summonMelissaStarGate(a, s)
                local expected = stage >= 2 and math.min(3, 2 + math.min(2, math.floor(count / 40))) or 1
                check(s.starGateCount == expected, "星门数量旧40层门槛保留")
                check(near(gates.getMelissaStarGateDmgMult(a), (stage >= 2 and 4 or stage == 1 and 3.4 or 3)
                    + (stage >= 1 and count * 0.003 or 0) * (stage == 3 and 2 or 1)), "星门成长III双倍")
                check(gates.getMelissaStarGateResonanceScale(a) == (stage == 3 and 1.5 or 1), "旧共鸣倍率保留")
                local targets = { enemy(), enemy(), enemy(), enemy(), enemy(), enemy() }
                targets[#targets + 1] = targets[1]
                local normal, collapse, normalDamage, burstDamage = 0, 0, 0, 0
                s.starGateStarMarks = 5
                local function capture(_, damage, _, prefix)
                    if prefix == "星门坍缩" then collapse = collapse + 1; burstDamage = damage
                    else normal = normal + 1; normalDamage = damage end
                end
                gates.triggerMelissaStarGates(a, true, targets, capture, { a })
                check(normal == expected and collapse == (stage == 3 and 4 or 0), "满星痕坍缩仅III且至多四个不同敌人")
                check(near(gates.getMelissaStarMarkDamageScale(a, { starGateStarMarks = 5 }), stage == 3 and 2.2 or 1.6), "星痕III每层24%")
                if stage == 3 then check(math.abs(burstDamage - normalDamage * 1.5) <= 1, "坍缩150%独立无护甲oracle") end
                check(s.starGateStarMarks == (stage >= 2 and expected or 0), "每扇星门补一层下轮星痕")
                collapse = 0
                gates.triggerMelissaStarGates(a, true, targets, capture, { a })
                check(collapse == 0, "残留星痕不足五层不循环坍缩")
                s.starGateStarMarks = 5
                targets = {}
                check(not gates.triggerMelissaStarGates(a, true, targets, capture, { a }) and s.starGateStarMarks == 5,
                    "无目标不消耗星痕")
                check(owned[20].extraTalent.gateStacks == count, "星门不改旧殖民成长")
            end
        end
        -- 故意交替元素/暴击/目标系数：坍缩必须冻结首门结果，不可再次进入伤害公式。
        local calcCalls = 0
        ---@type table<string, any>
        local variedDeps = {}
        for key, value in pairs(deps) do variedDeps[key] = value end
        variedDeps.calcTalentFixedDamage = function(_, tgt, damage, opts)
            calcCalls = calcCalls + 1
            local critical = calcCalls % 2 == 0
            return math.floor(damage * (critical and 2 or 1) * (tgt.testTaken or 1) + 0.5), critical
        end
        local variedGates = require("systems.talents.TalentMelissa").bind(variedDeps)
        for _, deadCaster in ipairs({ false, true }) do
            local caster = unit(20, 3, 80)
            local gateState = { heroId = 20 }
            states[caster] = gateState
            variedGates.summonMelissaStarGate(caster, gateState)
            if deadCaster then caster.hp = 0 end
            gateState.starGateStarMarks = 5
            local group = { enemy(), enemy(), enemy(), enemy(), enemy() }
            group[2].testTaken = 0.37
            local first, hits = {}, 0
            calcCalls = 0
            math.randomseed(417)
            variedGates.triggerMelissaStarGates(caster, true, group, function(tgt, value, _, prefix, _, opts)
                if prefix == "星门" and not first.damage then
                    first = { damage = value, atkType = opts.atkType, critical = opts.isCrit }
                elseif prefix == "星门坍缩" then
                    hits = hits + 1
                    check(value == math.floor(first.damage * 1.5 + 0.5), "坍缩精确复制首门发射伤害")
                    check(opts.atkType == first.atkType and opts.isCrit == first.critical and not opts.critEligible,
                        "坍缩元素暴击不重抽")
                    -- 首次回调移走当前目标，仍应按固定四目标快照继续，不跳过下一名。
                    if hits == 1 then
                        for index, entry in ipairs(group) do if entry == tgt then table.remove(group, index); break end end
                    end
                end
            end, { caster })
            check(calcCalls == 3 and hits == 4, "生前与死后坍缩均不追加公式或随换表漏目标")
        end

        -- 每门/坍缩回调后重新校验开战身份，外层大dt也不能继续旧场补发。
        for _, phase in ipairs({ "星门", "星门坍缩" }) do
            for _, action in ipairs({ "restart", "mount", "state" }) do
                local caster = unit(20, 3, 80)
                local gateState = { heroId = 20 }
                states[caster] = gateState
                gates.summonMelissaStarGate(caster, gateState)
                gateState.starGateStarMarks = 5
                local group = { enemy(), enemy(), enemy(), enemy() }
                local normals, bursts = 0, 0
                gates.updateMelissaStarGate(10, caster, gateState, true, group,
                    { dealTalentDamage = function(_, _, _, _, prefix)
                        if prefix == "星门" then normals = normals + 1 else bursts = bursts + 1 end
                        if prefix == phase then
                            if action == "restart" then gates.summonMelissaStarGate(caster, gateState)
                            elseif action == "mount" then testRefs = {}
                            else states[caster] = { heroId = 20 } end
                        end
                    end }, { caster })
                check(normals == (phase == "星门" and 1 or 3) and bursts == (phase == "星门" and 0 or 1),
                    "星门回调换场立即停止旧轮及大dt补发 phase=" .. phase .. " action=" .. action)
                if action == "restart" then
                    check(gateState.starGateTimer == 0 and gateState.starGateStarMarks == 0, "重开新状态不被旧轮扣时留痕")
                else check(gateState.starGateStarMarks == 5, "旧场取消不额外写入留痕") end
            end
        end

        for stage = 0, 3 do
            for _, count in ipairs({ 0, 1, 200, 399, 400, 10000 }) do
                local a, target = unit(25, stage, count), enemy(10000)
                local s = { heroId = 25 }
                states[a] = s
                ping.onBattleStart(a, s)
                local targets = { target }
                ping.onAfterAttack(a, target, { category = "physical", totalDamage = 1000 }, true, targets)
                local scale = stage >= 2 and 1 + math.min(stage == 3 and 4 or 2, count * (stage == 3 and 0.01 or 0.005)) or 1
                local expected = math.floor(1000 * (stage >= 1 and 0.55 or 0.45) * scale + 0.5)
                check(s.pingQueue[1].dmg == expected, "高ping成长倍率阶段与上限")
                local calls = {}
                local ctx = { dealTalentDamage = function(source, tgt, value, side, prefix, _, meta)
                    calls[#calls + 1] = { source = source, target = tgt, dmg = value, prefix = prefix }
                    check(source == a and not side and meta.threatScale == 0.1, "延迟包真实来源/方向/低仇恨")
                end }
                local delay = stage >= 2 and 1.2 or 1.5
                ping.update(delay - 0.001, { a }, targets, ctx)
                check(#calls == 0, "到期之前不结算")
                ping.update(0.0011, { a }, targets, ctx)
                check(#calls == 1 and calls[1].dmg == expected, "主包只结算一次")
                ping.update(0.599, { a }, targets, ctx)
                check(#calls == 1, "重传至少等待0.6秒")
                ping.update(0.002, { a }, targets, ctx)
                check(#calls == (stage == 3 and 2 or 1), "只有III追加一次重传")
                ping.update(10, { a }, targets, ctx)
                check(#s.pingQueue == 0 and #calls == (stage == 3 and 2 or 1), "大dt不无限生成包")
                check(owned[25].extraTalent.stacks == count, "延迟包不写旧成长层")
            end
        end
        -- 死目标被移出本战线后可转火；同英雄的另一战线列表不可借用。
        local a, dead, target = unit(25, 3, 0), enemy(), enemy()
        local s = { heroId = 25 }
        states[a] = s
        ping.onBattleStart(a, s)
        local targets = { dead, target }
        ping.onAfterAttack(a, dead, { totalDamage = 100, category = "physical" }, true, targets)
        dead.hp = 0; table.remove(targets, 1)
        local hits = 0
        ping.update(1.2, { a }, targets, { dealTalentDamage = function(_, tgt) hits = hits + 1; check(tgt == target, "死目标转火仍在本线") end })
        check(hits == 1, "移出列表的死目标包不丢失")
        testRefs = {}
        ping.update(0.6, { a }, { enemy() }, { dealTalentDamage = function() hits = hits + 1 end })
        check(hits == 1, "异战线refs不接收重传")

        -- 同战线换敌表仍转火；大dt只处理帧初到期包；复用状态开战使旧token失效。
        for _, replaceOnRetransmit in ipairs({ false, true }) do
            a, dead, target = unit(25, 3, 100), enemy(10000), enemy(10000)
            s = { heroId = 25 }; states[a] = s
            ping.onBattleStart(a, s)
            local oldTargets = { dead }
            ping.onAfterAttack(a, dead, { totalDamage = 1000, category = "physical" }, true, oldTargets)
            local current = replaceOnRetransmit and oldTargets or { target }
            if not replaceOnRetransmit then dead.hp = 0 end
            local packets = {}
            local ctx = { dealDamage = function(tgt, damage, side, prefix, _, source, meta)
                packets[#packets + 1] = damage
                check(source == a and not side and meta.instantDamage, "可靠传输七参来源回退")
                check(tgt == (replaceOnRetransmit and dead or target), "同线换表主包正确目标")
            end }
            ping.update(10, { a }, current, ctx)
            check(#packets == 1 and #s.pingQueue == 1 and s.pingQueue[1].t == 0.6,
                "活跃包大dt不会同帧推进新重传")
            local original = packets[1]
            if replaceOnRetransmit then dead.hp = 0; current = { target } end
            ping.update(0.6, { a }, current, { dealDamage = function(tgt, damage, _, _, _, source, meta)
                packets[#packets + 1] = damage
                check(tgt == target and source == a and meta.threatScale == 0.1, "同线换表重传转火")
            end })
            check(#packets == 2 and packets[2] == original and #s.pingQueue == 0,
                "转火重传复制主包实际值且不再生成")
            ping.onAfterAttack(a, target, { totalDamage = 1000, category = "physical" }, true, current)
            ping.onBattleStart(a, s)
            ping.update(10, { a }, current, { dealDamage = function() check(false, "开战不能泄露旧包") end })
            check(#s.pingQueue == 0, "复用状态开战清旧包")
        end
        -- 首包回调重开/切挂载：已经拆出的其余ready包必须重新检查身份。
        for _, action in ipairs({ "restart", "mount", "state", "append" }) do
            a, target = unit(25, 3, 0), enemy()
            s = { heroId = 25 }; states[a] = s
            ping.onBattleStart(a, s)
            targets = { target }
            for _ = 1, 2 do ping.onAfterAttack(a, target, { totalDamage = 100, category = "physical" }, true, targets) end
            local n = 0
            ping.update(10, { a }, targets, { dealTalentDamage = function()
                n = n + 1
                if n == 1 then
                    if action == "restart" then ping.onBattleStart(a, s)
                    elseif action == "mount" then testRefs = {}
                    elseif action == "state" then states[a] = { heroId = 25 }
                    else ping.onAfterAttack(a, target, { totalDamage = 100, category = "physical" }, true, targets) end
                end
            end })
            check(n == (action == "append" and 2 or 1), "回调变更身份或追加包不重复到期 action=" .. action)
            if action == "append" then
                check(#s.pingQueue == 3 and s.pingQueue[2].t == 1.2, "回调追加的主包仍保完整延迟")
            end
        end
        -- 本体死亡或离开名单不推进，复活只恢复未到期包；没有额外重传循环。
        a, target = unit(25, 3, 0), enemy()
        s = { heroId = 25 }; states[a] = s; ping.onBattleStart(a, s); targets = { target }
        ping.onAfterAttack(a, target, { totalDamage = 100, category = "physical" }, true, targets)
        local aliveHits = 0
        local lifeCtx = { dealTalentDamage = function() aliveHits = aliveHits + 1 end }
        a.hp = 0; ping.update(10, { a }, targets, lifeCtx)
        check(aliveHits == 0 and s.pingQueue[1].t == 1.2, "本体死亡不结算或计时")
        a.hp = a.maxHp; ping.update(10, {}, targets, lifeCtx)
        check(aliveHits == 0, "退出名单不结算")
        ping.update(1.2, { a }, targets, lifeCtx); ping.update(0.6, { a }, targets, lifeCtx)
        check(aliveHits == 2 and #s.pingQueue == 0, "同场复活只完成主包及一次重传")

        -- 显式extra=false不借同ID高成长启用新增联动，旧觉醒效果仍保留。
        for _, id in ipairs({ 16, 20, 25 }) do
            unit(id, 3, 10000)
            local disabled = assert(HC.createHero(id, 1, nil, awake(3), false, { litNodes = {}, silent = true }))
            local disabledState = { heroId = id, flyingSwordDamage = 1000, flyingSwordVolley = 2 }
            states[disabled] = disabledState
            local disabledTargets = { enemy() }
            if id == 16 then
                local normal, rain = 0, 0
                swords.fireLuoxingFlyingSwords(disabled, disabledState, disabledTargets, true,
                    function(_, _, _, prefix) if prefix == "剑冢剑雨" then rain = rain + 1 else normal = normal + 1 end end)
                check(normal <= 7 and rain == 0, "extra=false不增加飞剑或第三轮剑雨")
            elseif id == 20 then
                gates.summonMelissaStarGate(disabled, disabledState)
                disabledState.starGateStarMarks = 5
                local burst = 0
                gates.triggerMelissaStarGates(disabled, true, disabledTargets,
                    function(_, _, _, prefix) if prefix == "星门坍缩" then burst = burst + 1 end end, { disabled })
                check(burst == 0 and disabledState.starGateStarMarks == 0
                    and near(gates.getMelissaStarMarkDamageScale(disabled, { starGateStarMarks = 5 }), 1.6),
                    "extra=false不启用坍缩、增强星痕或留痕")
            else
                ping.onBattleStart(disabled, disabledState)
                ping.onAfterAttack(disabled, disabledTargets[1], { totalDamage = 1000, category = "physical" }, true, disabledTargets)
                check(disabledState.pingQueue[1].dmg == 550, "extra=false无成长包倍率")
                ping.update(10, { disabled }, disabledTargets, { dealDamage = function(_, _, _, _, _, source, meta)
                    check(source == disabled and meta.instantDamage and not meta.critEligible, "七参回退保真实来源及meta")
                end })
                check(#disabledState.pingQueue == 0, "extra=false无重传")
            end
        end

        -- 正式星门伤害公式：真实元素/暴击/护甲/状态后，坍缩仍精确复制首门结果。
        for seed = 1, 12 do
            local caster = unit(20, 3, 80)
            local group = { enemy(), enemy(), enemy(), enemy(), enemy() }
            caster.attrs:addModifier("synergy_crit", { { key = AD.CRIT_RATE, flat = 47 }, { key = AD.CRIT_DMG, flat = 73 } })
            group[2].attrs:addModifier("synergy_armor", { { key = AD.ARMOR, flat = 180 } })
            ETS.mount(ETS.newState()); TAL.reset(); SEM.reset()
            TAL.onBattleStart({ caster }, group)
            TAL.mountedUnitStates()[caster].starGateStarMarks = 5
            local first, burst, normals = {}, 0, 0
            math.randomseed(seed)
            TAL.update(2.2, { caster }, group, { dealTalentDamage = function(source, tgt, damage, side, prefix, _, opts)
                if prefix == "星门" then
                    normals = normals + 1
                    if not first.damage then first = { damage = damage, critical = opts.isCrit, atkType = opts.atkType } end
                elseif prefix == "星门坍缩" then
                    burst = burst + 1
                    check(damage == math.floor(first.damage * 1.5 + 0.5)
                        and opts.isCrit == first.critical and opts.atkType == first.atkType,
                        "真实元素暴击护甲下复制首门 seed=" .. seed)
                    check(source == caster and not side and opts.instantDamage, "真实坍缩来源/方向/即时标记")
                end
            end })
            check(normals == 3 and burst == 4, "正式TAL星门每轮仅四坍缩")
        end

        -- 第三轮剑雨通过真实BC/ProjectileSystem落地；没有记录/飞回，窗口不自喂。
        a, target = unit(16, 3, 200), enemy(10000000)
        ETS.mount(ETS.newState()); TAL.reset(); SEM.reset(); BC.reset(); PS.reset()
        local swordTargets = { target }
        TAL.onBattleStart({ a }, swordTargets)
        local swordState = TAL.mountedUnitStates()[a]
        swordState.flyingSwordVolley = 2
        swordState.flyingSwordDamage = 1000
        local normalHits, rainHits, rainTotal = 0, 0, 0
        BC.setContext({ getAllies = function() return { a } end, getEnemies = function() return swordTargets end,
            onTalentDealDamage = function(source, tgt, x, y, prefix, applyDamage, opts)
                if prefix == "剑冢剑雨" then
                    rainHits = rainHits + 1
                    check(not opts.recordOnHit and not opts.flyingSwordOnHit, "实际剑雨投射物无自喂回调")
                else normalHits = normalHits + 1 end
                BC.onTalentDealDamage(source, tgt, x, y, prefix, applyDamage, opts, { a }, swordTargets)
            end })
        local before = target.hp
        TAL.update(3, { a }, swordTargets, { dealTalentDamage = function(source, tgt, damage, side, prefix, color, opts)
            if prefix == "剑冢剑雨" then rainTotal = rainTotal + damage end
            return BC.dealTalentDamage(source, tgt, damage, side, prefix, color, opts, { a }, swordTargets)
        end })
        check(normalHits >= 9 and normalHits <= 12 and rainHits == normalHits and PS.getActiveCount() > 0,
            "正式第三轮飞剑及等量剑雨生成真实投射物")
        for _ = 1, 240 do PS.update(1 / 60) end
        check(PS.getActiveCount() == 0 and before - target.hp >= rainTotal * 2,
            "第三轮投射物及飞回完成且正向与剑雨伤害实际落地")
        check(swordState.flyingSwordDamage == 0, "剑雨不回流飞剑伤害窗口")
        ---@type table
        local oldRecord
        states[a] = { heroId = 16, flyingSwordVolley = 2, flyingSwordDamage = 1000, flyingSwordBattleToken = {} }
        local localSwordState = states[a]
        local stopped = 0
        swords.fireLuoxingFlyingSwords(a, localSwordState, swordTargets, true, function(_, _, _, _, _, opts)
            stopped = stopped + 1; oldRecord = opts.recordOnHit
            localSwordState.flyingSwordBattleToken = {}
        end)
        check(stopped == 1, "剑雨首柄回调重开立即停旧轮")
        local prior = localSwordState.flyingSwordCarryover
        oldRecord.addCarryover(1000)
        check(localSwordState.flyingSwordCarryover == prior, "旧飞剑记录回调不写新开战窗口")

        -- 正式TAL.update外层不能把首柄回调重开后新累计的窗口清掉。
        for _, phase in ipairs({ "灵月飞剑", "剑冢剑雨" }) do
            a, target = unit(16, 3, 0), enemy()
            ETS.mount(ETS.newState()); TAL.reset(); SEM.reset()
            local group = { target }
            TAL.onBattleStart({ a }, group)
            local freshState = TAL.mountedUnitStates()[a]
            freshState.flyingSwordVolley, freshState.flyingSwordDamage = 2, 1000
            local total, resetDone = 0, false
            TAL.update(10, { a }, group, { dealTalentDamage = function(_, _, _, _, prefix)
                total = total + 1
                if prefix == phase and not resetDone then
                    resetDone = true
                    TAL.onBattleStart({ a }, group)
                    TAL.onAfterAttack(a, target, { damageDealt = 100, totalDamage = 100, category = "physical" },
                        true, group, function() end, { a })
                end
            end })
            check(resetDone and total == (phase == "灵月飞剑" and 1 or 2), "正式飞剑回调重开停旧发射")
            check(freshState.flyingSwordDamage == 100 and freshState.flyingSwordTimer == 0
                and freshState.flyingSwordVolley == 0, "外层不清回调新场伤害或轮次")
        end

        -- 真实TAL/BC扣血 → 击杀归因 → ETS增量 → flush，不读取或写玩家文件。
        for _, id in ipairs({ 16, 20, 25 }) do
            a = unit(id, 3, 40)
            target = enemy(20)
            ETS.mount(ETS.newState()); SEM.reset(); TAL.reset(); BC.reset(); PS.reset()
            TAL.onBattleStart({ a }, { target })
            local list = { target }
            BC.setContext({ getAllies = function() return { a } end, getEnemies = function() return list end })
            local ctx = { dealTalentDamage = function(source, tgt, damage, side, prefix, color, opts)
                return BC.dealTalentDamage(source, tgt, damage, side, prefix, color, opts, { a }, list)
            end }
            if id == 25 then
                TAL.onAfterAttack(a, target, { totalDamage = 100, category = "physical" }, true, list, function() end, { a })
                TAL.update(1.2, { a }, list, ctx)
            elseif id == 20 then
                TAL.update(2.2, { a }, list, ctx)
            else
                TAL.onAfterAttack(a, target, { totalDamage = 100, damageDealt = 100, category = "physical" }, true, list, function() end, { a })
                TAL.update(3, { a }, list, ctx)
            end
            check(target.hp <= 0 and target._killedBy == a, "真实传说攻击归因 hero=" .. id)
            check(owned[id].extraTalent.stacks == 40, "战中成长仍为旧档值")
            check(ETS.mountedState().pendingGrowth[id] and ETS.mountedState().pendingGrowth[id].stacks == 1,
                "真实击杀只记一次成长 hero=" .. id)
            ETS.flush(); ETS.flush()
            check(owned[id].extraTalent.stacks == 41, "flush幂等且仅加一次 hero=" .. id)
        end
        -- 双线同英雄独立包、目标与重传；单线reset不影响另线状态。
        local refsA, refsB = TAL.newBattleRefs(), TAL.newBattleRefs()
        local statesA, statesB = TAL.newUnitStates(), TAL.newUnitStates()
        local extraA, extraB = ETS.newState(), ETS.newState()
        local a1, a2 = unit(25, 3, 0), unit(25, 3, 0)
        local e1, e2 = enemy(), enemy()
        local l1, l2 = { e1 }, { e2 }
        local function mount(refs, units, extra) TAL.mount(refs); TAL.mountUnitStates(units); ETS.mount(extra) end
        mount(refsA, statesA, extraA); TAL.onBattleStart({ a1 }, l1)
        TAL.onAfterAttack(a1, e1, { totalDamage = 100, category = "physical" }, true, l1, function() end, { a1 })
        mount(refsB, statesB, extraB); TAL.onBattleStart({ a2 }, l2)
        TAL.onAfterAttack(a2, e2, { totalDamage = 200, category = "physical" }, true, l2, function() end, { a2 })
        local n1, n2 = 0, 0
        mount(refsA, statesA, extraA)
        TAL.update(1.2, { a1 }, l1, { dealTalentDamage = function(source, tgt) n1 = n1 + 1; check(source == a1 and tgt == e1, "A线来源目标独立") end })
        mount(refsB, statesB, extraB)
        TAL.update(0.6, { a2 }, l2, { dealTalentDamage = function() n2 = n2 + 1 end })
        check(n1 == 1 and n2 == 0, "A线到期不推进B线计时")
        mount(refsA, statesA, extraA); TAL.reset()
        mount(refsB, statesB, extraB)
        TAL.update(0.6, { a2 }, l2, { dealTalentDamage = function(source, tgt) n2 = n2 + 1; check(source == a2 and tgt == e2, "B线来源目标独立") end })
        check(n2 == 1, "A线reset不删B线队列")

        for _, id in ipairs({ 16, 20, 25 }) do
            for _, lang in ipairs({ "zh_TW", "en", "ja", "ko" }) do
                for stage = 2, 3 do
                    local text = AC.getNodeEffect(id, stage)
                    check(type(dict[lang][text]) == "string" and dict[lang][text] ~= text, "新增正文四语齐全")
                end
            end
        end
        check(AC.getTotalShardCost() == 90 and AC.COMBAT_POWER[4][2] == 82 and AC.COMBAT_POWER[4][3] == 50,
            "费用与战力定义保持不变")
        check(sends >= 3, "真实flush同步动作经过内存边界")
        check(type(I18n.lookup) == "function", "正式词典接口保留")
    end)
    if not ok then failures = failures + 1; print("[传说觉醒][FAIL] 执行异常：" .. tostring(err)) end
    check(storageCalls == 0, "无玩家File/FS访问")
    rawset(_G, "require", nativeRequire)
    rawset(_G, "File", nativeFile); rawset(_G, "FileSystem", nativeFS); rawset(_G, "fileSystem", nativeFs)
    print(string.format("[legendary_awakening_synergy_test] assertions=%d failures=%d storage=%d %s",
        assertions, failures, storageCalls, failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
