-- ============================================================================
-- CharacterPower - 装备应用 / 战力计算 / 角标刷新（玩法不变）
-- ============================================================================

local M = {}
local EventBus = require("core.EventBus")
local GameEvents = require("config.GameEvents")

function M.bind(deps)
    local AD = deps.AD
    local HC = deps.HC
    local ClientDispatcher = deps.ClientDispatcher
    local PlayerStore = deps.PlayerStore
    local EquipmentSystem = deps.EquipmentSystem
    local EquipmentConfig = deps.EquipmentConfig
    local EquipmentSetSystem = require("systems.EquipmentSetSystem")
    local EquipmentPower = require("systems.EquipmentPower")
    local CPE = require("systems.CombatPowerEstimate")
    -- [927 遗物后端移除] RelicBridge 已删除，不再从 deps 取用
    local ArtifactBridge = deps.ArtifactBridge
    local AwakeningConfig = deps.AwakeningConfig
    local TalentEffect = deps.TalentEffect
    local GameState = deps.GameState
    local CharacterDetail = deps.CharacterDetail
    local CharacterPanel = deps.CharacterPanel
    local BottomNav = deps.BottomNav
    local MAX_SLOTS = deps.MAX_SLOTS
    local TEAM_COUNT = deps.TEAM_COUNT
    local get = deps.get
    local set = deps.set

    local POWER_SKIP = {
        [AD.STR] = true, [AD.AGI] = true, [AD.INT] = true,
        [AD.VIT] = true, [AD.LUK] = true, [AD.SPI] = true,
        [AD.HP]           = true,
        [AD.ATK_INTERVAL] = true,
        [AD.PHYS_RES]     = true,
        [AD.MAG_RES]      = true,
    }

    local function applyEquippedItems(attrs, heroId, partySlot)
        local eqData = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
        if not eqData or not eqData.inventory then
            return nil
        end
        EquipmentPower.applyEquipment(attrs, eqData, heroId)
        local heroEq = EquipmentSystem.getHeroSlots(eqData, heroId)
        local armor = heroEq and heroEq.armor and EquipmentSystem.getFromInventory(eqData, heroEq.armor)
        return armor and AD.ARMOR_TYPE_ENUM[armor.type] or nil
    end

    local function getHeroLevel(heroId)
        local ownedSet = get("ownedSet")
        local ownData = ownedSet[heroId]
        return ownData and ownData.level or 1
    end

    -- 槽位只在所属队里有意义；名册和详情缺省查全队，不读取活动视图。
    ---@param heroId number|string
    ---@param teamIdx? number
    ---@return number|nil slot
    ---@return number|nil team
    local function findHeroDeployPosition(heroId, teamIdx)
        local targetId = tonumber(heroId)
        if not targetId or targetId <= 0 then return nil, nil end
        local firstTeam, lastTeam = 1, TEAM_COUNT
        if teamIdx ~= nil then
            local requestedTeam = tonumber(teamIdx)
            if not requestedTeam or requestedTeam < 1 or requestedTeam > TEAM_COUNT
                or requestedTeam ~= math.floor(requestedTeam) then return nil, nil end
            firstTeam, lastTeam = requestedTeam, requestedTeam
        end
        local teams = get("teams") or {}
        for t = firstTeam, lastTeam do
            local team = teams[t] or teams[tostring(t)]
            local slots = team and team.slots or {}
            for i = 1, MAX_SLOTS do
                local slot = slots[i]
                if slot and slot.state == "occupied" and tonumber(slot.heroId) == targetId then
                    return i, t
                end
            end
        end
        return nil, nil
    end

    -- 角色估值属性不含神器；神器详情分数仅在队伍分项中相加。
    ---@return table|nil hero 含 attrs/classId/awakening 的单位；失败返回 nil
    local function buildHeroAttrs(heroId, partySlot, teamIdx)
        heroId = tonumber(heroId) or heroId
        local level = getHeroLevel(heroId)
        local ownedSet = get("ownedSet")
        local ownData = ownedSet[heroId]
        local advBranch = ownData and ownData.advBranch or nil
        local awakening = ownData and ownData.awakening or nil
        local hero = HC.createHero(heroId, level, advBranch, awakening, ownData and ownData.extraTalent)
        if not hero or not hero.attrs then return nil end
        local a = hero.attrs

        applyEquippedItems(a, heroId, partySlot)

        hero.awakening = awakening
        return hero
    end

    local function calcHeroPower(heroId, partySlot, teamIdx, wornBatches)
        local deployedSlot, deployedTeam = findHeroDeployPosition(heroId)
        local matches = (partySlot == nil or tonumber(partySlot) == deployedSlot)
            and (teamIdx == nil or tonumber(teamIdx) == deployedTeam)
        local owned = get("ownedSet") or {}
        local options = {
            heroData = owned[tonumber(heroId) or heroId],
            heroes = ClientDispatcher.get("heroes") or PlayerStore.Get("heroes"),
            equipment = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment"),
            artifacts = matches and (ClientDispatcher.get("artifacts") or PlayerStore.Get("artifacts")) or {},
            talents = ClientDispatcher.get("talents") or PlayerStore.Get("talents"),
            -- 仅refresh的私有批次允许共享完整只读队伍；独立查询/试穿仍逐ctx隔离。
            reuseTeamContext = wornBatches ~= nil,
        }
        -- 仅单次 refresh 内共享模块/已穿装备快照；不跨通知复用，不借错队神器。
        local batch = wornBatches and wornBatches[matches]
        if wornBatches and not batch then
            batch = EquipmentPower.createWornBatch(options)
            wornBatches[matches] = batch
        end
        local context = EquipmentPower.buildWornContext(heroId, options, batch)
        if not context then return 0 end
        return math.floor(context.currentPower + 0.5)
    end

    -- 实战预估（分项计价原型）：装备/觉醒与角色自身成长计入，完全排除神器。
    -- 仍按英雄伤害大类区别计价物攻/魔攻/治疗属性，仅供并列参考展示。
    local function calcHeroEstimate(heroId, partySlot, teamIdx)
        local hero = buildHeroAttrs(heroId, partySlot, teamIdx)
        if not hero then return 0 end
        local a = hero.attrs
        local base, _category = CPE.estimate(a, a.atkType)
        local extra = AwakeningConfig.calcTotalCombatPower(heroId, hero.awakening)
        return math.floor(base + extra + 0.5)
    end

    local pendingExtraHeroes = {}
    ---@type table|nil
    local lastRefreshState = nil
    local COMBAT_FIELDS = { "level", "advBranch", "awakening", "extraTalent" }
    local RESOURCE_KEYS = { "heroes", "equipment", "artifacts", "talents" }

    local function copyPowerValue(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, item in pairs(value) do result[key] = copyPowerValue(item) end
        return result
    end

    local function samePowerValue(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for key, value in pairs(a) do if not samePowerValue(value, b[key]) then return false end end
        for key in pairs(b) do if a[key] == nil then return false end end
        return true
    end

    -- 只取已穿引用；不能调用 getFromInventory（会水合 live item）。查找优先级与其一致。
    -- 保留完整槽表、缺失项及原始深值：同 seq 洗练/升阶、无效副手也不能漏判。
    local function wornState(equipment)
        if type(equipment) ~= "table" or type(equipment.equipped) ~= "table"
            or type(equipment.inventory) ~= "table" then return nil end
        local state = { equipped = copyPowerValue(equipment.equipped), items = {} }
        for id, slots in pairs(state.equipped) do
            if type(slots) ~= "table" then return nil end
            local items = {}
            for slot, seq in pairs(slots) do
                if type(seq) ~= "number" and type(seq) ~= "string" then return nil end
                items[slot] = copyPowerValue(equipment.inventory[tostring(seq)] or equipment.inventory[seq]) or false
            end
            state.items[id] = items
        end
        return state
    end

    -- 冻结小规模战斗输入，不复制/扫描库存。明确 patch 的 extraTalent 或已验证装备
    -- 通知才允许差分；经验/金币不参与评分。冷缓存、未知来源和结构变化一律全量。
    local function refreshState()
        local heroes = ClientDispatcher.get("heroes") or PlayerStore.Get("heroes") or {}
        local state = { owned = {}, sources = {}, teams = {}, roster = {}, resources = {},
            sourceTeams = copyPowerValue(heroes.teams), deployed = copyPowerValue(heroes.deployed) }
        for name, roster in pairs({ owned = get("ownedSet") or {}, sources = heroes.roster or {} }) do
            for id, hero in pairs(roster) do
                local values = {}
                for _, field in ipairs(COMBAT_FIELDS) do values[field] = copyPowerValue(hero[field]) end
                state[name][id] = values
            end
        end
        local teams = get("teams") or {}
        for t = 1, TEAM_COUNT do
            local slots = (teams[t] or teams[tostring(t)] or {}).slots or {}
            local values = {}
            for i = 1, MAX_SLOTS do
                local slot = slots[i]
                values[i] = { state = slot and slot.state, heroId = slot and slot.heroId }
            end
            state.teams[t] = values
        end
        for i, entry in ipairs(get("heroRoster") or {}) do
            state.roster[i] = { heroId = entry.heroId, owned = entry.owned }
        end
        for _, key in ipairs(RESOURCE_KEYS) do
            state.resources[key] = { source = ClientDispatcher.get(key) or PlayerStore.Get(key),
                storeSource = PlayerStore.Get(key), dispatcherSource = ClientDispatcher.get(key),
                revision = PlayerStore.GetRevision and PlayerStore.GetRevision(key) }
        end
        state.worn = wornState(state.resources.equipment.source)
        return state
    end

    local function safeRefreshInputs(current, extraTalentOnly, equipmentNotification)
        local previous = lastRefreshState
        if not previous or not PlayerStore.GetRevision then return false end
        for _, key in ipairs(RESOURCE_KEYS) do
            local a, b = previous.resources[key], current.resources[key]
            if key == "equipment" and equipmentNotification then
                -- GetRevision 使用全字段共享序列，合法连续装备通知可以相差 > 1。
                -- 不靠 cause/request heroId：只信本次订阅传来的同源 Store/Dispatcher 数据。
                if type(b.source) ~= "table" or equipmentNotification.data ~= b.source
                    or a.source ~= b.source or a.storeSource ~= a.source or b.storeSource ~= b.source
                    or (a.dispatcherSource and a.dispatcherSource ~= a.source)
                    or (b.dispatcherSource and b.dispatcherSource ~= b.source)
                    or type(a.revision) ~= "number" or type(b.revision) ~= "number"
                    or a.revision <= 0 or b.revision <= a.revision then return false end
            elseif key == "heroes" and equipmentNotification then
                -- Panel 的 heroes 订阅先于 Store：成长已评分后，同值回执才递增 revision。
                -- 不以 revision 单独变化否决穿戴差分；源身份/镜像仍必须一致，且下方
                -- 完整核对 owned/sources 战斗字段、编队、名册及已发布缓存的冻结深值。
                if a.source ~= b.source or a.storeSource ~= a.source or b.storeSource ~= b.source
                    or (a.dispatcherSource and a.dispatcherSource ~= a.source)
                    or (b.dispatcherSource and b.dispatcherSource ~= b.source)
                    or type(a.revision) ~= "number" or type(b.revision) ~= "number"
                    or not (b.revision >= a.revision) or b.revision == math.huge then return false end
            elseif key ~= "heroes" and (a.source ~= b.source or a.revision ~= b.revision) then return false end
            if equipmentNotification and (type(a.source) ~= "table"
                or type(a.revision) ~= "number" or a.revision <= 0) then return false end
        end
        if not equipmentNotification and not samePowerValue(previous.worn, current.worn) then return false end
        for _, key in ipairs({ "teams", "sourceTeams", "deployed", "roster" }) do
            if not samePowerValue(previous[key], current[key]) then return false end
        end
        for _, key in ipairs({ "owned", "sources" }) do
            for id, hero in pairs(current[key]) do
                local old = previous[key][id]
                if not old then return false end
                for _, field in ipairs(COMBAT_FIELDS) do
                    if not (extraTalentOnly and field == "extraTalent" and pendingExtraHeroes[tonumber(id) or id])
                        and not samePowerValue(old[field], hero[field]) then return false end
                end
            end
            for id in pairs(previous[key]) do if not current[key][id] then return false end end
        end
        -- 保留未评分名册/槽缓存不能当作暖缓存；外部清缓存也必须回退。
        local rosterCache, teamCaches = get("rosterPowerCache") or {}, get("teamPowerCaches") or {}
        if not samePowerValue(previous.rosterPowers, rosterCache)
            or not samePowerValue(previous.slotPowers, teamCaches) then return false end
        return true
    end

    local function dependencyClosure(affected, previous, current)
        -- 取 old/new 本地槽位与正式队表的联通闭包（当前门禁要求队表相等，仍显式保留两版）。
        -- 不按活动队猜测，也不假设装备/成长只影响本人（光环/星门/124会读队友）。
        local rows = {}
        for _, state in ipairs({ previous, current }) do
            for t = 1, TEAM_COUNT do
                local ids = {}
                for i, slot in ipairs(state.teams[t]) do
                    if slot.state == "occupied" then ids[i] = tonumber(slot.heroId) end
                end
                rows[#rows + 1] = ids
                local source = state.sourceTeams and (state.sourceTeams[t] or state.sourceTeams[tostring(t)])
                rows[#rows + 1] = source and source.slots or (not state.sourceTeams and t == 1 and state.deployed) or {}
            end
        end
        local changed = true
        while changed do
            changed = false
            for _, ids in ipairs(rows) do
                local members, touches = {}, false
                for i = 1, MAX_SLOTS do
                    local value = ids[i] or ids[tostring(i)]
                    local id = tonumber(type(value) == "table" and value.heroId or value)
                    if id and id > 0 then members[#members + 1] = id; touches = touches or affected[id] end
                end
                if touches then
                    for _, id in ipairs(members) do
                        if not affected[id] then affected[id], changed = true, true end
                    end
                end
            end
        end
        return affected
    end

    local function extraDependencyClosure(current)
        if not next(pendingExtraHeroes) or not safeRefreshInputs(current, true) then return nil end
        local affected = {}
        for id in pairs(pendingExtraHeroes) do affected[id] = true end
        return dependencyClosure(affected, lastRefreshState, current)
    end

    local function equipmentDependencyClosure(current, notification)
        if not notification or next(pendingExtraHeroes)
            or not safeRefreshInputs(current, false, notification) then return nil end
        local previous = lastRefreshState
        local old, new = previous.worn, current.worn
        if not old or not new then return nil end
        local affected = {}
        for _, state in ipairs({ old, new }) do
            for id in pairs(state.equipped) do
                if not samePowerValue(old.equipped[id], new.equipped[id])
                    or not samePowerValue(old.items[id], new.items[id]) then
                    local heroId = tonumber(id)
                    if not heroId or heroId <= 0 then return nil end
                    affected[heroId] = true
                end
            end
        end
        return dependencyClosure(affected, previous, current)
    end

    local function markExtraTalentDirty(heroId)
        pendingExtraHeroes[heroId] = true
    end

    local function refreshPowerCache(cause, extraTalentOnly, equipmentNotification)
        local current = refreshState()
        local affected = extraTalentOnly and extraDependencyClosure(current)
            or equipmentDependencyClosure(current, equipmentNotification)
        -- 全量入口同时消费待结算集合，避免其跨初始化/换队/全局通知泄漏。
        pendingExtraHeroes, lastRefreshState = {}, nil
        -- 此回调可早于评分订阅者；先失效，避免原地更新后红点仍用旧快照。
        EquipmentPower.invalidate()
        local talentsData = ClientDispatcher.get("talents") or PlayerStore.Get("talents")
        local litNodes = talentsData and talentsData.litNodes or nil
        HC.setDefaultLitNodes(litNodes)

        -- 仅在本轮刷新复用同英雄、同实际神器队/槽的计算，不跨通知缓存属性。
        -- 显式队/槽不匹配时仍走独立口径，不能拿名册的神器结果覆盖它。
        local refreshedPowers, wornBatches = {}, {}
        local function powerForRefresh(heroId, partySlot, teamIdx)
            local id = tonumber(heroId) or heroId
            local deployedSlot, deployedTeam = findHeroDeployPosition(id, teamIdx)
            local matchesSlot = partySlot == nil or tonumber(partySlot) == deployedSlot
            local context = deployedSlot and matchesSlot
                and (tostring(deployedTeam) .. ":" .. tostring(deployedSlot)) or "none"
            local key = tostring(id) .. ":" .. context
            local value = refreshedPowers[key]
            if value == nil then
                value = calcHeroPower(id, partySlot, teamIdx, wornBatches)
                refreshedPowers[key] = value
            end
            return value
        end

        -- 名册缓存与列表索引一致；订阅刷新也覆盖未出战的已拥有英雄。
        -- 沿用 rebuildRoster 的正式战力缺省队口径，不受当前视图影响。
        local heroRoster = get("heroRoster")
        local rosterPowerCache = get("rosterPowerCache")
        if heroRoster and rosterPowerCache then
            for i, entry in ipairs(heroRoster) do
                if entry.owned then
                    if not affected or affected[tonumber(entry.heroId) or entry.heroId] then
                        rosterPowerCache[i] = powerForRefresh(entry.heroId)
                    end
                else
                    rosterPowerCache[i] = 0
                end
            end
        end

        local teams = get("teams") or {}
        local ownedSet = get("ownedSet") or {}
        local teamPowerCaches = get("teamPowerCaches")
        local runtimeOnlyPowerCaches, artifactPowerCaches = {}, {}
        local artifacts = current.resources.artifacts.source
        -- 运行时节点已按各角色生效条件计入共享战力，旧 runtime 分项保持 0。
        -- 神器详情战力是独立队伍分项；每次刷新重读装配，不跨通知复用。
        for t = 1, TEAM_COUNT do
            local team = teams[t] or teams[tostring(t)]
            local slots = team and team.slots or {}
            local cache = teamPowerCaches[t]
            for i = 1, MAX_SLOTS do
                local slot = slots[i]
                local heroId = slot and tonumber(slot.heroId)
                if slot and slot.state == "occupied" and heroId and ownedSet[heroId] then
                    if cache and (not affected or affected[heroId]) then cache[i] = powerForRefresh(heroId, i, t) end
                elseif cache then
                    cache[i] = 0
                end
            end
            runtimeOnlyPowerCaches[t] = 0
            artifactPowerCaches[t] = ArtifactBridge.getTeamPower(artifacts, slots, ownedSet, t)
        end
        -- 独立分项先就绪，再由 runtime setter 完成名册索引重映射并发布。
        set("artifactPowerCaches", artifactPowerCaches)
        set("runtimeOnlyPowerCaches", runtimeOnlyPowerCaches)
        set("runtimeOnlyPowerCache", runtimeOnlyPowerCaches[1] or 0)

        -- 全队缓存完成后一次发布快照；队2/3独立成长也会通知，不借活动队推测来源。
        local teamPowers = {}
        for t = 1, TEAM_COUNT do
            local teamTotal = artifactPowerCaches[t] or 0
            local cache = teamPowerCaches[t] or {}
            for i = 1, MAX_SLOTS do teamTotal = teamTotal + (cache[i] or 0) end
            teamPowers[t] = teamTotal
        end
        -- powerRefreshed 可同步重排名册；保存最终索引与值，不能记排序前的结构。
        current.roster = {}
        for i, entry in ipairs(get("heroRoster") or {}) do
            current.roster[i] = { heroId = entry.heroId, owned = entry.owned }
        end
        current.rosterPowers = copyPowerValue(get("rosterPowerCache") or {})
        current.slotPowers = copyPowerValue(teamPowerCaches)
        lastRefreshState = current
        -- 顶栏与选关继续使用队1，专用提示使用完整快照。
        GameState.setPower(teamPowers[1] or 0)
        CharacterDetail.markPowerDirty()
        EventBus.emit(GameEvents.TEAM_POWER_CHANGED, {
            powers = teamPowers,
            cause = cause,
            ready = CharacterPanel.isHeroesDataApplied and CharacterPanel.isHeroesDataApplied() or false,
        })
    end

    -- 正式战力立即发布；全库存换装角标允许跨帧，但只提交完整同版本结果。
    ---@type thread|nil
    local badgeJob = nil
    local badgeRevision = ""
    local completedRevision = ""
    local completedEquipmentBadges = {}
    local badgeDeadline, badgeSteps = 0, 0
    local BADGE_CPU_BUDGET = 0.001
    local BADGE_MAX_STEPS = 128

    -- 只冻结小规模名册/队孔的战斗字段；在线经验和金币每秒变化不应饿死候选任务。
    local function appendSignature(parts, value)
        if type(value) ~= "table" then
            local text = tostring(value)
            parts[#parts + 1] = type(value) .. ":" .. #text .. ":" .. text
            return
        end
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        parts[#parts + 1] = "{"
        for _, key in ipairs(keys) do
            appendSignature(parts, key)
            appendSignature(parts, value[key])
        end
        parts[#parts + 1] = "}"
    end

    local function badgeVersion()
        local parts, deployed = {}, {}
        -- 每次版本采样只扫一次三队；既用于签名，也交给本版本任务判定出战。
        local teams = get("teams") or {}
        for team = 1, TEAM_COUNT do
            local slots = (teams[team] or teams[tostring(team)] or {}).slots or {}
            for slot = 1, MAX_SLOTS do
                local entry = slots[slot] or {}
                appendSignature(parts, entry.state)
                appendSignature(parts, entry.heroId)
                if entry.state == "occupied" and entry.heroId ~= nil then deployed[entry.heroId] = true end
            end
        end
        for _, key in ipairs({ "equipment", "artifacts", "talents" }) do
            parts[#parts + 1] = tostring(PlayerStore.GetRevision and PlayerStore.GetRevision(key) or 0)
        end
        local owned = get("ownedSet") or {}
        local ids = {}
        for id in pairs(owned) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
        for _, id in ipairs(ids) do
            local hero = owned[id]
            appendSignature(parts, id)
            appendSignature(parts, hero.level)
            appendSignature(parts, hero.advBranch)
            appendSignature(parts, hero.awakening)
            appendSignature(parts, hero.extraTalent)
        end
        return table.concat(parts, "|"), { ids = ids, deployed = deployed }
    end

    local function badgeCheckpoint()
        badgeSteps = badgeSteps + 1
        if badgeSteps >= BADGE_MAX_STEPS or os.clock() >= badgeDeadline then
            coroutine.yield()
        end
    end

    local function buildEquipmentBadges(checkpoint, state)
        local result = {}
        for _, heroId in ipairs(state.ids) do
            if checkpoint then checkpoint() end
            result[heroId] = state.deployed[heroId]
                and CharacterDetail.hasAnyUpgradeForHero(heroId, checkpoint) or false
        end
        return result
    end

    local function publishUpgradeBadges(equipmentBadges)
        local result, hasUpgrade = {}, false
        local okChurch, ChurchPage = pcall(require, "ui.church.ChurchPage")
        local canAdvance = okChurch and ChurchPage.hasAdvanceForHero
        for heroId in pairs(get("ownedSet") or {}) do
            local value = equipmentBadges[heroId] or CharacterDetail.hasAwakeningUpgrade(heroId)
                or (canAdvance and canAdvance(heroId)) or false
            result[heroId], hasUpgrade = value, hasUpgrade or value
        end
        set("upgradeBadgeCache", result)
        BottomNav.setBadge(1, hasUpgrade)
        return result
    end

    -- 显式调用仍同步返回；生产导航通知走下面的预算队列。
    local function refreshUpgradeBadgeCache()
        local revision, state = badgeVersion()
        local result = buildEquipmentBadges(nil, state)
        if PlayerStore.GetRevision then
            completedRevision, completedEquipmentBadges = revision, result
            badgeJob, badgeRevision = nil, completedRevision
        end
        return publishUpgradeBadges(result)
    end

    local function queueBadges(revision, state)
        if completedRevision == revision then
            badgeJob = nil
        elseif not badgeJob or badgeRevision ~= revision then
            badgeRevision = revision
            badgeJob = coroutine.create(function() return buildEquipmentBadges(badgeCheckpoint, state) end)
        end
    end

    local function refreshNavBadge()
        if PlayerStore.GetRevision then
            local revision, state = badgeVersion()
            queueBadges(revision, state)
            -- 金币/碎片只刷新小规模养成条件，不取消仍有效的全库存任务。
            publishUpgradeBadges(completedEquipmentBadges)
        else
            refreshUpgradeBadgeCache()
        end
        BottomNav.refreshTownBadge()
    end

    local function updateBadges()
        if not badgeJob then return end
        -- 一次Update仅采样一次结构签名（不只信heroes revision，保留原地变更检测）。
        -- resume到返回之间不执行其他游戏更新；结束时可复用本次采样，不再扫三队/名册。
        local revision, state = badgeVersion()
        if badgeRevision ~= revision then
            queueBadges(revision, state)
            publishUpgradeBadges(completedEquipmentBadges)
            BottomNav.refreshTownBadge()
        end
        if not badgeJob then return end
        local job = badgeJob
        badgeSteps, badgeDeadline = 0, os.clock() + BADGE_CPU_BUDGET
        local ok, result = coroutine.resume(job)
        if not ok then
            badgeJob = nil
            print("[CharacterPower] 角标预算任务失败: " .. tostring(result))
        elseif coroutine.status(job) == "dead" then
            badgeJob = nil
            completedRevision, completedEquipmentBadges = revision, result
            publishUpgradeBadges(result)
        end
    end

    local function cancelBadgeRefresh()
        badgeJob, badgeRevision, completedRevision = nil, "", ""
        completedEquipmentBadges = {}
        set("upgradeBadgeCache", {})
        BottomNav.setBadge(1, false)
    end

    return {
        applyEquippedItems = applyEquippedItems,
        getHeroLevel = getHeroLevel,
        findHeroDeployPosition = findHeroDeployPosition,
        calcHeroPower = calcHeroPower,
        calcHeroEstimate = calcHeroEstimate,
        refreshPowerCache = refreshPowerCache,
        markExtraTalentDirty = markExtraTalentDirty,
        refreshUpgradeBadgeCache = refreshUpgradeBadgeCache,
        refreshNavBadge = refreshNavBadge,
        updateBadges = updateBadges,
        cancelBadgeRefresh = cancelBadgeRefresh,
        POWER_SKIP = POWER_SKIP,
    }
end

return M
