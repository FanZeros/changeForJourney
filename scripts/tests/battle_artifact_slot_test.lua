-- 神器号位回归：真实 CP/BS/Reset/ArtifactBridge/Runtime，隔离 UI 和存档边界。
-- 空槽、阵亡紧凑仅改变显示位置；属性和运行时效果必须在下一波一起提交。
-- /home/Maker/validation-runtime/UrhoXRuntime scripts/tests/battle_artifact_slot_test.lua
-- -tapcode_dir=. -tool_mode -graphicsheadless（cwd=/workspace）
local assertions = 0
local failures = {}
local TAG = "[battle_artifact_slot_test]"

local function check(condition, message)
    assertions = assertions + 1
    if condition then print("[PASS] " .. message)
    else failures[#failures + 1] = message; print("[FAIL] " .. message) end
end

local function near(actual, expected, message)
    check(type(actual) == "number" and math.abs(actual - expected) < 1e-9,
        message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

function Start()
    local nativeRequire = require
    local ok, err = pcall(function()
        local function noop() end
        local env = setmetatable({}, { __index = _G })
        local modules = {
            player = { level = 100 },
            battle = { currentStageId = 101, maxStageId = 2501, clearedStages = {} },
            equipment = { inventory = {}, equipped = {} },
            talents = { litNodes = {} },
        }
        local anims = setmetatable({}, { __mode = "k" })
        local combat = {
            reset = function() for unit in pairs(anims) do anims[unit] = nil end end,
            clearCardAnim = function(unit) anims[unit] = nil end,
            getAnimState = function(unit) return anims[unit] and anims[unit].state end,
            setCardAnim = function(unit, state) anims[unit] = state end,
            syncUnitHp = function(unit)
                if unit.attrs then unit.hp = unit.attrs:get("hp"); unit.maxHp = unit.attrs:get("maxHp") end
            end,
            getCardCX = function(_, index) return 100 * index end,
            setContext = noop,
        }
        local gameState = { getLevel = function() return 100 end, setPower = noop }
        local effects = { reset = noop }
        local mocks = {
            ["core.PlayerStore"] = { Get = function(key) return modules[key] end },
            ["runtime.ClientDispatcher"] = { get = function(key) return modules[key] end },
            ["core.GameState"] = gameState,
            ["core.DarkIcon"] = {},
            ["systems.ThreatManager"] = { reset = noop, onBattleStart = noop, removeUnit = noop },
            ["systems.TalentManager"] = { reset = noop, initUnit = noop, onBattleStart = noop },
            ["systems.RelicConditionHandler"] = { reset = noop, initBattle = noop },
            ["systems.BattleDiag"] = { reset = noop, installSentinel = noop, scanNow = noop },
            ["systems.MapAffixSystem"] = {},
            ["systems.BattleTimeout"] = {},
            ["systems.OfflineCalc"] = {
                resolveIdleStageAnchors = function() return 101, 101 end,
                calcOnlineIdleRewards = function() return { gold = 0, adventureExp = 0 } end,
            },
            ["ui.battle.combat.BattleCombat"] = combat,
            ["ui.battle.combat.BattleCombatAnim"] = { DEATH_ANIM_DURATION = 0.5 },
            ["ui.battle.combat.BattleEffects"] = effects,
            ["ui.battle.combat.ProjectileSystem"] = effects,
            ["ui.widget.SpeechBubble"] = effects,
            ["ui.hud.BottomNav"] = { setBadge = noop, refreshTownBadge = noop, setAllLocked = noop },
            ["ui.character.detail.CharacterDetail"] = {
                markPowerDirty = noop, hasAnyUpgradeForHero = function() return false end,
                hasAwakeningUpgrade = function() return false end,
            },
            ["ui.church.ChurchPage"] = { hasAdvanceForHero = function() return false end },
            ["systems.TutorialManager"] = {},
            ["ui.widget.HeroFrame"] = {},
            ["ui.battle.tri.BattleTriPage"] = { invalidateTeams = noop },
            ["ui.hud.popup.OfflineRewardPanel"] = { isOpen = function() return false end },
            ["ui.battle.stage.BattleStageNav"] = { NAV = {} },
            ["ui.battle.stage.BattleStageNavLogic"] = { bind = function() return {} end },
            ["ui.battle.scene.BattleDataRestore"] = { bind = function() return {} end },
            ["shared.StageProvider"] = { Get = function() return env.require("config.StageConfig") end },
        }
        local realNames = {
            ["core.DrawUtil"] = true, ["core.BattleLayout"] = true,
            ["core.NumberUtil"] = true, ["shared.Protocol"] = true,
            ["shared.heroes.HeroResonance"] = true,
            ["shared.artifact.ArtifactDefs"] = true, ["shared.artifact.ArtifactSchema"] = true,
            ["systems.AttributeDef"] = true, ["systems.UnitAttributes"] = true,
            ["systems.TalentEffect"] = true, ["systems.ArtifactBridge"] = true,
            ["systems.ArtifactRuntime"] = true, ["systems.CombatFormula"] = true,
            ["systems.EquipmentSystem"] = true, ["systems.EquipmentSetSystem"] = true,
            ["systems.CombatPowerEstimate"] = true, ["systems.ExtraTalentSystem"] = true,
            ["systems.AwakeningGrowth"] = true, ["systems.StatusEffectManager"] = true,
            ["ui.character.panel.CharacterPanel"] = true,
            ["ui.character.panel.CharacterPanelDraw2"] = true,
            ["ui.character.panel.CharacterDeploy"] = true, ["ui.character.panel.CharacterInput"] = true,
            ["ui.character.panel.CharacterHeroSync"] = true, ["ui.character.panel.CharacterPower"] = true,
            ["ui.character.panel.CharacterProgress"] = true,
            ["ui.battle.scene.BattleScene"] = true, ["ui.battle.scene.BattleAllyReset"] = true,
            ["ui.battle.scene.BattleAllyLifecycle"] = true,
        }
        local real, loading = {}, {}
        env.require = function(name)
            if mocks[name] then return mocks[name] end
            if real[name] then return real[name] end
            -- 不编译其他 UI/战斗入口，更不加载规则层、存档模块或真实主游戏。
            if not realNames[name] and name:match("^ui%.") then
                mocks[name] = {}
                return mocks[name]
            end
            assert(realNames[name] or name:match("^config%."), "禁止未声明依赖或存档入口: " .. name)
            assert(not loading[name], "意外循环依赖: " .. name)
            loading[name] = true
            local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "缺少脚本 " .. name)
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            file:Dispose()
            local value = assert(load(table.concat(lines, "\n"), "@" .. name, "t", env))()
            loading[name] = nil
            real[name] = value
            return value
        end
        local CP = env.require("ui.character.panel.CharacterPanel")
        local BS = env.require("ui.battle.scene.BattleScene")
        local Reset = env.require("ui.battle.scene.BattleAllyReset")
        local AD = env.require("systems.AttributeDef")
        local UA = env.require("systems.UnitAttributes")
        local HC = env.require("config.HeroConfig")
        local ART = env.require("systems.ArtifactRuntime")
        local Schema = env.require("shared.artifact.ArtifactSchema")
        local heroes = {
            roster = {
                [1] = { level = 60, awakening = {}, extraTalent = {} },
                [2] = { level = 60, awakening = {}, extraTalent = {} },
                [3] = { level = 60, awakening = {}, extraTalent = {} },
                [4] = { level = 60, awakening = {}, extraTalent = {} },
            },
            deployed = { 1, 0, 2, 0 },
            teams = { { slots = { 1, 0, 2, 0 } }, { slots = { 0, 0, 0, 3 } }, { slots = { 0, 4, 0, 0 } } },
        }
        local artifacts = {
            bag = {
                { id = "1", artifactId = 11, quality = 1, valueRatio = 0 },
                { id = "2", artifactId = 11, quality = 3, valueRatio = 0 },
                { id = "3", artifactId = 5, quality = 2, valueRatio = 0 },
                { id = "4", artifactId = 11, quality = 2, valueRatio = 0 },
                { id = "5", artifactId = 7, quality = 1, valueRatio = 0 },
                { id = "6", artifactId = 9, quality = 1, valueRatio = 0 },
            },
            equippedByTeam = {
                [1] = { [2] = { "1" }, [3] = { "2" }, [4] = { "5" } },
                [2] = { [4] = { "4" } }, [3] = { [2] = { "6" } },
            }, nextId = 7,
        }
        Schema.normalizeModule(artifacts)
        modules.heroes, modules.artifacts = heroes, artifacts
        CP.setHeroesData(heroes)
        local allies = CP.getDeployedTeam(1)
        local a, b = assert(allies[1]), assert(allies[2])
        check(#allies == 2 and b.heroId == 2, "空槽保持两名实际战斗单位")
        check(a.partySlot == 1 and b.partySlot == 3 and b.artifactTeamIdx == 1,
            "真实CP初建保留槽1/3与所属队")
        local initialMult = b.attrs.artifactExtraDamageMult
        near(initialMult, 1.52, "初建读取槽3而非密集槽2神器")
        local originalPhysBonus = b.attrs:getUncapped(AD.PHYS_ATK_BONUS)
        BS.setAllies(allies)
        check(BS.getAllies() == allies and b._slotOrder == 3, "真实BS接线保留列表引用及真实原序")
        local oldAttrs, oldHp, oldMaxHp, oldInterval = b.attrs, b.hp, b.maxHp, b.atkInterval
        BS.refreshAllyStats()
        near(b._pendingSnapshot and b._pendingSnapshot.artifactExtraDamageMult, initialMult,
            "空槽后刷新仍按真实槽3生成pending")
        near(b._pendingSnapshot:getUncapped(AD.PHYS_ATK_BONUS), originalPhysBonus,
            "邻位战旗按实际槽关系而非显示间距应用")
        check(b.attrs == oldAttrs and b.hp == oldHp and b.maxHp == oldMaxHp and b.atkInterval == oldInterval,
            "刷新不改变当前attrs/HP/上限/攻击间隔")

        a.hp = 0
        a.attrs.final[AD.HP] = 0
        a._fallenPending, a._fallenAt = true, 0
        Reset.compactFallen(allies, 100)
        check(allies[1] == b and allies[2] == a and b.partySlot == 3 and a.partySlot == 1,
            "真实阵亡紧凑前移保留实际槽位")
        BS.refreshAllyStats()
        near(b._pendingSnapshot.artifactExtraDamageMult, initialMult, "紧凑后刷新不借显示槽1神器")
        check(a.hp == 0 and a._pendingSnapshot ~= nil, "阵亡者刷新下波属性但不提前复活")

        local oldEffects = b.artifactEffects
        Schema.setEquippedId(artifacts, 3, 1, "3", 1)
        BS.refreshAllyStats()
        check(b.attrs == oldAttrs and b.artifactEffects == oldEffects, "改装不提前切换当前属性或运行时效果")
        check(b._pendingArtifactEffects[1].artifactInstanceId == "3", "新神器效果随pending保存")
        Reset.resetAllyUnit(b, allies, combat.syncUnitHp)
        check(b.attrs.artifactExtraDamageMult == nil and b.artifactEffects[1].artifactInstanceId == "3",
            "下一波属性与运行时列表同步切换")
        check(b._pendingSnapshot == nil and b._pendingArtifactEffects == nil, "提交后清除pending属性和效果")
        local expectedPower = b.attrs.artifactPowerBonus
        b._baseSnapshot, b._pendingSnapshot = nil, nil
        Reset.resetAllyUnit(b, allies, combat.syncUnitHp)
        near(b.attrs.artifactPowerBonus, expectedPower, "无快照重建仍读真实槽3")
        check(b.artifactEffects[1].artifactInstanceId == "3", "无快照重建同步正确运行时效果")
        Schema.setEquippedId(artifacts, 3, 1, nil, 1)
        BS.refreshAllyStats()
        Reset.restoreFromSnapshot(b)
        check(b.artifactEffects == nil and not b.attrs.artifactPowerBonus,
            "卸下后pending空表明确清除旧神器效果")

        local second = CP.getDeployedTeam(2)
        check(#second == 1 and second[1].partySlot == 4 and second[1].artifactTeamIdx == 2,
            "队2仅槽4出战仍保留队号及真实槽")
        Reset.resetAllyUnit(second[1], second, combat.syncUnitHp)
        near(second[1].attrs.artifactExtraDamageMult, 1.32, "队2无快照重建不读取队1/密集槽1")
        local legacy = assert(HC.createHero(3, 60))
        legacy.artifactTeamIdx = 2
        Reset.resetAllyUnit(legacy, { legacy }, combat.syncUnitHp)
        check(legacy.partySlot == 4 and legacy.artifactTeamIdx == 2, "旧单位只在所属队反查真实槽")
        near(legacy.attrs.artifactExtraDamageMult, 1.32, "旧单位反查神器加成正确")
        local bare = assert(HC.createHero(3, 60))
        Reset.resetAllyUnit(bare, { bare }, combat.syncUnitHp)
        check(bare.partySlot == 4 and bare.artifactTeamIdx == 2, "同时缺队号/槽时全队反查实际归属")
        near(bare.attrs.artifactExtraDamageMult, 1.32, "全队反查不默认借用队1装配")
        local undeployed = assert(HC.createHero(5, 60))
        Reset.resetAllyUnit(undeployed, { undeployed }, combat.syncUnitHp)
        check(undeployed.partySlot == nil and undeployed.artifactEffects == nil
            and undeployed.attrs.artifactExtraDamageMult == nil, "未部署单位不猜测数组槽位或借用神器")

        local third = CP.getDeployedTeam(3)
        check(third[1].partySlot == 2 and third[1].artifactTeamIdx == 3, "队3稀疏槽2归属保持")
        BS.setAllies(third)
        check(not ART.canHeal(third[1]), "当前波真实Runtime启用禁止治疗神器")
        local thirdAttrs, thirdEffects = third[1].attrs, third[1].artifactEffects
        Schema.setEquippedId(artifacts, 2, 1, nil, 3)
        BS.refreshAllyStats()
        check(third[1].attrs == thirdAttrs and third[1].artifactEffects == thirdEffects and not ART.canHeal(third[1]),
            "卸装pending不提前禁用当前Runtime")
        Reset.resetAllyUnit(third[1], third, combat.syncUnitHp)
        ART.initBattle(third)
        check(ART.canHeal(third[1]) and third[1].artifactEffects == nil and not third[1].attrs.artifactNoHeal,
            "下一波属性标记/运行时列表/Runtime行为同时清除")

        BS.setAllies(allies)
        a.hp, a.attrs.final[AD.HP] = 0, 0
        Schema.setEquippedId(artifacts, 1, 1, "1", 1)
        BS.refreshAllyStats()
        check(a.hp == 0 and a._pendingSnapshot and a._pendingArtifactEffects[1].artifactInstanceId == "1",
            "阵亡者改装生成下一波快照与效果，不提前复活")
        near(a._pendingSnapshot.artifactExtraDamageMult, 1.2, "阵亡者pending读取原槽1新装配")
        Reset.resetAllyUnit(a, allies, combat.syncUnitHp)
        check(a.hp > 0 and a.artifactEffects[1].artifactInstanceId == "1", "下一波阵亡者按新装配满血复位")
        Reset.restoreOrder(allies)
        check(allies[1] == a and allies[2] == b and a._slotOrder == 1 and b._slotOrder == 3,
            "下一波还原实际槽顺序且不改列表引用")

        -- 真实Runtime复活临时倍率，分别覆盖快照和无快照替换attrs。
        for _, fallback in ipairs({ false, true }) do
            local revived = { name = "复活夹具", hp = 100, maxHp = 100,
                attrs = UA.create({ [AD.MAX_HP] = 100, atkType = AD.ATK_SLASH }),
                artifactEffects = { { effectType = "revive_damage_bonus", value = 80 } } }
            Reset.createSnapshot(revived)
            ART.initBattle({ revived })
            revived.attrs.final[AD.HP], revived.hp = 0, 0
            check(ART.onAllyDeath(revived), "旧波真实复活倍率已触发 fallback=" .. tostring(fallback))
            local old = revived.attrs
            near(old.artifactExtraDamageMult, 1.8, "旧波临时倍率1.8")
            if fallback then
                revived.heroId, revived.partySlot, revived.artifactTeamIdx = 3, 4, 2
                revived._baseSnapshot = nil
                Reset.resetAllyUnit(revived, { revived }, combat.syncUnitHp)
            else
                local clean = UA.create({ [AD.MAX_HP] = 100, atkType = AD.ATK_SLASH })
                clean.artifactExtraDamageMult = 1.32
                revived._pendingSnapshot, revived._pendingArtifactEffects = clean, {}
                Reset.restoreFromSnapshot(revived)
            end
            check(old.artifactExtraDamageMult == nil, "临时倍率撤销发生在旧attrs")
            ART.reset({ revived })
            near(revived.attrs.artifactExtraDamageMult, 1.32, "新attrs1.32不被旧临时倍率重复除掉")
        end
        check(require == nativeRequire, "隔离加载未修改全局require或初始化存档")
    end)
    if not ok then failures[#failures + 1] = tostring(err); print("[FAIL] 异常: " .. tostring(err)) end
    print(string.format("%s %s assertions=%d failures=%d", TAG,
        #failures == 0 and "ALL PASS" or "FAIL", assertions, #failures))
    if #failures > 0 then log:Write(LOG_ERROR, TAG .. " FAILURES=" .. #failures) end
    engine:Exit()
end
