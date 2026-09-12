-- ============================================================================
-- GMHandler - GM 命令网络入口
-- 职责: 参数提取 → 调 GMService → 返回结果
-- 层级: server/gm  |  薄 Handler
-- ============================================================================

local Protocol         = require("shared.Protocol")
local GMService        = require("server.gm.GMService")
local GMLogger         = require("server.gm.GMLogger")
local ServerDispatcher = require("network.ServerDispatcher")
local MailService      = require("server.mail.MailService")

local GMHandler = {}

-- ======================== GM 权限白名单 ========================
-- 只有以下 UID 才能执行 GM 指令，其余玩家一律拒绝。
-- 正式上线前务必更新此列表；留空则完全禁用 GM 功能。
local GM_WHITELIST = {
    [1658931154] = true,  -- 管理员 #1
    [1002454410] = true,  -- 管理员 #2
}

-- ======================== 公开接口 ========================

--- 判断指定 UID 是否为 GM（供 Server.lua 维护模式等外部模块使用）
---@param uid number
---@return boolean
function GMHandler.IsGM(uid)
    return GM_WHITELIST[uid] == true
end

-- ======================== 鉴权 ========================

--- 鉴权检查：uid 不在白名单时拒绝。供 Equipment/Relic 等非 GMHandler 模块复用。
---@param uid number
---@return boolean
function GMHandler.RequireAuth(uid)
    if not GM_WHITELIST[uid] then
        print("[GMHandler][WARN] 非授权 GM 请求 uid=" .. tostring(uid))
        return false
    end
    return true
end

--- 鉴权检查：uid 不在白名单时直接返回拒绝结果
local function checkGMAuth(uid)
    return GMHandler.RequireAuth(uid)
end

-- ======================== Handlers ========================

local handlers = {}

-- ──────────────────── 已有功能（资源/升级/重置） ────────────────────

--- GM: 给资源
handlers[Protocol.ACTION_TYPES.GM_GIVE_RESOURCE] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_GIVE_RESOURCE,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local key    = params and params.key
        local amount = params and tonumber(params.amount) or 0
        local ok, reason, result = GMService.GiveResource(uid, key, amount)
        if not ok then return { success = false, reason = reason } end
        return { success = true, key = result.key, newValue = result.newValue }
    end
)

--- GM: 英雄升级
handlers[Protocol.ACTION_TYPES.GM_LEVEL_UP] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_LEVEL_UP,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local heroId = params and tonumber(params.heroId)
        local ok, reason, result = GMService.LevelUpHero(uid, heroId)
        if not ok then return { success = false, reason = reason } end
        return { success = true, heroId = result.heroId, newLevel = result.newLevel }
    end
)

--- GM: 提升觉醒等级
handlers[Protocol.ACTION_TYPES.GM_AWAKENING] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_AWAKENING,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local heroId = params and tonumber(params.heroId)
        local ok, reason, result = GMService.ActivateAwakening(uid, heroId)
        if not ok then return { success = false, reason = reason } end
        return {
            success = true,
            heroId = result.heroId,
            nodeIndex = result.nodeIndex,
            awakeLevel = result.awakeLevel,
        }
    end
)

--- GM: 获得冒险家
handlers[Protocol.ACTION_TYPES.GM_GIVE_HERO] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_GIVE_HERO,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local heroId = params and tonumber(params.heroId)
        local level  = params and tonumber(params.level)
        local ok, reason, result = GMService.GiveHero(uid, heroId, level)
        if not ok then return { success = false, reason = reason } end
        return { success = true, heroId = result.heroId, level = result.level }
    end
)

--- GM: 冒险等级提升
handlers[Protocol.ACTION_TYPES.GM_PLAYER_LEVEL_UP] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_PLAYER_LEVEL_UP,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local ok, reason, result = GMService.PlayerLevelUp(uid)
        if not ok then return { success = false, reason = reason } end
        return { success = true, newLevel = result.newLevel }
    end
)

--- GM: Debug 跳转关卡（同步 maxStageId / clearedStages）
handlers[Protocol.ACTION_TYPES.GM_JUMP_STAGE] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_JUMP_STAGE,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local stageId = params and tonumber(params.stageId)
        local BattleService = require("server.battle.BattleService")
        local ok, err = BattleService.DebugJumpToStage(uid, stageId)
        if not ok then return { success = false, reason = err } end
        return { success = true, stageId = stageId }
    end
)

--- GM: 清除存档
handlers[Protocol.ACTION_TYPES.GM_RESET_SAVE] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_RESET_SAVE,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local ok, reason = GMService.ResetSave(uid)
        if not ok then return { success = false, reason = reason } end
        return { success = true }
    end
)

-- ──────────────────── 第一批新功能 ────────────────────

--- GM: 踢出玩家
handlers[Protocol.ACTION_TYPES.GM_KICK_PLAYER] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_KICK_PLAYER,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local targetUid = params and tonumber(params.targetUid)
        local reason    = params and params.reason or "被管理员踢出"
        local ok, errMsg = GMService.KickPlayer(targetUid, reason)
        if not ok then return { success = false, reason = errMsg } end
        return { success = true, targetUid = targetUid }
    end
)

--- GM: 向指定玩家发送邮件（支持资源附件，跨实例安全）
handlers[Protocol.ACTION_TYPES.GM_SEND_MAIL] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_SEND_MAIL,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local targetUid = params and tonumber(params.targetUid)
        local title     = params and params.title
        local body      = params and params.body or ""
        local rewards   = params and params.rewards  -- [{key, amount}, ...]
        local ok, reason, result = GMService.SendMailToPlayer(targetUid, title, body, rewards)
        if not ok then return { success = false, reason = reason } end

        -- 仅当目标在本实例（local 投递）时推送邮件列表
        -- cloud_queued 表示目标不在本实例，无法推送（下次登录时自动拉取）
        local delivered = result and result.delivered or ""
        if delivered == "local" then
            local mailList = MailService.BuildMailList(targetUid)
            if mailList then
                ServerDispatcher.sendEvent(targetUid, Protocol.RES_ACTION_RESULT, {
                    success  = true,
                    mailPush = true,
                    mails    = mailList,
                })
            end
        end

        return {
            success   = true,
            targetUid = targetUid,
            mailId    = result and result.mailId,
            delivered = delivered,
        }
    end
)

--- GM: 查询服务器状态（异步 — 需跨实例汇总在线玩家）
handlers[Protocol.ACTION_TYPES.GM_SERVER_STATUS] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_SERVER_STATUS,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        -- 异步获取跨实例状态，handler 返回 nil 表示"稍后自行响应"
        GMService.GetServerStatusAsync(function(status)
            ServerDispatcher.sendEvent(uid, Protocol.RES_ACTION_RESULT, {
                success = true,
                status  = status,
                action  = Protocol.ACTION_TYPES.GM_SERVER_STATUS,
            })
        end)
        return nil  -- 异步响应
    end
)

--- GM: 重置指定模块数据
handlers[Protocol.ACTION_TYPES.GM_RESET_MODULE] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_RESET_MODULE,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local targetUid  = params and tonumber(params.targetUid)
        local moduleName = params and params.moduleName
        local ok, reason = GMService.ResetModule(targetUid, moduleName)
        if not ok then return { success = false, reason = reason } end
        return { success = true, targetUid = targetUid, moduleName = moduleName }
    end
)

--- GM: 查询审计日志
handlers[Protocol.ACTION_TYPES.GM_QUERY_LOG] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_QUERY_LOG,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local count = params and tonumber(params.count) or 50
        local logs  = GMLogger.GetRecentLogs(count)
        local stats = GMLogger.GetStats()
        return { success = true, logs = logs, stats = stats }
    end
)

-- ──────────────────── 第二批新功能 ────────────────────

--- GM: 封禁玩家
handlers[Protocol.ACTION_TYPES.GM_BAN_PLAYER] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_BAN_PLAYER,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local targetUid = params and tonumber(params.targetUid)
        local duration  = params and tonumber(params.duration) or 0  -- 秒, 0=永久
        local reason    = params and params.reason or "违规操作"
        local ok, errMsg, result = GMService.BanPlayer(targetUid, duration, reason, uid)
        if not ok then return { success = false, reason = errMsg } end
        return { success = true, targetUid = targetUid, banExpireTime = result.banExpireTime }
    end
)

--- GM: 解封玩家
handlers[Protocol.ACTION_TYPES.GM_UNBAN_PLAYER] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_UNBAN_PLAYER,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local targetUid = params and tonumber(params.targetUid)
        local ok, errMsg = GMService.UnbanPlayer(targetUid)
        if not ok then return { success = false, reason = errMsg } end
        return { success = true, targetUid = targetUid }
    end
)

--- GM: 维护模式开关
handlers[Protocol.ACTION_TYPES.GM_MAINTENANCE] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_MAINTENANCE,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local enabled = params and params.enabled
        if enabled == nil then return { success = false, reason = "缺少 enabled 参数" } end
        -- 兼容字符串 "true"/"false"
        if type(enabled) == "string" then
            enabled = (enabled == "true")
        end
        local ok, errMsg, result = GMService.SetMaintenanceMode(enabled)
        if not ok then return { success = false, reason = errMsg } end
        return { success = true, maintenanceMode = result.maintenanceMode, kickedCount = result.kickedCount }
    end
)

--- GM: 查询在线玩家信息
handlers[Protocol.ACTION_TYPES.GM_QUERY_PLAYER] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_QUERY_PLAYER,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local targetUid = params and tonumber(params.targetUid)
        local ok, errMsg, result = GMService.QueryPlayer(targetUid)
        if not ok then return { success = false, reason = errMsg } end
        return { success = true, playerInfo = result }
    end
)

--- GM: 公告管理（增删查）
handlers[Protocol.ACTION_TYPES.GM_ANNOUNCEMENT] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_ANNOUNCEMENT,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local action = params and params.action  -- "add" | "remove" | "list"
        local data   = params and params.data    -- { id, title, content, type } for add; { id } for remove
        local ok, errMsg, result = GMService.ManageAnnouncement(action, data)
        if not ok then return { success = false, reason = errMsg } end
        return { success = true, result = result }
    end
)

--- GM: 全服邮件（支持区服范围选择）
handlers[Protocol.ACTION_TYPES.GM_BROADCAST_MAIL] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_BROADCAST_MAIL,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local title      = params and params.title
        local content    = params and params.content
        local rewards    = params and params.rewards    -- [{ type, amount }] 可选
        local expireDays = params and params.expireDays -- number 可选
        local serverIds  = params and params.serverIds  -- number[]|nil 目标区服（nil=全服）
        local ok, errMsg, result = GMService.BroadcastMail(title, content, rewards, expireDays, uid, serverIds)
        if not ok then return { success = false, reason = errMsg } end
        return { success = true, result = result }
    end
)

-- ──────────────────── 存档修复 ────────────────────

--- GM: 修复玩家丢档（诊断 + 迁移恢复）
--- params: { targetUid: number, dryRun?: boolean }
--- dryRun=true 时仅返回诊断报告不执行修复
handlers[Protocol.ACTION_TYPES.GM_REPAIR_SAVE] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_REPAIR_SAVE,
    function(uid, params)
        if not checkGMAuth(uid) then return { success = false, reason = "权限不足" } end
        local targetUid = params and tonumber(params.targetUid)
        local dryRun = params and params.dryRun
        -- 兼容字符串 "true"/"false"
        if type(dryRun) == "string" then
            dryRun = (dryRun == "true")
        end
        local ok, reason, result = GMService.RepairPlayerSave(targetUid, dryRun, uid)
        if not ok then return { success = false, reason = reason } end
        return { success = true, report = result }
    end
)

-- ======================== 导出 ========================

-- handlers 作为子表供 registerHandlers 使用
GMHandler.actionHandlers = handlers

return GMHandler
