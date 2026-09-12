-- MailSchema.lua — mail 模块 Schema
-- 邮件系统

local MailSchema = {}

MailSchema.Fields = {
    mail = {
        pdmKey     = "ModMail",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_mail" },
        getDefault = function()
            return {
                claimed = {},
                deleted = {},
                inbox   = {},   -- 动态邮件收件箱: { [dmId] = { id, title, body, rewards, date, ... } }
                nextId  = 1,    -- 动态邮件自增 ID 计数器
                claimedBroadcasts = {},  -- 已领取的全服邮件 ID 集合: { [bmId] = true }
                compensationFlags = {},  -- 一次性补偿标记: { [flagKey] = true }
            }
        end,
        onLoad = function(data)
            if not data.claimed then data.claimed = {} end
            if not data.deleted then data.deleted = {} end
            if not data.inbox   then data.inbox   = {} end
            if not data.nextId  then data.nextId  = 1  end
            if not data.claimedBroadcasts then data.claimedBroadcasts = {} end
            if not data.compensationFlags then data.compensationFlags = {} end
            -- cjson 反序列化会把数字 key 变成字符串 key，但 inbox 使用字符串 key（"dm_1"），无需转换
        end,
        desc = "邮件系统",
    },
}

return MailSchema
