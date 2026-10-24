-- 配装详情的单私有协程。只在Update推进；半成品不进入共享EquipmentPower缓存。
local Store = require("core.PlayerStore")
local Dispatcher = require("runtime.ClientDispatcher")
local Power = require("systems.EquipmentPower")
local Eq = require("systems.EquipmentSystem")
local Snapshot = require("ui.character.detail.CharacterDetailSnapshot")
local M = {}
local EMPTY_SOURCE = {}

-- 显式owner私有guard；不传guard仍执行原完整签名，无模块级/跨会话隐式缓存。
-- refresh只允许Update调用；Render依赖不匹配时直接无key，不补建基线。
function M.version(request, guard, refresh)
    local heroes = Dispatcher.get("heroes") or Store.Get("heroes") or EMPTY_SOURCE
    local equipment = Dispatcher.get("equipment") or Store.Get("equipment") or EMPTY_SOURCE
    local artifacts = Dispatcher.get("artifacts") or Store.Get("artifacts") or EMPTY_SOURCE
    local talents = Dispatcher.get("talents") or Store.Get("talents") or EMPTY_SOURCE
    local eqRev = Store.GetRevision and Store.GetRevision("equipment") or 0
    local artRev = Store.GetRevision and Store.GetRevision("artifacts") or 0
    local talentRev = Store.GetRevision and Store.GetRevision("talents") or 0
    local panelMatches = guard and guard.viewKey == request.viewKey
        and Snapshot.matchesDependencies(guard.frozen, heroes, equipment, artifacts, talents, request.heroId)
    if guard and not refresh then
        request.panelKey, request.key = nil, nil
        if panelMatches then
            request.panelKey = guard.panelKey
            if equipment == guard.equipment and artifacts == guard.artifacts and talents == guard.talents
                and eqRev == guard.eqRev and artRev == guard.artRev and talentRev == guard.talentRev then
                request.key = guard.key
            end
        end
        return request
    end
    local sources = { heroes = heroes, equipment = equipment, artifacts = artifacts, talents = talents }
    request.sources = sources
    request.panelKey = panelMatches and guard.panelKey
        or request.viewKey .. "\31" .. Snapshot.dependencies(sources, request.seq, request.heroId)
    if panelMatches and equipment == guard.equipment and artifacts == guard.artifacts and talents == guard.talents
        and eqRev == guard.eqRev and artRev == guard.artRev and talentRev == guard.talentRev then
        request.key = guard.key
    else
        request.key = table.concat({ request.panelKey, tostring(equipment), tostring(eqRev),
            tostring(artifacts), tostring(artRev), tostring(talents), tostring(talentRev) }, "\31")
    end
    if guard then
        if not panelMatches then guard.frozen = Snapshot.freezeDependencies(sources, request.seq, request.heroId) end
        guard.viewKey, guard.panelKey, guard.key = request.viewKey, request.panelKey, request.key
        guard.equipment, guard.artifacts, guard.talents = equipment, artifacts, talents
        guard.eqRev, guard.artRev, guard.talentRev = eqRev, artRev, talentRev
        request.guard = guard
    end
    return request
end

-- 可见评分只消费已穿项+当前候选，与全库升级箭头无关。
-- 同一次Update无yield构建/评分/终检，持续本人或同队成长也能提交当前分。
local function prepareScores(request, slots)
    local sources = request.sources
    local result = { viewKey = request.viewKey, pending = true, scoresPending = false,
        scores = {}, scoresBySeq = {}, upgrades = {} }
    if #slots == 0 then return result end
    local context = Power.buildContext(request.heroId, {
        heroes = sources.heroes,
        equipment = Snapshot.compactEquipment(sources.equipment, request.seq),
        artifacts = sources.artifacts, talents = sources.talents, cacheFixedTeammates = true,
    })
    if not context then return result end
    result.power = math.floor(context.currentPower + 0.5)
    local equipped = Eq.getHeroSlots(context.equipmentData, request.heroId) or {}
    for _, slot in ipairs(slots) do
        local seq = equipped[slot.slot]
        local item = seq and Eq.getFromInventory(context.equipmentData, seq)
        if item then
            local score = Power.scoreInContext(context, item, slot.slot, seq)
            result.scores[slot.slot] = score
            result.scoresBySeq[tostring(seq) .. ":" .. slot.slot] = score
            if slot.slot == "weapon" and item.grip == "twohand" then
                result.scoresBySeq[tostring(seq) .. ":offhand"] = score
            end
        end
    end
    if request.seq then
        local item = Eq.getFromInventory(context.equipmentData, request.seq)
        local slot = request.slot or (item and item.slot)
        if item then
            local evaluation = Power.evaluate(context, request.seq, slot)
            -- 等级/职业不合法也必须显示该角色可利用的词条价值，沿用scoreInContext口径；
            -- 不能拿power=0占位冒充有效试穿，也不能给无效候选伪造净提升。
            result.candidate = { seq = tostring(request.seq), slot = slot,
                score = Power.scoreInContext(context, item, slot, request.seq),
                gain = evaluation and evaluation.valid and evaluation.gain or nil }
        end
    end
    return result
end

function M.bind(deps)
    ---@type thread|nil
    local job = nil
    local jobKey, completedKey = nil, nil
    local panelKey, preparedPanel = nil, nil
    local scoresKey, preparedScores = nil, nil
    local generation, steps, deadline = 0, 0, 0
    local committed = { pending = true, scores = {}, upgrades = {} }
    local api = {}
    local guard = {}
    local function capture(refresh)
        local request = deps.capture()
        return M.version(request, guard, refresh)
    end
    local function checkpoint()
        steps = steps + 1
        if steps >= (deps.maxSteps or 64) or os.clock() >= deadline then coroutine.yield() end
    end
    function api.cancel()
        generation = generation + 1
        job, jobKey, completedKey = nil, nil, nil
        panelKey, preparedPanel = nil, nil
        scoresKey, preparedScores = nil, nil
        guard = {}
        committed = { pending = true, scores = {}, upgrades = {} }
        deps.clear()
    end
    function api.read(viewKey)
        -- 每次外部读取均复核内容，Update后同帧原地patch立即拒旧。
        local current = capture(false)
        if committed.viewKey == viewKey and current.key and completedKey == current.key then
            return committed
        end
        -- pending仍表示全库箭头尚未完成，不能挡住同版本已独立提交的可见评分。
        if preparedScores and preparedScores.viewKey == viewKey and current.panelKey
            and scoresKey == current.panelKey then return preparedScores end
        return { pending = true, scoresPending = true, scores = {}, upgrades = {} }
    end
    function api.update()
        local request = capture(true)
        if not request.heroId then api.cancel(); return end
        if panelKey ~= request.panelKey then
            -- 只有最多已穿项+当前候选的小世界，不遍历库存；不可yield让持续养成饿死底板。
            -- 完整比较在同一次Update内构建/终检/提交，Render仍禁止补算或借旧差值。
            local panelGeneration = generation
            local ok, panel = pcall(deps.prepare, request, function() end)
            if not ok then
                print("[CharacterDetail] panel prepare failed: " .. tostring(panel))
                return
            end
            if panelGeneration ~= generation or request.panelKey ~= capture().panelKey then return end
            deps.commit(panel, request)
            preparedPanel, panelKey = panel, request.panelKey
        end
        if scoresKey ~= request.panelKey then
            local scoreGeneration = generation
            local ok, scores = pcall(prepareScores, request, deps.slots)
            if not ok then
                print("[CharacterDetail] visible score prepare failed: " .. tostring(scores))
                return
            end
            if scoreGeneration ~= generation or request.panelKey ~= capture().panelKey then return end
            scores.panel = preparedPanel
            preparedScores, scoresKey = scores, request.panelKey
        end
        if completedKey == request.key then return end
        if not job or jobKey ~= request.key then
            generation = generation + 1
            local token = generation
            jobKey, completedKey = request.key, nil
            committed = { viewKey = request.viewKey, pending = true, scores = {}, upgrades = {} }
            local visible = preparedScores
            job = coroutine.create(function()
                -- 完整库存只服务升级箭头/可选预估，不再阻塞或重复计算可见装备分。
                checkpoint()
                local sources = request.sources
                local context = #deps.slots > 0 and Power.buildContext(request.heroId, {
                    heroes = sources.heroes, equipment = sources.equipment,
                    artifacts = sources.artifacts, talents = sources.talents,
                    checkpoint = checkpoint, cacheFixedTeammates = true,
                })
                local result = { viewKey = request.viewKey, pending = false, scoresPending = false,
                    scores = visible.scores, scoresBySeq = visible.scoresBySeq, candidate = visible.candidate,
                    power = visible.power, upgrades = {}, panel = visible.panel, generation = token }
                if context then
                    if deps.estimate and request.estimateVisible then
                        checkpoint()
                        result.estimate = deps.estimate(request, context)
                        checkpoint()
                    end
                    for _, slot in ipairs(deps.slots) do
                        checkpoint()
                        result.upgrades[slot.slot] = deps.hasUpgrade(request.heroId, slot.slot,
                            context.equipmentData, context, checkpoint)
                    end
                end
                return result
            end)
        end
        local running, key, token = job, jobKey, generation
        -- 签名校验和原子属性刷新不消耗worker推进额度，避免大名册每轮都过早让出。
        steps, deadline = 0, os.clock() + (deps.budgetSeconds or 0.001)
        local ok, result = coroutine.resume(running)
        if not ok then
            job, jobKey = nil, nil
            print("[CharacterDetail] prepare failed: " .. tostring(result))
        elseif coroutine.status(running) == "dead" then
            job, jobKey = nil, nil
            -- resume期间没有其他游戏更新；capture仍复核全部输入，原子发布同版本bundle。
            if token == generation and key == capture().key then
                committed, completedKey = result, key
            end
        end
    end
    return api
end
return M
