--- ImageCache: 共享 NanoVG 图片缓存（装备图标 LRU + 品质背景共享）
--- 解决多个 UI 模块各自维护独立缓存导致 VRAM 无限累积的问题。
--- 装备图标采用 FIFO 淘汰策略，超过上限时自动 nvgDeleteImage 释放最早的纹理。

local EquipmentConfig = require("config.EquipmentConfig")

local ImageCache = {}

-- ======================== 配置 ========================

local MAX_EQUIP_ICONS = 200  -- 装备图标缓存上限（覆盖全部198种模板，避免FIFO抖动）

-- ======================== 内部状态 ========================

local vg_ = nil

-- 装备图标: FIFO 淘汰
local equipCache = {}         -- [templateId] = handle
local equipFifo  = {}         -- 按插入顺序排列的 templateId 列表

-- 品质背景框: 有限集合（1-6），无需淘汰
local qualityBgCache = {}     -- [quality] = handle

-- 神器类型图标: 有限集合（1-16），无需淘汰
local artifactIconCache = {}  -- [typeId] = handle

-- ======================== Public API ========================

--- 初始化（传入 NanoVG 上下文，只需调用一次）
---@param vg any NanoVG 上下文
function ImageCache.init(vg)
    vg_ = vg
end

--- 获取装备图标（共享 + LRU 淘汰）
---@param templateId string 模板 ID（如 "W1"）
---@return number nvgImage handle (-1 if failed)
function ImageCache.getEquipIcon(templateId)
    if not templateId then return -1 end

    -- 命中缓存
    local cached = equipCache[templateId]
    if cached then return cached end

    -- 未命中，创建新纹理
    if not vg_ then return -1 end
    local path = EquipmentConfig.getIconPath(templateId)
    local handle = nvgCreateImage(vg_, path, 0)
    if handle < 0 then
        equipCache[templateId] = -1  -- 缓存失败结果，避免每帧重试
        return -1
    end

    -- 存入缓存
    equipCache[templateId] = handle
    table.insert(equipFifo, templateId)

    -- 超过上限，淘汰最早的
    while #equipFifo > MAX_EQUIP_ICONS do
        local evictId = table.remove(equipFifo, 1)
        local evictHandle = equipCache[evictId]
        if evictHandle and evictHandle >= 0 then
            nvgDeleteImage(vg_, evictHandle)
        end
        equipCache[evictId] = nil
    end

    return handle
end

--- 获取神器类型图标（共享，有限集合无需淘汰）
---@param artifactTypeId number 神器类型 ID（1-16）
---@return number nvgImage handle (-1 if failed)
function ImageCache.getArtifactIcon(artifactTypeId)
    local id = tonumber(artifactTypeId) or 0
    if id <= 0 then return -1 end

    local cached = artifactIconCache[id]
    if cached then return cached end

    if not vg_ then return -1 end
    local path = "image/神器图标/UI_icon_SQ_A" .. id .. ".png"
    local handle = nvgCreateImage(vg_, path, 0)
    artifactIconCache[id] = handle
    return handle
end

--- 获取品质背景框（共享，有限集合无需淘汰）
---@param quality number 品质等级（1-6）
---@return number nvgImage handle (-1 if failed)
function ImageCache.getQualityBg(quality)
    if not quality then return -1 end

    local cached = qualityBgCache[quality]
    if cached then return cached end

    if not vg_ then return -1 end
    local path = EquipmentConfig.getQualityBgPath(quality)
    local handle = nvgCreateImage(vg_, path, 0)
    qualityBgCache[quality] = handle
    return handle
end

--- 获取当前缓存统计（调试用）
---@return number equipCount 装备图标缓存数量
---@return number qualityCount 品质背景缓存数量
function ImageCache.getStats()
    return #equipFifo, 0
end

return ImageCache
