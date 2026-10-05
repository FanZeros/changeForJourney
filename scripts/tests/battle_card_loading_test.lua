-- 战斗预加载完成状态与帧预算回归；使用加载计数替身，不读取玩家存档。
local TAG = "[battle_card_loading_test]"
local failures, assertions = {}, 0
local function check(value, message)
    assertions = assertions + 1
    if not value then failures[#failures + 1] = message end
    print(TAG .. (value and " PASS: " or " FAIL: ") .. message)
end

function Start()
    local nativeImage, nativeTime = nvgCreateImage, time
    local Projectile = require("ui.battle.combat.ProjectileSystem")
    local nativeKeys, nativePrewarm = Projectile.getImageKeys, Projectile.prewarmOne
    local loads, prewarms = 0, 0
    local ok, err = xpcall(function()
        nvgCreateImage = function()
            loads = loads + 1
            return loads
        end
        Projectile.getImageKeys = function() return { "test_a", "test_b" } end
        Projectile.prewarmOne = function() prewarms = prewarms + 1 end
        -- 恒定时钟替身：即使加载缓存命中耗时不足8ms，任务数仍必须有上限。
        time = { elapsedTime = 123 }
        local Flow = require("ui.battle.stage.BattleStageFlow")
        local ctx = { imgHeroCards = {}, imgMonsterCards = {} }
        local queue = Flow.ensureBattleCards(ctx, nil)
        local jobs = #queue
        check(jobs > 4, "夹具包含超过单次泵上限的真实卡牌路径")
        local before = loads + prewarms
        queue = Flow.pumpBattleCards(queue, nil)
        check(loads + prewarms - before <= 4, "恒定计时替身下，单次泵最多处理4项加载")
        for _ = 1, jobs do
            queue = Flow.pumpBattleCards(queue, nil)
        end
        check(type(queue) == "table" and #queue == 0, "空队列保留已完成状态")
        check(loads + prewarms == jobs, "初次队列每项只执行一次")
        local finished = loads + prewarms
        for _ = 1, 180 do
            queue = Flow.ensureBattleCards(ctx, queue)
            queue = Flow.pumpBattleCards(queue, nil)
        end
        check(loads + prewarms == finished, "完成后180次调用不重新加载英雄/怪物/投射物")
        check(Flow.pumpBattleCards(nil, nil) == nil, "未初始化队列保持未初始化")

        local clock = 0
        time = setmetatable({}, { __index = function()
            clock = clock + 0.004
            return clock
        end })
        local slowJobs = {}
        for i = 1, 20 do slowJobs[i] = { fn = function() prewarms = prewarms + 1 end } end
        before = prewarms
        Flow.pumpBattleCards(slowJobs, nil)
        check(prewarms - before >= 1 and prewarms - before <= 2,
            "递增计时替身达到8ms后停止加载，不耗尽队列")
        time = nativeTime
        local nextCtx = { imgHeroCards = {}, imgMonsterCards = {} }
        local fresh = Flow.ensureBattleCards(nextCtx, nil)
        check(#fresh == jobs, "新上下文可显式从nil重新构建加载队列")

        -- 生产公开入口生命周期：同上下文重开保留缓存，新上下文重新加载。
        Projectile.getImageKeys, Projectile.prewarmOne = nativeKeys, nativePrewarm
        local cardLoads = 0
        nvgCreateImage = function(vg, path, flags)
            if path:find("image/角色卡牌/", 1, true) or path:find("image/怪物卡牌/", 1, true) then
                cardLoads = cardLoads + 1
            end
            return nativeImage(vg, path, flags)
        end
        local Scene = require("ui.battle.scene.BattleScene")
        local vg1 = assert(nvgCreate(1))
        Scene.init(vg1)
        for _ = 1, 240 do Scene.pumpBattleCards() end
        local initial = cardLoads
        local expected = #require("config.HeroAssetUtil").getAssetIds() + 67
        check(initial == expected, "真实BattleScene完整加载全部英雄和67项怪物卡牌")
        for _ = 1, 180 do Scene.pumpBattleCards() end
        check(cardLoads == initial, "公开入口完成后180帧不重复加载")
        Scene.resetToDefault()
        Scene.init(vg1)
        for _ = 1, 240 do Scene.pumpBattleCards() end
        check(cardLoads == initial, "同vg清档和重新初始化不重加载英雄/怪物卡")
        local vg2 = assert(nvgCreate(1))
        Scene.init(vg2)
        for _ = 1, 240 do Scene.pumpBattleCards() end
        check(cardLoads == initial * 2, "完成后新vg重建恰好一代卡牌")
        Scene.init(vg1)
        Scene.pumpBattleCards()
        check(cardLoads > initial * 2, "新vg加载中已有首批卡牌")
        local partial = cardLoads
        Scene.init(vg2)
        for _ = 1, 240 do Scene.pumpBattleCards() end
        check(cardLoads == partial + initial, "加载中新vg失效旧队列并完整加载一代")
        nvgDelete(vg1)
        nvgDelete(vg2)
    end, debug.traceback)
    nvgCreateImage, time = nativeImage, nativeTime
    Projectile.getImageKeys, Projectile.prewarmOne = nativeKeys, nativePrewarm
    if not ok then failures[#failures + 1] = tostring(err) end
    if #failures == 0 then
        print(TAG .. " ALL PASS assertions=" .. assertions)
    else
        print(TAG .. " FAIL count=" .. #failures .. ": " .. table.concat(failures, " | "))
    end
    engine:Exit()
end
