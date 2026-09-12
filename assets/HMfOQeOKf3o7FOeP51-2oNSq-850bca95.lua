-- ============================================================================
-- HeroAssetUtil - 角色美术资产路径与预加载 ID 列表
-- 职责: 统一管理角色图标/卡牌/立绘资源路径，以及需预加载的角色 ID
-- ============================================================================

local HC = require("config.HeroConfig")

local HeroAssetUtil = {}

--- 预留：HeroConfig 未收录但已有美术资产的角色 ID（当前无）
HeroAssetUtil.EXTRA_ASSET_IDS = {}

---@param heroId number
---@return string
function HeroAssetUtil.getIconPath(heroId)
    return "image/角色图标/UI_icon_hero_" .. heroId .. ".png"
end

---@param heroId number
---@return string
function HeroAssetUtil.getCardPath(heroId)
    return "image/角色卡牌/KP_YX_" .. heroId .. ".png"
end

---@param heroId number
---@return string
function HeroAssetUtil.getPortraitPath(heroId)
    return string.format("image/角色立绘/UI_DLH_%d.png", heroId)
end

--- 获取所有需预加载/可引用的角色资产 ID（HeroConfig + 额外美术）
---@return number[]
function HeroAssetUtil.getAssetIds()
    local seen = {}
    local ids = {}
    local function add(id)
        if id and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    for _, id in ipairs(HC.getAllIds()) do
        add(id)
    end
    for _, id in ipairs(HeroAssetUtil.EXTRA_ASSET_IDS) do
        add(id)
    end
    table.sort(ids)
    return ids
end

---@return number
function HeroAssetUtil.getMaxAssetId()
    local ids = HeroAssetUtil.getAssetIds()
    return ids[#ids] or 15
end

--- 预加载角色头像到 cache 表（就地写入 cache[heroId]）
---@param vg any
---@param cache table<number, number>
function HeroAssetUtil.preloadIcons(vg, cache)
    for _, id in ipairs(HeroAssetUtil.getAssetIds()) do
        if not cache[id] or cache[id] < 0 then
            local img = nvgCreateImage(vg, HeroAssetUtil.getIconPath(id), 0)
            if img >= 0 then
                cache[id] = img
            end
        end
    end
end

--- 预加载角色卡牌到 cache 表（就地写入 cache[heroId]）
---@param vg any
---@param cache table<number, number>
function HeroAssetUtil.preloadCards(vg, cache)
    for _, id in ipairs(HeroAssetUtil.getAssetIds()) do
        if not cache[id] or cache[id] < 0 then
            local img = nvgCreateImage(vg, HeroAssetUtil.getCardPath(id), 0)
            if img >= 0 then
                cache[id] = img
            end
        end
    end
end

return HeroAssetUtil
