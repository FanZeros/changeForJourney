-- 成功修改后的同步通知上下文；不写入玩家模块/装备/存档，不信请求或回执。
-- 只包围首次权威 MarkDirty，Panel 在评分前一次消费；离开发布栈自动清理。
local Context = {}
---@type table<table, table<string, table>>
local notifications = setmetatable({}, { __mode = "k" })

---@param data table
---@param moduleName string
---@param cause string|nil
---@param publish function
function Context.withNotification(data, moduleName, cause, publish)
    local scopes = notifications[data]
    if not scopes then scopes = {}; notifications[data] = scopes end
    local previous = scopes[moduleName]
    scopes[moduleName] = { cause = cause }
    local result = table.pack(pcall(publish))
    scopes[moduleName] = previous
    if next(scopes) == nil then notifications[data] = nil end
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
end

---@param data table|nil
---@param moduleName string
---@return string|nil
function Context.takeCause(data, moduleName)
    if type(data) ~= "table" then return nil end
    local scopes = notifications[data]
    local notification = scopes and scopes[moduleName]
    if not notification then return nil end
    scopes[moduleName] = nil
    return notification.cause
end

return Context
