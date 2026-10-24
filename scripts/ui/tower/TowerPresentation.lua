-- 通天塔纯展示适配：只返回显示串/图标主题，不反写 choice、配置、存档或随机状态。
local I18n = require("core.I18n")
local TowerText = require("core.I18nTower")
local M = {}

---@class TowerPresentationChoice
---@field id number|string|nil
---@field name string|nil
---@field desc string|nil
---@field classReq string|nil

-- 稳定业务 ID → 暗契展示名；与统计/奖励/战斗使用的原 ID、原名保持分离。
---@type string[]
local names = {
    "墓铁磨刃", "幽典涌魔", "余烬续命", "夜巡之眼", "断命刃", "墓影步",
    "锁链连斩", "饮血续命", "夜袭先手", "裂甲尖锋", "濒死狂焰", "盛命凶怒",
    "濒死铁幕", "开战血锋", "墓铁坚壁", "斩魂血潮", "拾魂凝命", "连斩黑潮",
    "终命审判", "奔雷夜刃", "冥霜封域", "战祸催燃", "亡者遗誓", "封门怨誓",
    "不屈墓盾", "血骸狂战", "残命战魂", "裂隙蓄爆", "幽典蓄魔", "夜眼连射",
    "墓阵援射", "换面暗刃", "虚面避祸", "烬灯赐祷", "余烬命契",
}

-- 图标用实体主题，不按显示名猜测机制；字符串用于资产/几何绘制器选择。
---@type string[]
local icons = {
    "blade", "tome", "blood", "eye", "blade", "eye",
    "chain", "blood", "blade", "blade", "blood", "blood",
    "shield", "blade", "shield", "blade", "blood", "chain",
    "blade", "blade", "tome", "bell", "bell", "shield",
    "shield", "blood", "blade", "tome", "tome", "eye",
    "eye", "blade", "eye", "bell", "bell",
}
local classIcons = {
    knight = "shield", warrior = "blade", mage = "tome",
    ranger = "eye", assassin = "blade", priest = "bell",
}
---@type string[]
local rarities = { "普通", "优质", "稀有" }
-- 对应 TowerConfig 的 1=白、2=绿、3=蓝；每次返回独立颜色，避免控件反写共享表。
---@type number[][]
local rarityColors = { { 231, 231, 231, 255 }, { 106, 190, 115, 255 }, { 100, 161, 226, 255 } }

---@param choice TowerPresentationChoice|nil
---@return number|nil
local function choiceId(choice)
    return choice and tonumber(choice.id) or nil
end

--- 每次查询读取当前语言；调用方将语言纳入自己的 UI 缓存版本。
---@param source string
---@param ... any
---@return string
function M.text(source, ...)
    local translated = TowerText.lookup(source, I18n.get())
    -- 描述含字面百分号，不带参数时绝不交给 string.format 解释。
    if select("#", ...) == 0 then return translated end
    return string.format(translated, ...)
end

---@param source string
---@param ... any
---@return string
function M.format(source, ...)
    return M.text(source, ...)
end

---@param choice TowerPresentationChoice|nil
---@return string
function M.name(choice)
    local id = choiceId(choice)
    local source = (id and names[id]) or (choice and choice.name) or "暗契"
    return M.text(source)
end

--- 翻译传入完整原描述；不按 ID 拼新效果，也不覆盖业务描述。
---@param choice TowerPresentationChoice|nil
---@return string
function M.description(choice)
    return M.text((choice and choice.desc) or "")
end

--- 1..3 是配置真实品质索引；仅改展示标签，不改抽取权重或暗契名。
---@param quality number|nil
---@return string
function M.quality(quality)
    return M.rarity(quality)
end

---@param quality number|nil
---@return string
function M.rarity(quality)
    return M.text((quality and rarities[quality]) or "")
end

---@param quality number|nil
---@return number[]
function M.rarityColor(quality)
    local color = (quality and rarityColors[quality]) or rarityColors[1]
    return { color[1], color[2], color[3], color[4] }
end

---@param choice TowerPresentationChoice|nil
---@return string
function M.icon(choice)
    local id = choiceId(choice)
    return (id and icons[id]) or (choice and classIcons[choice.classReq or ""]) or "chain"
end

return M
