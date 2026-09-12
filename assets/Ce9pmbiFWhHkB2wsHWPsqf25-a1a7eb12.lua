-- HeroesSchema.lua — heroes 模块 Schema
-- 英雄阵容（已拥有英雄、出战阵容）

local HeroesSchema = {}

HeroesSchema.Fields = {
    heroes = {
        pdmKey     = "ModHeroes",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_heroes" },
        getDefault = function()
            return {
                roster   = {},
                deployed = {},
                urShardConvertDayId = 0,
                urShardConvertCount = 0,
            }
        end,
        onLoad = function(data)
            if data.roster then
                local fixed = {}
                for k, v in pairs(data.roster) do
                    local numKey = tonumber(k)
                    if numKey then
                        fixed[numKey] = v
                    else
                        fixed[k] = v
                    end
                end
                data.roster = fixed
            else
                data.roster = {}
            end
            if data.deployed then
                for i, v in ipairs(data.deployed) do
                    local num = tonumber(v)
                    if num then data.deployed[i] = num end
                end
            else
                data.deployed = {}
            end
            data.urShardConvertDayId = math.floor(tonumber(data.urShardConvertDayId) or 0)
            data.urShardConvertCount = math.max(0, math.floor(tonumber(data.urShardConvertCount) or 0))
            if #data.deployed == 0 and data.roster then
                -- [DIAG-HERO] 触发 deployed 为空的回退逻辑
                local rosterAllKeys = {}
                for heroId, hd in pairs(data.roster) do
                    rosterAllKeys[#rosterAllKeys + 1] = tostring(heroId) .. "(lv" .. tostring(hd.level or "nil") .. ")"
                end
                print(string.format("[DIAG-HERO] HeroesSchema.onLoad FALLBACK TRIGGERED: deployed is EMPTY, roster={%s}",
                    table.concat(rosterAllKeys, ",")))

                -- 旧存档兼容：将所有已拥有英雄（level>0）按 heroId 排序填入，上限5
                local owned = {}
                for heroId, hd in pairs(data.roster) do
                    if hd.level and hd.level > 0 then
                        owned[#owned + 1] = tonumber(heroId) or heroId
                    end
                end
                if #owned > 0 then
                    table.sort(owned)
                    for i = 1, math.min(#owned, 5) do
                        data.deployed[i] = owned[i]
                    end
                    print("[DIAG-HERO] HeroesSchema.onLoad: deployed为空但roster有" .. #owned .. "英雄，已自动恢复出战: " .. table.concat(data.deployed, ","))
                else
                    -- roster 中没有 level>0 的英雄，取第一个作为兜底
                    for heroId, _ in pairs(data.roster) do
                        data.deployed[1] = tonumber(heroId) or heroId
                        print("[DIAG-HERO] HeroesSchema.onLoad: deployed为空且无level>0英雄，兜底填充首个: " .. tostring(data.deployed[1]))
                        break
                    end
                end
            end
            for _, heroData in pairs(data.roster or {}) do
                if heroData.advBranch then
                    if heroData.advBranch.first then
                        heroData.advBranch.first = tonumber(heroData.advBranch.first)
                    end
                    if heroData.advBranch.second then
                        heroData.advBranch.second = tonumber(heroData.advBranch.second)
                    end
                end
                if heroData.awakening then
                    local fixedAwk = {}
                    for k, v in pairs(heroData.awakening) do
                        local numK = tonumber(k)
                        if numK then fixedAwk[numK] = v end
                    end
                    heroData.awakening = fixedAwk
                end
                if heroData.dupeCount == nil then
                    local awakeCount = 0
                    if heroData.awakening then
                        for _ in pairs(heroData.awakening) do awakeCount = awakeCount + 1 end
                    end
                    heroData.dupeCount = awakeCount
                end

                -- 碎片字段初始化
                heroData.shards = tonumber(heroData.shards) or 0

                -- MIGRATION: dupeCount → shards 迁移（每 dupeCount = 15 碎片）
                -- 仅对未迁移的存档执行一次：检查 _shardMigrated 标志
                if not heroData._shardMigrated then
                    local dc = heroData.dupeCount or 0
                    -- 已用于觉醒的点数不迁移（它们已经"消费"了）
                    local awakeCount = 0
                    if heroData.awakening then
                        for _ in pairs(heroData.awakening) do awakeCount = awakeCount + 1 end
                    end
                    -- 可迁移的 dupeCount = 总 dupeCount - 已消耗的觉醒数
                    local migratable = dc - awakeCount
                    if migratable > 0 then
                        heroData.shards = heroData.shards + migratable * 15
                    end
                    heroData._shardMigrated = true
                end
            end
        end,
        desc = "英雄阵容",
    },
}

return HeroesSchema
