-- ============================================================================
-- 追加技生命成长生命周期回归：战中累计、战后统一结算，不写真实存档。
-- 跑法：/workspace/.cli/UrhoXRuntime tests/extra_talent_hp_lifecycle_test.lua \
--       -tapcode_dir=/workspace/game5 -tool_mode -graphicsheadless -nosound
-- 使用真实 UnitAttributes；require 拦截持久化依赖和共享状态模块，结束时恢复。
-- ============================================================================
local AD = require("systems.AttributeDef")
local UA = require("systems.UnitAttributes")
local Protocol = require("shared.Protocol")

---@class ExtraTalentHpOwned
---@field awakening table
---@field extraTalent ExtraTalentData

---@type string[]
local failures = {}
local assertions = 0

local function check(condition, message)
    assertions = assertions + 1
    if condition then
        print("[PASS] " .. message)
    else
        failures[#failures + 1] = message
        print("[FAIL] " .. message)
    end
end

local function awakening(enabled)
    return { [1] = enabled, _awk3Migrated = true }
end

function Start()
    print("[extra_talent_hp_lifecycle_test] 开始生命成长生命周期回归")
    local originalRequire = require
    local SEM = originalRequire("systems.StatusEffectManager")
    local originalSemState = SEM.mountedState()
    SEM.mount(SEM.newSemState())
    ---@type table
    local etsForCleanup = {}
    ---@type table
    local originalEtsState = {}
    ---@type table<number, ExtraTalentHpOwned>
    local owned = {}
    ---@type table<number, table>
    local roster = {}
    ---@type table[]
    local sent = {}
    local patchCalls = 0
    local batchCalls = 0
    local batchedPatchCalls = 0
    local panelMock = {
        getOwnedHero = function(heroId) return owned[heroId] end,
        patchExtraTalent = function(heroId, extra, deferBatch)
            patchCalls = patchCalls + 1
            if deferBatch then batchedPatchCalls = batchedPatchCalls + 1 end
            owned[heroId].extraTalent = extra
        end,
        finishExtraTalentBatch = function()
            batchCalls = batchCalls + 1
        end,
    }
    local dispatcherMock = {
        get = function(key)
            if key == "heroes" then return { roster = roster } end
        end,
    }
    local actionMock = {
        sendAction = function(actionType, payload)
            sent[#sent + 1] = { actionType = actionType, payload = payload }
        end,
    }
    require = function(name)
        if name == "ui.character.panel.CharacterPanel" then return panelMock end
        if name == "runtime.ClientDispatcher" then return dispatcherMock end
        if name == "runtime.GameAction" then return actionMock end
        if name == "systems.StatusEffectManager" then return SEM end
        return originalRequire(name)
    end
    local ok, err = pcall(function()
        local ETS = originalRequire("systems.ExtraTalentSystem")
        etsForCleanup = ETS
        originalEtsState = ETS.mountedState()
        ETS.mount(ETS.newState())

        ---@param heroId number
        ---@param extra table|nil
        ---@param hp number|nil
        ---@param config table|nil
        ---@return table
        local function makeUnit(heroId, extra, hp, config)
            owned[heroId] = { awakening = awakening(true), extraTalent = ETS.normalize(extra) }
            roster[heroId] = {}
            local attrs = UA.create(config or { [AD.MAX_HP] = 100 })
            ETS.applyToAttrs(heroId, attrs, owned[heroId].extraTalent, owned[heroId].awakening)
            attrs:fillHp()
            attrs:recalc() -- 消费开战满血标记，再模拟伤害/死亡。
            if hp ~= nil then attrs.final[AD.HP] = hp end
            local unit = attrs:toBattleUnit("成长回归单位", 1)
            unit.heroId = heroId
            unit.awakeningNodes = owned[heroId].awakening
            return unit
        end

        local function kill(unit)
            local enemy = { hp = 0, _killedBy = unit }
            ETS.onEnemyDeath(enemy, { unit }, { enemy })
        end

        -- 战中只累计永久收益；机制表可即时变化，但属性/血量/永久计数不能提前刷新。
        local growthKeys = {
            "stacks", "burnKills", "shockKills", "overflowCount", "shareCount",
            "nitroKills", "gatlingKills", "swordStacks", "gateStacks", "shieldStacks",
            "issuedCards",
        }
        local function unchangedDuringBattle(unit, trigger, message)
            local oldHp, oldMax = unit.hp, unit.maxHp
            local attrs = unit.attrs
            ---@type table<string, number>
            local oldFinal = {}
            for key, value in pairs(attrs.final) do oldFinal[key] = value end
            local oldExtra = ETS.getOwned(unit.heroId)
            local oldPatches = patchCalls
            trigger()
            local stable = unit.hp == oldHp and unit.maxHp == oldMax
            for key, value in pairs(oldFinal) do
                if attrs.final[key] ~= value then stable = false end
            end
            for key, value in pairs(attrs.final) do
                if oldFinal[key] ~= value then stable = false end
            end
            check(stable, message .. "：战中 attrs/单位血量/上限不变")
            local latest = ETS.getOwned(unit.heroId)
            local sameGrowth = true
            for _, key in ipairs(growthKeys) do
                if latest[key] ~= oldExtra[key] then sameGrowth = false end
            end
            check(sameGrowth, message .. "：拥有数据永久计数不提前增长")
            return oldPatches
        end

        local function killAndFlush(unit)
            local oldPatches = unchangedDuringBattle(unit, function() kill(unit) end,
                "hero" .. unit.heroId .. " 击杀")
            check(patchCalls == oldPatches, "仅觉醒I击杀不提前调用存档 patch")
            ETS.flush()
        end

        local function shareAndFlush(unit)
            local oldPatches = unchangedDuringBattle(unit, function() ETS.onShareFatal(unit) end,
                "分摊致死")
            check(patchCalls == oldPatches, "分摊致死不提前调用存档 patch")
            ETS.flush()
        end

        local function enableMechanisms(unit)
            unit.awakeningNodes[2], unit.awakeningNodes[3] = true, true
        end

        local function hpCheck(unit, hp, maxHp, message)
            check(unit.hp == hp and unit.attrs:get(AD.HP) == hp
                and unit.maxHp == maxHp and unit.attrs:get(AD.MAX_HP) == maxHp,
                message .. string.format("（HP=%s/%s，上限=%s/%s）",
                    tostring(unit.hp), tostring(unit.attrs:get(AD.HP)),
                    tostring(unit.maxHp), tostring(unit.attrs:get(AD.MAX_HP))))
        end

        -- 1) 只应用属性不额外回血；覆盖同 ID 只重算一次，存量成长不被临时上限夹血。
        do
            local u = makeUnit(1, { stacks = 100 })
            local attrs = u.attrs
            local recalcCalls = 0
            local originalRecalc = attrs.recalc
            attrs.recalc = function(self)
                recalcCalls = recalcCalls + 1
                originalRecalc(self)
            end
            ETS.applyToAttrs(1, attrs, ETS.normalize({ stacks = 101 }), awakening(true))
            check(recalcCalls == 1, "存量成长同 ID 覆盖仅一次重算")
            check(attrs:get(AD.HP) == 200 and attrs:get(AD.MAX_HP) == 201,
                "直接 apply：满血旧200保留，新上限201但不自动填满")
            attrs.final[AD.HP] = 150
            ETS.applyToAttrs(1, attrs, ETS.normalize({ stacks = 102 }), awakening(true))
            check(attrs:get(AD.HP) == 150, "直接 apply：高于基础上限的残血150不夹到100")
            attrs.final[AD.HP] = 50
            ETS.applyToAttrs(1, attrs, ETS.normalize({ stacks = 103 }), awakening(true))
            check(attrs:get(AD.HP) == 50, "直接 apply：低残血50原值保留")
            ETS.applyToAttrs(1, attrs, ETS.normalize({ stacks = 103 }), awakening(true))
            check(attrs:get(AD.MAX_HP) == 203 and #attrs.modifiers.extra_talent_1 == 1,
                "重复应用同层数不叠加第二份 modifier")
            attrs.recalc = originalRecalc
            attrs.final[AD.HP] = 180
            ETS.applyToAttrs(1, attrs, ETS.normalize({ stacks = 20 }), awakening(true))
            check(attrs:get(AD.HP) == 120 and attrs:get(AD.MAX_HP) == 120,
                "直接 apply：成长下降只夹到最终120上限")
            ETS.applyToAttrs(1, attrs, ETS.normalize({}), awakening(true))
            check(attrs.modifiers.extra_talent_1 == nil and attrs:get(AD.MAX_HP) == 100
                and attrs:get(AD.HP) == 100, "零层移除旧成长并合法夹血")
            ETS.applyToAttrs(1, attrs, ETS.normalize({ stacks = 100 }), awakening(true))
            ETS.applyToAttrs(1, attrs, false, awakening(true))
            check(attrs:get(AD.MAX_HP) == 200, "显式 false 保留原有不应用语义")
            ETS.applyToAttrs(1, attrs, ETS.normalize({ stacks = 100 }), awakening(false))
            check(attrs.modifiers.extra_talent_1 == nil and attrs:get(AD.MAX_HP) == 100,
                "未解锁觉醒I移除旧成长")
        end

        -- 2) 实际击杀后 flush：满血/残血/濒死、新成长/存量成长都只补新增上限。
        for _, case in ipairs({
            { stacks = 0, hp = 100, expected = 101 },
            { stacks = 0, hp = 35, expected = 36 },
            { stacks = 100, hp = 200, expected = 201 },
            { stacks = 100, hp = 150, expected = 151 },
            { stacks = 100, hp = 1, expected = 2 },
        }) do
            local u = makeUnit(1, { stacks = case.stacks }, case.hp)
            killAndFlush(u)
            hpCheck(u, case.expected, 101 + case.stacks,
                "击杀：旧层" .. case.stacks .. " 旧HP" .. case.hp .. "仅补新增1生命")
            check(owned[1].extraTalent.stacks == case.stacks + 1, "真实击杀仍保存正确成长层数")
        end
        do
            local u = makeUnit(1, { stacks = 100 }, 150,
                { [AD.MAX_HP] = 100, [AD.HP_BONUS] = 50 })
            killAndFlush(u)
            hpCheck(u, 152, 302, "击杀：使用最终上限差额（生命倍率/整数舍入后增加2）")
        end
        do
            local u = makeUnit(4, { stacks = 100 }, 140)
            killAndFlush(u)
            hpCheck(u, 141, 151, "半点生命成长第一次舍入新增1")
            killAndFlush(u)
            hpCheck(u, 141, 151, "半点生命成长第二次上限未变不再回血")
        end
        do
            local u = makeUnit(3, { stacks = 100 }, 75)
            local beforeAtk = u.attrs:get(AD.PHYS_ATK)
            killAndFlush(u)
            hpCheck(u, 75, 100, "非生命成长击杀不额外回血")
            check(math.abs(u.attrs:get(AD.PHYS_ATK) - beforeAtk - 0.2) < 0.000001,
                "非生命成长仍按原倍率提高物攻")
        end

        -- 3) attrs 是来源；上限缓存陈旧/缺失不会重复补存量成长，下降也必须同步。
        do
            local u = makeUnit(1, { stacks = 100 }, 150)
            u.hp, u.maxHp = 10, 100
            killAndFlush(u)
            hpCheck(u, 151, 201, "陈旧 unit 缓存不吞血也不把存量成长重复补血")
            u.hp, u.maxHp = nil, nil
            killAndFlush(u)
            hpCheck(u, 152, 202, "缺失 unit 缓存仍按 attrs 差额补血并恢复同步")
        end
        for _, hp in ipairs({ 180, 70 }) do
            local u = makeUnit(1, { stacks = 100 }, hp)
            owned[1].extraTalent = ETS.normalize({ stacks = 10 })
            killAndFlush(u) -- 存档回落后真实击杀到11层，最终上限111。
            hpCheck(u, math.min(hp, 111), 111, "commit 上限下降只夹血并同步（旧HP" .. hp .. "）")
        end

        -- 4) 分摊致死成长和死后击杀归因都不得变相复活，仍应保存成长、同步上限。
        do
            local u = makeUnit(10, {}, 0)
            shareAndFlush(u)
            hpCheck(u, 0, 103, "真实分摊致死：0→0，不随上限+3复活")
            shareAndFlush(u)
            hpCheck(u, 0, 106, "继续提交阵亡成长仍保持死亡")
            check(owned[10].extraTalent.shareCount == 2 and owned[10].extraTalent.stacks == 2,
                "阵亡不阻断成长存档")
            ETS.flush()
            check(roster[10].extraTalent.shareCount == 2, "flush 同步 Dispatcher 存档成长")
            local found = false
            for _, action in ipairs(sent) do
                if action.actionType == Protocol.ACTION_TYPES.SYNC_EXTRA_TALENT
                    and action.payload.heroId == 10 and action.payload.extraTalent.shareCount == 2 then
                    found = true
                end
            end
            check(found and patchCalls > 0, "flush 通过 GameAction 发送正确成长且无需真实服务")
        end
        do
            local u = makeUnit(10, { stacks = 100, shareCount = 100 }, 0)
            u.hp = 50 -- 陈旧显示缓存不应覆盖 attrs 已死亡的0。
            shareAndFlush(u)
            hpCheck(u, 0, 403, "存量分摊成长：陈旧缓存活血也不得使 attrs 死亡复活")
        end
        do
            local u = makeUnit(10, { shareCount = 10 }, 80)
            u.hp = 0 -- unit 已记录死亡，但 attrs 还未来得及同步。
            shareAndFlush(u)
            hpCheck(u, 0, 133, "分摊死亡同步窗口：unit为0、attrs仍活血也不得复活")
        end
        do
            local u = makeUnit(1, { stacks = 100 }, 150)
            u.hp = 0
            killAndFlush(u)
            hpCheck(u, 0, 201, "延迟击杀死亡同步窗口：unit为0优先死亡保护")
        end
        do
            local u = makeUnit(1, { stacks = 100 }, 0)
            killAndFlush(u)
            hpCheck(u, 0, 201, "阵亡杀手延迟击杀归因仅增加上限，不复活")
            owned[1].extraTalent = ETS.normalize({ stacks = 10 })
            killAndFlush(u)
            hpCheck(u, 0, 111, "阵亡单位上限下降也同步且保持0")
        end
        -- 5) 同场两次击杀只结算一次；update 的定时保存不能提前提交永久增量。
        do
            local u = makeUnit(1, { stacks = 100 }, 150)
            local attrs = u.attrs
            local recalcCalls = 0
            local originalRecalc = attrs.recalc
            attrs.recalc = function(self)
                recalcCalls = recalcCalls + 1
                originalRecalc(self)
            end
            local beforePatch, beforeBatch = patchCalls, batchCalls
            local beforeBatched, beforeSent = batchedPatchCalls, #sent
            unchangedDuringBattle(u, function() kill(u); kill(u) end, "同场两击杀")
            check(ETS.mountedState().pendingGrowth[1].stacks == 2,
                "两次击杀累计同一英雄 pending stacks+2")
            unchangedDuringBattle(u, function() ETS.update(100) end, "update(100)")
            check(patchCalls == beforePatch and batchCalls == beforeBatch and #sent == beforeSent
                and recalcCalls == 0, "长时间 update 不提前 patch/结算/同步/重算永久成长")
            ETS.flush()
            hpCheck(u, 152, 202, "同场两击杀 flush 只补总上限差额2")
            check(owned[1].extraTalent.stacks == 102 and recalcCalls == 1
                and patchCalls == beforePatch + 1 and batchCalls == beforeBatch + 1
                and batchedPatchCalls == beforeBatched + 1 and #sent == beforeSent + 1,
                "批累积一次 patch/批完成/属性重算/网络同步")
            check(next(ETS.mountedState().pendingGrowth) == nil
                and next(ETS.mountedState().growthUnits) == nil, "flush 消费本批成长账本与单位引用")
            ETS.flush()
            hpCheck(u, 152, 202, "重复 flush 幂等，不重复补血")
            check(owned[1].extraTalent.stacks == 102 and recalcCalls == 1
                and patchCalls == beforePatch + 1 and batchCalls == beforeBatch + 1
                and #sent == beforeSent + 1, "重复 flush 不重复保存/同步/重算")
            attrs.recalc = originalRecalc
        end
        do
            local u = makeUnit(1, { stacks = 100 }, 150)
            unchangedDuringBattle(u, function() kill(u); kill(u) end, "最新存档合并前")
            -- 模拟另一战线或存档回执已经更新拥有数据，不可被旧整表覆盖。
            owned[1].extraTalent = ETS.normalize({ stacks = 120, biteTypes = { ["7"] = true } })
            ETS.flush()
            check(owned[1].extraTalent.stacks == 122 and owned[1].extraTalent.biteTypes["7"],
                "flush 按最新 owned 加 delta，保留其他来源成长与机制字段")
            hpCheck(u, 172, 222, "合并最新成长仍仅按 attrs 最终上限差额补血")
        end

        -- 6) 非击杀公共钩子也只记永久增量，机制库存保持当场可用。
        do
            local u = makeUnit(4, { stacks = 100 }, 140)
            enableMechanisms(u)
            unchangedDuringBattle(u, function()
                ETS.onBlock(u, 12.9)
                ETS.onBlock(u, 8)
            end, "连续格挡")
            check(owned[4].extraTalent.blockBank == 20
                and ETS.mountedState().pendingGrowth[4].stacks == 2,
                "格挡伤害库存即时取整累计20，永久两层留在 pending")
            unchangedDuringBattle(u, function() ETS.update(100) end, "格挡机制定时保存")
            check(roster[4].extraTalent.blockBank == 20 and roster[4].extraTalent.stacks == 100,
                "update 保存即时库存，但不会夹带待结算成长")
            ETS.flush()
            hpCheck(u, 141, 151, "两次格挡批结算半点成长按最终整数上限差额补1")
            check(owned[4].extraTalent.stacks == 102 and owned[4].extraTalent.blockBank == 20,
                "格挡批结算保留即时库存，不重复加库存")
        end
        do
            local u = makeUnit(9, { stacks = 40, overflowCount = 40 }, 110)
            unchangedDuringBattle(u, function()
                ETS.onOverflowHeal(u, 7)
                ETS.onOverflowHeal(u, 99)
            end, "两次过量治疗")
            check(ETS.mountedState().pendingGrowth[9].overflowCount == 2
                and ETS.mountedState().pendingGrowth[9].stacks == 2,
                "过量治疗按次数累计，治疗量不变成层数")
            ETS.flush()
            check(owned[9].extraTalent.overflowCount == 42 and owned[9].extraTalent.stacks == 42
                and math.abs(u.attrs:get(AD.SPI) - 2.1) < 1e-9,
                "过量治疗战后累计魂火，原0.05系数保留")
            hpCheck(u, 111, 121, "魂火派生生命战后只补新增最终上限")
        end
        do
            local u = makeUnit(23, { stacks = 10, shieldStacks = 10 }, 80)
            local oldShield = u.attrs:get(AD.ENERGY_SHIELD)
            unchangedDuringBattle(u, function()
                ETS.onOverflowHeal(u, 1)
                ETS.onOverflowHeal(u, 2)
            end, "两次过量转盾")
            ETS.flush()
            check(owned[23].extraTalent.shieldStacks == 12 and owned[23].extraTalent.stacks == 12
                and math.abs(u.attrs:get(AD.ENERGY_SHIELD) - oldShield - 2) < 1e-9,
                "过量转盾战后统一增加两层护盾，战中属性未提前增长")
            hpCheck(u, 80, 100, "护盾永久成长不额外回血")
        end
        do
            local u = makeUnit(12, { stacks = 100 }, 75)
            enableMechanisms(u)
            local enemy = { hp = 1, name = "冰冻回归敌人", _killedBy = u }
            SEM.apply(enemy, SEM.FROZEN, 2, u, {})
            enemy.hp = 0
            local oldMag = u.attrs:get(AD.MAG_ATK)
            unchangedDuringBattle(u, function()
                ETS.onEnemyDeath(enemy, { u }, { enemy })
            end, "击杀冰冻敌人")
            check(owned[12].extraTalent.iceStatues == 1 and #ETS.getIceStatues() == 1,
                "冰雕库存与实体在战中即时生成")
            check(ETS.getSnowFreezeBonus(ETS.getOwned(12), u) == 0.05,
                "新增冰雕不提前增加永久冰冻概率")
            check(ETS.absorbWithIceStatue(u, 37, {}) == 0
                and owned[12].extraTalent.iceStatues == 0 and #ETS.getIceStatues() == 0,
                "新冰雕当场可消费挡伤")
            ETS.flush()
            check(owned[12].extraTalent.stacks == 101 and owned[12].extraTalent.iceStatues == 0
                and math.abs(u.attrs:get(AD.MAG_ATK) - oldMag - 0.2) < 1e-9,
                "成长 delta 不覆盖已消费冰雕，也不复生成冰雕")
            SEM.removeUnit(enemy)
        end
        do
            local u = makeUnit(13, { stacks = 100, splitKills = 7 }, 75)
            enableMechanisms(u)
            local enemy = { hp = 0, _killedBy = u, _killedByRicochet = true }
            local oldAtk = u.attrs:get(AD.PHYS_ATK)
            unchangedDuringBattle(u, function()
                ETS.onEnemyDeath(enemy, { u }, { enemy })
            end, "弹射击杀")
            check(owned[13].extraTalent.splitKills == 8
                and ETS.getExtraBounces(ETS.getOwned(13), u) == 1,
                "分裂击杀机制即时跨8层阈值，额外弹射当场可用")
            ETS.flush()
            check(owned[13].extraTalent.stacks == 102 and owned[13].extraTalent.splitKills == 8
                and math.abs(u.attrs:get(AD.PHYS_ATK) - oldAtk - 0.5) < 1e-9,
                "弹射永久两层只在 flush 生效，分裂机制不重复计数")
        end

        -- 7) 发卡计数战后持久化；票当场可用，圣核读取存量卡数+本场待结算卡数。
        do
            local u = makeUnit(15, { stacks = 10, issuedCards = 2 }, 110,
                { [AD.MAX_HP] = 100, [AD.MAG_ATK] = 10 })
            enableMechanisms(u)
            local saved = { heroId = 301, name = "票回归队友", hp = 0, maxHp = 80 }
            local other = { heroId = 302, name = "另一票回归队友", hp = 80, maxHp = 80 }
            local beforeRate = ETS.getReviveRateBonus(ETS.getOwned(15), u)
            unchangedDuringBattle(u, function()
                ETS.onSuccessfulRevive(u, saved)
                ETS.onSuccessfulRevive(u, other)
            end, "两次成功救援")
            check(owned[15].extraTalent.stacks == 10 and owned[15].extraTalent.issuedCards == 2
                and ETS.mountedState().pendingGrowth[15].stacks == 2
                and ETS.mountedState().pendingGrowth[15].issuedCards == 2,
                "stacks/issuedCards均仅累计 pending，拥有数据与正式成长不提前变化")
            check(ETS.getReviveRateBonus(ETS.getOwned(15), u) == beforeRate
                and owned[15].extraTalent.tickets["301"] and owned[15].extraTalent.tickets["302"],
                "永久复活概率不提前增长，两张救援票仍即时入库存")
            check(ETS.tryTicketRevive(saved, { u }, function() end) and saved.hp == 80
                and owned[15].extraTalent.tickets["301"] == nil,
                "新票当场可使用且立即从最新 owned 消费")
            unchangedDuringBattle(u, function() ETS.update(100) end, "救援机制定时保存")
            check(roster[15].extraTalent.issuedCards == 2 and roster[15].extraTalent.stacks == 10
                and roster[15].extraTalent.tickets["301"] == nil,
                "定时同步只保存票消费，不提前持久化卡数/永久层")
            u.hp, u.attrs.final[AD.HP] = 0, 0
            local enemy, deadEnemy = { hp = 100 }, { hp = 0 }
            ---@type table[]
            local hits = {}
            local function dealDamage(target, damage, enemyFlag, prefix, color, opts)
                hits[#hits + 1] = { target = target, damage = damage, options = opts }
            end
            ETS.onLoverDeathNuke(u, { u }, { enemy, deadEnemy }, dealDamage)
            check(#hits == 1 and hits[1].target == enemy and hits[1].damage == 24
                and hits[1].options.instantDamage and hits[1].options.statCategory == "magical",
                "未flush圣核使用存量2+本场2张卡，即时造成24且不攻击死敌")
            ETS.flush()
            hpCheck(u, 0, 124, "救援成长结算增加上限但绝不复活已阵亡爱人")
            check(owned[15].extraTalent.stacks == 12 and owned[15].extraTalent.issuedCards == 4
                and owned[15].extraTalent.tickets["301"] == nil
                and owned[15].extraTalent.tickets["302"],
                "战后统一提交发卡与生命层，保留票消费/其他未消费票")
            hits = {}
            ETS.onLoverDeathNuke(u, { u }, { enemy }, dealDamage)
            check(#hits == 1 and hits[1].damage == 24,
                "flush后圣核同为4张卡，不将已提交pending重复计算")
            local beforePatch, beforeBatch, beforeSent = patchCalls, batchCalls, #sent
            ETS.flush()
            check(owned[15].extraTalent.issuedCards == 4 and patchCalls == beforePatch
                and batchCalls == beforeBatch and #sent == beforeSent,
                "发卡批结算幂等，重复flush不重复卡数/同步")
        end

        -- 8) 两条战线同英雄账本隔离；轮流结算均基于最新owned，只刷新本战线单位。
        do
            local stateA, stateB = ETS.newState(), ETS.newState()
            local uA = makeUnit(1, { stacks = 100 }, 150)
            local attrsB = UA.create({ [AD.MAX_HP] = 100 })
            ETS.applyToAttrs(1, attrsB, owned[1].extraTalent, owned[1].awakening)
            attrsB:fillHp()
            attrsB:recalc()
            attrsB.final[AD.HP] = 140
            local uB = attrsB:toBattleUnit("战线B成长单位", 1)
            uB.heroId, uB.awakeningNodes = 1, owned[1].awakening
            ETS.mount(stateA)
            unchangedDuringBattle(uA, function() kill(uA) end, "战线A击杀")
            ETS.mount(stateB)
            unchangedDuringBattle(uB, function() kill(uB); kill(uB) end, "战线B两击杀")
            check(stateA.pendingGrowth ~= stateB.pendingGrowth
                and stateA.pendingGrowth[1].stacks == 1 and stateB.pendingGrowth[1].stacks == 2,
                "两个ETS state独立累计，不共享同英雄pending表")
            ETS.flush()
            hpCheck(uB, 142, 202, "仅结算战线B的两层与单位血量")
            hpCheck(uA, 150, 200, "战线B结算不提前刷新战线A单位")
            check(owned[1].extraTalent.stacks == 102 and stateA.pendingGrowth[1].stacks == 1
                and next(stateB.pendingGrowth) == nil, "B消费自己账本，A收益保留待结算")
            ETS.mount(stateA)
            ETS.flush()
            hpCheck(uA, 153, 203, "战线A结算基于最新102层+自身delta1")
            hpCheck(uB, 142, 202, "战线A结算不二次刷新战线B单位")
            check(owned[1].extraTalent.stacks == 103 and next(stateA.pendingGrowth) == nil,
                "两战线总收益恰好3层，不丢失或重复")
            ETS.mount(ETS.newState())
        end
        do
            local stateA, stateB = ETS.newState(), ETS.newState()
            local u = makeUnit(15, { issuedCards = 2 }, 90,
                { [AD.MAX_HP] = 100, [AD.MAG_ATK] = 10 })
            enableMechanisms(u)
            local saved = { heroId = 303, name = "跨战线票队友", hp = 0, maxHp = 80 }
            local enemy = { hp = 100 }
            local damageA, damageB = 0, 0
            ETS.mount(stateA)
            unchangedDuringBattle(u, function() ETS.onSuccessfulRevive(u, saved) end,
                "战线A发卡")
            ETS.onLoverDeathNuke(u, { u }, { enemy }, function(target, damage) damageA = damage end)
            ETS.mount(stateB)
            ETS.onLoverDeathNuke(u, { u }, { enemy }, function(target, damage) damageB = damage end)
            check(damageA == 18 and damageB == 12,
                "圣核只读取当前state待结算卡数，B不借用A新卡")
            check(ETS.tryTicketRevive(saved, { u }, function() end), "战线B可消费共享最新owned的A新票")
            ETS.mount(stateA)
            ETS.update(100) -- A dirty 内仍是发票旧快照，不可把 B 已消费的票写回。
            check(owned[15].extraTalent.tickets["303"] == nil
                and roster[15].extraTalent.tickets["303"] == nil
                and owned[15].extraTalent.issuedCards == 2,
                "暂停战线旧dirty定时保存不覆盖另一战线消费，也不提前入账发卡")
            ETS.flush()
            check(owned[15].extraTalent.issuedCards == 3 and owned[15].extraTalent.stacks == 1
                and owned[15].extraTalent.tickets["303"] == nil,
                "A发卡delta结算保留B票消费")
            ETS.mount(stateB)
            ETS.flush()
            check(owned[15].extraTalent.issuedCards == 3 and owned[15].extraTalent.tickets["303"] == nil,
                "B旧机制dirty flush仍使用最新owned，不还原旧卡数或票")
            ETS.mount(ETS.newState())
        end

        -- 9) 清档丢弃当前账本，包含单位引用/机制dirty；另一state账本不受误清。
        do
            local stateA, stateB = ETS.newState(), ETS.newState()
            local u = makeUnit(15, { stacks = 10, issuedCards = 2 }, 110)
            enableMechanisms(u)
            local saved = { heroId = 304, name = "清档票队友" }
            ETS.mount(stateA)
            unchangedDuringBattle(u, function() ETS.onSuccessfulRevive(u, saved) end, "清档前A救援")
            ETS.mount(stateB)
            unchangedDuringBattle(u, function() ETS.onSuccessfulRevive(u, saved) end, "清档前B救援")
            ETS.mount(stateA)
            ETS.discard()
            check(next(stateA.pendingGrowth) == nil and next(stateA.growthUnits) == nil
                and next(stateA.dirty) == nil and stateB.pendingGrowth[15].stacks == 1,
                "discard清空当前state三类账本，不误清另一个state")
            ETS.mount(stateB)
            ETS.discard() -- 实际清档会逐战线mount/discard，防旧收益污染新档。
            owned[15].extraTalent = ETS.normalize({})
            roster[15] = {}
            local beforePatch, beforeBatch, beforeSent = patchCalls, batchCalls, #sent
            ETS.update(100)
            ETS.flush()
            ETS.mount(stateA)
            ETS.update(100)
            ETS.flush()
            check(owned[15].extraTalent.stacks == 0 and owned[15].extraTalent.issuedCards == 0
                and next(owned[15].extraTalent.tickets) == nil and roster[15].extraTalent == nil
                and patchCalls == beforePatch and batchCalls == beforeBatch and #sent == beforeSent,
                "清档后update/flush不把旧成长/旧票/旧dirty写入新档")
            hpCheck(u, 110, 120, "discard不会把已丢弃成长应用到旧战斗单位")
            ETS.mount(ETS.newState())
        end
        ETS.flush()
    end)
    -- 不论测试成功/异常，都恢复全局函数及共享模块的原挂载状态。
    if etsForCleanup.mount then
        etsForCleanup.discard()
        etsForCleanup.mount(originalEtsState)
    end
    SEM.mount(originalSemState)
    require = originalRequire
    check(require == originalRequire, "测试结束恢复 require，替身未泄漏到后续运行")
    check(SEM.mountedState() == originalSemState, "测试结束恢复 SEM 原状态")
    if etsForCleanup.mountedState then
        check(etsForCleanup.mountedState() == originalEtsState, "测试结束恢复 ETS 原状态")
    end
    if not ok then check(false, "测试异常：" .. tostring(err)) end
    if #failures == 0 then
        print("[extra_talent_hp_lifecycle_test] ALL PASS assertions=" .. assertions)
    else
        log:Write(LOG_ERROR, "[extra_talent_hp_lifecycle_test] FAILURES=" .. #failures
            .. " assertions=" .. assertions)
    end
    engine:Exit()
end
