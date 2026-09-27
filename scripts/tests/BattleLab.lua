-- BattleLab：独立战斗实验。只在 tests/battle_lab.lua 的新 Runtime 进程中运行。
-- 复用 BattleTriDriver/BattleStats/正式怪物配置；不访问存档、不发奖励。
local HC = require("config.HeroConfig")
local SC = require("config.StageConfig")
local Stats = require("systems.BattleStats")
local Driver = require("ui.battle.tri.BattleTriDriver")
local Layout = require("core.BattleLayout")

local Lab = {}
local STEP = 1 / 60
local MAX_RUNS = 1000
local MAX_HERO_LEVEL = 345

local function integer(value, default, minValue, maxValue)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return default end
    return math.max(minValue, math.min(maxValue, math.floor(number)))
end

function Lab.prepare(config)
    if type(config) ~= "table" then return nil, "需要 JSON 测试配置" end
    local stageId = integer(config.stageId, SC.NORMAL_FIRST_STAGE, 1, 99999)
    local stage = SC.getStage(stageId)
    if not stage then return nil, "未知关卡 ID: " .. tostring(stageId) end
    local rawHeroes = config.heroes
    if type(rawHeroes) ~= "table" or #rawHeroes < 1 or #rawHeroes > 4 then
        return nil, "heroes 需要 1~4 个英雄（可填 ID 或 {id, level}）"
    end
    local heroes = {}
    local seen = {}
    for i, value in ipairs(rawHeroes) do
        local id = integer(type(value) == "table" and (value.id or value.heroId) or value, 0, 1, 999)
        if not HC.get(id) then return nil, "第 " .. i .. " 个英雄 ID 不存在" end
        if seen[id] then return nil, "重复英雄 ID: " .. id end
        seen[id] = true
        local level = integer(type(value) == "table" and value.level or config.level, 1, 1, MAX_HERO_LEVEL)
        heroes[i] = { id = id, level = level }
    end
    local runs = integer(config.runs, 20, 1, MAX_RUNS)
    local seed = integer(config.seed, 926, 1, 2147483646)
    local mode = config.mode == "idle" and "idle" or "firstClear"
    if stage.mode == "terminal" and mode == "idle" then
        return nil, "终焉神殿没有挂机敌人，请切换首通模式"
    end
    local prepared = { stageId = stageId, stage = stage, heroes = heroes,
        runs = runs, seed = seed, mode = mode,
        timeLimit = integer(config.timeLimit, 300, 1, 600),
    }
    return prepared
end

local function copyHeroStats(stats)
    local result = {}
    for _, s in ipairs(stats) do
        result[#result + 1] = {
            heroId = s.heroId, name = s.name,
            damage = s.totalDamage, physical = s.physDamage, magical = s.magDamage,
            dot = s.dotDamage, healing = s.totalHeal, taken = s.takenDamage,
            hits = s.hitCount, critHits = s.critHitCount, crits = s.critCount,
        }
    end
    return result
end

-- 一局按 1/60 秒固定步长模拟；UI 的多局同步执行期间会暂时停止重绘。
local function runOne(cfg, index)
    math.randomseed(cfg.seed + index - 1)
    local drv = Driver.new(926, {
        battleLab = true,
        firstClear = cfg.mode == "firstClear",
        timeLimit = cfg.timeLimit,
        allyFactory = function()
            local team = {}
            for _, hero in ipairs(cfg.heroes) do
                local unit = HC.createHero(hero.id, hero.level, nil, nil, false)
                assert(unit, "英雄创建失败: " .. hero.id)
                team[#team + 1] = unit
            end
            return team
        end,
    })
    drv:start(cfg.stageId)
    if #drv.allies == 0 or drv.stageTotal == 0 then
        error("战斗初始化失败: 英雄或怪物列表为空")
    end
    local maxFrames = math.ceil((cfg.timeLimit + 12) / STEP)
    local frames = 0
    while drv.active and frames < maxFrames do
        drv:update(STEP)
        frames = frames + 1
    end
    drv:activate()
    local heroes = copyHeroStats(Stats.getSorted("totalDamage"))
    local winner = drv._clearReported and "win" or drv._labDefeated and "lose"
        or drv._labTimedOut and "timeout" or "error"
    local survivors = 0
    local hpLeft, hpMax = 0, 0
    for _, ally in ipairs(drv.allies) do
        if ally.hp > 0 then survivors = survivors + 1 end
        hpLeft = hpLeft + math.max(0, ally.hp or 0)
        hpMax = hpMax + (ally.maxHp or 0)
    end
    return {
        index = index, seed = cfg.seed + index - 1, outcome = winner,
        seconds = math.min(cfg.timeLimit, drv._labElapsed or 0),
        kills = drv.kills, monsters = drv.stageTotal,
        survivors = survivors, hpRemainingPct = hpMax > 0 and hpLeft / hpMax * 100 or 0,
        totalDamage = Stats.getTotal("totalDamage"),
        totalHealing = Stats.getTotal("totalHeal"),
        heroes = heroes,
    }
end

function Lab.run(config, progress)
    local cfg, errorMessage = Lab.prepare(config)
    if not cfg then return nil, errorMessage end
    local oldLayout = Layout.MODE
    local oldBucket = Stats.mountedTeam()
    local SFX = require("systems.GameSFX")
    local oldSound = SFX.isTeamMuted(926)
    Layout.setMode("strip")
    SFX.setTeamMuted(926, true)
    local report = {
        schemaVersion = 1, stageId = cfg.stageId, stageName = cfg.stage.name,
        mode = cfg.mode, seed = cfg.seed, timeLimit = cfg.timeLimit,
        requestedRuns = cfg.runs, completedRuns = 0,
        wins = 0, losses = 0, timeouts = 0, errors = 0,
        avgSeconds = 0, avgHpRemainingPct = 0, avgDamage = 0, avgHealing = 0,
        heroes = cfg.heroes, heroStats = {}, runs = {},
        note = "独立测试进程的模板英雄（无装备/遗物/神器/玩家存档）；真实三行驱动的技能与伤害，首通含地图词缀与狂暴；挂机只测本关敌人列表，不含主线前五关混合出怪与完整 BattleScene 结算。",
    }
    local ok, err = xpcall(function()
        for i = 1, cfg.runs do
            local one = runOne(cfg, i)
            report.runs[#report.runs + 1] = one
            report.completedRuns = i
            if one.outcome == "win" then report.wins = report.wins + 1
            elseif one.outcome == "lose" then report.losses = report.losses + 1
            elseif one.outcome == "timeout" then report.timeouts = report.timeouts + 1
            else report.errors = report.errors + 1 end
            report.avgSeconds = report.avgSeconds + one.seconds
            report.avgHpRemainingPct = report.avgHpRemainingPct + one.hpRemainingPct
            report.avgDamage = report.avgDamage + one.totalDamage
            report.avgHealing = report.avgHealing + one.totalHealing
            for _, item in ipairs(one.heroes) do
                local stat = report.heroStats[item.heroId]
                if not stat then
                    stat = { heroId = item.heroId, name = item.name, damage = 0,
                        healing = 0, taken = 0, hits = 0, critHits = 0, crits = 0 }
                    report.heroStats[item.heroId] = stat
                end
                stat.damage = stat.damage + item.damage
                stat.healing = stat.healing + item.healing
                stat.taken = stat.taken + item.taken
                stat.hits = stat.hits + item.hits
                stat.critHits = stat.critHits + item.critHits
                stat.crits = stat.crits + item.crits
            end
            if progress then progress(i, cfg.runs, one) end
        end
    end, debug.traceback)
    require("ui.battle.stage.StageBerserk").exit()
    SFX.setTeamMuted(926, oldSound)
    Stats.mount(oldBucket or 0)
    Layout.setMode(oldLayout or "strip")
    if not ok then return nil, err end
    local n = report.completedRuns
    report.winRate = report.wins / n * 100
    report.avgSeconds = report.avgSeconds / n
    report.avgHpRemainingPct = report.avgHpRemainingPct / n
    report.avgDamage = report.avgDamage / n
    report.avgHealing = report.avgHealing / n
    local list = {}
    for _, hero in ipairs(cfg.heroes) do
        local stat = report.heroStats[hero.id] or {
            heroId = hero.id, name = HC.get(hero.id).name, damage = 0,
            healing = 0, taken = 0, hits = 0, critHits = 0, crits = 0,
        }
        stat.avgDamage = stat.damage / n
        stat.avgHealing = stat.healing / n
        stat.avgTaken = stat.taken / n
        stat.critRate = stat.critHits > 0 and stat.crits / stat.critHits * 100 or 0
        list[#list + 1] = stat
    end
    table.sort(list, function(a, b) return a.damage > b.damage end)
    report.heroStats = list
    return report
end

return Lab
