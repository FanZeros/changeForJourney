-- ResourceDefs.lua — 资源定义中央注册表（唯一真相源）
-- ============================================================
-- 所有 UI 面板（RewardPopup / MailPanel / BattleResultPanel / OfflineRewardPanel /
-- RecruitAnim / SignInPanel / GMConsolePanel 等）统一 require 此文件，
-- 新增资源只需在此文件添加一行即可全局生效。
-- ============================================================

local ResourceDefs = {}

--- UI 资源定义表
--- key = snake_case type 字符串（与奖励协议 payload 一致）
--- value = { iconPath, quality, name }
ResourceDefs.DEFS = {
    gold              = { iconPath = "image/UI_icon_JB.png",     quality = 2, name = "金币" },
    diamond           = { iconPath = "image/UI_icon_SJ.png",     quality = 5, name = "钻石" },
    essence           = { iconPath = "image/UI_icon_JC.png",     quality = 2, name = "精粹" },
    enhance_star      = { iconPath = "image/UI_icon_QH_1.png",   quality = 3, name = "洗练石" },
    refine_stone      = { iconPath = "image/UI_icon_QH_1.png",   quality = 3, name = "洗练石" },  -- 别名
    degrade_protect   = { iconPath = "image/UI_icon_QH_2.png",   quality = 4, name = "退级保护石" },  -- 已隐藏(seq5)，保留兼容旧邮件/奖励显示
    break_protect     = { iconPath = "image/UI_icon_QH_3.png",   quality = 5, name = "点金石" },
    gold_stone        = { iconPath = "image/UI_icon_QH_3.png",   quality = 5, name = "点金石" },  -- 别名
    weapon_scroll     = { iconPath = "image/UI_icon_JZ_WQ.png",  quality = 3, name = "武器卷轴" },
    offhand_scroll    = { iconPath = "image/UI_icon_JZ_FS.png",  quality = 3, name = "副手卷轴" },
    armor_scroll      = { iconPath = "image/UI_icon_JZ_HJ.png",  quality = 3, name = "护甲卷轴" },
    accessory_scroll  = { iconPath = "image/UI_icon_JZ_SP.png",  quality = 3, name = "饰品卷轴" },
    random_scroll     = { iconPath = "image/UI_icon_JZ_SJ.png",  quality = 3, name = "随机卷轴" },
    adventure_ticket  = { iconPath = "image/UI_icon_ZMQ_1.png",  quality = 5, name = "冒险招募券" },
    stellar_ticket    = { iconPath = "image/UI_icon_ZMQ_2.png",  quality = 6, name = "星辉招募券" },
    sweep_ticket      = { iconPath = "image/UI_icon_SDQ.png",    quality = 4, name = "扫荡券" },
    arena_ticket      = { iconPath = "image/UI_icon_JJCQ.png",   quality = 4, name = "竞技券" },
    arena_coin        = { iconPath = "image/UI_icon_JJB.png",    quality = 3, name = "竞技币" },
    tavern_coin       = { iconPath = "image/UI_icon_JGB.png",    quality = 3, name = "酒馆币" },
    privilege_point   = { iconPath = "image/UI_icon_TQD.png",    quality = 4, name = "特权点" },
    arcane_dust       = { iconPath = "image/UI_icon_ASFC.png",   quality = 3, name = "奥术粉尘" },  -- 序号17
    speed_card        = { iconPath = "image/UI_icon_JSK.png",    quality = 5, name = "加速卡" },    -- 序号18
    privilege_card    = { iconPath = "image/UI_icon_TQK.png",    quality = 6, name = "特权卡" },    -- 序号19
    golden_key        = { iconPath = "image/UI_icon_HJYS.png", quality = 6, name = "黄金钥匙" },
    corrupt_stone     = { iconPath = "image/UI_icon_FHS.png",    quality = 3, name = "腐化石" },
    sacred_stone      = { iconPath = "image/UI_icon_SSS.png",    quality = 6, name = "神圣石" },
    relic             = { iconPath = "image/ICON_SJYW.png",      quality = 4, name = "遗物" },      -- 上古遗迹掉落（随机遗物图标）
}

--- 数字 ID（来自资源配置表序号）→ snake_case type 映射
--- GMConsolePanel / 奖励字符串解析使用
ResourceDefs.ID_TO_TYPE = {
    ["1"]  = "gold",
    ["2"]  = "diamond",
    ["3"]  = "essence",
    ["4"]  = "enhance_star",
    -- 5 已隐藏
    ["6"]  = "break_protect",
    ["7"]  = "adventure_ticket",
    ["8"]  = "sweep_ticket",
    ["9"]  = "arena_ticket",
    ["10"] = "arena_coin",
    ["11"] = "tavern_coin",
    ["12"] = "privilege_point",
    ["13"] = "weapon_scroll",
    ["14"] = "offhand_scroll",
    ["15"] = "armor_scroll",
    ["16"] = "accessory_scroll",
    ["17"] = "arcane_dust",
    ["18"] = "speed_card",
    ["19"] = "privilege_card",
    ["20"] = "stellar_ticket",
    ["21"] = "golden_key",
    ["22"] = "corrupt_stone",
    ["23"] = "sacred_stone",
}

--- 数字 ID → 中文名映射（GM 控制台显示用）
--- 自动从 DEFS + ID_TO_TYPE 生成，无需手动维护
ResourceDefs.REWARD_NAMES = {}
for id, typeKey in pairs(ResourceDefs.ID_TO_TYPE) do
    local def = ResourceDefs.DEFS[typeKey]
    if def and def.name then
        ResourceDefs.REWARD_NAMES[id] = def.name
    end
end
-- 英雄碎片（101-115）单独维护，不走 DEFS
ResourceDefs.REWARD_NAMES["101"] = "大狗嚼碎片"
ResourceDefs.REWARD_NAMES["102"] = "黄桃龙碎片"
ResourceDefs.REWARD_NAMES["103"] = "叮咚鸡碎片"
ResourceDefs.REWARD_NAMES["104"] = "接化发掌门碎片"
ResourceDefs.REWARD_NAMES["105"] = "叠甲怪碎片"
ResourceDefs.REWARD_NAMES["106"] = "阿姨压碎片"
ResourceDefs.REWARD_NAMES["107"] = "信光机兵碎片"
ResourceDefs.REWARD_NAMES["108"] = "愤怒的小雀碎片"
ResourceDefs.REWARD_NAMES["109"] = "卡皮巴拉碎片"
ResourceDefs.REWARD_NAMES["110"] = "铁憨憨碎片"
ResourceDefs.REWARD_NAMES["111"] = "熬夜冠军碎片"
ResourceDefs.REWARD_NAMES["112"] = "雪皇碎片"
ResourceDefs.REWARD_NAMES["113"] = "弹弹弹碎片"
ResourceDefs.REWARD_NAMES["114"] = "内鬼碎片"
ResourceDefs.REWARD_NAMES["115"] = "复活吧爱人碎片"
ResourceDefs.REWARD_NAMES["116"] = "万剑归宗碎片"
ResourceDefs.REWARD_NAMES["121"] = "闪电卖鸡碎片"
ResourceDefs.REWARD_NAMES["122"] = "小黑子碎片"
ResourceDefs.REWARD_NAMES["123"] = "真布诗人碎片"

-- 英文 key → 中文名（兼容旧格式 reward 字符串）
for typeKey, def in pairs(ResourceDefs.DEFS) do
    if def.name then
        ResourceDefs.REWARD_NAMES[typeKey] = def.name
    end
end

--- 英雄碎片奖励编号（GM 邮件/控制台）→ heroId
ResourceDefs.SHARD_ID_TO_HERO = {
    ["101"] = 1,  ["102"] = 2,  ["103"] = 3,
    ["104"] = 4,  ["105"] = 5,  ["106"] = 6,
    ["107"] = 7,  ["108"] = 8,  ["109"] = 9,
    ["110"] = 10, ["111"] = 11, ["112"] = 12,
    ["113"] = 13, ["114"] = 14, ["115"] = 15,
    ["116"] = 16,
    ["121"] = 21, ["122"] = 22, ["123"] = 23,
}

ResourceDefs.HERO_TO_SHARD_ID = {}
for shardId, heroId in pairs(ResourceDefs.SHARD_ID_TO_HERO) do
    ResourceDefs.HERO_TO_SHARD_ID[heroId] = shardId
end

local function resolveShardHeroId(key)
    if not key then return nil end
    key = tostring(key)
    if ResourceDefs.SHARD_ID_TO_HERO[key] then
        return ResourceDefs.SHARD_ID_TO_HERO[key]
    end
    local heroId = key:match("^shard_(%d+)$")
        or key:match("^shard(%d+)$")
        or key:match("^[hH](%d+)$")
        or key:match("^[hH]ero[_-]?(%d+)$")
    if heroId then
        return tonumber(heroId)
    end
    return nil
end

--- 从 reward 条目中解析 heroId（兼容 GM/邮件多种字段名）
---@param r table
---@return number|nil
local function resolveShardHeroIdFromEntry(r)
    if not r then return nil end
    local heroId = tonumber(r.heroId) or tonumber(r.rewardHeroId)
    if heroId then return heroId end

    local keyStr = r.key and tostring(r.key) or nil
    if keyStr then
        heroId = resolveShardHeroId(keyStr)
        if heroId then return heroId end
        -- type=shard 时 key 可能是 heroId（如 key=16 表示万剑归宗）
        if r.type == "shard" then
            local directId = tonumber(keyStr)
            if directId then return directId end
        end
    end

    return nil
end

--- 将 GM 奖励 token 规范化为邮件/发放格式
---@param key string|number 资源编号或 type（如 "7", "diamond", "101", "shard_16"）
---@param amount number
---@return table|nil { type, amount, heroId? }
function ResourceDefs.normalizeMailReward(key, amount)
    amount = tonumber(amount)
    if key == nil or not amount or amount <= 0 then
        return nil
    end
    key = tostring(key)

    local heroId = resolveShardHeroId(key)
    if heroId then
        return { type = "shard", heroId = heroId, amount = amount }
    end

    local typeKey = ResourceDefs.ID_TO_TYPE[key] or key
    if ResourceDefs.DEFS[typeKey] or ResourceDefs.REWARD_NAMES[typeKey] then
        return { type = typeKey, amount = amount }
    end
    return nil
end

--- 规范化已有 reward 条目（保留 heroId 等扩展字段）
---@param r table { type?, key?, amount?, heroId? }
---@return table|nil
function ResourceDefs.normalizeMailRewardEntry(r)
    if not r then return nil end
    local amount = tonumber(r.amount)
    if not amount or amount <= 0 then
        return nil
    end

    local shardHeroId = resolveShardHeroIdFromEntry(r)
    if shardHeroId or r.type == "shard" then
        if shardHeroId then
            return { type = "shard", heroId = shardHeroId, amount = amount }
        end
        print("[ResourceDefs] WARN drop shard reward: missing heroId"
            .. " type=" .. tostring(r.type) .. " key=" .. tostring(r.key))
        return nil
    end

    return ResourceDefs.normalizeMailReward(r.type or r.key, amount)
end

--- 规范化奖励列表（兼容单对象 / 数组 / map 及旧 GM 格式）
---@param rewards table|nil
---@return table[]
function ResourceDefs.normalizeMailRewardList(rewards)
    local list = {}
    if not rewards or type(rewards) ~= "table" then
        return list
    end

    local function addEntry(entry)
        if type(entry) ~= "table" then return end
        local normalized = ResourceDefs.normalizeMailRewardEntry(entry)
        if normalized then
            list[#list + 1] = normalized
        end
    end

    -- 单条奖励对象（非数组）：{ type/key, amount, heroId? }
    if rewards.type or rewards.key then
        addEntry(rewards)
        return list
    end

    for _, r in ipairs(rewards) do
        addEntry(r)
    end

    -- JSON 对象 map 兜底（ipairs 为空时）
    if #list == 0 then
        for _, r in pairs(rewards) do
            addEntry(r)
        end
    end

    return list
end

--- 合并多组邮件奖励（同 type 累加 amount）
---@param lists table[]
---@return table[]
function ResourceDefs.mergeMailRewardLists(lists)
    local byKey = {}
    local ordered = {}
    for _, list in ipairs(lists or {}) do
        for _, reward in ipairs(list or {}) do
            if type(reward) == "table" then
                local typeKey = tostring(reward.type or reward.key or "")
                local heroPart = reward.heroId and ("#h" .. tostring(reward.heroId)) or ""
                local key = typeKey .. heroPart
                if byKey[key] then
                    byKey[key].amount = (tonumber(byKey[key].amount) or 0) + (tonumber(reward.amount) or 0)
                else
                    local entry = {
                        type = reward.type or reward.key,
                        amount = tonumber(reward.amount) or 0,
                        heroId = reward.heroId,
                    }
                    byKey[key] = entry
                    ordered[#ordered + 1] = entry
                end
            end
        end
    end
    return ordered
end

--- 奖励表是否“看起来有内容但全部被丢弃”
---@param rewards table|nil
---@param normalized table[]
---@return boolean
function ResourceDefs.hasDroppedMailRewards(rewards, normalized)
    if not rewards or type(rewards) ~= "table" then
        return false
    end
    if normalized and #normalized > 0 then
        return false
    end
    if rewards.type or rewards.key then
        return true
    end
    if #rewards > 0 then
        return true
    end
    for _, r in pairs(rewards) do
        if type(r) == "table" then
            return true
        end
    end
    return false
end

--- 奖励展示名（GM 预览 / 邮件 UI）
---@param reward table
---@return string
function ResourceDefs.getRewardDisplayName(reward)
    if not reward then return "?" end
    if reward.type == "shard" and reward.heroId then
        local shardId = ResourceDefs.HERO_TO_SHARD_ID[reward.heroId]
        if shardId and ResourceDefs.REWARD_NAMES[shardId] then
            return ResourceDefs.REWARD_NAMES[shardId]
        end
        return "英雄" .. tostring(reward.heroId) .. "碎片"
    end
    local name = ResourceDefs.REWARD_NAMES[reward.type]
        or ResourceDefs.REWARD_NAMES[tostring(reward.type)]
    if name then return name end
    local def = ResourceDefs.DEFS[reward.type]
    if def and def.name then return def.name end
    return tostring(reward.type)
end

return ResourceDefs
