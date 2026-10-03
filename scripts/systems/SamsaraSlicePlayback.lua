-- SamsaraSlicePlayback.lua — 旧播放源消化后的无奖展示边界。
-- 不消费旧队列，不发送领奖/教程/FOLLOW；结束只交还租约，下帧由宿主重新仲裁。
local Player = require("systems.SamsaraSlicePlayer")
local Config = require("config.SamsaraSliceConfig")
local Dialogue = require("ui.story.ScenarioDialogue")

local M = {}

---@param gates table { ready:boolean, legacyPending:boolean, blocked:boolean, pointerBusy:boolean }
---@return boolean 是否开始了新切片
function M.tryPlay(gates)
    if not gates or gates.ready ~= true or gates.legacyPending == true
        or gates.blocked == true or gates.pointerBusy == true or Dialogue.isActive() then
        return false
    end
    local request = Player.takeRequest()
    local key = request and request.key or Player.peekReady()
    if not key then return false end
    local kind = request and request.kind or "samsara_first_read"
    local cfg = Config.get(key)
    if not cfg or not cfg.steps or #cfg.steps == 0 then
        print("[SamsaraSlicePlayback] 缺少正文，保留待阅 key=" .. tostring(key))
        return false
    end
    local lease = Player.begin(kind, key)
    if not lease then return false end
    -- 首次准备可能刚挂案件副本，使用持久来源选择N12旁白，不伪造玩家持有史。
    if key == "samsara.cargo_match" then
        local record = Player.getRecord(key)
        local source = record.evidences and record.evidences[1] and record.evidences[1].source
        cfg = Config.get(key, source) or cfg
    end
    local ok, shown = pcall(Dialogue.show, {
        mode = cfg.mode, title = cfg.title, steps = cfg.steps,
        completionToken = lease,
        onResult = function(result) Player.onResult(result) end,
    })
    if not ok or shown ~= true then
        Player.onResult({ playToken = lease.playToken, contextEpoch = lease.contextEpoch,
            nodeKey = lease.nodeKey, reason = "failed" })
        print("[SamsaraSlicePlayback] 展示失败，待阅保留: " .. tostring(shown))
        return false
    end
    print("[SamsaraSlicePlayback] 无奖展示 key=" .. key .. " kind=" .. kind)
    return true
end

return M
