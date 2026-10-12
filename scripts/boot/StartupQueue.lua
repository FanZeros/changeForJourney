-- 启动任务合作式分帧：只在本队列的协程内让出，普通绘制/事件回调不受影响。
local M = {}

---@class StartupQueue
---@field steps table[]
---@field index number
---@field worker thread|nil
---@field budget number
---@field maxImages number
---@field frameStart number
---@field stepStart number
---@field images number
---@field clock fun(): number
---@field onComplete fun(index:number, name:string, elapsed:number, ok:boolean, err:any)|nil
local Queue = {}
Queue.__index = Queue

---@type StartupQueue|nil
local activeQueue = nil

---@param steps table[]
---@param options? table
---@return StartupQueue
function M.new(steps, options)
    options = options or {}
    return setmetatable({
        steps = steps, index = 0, worker = nil,
        budget = options.budget or 0.004,
        maxImages = options.maxImages or 2,
        frameStart = 0, stepStart = 0, images = 0,
        clock = options.clock or function() return time.elapsedTime end,
        onComplete = options.onComplete,
    }, Queue)
end

--- 在真实资源加载前检查预算。单张解码不可抢占，超时后下一项才让出。
function M.checkpoint()
    local queue = activeQueue
    if not queue or coroutine.running() ~= queue.worker or not coroutine.isyieldable() then return end
    if queue.images >= queue.maxImages or queue.clock() - queue.frameStart >= queue.budget then
        coroutine.yield()
    end
    queue.images = queue.images + 1
end

--- 每帧最多恢复一次；任务结束也不在同帧追赶下一步。
---@return boolean done
function Queue:pump()
    if self.index >= #self.steps and not self.worker then return true end
    if not self.worker then
        self.index = self.index + 1
        local step = self.steps[self.index]
        self.stepStart = self.clock()
        self.worker = coroutine.create(step[2])
    end
    self.frameStart = self.clock()
    self.images = 0
    local previous = activeQueue
    activeQueue = self
    local ok, err = coroutine.resume(self.worker)
    activeQueue = previous
    if not ok or coroutine.status(self.worker) == "dead" then
        local step = self.steps[self.index]
        self.worker = nil
        if self.onComplete then
            self.onComplete(self.index, step[1], self.clock() - self.stepStart, ok, err)
        end
    end
    return self.index >= #self.steps and not self.worker
end

return M
