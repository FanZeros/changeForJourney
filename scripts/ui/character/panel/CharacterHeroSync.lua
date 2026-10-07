-- ============================================================================
-- CharacterHeroSync - setHeroesData / resetSessionData（玩法不变）
-- ============================================================================

local ExtraTalentSystem = require("systems.ExtraTalentSystem")

local M = {}

function M.bind(deps)
    local ExpTable = deps.ExpTable
    local GameState = deps.GameState
    local MAX_SLOTS = deps.MAX_SLOTS
    local TEAM_COUNT = deps.TEAM_COUNT
    local get = deps.get
    local set = deps.set
    local buildDefaultSlots = deps.buildDefaultSlots
    local rebuildRoster = deps.rebuildRoster
    local refreshPowerCache = deps.refreshPowerCache
    local refreshNavBadge = deps.refreshNavBadge
    ---@type table|nil
    local lastPowerState = nil
    ---@type table|nil
    local lastShards = nil

    local function copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, item in pairs(value) do result[key] = copy(item) end
        return result
    end

    local function same(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for key, value in pairs(a) do if not same(value, b[key]) then return false end end
        for key in pairs(b) do if a[key] == nil then return false end end
        return true
    end

    local function powerState()
        local state = { owned = {}, teams = {} }
        for id, own in pairs(get("ownedSet") or {}) do
            state.owned[id] = { level = own.level, advBranch = copy(own.advBranch),
                awakening = copy(own.awakening), extraTalent = copy(own.extraTalent) }
        end
        local teams = get("teams")
        for t = 1, TEAM_COUNT do
            local ids, slots = {}, teams[t] and teams[t].slots or {}
            for i = 1, MAX_SLOTS do
                local slot = slots[i]
                ids[i] = slot and slot.state == "occupied" and slot.heroId or 0
            end
            state.teams[t] = ids
        end
        return state
    end

    -- 冻结的是最后完成评分的值，不能拿乐观改过的编队或共享分支引用作门禁。
    local function rememberState()
        lastPowerState = powerState()
        lastShards = copy(get("shardMap") or {})
    end

    local function setHeroesData(data)
        if not data then return end

        -- 记录覆盖前的各队槽位布局（英雄ID序列），用于只失效真正改过编队的行：
        -- 等级/经验/装备等数据推送不应重启未改编队的战斗
        local prevLayout = {}
        do
            local oldTeams = get("teams")
            for t = 1, TEAM_COUNT do
                local ids = {}
                local slots = oldTeams[t] and oldTeams[t].slots or {}
                for i = 1, MAX_SLOTS do
                    local s = slots[i]
                    ids[i] = (s and s.state == "occupied" and s.heroId) or 0
                end
                prevLayout[t] = lastPowerState and lastPowerState.teams[t] or ids
            end
        end

        do
            local deployedStr = "nil"
            if data.deployed and type(data.deployed) == "table" then
                local ids = {}
                for i, v in ipairs(data.deployed) do ids[i] = tostring(v) end
                deployedStr = "[" .. table.concat(ids, ",") .. "]"
            end
            local rosterCount = 0
            if data.roster then
                for _ in pairs(data.roster) do rosterCount = rosterCount + 1 end
            end
            print(string.format("[DIAG-HERO] setHeroesData ENTER deployed=%s rosterFieldCount=%d",
                deployedStr, rosterCount))
        end

        local previousOwned = get("ownedSet") or {}
        local expChanged = false
        local ownedSet = {}
        local shardMap = {}
        if data.roster then
            for heroId, heroData in pairs(data.roster) do
                local numId = tonumber(heroId) or heroId
                shardMap[numId] = heroData.shards or 0
                if heroData.level then
                    local level = heroData.level
                    local exp   = heroData.exp or 0
                    local maxExp = heroData.maxExp
                    if not maxExp or maxExp == 0 then
                        maxExp = ExpTable.getHeroExpForLevel(level) or 5
                    end
                    ownedSet[numId] = {
                        level  = level,
                        exp    = exp,
                        maxExp = maxExp,
                        advBranch = heroData.advBranch,
                        awakening = heroData.awakening,
                        dupeCount = heroData.dupeCount or 0,
                        shards = heroData.shards or 0,
                        extraTalent = ExtraTalentSystem.normalize(heroData.extraTalent),
                    }
                end
            end
        end
        for id, own in pairs(ownedSet) do
            local previous = previousOwned[id]
            if not previous or previous.exp ~= own.exp or previous.maxExp ~= own.maxExp then
                expChanged = true
                break
            end
        end
        set("ownedSet", ownedSet)
        set("shardMap", shardMap)

        do
            local ownedKeys = {}
            for k, v in pairs(ownedSet) do
                ownedKeys[#ownedKeys + 1] = tostring(k) .. "(lv" .. tostring(v.level) .. ")"
            end
            print(string.format("[DIAG-HERO] setHeroesData AFTER_ROSTER ownedSet={%s}",
                table.concat(ownedKeys, ",")))
        end

        local teams = get("teams")
        local function buildSlotsFromIds(ids)
            local unlocked = ExpTable.getUnlockedSlotCountForTeam(GameState.getLevel())
            local cnt = ids and #ids or 0
            if cnt > unlocked then
                unlocked = cnt
            end
            local slots = {}
            for i = 1, MAX_SLOTS do
                slots[i] = { state = (i <= unlocked) and "empty" or "locked" }
            end
            local idCount = ids and #ids or 0
            for idx = 1, idCount do
                local heroId = ids[idx]
                local numId = tonumber(heroId) or 0
                if idx <= MAX_SLOTS and numId ~= 0 then
                    local ownData = ownedSet[numId]
                    if ownData then
                        slots[idx] = {
                            state  = "occupied",
                            heroId = numId,
                            level  = ownData.level,
                            exp    = ownData.exp,
                            maxExp = ownData.maxExp,
                        }
                    else
                        print(string.format("[DIAG-HERO] WARNING: slots[%d]=%s NOT in ownedSet! Slot stays empty.",
                            idx, tostring(numId)))
                    end
                end
            end
            return slots
        end

        local function applySlots(previous, slots)
            if #previous ~= #slots then return slots end
            for i, slot in ipairs(slots) do
                local old = previous[i]
                if not old or old.state ~= slot.state or old.heroId ~= slot.heroId then return slots end
            end
            -- 身份不变只同步经验/等级，保留头像手势与现有槽位引用。
            for i, slot in ipairs(slots) do
                local old = previous[i]
                old.level, old.exp, old.maxExp = slot.level, slot.exp, slot.maxExp
            end
            return previous
        end
        if data.deployed then
            local previous = teams[1].slots
            local slots = buildSlotsFromIds(data.deployed)
            teams[1].slots = applySlots(previous, slots)
        end
        if data.teams and type(data.teams) == "table" then
            for t = 2, TEAM_COUNT do
                local tdata = data.teams[t]
                if type(tdata) == "table" and type(tdata.slots) == "table" then
                    local previous = teams[t].slots
                    local slots = buildSlotsFromIds(tdata.slots)
                    teams[t].slots = applySlots(previous, slots)
                end
            end
        end

        do
            local seenHero = {}
            for t = 1, TEAM_COUNT do
                local slots = teams[t] and teams[t].slots
                if slots then
                    for i = 1, #slots do
                        local s = slots[i]
                        if s.state == "occupied" and s.heroId then
                            if seenHero[s.heroId] then
                                print(string.format("[CharacterPanel] 去重: 英雄%d 重复编队，移出队伍%d", s.heroId, t))
                                slots[i] = { state = "empty" }
                            else
                                seenHero[s.heroId] = true
                            end
                        end
                    end
                end
            end
        end

        local teamPowerCaches = get("teamPowerCaches")
        local activeTeamIdx = get("activeTeamIdx")
        local powerChanged = not get("heroesDataApplied") or not same(lastPowerState, powerState())
        local shardsChanged = not same(lastShards, shardMap)
        set("teamSlots", teams[activeTeamIdx].slots)
        set("slotPowerCache", teamPowerCaches[activeTeamIdx])
        set("heroesDataApplied", true)
        local function refreshOfflinePreview()
            local OfflineRewardPanel = require("ui.hud.popup.OfflineRewardPanel")
            if OfflineRewardPanel.isOpen() and OfflineRewardPanel.refreshHeroPreview then
                local OfflineService = require("rules.offline.OfflineService")
                local preview = OfflineService.RebuildHeroPreview and OfflineService.RebuildHeroPreview(1)
                if preview then OfflineRewardPanel.refreshHeroPreview(preview) end
            end
        end
        if not powerChanged then
            -- 经验/碎片只更新原名册显示，不失效装备模拟，不重算全队战力。
            local roster = get("heroRoster") or {}
            for _, entry in ipairs(roster) do
                local own = ownedSet[entry.heroId]
                if own then entry.exp, entry.maxExp = own.exp, own.maxExp end
                entry.shards = shardMap[entry.heroId] or 0
            end
            if shardsChanged then refreshNavBadge() end
            if expChanged then refreshOfflinePreview() end
            lastShards = copy(shardMap)
            return {}, false
        end
        -- 完整缓存先于可能即时读取的编队失效/离线预览回调，且快照已 ready。
        rebuildRoster()
        refreshPowerCache()
        rememberState()
        -- 只失效编队布局真正变化的队伍：其他行保持战斗进度不重置
        local changed = {}
        local anyChanged = false
        local teams = get("teams")
        for t = 1, TEAM_COUNT do
            local ids = {}
            local slots = teams[t] and teams[t].slots or {}
            for i = 1, MAX_SLOTS do
                local s = slots[i]
                ids[i] = (s and s.state == "occupied" and s.heroId) or 0
            end
            local old = prevLayout[t] or {}
            for i = 1, MAX_SLOTS do
                if (ids[i] or 0) ~= (old[i] or 0) then
                    changed[t] = true
                    anyChanged = true
                    break
                end
            end
        end
        local okTri, BattleTriPage = pcall(require, "ui.battle.tri.BattleTriPage")
        if okTri and BattleTriPage.invalidateTeams then
            if anyChanged then
                BattleTriPage.invalidateTeams(changed)
                local list = {}
                for t in pairs(changed) do list[#list + 1] = t end
                table.sort(list)
                print("[CharacterHeroSync] 编队布局变化队伍: " .. table.concat(list, ","))
            else
                print("[CharacterHeroSync] 编队布局未变化，战斗不重置")
            end
        end
        refreshOfflinePreview()

        do
            local teamsInfo = {}
            for t = 1, TEAM_COUNT do
                local ids = {}
                local slots = teams[t].slots
                for i = 1, #slots do
                    ids[i] = tostring(slots[i].heroId or (slots[i].state == "locked" and "L" or "-"))
                end
                teamsInfo[t] = "T" .. t .. "[" .. table.concat(ids, ",") .. "]"
            end
            print(string.format("[DIAG-HERO] setHeroesData AFTER_TEAMS active=%d %s",
                activeTeamIdx, table.concat(teamsInfo, " ")))
        end

        refreshNavBadge()
        return changed, true
    end

    local function resetSessionData()
        lastPowerState, lastShards = nil, nil
        local teams = get("teams")
        local teamPowerCaches = get("teamPowerCaches")
        for t = 1, TEAM_COUNT do
            teams[t].slots = buildDefaultSlots(t)
            teamPowerCaches[t] = {}
        end
        set("activeTeamIdx", 1)
        set("heroesDataApplied", false)
        set("teamSlots", teams[1].slots)
        set("slotPowerCache", teamPowerCaches[1])
        set("runtimeOnlyPowerCache", 0)
        set("ownedSet", {})
        set("shardMap", {})
        set("heroRoster", {})
        set("rosterPowerCache", {})
        set("upgradeBadgeCache", {})
        set("scrollY", 0)
        set("scrollVelocity", 0)
        set("isDragging", false)
        local dragState = get("dragState")
        dragState.active = false
        dragState.heroId = nil
        dragState.rosterIdx = nil
        dragState.fromSlot = nil
        dragState.fromTeam = nil
        local selectSlotState = get("selectSlotState")
        selectSlotState.active = false
        selectSlotState.slotIndex = nil
        rebuildRoster()
        refreshPowerCache()
        refreshNavBadge()
        print("[CharacterPanel] session data reset")
    end

    return {
        setHeroesData = setHeroesData,
        resetSessionData = resetSessionData,
        rememberState = rememberState,
    }
end

return M
