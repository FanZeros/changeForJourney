-- TalentsSchema.lua — talents 模块 Schema
-- 天赋星图

local TalentsSchema = {}

--- 归一化 litNodes：压成连续数组，0 在首位
---@param data table
function TalentsSchema.normalizeModule(data)
    if type(data) ~= "table" then return end
    local dense = {}
    local seen = {}
    local raw = data.litNodes
    if type(raw) == "table" then
        for _, v in pairs(raw) do
            local id = tonumber(v)
            if id ~= nil and not seen[id] and id ~= 0 then
                seen[id] = true
                dense[#dense + 1] = id
            end
        end
    end
    table.sort(dense, function(a, b) return a < b end)
    table.insert(dense, 1, 0)
    data.litNodes = dense
end

TalentsSchema.Fields = {
    talents = {
        pdmKey     = "ModTalents",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_talents" },
        getDefault = function()
            return {
                litNodes = { 0 },
            }
        end,
        onLoad = function(data)
            TalentsSchema.normalizeModule(data)
        end,
        desc = "天赋星图",
    },
}

return TalentsSchema
