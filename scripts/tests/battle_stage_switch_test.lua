-- ============================================================================
-- battle_stage_switch_test.lua — 战斗切关回归
-- 覆盖三处修复：
--   1) 失败回退 / 轮回 / 寻怪 后 battleActive 不被过期值覆盖（否则战斗卡死）
--   2) 切关时还原己方出场顺序（否则选关后角色位置变化）
--   3) 行2/3 全灭有墙钟兜底复活（否则永久卡住）
-- 跑法: ./.cli/UrhoXRuntime tests/battle_stage_switch_test.lua -tool_mode -graphicssurfaceless
-- ============================================================================

local failures = {}

local function check(cond, msg)
    if cond then
        print("[PASS] " .. msg)
    else
        print("[FAIL] " .. msg)
        failures[#failures + 1] = msg
    end
end

-- ── 1) BattleAllyReset.restoreOrder：按 _slotOrder 原位还原 ──
local function testRestoreOrder()
    local BattleAllyReset = require("ui.battle.scene.BattleAllyReset")

    local function mk(slot, name)
        return { _slotOrder = slot, name = name }
    end
    -- 模拟「阵亡紧凑」后的顺序：2 号阵亡被移到队尾
    local allies = { mk(1, "a"), mk(3, "c"), mk(4, "d"), mk(2, "b") }
    local ref = allies
    BattleAllyReset.restoreOrder(allies)
    check(allies == ref, "restoreOrder 原位排序（数组引用不变）")
    local order = {}
    for i, u in ipairs(allies) do order[i] = u.name end
    check(table.concat(order, "") == "abcd", "restoreOrder 还原槽位顺序 → abcd，实得 " .. table.concat(order, ""))

    -- 无 _slotOrder 时不改动顺序
    local noSlot = { { name = "x" }, { name = "y" } }
    BattleAllyReset.restoreOrder(noSlot)
    check(noSlot[1].name == "x" and noSlot[2].name == "y", "restoreOrder 无槽位信息时保持原序")

    -- 单个元素 / nil 不报错
    BattleAllyReset.restoreOrder({ { _slotOrder = 1 } })
    BattleAllyReset.restoreOrder(nil)
    check(true, "restoreOrder 边界输入不报错")
end

-- ── 2) 套装高阶标记在战斗快照和待更新快照中保留 ──
local function testSetSnapshot()
    local AD = require("systems.AttributeDef")
    local UA = require("systems.UnitAttributes")
    local Sets = require("systems.EquipmentSetSystem")
    local Reset = require("ui.battle.scene.BattleAllyReset")
    local attrs = UA.create({ [AD.MAX_HP] = 1000, atkType = AD.ATK_SLASH })
    Sets.applyTwoPieceToUnit(attrs, { ironwall = 6 })
    attrs._setFour = "ironwall"
    attrs._setSix = "ironwall"
    attrs._setRows = { { setId = "ironwall", count = 6, twoActive = true,
        fourActive = true, sixActive = true, color = { 1, 2, 3, 255 } } }
    local ally = { attrs = attrs, armorType = attrs.armorType }
    Reset.createSnapshot(ally)
    check(ally._baseSnapshot._setSix == "ironwall", "初始快照保留六件套标记")
    check(ally._baseSnapshot.modifiers.set2_ironwall ~= nil, "初始快照保留两件套属性")
    check(Reset.restoreFromSnapshot(ally)
        and select(2, Sets.activeHighSets(ally)) == "ironwall",
        "首次恢复后战斗六件套继续生效")
    ally.attrs._setRows[1].color[1] = 99
    check(ally._baseSnapshot._setRows[1].color[1] == 1,
        "摘要颜色深拷贝，不污染基线快照")

    local pending = attrs:clone()
    pending._setFour, pending._setSix = "gambler", "gambler"
    pending._setRows = { { setId = "gambler", count = 6, fourActive = true, sixActive = true } }
    ally._pendingSnapshot = pending
    check(Reset.restoreFromSnapshot(ally)
        and select(2, Sets.activeHighSets(ally)) == "gambler",
        "装备切换待定快照恢复后六件套切换")
    check(ally.attrs._setRows ~= pending._setRows
        and ally.attrs._setRows[1] ~= pending._setRows[1],
        "待定快照恢复后摘要行独立")
end

-- ── 3) 统一穿戴入口执行职业、双持与双手互斥校验 ──
local function testEquipGuards()
    local ES = require("systems.EquipmentSystem")
    local function makeData(ids)
        local inventory = {}
        for i, templateId in ipairs(ids) do
            inventory[tostring(i)] = ES.generate(templateId, 85, 1)
        end
        return { inventory = inventory, equipped = {} }
    end
    local function wear(data, seq, heroId, slot, heroes)
        local ok, err = ES.applyEquip(data, seq, heroId, slot, heroes)
        return ok, err or ""
    end

    local warrior = makeData({ "W31", "W1", "O13", "A55", "A31", "O7", "W7" })
    local ok, err = wear(warrior, 1, 1, "weapon")
    check(not ok and err:find("无法穿戴", 1, true) ~= nil,
        "战士主手魔杖被职业限制拒绝")
    ok, err = wear(warrior, 3, 1, "offhand")
    check(not ok and err:find("无法穿戴", 1, true) ~= nil,
        "战士副手魔典被职业限制拒绝")
    ok, err = wear(warrior, 4, 1, "armor")
    check(not ok and err:find("无法穿戴", 1, true) ~= nil,
        "战士布甲被职业限制拒绝")
    check(wear(warrior, 2, 1, "weapon") == true
        and wear(warrior, 5, 1, "armor") == true
        and wear(warrior, 6, 1, "offhand") == true,
        "战士正常单手剑、重甲、重盾可穿")
    local before = warrior.equipped[1].offhand
    ok, err = wear(warrior, 1, 1, "offhand")
    check(not ok and warrior.equipped[1].offhand == before,
        "无双持天赋时魔杖不能占副手，失败不改原槽")
    check(wear(warrior, 7, 1, "weapon") == true
        and warrior.equipped[1].offhand == nil,
        "换双手剑会自动卸副手")

    local sameHeroes = { roster = { [18] = { advBranch = { first = 110, second = 220 } } } }
    local same = makeData({ "W61", "W62", "W55", "O1" })
    ok, err = wear(same, 4, 18, "offhand", sameHeroes)
    check(not ok and err:find("常规副手", 1, true) ~= nil,
        "220 双持角色不能再穿普通轻盾")
    ok, err = wear(same, 2, 18, "offhand", sameHeroes)
    check(not ok and err:find("主手", 1, true) ~= nil,
        "220 同类型双持缺主手时拒绝")
    check(wear(same, 1, 18, "weapon", sameHeroes) == true
        and wear(same, 2, 18, "offhand", sameHeroes) == true,
        "220 同类型细剑可双持")
    ok, err = wear(same, 3, 18, "offhand", sameHeroes)
    check(not ok and err:find("相同类型", 1, true) ~= nil,
        "220 不同类型武器副手被拒绝")
    check(wear(same, 3, 18, "weapon", sameHeroes) == false
        and same.equipped[18].weapon == 1,
        "220 已持同类型副手时替换主手为异类被拒绝")

    local diffHeroes = { roster = { [1] = { advBranch = { first = 104, second = 207 } } } }
    local different = makeData({ "W1", "W13", "W2", "O7", "W31", "W14" })
    check(wear(different, 1, 1, "weapon", diffHeroes) == true
        and wear(different, 2, 1, "offhand", diffHeroes) == true,
        "207 不同类型剑斧可双持")
    ok, err = wear(different, 3, 1, "offhand", diffHeroes)
    check(not ok and err:find("不同类型", 1, true) ~= nil,
        "207 相同类型剑副手被拒绝")
    ok, err = wear(different, 4, 1, "offhand", diffHeroes)
    check(not ok and err:find("常规副手", 1, true) ~= nil,
        "207 角色不能穿普通重盾")
    ok, err = wear(different, 5, 1, "offhand", diffHeroes)
    check(not ok and err:find("无法穿戴", 1, true) ~= nil,
        "207 副手魔杖仍受英雄武器类型约束")
    check(wear(different, 6, 1, "weapon", diffHeroes) == false
        and different.equipped[1].weapon == 1,
        "207 已持异类型副手时替换主手为同类型被拒绝")
end

-- ── 4) 失败回退分支不再把过期的 battleActive=false 写回 ──
local function testDefeatRollbackKeepsBattleActive()
    local Phases = require("ui.battle.scene.BattleScenePhases")

    local loaded = 0
    local ally = { name = "a", hp = 0 }
    local ctx
    ctx = {
        -- 进入 process 时是「已全灭」状态
        battleActive = false,
        defeatTimer = 10,        -- 已超过 DEFEAT_DELAY
        reincarnationTimer = nil,
        searchingTimer = nil,
        terminalDefeatPending = false,
        defeatByTimeout = false,
        isFirstClear = true,
        currentStageId = 101,
        maxStageId_ = 101,
        clearedStages = {},
        stageName = "1-1",
        pendingReincarnation = nil,
        bgTransAnim = nil,
        regenAccum = 0,
        enemies = {},
        enemyQueue = {},
        allies = { ally },
        DEFEAT_DELAY = 1.5,
        REINCARNATION_DELAY = 2.0,
        SEARCH_ENEMY_DURATION = 1.0,
        BG_ZOOM_BACK_TARGET = 1,
        BG_ZOOM_FWD_TARGET = 2,
        isPaused = false,
        updateCardAnims = function() end,
        updateFloatingTexts = function() end,
        updateHitFlashes = function() end,
        updateComboQueue = function() end,
        getStageConfig = function()
            return {
                isTerminalTemple = function() return false end,
                getPrevStageId = function() return 101 end,
                getTerminalPrevStageId = function() return 101 end,
            }
        end,
        -- loadStage 把 battleActive 置 true（真实 BattleStageLoad 的行为）
        loadStage = function() loaded = loaded + 1 ctx.battleActive = true end,
        resetAllyUnit = function(u) u.hp = 100 end,
        startBattleTalents = function() end,
        onStageChangedCallback = nil,
        onReincarnateCallback = nil,
        recalcIdleIncome = function() end,
        generateIdleEnemyList = function() return {}, 1 end,
        assignEnemiesToField = function(e) return e, 1 end,
        BattleScene = { nextStage = function() end, refreshAllyStats = function() end },
    }

    local consumed = Phases.process(ctx, 1 / 60)
    check(consumed == true, "失败回退帧被 process 消费")
    check(loaded == 1, "失败回退调用了 loadStage")
    check(ctx.defeatTimer == nil, "失败回退清空 defeatTimer")
    -- 核心断言：loadStage 设的 true 不能被过期局部值覆盖
    check(ctx.battleActive == true,
        "失败回退后 battleActive 保持 true（不被过期 false 覆盖），实得 " .. tostring(ctx.battleActive))
    check(ally.hp == 100, "失败回退重置了己方单位")
end

-- ── 3) BattleTriDriver 全灭退回上一关，倒下的人不会自己满血 ──
local function testTriDriverWipeFallback()
    local Driver = require("ui.battle.tri.BattleTriDriver")
    local SC = require("config.StageConfig")
    local drv = Driver.new(2)
    local stageId = SC.getNextStageId(SC.NORMAL_FIRST_STAGE)
    drv.stageId = stageId
    drv.allies = { { name = "a", hp = 0, maxHp = 50 }, { name = "b", hp = 0, maxHp = 60 } }
    drv.enemies = { { name = "e", hp = 10, maxHp = 10 } }
    drv.enemyQueue = {}
    drv.active = true
    drv.mount()
    drv.bindContext()

    drv:tick(1 / 60)
    check(drv.stageId == SC.NORMAL_FIRST_STAGE, "全灭后退回上一关，实得 " .. tostring(drv.stageId))
    local stillDown = true
    for _, u in ipairs(drv.allies) do
        if u.name == "a" or u.name == "b" then stillDown = false end
    end
    check(stillDown, "倒下的单位没有在本场被自动复活")
end

-- ── 4) 神器并行战线/叠层/倒计时回归 ──
local function testArtifactRuntimeIsolation()
    local ART = require("systems.ArtifactRuntime")
    local AD = require("systems.AttributeDef")
    local function makeUnit(effectType, value)
        local attrs = {
            final = { [AD.HP] = 0 },
            artifactExtraDamageMult = nil,
            modifiers = {},
        }
        function attrs:get(key)
            if key == AD.MAX_HP then return 100 end
            return self.final[key] or 0
        end
        function attrs:addModifier(id, entries)
            self.modifiers[id] = entries
        end
        function attrs:removeModifier(id)
            self.modifiers[id] = nil
        end
        return { attrs = attrs, hp = 0, maxHp = 100,
            artifactEffects = { { effectType = effectType, value = value } } }
    end
    local a = makeUnit("revive_damage_bonus", 50)
    local b = makeUnit("revive_damage_bonus", 50)
    ART.initBattle({ a })
    ART.initBattle({ b })
    check(ART.onAllyDeath(a), "队 A 神圣十架首次触发")
    ART.reset({ b })
    check(not ART.onAllyDeath(a), "队 B 重置后队 A 复活次数不会重置")
    ART.initBattle({ b })
    check(ART.onAllyDeath(b), "队 B 重开后能独立触发")

    local cloak = makeUnit("dodge_decay", 25)
    ART.initBattle({ cloak })
    local modId = "artifact_dodge_decay_1"
    check(cloak.attrs.modifiers[modId][1].flat == 200, "影羽斗篷入场额外闪避 200")
    ART.onDodge(cloak)
    check(cloak.attrs.modifiers[modId][1].flat == 150, "影羽斗篷按初始值 25% 衰减 50")
    ART.initBattle({ cloak })
    check(cloak.attrs.modifiers[modId][1].flat == 200, "重新开战前清理旧 modifier")

    local attacker = makeUnit("judgment_res_down", 3)
    local enemyA, enemyB = {}, {}
    ART.initBattle({ attacker })
    ART.onAfterAttack(attacker, enemyA, { isHit = true, category = "physical" })
    ART.onAfterAttack(attacker, enemyA, { isHit = true, category = "physical" })
    check(attacker.artifactJudgmentStacks[enemyA].value == 6, "连续命中叠加抗性削减")
    ART.onAfterAttack(attacker, enemyB, { isHit = true, category = "physical" })
    check(attacker.artifactJudgmentStacks[enemyA] == nil
        and attacker.artifactJudgmentStacks[enemyB].value == 3, "切换目标清旧叠层")

    local ghost = makeUnit("ghost_damage_bonus", 50)
    ART.initBattle({ ghost })
    check(ART.onAllyDeath(ghost) and ghost.artifactUntargetable, "亡魂首次触发")
    ART.update(5, { ghost })
    check(ghost.hp == 1 and ghost.artifactUntargetable, "亡魂计时 5 秒后仍存活")
    ART.update(5, { ghost })
    check(ghost.hp == 0 and not ghost.artifactUntargetable, "亡魂十秒到期退场")
    ART.reset({ a, b, cloak, attacker, ghost })
end

-- ── 5) [三队适配] 神器装配表按队伍隔离 + 旧档迁移 ──
local function testArtifactTeamSchema()
    local ArtifactSchema = require("shared.artifact.ArtifactSchema")

    -- 旧档（无 equippedByTeam）迁移到队1
    local legacy = {
        bag = { { id = "1", artifactId = 5, quality = 2, value = 50 } },
        equipped = { [1] = { [1] = "1" } },
        nextId = 2,
    }
    ArtifactSchema.normalizeModule(legacy)
    check(ArtifactSchema.getEquippedId(legacy, 1, 1) == "1", "旧档装配迁移后队1 可读（缺省 teamIdx）")
    check(ArtifactSchema.getEquippedId(legacy, 1, 1, 1) == "1", "旧档装配显式 teamIdx=1 可读")
    check(ArtifactSchema.getEquippedId(legacy, 1, 1, 2) == nil, "旧档装配不会泄漏到队2")
    check(ArtifactSchema.getEquippedId(legacy, 1, 1, 3) == nil, "旧档装配不会泄漏到队3")

    -- 同一实例可跨队复用（实例可复用方案）
    local data = { bag = { { id = "7", artifactId = 5, quality = 2, value = 50 } }, nextId = 8 }
    ArtifactSchema.normalizeModule(data)
    ArtifactSchema.setEquippedId(data, 2, 1, "7", 1)
    ArtifactSchema.setEquippedId(data, 2, 1, "7", 2)
    ArtifactSchema.setEquippedId(data, 3, 2, "7", 3)
    check(ArtifactSchema.getEquippedId(data, 2, 1, 1) == "7"
        and ArtifactSchema.getEquippedId(data, 2, 1, 2) == "7"
        and ArtifactSchema.getEquippedId(data, 3, 2, 3) == "7", "同一实例可同时装到三支队伍")

    -- 各队独立查找/卸下
    check((ArtifactSchema.findEquippedSlot(data, "7", 1)) == 2, "队1 查找命中本队槽位")
    local teamAny, slotAny = ArtifactSchema.findEquippedSlotAnyTeam(data, "7")
    check(teamAny == 1 and slotAny == 2, "任意队查找优先命中队1")
    ArtifactSchema.setEquippedId(data, 2, 1, nil, 1)
    check(ArtifactSchema.getEquippedId(data, 2, 1, 1) == nil, "卸下队1 装配")
    check(ArtifactSchema.getEquippedId(data, 2, 1, 2) == "7", "卸队1 不影响队2 装配")
    local t2 = ArtifactSchema.findEquippedSlotAnyTeam(data, "7")
    check(t2 == 2, "队1 卸下后任意队查找命中队2")

    -- 同队内实例唯一：队2 再装到别处应清掉旧位
    ArtifactSchema.setEquippedId(data, 1, 1, "7", 2)
    check(ArtifactSchema.getEquippedId(data, 2, 1, 2) == nil
        and ArtifactSchema.getEquippedId(data, 1, 1, 2) == "7", "同队内重装实例自动移出旧位")

    -- 非法 teamIdx 回落 1
    ArtifactSchema.setEquippedId(data, 4, 1, "7", nil)
    check(ArtifactSchema.getEquippedId(data, 4, 1, 1) == "7", "teamIdx 缺省回落队1")
    ArtifactSchema.setEquippedId(data, 4, 1, "7", 99)
    check(ArtifactSchema.getEquippedId(data, 4, 1, 1) == "7", "teamIdx 越界回落队1")

    -- 存档 roundtrip：dehydrate → normalize 后三队装配保持
    local lean = ArtifactSchema.dehydrateModule(data)
    check(lean.e == nil and type(lean.et) == "table", "dehydrate 输出 et 分队结构且不再输出旧 e")
    local restored = { bag = { { id = "7", artifactId = 5, quality = 2, value = 50 } } }
    for k, v in pairs(lean) do restored[k] = v end
    ArtifactSchema.normalizeModule(restored)
    check(ArtifactSchema.getEquippedId(restored, 1, 1, 2) == "7"
        and ArtifactSchema.getEquippedId(restored, 3, 2, 3) == "7"
        and ArtifactSchema.getEquippedId(restored, 4, 1, 1) == "7", "存档 roundtrip 后各队装配一致")

    -- [双格改版] 解锁等级：Lv30 第1格、Lv60 第2格，30 级前 0 格
    check(ArtifactSchema.SUB_SLOT_COUNT == 2, "SUB_SLOT_COUNT 改为 2（双格）")
    check(ArtifactSchema.getUnlockedSubSlotCount(1) == 0, "Lv1 未解锁任何子格")
    check(ArtifactSchema.getUnlockedSubSlotCount(29) == 0, "Lv29 仍未解锁子格")
    check(ArtifactSchema.getUnlockedSubSlotCount(30) == 1, "Lv30 解锁第1子格")
    check(ArtifactSchema.getUnlockedSubSlotCount(59) == 1, "Lv59 仍只第1子格")
    check(ArtifactSchema.getUnlockedSubSlotCount(60) == 2, "Lv60 解锁第2子格")
    check(ArtifactSchema.getSubSlotUnlockLevel(1) == 30
        and ArtifactSchema.getSubSlotUnlockLevel(2) == 60, "子格解锁等级 30/60")

    -- [双格改版] 旧档第3格迁移：3格旧档归一化后第3格卸下，实例仍留背包不丢失
    local legacy3 = {
        bag = {
            { id = "1", artifactId = 5, quality = 2, value = 50 },
            { id = "2", artifactId = 6, quality = 2, value = 50 },
            { id = "3", artifactId = 7, quality = 2, value = 50 },
        },
        equippedByTeam = { [1] = { [1] = { [1] = "1", [2] = "2", [3] = "3" } } },
        nextId = 4,
    }
    ArtifactSchema.normalizeModule(legacy3)
    check(ArtifactSchema.getEquippedId(legacy3, 1, 1, 1) == "1", "旧档3格迁移：第1格保留")
    check(ArtifactSchema.getEquippedId(legacy3, 1, 2, 1) == "2", "旧档3格迁移：第2格保留")
    check(ArtifactSchema.getEquippedId(legacy3, 1, 3, 1) == nil, "旧档3格迁移：第3格已卸下")
    local bagHas3 = false
    for _, a in ipairs(legacy3.bag) do if tostring(a.id) == "3" then bagHas3 = true end end
    check(bagHas3, "旧档3格迁移：卸下的第3格实例仍在背包（不丢失）")
end

-- ── 6) [三队适配] ArtifactBridge 按队伍读取装配 ──
local function testArtifactBridgeTeam()
    local ArtifactBridge = require("systems.ArtifactBridge")
    local ArtifactSchema = require("shared.artifact.ArtifactSchema")
    local AD = require("systems.AttributeDef")

    -- 巨人之铠(5, counter_attack) 只加战力分；嘲讽面具(11, taunt_mask) 加 artifactExtraDamageMult，可断言
    local data = {
        bag = {
            { id = "1", artifactId = 11, quality = 1, value = 20 },
            { id = "2", artifactId = 11, quality = 3, value = 60 },
        },
        nextId = 3,
    }
    ArtifactSchema.normalizeModule(data)
    ArtifactSchema.setEquippedId(data, 1, 1, "1", 1)
    ArtifactSchema.setEquippedId(data, 1, 1, "2", 2)

    local function mkAttrs()
        local attrs = { final = {}, modifiers = {} }
        function attrs:get(key) return self.final[key] or 0 end
        function attrs:addModifier(id, entries)
            self.modifiers[id] = entries
            for _, e in ipairs(entries) do
                self.final[e.key] = (self.final[e.key] or 0) + e.flat
            end
        end
        function attrs:removeModifier(id) self.modifiers[id] = nil end
        return attrs
    end

    local a1 = mkAttrs()
    local fx1 = ArtifactBridge.applyToUnit(a1, 1, data, 1)
    check(#fx1 == 1 and a1.artifactExtraDamageMult and math.abs(a1.artifactExtraDamageMult - 1.2) < 1e-9,
        "队1 按本队装配获得 +20% 额外伤害")

    local a2 = mkAttrs()
    local fx2 = ArtifactBridge.applyToUnit(a2, 1, data, 2)
    check(#fx2 == 1 and a2.artifactExtraDamageMult and math.abs(a2.artifactExtraDamageMult - 1.6) < 1e-9,
        "队2 按本队装配获得 +60% 额外伤害（与队1 隔离）")

    local a3 = mkAttrs()
    local fx3 = ArtifactBridge.applyToUnit(a3, 1, data, 3)
    check(#fx3 == 0 and a3.artifactExtraDamageMult == nil, "队3 无装配时不获得神器效果")

    -- 缺省 teamIdx（旧调用）等价队1
    local a4 = mkAttrs()
    ArtifactBridge.applyToUnit(a4, 1, data)
    check(a4.artifactExtraDamageMult and math.abs(a4.artifactExtraDamageMult - 1.2) < 1e-9,
        "缺省 teamIdx 回落队1（旧调用兼容）")
end

function Start()
    print("[battle_stage_switch_test] start")
    local ok, err = pcall(function()
        testRestoreOrder()
        testSetSnapshot()
        testEquipGuards()
        testDefeatRollbackKeepsBattleActive()
        testTriDriverWipeFallback()
        testArtifactRuntimeIsolation()
        testArtifactTeamSchema()
        testArtifactBridgeTeam()
    end)
    if not ok then
        print("[FAIL] 测试抛异常: " .. tostring(err))
        failures[#failures + 1] = "exception"
    end
    if #failures == 0 then
        print("[battle_stage_switch_test] ALL PASS")
    else
        print("[battle_stage_switch_test] FAILURES=" .. #failures)
        for _, m in ipairs(failures) do print("  - " .. m) end
    end
    engine:Exit()
end
