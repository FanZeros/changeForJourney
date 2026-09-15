-- ============================================================================
-- EventBus - 游戏内事件总线（轻量发布/订阅）
-- ============================================================================

local EventBus = {}
local listeners = {}

--- 订阅事件
function EventBus.on(event, callback)
    if not listeners[event] then
        listeners[event] = {}
    end
    table.insert(listeners[event], callback)
end

--- 取消订阅
function EventBus.off(event, callback)
    local list = listeners[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == callback then
            table.remove(list, i)
            break
        end
    end
end

--- 触发事件
function EventBus.emit(event, data)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do
        list[i](data)
    end
end

--- 清空所有监听
function EventBus.clear()
    listeners = {}
end

return EventBus
