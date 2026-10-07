-- 只把规则层回执转为展示项；这里绝不生成/交付装备或修改货币。
local M = {}
local EquipmentConfig = require("config.EquipmentConfig")
local CHEST_ICON = "image/货币道具/UI_icon_FBBX.png"

function M.build(data)
    local rewards = {}
    if not data or data.success == false then return rewards end
    for _, kind in ipairs({ "gold", "diamond" }) do
        local amount = data[kind] or 0
        if data.rewardType == kind and data.amount ~= nil then amount = data.amount end
        if amount > 0 then rewards[#rewards + 1] = { type = kind, amount = amount } end
    end
    for _, item in ipairs(data.equips or {}) do
        -- 回执含完整装备及 destination，RewardPopup 可按原实例展示遗匣去向。
        local reward = {}
        for key, value in pairs(item) do reward[key] = value end
        reward.type = "equip"
        reward.amount = 1
        reward.iconPath = item.iconPath or (item.templateId and EquipmentConfig.getIconPath(item.templateId)) or CHEST_ICON
        rewards[#rewards + 1] = reward
    end
    -- 装备副本补发的卷轴/扫荡券：并入同一回执展示。
    local SCROLL_TO_REWARD = {
        weaponScroll = "weapon_scroll", offhandScroll = "offhand_scroll",
        armorScroll = "armor_scroll", accessoryScroll = "accessory_scroll",
        helmetScroll = "helmet_scroll", shoesScroll = "shoes_scroll",
        sweepTicket = "sweep_ticket",
    }
    for field, count in pairs(data.scrollDrops or {}) do
        local amount = math.floor(tonumber(count) or 0)
        if amount > 0 then
            rewards[#rewards + 1] = { type = SCROLL_TO_REWARD[field] or field, amount = amount }
        end
    end
    return rewards
end

function M.overflowText(data)
    local count = data and data.lootboxCount or 0
    if count <= 0 then
        for _, item in ipairs(data and data.equips or {}) do
            if item.destination == "lootbox" then count = count + 1 end
        end
    end
    if count > 0 then return "背包已满，" .. tostring(count) .. "件装备已存入遗匣" end
    return nil
end

function M.rewardLabel(dungeonId)
    if dungeonId == "equipment_vault" then return "装备" end
    if dungeonId == "black_diamond" or dungeonId == "babel_tower" then return "黑晶" end
    return "金币"
end

return M
