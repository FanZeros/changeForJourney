-- EquipmentSchema.lua — equipment 模块 Schema
-- 装备背包与穿戴

local EquipmentSystem = require("systems.EquipmentSystem")

local EquipmentSchema = {}

EquipmentSchema.Fields = {
    equipment = {
        pdmKey     = "ModEquipment",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_equipment" },
        getDefault = function()
            return {
                inventory = {},
                equipped  = {},
                nextSeq   = 1,
                settings  = { autoQuality = 0, autoLevel = 0 },
            }
        end,
        onLoad = function(data)
            if not data.inventory then data.inventory = {} end
            if not data.equipped  then data.equipped  = {} end
            if not data.nextSeq   then data.nextSeq   = 1 end
            if not data.settings  then data.settings  = { autoQuality = 0, autoLevel = 0 } end
            if data.settings.autoQuality == nil then data.settings.autoQuality = 0 end
            if data.settings.autoLevel   == nil then data.settings.autoLevel   = 0 end
            data.nextSeq = math.floor(tonumber(data.nextSeq) or 1)
            local fixedEquipped = {}
            for k, v in pairs(data.equipped) do
                local numKey = tonumber(k)
                if numKey then
                    fixedEquipped[numKey] = v
                else
                    fixedEquipped[k] = v
                end
            end
            for heroId, slots in pairs(fixedEquipped) do
                for slot, seq in pairs(slots) do
                    if not data.inventory[tostring(seq)] and not data.inventory[seq] then
                        slots[slot] = nil
                        print("[equipment.onLoad] removed orphan equipped heroId=" .. tostring(heroId)
                            .. " slot=" .. slot .. " seq=" .. tostring(seq))
                    end
                end
                if next(slots) == nil then
                    fixedEquipped[heroId] = nil
                    print("[equipment.onLoad] removed empty heroId=" .. tostring(heroId))
                end
            end
            data.equipped = fixedEquipped

            -- 水合：从精简存储格式还原可派生字段（name/type/slot/grip, affix key/name）
            EquipmentSystem.hydrateInventory(data.inventory)
        end,
        --- 存储前脱水：去除可派生字段，减少 ~40% 数据体积
        onSave = function(data)
            if not data or not data.inventory then return data end
            local lean = {}
            for k, v in pairs(data) do
                lean[k] = v
            end
            lean.inventory = EquipmentSystem.dehydrateInventory(data.inventory)
            return lean
        end,
        desc = "装备背包与穿戴",
    },
}

return EquipmentSchema
