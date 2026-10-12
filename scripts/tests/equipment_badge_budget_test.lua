-- 角标预算回归：加载真实调度器，时间与候选循环隔离，不访问玩家文件。
local TAG = "[equipment_badge_budget_test]"

local function source(path)
    local file = assert(cache:GetFile(path), path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

function Start()
    local assertions = 0
    local function check(ok, label)
        assertions = assertions + 1
        assert(ok, label)
    end
    local revisions, calls, now = {}, 0, 0
    local published, badge, town = {}, false, 0
    local owned = { [1] = {}, [2] = {}, [3] = {} }
    local target = false
    local store = { GetRevision = function(key) return revisions[key] or 0 end }
    local detail = {
        hasAwakeningUpgrade = function(id) return id == 3 end,
        hasAnyUpgradeForHero = function(id, checkpoint)
            for _ = 1, 400 do
                if checkpoint then checkpoint() end
                calls, now = calls + 1, now + 0.00005
            end
            return id == 2 and target
        end,
    }
    local env = setmetatable({}, { __index = _G })
    env.os = { clock = function() return now end }
    env.require = function(name)
        if name == "ui.church.ChurchPage" then return { hasAdvanceForHero = function() return false end } end
        return {}
    end
    local Power = assert(load(source("ui/character/panel/CharacterPower.lua"), "@CharacterPower.lua", "t", env))()
    local function bind()
        return Power.bind({
            AD = { STR = "str", AGI = "agi", INT = "int", VIT = "vit", LUK = "luk", SPI = "spi",
                HP = "hp", ATK_INTERVAL = "interval", PHYS_RES = "pr", MAG_RES = "mr" },
            PlayerStore = store, CharacterDetail = detail,
            CharacterPanel = { isHeroDeployed = function(id) return id ~= 3 end },
            BottomNav = { setBadge = function(_, v) badge = v end,
                refreshTownBadge = function() town = town + 1 end },
            get = function(key) if key == "ownedSet" then return owned end end,
            set = function(key, value) if key == "upgradeBadgeCache" then published = value end end,
        })
    end
    local scheduler = bind()
    scheduler.refreshNavBadge()
    check(calls == 0 and town == 1, "请求只排队，不在数据通知里扫描候选")
    scheduler.updateBadges()
    check(calls > 0 and calls <= 128, "单次驱动按时间/候选预算让出")
    check(published[2] == false and published[3] == true, "只提前发布轻量养成，不发布部分装备角标")
    local function finish()
        for _ = 1, 120 do scheduler.updateBadges() end
    end
    finish()
    check(calls == 800, "两出战英雄完整遍历，未出战只检查养成")
    check(published[1] == false and published[2] == false and published[3] == true and badge,
        "完整结果发布，未出战觉醒也保留")
    local stableCalls = calls
    finish()
    check(calls == stableCalls, "完成后update不重复扫描")

    target = true
    revisions.equipment = 1
    scheduler.refreshNavBadge()
    scheduler.updateBadges()
    local beforeRestart = calls
    revisions.equipment = 2
    scheduler.updateBadges()
    check(calls > beforeRestart and published[2] == false, "同引用版本变化重启且不发布旧任务")
    finish()
    check(published[2] == true, "重启后发布新版本结果")
    target = false
    revisions.equipment = 3
    scheduler.refreshNavBadge()
    scheduler.updateBadges()
    scheduler.cancelBadgeRefresh()
    stableCalls = calls
    finish()
    check(calls == stableCalls and next(published) == nil and not badge, "清档取消任务及旧角标")
    scheduler.refreshNavBadge()
    scheduler.refreshNavBadge()
    stableCalls = calls
    finish()
    check(calls - stableCalls == 800, "连续通知只执行最后一次排队任务")
    stableCalls = calls
    scheduler.refreshNavBadge()
    finish()
    check(calls == stableCalls, "已完成同语义通知不重复扫库存")
    revisions.equipment = 4
    scheduler.refreshNavBadge()
    stableCalls = calls
    for frame = 1, 120 do
        revisions.heroes, revisions.currency, revisions.player = frame, frame, frame
        owned[1].exp = frame
        scheduler.refreshNavBadge()
        scheduler.updateBadges()
    end
    check(calls - stableCalls == 800, "持续经验/金币通知不取消或饿死角标任务")
    revisions.equipment = 5
    scheduler.refreshNavBadge()
    scheduler.updateBadges()
    owned[1].level = 60
    stableCalls = calls
    scheduler.updateBadges()
    finish()
    check(calls - stableCalls == 800, "英雄等级语义变更重启完整候选检查")
    target, revisions.equipment = true, 6
    local immediate = scheduler.refreshUpgradeBadgeCache()
    check(immediate[2] == true, "同步查询发布当前版本装备结果")
    stableCalls = calls
    scheduler.refreshNavBadge()
    finish()
    check(published[2] == true and calls == stableCalls, "同步查询同步预算缓存，不闪回旧角标或重复扫描")
    target = false

    -- 无版本的旧宿主保持同步契约，显式同步查询也不改变返回值。
    store.GetRevision = nil
    scheduler = bind()
    stableCalls = calls
    scheduler.refreshNavBadge()
    check(calls - stableCalls == 800, "旧宿主无版本时同步刷新")
    local result = scheduler.refreshUpgradeBadgeCache()
    check(result[3] == true and result[2] == false, "显式刷新仍返回完整缓存")
    print(TAG .. " ALL PASS assertions=" .. tostring(assertions))
    if engine and engine.Exit then engine:Exit() end
end
