-- ============================================================================
-- BanService - 玩家封禁/解封业务逻辑
-- 职责: 封禁持久化（写入 global_profile.banInfo）、解封、封禁检查
-- 层级: server/gm  |  通过 PDM 读写 global_profile
-- ============================================================================

local PDM = require("server.character.PlayerDataManager")

local BanService = {}

-- ======================== 封禁检查 ========================

--- 检查玩家是否处于封禁状态
--- 如果封禁已过期则自动解封并标脏
---@param uid number
---@return boolean isBanned
---@return table|nil banInfo  封禁详情（仅 banned=true 时有效）
function BanService.CheckBan(uid)
    local gp = PDM.GetModule(uid, "global_profile")
    if not gp or not gp.banInfo then
        return false, nil
    end

    local info = gp.banInfo
    if not info.banned then
        return false, nil
    end

    -- 检查是否已过期（banExpireTime > 0 表示限时封禁）
    if info.banExpireTime > 0 and info.banExpireTime <= os.time() then
        -- 已过期，自动解封
        info.banned = false
        PDM.MarkDirty(uid, "global_profile")
        print("[BanService] auto-unban uid=" .. tostring(uid) .. " (expired)")
        return false, nil
    end

    return true, info
end

-- ======================== 封禁玩家 ========================

--- 封禁指定玩家
---@param targetUid number     目标玩家 UID
---@param duration number      封禁时长（秒），0 = 永久
---@param reason string        封禁原因
---@param operatorUid number   操作者 UID
---@return boolean ok
---@return string|nil errMsg
function BanService.BanPlayer(targetUid, duration, reason, operatorUid)
    if not targetUid then
        return false, "缺少 targetUid"
    end

    -- 检查玩家数据是否已加载
    if not PDM.IsLoaded(targetUid) then
        return false, "目标玩家数据未加载（不在线）"
    end

    -- 禁止封禁 GM
    local GMHandler = require("server.gm.GMHandler")
    if GMHandler.IsGM(targetUid) then
        return false, "不能封禁 GM 管理员"
    end

    local gp = PDM.GetModule(targetUid, "global_profile")
    if not gp then
        return false, "无法获取玩家 global_profile"
    end

    -- 初始化 banInfo（兼容旧数据）
    if not gp.banInfo then
        gp.banInfo = {}
    end

    local now = os.time()
    local expireTime = 0  -- 永久
    if duration and duration > 0 then
        expireTime = now + duration
    end

    gp.banInfo.banned        = true
    gp.banInfo.banExpireTime = expireTime
    gp.banInfo.banReason     = reason or "违规操作"
    gp.banInfo.bannedBy      = operatorUid or 0
    gp.banInfo.bannedAt      = now

    PDM.MarkDirty(targetUid, "global_profile")

    print(string.format("[BanService] BanPlayer uid=%d duration=%s reason=%s by=%d",
        targetUid,
        duration == 0 and "永久" or tostring(duration) .. "s",
        tostring(reason),
        operatorUid or 0))

    return true
end

-- ======================== 解封玩家 ========================

--- 解封指定玩家
---@param targetUid number     目标玩家 UID
---@return boolean ok
---@return string|nil errMsg
function BanService.UnbanPlayer(targetUid)
    if not targetUid then
        return false, "缺少 targetUid"
    end

    if not PDM.IsLoaded(targetUid) then
        return false, "目标玩家数据未加载（不在线）"
    end

    local gp = PDM.GetModule(targetUid, "global_profile")
    if not gp then
        return false, "无法获取玩家 global_profile"
    end

    if not gp.banInfo or not gp.banInfo.banned then
        return false, "该玩家未被封禁"
    end

    gp.banInfo.banned = false
    PDM.MarkDirty(targetUid, "global_profile")

    print("[BanService] UnbanPlayer uid=" .. tostring(targetUid))
    return true
end

-- ======================== 查询封禁信息 ========================

--- 获取玩家封禁详情（不触发自动解封）
---@param targetUid number
---@return table|nil banInfo
function BanService.GetBanInfo(targetUid)
    if not PDM.IsLoaded(targetUid) then
        return nil
    end

    local gp = PDM.GetModule(targetUid, "global_profile")
    if not gp or not gp.banInfo then
        return nil
    end

    return gp.banInfo
end

return BanService
