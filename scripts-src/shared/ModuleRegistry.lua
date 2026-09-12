-- ============================================================================
-- ModuleRegistry - 模块注册表（双端共享）
-- 职责: 定义所有业务模块名称、存档 key、默认值
-- 运行端: shared（服务端 + 客户端都加载）
-- ============================================================================

local ModuleRegistry = {}

--- 模块作用域常量
ModuleRegistry.SCOPE_GLOBAL = "global"   -- 跨服共享，key 不加区服前缀
ModuleRegistry.SCOPE_SERVER = "server"   -- 区服隔离，key 加 "s{id}_" 前缀

--- 全局模块定义表（跨服共享，key 无前缀）
ModuleRegistry.globalModules = {
    {
        name = "global_profile",
        key  = "global_profile",
        scope = "global",
        getDefault = function()
            return {
                servers      = {},   -- 已创角的区服 id 列表，如 {1, 3, 5}
                lastServerId = 0,    -- 上次登录的区服 id（0 表示从未选服）
                createTime   = 0,    -- 账号创建时间戳
            }
        end,
        onLoad = function(data)
            if not data.servers then data.servers = {} end
            data.lastServerId = tonumber(data.lastServerId) or 0
            data.createTime   = tonumber(data.createTime) or 0
            -- servers 存储为 dict { ["serverId"] = true }，
            -- cjson 反序列化后 key 是字符串，需转回数字 key
            local fixedServers = {}
            for k, v in pairs(data.servers) do
                local numK = tonumber(k)
                if numK then
                    fixedServers[numK] = v
                else
                    fixedServers[k] = v
                end
            end
            data.servers = fixedServers
        end,
    },
}

--- 模块定义表（区服隔离，key 加区服前缀）
--- 每个模块包含:
---   name       : 模块名（唯一标识，用于 SaveManager/Dispatcher）
---   key        : 存档 key（省略则归入默认 key "save_data"）
---   scope      : "server"（区服隔离）
---   getDefault : 返回子表默认值的工厂函数
ModuleRegistry.modules = {
    -- ========== 玩家基础 ==========
    {
        name = "player",
        key  = "mod_player",
        scope = "server",
        getDefault = function()
            return {
                name         = "玩家",
                level        = 1,
                exp          = 0,
                maxExp       = 50,   -- 冒险等级1级升2级所需经验（来自 ExpTable）
                power        = 1000,
                avatarHeroId  = 1,
                avatarFrameId = 1,
            }
        end,
        onLoad = function(data)
            local PlayerSchema = require("shared.player.PlayerSchema")
            local field = PlayerSchema.Fields and PlayerSchema.Fields.player
            if field and field.onLoad then
                field.onLoad(data)
            end
            data.avatarHeroId = tonumber(data.avatarHeroId) or 1
        end,
    },

    -- ========== 货币 ==========
    {
        name = "currency",
        key  = "mod_currency",
        scope = "server",
        getDefault = function()
            return {
                gold = 0,
                gems = 0,
                essence = 0,
                enhanceStone = 0,     -- 洗练石（原强化星石）
                degradeStone = 0,     -- （已隐藏，占位保留）
                destroyStone = 0,     -- 点金石（原损毁保护石）
                weaponScroll = 0,     -- 武器卷轴
                offhandScroll = 0,    -- 副手卷轴
                armorScroll = 0,      -- 护甲卷轴
                accessoryScroll = 0,  -- 饰品卷轴
                recruitTicket = 0,
                stellarRecruitTicket = 0,
                goldenKey = 0,
                sweepTicket = 0,
                arenaTicket = 0,
                arenaCoin = 0,
                tavernCoin = 0,
                privilegePoint = 0,
                arcaneDust = 0,
                corruptStone = 0,
                sacredStone = 0,
                speedCardExpireAt = 0, -- 加速卡到期时间戳（与 CurrencySchema 一致）
                gachaPitySR  = 0,
                gachaPitySSR = 0,
                gachaStandardPulls = 0,
                gachaDrawStats = {},
                urPitySR  = 0,
                urPitySSR = 0,
                urPityUR  = 0,
                targetRecruitHeroId = nil,
                targetRecruitRemain = 0,
                stellarTargetUpHeroId = nil,
            }
        end,
        onLoad = function(data)
            local CurrencySchema = require("shared.currency.CurrencySchema")
            local field = CurrencySchema.Fields and CurrencySchema.Fields.currency
            if field and field.onLoad then
                field.onLoad(data)
            end
        end,
    },

    -- ========== 英雄阵容 ==========
    {
        name = "heroes",
        key  = "mod_heroes",
        scope = "server",
        getDefault = function()
            return {
                -- roster: 已拥有的英雄 { [heroId] = { level=1, exp=0, ... } }
                -- 注意: heroId 使用数字 key（与 HeroConfig.HEROES 一致）
                roster = {},
                -- deployed: 出战阵容（队1 兼容镜像，最多 4 个英雄 ID）
                deployed = {},
                -- [三队并行] teams[1..3] 权威三队结构（见 shared/heroes/TeamSlots.lua）
                teams = {},
                urShardConvertDayId = 0,
                urShardConvertCount = 0,
            }
        end,
        --- cjson 反序列化后数字 key 变成字符串 key，需要在加载时修正
        --- 同时确保老玩家存档中至少有初始英雄
        onLoad = function(data)
            if data.roster then
                local fixed = {}
                for k, v in pairs(data.roster) do
                    local numKey = tonumber(k)
                    if numKey then
                        fixed[numKey] = v
                    else
                        fixed[k] = v  -- 保留无法转换的 key（兼容旧 "hero_001" 格式）
                    end
                end
                data.roster = fixed
            else
                data.roster = {}
            end
            -- 注意：roster 为空是合法状态（新玩家尚未选择初始英雄）
            -- deployed 数组元素也需要转为数字
            if data.deployed then
                for i, v in ipairs(data.deployed) do
                    local num = tonumber(v)
                    if num then
                        data.deployed[i] = num
                    end
                end
            else
                data.deployed = {}
            end
            data.urShardConvertDayId = math.floor(tonumber(data.urShardConvertDayId) or 0)
            data.urShardConvertCount = math.max(0, math.floor(tonumber(data.urShardConvertCount) or 0))
            -- 确保阵容不为空：部署 roster 中第一个英雄
            if #data.deployed == 0 then
                for heroId, _ in pairs(data.roster) do
                    data.deployed[1] = heroId
                    break
                end
            end
            -- [三队并行] teams 归一化 + 旧档迁移（deployed → teams[1] 镜像）
            do
                local TeamSlots = require("shared.heroes.TeamSlots")
                TeamSlots.normalize(data)
            end
            -- 兼容旧存档：确保 advBranch 字段中的 branchId 为数字
            -- 兼容旧存档：确保 awakening 字段中的 nodeIndex key 为数字
            for _, heroData in pairs(data.roster) do
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
                        if numK then
                            fixedAwk[numK] = v
                        end
                    end
                    heroData.awakening = fixedAwk
                end
                -- 迁移：老存档没有 dupeCount，从已激活觉醒数推算
                if heroData.dupeCount == nil then
                    local awakeCount = 0
                    if heroData.awakening then
                        for _ in pairs(heroData.awakening) do awakeCount = awakeCount + 1 end
                    end
                    heroData.dupeCount = awakeCount
                end
            end
        end,
    },

    -- ========== 装备 ==========
    {
        name = "equipment",
        key  = "mod_equipment",
        scope = "server",
        getDefault = function()
            return {
                -- inventory: 背包中的装备 { ["seq"] = equipInstance, ... }
                -- equipInstance 结构见 EquipmentSystem.generate 返回值
                inventory = {},
                -- equipped: 英雄穿戴的装备 { [heroId] = { [slot] = seq, ... } }
                equipped  = {},
                -- nextSeq: 装备序列号自增计数器
                nextSeq   = 1,
            }
        end,
        onLoad = function(data)
            if not data.inventory then data.inventory = {} end
            if not data.equipped  then data.equipped  = {} end
            if not data.nextSeq   then data.nextSeq   = 1 end
            -- nextSeq 可能被 cjson 反序列化为浮点数
            data.nextSeq = math.floor(tonumber(data.nextSeq) or 1)
            -- equipped 的 heroId key 需要转为数字
            local fixedEquipped = {}
            for k, v in pairs(data.equipped) do
                local numKey = tonumber(k)
                if numKey then
                    fixedEquipped[numKey] = v
                else
                    fixedEquipped[k] = v
                end
            end
            -- 清理孤立条目：删除 inventory 中已不存在的 seq 引用
            for heroId, slots in pairs(fixedEquipped) do
                for slot, seq in pairs(slots) do
                    if not data.inventory[tostring(seq)] and not data.inventory[seq] then
                        slots[slot] = nil
                        print("[equipment.onLoad] removed orphan equipped heroId=" .. tostring(heroId)
                            .. " slot=" .. slot .. " seq=" .. tostring(seq))
                    end
                end
                -- 如果该英雄所有槽位都被清空，移除整个条目
                if next(slots) == nil then
                    fixedEquipped[heroId] = nil
                    print("[equipment.onLoad] removed empty heroId=" .. tostring(heroId))
                end
            end
            data.equipped = fixedEquipped

            -- 🔴 水合：从精简存储/传输格式还原可派生字段（name/type/slot/grip/baseStats, affix key/name）
            -- 服务端推送和云端存储均使用 dehydrated 格式，客户端收到后需要还原
            local EquipmentSystem = require("systems.EquipmentSystem")
            EquipmentSystem.hydrateInventory(data.inventory)
        end,
    },

    -- ========== 槽位强化 ==========
    {
        name = "slotEnhance",
        key  = "mod_slot_enhance",
        scope = "server",
        getDefault = function()
            return {
                -- levels: 槽位强化等级
                -- levels[partySlot][equipSlot] = enhanceLevel
                -- partySlot: "1"~"5"（出战槽位索引，cjson 反序列化后为字符串）
                -- equipSlot: "weapon"/"offhand"/"armor"/"accessory"
                -- enhanceLevel: 0~100
                levels = {},
            }
        end,
        onLoad = function(data)
            if not data.levels then data.levels = {} end
            -- cjson 反序列化后数字 key 变字符串，统一转为数字 key
            local fixed = {}
            for k, slots in pairs(data.levels) do
                local numK = tonumber(k)
                if numK then
                    fixed[numK] = slots
                end
            end
            data.levels = fixed
        end,
    },

    -- ========== 战斗进度 ==========
    {
        name = "battle",
        key  = "mod_battle",
        scope = "server",
        getDefault = function()
            return {
                currentStageId = 0101,   -- 当前关卡 4 位 ID（chapter*100+stage）
                maxStageId     = 0101,   -- 最远到达的关卡 ID
                autoBattle     = true,
                clearedStages  = {},     -- { ["101"]=true, ["102"]=true, ... }
            }
        end,
        onLoad = function(data)
            -- 确保 clearedStages 存在（兼容旧存档）
            if not data.clearedStages then
                data.clearedStages = {}
            end
            -- 兼容旧存档字段名迁移
            if data.currentStage and not data.currentStageId then
                data.currentStageId = 0101
                data.currentStage = nil
            end
            if data.maxStage and not data.maxStageId then
                data.maxStageId = data.currentStageId or 0101
                data.maxStage = nil
            end
            -- 确保有值
            if not data.currentStageId then
                data.currentStageId = 0101
            end
            if not data.maxStageId then
                data.maxStageId = data.currentStageId
            end
        end,
    },

    -- ========== 竞技场 ==========
    {
        name = "arena",
        key  = "mod_arena",
        scope = "server",
        getDefault = function()
            return {
                rankScore        = 0,       -- 段位分（永久累积）
                weekScore        = 1000,    -- 周期分（每周重置）
                groupId          = nil,     -- 当前所属小组ID
                weekId           = 0,       -- 当前赛周ID
                lastSettleWeekId = 0,       -- 上次结算的赛周ID
                reachedTiers     = {},      -- 已达成的段位ID（用于首次奖励判断）
                totalWins        = 0,       -- 累计进攻胜利
                totalLosses      = 0,       -- 累计进攻失败
                ticketsUsedToday = 0,       -- 今日已使用竞技券
                ticketResetDay   = 0,       -- 竞技券重置日编号
                shopPurchased    = {},      -- 商店已购买次数 { [itemId] = count }
                shopWeekId       = 0,       -- 商店购买记录对应的赛周（用于每周重置）
            }
        end,
        onLoad = function(data)
            data.rankScore        = tonumber(data.rankScore)        or 0
            data.weekScore        = tonumber(data.weekScore)        or 1000
            data.weekId           = tonumber(data.weekId)           or 0
            data.lastSettleWeekId = tonumber(data.lastSettleWeekId) or 0
            data.totalWins        = tonumber(data.totalWins)        or 0
            data.totalLosses      = tonumber(data.totalLosses)      or 0
            data.ticketsUsedToday = tonumber(data.ticketsUsedToday) or 0
            data.ticketResetDay   = tonumber(data.ticketResetDay)   or 0
            data.shopWeekId       = tonumber(data.shopWeekId)       or 0
            if not data.shopPurchased then
                data.shopPurchased = {}
            else
                -- cjson 反序列化后数字 key 变成字符串 key，需要转回数字
                local fixedShop = {}
                for k, v in pairs(data.shopPurchased) do
                    local numK = tonumber(k)
                    if numK then
                        fixedShop[numK] = tonumber(v) or 0
                    end
                end
                data.shopPurchased = fixedShop
            end
            if not data.reachedTiers then
                data.reachedTiers = {}
            else
                -- reachedTiers 是 dict: { [tierId]=true }
                -- cjson 反序列化后数字 key 变成字符串 key，需要转回数字
                local fixed = {}
                for k, v in pairs(data.reachedTiers) do
                    local numK = tonumber(k)
                    if numK then
                        fixed[numK] = v
                    else
                        fixed[k] = v
                    end
                end
                data.reachedTiers = fixed
            end
            data.groupId = tonumber(data.groupId)  -- 可为 nil
        end,
    },

    -- ========== 战利品缓冲 ==========
    {
        name = "lootbox",
        key  = "mod_lootbox",
        scope = "server",
        getDefault = function()
            return {
                -- seeds: 掉落种子数组（合并计数）
                -- { stageId=number, quality=number, level=number, count=number }
                seeds = {},
            }
        end,
        onLoad = function(data)
            if not data.seeds then data.seeds = {} end
            -- cjson 反序列化后数字可能变浮点，修正为整数
            for _, seed in ipairs(data.seeds) do
                seed.stageId = math.floor(tonumber(seed.stageId) or 0)
                seed.quality = math.floor(tonumber(seed.quality) or 1)
                seed.level   = math.floor(tonumber(seed.level) or 1)
                seed.count   = math.floor(tonumber(seed.count) or 1)
            end
        end,
    },

    -- ========== 天赋 ==========
    {
        name = "talents",
        key  = "mod_talents",
        scope = "server",
        getDefault = function()
            return {
                litNodes = { 0 },   -- 已点亮节点 ID 数组，node 0 = 起始点（始终点亮）
            }
        end,
        onLoad = function(data)
            if not data.litNodes then
                data.litNodes = { 0 }
            end
            -- cjson 反序列化后数组元素可能变为字符串，修正为 number
            for i, v in ipairs(data.litNodes) do
                data.litNodes[i] = tonumber(v) or v
            end
            -- 确保起始点 0 存在
            local has0 = false
            for _, v in ipairs(data.litNodes) do
                if v == 0 then has0 = true; break end
            end
            if not has0 then
                table.insert(data.litNodes, 1, 0)
            end
        end,
    },

    -- ========== 签到 ==========
    {
        name = "signin",
        key  = "mod_signin",
        scope = "server",
        getDefault = function()
            return {
                -- 每周签到
                weekId       = 0,    -- 当前周编号（用于周重置判断）
                weeklyClaimed = {},   -- 已领取的天数集合 { [1]=true, [2]=true, ... }
                -- 每日签到（按月循环）
                monthId      = 0,    -- 当前月编号（用于月重置判断）
                dailyClaimed = {},   -- 已领取的天数集合 { [1]=true, [2]=true, ... }
            }
        end,
        onLoad = function(data)
            data.weekId  = tonumber(data.weekId)  or 0
            data.monthId = tonumber(data.monthId)  or 0
            -- cjson 反序列化：数字 key 变字符串，修正为数字
            if data.weeklyClaimed then
                local fixed = {}
                for k, v in pairs(data.weeklyClaimed) do
                    fixed[tonumber(k) or k] = v
                end
                data.weeklyClaimed = fixed
            else
                data.weeklyClaimed = {}
            end
            if data.dailyClaimed then
                local fixed = {}
                for k, v in pairs(data.dailyClaimed) do
                    fixed[tonumber(k) or k] = v
                end
                data.dailyClaimed = fixed
            else
                data.dailyClaimed = {}
            end
        end,
    },

    -- ========== 邮件 ==========
    {
        name = "mail",
        key  = "mod_mail",
        scope = "server",
        getDefault = function()
            return {
                claimed = {},   -- { [mailId] = true } 已领取的邮件
                deleted = {},   -- { [mailId] = true } 已删除的邮件
            }
        end,
        onLoad = function(data)
            if not data.claimed then data.claimed = {} end
            if not data.deleted then data.deleted = {} end
        end,
    },

    -- ========== 兑换码 ==========
    {
        name = "redeem",
        key  = "mod_redeem",
        scope = "server",
        getDefault = function()
            return {
                usedCodes = {},   -- { [CODE] = true } 已使用的兑换码
            }
        end,
        onLoad = function(data)
            if not data.usedCodes then data.usedCodes = {} end
        end,
    },

    -- ========== 任务系统 ==========
    {
        name = "task",
        key  = "mod_task",
        scope = "server",
        getDefault = function()
            return {
                -- 日任务
                dayId        = 0,    -- 当前天编号（用于日重置）
                dailyProg    = {},   -- { [condKey] = number } 日任务进度
                dailyClaimed = {},   -- { [taskId] = true }   日任务已领取

                -- 周任务
                weekId        = 0,    -- 当前周编号（用于周重置）
                weeklyProg    = {},   -- { [condKey] = number } 周任务进度
                weeklyClaimed = {},   -- { [taskId] = true }   周任务已领取

                -- 成就（永久）
                achProg    = {},   -- { [condKey] = number } 成就进度
                achClaimed = {},   -- { [taskId] = true }   成就已领取
            }
        end,
        onLoad = function(data)
            data.dayId  = tonumber(data.dayId)  or 0
            data.weekId = tonumber(data.weekId) or 0
            if not data.dailyProg    then data.dailyProg    = {} end
            if not data.dailyClaimed then data.dailyClaimed = {} end
            if not data.weeklyProg    then data.weeklyProg    = {} end
            if not data.weeklyClaimed then data.weeklyClaimed = {} end
            if not data.achProg    then data.achProg    = {} end
            if not data.achClaimed then data.achClaimed = {} end
        end,
    },

    -- ========== 会话信息 ==========
    {
        name = "session",
        key  = "mod_session",
        scope = "server",
        getDefault = function()
            return {
                lastOnlineTime = 0,  -- 上次在线时间戳（os.time()）
                firstLoginTime = 0,  -- 首次登录时间戳（os.time()）
                introCompleted = false,  -- 是否已完成开场剧情（客户端播完后标记）
            }
        end,
        onLoad = function(data)
            data.lastOnlineTime = tonumber(data.lastOnlineTime) or 0
            data.firstLoginTime = tonumber(data.firstLoginTime) or 0
            if data.introCompleted == nil then
                data.introCompleted = false
            end
            -- cjson 会将数字字符串 key 反序列化为数字 key，统一转为字符串
            if data.claimedScenarios then
                local fixed = {}
                for k, v in pairs(data.claimedScenarios) do
                    fixed[tostring(k)] = v
                end
                data.claimedScenarios = fixed
            end
        end,
    },

    -- ========== 副本 ==========
    {
        name = "dungeon",
        key  = "mod_dungeon",
        scope = "server",
        getDefault = function()
            return {
                -- gold_mine: 黄金矿洞进度
                gold_mine = {
                    floor     = 1,   -- 当前挑战层（已通关层+1，首次为1）
                    cleared   = {},  -- { [floor]=true } 已首通的层
                    dailyUsed = 0,   -- 今日已扫荡次数
                    dailyDay  = 0,   -- 上次扫荡的天编号（用于每日重置）
                },
                ancient_ruin = {
                    floor     = 1,
                    cleared   = {},
                    dailyUsed = 0,
                    dailyDay  = 0,
                },
                -- babel_tower: 通天塔进度
                babel_tower = {
                    floor     = 1,   -- 当前可挑战层
                    cleared   = {},  -- { [floor]=true } 已首通的层
                    dailyUsed = 0,   -- 今日已扫荡次数
                    dailyDay  = 0,   -- 上次扫荡的天编号
                    buffs     = {},  -- 当前局内已选强化ID列表 { buffId, ... }
                },
            }
        end,
        onLoad = function(data)
            local DungeonCompat = require("shared.dungeon.DungeonCompat")
            DungeonCompat.onLoad(data)
        end,
    },

    -- ========== 市场商店 ==========
    {
        name = "market",
        key  = "mod_market",
        scope = "server",
        getDefault = function()
            return {
                -- purchased: { [itemId] = { count=number, lastBuyTime=number } }
                purchased = {},
            }
        end,
        onLoad = function(data)
            if not data.purchased then
                data.purchased = {}
            else
                local fixed = {}
                for k, v in pairs(data.purchased) do
                    local numK = tonumber(k)
                    if numK then
                        fixed[numK] = v
                        fixed[numK].count = tonumber(v.count) or 0
                        fixed[numK].firstBuyTime = tonumber(v.firstBuyTime) or 0
                    end
                end
                data.purchased = fixed
            end
        end,
    },

    -- ========== 神器 ==========
    {
        name = "artifacts",
        key  = "mod_artifacts",
        scope = "server",
        getDefault = function()
            return {
                bag        = {},
                equipped   = {},
                nextId     = 1,
                pityRare   = 0,
                pityEpic   = 0,
                totalDraws = 0,
                drawStats  = {},
            }
        end,
        onLoad = function(data)
            local ArtifactSchema = require("shared.artifact.ArtifactSchema")
            ArtifactSchema.normalizeModule(data)
        end,
        onSave = function(data)
            local ArtifactSchema = require("shared.artifact.ArtifactSchema")
            return ArtifactSchema.dehydrateModule(data)
        end,
    },
}

--- 按模块名查找（先查区服模块，再查全局模块）
---@param name string
---@return table|nil
function ModuleRegistry.find(name)
    for _, m in ipairs(ModuleRegistry.modules) do
        if m.name == name then
            return m
        end
    end
    for _, m in ipairs(ModuleRegistry.globalModules) do
        if m.name == name then
            return m
        end
    end
    return nil
end

--- 旧版存档 key（用于数据迁移）
--- 之前所有模块共享此 key，新版拆分为独立 key 后需要兼容读取
ModuleRegistry.LEGACY_KEY = "save_data"

--- 获取所有区服模块名列表
---@return string[]
function ModuleRegistry.getAllNames()
    local names = {}
    for _, m in ipairs(ModuleRegistry.modules) do
        names[#names + 1] = m.name
    end
    return names
end

--- 获取所有全局模块名列表
---@return string[]
function ModuleRegistry.getGlobalNames()
    local names = {}
    for _, m in ipairs(ModuleRegistry.globalModules) do
        names[#names + 1] = m.name
    end
    return names
end

--- 对指定模块的数据执行 onLoad 修正（cjson key 类型等）
--- 客户端收到推送数据后也需要调用，确保与服务端一致
---@param moduleName string
---@param data table
function ModuleRegistry.applyOnLoad(moduleName, data)
    -- 先查区服模块
    for _, m in ipairs(ModuleRegistry.modules) do
        if m.name == moduleName and m.onLoad then
            local ok, err = pcall(m.onLoad, data)
            if not ok then
                print("[ModuleRegistry] applyOnLoad error for " .. moduleName .. ": " .. tostring(err))
            end
            return
        end
    end
    -- 再查全局模块
    for _, m in ipairs(ModuleRegistry.globalModules) do
        if m.name == moduleName and m.onLoad then
            local ok, err = pcall(m.onLoad, data)
            if not ok then
                print("[ModuleRegistry] applyOnLoad error for " .. moduleName .. ": " .. tostring(err))
            end
            return
        end
    end
end

return ModuleRegistry
