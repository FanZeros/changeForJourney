-- ============================================================================
-- 全局游戏配置 - 所有常量的唯一来源
-- ============================================================================

local GameConfig = {}

-- 设计分辨率（竖屏）
GameConfig.Design = {
    WIDTH  = 1080,
    HEIGHT = 2400,
}

-- 棋盘配置
GameConfig.Board = {
    ROWS = 4,
    COLS = 4,
    SLOT_SIZE = 72,
    SLOT_GAP = 6,
}

-- 手牌配置
GameConfig.Hand = {
    MAX_CARDS = 7,
    DRAW_COST = 50,
}

-- 挂机配置
GameConfig.Idle = {
    TICK_INTERVAL = 1.0,
    OFFLINE_MAX_HOURS = 8,
    BASE_INCOME_PER_TICK = 1,
}

-- 货币配置
GameConfig.Currency = {
    START_GOLD = 0,
    START_GEMS = 0,
    START_ESSENCE = 0,
    START_ENHANCE_STONE = 0,   -- 洗练石（原强化星石，字段名保留兼容存档）
    START_DEGRADE_STONE = 0,   -- （已隐藏，占位保留）
    START_DESTROY_STONE = 0,   -- 点金石（原损毁保护石，字段名保留兼容存档）
    START_WEAPON_SCROLL = 0,   -- 武器卷轴
    START_OFFHAND_SCROLL = 0,  -- 副手卷轴
    START_ARMOR_SCROLL = 0,    -- 护甲卷轴
    START_ACCESSORY_SCROLL = 0,-- 饰品卷轴
    START_RECRUIT_TICKET = 0,
    START_SWEEP_TICKET = 0,
    START_ARENA_TICKET = 0,
    START_ARENA_COIN = 0,
    START_TAVERN_COIN = 0,
    START_PRIVILEGE_POINT = 0,
    START_CORRUPT_STONE = 0,
    START_SACRED_STONE = 0,
}

-- 资源定义表（Debug面板用）
-- key 与 currency 存档字段名一致
GameConfig.Resources = {
    { key = "gold",          name = "金币",       giveAmount = 1000 },
    { key = "gems",          name = "钻石",       giveAmount = 100  },
    { key = "essence",       name = "精粹",       giveAmount = 500  },
    { key = "enhanceStone",    name = "洗练石",     giveAmount = 10   },
    -- degradeStone(seq5) 已隐藏，不在 Debug 面板显示
    { key = "destroyStone",    name = "点金石",     giveAmount = 3    },
    { key = "weaponScroll",    name = "武器卷轴",   giveAmount = 5    },
    { key = "offhandScroll",   name = "副手卷轴",   giveAmount = 5    },
    { key = "armorScroll",     name = "护甲卷轴",   giveAmount = 5    },
    { key = "accessoryScroll", name = "饰品卷轴",   giveAmount = 5    },
    { key = "recruitTicket", name = "冒险招募券", giveAmount = 10   },
    { key = "stellarRecruitTicket", name = "星辉招募券", giveAmount = 10 },
    { key = "sweepTicket",   name = "扫荡券",     giveAmount = 10   },
    { key = "arenaTicket",   name = "竞技券",     giveAmount = 5    },
    { key = "arenaCoin",     name = "竞技币",     giveAmount = 50   },
    { key = "tavernCoin",    name = "酒馆币",     giveAmount = 50   },
    { key = "privilegePoint", name = "特权点",   giveAmount = 20   },
    { key = "arcaneDust",    name = "奥术粉尘", giveAmount = 1000 },
    { key = "corruptStone",  name = "腐化石",   giveAmount = 10   },
    { key = "sacredStone",   name = "神圣石",   giveAmount = 3    },
    { key = "speedCardExpireAt", name = "加速卡", giveAmount = 86400 },
    { key = "privilegeCardOwned", name = "特权卡", giveAmount = 1 },  -- 永久，1=激活
}

-- 玩家初始信息
GameConfig.Player = {
    DEFAULT_NAME = "玩家",
    DEFAULT_LEVEL = 1,
    DEFAULT_EXP = 0,
    DEFAULT_MAX_EXP = 50,   -- 冒险等级1级升2级所需经验（来自 ExpTable）
    DEFAULT_POWER = 1000,
}

-- 功能开关
GameConfig.Features = {
    MERGE_ENABLED = true,
    SHOP_ENABLED = true,
    OFFLINE_REWARDS = true,
}

-- 限时战斗（首通推关 / 副本 / 竞技场）：超时自动判负
GameConfig.Battle = {
    TIME_LIMIT_SEC = 300,   -- 5 分钟
}

-- 首通狂暴机制（防止肉+奶无限磨血；须早于 Battle.TIME_LIMIT_SEC）
GameConfig.StageBerserk = {
    RAGE_TIME       = 120,   -- 一阶狂暴：2 分钟（限时 40%）
    RAGE_ATK_BONUS  = 0.50,  -- 一阶狂暴：敌方攻速 +50%；己方同值加速
    SUPER_RAGE_TIME      = 210,   -- 二阶超级狂暴：3.5 分钟（限时 70%）
    SUPER_RAGE_ATK_BONUS = 1.00,  -- 二阶超级狂暴：敌方攻速 +100%；己方同值加速
    SUPER_RAGE_DMG_BONUS = 0.30,  -- 二阶超级狂暴：敌方攻击力 +30%
    ALLY_RAGE_DMG_BONUS = 0.30,   -- 一阶狂暴：己方攻击力 +30%
    ALLY_SUPER_RAGE_DMG_BONUS = 0.30, -- 二阶超级狂暴：己方攻击力 +30%
}

return GameConfig
