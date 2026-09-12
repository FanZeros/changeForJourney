-- ============================================================================
-- AvatarFrameConfig - 头像框配置
-- 素材: assets/image/UI_icon_TXK_1.png ~ UI_icon_TXK_6.png
-- ============================================================================

local C = {}

C.FRAMES = {
    { id = 1, name = "默认", icon = "image/UI_icon_TXK_1.png", defaultUnlocked = true,
      unlockDesc = "获取途径：默认开放", attributes = {}, attributeDesc = "无属性" },
    { id = 2, name = "青铜挑战者", icon = "image/UI_icon_TXK_2.png", defaultUnlocked = false,
      unlockDesc = "获取途径：挑战者区服达成青铜挑战者 II",
      attributes = { { key = "hpBonus", value = 3.5 } }, attributeDesc = "生命加成 +3.5%" },
    { id = 3, name = "白银挑战者", icon = "image/UI_icon_TXK_3.png", defaultUnlocked = false,
      unlockDesc = "获取途径：挑战者区服达成白银挑战者 II",
      attributes = { { key = "armorBonus", value = 3.5 } }, attributeDesc = "护甲加成 +3.5%" },
    { id = 4, name = "黄金挑战者", icon = "image/UI_icon_TXK_4.png", defaultUnlocked = false,
      unlockDesc = "获取途径：挑战者区服达成黄金挑战者 II",
      attributes = {
          { key = "physAtkBonus", value = 1.5 },
          { key = "magAtkBonus", value = 1.5 },
      },
      attributeDesc = "物理/魔法攻击加成 +1.5%" },
    { id = 5, name = "铂金挑战者", icon = "image/UI_icon_TXK_5.png", defaultUnlocked = false,
      unlockDesc = "获取途径：挑战者区服达成铂金挑战者 II",
      attributes = { { key = "critRate", value = 2 } }, attributeDesc = "暴击率 +2%" },
    { id = 6, name = "钻石挑战者", icon = "image/UI_icon_TXK_6.png", defaultUnlocked = false,
      unlockDesc = "获取途径：挑战者区服达成钻石挑战者 II",
      attributes = { { key = "dmgBonus", value = 5 } }, attributeDesc = "伤害加成 +5%" },
}

local byId = {}
for _, frame in ipairs(C.FRAMES) do
    byId[frame.id] = frame
end

---@param frameId number|nil
---@return table|nil
function C.get(frameId)
    return byId[tonumber(frameId)]
end

---@return number[]
function C.getAllIds()
    local ids = {}
    for _, frame in ipairs(C.FRAMES) do
        ids[#ids + 1] = frame.id
    end
    return ids
end

---@param frameId number|nil
---@return string
function C.getIconPath(frameId)
    local cfg = C.get(frameId)
    return (cfg and cfg.icon) or C.FRAMES[1].icon
end

---@param frameId number|nil
---@return boolean
function C.isDefaultUnlocked(frameId)
    local cfg = C.get(frameId)
    return cfg and cfg.defaultUnlocked == true or false
end

---@param unlockedAvatarFrames table|nil
---@return boolean
function C.isUnlocked(frameId, unlockedAvatarFrames)
    if C.isDefaultUnlocked(frameId) then
        return true
    end
    frameId = tonumber(frameId)
    if not frameId or not unlockedAvatarFrames then
        return false
    end
    local value = unlockedAvatarFrames[tostring(frameId)]
        or unlockedAvatarFrames[frameId]
    return value == true or (tonumber(value) or 0) > 0
end

---@param frameId number|nil
---@param unlockedAvatarFrames table|nil
---@return number
function C.getLevel(frameId, unlockedAvatarFrames)
    if C.isDefaultUnlocked(frameId) then
        return 1
    end
    frameId = tonumber(frameId)
    if not frameId or not unlockedAvatarFrames then
        return 0
    end
    local value = unlockedAvatarFrames[tostring(frameId)]
        or unlockedAvatarFrames[frameId]
    if value == true then return 1 end
    return math.min(2, math.max(0, math.floor(tonumber(value) or 0)))
end

---@param frameId number|nil
---@return string
function C.getUnlockDesc(frameId)
    local cfg = C.get(frameId)
    return (cfg and cfg.unlockDesc) or "获取途径：完成对应挑战者档位"
end

---@param frameId number|nil
---@return table[]
function C.getAttributes(frameId)
    local cfg = C.get(frameId)
    return (cfg and cfg.attributes) or {}
end

---@param frameId number|nil
---@return string
function C.getAttributeDesc(frameId)
    local cfg = C.get(frameId)
    return (cfg and cfg.attributeDesc) or "无属性"
end

---@param unlockedAvatarFrames table|nil
---@return table<string, number>
function C.aggregateUnlockedAttributes(unlockedAvatarFrames)
    local totals = {}
    for _, frame in ipairs(C.FRAMES) do
        local level = C.getLevel(frame.id, unlockedAvatarFrames)
        if level > 0 then
            for _, entry in ipairs(frame.attributes or {}) do
                totals[entry.key] = (totals[entry.key] or 0)
                    + (tonumber(entry.value) or 0) * level
            end
        end
    end
    return totals
end

return C
