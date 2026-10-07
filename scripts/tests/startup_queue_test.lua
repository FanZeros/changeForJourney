-- 启动合作式队列回归：资源数硬上限、时钟预算及普通事件不让出。
local failures, assertions = {}, 0
local function check(value, label)
    assertions = assertions + 1
    if not value then failures[#failures + 1] = label end
end

function Start()
    local ok, err = xpcall(function()
        local Queue = require("boot.StartupQueue")
        local images, completions, frames = 0, {}, 0
        local clock = 0
        local queue = Queue.new({
            { "images", function()
                for _ = 1, 9 do Queue.checkpoint(); images = images + 1 end
            end },
            { "next", function() check(images == 9, "下一任务只在上一步完整完成后执行") end },
            { "error", function() error("expected startup failure") end },
            { "afterError", function() check(#completions == 3, "失败任务报告后继续下一任务") end },
        }, { clock = function() return clock end, onComplete = function(index, name, elapsed, success)
            completions[#completions + 1] = { index = index, name = name, success = success }
        end })
        while true do
            frames = frames + 1
            local before = images
            local done = queue:pump()
            check(images - before <= 2, "恒定时钟下每帧最多两张资源 " .. frames)
            if done then break end
            check(frames < 20, "队列没有挂起")
            if frames >= 20 then break end
        end
        check(images == 9 and #completions == 4, "资源和完成回调恰好执行一次")
        check(frames == 8, "资源分五帧且后续三步各占一帧")
        check(completions[3].success == false and completions[4].success == true, "错误不冒充成功")
        check(queue:pump() and #completions == 4, "完成后重复泵不重跑")
        check(pcall(Queue.checkpoint), "队列外普通主线程不yield")

        images = 0
        local slow = Queue.new({ { "slow", function()
            for _ = 1, 4 do
                Queue.checkpoint()
                images = images + 1
                clock = clock + 0.010
            end
        end } }, { clock = function() return clock end })
        for i = 1, 4 do
            local before = images
            local done = slow:pump()
            check(images - before == 1, "超预算单图后下一图让到下一帧 " .. i)
            check(done == (i == 4), "最后一张之前不提前就绪 " .. i)
        end

        local nestedFinished = false
        local nested = Queue.new({ { "nested", function()
            local event = coroutine.create(function() Queue.checkpoint(); nestedFinished = true end)
            check(coroutine.resume(event), "异步事件协程可正常执行")
            check(coroutine.status(event) == "dead", "不是队列worker的协程不被yield")
            Queue.checkpoint()
        end } }, { maxImages = 1, clock = function() return clock end })
        check(nested:pump() and nestedFinished, "嵌套协程不会占用启动资源计数")
        check(Queue.new({}):pump(), "空队列立即完成")
    end, debug.traceback)
    if not ok then failures[#failures + 1] = tostring(err) end
    print("[startup_queue_test] assertions=" .. assertions .. " failures=" .. #failures)
    if #failures > 0 then print("[startup_queue_test] FAIL " .. table.concat(failures, " | "))
    else print("[startup_queue_test] ALL PASS") end
    engine:Exit()
end
