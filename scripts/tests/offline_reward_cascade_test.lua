-- 离线奖励大批量弹出回归：真实时间轴与弹窗，模拟时钟，不改存档或图形 API。
-- Runtime: tests/offline_reward_cascade_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
function Start()
    local Cascade = require("ui.widget.RewardCascade")
    local Panel = require("ui.hud.popup.OfflineRewardPanel")
    local SFX = require("systems.GameSFX")
    local originalTime = rawget(_G, "time")
    local originalNew, originalPlay = Cascade.new, SFX.play
    local clock = { elapsedTime = 100 }
    rawset(_G, "time", clock)
    local assertions = 0
    local sounds = {}
    ---@type any
    local captured = {}

    local function check(condition, label)
        assertions = assertions + 1
        assert(condition, label)
    end
    local function near(actual, expected, label)
        check(math.abs(actual - expected) < 0.0000001,
            label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
    end
    local function referenceStart(timeline, idx)
        local result = 0
        for i = 2, idx do result = result + timeline:gap(i) end
        return result
    end
    local function referenceShown(timeline, elapsed)
        if elapsed < 0 then return 0 end
        local shown = 0
        for i = 1, timeline.count do
            if elapsed + 0.0001 < referenceStart(timeline, i) then break end
            shown = i
        end
        return shown
    end

    local ok, err = pcall(function()
        -- 默认首通、离线三段、缺省最快间隔、零间隔与反向阈值均保持原来 gap 语义。
        local options = {
            {},
            { interval = 0.14, intervalTail = 0.10, fastAfter = 10,
                intervalFaster = 0.05, fasterAfter = 20 },
            { interval = 0.14, intervalTail = 0.06, fastAfter = 10,
                intervalFaster = 0.002, fasterAfter = 20 },
            { interval = 0, intervalTail = 0, fastAfter = 3 },
            { fastAfter = 8, fasterAfter = 3, intervalFaster = 0.03 },
            { fastAfter = 0, fasterAfter = 0, intervalFaster = 0.01 },
            { fastAfter = 10.5, fasterAfter = 20.5 },
        }
        for _, opts in ipairs(options) do
            local timeline = originalNew(100, opts)
            for i = 1, 100 do
                near(timeline:startAt(i), referenceStart(timeline, i), "区段求和与逐项累计一致")
            end
            for _, elapsed in ipairs({ -0.01, 0, 0.1198, 0.12, 0.84, 1.26, 1.86, 3, 30 }) do
                check(timeline:shownCount(elapsed) == referenceShown(timeline, elapsed),
                    "二分已显示数量与旧算法一致")
            end
            for _, i in ipairs({ 2, 8, 9, 10, 11, 20, 21, 99, 100 }) do
                local at = referenceStart(timeline, i)
                for _, delta in ipairs({ -0.0002, -0.00005, 0, 0.00005 }) do
                    check(timeline:shownCount(at + delta) == referenceShown(timeline, at + delta),
                        "区段边界与浮点容差不变")
                end
            end
        end
        local default = originalNew(200)
        near(default:startAt(200) + default.popDur + default.lead, 20.36, "普通首通200项节奏不变")
        local empty = originalNew(0)
        check(empty:finished() and empty:shownCount(100) == 0, "空奖励直接完成")
        local single = originalNew(1)
        single:start(clock.elapsedTime)
        check(single:t(1) == nil, "首件保留停顿")
        clock.elapsedTime = single.revealStart
        near(single:t(1), 0, "出场边界进度为0")
        clock.elapsedTime = single.revealStart + single.popDur + 0.000001
        check(single:finished(), "最后动画落地才完成")
        single:start(clock.elapsedTime, true)
        near(single:elapsed(), 0, "跳过首件停顿")
        single:skipToEnd()
        near(single:t(1), 1, "跳过动画推进到落地边界")
        check(single:shownCount() == 1, "跳过动画不漏显示首件")
        clock.elapsedTime = clock.elapsedTime + 0.000001
        check(single:finished(), "跳过后的浮点边界正常完成")

        -- 捕获真实 Panel.show 创建的时间轴，避免只验证手抄参数。
        Cascade.new = function(count, opts)
            captured = originalNew(count, opts)
            return captured
        end
        SFX.play = function(key) sounds[#sounds + 1] = key end
        local source = {}
        local function showCount(count, withHeroes)
            clock.elapsedTime = 100
            sounds = {}
            source = {}
            if count > 0 then source[1] = { type = "gold", amount = 100 } end
            for i = 2, count do
                source[i] = { type = "equip", templateId = "W1", quality = 1, level = i }
            end
            Panel.show({
                offlineSeconds = 86400,
                rewards = source,
                heroExpPreview = withHeroes and {
                    { heroId = 1, startLevel = 1, startExp = 0, expGain = 100 },
                } or {},
            })
            check(captured.count == count and #source == count, "奖励条目数量未改变")
            if count > 0 then near(captured.revealStart, 100.55, "首件与队员动画同起点") end
            return captured
        end
        for _, count in ipairs({ 0, 1, 10, 11, 20, 21, 100, 120, 121, 200, 1000, 10000 }) do
            local timeline = showCount(count, false)
            local lastStart = timeline:startAt(count)
            if count > 0 then
                check(lastStart + timeline.lead + timeline.popDur <= 4.6500001,
                    "任意大队列约4.65秒全部落地")
                for i = 2, math.min(count, 10) do near(timeline:gap(i), 0.14, "前10项节奏不变") end
                if count > 10 then near(timeline:gap(11), 0.06, "第11项开始加速") end
                if count > 20 then
                    check(timeline:gap(21) <= 0.02, "第21项起间隔不超过20毫秒")
                    check(lastStart - timeline:startAt(20) <= 2.0000001, "尾段排队不超过2秒")
                end
            end
        end
        local hundred = showCount(100, false)
        near(hundred:startAt(100) + hundred.lead + hundred.popDur, 4.25, "100项由7.05秒降至4.25秒")
        local large = showCount(200, false)
        near(large:startAt(200) + large.lead + large.popDur, 4.65, "200项由12.05秒降至4.65秒")
        local withHeroes = showCount(200, true)
        near(withHeroes:startAt(200), large:startAt(200), "队员经验预览不阻塞装备动画")

        -- 大帧跳跃到尾部：一帧最多一个入场音；未新增奖励时不能重播。
        local soundTimeline = showCount(200, false)
        Panel.update(1 / 60)
        check(#sounds == 0, "停顿期间不播放入场音")
        clock.elapsedTime = soundTimeline.revealStart + 0.001
        Panel.update(1 / 60)
        check(#sounds == 1 and sounds[1] == "ui_click_3", "资源首件播放资源音")
        clock.elapsedTime = soundTimeline.revealStart + soundTimeline:startAt(2) + 0.001
        Panel.update(1 / 60)
        check(#sounds == 2 and sounds[2] == "install", "装备入场播放安装音")
        clock.elapsedTime = soundTimeline.revealStart + soundTimeline:startAt(200) + 0.3
        Panel.update(1 / 60)
        check(#sounds == 3, "同帧批量出场只补一次音效")
        Panel.update(1 / 60)
        check(#sounds == 3, "同一批奖励不会重复播放音效")
        check(soundTimeline:shownCount() == 200 and soundTimeline:finished(), "音效合并不漏显示奖励")
        check(source[1].type == "gold" and source[2].level == 2 and source[200].level == 200,
            "奖励源数组顺序与内容不变")

        -- 不等待动画即可领取；失败保留、再次成功后关闭动画正常结束。
        clock.elapsedTime = 200
        local attempts = 0
        Panel.show({ rewards = source, onClaim = function()
            attempts = attempts + 1
            return attempts > 1
        end })
        check(captured:t(200) == nil, "提前领取时末件尚未出场")
        check(Panel.claim() and Panel.isOpen() and attempts == 1, "领取失败保留弹窗")
        check(Panel.claim() and attempts == 2, "提前领取可重试成功")
        clock.elapsedTime = 201
        Panel.update(1 / 60)
        check(not Panel.isOpen(), "领取后的关闭动画正常结束")
        check(not Panel.claim() and attempts == 2, "关闭后不能再次领取")
    end)

    Cascade.new, SFX.play = originalNew, originalPlay
    rawset(_G, "time", originalTime)
    if not ok then error("[offline_reward_cascade_test] " .. tostring(err)) end
    print("[offline_reward_cascade_test] ALL PASS: " .. assertions .. " assertions")
    engine:Exit()
end
