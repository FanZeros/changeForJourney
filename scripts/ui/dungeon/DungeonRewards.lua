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
    -- 仅展示规则层已经同事务入账的自动分解精粹，绝不在UI再次发奖。
    if (data.autoDecomposeEssence or 0) > 0 then
        rewards[#rewards + 1] = { type = "essence", amount = data.autoDecomposeEssence }
    end
    for _, item in ipairs(data.equips or {}) do
        -- 回执含完整装备及 destination，RewardPopup 可按原实例展示遗匣去向。
        if item.type == "equipbatch" then
            -- 大批掉落按品质聚合：只展示数量，不在界面层再生成装备。
            local reward = {}
            for key, value in pairs(item) do reward[key] = value end
            reward.type = "equipbatch"
            reward.amount = item.amount or item.count or 0
            reward.iconPath = item.iconPath or CHEST_ICON
            rewards[#rewards + 1] = reward
        else
            local reward = {}
            for key, value in pairs(item) do reward[key] = value end
            reward.type = "equip"
            reward.amount = 1
            reward.iconPath = item.iconPath or (item.templateId and EquipmentConfig.getIconPath(item.templateId)) or CHEST_ICON
            rewards[#rewards + 1] = reward
        end
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

local DungeonIdleConfig = require("config.DungeonIdleConfig")

-- 每个页面实例自己的请求槽；关闭即释放，不让迟到回执清新页面的pending。
function M.newSweepIdentity()
    local sequence, active = 0, nil ---@type integer, table?
    return {
        clear = function() active = nil end,
        isPending = function() return active ~= nil end,
        send = function(params, send)
            if active then return false end
            sequence = sequence + 1
            params.sweepRequestId = "dungeon-sweep:" .. tostring(sequence)
            local request = { id = params.sweepRequestId, dungeonId = params.dungeonId,
                teamIdx = params.teamIdx, floor = params.floor }
            active = request
            local called, accepted = pcall(send, params)
            if not called or accepted == false then
                if active == request then active = nil end
                return false
            end
            return true
        end,
        consume = function(data)
            local request = active
            if not request or data.sweepRequestId ~= request.id or data.dungeonId ~= request.dungeonId
                or (data.teamIdx ~= nil and data.teamIdx ~= request.teamIdx)
                or (data.sweepFloor ~= nil and data.sweepFloor ~= request.floor) then return false end
            active = nil
            return true
        end,
    }
end

function M.idleClaimPreview(dungeonId, dungeon)
    local sub = dungeon and dungeon[dungeonId]
    if not sub then return 0, 0 end
    local idleFloor = DungeonIdleConfig.getIdleFloorFromSub(sub, dungeonId)
    local accumSec = sub.idleAccumSec or 0
    return DungeonIdleConfig.calcReward(dungeonId, idleFloor, accumSec, sub.idleConsumedSec), accumSec
end

function M.idleMaxHourText()
    return tostring(math.floor((DungeonIdleConfig.FULL_RATE_SEC or 0) / 3600 + 0.5)) .. "h"
end

function M.formatIdleDuration(sec)
    sec = math.floor(tonumber(sec) or 0)
    local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
    if h > 0 then return string.format("%d:%02d", h, m) end
    return tostring(m) .. "分"
end

return M
