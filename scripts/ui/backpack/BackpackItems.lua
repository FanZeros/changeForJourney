-- 背包道具目录：展示信息来自资源注册表，余额与来源由背包读取。
local GameState = require("core.GameState")
local ResourceDefs = require("config.ResourceDefs")

---@type [string, string, string, fun(): any][]
local sources = {
    { "gold", "gold", "击杀/通关/任务", GameState.getGold },
    { "gems", "diamond", "成就/首通/活动", GameState.getGems },
    { "essence", "essence", "分解装备获得", GameState.getEssence },
    { "enhanceStone", "enhance_star", "市场购买/任务", GameState.getEnhanceStone },
    { "destroyStone", "break_protect", "市场购买/任务", GameState.getDestroyStone },
    { "weaponScroll", "weapon_scroll", "击杀/通关/任务", GameState.getWeaponScroll },
    { "offhandScroll", "offhand_scroll", "击杀/通关/任务", GameState.getOffhandScroll },
    { "armorScroll", "armor_scroll", "击杀/通关/任务", GameState.getArmorScroll },
    { "accessoryScroll", "accessory_scroll", "击杀/通关/任务", GameState.getAccessoryScroll },
    { "helmetScroll", "helmet_scroll", "击杀/通关/任务", GameState.getHelmetScroll },
    { "shoesScroll", "shoes_scroll", "击杀/通关/任务", GameState.getShoesScroll },
    { "recruitTicket", "adventure_ticket", "市场/活动/福利", GameState.getRecruitTicket },
    { "stellarRecruitTicket", "stellar_ticket", "活动/福利", GameState.getStellarRecruitTicket },
    { "goldenKey", "golden_key", "首通奖励/市场购买", GameState.getGoldenKey },
    { "sweepTicket", "sweep_ticket", "活动获得/看广告获得", GameState.getSweepTicket },
    { "tavernCoin", "tavern_coin", "非UR满觉醒碎片分解", GameState.getTavernCoin },
    { "arcaneDust", "arcane_dust", "关卡首通/任务/市场", GameState.getArcaneDust },
    { "corruptStone", "corrupt_stone", "关卡首通/活动/市场", GameState.getCorruptStone },
    { "sacredStone", "sacred_stone", "关卡首通/活动/市场", GameState.getSacredStone },
    { "speedCard", "speed_card", "市场购买获得", GameState.getSpeedCardDisplayCount },
}

---@class BackpackItemDef
---@field key string
---@field iconPath string
---@field quality number
---@field name string
---@field source string
---@field desc string
---@field getter fun(): any
---@field amountTextGetter? fun(): string
---@field detailAmountTextGetter? fun(): string
---@field descGetter? fun(): string

---@type BackpackItemDef[]
local items = {}
for _, source in ipairs(sources) do
    local registered = ResourceDefs.DEFS[source[2]]
    local getter = source[4]
    items[#items + 1] = {
        key = source[1], iconPath = registered.iconPath,
        quality = tonumber(registered.quality) or 1, name = registered.name or source[1],
        source = source[3], desc = registered.desc or "",
        getter = function() return getter() end,
    }
end
local speedCard = items[#items]
speedCard.amountTextGetter = function() return GameState.formatSpeedCardRemain() end
speedCard.detailAmountTextGetter = function() return "剩余:" .. GameState.formatSpeedCardRemain() end
speedCard.descGetter = function()
    return "提升20%在线挂机收益，包括金币/经验/装备等；当前剩余时间：" .. GameState.formatSpeedCardRemain()
end

return items
