-- 原生Runtime定向入口：仅运行原async专项的5组真实宿主逐帧background回归。
-- 保留原12件fixture、私有require、完整业务链及全部断言；不启动Boot/读取玩家档。
-- 不代表完整async全集，全集仍使用 tests/quick_equip_async_test.lua。
local PREFIX = "real host frame pump empty slots with continuous background / "
local MARKER = "local function group(name, fn)\n"

function Start()
    local file = assert(cache:GetFile("tests/quick_equip_async_test.lua"), "missing async test source")
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local source = table.concat(lines, "\n")
    local first = assert(source:find(MARKER, 1, true), "async group function changed; update live entry")
    assert(not source:find(MARKER, first + #MARKER, true), "ambiguous async group function")
    local selected = 0
    local env = setmetatable({ QUICK_EQUIP_FROZEN_ORACLE = false }, { __index = _G })
    env._G = env
    env.selectQuickEquipLiveGroup = function(name)
        if name:sub(1, #PREFIX) ~= PREFIX then return false end
        selected = selected + 1
        return true
    end
    local insertion = "    if not selectQuickEquipLiveGroup(name) then return end\n"
    source = source:sub(1, first + #MARKER - 1) .. insertion .. source:sub(first + #MARKER)
    -- 原专项收尾先检查实际执行组数，再允许Runtime退出；缺匹配不能伪报全绿。
    env.engine = { Exit = function()
        assert(selected == 5, "quick equip live entry expected exactly 5 groups, got " .. selected)
        print("[quick_equip_live_test] selected=5 (live-only; not full async suite)")
        engine:Exit()
    end }
    assert(load(source, "@quick-equip-live/quick_equip_async_test.lua", "t", env))()
    assert(type(env.Start) == "function", "async Start missing")
    env.Start()
end
