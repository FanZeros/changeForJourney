-- ============================================================================
-- MarketResults - MarketPage.onActionResult / setMarketData / resetSessionData
-- ============================================================================

local ArtifactDefs = require("shared.artifact.ArtifactDefs")
local PlayerStore = require("client.data.PlayerStore")
local RewardPopup = require("ui.RewardPopup")

local M = {}

function M.bind(deps)
    local state = deps.state
    local Protocol = deps.Protocol
    local COL = deps.COL
    local getShopItemById = deps.getShopItemById
    local getDayId = deps.getDayId
    local SHOP_CONFIG_VERSION = deps.SHOP_CONFIG_VERSION

    local function onActionResult(data)
        if data.action == Protocol.ACTION_TYPES.ARTIFACT_DRAW then
            if data.success then
                local artifactData = PlayerStore.Get("artifacts")
                if artifactData then
                    if data.pityRare ~= nil then artifactData.pityRare = data.pityRare end
                    if data.pityEpic ~= nil then artifactData.pityEpic = data.pityEpic end
                end

                if data.dailyFreeDrawDayId ~= nil then
                    state.artifactFreeDrawDayId = data.dailyFreeDrawDayId
                    local ad = PlayerStore.Get("artifacts")
                    if ad then ad.dailyFreeDrawDayId = data.dailyFreeDrawDayId end
                end
                local rewards = {}
                for _, artifact in ipairs(data.artifacts or {}) do
                    rewards[#rewards + 1] = {
                        type = "artifact",
                        id = artifact.id,
                        artifactId = artifact.artifactId,
                        name = ArtifactDefs.getName(artifact),
                        quality = artifact.quality or 1,
                        value = artifact.value or 0,
                        valueRatio = artifact.valueRatio,
                        threatClearValue = artifact.threatClearValue,
                        threatClearRatio = artifact.threatClearRatio,
                    }
                end
                if #rewards > 0 then
                    RewardPopup.show("神器宝箱", rewards)
                end
                state.floatText = "获得" .. tostring(#rewards) .. "件神器"
            else
                state.floatText = data.reason or "抽取失败"
            end
            state.floatTextX = 540
            state.floatTextY = COL.BTN_Y - 120
            state.floatTextTime = time.elapsedTime
            return
        end

        if data.action ~= Protocol.ACTION_TYPES.MARKET_BUY then return end

        if data.success then
            local itemId = data.itemId
            if itemId and data.purchased then
                -- 用服务端返回的已购次数 + 倒计时起点更新本地状态
                local rec = state.purchased[itemId]
                if not rec then rec = { count = 0, firstBuyTime = 0, dayId = 0 } end
                rec.count = data.purchased
                if data.firstBuyTime then
                    rec.firstBuyTime = data.firstBuyTime
                end
                -- 每日型商品：记录当天 dayId，确保跨天后 getPurchased 能正确重置
                local item = getShopItemById(itemId)
                if item and item.restockType == "daily" then
                    rec.dayId = getDayId()
                end
                state.purchased[itemId] = rec
            end
            print("[MarketPage] 购买成功: itemId=" .. tostring(data.itemId)
                .. " reward=" .. tostring(data.rewardName) .. "x" .. tostring(data.rewardCount)
                .. " purchased=" .. tostring(data.purchased))

            -- 特殊奖励展示：随机卷轴展示实际卷轴；随机遗物展示遗物；加速卡展示生效提示
            local detail = data.rewardDetail
            if detail then
                local shownSpecial = false
                local SCROLL_MAP = {
                    weaponScroll    = "weapon_scroll",
                    offhandScroll   = "offhand_scroll",
                    armorScroll     = "armor_scroll",
                    accessoryScroll = "accessory_scroll",
                }
                if detail.scrolls then
                    -- 新格式：每个独立随机，按类型聚合
                    local rewards = {}
                    for st, n in pairs(detail.scrolls) do
                        local rewardKey = SCROLL_MAP[st]
                        if rewardKey and n > 0 then
                            rewards[#rewards + 1] = { type = rewardKey, amount = n }
                        end
                    end
                    if #rewards > 0 then
                        RewardPopup.show("购买成功", rewards)
                        shownSpecial = true
                    end
                elseif detail.scrollType then
                    -- 兼容旧格式
                    local rewardKey = SCROLL_MAP[detail.scrollType]
                    if rewardKey then
                        RewardPopup.show("购买成功", {
                            { type = rewardKey, amount = detail.amount or 1 },
                        })
                        shownSpecial = true
                    end
                elseif detail.relics then
                    local rewards = {}
                    for _, relic in ipairs(detail.relics) do
                        rewards[#rewards + 1] = { type = "relic", relicType = relic.type or 1, quality = relic.quality or 2 }
                    end
                    if #rewards > 0 then
                        RewardPopup.show("购买成功", rewards)
                        shownSpecial = true
                    end
                elseif detail.speedCardExpireAt then
                    RewardPopup.show("购买成功", { { type = "speed_card", amount = data.rewardCount or 1 } })
                    shownSpecial = true
                end
                data.marketSpecialShown = shownSpecial
            end
        else
            print("[MarketPage] 购买失败: " .. tostring(data.reason))
        end
    end

    local function setMarketData(data)
        if not data then return end

        local incomingVersion = tonumber(data.shopConfigVersion) or 0
        if incomingVersion >= SHOP_CONFIG_VERSION
            and (state.shopConfigVersion or 0) < SHOP_CONFIG_VERSION then
            state.purchased = {}
            print("[MarketPage] shop config version migrated to " .. SHOP_CONFIG_VERSION)
        end
        if incomingVersion > 0 then
            state.shopConfigVersion = incomingVersion
        end

        if data.purchased ~= nil then
            -- 服务端 purchased: { [itemId] = { count, firstBuyTime, dayId } }
            local newPurchased = {}
            for idStr, rec in pairs(data.purchased) do
                local id = tonumber(idStr)
                if id and rec then
                    newPurchased[id] = {
                        count        = rec.count or 0,
                        firstBuyTime = rec.firstBuyTime or 0,
                        dayId        = rec.dayId or 0,
                    }
                end
            end
            state.purchased = newPurchased
            print("[MarketPage] 已同步服务端购买记录")
        end
    end

    local function resetSessionData()
        state.purchased = {}
        state.shopConfigVersion = 0
        state.artifactFreeDrawDayId = 0
        state.dialogOpen = false
        state.dialogItemIdx = nil
        state.keyConfirmVisible = false
        state.keyConfirmClosing = false
        print("[MarketPage] session data reset")
    end

    return {
        onActionResult = onActionResult,
        setMarketData = setMarketData,
        resetSessionData = resetSessionData,
    }
end

return M
