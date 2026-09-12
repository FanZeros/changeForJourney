-- ============================================================================
-- AvatarFrameBridge - 头像框收藏属性桥接
-- 解锁状态由调用方显式传入，避免玩家与竞技场对手数据串用。
-- ============================================================================

local AvatarFrameConfig = require("config.AvatarFrameConfig")

local AvatarFrameBridge = {}

AvatarFrameBridge.MODIFIER_ID = "avatar_frame_collection"

---@param unlockedAvatarFrames table|nil
---@return table[] entries
function AvatarFrameBridge.getEntries(unlockedAvatarFrames)
    local totals = AvatarFrameConfig.aggregateUnlockedAttributes(unlockedAvatarFrames)
    local entries = {}
    for key, value in pairs(totals) do
        if value ~= 0 then
            entries[#entries + 1] = { key = key, flat = value }
        end
    end
    table.sort(entries, function(a, b)
        return a.key < b.key
    end)
    return entries
end

---@param attrs table|nil UnitAttributes 实例
---@param unlockedAvatarFrames table|nil
---@return table[] entries
function AvatarFrameBridge.applyToUnit(attrs, unlockedAvatarFrames)
    if not attrs or not attrs.addModifier then return {} end

    if attrs.removeModifier then
        attrs:removeModifier(AvatarFrameBridge.MODIFIER_ID)
    end

    local entries = AvatarFrameBridge.getEntries(unlockedAvatarFrames)
    if #entries > 0 then
        attrs:addModifier(AvatarFrameBridge.MODIFIER_ID, entries)
    end
    return entries
end

return AvatarFrameBridge
