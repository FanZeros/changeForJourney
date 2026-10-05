-- 真实单机入口启动验收：隔离本地存档读写，避免测试覆盖玩家存档。
-- 运行：UrhoXRuntime tests/team_parity_startup_validate.lua -tool_mode -graphicsheadless -validate。
-- 存档读写/恢复另由 team_save_reset_test 覆盖，此处只验证真实初始化与逐帧更新。
function Start()
    local Save = require("boot.StandaloneSave")
    Save.RestoreData = function() return false end
    Save.Flush = function() return true end
    Save.Update = function() end
    Save.Wipe = function() end
    print("[team_parity_startup] 玩家存档读写已隔离，启动真实Standalone")
    require("boot.Standalone").Start()
end

function Stop()
    require("boot.Standalone").Stop()
end
