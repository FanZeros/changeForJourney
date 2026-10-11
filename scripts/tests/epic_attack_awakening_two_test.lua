-- 史诗攻击觉醒Ⅱ：只读历史成长、冻结单轮、真实TAL/UA/BC/投射物与击杀归因。
-- 独立Runtime入口；owned只在内存，File/FileSystem/fileSystem/GetFileSystem四接口封闭。
local assertions, failures = 0, 0
local function check(value, message)
    assertions = assertions + 1
    if not value then failures = failures + 1; print("[史诗攻击Ⅱ][FAIL] " .. message) end
end
local function near(a, b) return math.abs(a - b) < 1e-8 end
local function awake(stage)
    local nodes = { _awk3Migrated = true }
    for i = 1, stage do nodes[i] = true end
    return nodes
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, v in pairs(value) do out[key] = copy(v) end
    return out
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

function Start()
    local originalRequire = require
    local originals = { File = File, FileSystem = FileSystem, fileSystem = fileSystem, GetFileSystem = GetFileSystem }
    local storage, sends, patches = 0, 0, 0
    local function denyIO() storage = storage + 1; error("史诗攻击Ⅱ专项禁止File/FS访问") end
    rawset(_G, "File", denyIO); rawset(_G, "FileSystem", denyIO); rawset(_G, "GetFileSystem", denyIO)
    rawset(_G, "fileSystem", setmetatable({}, { __index = function() return denyIO end }))
    local owned = {}
    local mocks = {
        ["ui.character.panel.CharacterPanel"] = {
            getOwnedHero = function(id) return owned[id] end,
            patchExtraTalent = function(id, extra)
                patches = patches + 1; assert(owned[id]); owned[id].extraTalent = extra
            end,
            finishExtraTalentBatch = function() end,
        },
        ["runtime.GameAction"] = { sendAction = function() sends = sends + 1 end },
        ["runtime.ClientDispatcher"] = { get = function(key) if key == "heroes" then return { roster = owned } end end },
    }
    rawset(_G, "require", function(name) return mocks[name] or originalRequire(name) end)
    local nativeRandom = math.random
    local ok, err = pcall(function()
        local AC = require("config.AwakeningConfig")
        local AD = require("systems.AttributeDef")
        local CF = require("systems.CombatFormula")
        local HC = require("config.HeroConfig")
        local UA = require("systems.UnitAttributes")
        local ETS = require("systems.ExtraTalentSystem")
        local TAL = require("systems.TalentManager")
        local SEM = require("systems.StatusEffectManager")
        local BC = require("ui.battle.combat.BattleCombat")
        local PS = require("ui.battle.combat.ProjectileSystem")
        local cjson = require("cjson")
        local deps = {
            AD = AD, CF = CF, SEM = SEM, talentLog = function() end,
            hasAwaken = function(u, n) return AC.hasNode(u.awakeningNodes, n) end,
            hasAwakenStage = function(u, n) return AC.hasStage(u.awakeningNodes, n) end,
            getState = function(u) return TAL.mountedUnitStates()[u] end,
            getBattleRefs = function() return TAL.mountedState() end,
        }
        local suhua = require("systems.talents.TalentSuhua").bind(deps)
        local rosa = require("systems.talents.TalentRosa").bind(deps)
        local alex = require("systems.talents.TalentAlex").bind(deps)
        local sera = require("systems.talents.TalentSera").bind(deps)
        local function hero(id, stage, extra, disabled)
            owned[id] = { level = 1, awakening = awake(stage), extraTalent = ETS.normalize(extra) }
            local input = disabled and false
            if not disabled then input = owned[id].extraTalent end
            return assert(HC.createHero(id, 1, nil, awake(stage), input, { litNodes = {}, silent = true }))
        end
        local function enemy(hp)
            local attrs = UA.create({ [AD.MAX_HP] = hp or 10000000, [AD.ARMOR] = 125,
                armorType = AD.ARMOR_PLATE })
            attrs:fillHp()
            local u = attrs:toBattleUnit("隔离敌人", 1)
            u.heroId = 0
            return u
        end
        local function mount(a, enemies)
            ETS.mount(ETS.newState()); TAL.mount(TAL.newBattleRefs()); TAL.mountUnitStates(TAL.newUnitStates())
            SEM.reset(); BC.reset(); PS.reset()
            TAL.onBattleStart({ a }, enemies)
            return TAL.mountedUnitStates()[a]
        end
        local function stableGrowth(id, before, label)
            check(equal(owned[id].extraTalent, before), label .. "历史字段不写回")
            check(next(ETS.mountedState().pendingGrowth) == nil, label .. "无虚构成长")
            check(next(ETS.mountedState().dirty) == nil, label .. "无存档dirty")
        end
        local function hitRecord(a, records, callback)
            return function(tgt, damage, side, prefix, color, meta)
                records[#records + 1] = { target = tgt, damage = damage, prefix = prefix, meta = meta }
                check(not side and meta.sourceAttacker == a, "正确己方source/敌方方向 " .. prefix)
                check(type(damage) == "number" and damage > 0 and damage == math.floor(damage), "正整数伤害 " .. prefix)
                if callback then callback(tgt, damage, side, prefix, color, meta) end
            end
        end
        local function directSlash(a, s, enemies, records, callback)
            s.atkCount = AC.hasStage(a.awakeningNodes, 1) and 2 or 3
            suhua.runSuhuaNightSlash(a, s, enemies[1], true, enemies, hitRecord(a, records, callback))
        end

        -- Ⅰ通宵斩击杀记2 stacks；完整斩影门槛/50击杀成长边界与封顶。
        for stage = 0, 3 do
            for _, shadows in ipairs({ 0, 1, 2, 3, 4, 40 }) do
                for _, stacks in ipairs({ 0, 99, 100, 199, 200, 299, 300, 399, 400, 100000 }) do
                    local a = hero(11, stage, { stacks = stacks, slashShadows = shadows })
                    local enemies = { enemy(), enemy(), enemy(), enemy() }
                    local s = mount(a, enemies)
                    local before, records = copy(owned[11].extraTalent), {}
                    math.randomseed(113)
                    directSlash(a, s, enemies, records)
                    local normal = stage >= 2 and 3 or 2
                    local extra = stage >= 2 and math.min(2, math.floor(shadows / 2)) or 0
                    local ratio = 0.5 * (1 + (stage >= 1 and math.min(0.5, math.floor(stacks / 100) * 0.125) or 0))
                    check(#records == normal + extra, "斩影门槛/最多2追斩 stage=" .. stage)
                    for index = 1, normal do
                        check(records[index].prefix == "通宵斩" and records[index].meta.isNightSlash
                            and records[index].meta.critEligible, "旧普通斩数量/精确成长归因保留")
                    end
                    for index = 1, extra do
                        local original, follow = records[index], records[normal + index]
                        check(follow.prefix == "斩影追斩" and follow.target == original.target
                            and follow.damage == math.max(1, math.floor(original.damage * ratio + 0.5)), "同目标单斩50%→75%精确复制")
                        check(follow.meta.isCrit == original.meta.isCrit and follow.meta.atkType == original.meta.atkType
                            and follow.meta.isNightSlash and not follow.meta.critEligible, "追斩暴击/元素不重抽且保旧击杀归因")
                    end
                    stableGrowth(11, before, "追斩")
                end
            end
        end
        -- 真CF.rollCrit次数只等于普通斩数；重入普通钩子不能增加计数或递归追斩。
        do
            local a = hero(11, 2, { stacks = 100, slashShadows = 4 })
            local enemies = { enemy() }; local s = mount(a, enemies)
            local originalRoll, rolls, records = CF.rollCrit, 0, {}
            CF.rollCrit = function(rate, damage)
                rolls = rolls + 1; return originalRoll(rate, damage)
            end
            local innerOK, innerError = pcall(function()
                directSlash(a, s, enemies, records, function(_, _, _, prefix)
                    if prefix == "斩影追斩" then
                        suhua.runSuhuaNightSlash(a, s, enemies[1], true, enemies, function() check(false, "追斩不得递归发射") end)
                        TAL.onComboAttack(a, enemies[1], true, enemies, function() check(false, "重入连击不得递归") end,
                            { totalDamage = 100, category = "physical" })
                    end
                    owned[11].extraTalent.slashShadows, owned[11].extraTalent.stacks = 4, 100000
                end)
            end)
            CF.rollCrit = originalRoll
            assert(innerOK, innerError)
            check(rolls == 3 and #records == 5 and s.atkCount == 3, "追斩不重roll/不充攻击计数/不递归")
            check(records[4].damage == math.floor(records[1].damage * 0.5625 + 0.5), "同轮成长变化不改变冻结比例")
            check(s.suhuaSlashActive == nil, "斩轮临时重入锁释放")
            local thrown = pcall(function() directSlash(a, s, enemies, {}, function() error("伤害回调测试异常") end) end)
            check(not thrown and s.suhuaSlashActive == nil, "伤害回调异常仍清自己重入锁")
        end

        -- 弹射各跳在旧递增倍率上+0.10+每50击杀0.05（成长最多0.20）。
        for stage = 0, 3 do
            for _, kills in ipairs({ 0, 7, 8, 39, 40, 49, 50, 99, 100, 149, 150, 199, 200, 99999 }) do
                local a = hero(13, stage, { splitKills = kills })
                local enemies = { enemy(), enemy(), enemy(), enemy(), enemy(), enemy(), enemy(), enemy(), enemy() }
                local s = mount(a, enemies); local before, records = copy(owned[13].extraTalent), {}
                local result = { totalDamage = 1000, isCrit = true, category = "physical", atkType = AD.ATK_PIERCE }
                local callback = hitRecord(a, records, function(_, _, _, _, _, meta) meta.onProjectileLand() end)
                rosa.tryRosaBounce(a, s, enemies[1], true, enemies, callback, result)
                local count = (stage == 3 and 3 or stage >= 1 and 2 or 1)
                    + (stage >= 2 and math.min(5, math.floor(kills / 8)) or 0)
                check(#records == count, "弹射保旧基础次数与每8击杀次数")
                local seen = { [enemies[1]] = true }
                for index, hit in ipairs(records) do
                    local coeff = 0.5 + (stage >= 2 and index * 0.15 + 0.10 + math.min(0.20, math.floor(kills / 50) * 0.05) or 0)
                    check(hit.damage == math.floor(1000 * coeff + 0.5), "弹射逐跳精确倍率 stage=" .. stage)
                    check(hit.meta.isRicochet and hit.meta.isCrit and hit.meta.atkType == AD.ATK_PIERCE
                        and hit.meta.statCategory == "physical" and not hit.meta.critEligible, "弹射复制暴击/元素/类别")
                    if stage <= 2 then check(not seen[hit.target], "Ⅱ弹射仍不重复目标") end
                    seen[hit.target] = true
                end
                stableGrowth(13, before, "弹射")
            end
        end
        do
            local a = hero(13, 2, { splitKills = 50 }); local enemies = { enemy(), enemy(), enemy(), enemy() }
            local s = mount(a, enemies); local records = {}
            local result = { totalDamage = 1000, isCrit = true, category = "physical", atkType = AD.ATK_PIERCE }
            rosa.tryRosaBounce(a, s, enemies[1], true, enemies, hitRecord(a, records), result)
            local firstLand = records[1].meta.onProjectileLand
            result.totalDamage, result.isCrit, result.atkType = 1, false, AD.ATK_FIRE
            owned[13].extraTalent.splitKills = 100000
            firstLand(); firstLand()
            check(#records == 2 and records[2].damage == 950 and records[2].meta.isCrit
                and records[2].meta.atkType == AD.ATK_PIERCE, "弹射全链冻结且重复回调幂等")
            local replacement = enemy()
            TAL.mountedState().bEnemies = { replacement }
            records[2].meta.onProjectileLand()
            check(#records == 3 and records[3].target == replacement and records[3].damage == 1100,
                "同refs换敌表弹射使用当前活敌，不借旧表")
        end

        -- 氮气前五次只叠速；满层后的下一次复制原氮气×(1.20+成长)，贯穿取强化后60%。
        for stage = 0, 3 do
            for _, kills in ipairs({ 0, 39, 40, 79, 80, 119, 120, 159, 160, 100000 }) do
                for _, stacks in ipairs({ 0, 4, 5 }) do
                    local a = hero(21, stage, { nitroKills = kills }); local enemies = { enemy(), enemy() }
                    local s = mount(a, enemies); s.nitroStacks, s.epicNitroStacks = stacks, stacks
                    local before, records = copy(owned[21].extraTalent), {}
                    math.random = function(low) return low or 0 end
                    alex.tryAlexSilverFlash(a, s, enemies[1], true, hitRecord(a, records),
                        { totalDamage = 1000, isCrit = true, category = "physical", atkType = AD.ATK_SLASH })
                    math.random = nativeRandom
                    local base = math.floor(1000 * (stage >= 1 and 1.8 or 1.5) + 0.5)
                    if stage == 3 then base = math.floor(base * (1 + a.attrs:get(AD.MAG_DMG_BONUS) / 100) + 0.5) end
                    local factor = stage >= 2 and stacks >= 5 and 1.20 + math.min(0.20, math.floor(kills / 40) * 0.05) or 1
                    local expected = math.floor(base * factor + 0.5)
                    check(#records == 2 and records[1].damage == expected
                        and records[2].damage == math.floor(expected * 0.60 + 0.5), "氮气/贯穿冻结倍率与40击杀边界")
                    for _, hit in ipairs(records) do
                        check(hit.meta.statCategory == "magical" and hit.meta.atkType == AD.ATK_LIGHTNING
                            and hit.meta.isCrit and not hit.meta.critEligible and hit.meta.instantDamage, "真实氮气闪电来源/复制暴击不重抽")
                    end
                    check(s.nitroStacks == math.min(5, stacks + 1)
                        and a.attrs.modifiers.talent_nitro_speed[1].flat == math.min(5, stacks + 1) * 8, "旧氮气8%×5叠速保留")
                    check(SEM.has(enemies[1], SEM.FROZEN), "旧麻痹保留")
                    stableGrowth(21, before, "氮气")
                end
            end
        end
        do
            for _, stage in ipairs({ 1, 2 }) do
                local a = hero(21, stage, { nitroKills = 40 }); local enemies = { enemy(), enemy() }
                local s = mount(a, enemies); s.nitroStacks = 5; s.epicNitroStacks = 5
                local n = 0
                math.random = function(low) if low then return low end; return 0.9 end
                alex.tryAlexSilverFlash(a, s, enemies[1], true, function() n = n + 1 end, { totalDamage = 1000 })
                math.random = nativeRandom
                check(n == 0 and s.nitroStacks == 5, "Ⅱ不修改原失败触发概率")
            end
        end

        -- 入口refs仍为上轮死表时以实际targetList为准；只跟进入链后真正替换的refs。
        for stage = 0, 3 do
            for _, allySide in ipairs({ true, false }) do
                local a = hero(13, stage, { splitKills = 50 }); local stale = { enemy(1) }
                local s = mount(a, stale); stale[1].hp = 0
                local fresh = { enemy(), enemy(), enemy(), enemy() }; local records = {}
                if not allySide then TAL.mountedState().bAllies = stale end
                rosa.tryRosaBounce(a, s, fresh[1], allySide, fresh, function(tgt, damage, side, prefix, _, meta)
                    records[#records + 1] = tgt
                    check(side == not allySide and tgt ~= stale[1], "过期refs不选死敌，两方向阵营正确")
                    check((meta.epicBounceTargetList == fresh) == (stage >= 2), "动态targetList meta仅新Ⅱ/Ⅲ")
                    meta.onProjectileLand()
                end, { totalDamage = 1000, category = "physical", atkType = AD.ATK_PIERCE })
                check(#records == (stage == 3 and 8 or stage == 2 and 3 or stage == 1 and 2 or 1),
                    "过期refs+实际新表有效弹射，Ⅲ仍按旧规则允许重复")
            end
        end
        -- 同对象同s重开不借原nitroStacks=5：本场成功触发六次才在第六次受益。
        do
            local a = hero(21, 2, { nitroKills = 160 }); local enemies = { enemy(), enemy() }; local s = mount(a, enemies)
            s.nitroStacks = 5
            for battle = 1, 2 do
                if battle == 2 then TAL.onBattleStart({ a }, enemies) end
                check(s.nitroStacks == 5 and s.epicNitroStacks == 0, "重开仅清新本场计数，不改原叠速")
                for trigger = 1, 6 do
                    local records = {}; math.random = function(low) return low or 0 end
                    alex.tryAlexSilverFlash(a, s, enemies[1], true, hitRecord(a, records), { totalDamage = 1000 })
                    math.random = nativeRandom
                    check(records[1].damage == (trigger == 6 and 2520 or 1800)
                        and s.epicNitroStacks == math.min(5, trigger), "本场第六次才强化 battle=" .. battle .. " trigger=" .. trigger)
                end
            end
        end
        -- 小黑子正常门槛启动时每40成长多1发，最多4；不影响旧预存、门槛和Ⅰ效果。
        for stage = 0, 3 do
            for _, kills in ipairs({ 0, 39, 40, 79, 80, 119, 120, 159, 160, 100000 }) do
                local a = hero(22, stage, { gatlingKills = kills }); local enemies = { enemy() }
                local s = mount(a, enemies); local before = copy(owned[22].extraTalent)
                local oldStart = stage >= 2 and math.min(10, math.floor(kills / 8)) or 0
                check(s.machineGunShotsLeft == 0 and (a._etsGatlingStart or 0) == oldStart,
                    "原开局预存延后flag最多10且不带新增4发")
                s.machineGunShotsLeft, s.machineGunInBurst = 0, false
                local interval = math.max(8, (stage >= 2 and 15 or stage >= 1 and 18 or 20)
                    - (stage >= 1 and math.min(12, kills * 0.05) or 0))
                local count = math.ceil(interval - 1e-9)
                for _ = 1, count - 1 do sera.tickSeraMachineGunCount(a, s) end
                check(s.machineGunShotsLeft == 0, "原门槛之前不提前出弹")
                sera.tickSeraMachineGunCount(a, s)
                local expected = (stage >= 1 and 12 or 10) + (stage >= 2 and math.min(4, math.floor(kills / 40)) or 0)
                check(s.machineGunShotsLeft == expected and near(s.machineGunProgress, count - interval), "正常轮固定发数与门槛小数余量")
                check((a.attrs.modifiers.sera_burst_pen ~= nil) == (stage >= 2)
                    and (a.attrs.modifiers.sera_burst_speed ~= nil) == (stage >= 2), "旧穿透/连射攻速保留")
                stableGrowth(22, before, "连射")
                owned[22].extraTalent.gatlingKills = 100000
                check(s.machineGunShotsLeft == expected, "正在连射不因成长写入续弹")
            end
        end

        -- 明确单位快照优先owned，同ID高成长不泄漏到禁ETS单位，也不借wrong hero owned。
        for _, id in ipairs({ 11, 13, 21, 22 }) do
            local a = hero(id, 2, { stacks = 100000, slashShadows = 4, splitKills = 100000,
                nitroKills = 100000, gatlingKills = 100000 })
            a._epicAwakeningGrowth = ETS.normalize(nil)
            local enemies = { enemy(), enemy(), enemy(), enemy() }; local s = mount(a, enemies); local records = {}
            if id == 11 then
                directSlash(a, s, enemies, records); check(#records == 3, "11实例零库存不借owned")
            elseif id == 13 then
                rosa.tryRosaBounce(a, s, enemies[1], true, enemies,
                    hitRecord(a, records, function(_, _, _, _, _, meta) meta.onProjectileLand() end), { totalDamage = 1000 })
                check(#records == 3 and records[1].damage == 750, "13实例零新增成长不借owned，旧次数仍沿owned")
            elseif id == 21 then
                s.nitroStacks = 5; s.epicNitroStacks = 5; math.random = function(low) return low or 0 end
                alex.tryAlexSilverFlash(a, s, enemies[1], true, hitRecord(a, records), { totalDamage = 1000 })
                math.random = nativeRandom
                check(records[1].damage == 2160, "21新增增伤读取实例零成长")
            else
                s.machineGunProgress = 7; sera.tickSeraMachineGunCount(a, s)
                check(s.machineGunShotsLeft == 12, "22新增弹数读取实例零成长")
            end
            a._etsDisabled = true; records = {}; s = mount(a, enemies)
            if id == 11 then
                directSlash(a, s, enemies, records); check(#records == 3, "11禁ETS仍保旧Ⅱ普通斩")
            elseif id == 13 then
                rosa.tryRosaBounce(a, s, enemies[1], true, enemies,
                    hitRecord(a, records, function(_, _, _, _, _, meta) meta.onProjectileLand() end), { totalDamage = 1000 })
                check(#records == 2 and records[1].damage == 650, "13禁ETS无新系数与额外弹数")
            elseif id == 21 then
                s.nitroStacks = 5; s.epicNitroStacks = 5; math.random = function(low) return low or 0 end
                alex.tryAlexSilverFlash(a, s, enemies[1], true, hitRecord(a, records), { totalDamage = 1000 })
                math.random = nativeRandom; check(records[1].damage == 1800, "21禁ETS无满层新增倍率")
            else
                s.machineGunProgress = 14; sera.tickSeraMachineGunCount(a, s)
                check(s.machineGunShotsLeft == 12, "22禁ETS无额外4弹/旧门槛保留")
            end
        end

        -- 通过真实HC输入验证零快照/高快照/默认owned刷新与调用方原表隔离。
        for _, id in ipairs({ 11, 13, 21, 22 }) do
            for _, explicitHigh in ipairs({ false, true }) do
                local high = ETS.normalize({ stacks = 400, slashShadows = 4, splitKills = 200,
                    nitroKills = 160, gatlingKills = 160 })
                local input = explicitHigh and high or ETS.normalize(nil)
                owned[id] = { awakening = awake(2), extraTalent = explicitHigh and ETS.normalize(nil) or high }
                local a = assert(HC.createHero(id, 1, nil, awake(2), input, { litNodes = {}, silent = true }))
                local enemies = { enemy(), enemy(), enemy(), enemy() }; local s = mount(a, enemies); local records = {}
                check(equal(ETS.getEpicGrowth(a), input), "真实HC显式成长优先owned hero=" .. id)
                input.stacks, input.slashShadows, input.splitKills, input.nitroKills, input.gatlingKills = 1, 1, 1, 1, 1
                check(ETS.getEpicGrowth(a).stacks == (explicitHigh and 400 or 0), "HC显式原表变更不改战斗快照")
                if id == 11 then
                    directSlash(a, s, enemies, records)
                    check(#records == (explicitHigh and 5 or 3), "真实HC显式斩影库存生效")
                elseif id == 13 then
                    rosa.tryRosaBounce(a, s, enemies[1], true, enemies, hitRecord(a, records), { totalDamage = 1000 })
                    check(records[1].damage == (explicitHigh and 950 or 750), "真实HC显式弹射成长系数生效")
                elseif id == 21 then
                    s.nitroStacks = 5; s.epicNitroStacks = 5; math.random = function(low) return low or 0 end
                    alex.tryAlexSilverFlash(a, s, enemies[1], true, hitRecord(a, records), { totalDamage = 1000 })
                    math.random = nativeRandom
                    check(records[1].damage == (explicitHigh and 2520 or 2160), "真实HC显式氮气成长生效")
                else
                    s.machineGunProgress = 14; sera.tickSeraMachineGunCount(a, s)
                    check(s.machineGunShotsLeft == (explicitHigh and 16 or 12), "真实HC显式课时只改变新弹数")
                end
            end
            owned[id] = { awakening = awake(2), extraTalent = ETS.normalize(nil) }
            local a = assert(HC.createHero(id, 1, nil, awake(2), nil, { litNodes = {}, silent = true }))
            check(a._epicAwakeningGrowth == nil and ETS.getEpicGrowth(a).stacks == 0, "HC nil没有伪造冻结零快照")
            owned[id].extraTalent.stacks = 100
            check(ETS.getEpicGrowth(a).stacks == 100, "nil实例读取最新已提交owned")
            local disabled = assert(HC.createHero(id, 1, nil, awake(2), false, { litNodes = {}, silent = true }))
            check(disabled._etsDisabled and equal(ETS.getEpicGrowth(disabled), ETS.normalize(nil)), "HC false不借账号成长")
        end

        -- 真实TAL接线：伤害回调reset/mount/同unit同refs开战停止旧普通斩/追斩/贯穿。
        for _, action in ipairs({ "reset", "mount", "restart", "unitStates" }) do
            for _, phase in ipairs({ "通宵斩", "斩影追斩" }) do
                local a = hero(11, 2, { slashShadows = 4 }); local enemies = { enemy() }; local s = mount(a, enemies)
                s.atkCount = 2; local hits, changed = 0, false
                TAL.onAfterAttack(a, enemies[1], { totalDamage = 1000, category = "physical" }, true, enemies,
                    function(_, _, _, prefix)
                        hits = hits + 1
                        if prefix == phase and not changed then
                            changed = true
                            if action == "reset" then TAL.reset()
                            elseif action == "mount" then TAL.mount(TAL.newBattleRefs())
                            elseif action == "unitStates" then TAL.mountUnitStates(TAL.newUnitStates())
                            else TAL.onBattleStart({ a }, enemies) end
                        end
                    end, { a })
                check(changed and hits == (phase == "通宵斩" and 1 or 4), "正式TAL回调立即停旧斩轮 " .. action .. phase)
            end
            local a = hero(21, 2, { nitroKills = 160 }); local enemies = { enemy(), enemy() }; local s = mount(a, enemies)
            s.nitroStacks = 5; s.epicNitroStacks = 5; local hits = 0
            math.random = function(low) return low or 0 end
            alex.tryAlexSilverFlash(a, s, enemies[1], true, function()
                hits = hits + 1
                if action == "reset" then TAL.reset()
                elseif action == "mount" then TAL.mount(TAL.newBattleRefs())
                elseif action == "unitStates" then TAL.mountUnitStates(TAL.newUnitStates())
                else TAL.onBattleStart({ a }, enemies) end
            end, { totalDamage = 1000 })
            math.random = nativeRandom
            check(hits == 1 and not SEM.has(enemies[1], SEM.FROZEN), "氮气回调换场不贯穿/施状态 " .. action)
            a = hero(13, 2, { splitKills = 200 }); enemies = { enemy(), enemy(), enemy(), enemy() }; s = mount(a, enemies)
            local records = {}
            TAL.onAfterAttack(a, enemies[1], { totalDamage = 1000, category = "physical" }, true, enemies,
                hitRecord(a, records), { a })
            if action == "reset" then TAL.reset()
            elseif action == "mount" then TAL.mount(TAL.newBattleRefs())
            elseif action == "unitStates" then TAL.mountUnitStates(TAL.newUnitStates())
            else TAL.onBattleStart({ a }, enemies) end
            records[1].meta.onProjectileLand()
            check(#records == 1, "正式TAL旧弹射回调取消 " .. action)
        end

        -- 真实performAttack六参天赋闭包：新Ⅱ弹射落地后换整表仍查新表位置并继续复制。
        do
            local a = hero(13, 2, { splitKills = 200 }); local enemies = { enemy(), enemy() }; mount(a, enemies)
            local allies, records, mainDamage = { a }, {}, 0
            local replacement = enemy()
            local nativeHit = {}
            BC.setContext({ getAllies = function() return allies end, getEnemies = function() return enemies end,
                onAttackHit = function(_, _, _, _, _, _, result, applyHit)
                    mainDamage = result.totalDamage
                    applyHit()
                end,
                onTalentDealDamage = function(source, tgt, _, _, prefix, applyDamage, meta)
                    records[#records + 1] = { target = tgt, damageBefore = tgt.hp, prefix = prefix, meta = meta }
                    nativeHit[#nativeHit + 1] = applyDamage
                end })
            math.randomseed(213)
            BC.performAttack(a, enemies, true)
            check(#records == 1 and mainDamage > 0 and records[1].meta.epicBounceTargetList == enemies,
                "真实六参闭包首跳动态列表meta")
            local first = records[1]
            nativeHit[1]()
            local actualFirst = first.damageBefore - first.target.hp
            local oldEnemies = enemies
            enemies = { replacement }
            TAL.mountedState().bEnemies = enemies
            first.meta.onProjectileLand()
            check(#records == 2 and records[2].target == replacement and records[2].meta.epicBounceTargetList == enemies,
                "真实六参闭包首跳land后查新敌表而非旧capture表")
            if nativeHit[2] then nativeHit[2]() end
            check(actualFirst == math.floor(mainDamage * 0.95 + 0.5)
                and replacement.hp == replacement.maxHp - math.floor(mainDamage * 1.10 + 0.5),
                "真实换表第二跳伤害落地/复制主包无二次公式")
            check(enemies ~= oldEnemies, "真实换表夹具保留独立旧表")
        end
        -- 真BC/PS投射物：普斩与复制追斩实际落地，真击杀走旧AG→pending→flush幂等。
        do
            local a = hero(11, 2, { stacks = 100, slashShadows = 4 }); local enemies = { enemy() }
            local s = mount(a, enemies); local records = {}; local allies = { a }
            BC.setContext({ getAllies = function() return allies end, getEnemies = function() return enemies end,
                onTalentDealDamage = function(source, tgt, x, y, prefix, applyDamage, meta)
                    BC.onTalentDealDamage(source, tgt, x, y, prefix, applyDamage, meta, allies, enemies)
                end })
            local beforeHp = enemies[1].hp
            directSlash(a, s, enemies, records, function(tgt, damage, side, prefix, color, meta)
                BC.dealTalentDamage(a, tgt, damage, side, prefix, color, meta, allies, enemies)
            end)
            check(#records == 5 and PS.getActiveCount() > 0, "真实追斩生成投射物")
            local total = 0; for _, hit in ipairs(records) do total = total + hit.damage end
            for _ = 1, 240 do PS.update(1 / 60) end
            check(PS.getActiveCount() == 0 and near(beforeHp - enemies[1].hp, total), "真实追斩仅扣复制值，不重复暴击/护甲")
            stableGrowth(11, ETS.normalize({ stacks = 100, slashShadows = 4 }), "未击杀真实投射物")
        end
        for _, id in ipairs({ 11, 13, 21, 22 }) do
            local a = hero(id, 2, { stacks = 100, slashShadows = 4, splitKills = 50, nitroKills = 40, gatlingKills = 40 })
            local enemies = { enemy(10) }; local s = mount(a, enemies); local allies = { a }
            local before = copy(owned[id].extraTalent)
            BC.setContext({ getAllies = function() return allies end, getEnemies = function() return enemies end })
            if id == 11 then
                -- 明确由追斩而不是前置普通斩完成击杀，仍走原isNightSlash成长。
                directSlash(a, s, enemies, {}, function(tgt, damage, side, prefix, color, meta)
                    if prefix == "斩影追斩" then BC.dealTalentDamage(a, tgt, damage, side, prefix, color, meta) end
                end)
            elseif id == 13 then
                local extraEnemy = enemy(); enemies[2] = extraEnemy
                rosa.tryRosaBounce(a, s, extraEnemy, true, enemies, function(tgt, damage, side, prefix, color, meta)
                    BC.dealTalentDamage(a, tgt, damage, side, prefix, color, meta)
                end, { totalDamage = 1000, category = "physical", atkType = AD.ATK_PIERCE })
            elseif id == 21 then
                s.nitroStacks = 5; s.epicNitroStacks = 5; math.random = function(low) return low or 0 end
                alex.tryAlexSilverFlash(a, s, enemies[1], true, function(tgt, damage, side, prefix, color, meta)
                    BC.dealTalentDamage(a, tgt, damage, side, prefix, color, meta)
                end, { totalDamage = 1000, category = "physical", isCrit = true })
                math.random = nativeRandom
            else
                s.machineGunProgress = 14
                sera.tickSeraMachineGunCount(a, s)
                -- 真BC统一伤害，连射弹伤害计算仍由原performAttack，无新增复制公式。
                BC.dealDamageToUnit(enemies[1], 1000, false, "正常连射弹", { 255, 255, 255 }, a,
                    { category = "magical", atkType = AD.ATK_LIGHTNING })
            end
            check(enemies[1].hp <= 0 and enemies[1]._killedBy == a, "真击杀保正确来源 hero=" .. id)
            local expectedStack = (id == 11 or id == 13) and 2 or 1
            local pending = ETS.mountedState().pendingGrowth[id]
            check(pending and pending.stacks == expectedStack, "真实击杀仅按旧Ⅰ增长 hero=" .. id)
            if id == 11 then check(enemies[1]._killedByNightSlash, "追斩击杀精确NightSlash归因") end
            if id == 13 then check(enemies[1]._killedByRicochet, "弹射击杀精确Ricochet归因") end
            check(owned[id].extraTalent.stacks == before.stacks, "真实战中Ⅰ成长仍pending")
            ETS.flush(); local frozen = copy(owned[id].extraTalent); ETS.flush()
            check(owned[id].extraTalent.stacks == before.stacks + expectedStack and equal(frozen, owned[id].extraTalent),
                "真实flush幂等且只加旧成长 hero=" .. id)
            local roundtrip = ETS.normalize(cjson.decode(cjson.encode(owned[id].extraTalent)))
            check(equal(roundtrip, owned[id].extraTalent), "原存档字段JSON规范化往返 hero=" .. id)
        end

        -- 显式实例快照接收本实例真实战斗增量：库存即时，永久层等flush，下一轮读取新门槛。
        do
            local a = hero(11, 2, { stacks = 98, slashShadows = 0 }); local enemies = { enemy(1), enemy(1) }
            local s = mount(a, enemies); local allies = { a }
            BC.setContext({ getAllies = function() return allies end, getEnemies = function() return enemies end })
            for _, tgt in ipairs(enemies) do
                a._nightSlashKill = true
                BC.dealTalentDamage(a, tgt, 1000, false, "通宵斩", { 255, 255, 255 },
                    { isNightSlash = true, atkType = AD.ATK_SLASH, statCategory = "physical" }, allies, enemies)
            end
            check(ETS.getEpicGrowth(a).slashShadows == 2 and ETS.getEpicGrowth(a).stacks == 98,
                "两次真实击杀即时2斩影但Ⅰ永久成长仍98")
            local fresh = { enemy() }; TAL.mountedState().bEnemies = fresh
            local records = {}; directSlash(a, s, fresh, records)
            check(#records == 4 and records[4].damage == math.floor(records[1].damage * 0.5 + 0.5),
                "显式快照新斩影立即给下一轮1追斩，不借pending永久成长")
            ETS.flush()
            records = {}; directSlash(a, s, fresh, records)
            check(ETS.getEpicGrowth(a).stacks == 102 and records[4].damage == math.floor(records[1].damage * 0.5625 + 0.5),
                "真实flush后100 stacks门槛才给追斩成长")
            local b = hero(13, 2, { splitKills = 49 }); local enemiesB = { enemy(1), enemy() }; local sb = mount(b, enemiesB)
            BC.setContext({ getAllies = function() return { b } end, getEnemies = function() return enemiesB end })
            BC.dealTalentDamage(b, enemiesB[1], 1000, false, "弹射 ", { 255, 255, 255 },
                { isRicochet = true, atkType = AD.ATK_PIERCE, statCategory = "physical" }, { b }, enemiesB)
            check(ETS.getEpicGrowth(b).splitKills == 50, "显式快照真实分裂击杀49→50即时门槛")
            local rb = {}; rosa.tryRosaBounce(b, sb, enemiesB[1], true, enemiesB, hitRecord(b, rb), { totalDamage = 1000 })
            check(rb[1].damage == 800, "真实分裂击杀更新后下一链增强5个百分点")
        end

        -- 对真实BC主包已结算结果复制氮气/贯穿，不因目标护甲不同二次roll或算抗性。
        do
            local a = hero(21, 2, { nitroKills = 160 }); local enemies = { enemy(), enemy() }; local s = mount(a, enemies)
            enemies[2].attrs:addModifier("different_armor", { { key = AD.ARMOR, flat = 999 } })
            a.attrs:addModifier("copy_crit", { { key = AD.CRIT_RATE, flat = 100 }, { key = AD.CRIT_DMG, flat = 70 } })
            local result = CF.calcAttack(a.attrs, enemies[1].attrs)
            check(not result.isMiss and result.totalDamage > 0 and result.isCrit, "真实主包元素/护甲/暴击公式")
            s.nitroStacks = 5; s.epicNitroStacks = 5
            local allies, records = { a }, {}
            BC.setContext({ getAllies = function() return allies end, getEnemies = function() return enemies end })
            local beforeA, beforeB = enemies[1].hp, enemies[2].hp
            math.random = function(low) return low or 0 end
            TAL.onAfterAttack(a, enemies[1], result, true, enemies,
                hitRecord(a, records, function(tgt, damage, side, prefix, color, meta)
                    BC.dealTalentDamage(a, tgt, damage, side, prefix, color, meta, allies, enemies)
                end), allies)
            math.random = nativeRandom
            local expected = math.floor(math.floor(result.totalDamage * 1.8 + 0.5) * 1.4 + 0.5)
            check(#records == 2 and records[1].damage == expected and records[2].damage == math.floor(expected * 0.60 + 0.5),
                "真实TAL氮气先复制主包再强化，贯穿复制强化后60%")
            check(beforeA - enemies[1].hp == expected and beforeB - enemies[2].hp == math.floor(expected * 0.60 + 0.5),
                "真BC不同护甲目标仍直接落地复制值")
        end
        -- 旧低血通宵斩倍率仍生效；追斩逐道复制，不引入额外生命/暴击公式。
        for _, hpRatio in ipairs({ 1, 0.5, 0.01 }) do
            local a = hero(11, 2, { stacks = 400, slashShadows = 4 }); local enemies = { enemy() }; local s = mount(a, enemies)
            a.hp = math.max(1, math.floor(a.maxHp * hpRatio))
            local records = {}; directSlash(a, s, enemies, records)
            check(#records == 5 and records[4].damage == math.floor(records[1].damage * 0.75 + 0.5)
                and records[5].damage == math.floor(records[2].damage * 0.75 + 0.5), "旧低血增幅后的追斩仍精确复制")
        end
        -- 新效果按本英雄ID读取；直接错用helper不借另一个英雄的已拥有成长。
        for _, id in ipairs({ 11, 13, 21, 22 }) do
            owned[id] = { awakening = awake(2), extraTalent = ETS.normalize({ stacks = 100000, slashShadows = 4,
                splitKills = 100000, nitroKills = 100000, gatlingKills = 100000 }) }
        end
        do
            local a = hero(10, 2, nil); local enemies = { enemy(), enemy(), enemy(), enemy() }; local s = mount(a, enemies)
            s.atkCount = 2; local records = {}
            suhua.runSuhuaNightSlash(a, s, enemies[1], true, enemies, hitRecord(a, records))
            check(#records == 3, "wrong hero不借11斩影")
            records = {}; rosa.tryRosaBounce(a, s, enemies[1], true, enemies, hitRecord(a, records), { totalDamage = 1000 })
            check(records[1].damage == 650, "wrong hero无13新增弹射系数")
            records = {}; s.nitroStacks = 5; s.epicNitroStacks = 5; math.random = function(low) return low or 0 end
            alex.tryAlexSilverFlash(a, s, enemies[1], true, hitRecord(a, records), { totalDamage = 1000 })
            math.random = nativeRandom; check(records[1].damage == 1800, "wrong hero无21新增氮气系数")
            s.machineGunProgress = 14; sera.tickSeraMachineGunCount(a, s)
            check(s.machineGunShotsLeft == 12, "wrong hero无22新增弹数")
        end
        -- 追斩回调同state重开并立即执行新轮，不清新轮计数/临时状态或继续旧轮。
        do
            local a = hero(11, 2, { slashShadows = 4 }); local enemies = { enemy() }; local s = mount(a, enemies)
            local outer, inner = {}, {}
            directSlash(a, s, enemies, outer, function(_, _, _, prefix)
                if prefix == "斩影追斩" and #inner == 0 then
                    TAL.onBattleStart({ a }, enemies)
                    directSlash(a, s, enemies, inner)
                end
            end)
            check(#outer == 4 and #inner == 5 and s.atkCount == 3 and s.suhuaSlashActive == nil,
                "旧追斩回调不阻止新token斩轮且不擦新状态")
        end
        -- 连射正常启动冻结，本轮成长不续弹；真实TAL.update不把连射弹计入门槛。
        do
            local a = hero(22, 2, { gatlingKills = 40 }); local enemies = { enemy() }; local s = mount(a, enemies)
            s.machineGunShotsLeft, s.machineGunInBurst, s.machineGunProgress = 0, false, 12
            TAL.onBeforeAttack(a)
            check(s.machineGunShotsLeft == 13, "真实TAL正常门槛12+1弹")
            local count = 0
            local ctx = { performAttack = function(u)
                count = count + 1; TAL.onBeforeAttack(u); owned[22].extraTalent.gatlingKills = 100000
            end }
            for _ = 1, 20 do TAL.update(0.13, { a }, enemies, ctx) end
            check(count == 13 and s.machineGunNormalCount == 1 and s.machineGunShotsLeft == 0,
                "真实TAL整轮13弹耗尽/成长不续弹/连射不自充")
        end
        for _, action in ipairs({ "reset", "mount", "restart", "unitStates" }) do
            local a = hero(22, 2, { gatlingKills = 40 }); local enemies = { enemy() }; local s = mount(a, enemies)
            s.machineGunShotsLeft, s.machineGunInBurst, s.machineGunProgress = 0, false, 12
            TAL.onBeforeAttack(a)
            local callbackToken, calls, newState = s.epicAttackBattleToken, 0, s
            TAL.update(0.13, { a }, enemies, { performAttack = function(u)
                calls = calls + 1
                TAL.onBeforeAttack(u)
                if action == "reset" then TAL.reset(); TAL.initUnit(a)
                elseif action == "mount" then TAL.mount(TAL.newBattleRefs())
                elseif action == "unitStates" then TAL.mountUnitStates(TAL.newUnitStates()); TAL.initUnit(a)
                else TAL.onBattleStart({ a }, enemies) end
                newState = TAL.mountedUnitStates()[a]
                newState.machineGunShotsLeft, newState.machineGunShotTimer, newState.machineGunInBurst = 7, 0.077, true
            end })
            check(calls == 1 and newState.machineGunShotsLeft == 7 and newState.machineGunShotTimer == 0.077
                and newState.machineGunInBurst, "真实Update旧回调不扣新轮弹/不清timer " .. action)
            if action == "restart" then check(newState.epicAttackBattleToken ~= callbackToken, "重开同state更换连射token") end
        end
        check(AC.getTotalShardCost() == 90, "原觉醒费用90不变")
        check(sends >= 4 and patches >= 4, "真实成长同步仅经过内存边界")
    end)
    math.random = nativeRandom
    if not ok then failures = failures + 1; print("[史诗攻击Ⅱ][FAIL] 执行异常：" .. tostring(err)) end
    check(storage == 0, "四File/FS入口调用0")
    rawset(_G, "require", originalRequire)
    for key, value in pairs(originals) do rawset(_G, key, value) end
    print(string.format("[epic_attack_awakening_two_test] assertions=%d failures=%d storage=%d %s",
        assertions, failures, storage, failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
