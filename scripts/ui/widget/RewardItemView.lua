-- 奖励物品的统一图标、名称与数量展示；仅消费展示回执，不访问玩家库存。
local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")
local ImageCache = require("ui.widget.ImageCache")
local HeroFrame = require("ui.widget.HeroFrame")
local HeroConfig = require("config.HeroConfig")
local EquipmentConfig = require("config.EquipmentConfig")
local ResourceDefs = require("config.ResourceDefs")
local ArtifactAssetUtil = require("config.ArtifactAssetUtil")
local NumberUtil = require("core.NumberUtil")
local M = {}

function M.name(item)
    if item.name and item.name ~= "" then return item.name end
    if item.type == "equip" then
        local def = EquipmentConfig.ITEMS[item.templateId]
        return def and def.name or tostring(item.templateId or "装备")
    end
    if item.type == "hero" then
        local def = HeroConfig.get(tonumber(item.heroId) or 0)
        return def and def.name or "英雄"
    end
    if item.type == "seed" then return "待鉴定装备" end
    if item.type == "artifact" then
        return require("shared.artifact.ArtifactDefs").getName(item)
    end
    return ResourceDefs.getRewardDisplayName(item)
end

function M.quantity(item, exact)
    local amount = tonumber(item.amount) or 1
    return "×" .. (exact and tostring(amount) or NumberUtil.format(amount))
end

local function badge(vg, text, x, y)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 40)
    local width = nvgTextBounds(vg, 0, 0, text) or 0
    local font = width > 140 and math.max(24, 40 * 140 / width) or 40
    DrawUtil.drawTextStroke(vg, x, y, text, font, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM,
        255, 255, 255, 4)
end

-- getResourceIcon/getHeroIcon 由宿主缓存提供；尺寸缩放与图标角标共用同一变换。
function M.draw(vg, item, cx, cy, size, getResourceIcon, getHeroIcon)
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgScale(vg, size / 160, size / 160)
    local q = item.quality or 1
    if item.type == "hero" or (item.type == "shard" and item.heroId) then
        local heroId = tonumber(item.heroId) or 0
        local def = HeroConfig.get(heroId)
        local inner = item.type == "shard" and 148 or 136
        HeroFrame.draw(vg, { cx = 0, cy = 0, size = inner, heroId = heroId,
            iconHandle = getHeroIcon(heroId), quality = item.quality or (def and def.quality) or 3, state = "owned" })
        if item.type == "shard" and DrawUtil._shardBadgeImg and DrawUtil._shardBadgeImg >= 0 then
            local b = math.floor(inner * 53 / 160 + 0.5)
            DrawUtil.drawImageCentered(vg, DrawUtil._shardBadgeImg, -inner * 0.5 + b * 0.5,
                -inner * 0.5 + b * 0.5, b, b, 1)
        end
        if item.type == "hero" and item.name then badge(vg, item.name, 72, 72)
        elseif item.amount then badge(vg, M.quantity(item), 72, 72) end
    elseif item.type == "artifact" then
        -- 神器原生绘制负责品质框与图标，回执字段完整保留。
        ArtifactAssetUtil.drawIcon(vg, item, 0, 0, 160, {})
    else
        local def = ResourceDefs.DEFS[item.type]
        if def then q = def.quality or q end
        local bg = ImageCache.getQualityBg(q)
        if bg >= 0 then DrawUtil.drawImageCentered(vg, bg, 0, 0, 160, 160, 1) end
        local img = -1
        if item.type == "equip" then img = ImageCache.getEquipIcon(item.templateId)
        elseif item.type ~= "seed" then img = getResourceIcon(item.type) end
        if img >= 0 then
            if item.type == "equip" then DarkIcon.drawIconDark(vg, img, 0, 0, 136, 136, 1)
            else DrawUtil.drawImageCentered(vg, img, 0, 0, 136, 136, 1) end
        else
            local trim = DarkIcon.QUALITY_TRIM[q] or DarkIcon.QUALITY_TRIM[1]
            DrawUtil.drawTextStroke(vg, 0, 0, "?", 80, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                trim[1], trim[2], trim[3], 3)
        end
        if item.type == "equip" then
            if item.destination == "lootbox" then
                DrawUtil.drawTextStroke(vg, 0, -62, "已入遗匣", 27,
                    NVG_ALIGN_CENTER + NVG_ALIGN_TOP, 230, 198, 125, 3)
            end
            if item.level and item.level > 0 then badge(vg, "Lv." .. tostring(item.level), 72, 72) end
        elseif item.amount and item.amount > 0 then badge(vg, M.quantity(item), 72, 72) end
    end
    nvgRestore(vg)
end

return M
