-- ResourceDefs.lua — 资源定义中央注册表（唯一真相源）
-- ============================================================
-- 所有 UI 面板（RewardPopup / MailPanel / BattleResultPanel / OfflineRewardPanel /
-- RecruitAnim / GMConsolePanel 等）统一 require 此文件，
-- 新增资源只需在此文件添加一行即可全局生效。
-- ============================================================

local ResourceDefs = {}

--- UI 资源定义表
--- key = snake_case type 字符串（与奖励协议 payload 一致）
--- value = { iconPath, quality, name }
ResourceDefs.DEFS = {
    gold              = { iconPath = "image/货币道具/UI_icon_JB_X.png",   quality = 2, name = "金币" },
    diamond           = { iconPath = "image/货币道具/UI_icon_SJ_X.png",     quality = 5, name = "黑晶" },
    essence           = { iconPath = "image/货币道具/UI_icon_JC.png",     quality = 2, name = "精粹" },
    enhance_star      = { iconPath = "image/货币道具/UI_icon_QH_1.png",   quality = 3, name = "洗练石" },
    refine_stone      = { iconPath = "image/货币道具/UI_icon_QH_1.png",   quality = 3, name = "洗练石" },  -- 别名
    degrade_protect   = { iconPath = "image/货币道具/UI_icon_QH_2.png",   quality = 4, name = "退级保护石" },  -- 已隐藏(seq5)，保留兼容旧邮件/奖励显示
    break_protect     = { iconPath = "image/货币道具/UI_icon_QH_3.png",   quality = 5, name = "点金石" },
    gold_stone        = { iconPath = "image/货币道具/UI_icon_QH_3.png",   quality = 5, name = "点金石" },  -- 别名
    weapon_scroll     = { iconPath = "image/货币道具/UI_icon_JZ_WQ.png",  quality = 3, name = "武器卷轴" },
    offhand_scroll    = { iconPath = "image/货币道具/UI_icon_JZ_FS.png",  quality = 3, name = "副手卷轴" },
    armor_scroll      = { iconPath = "image/货币道具/UI_icon_JZ_HJ.png",  quality = 3, name = "护甲卷轴" },
    accessory_scroll  = { iconPath = "image/货币道具/UI_icon_JZ_SP.png",  quality = 3, name = "饰品卷轴" },
    helmet_scroll     = { iconPath = "image/货币道具/UI_icon_JZ_TK.png",  quality = 3, name = "头盔卷轴" },
    shoes_scroll      = { iconPath = "image/货币道具/UI_icon_JZ_XZ.png",  quality = 3, name = "鞋子卷轴" },
    random_scroll     = { iconPath = "image/货币道具/UI_icon_JZ_SJ.png",  quality = 3, name = "随机卷轴" },
    adventure_ticket  = { iconPath = "image/货币道具/UI_icon_ZMQ_1.png",  quality = 5, name = "远征招募券" },
    stellar_ticket    = { iconPath = "image/货币道具/UI_icon_ZMQ_2.png",  quality = 6, name = "星辰招募券" },
    sweep_ticket      = { iconPath = "image/货币道具/UI_icon_SDQ.png",    quality = 4, name = "扫荡券" },
    tavern_coin       = { iconPath = "image/货币道具/UI_icon_JGB_X.png", quality = 3, name = "酒馆币" },
    arcane_dust       = { iconPath = "image/货币道具/UI_icon_ASFC.png",   quality = 3, name = "奥术粉尘" },  -- 序号17
    speed_card        = { iconPath = "image/货币道具/UI_icon_JSK.png",    quality = 5, name = "加速卡" },    -- 序号18
    golden_key        = { iconPath = "image/货币道具/UI_icon_HJYS.png", quality = 6, name = "黄金钥匙" },
    corrupt_stone     = { iconPath = "image/货币道具/UI_icon_FHS.png",    quality = 3, name = "腐化石" },
    sacred_stone      = { iconPath = "image/货币道具/UI_icon_SSS.png",    quality = 6, name = "神圣石" },
}

--- 物品用途由奖励、离线与背包详情共同读取。
ResourceDefs.DEFS.gold.desc = "用于角色转职、装备升阶和市场购买。"
ResourceDefs.DEFS.diamond.desc = "用于酒馆招募、神器宝箱和市场购买。"
ResourceDefs.DEFS.golden_key.desc = "用于开启神器宝箱：普通宝箱每次1把，高级宝箱每次5把。每把钥匙的购买价格为150黑晶。"
ResourceDefs.DEFS.sweep_ticket.desc = "用于扫荡已通关关卡：每券结算一场重复战斗奖励，不含首通奖励；主线与资源副本均按所选关卡计算。"
ResourceDefs.DEFS.adventure_ticket.desc = "用于酒馆普通远征招募，每次招募消耗1张。"
ResourceDefs.DEFS.stellar_ticket.desc = "用于酒馆星辰招募，每次招募消耗1张。"
ResourceDefs.DEFS.tavern_coin.desc = "用于酒馆商店兑换英雄碎片等物品。"
ResourceDefs.DEFS.arcane_dust.desc = "奥术材料，可在背包查看持有数量，当前没有消耗入口。"
ResourceDefs.DEFS.speed_card.desc = "获得时立即生效，持续24小时，使在线挂机收益提高20%；不提高离线收益。"
ResourceDefs.DEFS.degrade_protect.desc = "兼容存档中的退级保护材料，当前没有使用入口。"
for _, key in ipairs({ "weapon_scroll", "offhand_scroll", "armor_scroll", "accessory_scroll", "helmet_scroll", "shoes_scroll" }) do
    ResourceDefs.DEFS[key].desc = "用于对应部位装备升阶，提升装备主属性、固定副属性及普通随机词条。"
end
ResourceDefs.DEFS.random_scroll.desc = "可获得随机部位的装备升阶卷轴。"

--- 洗练材料使用说明；按当前锻炉规则展示，不根据遗留资源 key 推断用途。
ResourceDefs.DEFS.essence.desc = "用于普通洗练，重新随机未锁定的普通词缀；锁定词缀和魔化词条保持不变。\n消耗随装备品质、等级和锁定数量变化，双手装备费用翻倍；腐化装备的精粹费用再翻倍。\n洗练后需点击「替换」应用结果。"
ResourceDefs.DEFS.enhance_star.desc = "保留词缀种类，重新随机未锁定词缀的品级与数值；若新数值更低，保留原词缀。锁定词缀和魔化词条不变。\n每次消耗1颗，不消耗精粹。\n洗练后需点击「替换」应用结果。"
ResourceDefs.DEFS.break_protect.desc = "提升装备品质1级，保留原词缀；增加词缀槽位时补充新词缀。\n达到当前进度的品质上限后，改为随机提升一条普通词缀的品级1级，最高S品。\n消耗颗数等于装备当前品质编号，不消耗精粹，结果直接生效。"
ResourceDefs.DEFS.corrupt_stone.desc = "随机将一条可转换的普通词缀变为对应魔化词条并强化数值，同时增加1层腐化，最多3层。\n每层腐化使装备基础属性乘以90%；腐化后普通洗练的精粹费用翻倍。\n每次消耗1颗，不消耗精粹，结果直接生效。"
ResourceDefs.DEFS.sacred_stone.desc = "用于已腐化装备，洗除最上层腐化，恢复该层损失的基础属性，并还原该层转换的词缀。旧版腐化记录可能一次清除全部层数。\n每次消耗1颗，不消耗精粹，不增加洗练次数，结果直接生效。"
ResourceDefs.DEFS.refine_stone.desc = ResourceDefs.DEFS.enhance_star.desc
ResourceDefs.DEFS.gold_stone.desc = ResourceDefs.DEFS.break_protect.desc

--- 数字 ID（来自资源配置表序号）→ snake_case type 映射
--- GMConsolePanel / 奖励字符串解析使用
ResourceDefs.ID_TO_TYPE = {
    ["1"]  = "gold",
    ["2"]  = "diamond",
    ["3"]  = "essence",
    ["4"]  = "enhance_star",
    -- 5：隐藏
    ["6"]  = "break_protect",
    ["7"]  = "adventure_ticket",
    ["8"]  = "sweep_ticket",
    ["11"] = "tavern_coin",
    ["13"] = "weapon_scroll",
    ["14"] = "offhand_scroll",
    ["15"] = "armor_scroll",
    ["16"] = "accessory_scroll",
    ["24"] = "helmet_scroll",
    ["25"] = "shoes_scroll",
    ["17"] = "arcane_dust",
    ["18"] = "speed_card",
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
ResourceDefs.REWARD_NAMES["106"] = "压一压碎片"
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
ResourceDefs.REWARD_NAMES["121"] = "雷电麦坤碎片"
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

--- 奖励详情用途；仅描述物品规则，不参与领取或奖励计算。
---@param reward table|nil
---@return string
function ResourceDefs.getRewardDescription(reward)
    if not reward then return "" end
    if reward.type == "equip" then return "用于角色穿戴；可在铁匠铺升阶、洗练或分解。" end
    if reward.type == "shard" then return "用于招募对应英雄和英雄觉醒。" end
    local typeKey = ResourceDefs.ID_TO_TYPE[tostring(reward.type)] or reward.type
    local def = ResourceDefs.DEFS[typeKey]
    return def and def.desc or ""
end

return ResourceDefs
