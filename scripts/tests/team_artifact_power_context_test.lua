------------------------------------------------------------------------
-- team_artifact_power_context_test.lua —— 战力与星门的所属队回归
-- 独立 Runtime 进程；存档全部内存替身，不启动 main、不加载/写入玩家存档。
-- tests/team_artifact_power_context_test.lua -tapcode_dir=. -tool_mode -graphicsheadless
------------------------------------------------------------------------
local AD = require("systems.AttributeDef")
local HC = require("config.HeroConfig")
local Eq = require("systems.EquipmentSystem")
local EC = require("config.EquipmentConfig")
local ES = require("systems.EquipmentSetSystem")
local AC = require("config.AwakeningConfig")
local TE = require("systems.TalentEffect")
local Artifact = require("systems.ArtifactBridge")
local Power = require("ui.character.panel.CharacterPower")
local Attrs = require("ui.character.detail.CharacterDetailAttrs")
local Store = require("core.PlayerStore")
local Dispatcher = require("runtime.ClientDispatcher")
local Melissa = require("systems.talents.TalentMelissa")

local assertions, failures = 0, 0
local function check(ok, message)
    assertions = assertions + 1
    if ok then print("[PASS] " .. message)
    else failures = failures + 1; print("[FAIL] " .. message) end
end
local function close(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.000001
end
local function copy(v)
    if type(v) ~= "table" then return v end
    local r = {}
    for k, item in pairs(v) do r[k] = copy(item) end
    return r
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function slots(ids)
    local r = {}
    for i = 1, 4 do
        local id = ids[i]
        r[i] = id and { state = "occupied", heroId = id } or { state = "empty" }
    end
    return r
end
local function row(data, key)
    for _, r in ipairs(data.right) do if r.key == key then return r.numericValue end end
    return nil
end

function Start()
    print("[team_artifact_power_context_test] start")
    local savedLit = HC._getSavedLitNodes()
    local oldGet, oldStoreGet = Dispatcher.get, Store.Get
    local oldPanel = package.loaded["ui.character.panel.CharacterPanel"]
    local ownedReads = 0
    package.loaded["ui.character.panel.CharacterPanel"] = {
        getOwnedHero = function() ownedReads = ownedReads + 1; error("unexpected real owned fallback") end,
    }
    HC.setDefaultLitNodes(nil)
    local data = { equipment = { inventory = {}, equipped = {} }, talents = { litNodes = {} },
        artifacts = { bag = {
            { id = "a", artifactId = 5, value = 20 },
            { id = "b", artifactId = 5, value = 80 },
            { id = "c", artifactId = 5, value = 140 },
        }, equippedByTeam = { { { "a" } }, { { "b" } }, { { "c" } } } } }
    local writes, reads = 0, 0
    Dispatcher.get = function(k) reads = reads + 1; return data[k] end
    Store.Get = function(k) reads = reads + 1; return data[k] end
    local ok, err = pcall(function()
        local owned = {}
        for _, id in ipairs({ 1, 2, 3, 5, 6, 7, 8, 20 }) do
            owned[id] = { level = 70, awakening = {}, extraTalent = {} }
        end
        local teams = { { slots = slots({ 1 }) }, { slots = slots({ 2, 3 }) },
            { slots = slots({ 6, 7, 8 }) } }
        local state = { ownedSet = owned, teams = teams, teamSlots = teams[1].slots,
            teamPowerCaches = { {}, {}, {} }, heroRoster = {
                { heroId = 2, owned = true }, { heroId = 6, owned = true },
                { heroId = 5, owned = true }, { heroId = 999, owned = false },
            }, rosterPowerCache = {} }
        local gamePower, dirty = 0, 0
        local power = Power.bind({ AD = AD, HC = HC, EquipmentSystem = Eq, EquipmentConfig = EC,
            AwakeningConfig = AC, TalentEffect = TE, ClientDispatcher = Dispatcher, PlayerStore = Store,
            ArtifactBridge = { applyToUnit = function(a, slot, _data, team)
                return Artifact.applyToUnit(a, slot, data.artifacts, team)
            end }, GameState = { setPower = function(p) gamePower = p end },
            CharacterDetail = { markPowerDirty = function() dirty = dirty + 1 end },
            CharacterPanel = {}, BottomNav = {}, MAX_SLOTS = 4, TEAM_COUNT = 3,
            get = function(k) return state[k] end,
            set = function(k, v) state[k] = v; writes = writes + 1 end,
        })
        local artifactsBefore = copy(data.artifacts)
        local explicit2 = power.calcHeroPower(2, 1, 2)
        local explicit3 = power.calcHeroPower(6, 1, 3)
        local bench = power.calcHeroPower(5)
        check(power.calcHeroPower(2) == explicit2, "名册缺省战力读取英雄2所属队2神器，不随活动队1")
        check(power.calcHeroPower(6) == explicit3, "名册缺省战力读取英雄6所属队3神器")
        check(power.calcHeroPower(2, 1) == explicit2, "仅传partySlot旧调用补全英雄所属队而非默认队1")
        check(power.calcHeroEstimate(2) == power.calcHeroEstimate(2, 1, 2), "预估与正式战力共用所属队神器解析")
        for t = 1, 3 do
            state.teamSlots = teams[t].slots
            check(power.calcHeroPower(2) == explicit2 and power.calcHeroPower(6) == explicit3,
                "活动队切到" .. t .. "不改变单人战力与预估的所属队")
        end
        data.artifacts = { bag = {}, equippedByTeam = {} }
        local bare2, bare3 = power.calcHeroPower(2), power.calcHeroPower(6)
        check(explicit2 == bare2 + 40 and explicit3 == bare3 + 70, "真实神器桥队2/3固定战力分别40/70，正式公式不改")
        check(power.calcHeroPower(5) == bench, "未编队角色不借用活动槽神器")
        data.artifacts = copy(artifactsBefore)
        check(power.calcHeroPower(5, 1, 1) == bench, "未编队即使传入槽位也不能蹭队1神器")
        check(power.calcHeroPower(2, 1, 1) == bare2, "显式错误队伍不回退本队或默认队1神器")
        check(power.calcHeroPower(2, 2, 2) == bare2, "显式槽位不属于该英雄时不借旁人神器")
        if type(power.findHeroDeployPosition) == "function" then
            local slot, team = power.findHeroDeployPosition("2")
            check(slot == 1 and team == 2, "finder缺省扫全队、兼容英雄数字字符串")
            slot, team = power.findHeroDeployPosition(6, 3)
            check(slot == 1 and team == 3, "finder显式team3只查队3")
            check(power.findHeroDeployPosition(2, 1) == nil and power.findHeroDeployPosition(5) == nil,
                "finder显式错误队和未编队均返回nil")
            check(power.findHeroDeployPosition(0) == nil and power.findHeroDeployPosition(2, 4) == nil,
                "finder空槽0及非法队索引不借默认队1")
            local originalTeams = state.teams
            state.teams = { ["2"] = { slots = slots({ [4] = "2" }) } }
            slot, team = power.findHeroDeployPosition("2", 2)
            check(slot == 4 and team == 2, "finder兼容字符串team键和英雄ID，保留稀疏槽位4")
            check(power.calcHeroPower("2", 4, 2) == bare2, "字符串英雄ID归一后仍使用本人槽4，不借队2槽1神器")
            state.teams = originalTeams
        else check(false, "findHeroDeployPosition API已导出") end
        power.refreshPowerCache()
        check(state.rosterPowerCache[1] == explicit2 and state.rosterPowerCache[2] == explicit3
            and state.rosterPowerCache[3] == bench and state.rosterPowerCache[4] == 0,
            "名册刷新与各英雄所属队一致，未拥有缓存为0")
        data.talents.litNodes = { 113, 124 }
        local oneRuntime = TE.calcRuntimeOnlyPower(data.talents.litNodes)
        check(oneRuntime > 0, "真实runtime节点113/124产生非零单人固定战力")
        power.refreshPowerCache()
        check(type(state.runtimeOnlyPowerCaches) == "table" and state.runtimeOnlyPowerCaches[1] == oneRuntime
            and state.runtimeOnlyPowerCaches[2] == oneRuntime * 2
            and state.runtimeOnlyPowerCaches[3] == oneRuntime * 3,
            "runtimeOnlyPowerCaches逐队按本队1/2/3人数计算")
        check(gamePower == state.teamPowerCaches[1][1] + oneRuntime
            and state.runtimeOnlyPowerCache == oneRuntime,
            "GameState与兼容scalar仍仅队1总战力，不跟活动队3")
        teams[2].slots = slots({})
        teams[3].slots = slots({ 6 })
        power.refreshPowerCache()
        check(type(state.runtimeOnlyPowerCaches) == "table" and state.runtimeOnlyPowerCaches[2] == 0
            and state.runtimeOnlyPowerCaches[3] == oneRuntime, "清空/缩减队伍刷新runtime，旧人数不残留")
        check(state.teamPowerCaches[2][1] == 0 and state.teamPowerCaches[3][2] == 0,
            "空槽与原队员槽位缓存一并清零")
        data.talents.litNodes = {}
        power.refreshPowerCache()
        check(type(state.runtimeOnlyPowerCaches) == "table" and state.runtimeOnlyPowerCaches[1] == 0
            and state.runtimeOnlyPowerCaches[2] == 0 and state.runtimeOnlyPowerCaches[3] == 0,
            "清天赋后全部队runtime缓存清零")
        check(equal(data.artifacts, artifactsBefore), "战力计算不改神器存档替身")
        data.talents.litNodes = { 113, 124 }
        power.refreshPowerCache()
        data.talents = nil
        power.refreshPowerCache()
        check(state.runtimeOnlyPowerCaches[1] == 0 and state.runtimeOnlyPowerCaches[2] == 0
            and state.runtimeOnlyPowerCaches[3] == 0, "talents模块缺失也清掉此前runtime缓存")
        data.talents = { litNodes = {} }
        HC.setDefaultLitNodes(nil)

        -- 普通属性页与显式配装快照的hero20都按所属队；队友属性使用同队神器。
        data.heroes = { roster = {}, deployed = { 2, 0, 0, 0 }, teams = {
            { slots = { 2, 0, 0, 0 } }, { slots = { 20, 6, 1, 3 } }, { slots = { 7, 0, 0, 0 } },
        } }
        for id, entry in pairs(owned) do data.heroes.roster[tostring(id)] = copy(entry) end
        data.equipment = { inventory = {}, equipped = {} }
        local function give(id, damage, pen)
            data.equipment.inventory[tostring(id)] = { templateId = "C1", level = 1, quality = 1,
                baseStats = { { AD.MAG_DMG_BONUS, damage }, { AD.MAG_PEN, pen } }, affixes = {} }
            -- 普通属性页允许水合存档对象；夹具先水合，避免把既有规范化误判为队伍改写。
            Eq.hydrate(data.equipment.inventory[tostring(id)])
            data.equipment.equipped[tostring(id)] = { accessory = id }
        end
        give(2, 100, 60); give(6, 10, 4); give(20, 5, 2); give(1, 25, 8); give(3, 20, 6)
        data.artifacts = { bag = { { id = "adj", artifactId = 8, value = 12 } },
            equippedByTeam = { {}, { { "adj" } }, {} } }
        local melissa = Melissa.bind({ AD = AD, hasAwaken = function(unit, node)
            return AC.hasNode(unit.awakeningNodes, node)
        end })
        local function combatResonance(ids)
            local units = {}
            local subject = nil ---@type table|nil
            for _, id in ipairs(ids) do
                local entry = data.heroes.roster[tostring(id)]
                local unit = HC.createHero(id, entry.level, entry.advBranch, entry.awakening, entry.extraTalent)
                -- 独立建立战斗前静态单位，避免拿被测详情属性管线充当自身oracle。
                local heroEq = Eq.getHeroSlots(data.equipment, id) or {}
                local applied = {}
                for _, slotKey in ipairs(EC.SLOTS) do
                    local seq = heroEq[slotKey]
                    local equip = seq and data.equipment.inventory[tostring(seq)]
                    if equip and not applied[seq] then
                        Eq.applyToUnit(unit.attrs, equip, seq, Eq.getAscendBoost(equip))
                        applied[seq] = true
                    end
                end
                ES.applyToUnit(unit.attrs, data.equipment, id, Eq.getFromInventory, Eq.getHeroSlots)
                local found = false
                if data.heroes.teams then
                    for t = 1, 3 do
                        local team = data.heroes.teams[t] or data.heroes.teams[tostring(t)]
                        local ids2 = team and team.slots or {}
                        for slot = 1, 4 do
                            if tonumber(ids2[slot] or ids2[tostring(slot)]) == id then
                                Artifact.applyToUnit(unit.attrs, slot, data.artifacts, t)
                                found = true
                                break
                            end
                        end
                        if found then break end
                    end
                else
                    for slot = 1, 4 do
                        if tonumber(data.heroes.deployed[slot]) == id then
                            Artifact.applyToUnit(unit.attrs, slot, data.artifacts, 1)
                            break
                        end
                    end
                end
                units[#units + 1] = unit
                if id == 20 then subject = unit end
            end
            return melissa.calcMelissaTeamResonance(subject, units)
        end
        local function checkDetail(ids, label)
            local before, beforeReads = copy(data), reads
            local snapshot = Attrs.collectAttributes(20, HC.get(20), 70, data)
            check(reads == beforeReads, label .. "显式快照不回读存档")
            local ordinary = Attrs.collectAttributes(20, HC.get(20), 70)
            local expected = combatResonance(ids)
            check(close(row(ordinary, "_melissaStarGateResonance"), expected.independentMult)
                and close(row(ordinary, "_melissaStarGatePen"), expected.magPen),
                label .. "普通属性页星门与本队真实战斗聚合一致")
            check(close(row(snapshot, "_melissaStarGateResonance"), expected.independentMult)
                and close(row(snapshot, "_melissaStarGatePen"), expected.magPen),
                label .. "配装快照星门与本队真实战斗聚合一致")
            check(equal(data, before), label .. "普通/快照均未改测试数据")
        end
        checkDetail({ 20, 6, 1, 3 }, "hero20队2未觉醒：")
        data.heroes.roster["20"].awakening = { [7] = true }
        checkDetail({ 20, 6, 1, 3 }, "hero20队2觉醒7全队贡献：")
        data.heroes.roster["20"].awakening = {}
        data.heroes.teams[2].slots = { 6, 0, 0, 0 }
        data.heroes.teams[3].slots = { 20, 7, 0, 0 }
        checkDetail({ 20, 7 }, "hero20转移到队3：")
        data.heroes.teams[3].slots = { ["2"] = "20", ["4"] = "7" }
        data.heroes.teams["3"] = data.heroes.teams[3]
        data.heroes.teams[3] = nil
        checkDetail({ 20, 7 }, "hero20队3字符串键与空槽间隔：")
        data.heroes.teams[3] = data.heroes.teams["3"]
        data.heroes.teams["3"] = nil
        data.heroes.teams[3].slots = { 20, 7, 20, 7 }
        checkDetail({ 20, 7 }, "脏档同队重复ID不虚增星门贡献：")
        data.heroes.teams[3].slots = { 7, 0, 0, 0 }
        checkDetail({ 20 }, "hero20未编队仅自身贡献：")
        -- teams已存在时不能被陈旧deployed复活成队1成员。
        data.heroes.deployed = { 20, 2, 0, 0 }
        checkDetail({ 20 }, "teams权威与陈旧deployed冲突：")
        data.heroes.teams = nil
        checkDetail({ 20, 2 }, "旧档仅deployed队1兼容：")
        check(ownedReads == 0 and writes > 0 and dirty == 6, "全测试无真实拥有数据回退，缓存setter/脏标记正常")
    end)
    Dispatcher.get, Store.Get = oldGet, oldStoreGet
    package.loaded["ui.character.panel.CharacterPanel"] = oldPanel
    HC.setDefaultLitNodes(savedLit)
    if not ok then check(false, "测试异常: " .. tostring(err)) end
    print("[team_artifact_power_context_test] " .. (failures == 0 and "ALL PASS" or "FAILURES=" .. failures)
        .. " assertions=" .. assertions)
    engine:Exit()
end
