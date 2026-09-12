-- ============================================================================
-- AvatarFrameUtil - 头像框资源预加载与句柄查询
-- ============================================================================

local AvatarFrameConfig = require("config.AvatarFrameConfig")

local AvatarFrameUtil = {}

--- 预加载全部头像框到 cache[frameId]
---@param vg any
---@param cache table<number, number>
function AvatarFrameUtil.preloadFrames(vg, cache)
    for _, frameId in ipairs(AvatarFrameConfig.getAllIds()) do
        if not cache[frameId] or cache[frameId] < 0 then
            local img = nvgCreateImage(vg, AvatarFrameConfig.getIconPath(frameId), 0)
            if img >= 0 then
                cache[frameId] = img
            end
        end
    end
end

---@param cache table<number, number>
---@param frameId number|nil
---@return number
function AvatarFrameUtil.getIconHandle(cache, frameId)
    frameId = tonumber(frameId) or 1
    local handle = cache and cache[frameId]
    if handle and handle >= 0 then
        return handle
    end
    local fallback = cache and cache[1]
    if fallback and fallback >= 0 then
        return fallback
    end
    return -1
end

return AvatarFrameUtil
