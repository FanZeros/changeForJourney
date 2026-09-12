-- SlotEnhanceSchema.lua — slotEnhance 模块 Schema
-- 槽位强化等级

local SlotEnhanceSchema = {}

SlotEnhanceSchema.Fields = {
    slotEnhance = {
        pdmKey     = "ModSlotEnhance",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_slot_enhance" },
        getDefault = function()
            return {
                -- levels[partySlot][equipSlot] = enhanceLevel
                -- partySlot: 1~5（出战槽位索引）
                -- equipSlot: "weapon"/"offhand"/"armor"/"accessory"
                -- enhanceLevel: 0~100
                levels = {},
            }
        end,
        onLoad = function(data)
            if not data.levels then data.levels = {} end
            -- cjson 反序列化后数字 key 变字符串，统一转为数字 key
            local fixed = {}
            for k, slots in pairs(data.levels) do
                local numK = tonumber(k)
                if numK then
                    fixed[numK] = slots
                end
            end
            data.levels = fixed
        end,
        desc = "槽位强化等级",
    },
}

return SlotEnhanceSchema
