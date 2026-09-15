-- ProfileSchema.lua — global_profile 模块 Schema
-- 跨服共享的玩家档案（已创角区服列表、上次登录区服等）

local ProfileSchema = {}

ProfileSchema.Fields = {
    global_profile = {
        pdmKey     = "ModGlobalProfile",
        type       = "json",
        scope      = "global",
        persist    = { via = "cloud", cloudKey = "global_profile" },
        getDefault = function()
            return {
                servers      = {},
                lastServerId = 0,
                createTime   = 0,
                pendingPrivilegeCardTransfer     = 0, -- 1=特权卡待转入下一进入的区服
                pendingPrivilegeCardTransferFrom = 0, -- 转出源区服 ID（避免重进同服重复发放）
                banInfo      = {
                    banned        = false,
                    banExpireTime = 0,
                    banReason     = "",
                    bannedBy      = 0,
                    bannedAt      = 0,
                },
            }
        end,
        onLoad = function(data)
            if not data.servers then data.servers = {} end
            data.lastServerId = tonumber(data.lastServerId) or 0
            data.createTime   = tonumber(data.createTime) or 0
            if data.pendingPrivilegeCardTransfer == nil then data.pendingPrivilegeCardTransfer = 0 end
            data.pendingPrivilegeCardTransfer = math.floor(tonumber(data.pendingPrivilegeCardTransfer) or 0)
            if data.pendingPrivilegeCardTransferFrom == nil then data.pendingPrivilegeCardTransferFrom = 0 end
            data.pendingPrivilegeCardTransferFrom = math.floor(tonumber(data.pendingPrivilegeCardTransferFrom) or 0)

            local fixedServers = {}
            for k, v in pairs(data.servers) do
                fixedServers[tostring(k)] = v
            end
            data.servers = fixedServers

            if not data.serverProgress then data.serverProgress = {} end
            local fixedProgress = {}
            for k, v in pairs(data.serverProgress) do
                fixedProgress[tostring(k)] = v
            end
            data.serverProgress = fixedProgress

            -- banInfo 兼容旧数据
            if not data.banInfo then
                data.banInfo = {
                    banned        = false,
                    banExpireTime = 0,
                    banReason     = "",
                    bannedBy      = 0,
                    bannedAt      = 0,
                }
            else
                data.banInfo.banned        = data.banInfo.banned or false
                data.banInfo.banExpireTime = tonumber(data.banInfo.banExpireTime) or 0
                data.banInfo.banReason     = data.banInfo.banReason or ""
                data.banInfo.bannedBy      = tonumber(data.banInfo.bannedBy) or 0
                data.banInfo.bannedAt      = tonumber(data.banInfo.bannedAt) or 0
            end
        end,
        desc = "跨服共享的玩家档案",
    },
}

return ProfileSchema
