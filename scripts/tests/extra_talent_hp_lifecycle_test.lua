-- ============================================================================
-- 追加技生命成长生命周期回归：真实 UnitAttributes + ETS 公共钩子，不写真实存档。
-- 跑法：./.cli/UrhoXRuntime tests/extra_talent_hp_lifecycle_test.lua \
--       -tapcode_dir=/workspace -tool_mode -graphicsheadless
-- 只包装 require 拦截三项外部依赖，结束时恢复；兼容 Runtime 绕过 package.loaded。
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
    ---@type table<number, ExtraTalentHpOwned>
    local owned = {}
    ---@type table<number, table>
    local roster = {}
    ---@type table[]
    local sent = {}
    local patchCalls = 0
    local panelMock = {
        getOwnedHero = function(heroId) return owned[heroId] end,
        patchExtraTalent = function(heroId, extra)
            patchCalls = patchCalls + 1
            owned[heroId].extraTalent = extra
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
        return originalRequire(name)
    end
    local ok, err = pcall(function()
        local ETS = originalRequire("systems.ExtraTalentSystem")

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

        -- 2) 实际击杀 commit：满血/残血/濒死、新成长/存量成长都只补新增上限。
        for _, case in ipairs({
            { stacks = 0, hp = 100, expected = 101 },
            { stacks = 0, hp = 35, expected = 36 },
            { stacks = 100, hp = 200, expected = 201 },
            { stacks = 100, hp = 150, expected = 151 },
            { stacks = 100, hp = 1, expected = 2 },
        }) do
            local u = makeUnit(1, { stacks = case.stacks }, case.hp)
            kill(u)
            hpCheck(u, case.expected, 101 + case.stacks,
                "击杀：旧层" .. case.stacks .. " 旧HP" .. case.hp .. "仅补新增1生命")
            check(owned[1].extraTalent.stacks == case.stacks + 1, "真实击杀仍保存正确成长层数")
        end
        do
            local u = makeUnit(1, { stacks = 100 }, 150,
                { [AD.MAX_HP] = 100, [AD.HP_BONUS] = 50 })
            kill(u)
            hpCheck(u, 152, 302, "击杀：使用最终上限差额（生命倍率/整数舍入后增加2）")
        end
        do
            local u = makeUnit(4, { stacks = 100 }, 140)
            kill(u)
            hpCheck(u, 141, 151, "半点生命成长第一次舍入新增1")
            kill(u)
            hpCheck(u, 141, 151, "半点生命成长第二次上限未变不再回血")
        end
        do
            local u = makeUnit(3, { stacks = 100 }, 75)
            local beforeAtk = u.attrs:get(AD.PHYS_ATK)
            kill(u)
            hpCheck(u, 75, 100, "非生命成长击杀不额外回血")
            check(math.abs(u.attrs:get(AD.PHYS_ATK) - beforeAtk - 0.2) < 0.000001,
                "非生命成长仍按原倍率提高物攻")
        end

        -- 3) attrs 是来源；上限缓存陈旧/缺失不会重复补存量成长，下降也必须同步。
        do
            local u = makeUnit(1, { stacks = 100 }, 150)
            u.hp, u.maxHp = 10, 100
            kill(u)
            hpCheck(u, 151, 201, "陈旧 unit 缓存不吞血也不把存量成长重复补血")
            u.hp, u.maxHp = nil, nil
            kill(u)
            hpCheck(u, 152, 202, "缺失 unit 缓存仍按 attrs 差额补血并恢复同步")
        end
        for _, hp in ipairs({ 180, 70 }) do
            local u = makeUnit(1, { stacks = 100 }, hp)
            owned[1].extraTalent = ETS.normalize({ stacks = 10 })
            kill(u) -- 存档回落后真实击杀到11层，最终上限111。
            hpCheck(u, math.min(hp, 111), 111, "commit 上限下降只夹血并同步（旧HP" .. hp .. "）")
        end

        -- 4) 分摊致死成长和死后击杀归因都不得变相复活，仍应保存成长、同步上限。
        do
            local u = makeUnit(10, {}, 0)
            ETS.onShareFatal(u)
            hpCheck(u, 0, 103, "真实分摊致死：0→0，不随上限+3复活")
            ETS.onShareFatal(u)
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
            ETS.onShareFatal(u)
            hpCheck(u, 0, 403, "存量分摊成长：陈旧缓存活血也不得使 attrs 死亡复活")
        end
        do
            local u = makeUnit(10, { shareCount = 10 }, 80)
            u.hp = 0 -- unit 已记录死亡，但 attrs 还未来得及同步。
            ETS.onShareFatal(u)
            hpCheck(u, 0, 133, "分摊死亡同步窗口：unit为0、attrs仍活血也不得复活")
        end
        do
            local u = makeUnit(1, { stacks = 100 }, 150)
            u.hp = 0
            kill(u)
            hpCheck(u, 0, 201, "延迟击杀死亡同步窗口：unit为0优先死亡保护")
        end
        do
            local u = makeUnit(1, { stacks = 100 }, 0)
            kill(u)
            hpCheck(u, 0, 201, "阵亡杀手延迟击杀归因仅增加上限，不复活")
            owned[1].extraTalent = ETS.normalize({ stacks = 10 })
            kill(u)
            hpCheck(u, 0, 111, "阵亡单位上限下降也同步且保持0")
        end
        ETS.flush()
    end)
    -- 不论测试成功/异常，都恢复唯一改动的全局函数。
    require = originalRequire
    check(require == originalRequire, "测试结束恢复 require，替身未泄漏到后续运行")
    if not ok then check(false, "测试异常：" .. tostring(err)) end
    if #failures == 0 then
        print("[extra_talent_hp_lifecycle_test] ALL PASS assertions=" .. assertions)
    else
        log:Write(LOG_ERROR, "[extra_talent_hp_lifecycle_test] FAILURES=" .. #failures
            .. " assertions=" .. assertions)
    end
    engine:Exit()
end
