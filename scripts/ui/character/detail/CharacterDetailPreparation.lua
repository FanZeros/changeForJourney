-- 配装详情的单私有协程。只在Update推进；半成品不进入共享EquipmentPower缓存。
local Store = require("core.PlayerStore")
local Dispatcher = require("runtime.ClientDispatcher")
local Power = require("systems.EquipmentPower")
local Eq = require("systems.EquipmentSystem")
local Snapshot = require("ui.character.detail.CharacterDetailSnapshot")
local M = {}
local EMPTY_SOURCE = {}

-- 仅小依赖校验，Render可调用，不复制/扫描完整库存或运行属性管线。
function M.version(request)
    local sources = {}
    for _, key in ipairs({ "heroes", "equipment", "artifacts", "talents" }) do
        sources[key] = Dispatcher.get(key) or Store.Get(key) or EMPTY_SOURCE
    end
    request.sources = sources
    -- 下部属性只依赖已穿/候选内容；库存其它物品掉落不能把它清空。
    -- 整库评分仍额外遵守引用/revision契约，两种结果不共用提交栅栏。
    request.panelKey = request.viewKey .. "\31" .. Snapshot.dependencies(sources, request.seq, request.heroId)
    local parts = { request.panelKey }
    for _, key in ipairs({ "equipment", "artifacts", "talents" }) do
        parts[#parts + 1] = tostring(sources[key])
        parts[#parts + 1] = tostring(Store.GetRevision and Store.GetRevision(key) or 0)
    end
    request.key = table.concat(parts, "\31")
    return request
end

function M.bind(deps)
    ---@type thread|nil
    local job = nil
    local jobKey, completedKey = nil, nil
    local panelKey, preparedPanel = nil, nil
    local generation, steps, deadline = 0, 0, 0
    local committed = { pending = true, scores = {}, upgrades = {} }
    local api = {}
    local function capture()
        local request = deps.capture()
        return M.version(request)
    end
    local function checkpoint()
        steps = steps + 1
        if steps >= (deps.maxSteps or 64) or os.clock() >= deadline then coroutine.yield() end
    end
    function api.cancel()
        generation = generation + 1
        job, jobKey, completedKey = nil, nil, nil
        panelKey, preparedPanel = nil, nil
        committed = { pending = true, scores = {}, upgrades = {} }
        deps.clear()
    end
    function api.read(viewKey)
        -- 只读小依赖签名；Update之后同帧业务patch也不能显示旧比较/箭头。
        if committed.viewKey ~= viewKey or completedKey ~= capture().key then
            return { pending = true, scores = {}, upgrades = {} }
        end
        return committed
    end
    function api.update()
        local request = capture()
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
        if completedKey == request.key then return end
        if not job or jobKey ~= request.key then
            generation = generation + 1
            local token = generation
            jobKey, completedKey = request.key, nil
            committed = { viewKey = request.viewKey, pending = true, scores = {}, upgrades = {} }
            local panel = preparedPanel
            job = coroutine.create(function()
                -- 完整库存只服务评分/箭头；慢任务重启或失败不再清空已提交的属性。
                checkpoint()
                local sources = request.sources
                local context = #deps.slots > 0 and Power.buildContext(request.heroId, {
                    heroes = sources.heroes, equipment = sources.equipment,
                    artifacts = sources.artifacts, talents = sources.talents,
                    checkpoint = checkpoint, cacheFixedTeammates = true,
                })
                local result = { viewKey = request.viewKey, pending = false, scores = {}, upgrades = {},
                    scoresBySeq = {}, panel = panel, generation = token }
                if context then
                    result.power = math.floor(context.currentPower + 0.5)
                    if deps.estimate and request.estimateVisible then
                        checkpoint()
                        result.estimate = deps.estimate(request, context)
                        checkpoint()
                    end
                    local slots = Eq.getHeroSlots(context.equipmentData, request.heroId) or {}
                    for _, slot in ipairs(deps.slots) do
                        checkpoint()
                        local seq = slots[slot.slot]
                        local item = seq and Eq.getFromInventory(context.equipmentData, seq)
                        if item then
                            local score = Power.scoreInContext(context, item, slot.slot, seq)
                            result.scores[slot.slot] = score
                            result.scoresBySeq[tostring(seq) .. ":" .. slot.slot] = score
                            if slot.slot == "weapon" and item.grip == "twohand" then
                                -- 副手是主武器占位，不执行一次非法副手试穿。
                                result.scoresBySeq[tostring(seq) .. ":offhand"] = score
                            end
                        end
                        result.upgrades[slot.slot] = deps.hasUpgrade(request.heroId, slot.slot,
                            context.equipmentData, context, checkpoint)
                    end
                    if request.seq then
                        checkpoint()
                        local candidate = Eq.getFromInventory(context.equipmentData, request.seq)
                        local targetSlot = request.slot or (candidate and candidate.slot)
                        local evaluation = candidate and Power.evaluate(context, request.seq, targetSlot)
                        if evaluation and evaluation.valid then
                            result.candidate = { seq = tostring(request.seq), slot = targetSlot,
                                score = math.floor(evaluation.power + 0.5), gain = evaluation.gain }
                        end
                        checkpoint()
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
