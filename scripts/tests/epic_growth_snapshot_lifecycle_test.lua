-- 史诗成长快照生命周期：真实 HeroConfig/ETS/UA/Reset/Lifecycle，独立 Runtime。
-- owned/编队/神器输入仅内存；不载入主入口，不读玩家档，不调用保存或构建。
-- /workspace/.cli/UrhoXRuntime tests/epic_growth_snapshot_lifecycle_test.lua \
--   -tapcode_dir=/workspace -tool_mode -graphicsheadless -nosound
local assertions, failures, cases = 0, 0, 0
local function check(value, message)
    assertions = assertions + 1
    if not value then failures = failures + 1; print("[EpicGrowthSnapshot][FAIL] " .. message) end
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end
local function awake()
    return { [1] = true, [2] = true, _awk3Migrated = true }
end

function Start()
    local nativeRequire = require
    local originals = { File = File, FileSystem = FileSystem, fileSystem = fileSystem, GetFileSystem = GetFileSystem }
    local storage, sends, patches, creates, income, setters, syncs = 0, 0, 0, 0, 0, 0, 0
    local batches = 0
    local allowCommit = false
    local patchRefresh = false
    local patchCallback = function() end
    local sentPayloads = {}
    local function denyIO() storage = storage + 1; error("EpicGrowthSnapshot forbids File/FS") end
    rawset(_G, "File", denyIO)
    rawset(_G, "FileSystem", denyIO)
    rawset(_G, "GetFileSystem", denyIO)
    rawset(_G, "fileSystem", setmetatable({}, { __index = function() return denyIO end }))
    ---@type table<number, table>
    local owned = {}
    ---@type table[]
    local allies = {}
    ---@type table[]
    local enemies = {}
    ---@type table<string, any>
    local scene = { battleActive = true, currentStageId = 101, isFirstClear = false }
    ---@type table[]
    local created = {}
    local failedHero = 0
    local artifactEffects = {}
    local equipmentCalls, artifactCalls = {}, {}
    local mocks = {
        ["ui.character.panel.CharacterPanel"] = {
            getOwnedHero = function(id) return owned[id] end,
            getEffectiveLevel = function(id) return owned[id] and owned[id].level end,
            getHeroDeployPosition = function(id, team)
                for _, u in ipairs(allies) do if u.heroId == id then return u.partySlot, team or u.artifactTeamIdx end end
            end,
            applyEquippedItems = function(attrs, id, slot)
                equipmentCalls[#equipmentCalls + 1] = { attrs = attrs, id = id, slot = slot }
            end,
            patchExtraTalent = function(id, extra)
                assert(allowCommit, "No player patches outside real commit cases")
                patches = patches + 1
                assert(owned[id]); owned[id].extraTalent = copy(extra)
                if patchRefresh then patchCallback() end
            end,
            finishExtraTalentBatch = function()
                assert(allowCommit, "No player batch outside real commit cases")
                batches = batches + 1
            end,
        },
        ["systems.ArtifactBridge"] = { applyToUnit = function(attrs, slot, _, team)
            artifactCalls[#artifactCalls + 1] = { attrs = attrs, slot = slot, team = team }
            return artifactEffects
        end },
        ["runtime.GameAction"] = { sendAction = function(_, payload)
            assert(allowCommit, "No persistence action outside real commit cases")
            sends = sends + 1; sentPayloads[#sentPayloads + 1] = copy(payload)
        end },
        ["runtime.ClientDispatcher"] = { get = function(key) if key == "heroes" then return { roster = owned } end end },
        ["ui.fx.SpineCardEffect"] = { playLevelUp = function() end },
    }
    rawset(_G, "require", function(name) return mocks[name] or nativeRequire(name) end)
    local ok, err = pcall(function()
        local AD = require("systems.AttributeDef")
        local HC = nativeRequire("config.HeroConfig")
        local ETS = require("systems.ExtraTalentSystem")
        local Reset = require("ui.battle.scene.BattleAllyReset")
        local Lifecycle = require("ui.battle.scene.BattleAllyLifecycle")
        local BC = require("ui.battle.combat.BattleCombat")
        HC.setDefaultLitNodes({})
        mocks["config.HeroConfig"] = { createHero = function(id, level, branch, awakening, extra)
            creates = creates + 1
            if id == failedHero then return nil end
            local unit = HC.createHero(id, level, branch, awakening, extra, { litNodes = {}, silent = true })
            created[#created + 1] = unit
            return unit
        end }
        local function makeHero(id, extra, level)
            owned[id] = { level = level or 20, awakening = awake(), extraTalent = extra }
            local u = assert(HC.createHero(id, level or 20, nil, awake(), extra, { litNodes = {}, silent = true }))
            u.partySlot, u.artifactTeamIdx = 2, 3
            return u
        end
        local function reset(u)
            Reset.resetAllyUnit(u, allies, function(unit) syncs = syncs + 1; BC.syncUnitHp(unit) end)
        end
        local life = Lifecycle.bind({
            getAllies = function() return allies end,
            getEnemies = function() return enemies end,
            getEnemyQueue = function() return {} end,
            getStageConfig = function() return require("config.StageConfig") end,
            getStageMaxFieldEnemies = function() return 4 end,
            get = function(key) return scene[key] end,
            set = function(key, value)
                setters = setters + 1
                if key == "allies" then allies = value else scene[key] = value end
            end,
            resetAllyUnit = reset,
            startBattleTalents = function() end,
            recalcIdleIncome = function() income = income + 1 end,
            loadStage = function() end,
            MAX_FIELD_ALLIES = 4, ALLY_CARD_CY = 1760,
        })
        patchCallback = life.refreshAllyStats
        local function runCase(name, fn)
            cases = cases + 1
            local before = failures
            local success, detail = pcall(fn)
            if not success then check(false, name .. " exception: " .. tostring(detail)) end
            print(string.format("[EpicGrowthSnapshot] case=%s failures=%d", name, failures - before))
        end
        local function checkPendingCleared(u, message)
            check(u._pendingSnapshot == nil and u._pendingEpicAwakeningGrowth == nil
                and u._hasPendingEpicAwakeningGrowth == nil, message)
        end

        runCase("formal setAllies/base isolation", function()
            local input = { stacks = 100, shareCount = 8, tickets = { alpha = true }, markTypes = { fire = true } }
            local u = makeHero(10, input)
            local source = copy(input)
            local firstGrowth = u._epicAwakeningGrowth
            check(u.quality == 3 and firstGrowth ~= input and firstGrowth.tickets ~= input.tickets,
                "real HC normalizes and deep-copies explicit epic growth")
            life.setAllies({ u })
            check(u._hasBaseEpicAwakeningGrowth == true and same(u._baseEpicAwakeningGrowth, ETS.normalize(source)),
                "formal setAllies captures epic base with attrs")
            check(u._epicAwakeningGrowth ~= u._baseEpicAwakeningGrowth
                and u._epicAwakeningGrowth.tickets ~= u._baseEpicAwakeningGrowth.tickets,
                "restored current wave and baseline do not share nested maps")
            input.shareCount, input.tickets.alpha = 900, nil
            u._epicAwakeningGrowth.shareCount, u._epicAwakeningGrowth.tickets.alpha = 777, nil
            reset(u)
            check(ETS.getEpicGrowth(u).shareCount == 8 and ETS.getEpicGrowth(u).tickets.alpha == true,
                "same unit restart restores initial baseline despite source/live mutation")
            check(same(u._baseEpicAwakeningGrowth, ETS.normalize(source)), "restart does not mutate base growth")
            local read = ETS.getEpicGrowth(u)
            read.shareCount, read.tickets.alpha = 555, nil
            check(ETS.getEpicGrowth(u).shareCount == 8 and u._epicAwakeningGrowth.tickets.alpha,
                "ETS getter does not publish live/base aliases")
        end)

        runCase("refresh deferred with attrs/artifacts", function()
            local u = makeHero(10, { shareCount = 4, stacks = 4 })
            allies = { u }; Reset.createSnapshot(u)
            u.attrs.final[AD.HP] = 0; BC.syncUnitHp(u)
            u.reviveTimer, u.atkProgress = 0.7, 0.6
            u.artifactEffects = { { kind = "old" } }
            local oldAttrs, oldBase, oldGrowth = u.attrs, u._baseSnapshot, u._epicAwakeningGrowth
            local oldFinal, oldBaseFinal, oldBaseGrowth = copy(u.attrs.final), copy(u._baseSnapshot.final), copy(u._baseEpicAwakeningGrowth)
            owned[10].extraTalent = { shareCount = 12, stacks = 12, tickets = { new = true } }
            owned[10].level = 21
            artifactEffects = {}
            local oldSetters, oldIncome = setters, income
            life.refreshAllyStats()
            local newUnit = created[#created]
            check(u.attrs == oldAttrs and same(u.attrs.final, oldFinal)
                and u._baseSnapshot == oldBase and same(u._baseSnapshot.final, oldBaseFinal),
                "refresh does not modify live or base attrs")
            check(u._epicAwakeningGrowth == oldGrowth and ETS.getEpicGrowth(u).shareCount == 4
                and same(u._baseEpicAwakeningGrowth, oldBaseGrowth), "refresh does not advance current-wave/base epic growth")
            check(u.hp == 0 and u.reviveTimer == 0.7 and u.atkProgress == 0.6 and #u.artifactEffects == 1,
                "refresh leaves death/revive/progress/live artifact state unchanged")
            check(u._pendingSnapshot == newUnit.attrs and u._hasPendingEpicAwakeningGrowth
                and same(u._pendingEpicAwakeningGrowth, newUnit._epicAwakeningGrowth), "new attrs and growth staged together")
            check(u._pendingEpicAwakeningGrowth ~= newUnit._epicAwakeningGrowth
                and u._pendingEpicAwakeningGrowth.tickets ~= newUnit._epicAwakeningGrowth.tickets,
                "pending does not alias rebuilt unit growth")
            check(setters == oldSetters and income == oldIncome + 1, "refresh retains existing no-scene-set/income contract")
            local eq, art = equipmentCalls[#equipmentCalls], artifactCalls[#artifactCalls]
            check(eq.slot == 2 and art.slot == 2 and art.team == 3, "refresh uses true party slot and artifact team")
            local pendingAttrs, pendingGrowth = u._pendingSnapshot, copy(u._pendingEpicAwakeningGrowth)
            owned[10].extraTalent.shareCount, owned[10].extraTalent.tickets.new = 999, nil
            newUnit._epicAwakeningGrowth.shareCount = 888
            check(same(u._pendingEpicAwakeningGrowth, pendingGrowth), "source/temporary unit changes do not rewrite pending")
            check(Reset.restoreFromSnapshot(u), "next-wave restore succeeds")
            check(same(u.attrs.final, pendingAttrs.final) and ETS.getEpicGrowth(u).shareCount == 12,
                "next-wave attrs and frozen epic growth switch together")
            check(u.level == 21 and u.artifactEffects == nil and u.hp == 0,
                "raw snapshot restore consumes level/artifact but does not independently revive")
            checkPendingCleared(u, "commit consumes both pending payloads/has marker")
            check(u._epicAwakeningGrowth ~= u._baseEpicAwakeningGrowth
                and u._epicAwakeningGrowth.tickets ~= u._baseEpicAwakeningGrowth.tickets,
                "committed wave/base remain independent")
            u._epicAwakeningGrowth.shareCount = 600
            reset(u)
            check(ETS.getEpicGrowth(u).shareCount == 12 and u.hp == u.maxHp, "same-unit reset retains committed baseline and original fillHp behavior")
        end)

        runCase("pending replacement/nil/explicit zero", function()
            local u = makeHero(13, { splitKills = 64 })
            allies = { u }; Reset.createSnapshot(u)
            owned[13].extraTalent = { splitKills = 128 }; life.refreshAllyStats()
            owned[13].extraTalent = nil; life.refreshAllyStats()
            check(u._hasPendingEpicAwakeningGrowth == true and u._pendingEpicAwakeningGrowth == nil,
                "nil replacement carries has marker and clears previous pending payload")
            check(ETS.getEpicGrowth(u).splitKills == 64, "nil pending does not prematurely clear current wave")
            Reset.restoreFromSnapshot(u)
            check(u._epicAwakeningGrowth == nil and u._baseEpicAwakeningGrowth == nil,
                "nil commit explicitly clears old live/base payload")
            owned[13].extraTalent = { splitKills = 21 }
            check(ETS.getEpicGrowth(u).splitKills == 21, "nil instance preserves legacy dynamic-owned source")
            reset(u)
            check(u._epicAwakeningGrowth == nil and ETS.getEpicGrowth(u).splitKills == 21, "nil baseline stays dynamic after restart")
            owned[13].extraTalent = { splitKills = 256 }; life.refreshAllyStats()
            owned[13].extraTalent = 0; life.refreshAllyStats()
            check(u._hasPendingEpicAwakeningGrowth and same(u._pendingEpicAwakeningGrowth, ETS.normalize(nil)),
                "real HC explicit numeric zero creates empty normalized pending, replacing old growth")
            Reset.restoreFromSnapshot(u)
            owned[13].extraTalent = { splitKills = 9999 }
            check(type(u._epicAwakeningGrowth) == "table" and ETS.getEpicGrowth(u).splitKills == 0,
                "explicit zero stays bound to zero instead of borrowing owned")
            reset(u)
            check(ETS.getEpicGrowth(u).splitKills == 0, "zero baseline survives same-unit restart")
            checkPendingCleared(u, "zero commit clears pending markers")
        end)

        runCase("legacy absent/non-epic/disabled", function()
            local u = makeHero(11, nil)
            allies = { u }; Reset.createSnapshot(u)
            owned[11].extraTalent = { stacks = 300, slashShadows = 4 }
            reset(u)
            check(u._epicAwakeningGrowth == nil and u._hasBaseEpicAwakeningGrowth == nil
                and ETS.getEpicGrowth(u).stacks == 300, "omitted HC input remains unbound/dynamic across reset")
            local disabled = makeHero(11, false)
            Reset.createSnapshot(disabled); reset(disabled)
            check(disabled._etsDisabled == true and disabled._epicAwakeningGrowth == nil
                and same(ETS.getEpicGrowth(disabled), ETS.normalize(nil)), "false opponent stays disabled/empty")
            for _, id in ipairs({ 1, 4, 16, 20, 25 }) do
                local other = makeHero(id, { stacks = 80 })
                allies = { other }; Reset.createSnapshot(other)
                owned[id].extraTalent = { stacks = 90 }; life.refreshAllyStats()
                check(other.quality ~= 3 and other._epicAwakeningGrowth == nil
                    and other._hasBaseEpicAwakeningGrowth == nil and other._hasPendingEpicAwakeningGrowth == nil,
                    "non-epic never receives snapshot markers id=" .. id)
                Reset.restoreFromSnapshot(other)
                check(other._epicAwakeningGrowth == nil, "non-epic restore leaves legacy source id=" .. id)
            end
        end)

        runCase("different epic heroes and all ten IDs", function()
            local epicIds = { 10, 11, 12, 13, 14, 15, 21, 22, 23, 24 }
            for _, id in ipairs(epicIds) do
                local extra = { stacks = id, splitKills = id * 2, tickets = { [tostring(id)] = true } }
                local u = makeHero(id, extra)
                allies = { u }; Reset.createSnapshot(u)
                local oldGrowth = copy(u._epicAwakeningGrowth)
                owned[id].extraTalent = { stacks = id + 100, splitKills = id * 3, tickets = { next = true } }
                life.refreshAllyStats()
                check(u.quality == 3 and same(u._epicAwakeningGrowth, oldGrowth), "epic current-wave isolation id=" .. id)
                Reset.restoreFromSnapshot(u)
                check(ETS.getEpicGrowth(u).stacks == id + 100 and ETS.getEpicGrowth(u).splitKills == id * 3,
                    "epic commit captured exact own growth id=" .. id)
            end
            local a = makeHero(11, { stacks = 100, slashShadows = 2 })
            local b = makeHero(13, { stacks = 20, splitKills = 30 })
            allies = { a, b }; Reset.createSnapshot(a); Reset.createSnapshot(b)
            owned[11].extraTalent = { stacks = 200, slashShadows = 4 }
            owned[13].extraTalent = { stacks = 60, splitKills = 80 }
            life.refreshAllyStats()
            Reset.restoreFromSnapshot(a)
            check(ETS.getEpicGrowth(a).stacks == 200 and ETS.getEpicGrowth(b).stacks == 20
                and b._pendingEpicAwakeningGrowth.splitKills == 80, "restoring one hero cannot commit another hero pending")
            Reset.restoreFromSnapshot(b)
            check(ETS.getEpicGrowth(b).splitKills == 80 and a._epicAwakeningGrowth ~= b._epicAwakeningGrowth,
                "different hero instances do not share payload")
        end)

        runCase("missing base rebuild and failed rebuild", function()
            local u = makeHero(10, { shareCount = 5 })
            allies = { u }; Reset.createSnapshot(u)
            u._baseSnapshot = nil
            owned[10].extraTalent = { shareCount = 17, tickets = { rebuilt = true } }
            local oldCreates = creates
            reset(u)
            check(creates == oldCreates + 1 and ETS.getEpicGrowth(u).shareCount == 17
                and u._baseEpicAwakeningGrowth.shareCount == 17, "missing base fallback rebuild adopts newUnit growth alongside attrs")
            check(u._epicAwakeningGrowth ~= created[#created]._epicAwakeningGrowth
                and u._epicAwakeningGrowth ~= u._baseEpicAwakeningGrowth, "fallback copies newUnit and baseline independently")
            u._baseSnapshot = nil; owned[10].extraTalent = nil; reset(u)
            check(u._epicAwakeningGrowth == nil and u._baseEpicAwakeningGrowth == nil,
                "fallback nil source clears stale growth rather than retaining previous explicit value")
            owned[10].extraTalent = { shareCount = 32 }; u._baseSnapshot = nil; reset(u)
            owned[10].extraTalent = 0; u._baseSnapshot = nil; reset(u)
            check(ETS.getEpicGrowth(u).shareCount == 0 and type(u._epicAwakeningGrowth) == "table",
                "fallback explicit zero clears old snapshot to bound zero")
            local beforeAttrs, beforeGrowth = u.attrs, u._epicAwakeningGrowth
            u._baseSnapshot = nil; failedHero = 10
            owned[10].extraTalent = { shareCount = 500 }
            reset(u)
            check(u.attrs == beforeAttrs and u._epicAwakeningGrowth == beforeGrowth and ETS.getEpicGrowth(u).shareCount == 0,
                "failed rebuild keeps existing attrs/growth together without borrowing newly owned")
            check(u._baseSnapshot ~= nil and u._baseEpicAwakeningGrowth.shareCount == 0,
                "failed fallback snapshots retained old attrs/growth, preserving existing recovery path")
            failedHero = 0
            owned[10].extraTalent = { shareCount = 41 }; life.refreshAllyStats()
            u._baseSnapshot = nil; oldCreates = creates
            reset(u)
            check(creates == oldCreates and ETS.getEpicGrowth(u).shareCount == 41,
                "valid pending repairs absent base without invoking unrelated fallback rebuild")
            checkPendingCleared(u, "repaired base consumes pending growth")
        end)

        runCase("same unit recapture clears pending and old base", function()
            local u = makeHero(13, { splitKills = 10 })
            allies = { u }; Reset.createSnapshot(u)
            owned[13].extraTalent = { splitKills = 20 }; life.refreshAllyStats()
            u._epicAwakeningGrowth = ETS.normalize({ splitKills = 30 })
            Reset.createSnapshot(u)
            checkPendingCleared(u, "createSnapshot discards abandoned old pending payload/marker")
            reset(u)
            check(ETS.getEpicGrowth(u).splitKills == 30, "same-unit recapture does not restore stale previous base")
            u._epicAwakeningGrowth = nil; Reset.createSnapshot(u)
            owned[13].extraTalent = { splitKills = 40 }; reset(u)
            check(u._baseEpicAwakeningGrowth == nil and u._hasBaseEpicAwakeningGrowth == nil
                and u._epicAwakeningGrowth == nil and ETS.getEpicGrowth(u).splitKills == 40,
                "same-unit recapture to omitted snapshot clears old base and preserves dynamic source")
        end)
        runCase("real reloadStage exit and failed refresh", function()
            local u = makeHero(13, { splitKills = 12 })
            allies = { u }; Reset.createSnapshot(u)
            owned[13].extraTalent = { splitKills = 24 }; life.refreshAllyStats()
            local pendingAttrs, pendingGrowth = u._pendingSnapshot, u._pendingEpicAwakeningGrowth
            failedHero = 13; owned[13].extraTalent = { splitKills = 999 }; life.refreshAllyStats()
            check(u._pendingSnapshot == pendingAttrs and u._pendingEpicAwakeningGrowth == pendingGrowth
                and u._hasPendingEpicAwakeningGrowth == true and ETS.getEpicGrowth(u).splitKills == 12,
                "failed refresh cannot replace valid pending or advance current wave")
            failedHero = 0
            life.reloadStage({ startSearching = true })
            check(u._pendingSnapshot == pendingAttrs and ETS.getEpicGrowth(u).splitKills == 12,
                "searching reload follows old no-reset branch and preserves deferred growth")
            life.reloadStage()
            check(ETS.getEpicGrowth(u).splitKills == 24 and u._baseEpicAwakeningGrowth.splitKills == 24,
                "real reloadStage resetAllyUnit exit commits matching attrs/growth")
            checkPendingCleared(u, "reloadStage consumes pending attrs/growth together")
            local oldGrowth = copy(u._epicAwakeningGrowth)
            local orphan = ETS.normalize({ splitKills = 48 })
            u._pendingEpicAwakeningGrowth, u._hasPendingEpicAwakeningGrowth = orphan, true
            Reset.restoreFromSnapshot(u)
            check(same(u._epicAwakeningGrowth, oldGrowth) and u._pendingEpicAwakeningGrowth == orphan,
                "growth-only orphan cannot commit without its attrs snapshot")
            Reset.createSnapshot(u)
            checkPendingCleared(u, "explicit recapture clears abandoned growth-only pending")
        end)
        runCase("committed live growth vs paired base/pending", function()
            local u = makeHero(10, { shareCount = 2, stacks = 2 })
            allies = { u }; Reset.createSnapshot(u)
            local baseAttrs, baseGrowth = copy(u._baseSnapshot.final), copy(u._baseEpicAwakeningGrowth)
            -- 模拟 ETS 已在战后同步的 live 结果；不调用持久化，真实 applyToAttrs 重算。
            local committed = ETS.normalize({ shareCount = 3, stacks = 3 })
            ETS.applyToAttrs(10, u.attrs, committed, u.awakeningNodes)
            u._epicAwakeningGrowth = copy(committed)
            check(u.attrs:get(AD.MAX_HP) > baseAttrs[AD.MAX_HP] and ETS.getEpicGrowth(u).shareCount == 3,
                "fixture has genuinely changed live attrs and committed live growth")
            Reset.restoreFromSnapshot(u)
            check(same(u.attrs.final, baseAttrs) and same(u._epicAwakeningGrowth, baseGrowth),
                "without pending restore chooses paired old base attrs/growth, not newer live growth with old attrs")
            owned[10].extraTalent = { shareCount = 8, stacks = 8 }; life.refreshAllyStats()
            local pendingAttrs, pendingGrowth = copy(u._pendingSnapshot.final), copy(u._pendingEpicAwakeningGrowth)
            committed = ETS.normalize({ shareCount = 4, stacks = 4 })
            ETS.applyToAttrs(10, u.attrs, committed, u.awakeningNodes)
            u._epicAwakeningGrowth = copy(committed)
            check(same(u._baseSnapshot.final, baseAttrs) and same(u._baseEpicAwakeningGrowth, baseGrowth)
                and same(u._pendingSnapshot.final, pendingAttrs) and same(u._pendingEpicAwakeningGrowth, pendingGrowth),
                "later committed live result cannot rewrite frozen base or pending pair")
            Reset.restoreFromSnapshot(u)
            check(same(u.attrs.final, pendingAttrs) and same(u._epicAwakeningGrowth, pendingGrowth),
                "valid pending pair wins over newer live value and old base together")
            checkPendingCleared(u, "paired priority commit consumes pending")
        end)
        check(storage == 0 and sends == 0 and patches == 0, "non-commit lifecycle cases never use storage/persistence")
        allowCommit = true
        local function freshState()
            ETS.mount(ETS.newState())
            patchRefresh = false
        end
        local function ricochetKill(u)
            local dead = { hp = 0, _killedBy = u, _killedByRicochet = true }
            ETS.onEnemyDeath(dead, { u }, { dead })
        end
        local function expectedAttrs(u, growth)
            local expected = HC.createHero(u.heroId, u.level, u.advBranch, u.awakeningNodes, growth,
                { litNodes = {}, silent = true })
            return assert(expected).attrs
        end
        runCase("real ricochet commit flush reload double restore", function()
            freshState()
            local u = makeHero(13, { stacks = 98, splitKills = 49 })
            allies = { u }; Reset.createSnapshot(u)
            local oldBase = copy(u._baseSnapshot.final)
            ricochetKill(u)
            check(ETS.getEpicGrowth(u).splitKills == 50 and owned[13].extraTalent.splitKills == 50,
                "real immediate ricochet mechanism commit advances 49 to 50")
            check(u._epicCommittedGrowthDelta.splitKills == 1 and u._baseEpicCommittedGrowthDelta == nil,
                "real commit records unit ledger but does not mutate base captured ledger")
            ETS.flush()
            check(ETS.getEpicGrowth(u).stacks == 100 and u._epicCommittedGrowthDelta.stacks == 2,
                "real permanent event flush advances live snapshot and ledger by exact stacks delta")
            check(same(u._baseSnapshot.final, oldBase), "commit/flush do not eagerly rewrite old base attrs")
            life.reloadStage()
            check(ETS.getEpicGrowth(u).splitKills == 50 and ETS.getEpicGrowth(u).stacks == 100,
                "reload no longer rolls back committed mechanism or permanent growth")
            check(same(u.attrs.final, expectedAttrs(u, ETS.normalize({ stacks = 100, splitKills = 50 })).final),
                "reload recomputes legal permanent delta via original real HC/ETS formula")
            local growth, attrs, ledger = copy(u._epicAwakeningGrowth), copy(u.attrs.final), copy(u._baseEpicCommittedGrowthDelta)
            Reset.restoreFromSnapshot(u); Reset.restoreFromSnapshot(u)
            check(same(u._epicAwakeningGrowth, growth) and same(u.attrs.final, attrs)
                and same(u._baseEpicCommittedGrowthDelta, ledger), "two restores cannot count committed delta twice")
            ricochetKill(u); ETS.flush(); life.reloadStage()
            check(ETS.getEpicGrowth(u).splitKills == 51 and ETS.getEpicGrowth(u).stacks == 102,
                "second real kill after reload adds exactly once to updated baseline")
        end)
        runCase("late pending contains some committed delta", function()
            freshState()
            local u = makeHero(13, { stacks = 98, splitKills = 49 })
            allies = { u }; Reset.createSnapshot(u)
            ricochetKill(u); ETS.flush()
            life.refreshAllyStats()
            check(u._pendingEpicAwakeningGrowth.splitKills == 50 and u._pendingEpicCommittedGrowthDelta.splitKills == 1
                and u._pendingEpicCommittedGrowthDelta.stacks == 2,
                "pending built after first commit captures its already-contained ledger")
            check(u._pendingEpicCommittedGrowthDelta ~= u._epicCommittedGrowthDelta,
                "pending captured ledger is a copy, not live alias")
            ricochetKill(u); ETS.flush()
            check(u._pendingEpicAwakeningGrowth.splitKills == 50 and u._pendingEpicCommittedGrowthDelta.splitKills == 1,
                "second commit does not mutate pre-existing late pending")
            Reset.restoreFromSnapshot(u)
            check(ETS.getEpicGrowth(u).splitKills == 51 and ETS.getEpicGrowth(u).stacks == 102,
                "restore adds only later missing delta, not first already-contained delta")
            Reset.restoreFromSnapshot(u)
            check(ETS.getEpicGrowth(u).splitKills == 51 and ETS.getEpicGrowth(u).stacks == 102,
                "late pending second restore remains exact")
        end)
        runCase("patch synchronous refresh and later commit", function()
            freshState()
            local u = makeHero(13, { stacks = 98, splitKills = 49 })
            allies = { u }; Reset.createSnapshot(u)
            -- 明确注入CP内存patch重入refresh，非声称正式CP默认必定走该回调。
            patchRefresh = true
            ricochetKill(u); ETS.flush()
            patchRefresh = false
            check(u._pendingEpicAwakeningGrowth.splitKills == 50 and u._pendingEpicAwakeningGrowth.stacks == 100,
                "injected synchronous CP patch callback rebuilt pending from actually committed owned")
            check(u._pendingEpicCommittedGrowthDelta.splitKills == 1 and u._pendingEpicCommittedGrowthDelta.stacks == 2,
                "patch-created pending ledger acknowledges commit included in its owned rebuild")
            ricochetKill(u); ETS.flush()
            Reset.restoreFromSnapshot(u)
            check(ETS.getEpicGrowth(u).splitKills == 51 and ETS.getEpicGrowth(u).stacks == 102,
                "patch-created pending plus later commit restore cannot double count first commit")
            Reset.restoreFromSnapshot(u)
            check(ETS.getEpicGrowth(u).splitKills == 51 and ETS.getEpicGrowth(u).stacks == 102,
                "synchronous patch second restore remains exact")
        end)
        runCase("external explicit zero nil and HP delta", function()
            freshState()
            local u = makeHero(10, { shareCount = 4, stacks = 4 })
            allies = { u }; Reset.createSnapshot(u)
            owned[10].extraTalent = ETS.normalize({ shareCount = 100, stacks = 100 })
            u.attrs.final[AD.HP] = 0; BC.syncUnitHp(u)
            ETS.onShareFatal(u); ETS.flush()
            check(ETS.getEpicGrowth(u).shareCount == 5 and owned[10].extraTalent.shareCount == 101,
                "external unit applies own legal +1 delta, not account whole-growth snapshot")
            Reset.restoreFromSnapshot(u)
            check(ETS.getEpicGrowth(u).shareCount == 5 and u.attrs:get(AD.HP) > 0,
                "raw restore retains pre-existing base HP semantics and external growth plus delta")
            check(u.attrs:get(AD.MAX_HP) == expectedAttrs(u, ETS.normalize({ shareCount = 5, stacks = 5 })):get(AD.MAX_HP),
                "external paired attrs use +1 growth not account 101 growth")
            reset(u)
            check(u.hp == u.maxHp and ETS.getEpicGrowth(u).shareCount == 5,
                "normal next-wave reset fills HP once while retaining delta baseline")
            owned[10].extraTalent = 0; life.refreshAllyStats()
            owned[10].extraTalent = ETS.normalize({ shareCount = 200, stacks = 200 })
            ETS.onShareFatal(u); ETS.flush(); Reset.restoreFromSnapshot(u)
            check(ETS.getEpicGrowth(u).shareCount == 1 and ETS.getEpicGrowth(u).stacks == 1,
                "explicit zero pending receives only legal post-capture delta, not old ledger or account amount")
            owned[10].extraTalent = nil; life.refreshAllyStats()
            owned[10].extraTalent = ETS.normalize({ shareCount = 300, stacks = 300 })
            ETS.onShareFatal(u); ETS.flush(); Reset.restoreFromSnapshot(u)
            check(u._epicAwakeningGrowth == nil and ETS.getEpicGrowth(u).shareCount == 301,
                "nil pending clears binding and uses dynamic owned, never forces ledger snapshot")
            check(u._epicCommittedGrowthDelta.shareCount == 3, "restore never clears cumulative unit ledger")
        end)
        local transient = { "_epicCommittedGrowthDelta", "_baseEpicCommittedGrowthDelta", "_pendingEpicCommittedGrowthDelta",
            "_epicAwakeningGrowth", "_baseEpicAwakeningGrowth", "_pendingEpicAwakeningGrowth" }
        for _, payload in ipairs(sentPayloads) do
            check(same(payload.extraTalent, ETS.normalize(payload.extraTalent)), "real ETS send payload stays original normalized permanent schema")
            for _, field in ipairs(transient) do
                check(payload[field] == nil and payload.extraTalent[field] == nil, "temporary ledger absent from send payload " .. field)
            end
        end
        check(creates > 0 and syncs > 0 and patches > 0 and sends > 0 and batches > 0,
            "real lifecycle plus commit/flush with memory-only CP/send executed")
        check(storage == 0, "real commit/flush lifecycle still uses closed File/FS")
    end)
    if not ok then check(false, "unhandled exception: " .. tostring(err)) end
    check(storage == 0, "closed File/FS boundary was not touched")
    rawset(_G, "require", nativeRequire)
    rawset(_G, "File", originals.File)
    rawset(_G, "FileSystem", originals.FileSystem)
    rawset(_G, "fileSystem", originals.fileSystem)
    rawset(_G, "GetFileSystem", originals.GetFileSystem)
    print(string.format("[epic_growth_snapshot_lifecycle_test] cases=%d assertions=%d failures=%d FileFS=%d sends=%d patches=%d %s",
        cases, assertions, failures, storage, sends, patches, failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
