-- RelicSchema.lua — relic 模块 Schema
-- 遗物背包与宫格

local RelicSchema = {}

--- 将 bag/grid 归一化为连续数组，并修正遗物字段类型（cjson 反序列化后 key/id 类型可能不一致）
---@param list table|nil
---@return table
local function normalizeRelicList(list)
    if type(list) ~= "table" then return {} end
    local dense = {}
    for _, r in pairs(list) do
        if type(r) == "table" and r.id ~= nil then
            r.id = tostring(r.id)
            if r.type then r.type = tonumber(r.type) end
            if r.quality then r.quality = tonumber(r.quality) end
            if r.affixId then r.affixId = tonumber(r.affixId) end
            if r.level then r.level = tonumber(r.level) end
            if r.pendingReforgeAffixId ~= nil then
                r.pendingReforgeAffixId = tonumber(r.pendingReforgeAffixId)
            end
            if r.row then r.row = tonumber(r.row) end
            if r.col then r.col = tonumber(r.col) end
            if r.rotation then r.rotation = tonumber(r.rotation) end
            -- locked 仅持久化 true；false/0/"true" 等一律归一为 nil/false
            if r.locked == true then
                r.locked = true
            else
                r.locked = nil
            end
            dense[#dense + 1] = r
        end
    end
    return dense
end

--- 对 mod_relics 模块执行完整归一化（服务端 onLoad + 客户端推送后修正）
---@param data table
function RelicSchema.normalizeModule(data)
    if type(data) ~= "table" then return end
    if not data.bag          then data.bag          = {} end
    if not data.grid         then data.grid         = {} end
    if not data.nextId       then data.nextId       = 1 end
    if not data.mergeCount   then data.mergeCount   = 0 end
    if not data.reforgeCount then data.reforgeCount = 0 end
    data.nextId = math.floor(tonumber(data.nextId) or 1)
    data.bag = normalizeRelicList(data.bag)
    data.grid = normalizeRelicList(data.grid)
end

RelicSchema.Fields = {
    mod_relics = {
        pdmKey     = "ModRelics",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_relics" },
        getDefault = function()
            return {
                bag          = {},
                grid         = {},
                nextId       = 1,
                mergeCount   = 0,
                reforgeCount = 0,
            }
        end,
        onLoad = function(data)
            RelicSchema.normalizeModule(data)
        end,
    },
}

return RelicSchema
