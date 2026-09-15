-- ============================================================================
-- TutorialConfig - 新手引导配置
-- 来源: docs/配置文件/新手引导.txt
-- ============================================================================
--
-- 结构说明：
--   TutorialConfig[groupId] = {
--     triggerScenario = number|number[],  -- 触发条件：哪些情景ID结束后触发
--     unlocks         = string[]|nil,     -- 本组完成后解锁的建筑 key
--     steps           = {                 -- 步骤列表
--       {
--         text       = string,            -- 引导文本（nil = 无气泡文本）
--         highlight  = string,            -- 高亮区域 key（注册到 TutorialOverlay 的热点）
--         advanceOn  = string,            -- 触发进入下一步的事件（"click_highlight" / "enter_panel" / nil=手动）
--       }
--     }
--   }
--
-- highlight key 对照表（由各 UI 模块调用 TutorialOverlay.registerHotspot() 注册）：
--   "tab_character"          — 底部导航栏角色按钮
--   "tab_log"                — 底部导航栏日志按钮
--   "tab_town"               — 底部导航栏城镇按钮
--   "character_slot_1"       — 角色面板第一个槽位中的角色
--   "equip_slot_weapon"      — 角色详情武器槽位
--   "equip_btn_equip"        — 装备详情「装备」按钮
--   "equip_btn_auto"         — 角色详情「一键装备」按钮
--   "building_church"        — 城镇教堂建筑
--   "building_tavern"        — 城镇酒馆建筑
--   "building_smith"         — 城镇铁匠铺建筑
--   "building_arena"         — 城镇竞技场建筑
--   "talent_toggle"          — 天赋滑块按钮
--   "talent_node_area"       — 天赋节点整体区域
--   "tavern_btn_gacha10"     — 酒馆十连抽按钮
--   "character_new_hero"     — 角色面板新角色位置
--   "smith_btn_enhance"      — 铁匠铺强化按钮
--   "arena_btn_start"        — 竞技场「开始对战」按钮
--   "arena_opponent_1"       — 竞技场第一位对手挑战按钮
--   "building_guild"         — 城镇冒险者公会建筑
--   "relic_tab"              — 公会页面遗物标签按钮
--   "relic_bag_btn"          — 遗物面板背包按钮
-- ============================================================================

local TutorialConfig = {}

-- ─── 引导组 1 ───
-- 触发：情景5/6/7（首通0101）结束后
-- 解锁：角色面板
TutorialConfig[1] = {
    triggerScenarios = { 5, 6, 7 },
    unlocks = { "character_panel" },
    steps = {
        {
            text      = "前往角色页面查看角色",
            highlight = "tab_character",
            advanceOn = "enter_panel_character",
        },
        {
            text      = "点击角色查看详情",
            highlight = "character_slot_1",
            advanceOn = "click_highlight",
        },
        {
            text      = "快来点击武器槽位来为角色装备新武器吧！",
            highlight = "equip_slot_weapon",
            advanceOn = "click_highlight",
        },
        {
            text      = "点击武器来查看属性",
            highlight = "equip_item_gifted",
            advanceOn = "click_highlight",
        },
        {
            text      = "点击装备按钮进行装备",
            highlight = "equip_btn_equip",
            advanceOn = "click_highlight",
        },
    },
}

-- ─── 引导组 2 ───
-- 触发：情景8/9/10（首通0102）结束后
TutorialConfig[2] = {
    triggerScenarios = { 8, 9, 10 },
    steps = {
        {
            text      = "又掉落了新装备",
            highlight = "tab_character",
            advanceOn = "enter_panel_character",
        },
        {
            text      = "点击角色查看详情",
            highlight = "character_slot_1",
            advanceOn = "click_highlight",
        },
        {
            text      = "这次试试一键装备吧！",
            highlight = "equip_btn_auto",
            advanceOn = "click_highlight",
        },
    },
}

-- ─── 引导组 3 ───
-- 触发：情景17/18/19（首通0104）结束后
-- 解锁：日志面板
TutorialConfig[3] = {
    triggerScenarios = { 17, 18, 19 },
    unlocks = { "log_panel" },
    steps = {
        {
            text      = "点击日志来看看有什么奖励可以领取的吧！",
            highlight = "tab_log",
            advanceOn = "click_highlight",
        },
    },
}

-- ─── 引导组 4 ───
-- 触发：情景20/21/22（首通0105）结束后
-- 解锁：城镇面板
TutorialConfig[4] = {
    triggerScenarios = { 20, 21, 22 },
    unlocks = { "town_panel" },
    steps = {
        {
            text      = "来看看城镇都有些什么吧！",
            highlight = "tab_town",
            advanceOn = "enter_panel_town",
        },
    },
}

-- ─── 引导组 5 ───
-- 触发：情景24/25/26（进入城镇后英雄分支）结束后
-- 兼容触发：情景23（卫兵拦截主线），用于英雄分支已被旧存档 claim 的玩家
-- 解锁：教堂
TutorialConfig[5] = {
    triggerScenarios = { 24, 25, 26 },
    unlocks = { "church" },
    steps = {
        {
            text      = "那就先前往教堂看看吧",
            highlight = "building_church",
            advanceOn = "click_highlight",
        },
    },
}

-- ─── 引导组 6 ───
-- 触发：情景27（教堂入场）结束后
TutorialConfig[6] = {
    triggerScenarios = { 27 },
    steps = {
        {
            text      = "点击天赋页面，来学习天赋吧",
            highlight = "talent_toggle",
            advanceOn = "click_highlight",
        },
        {
            text      = "尝试点击来学习任意的天赋点",
            highlight = "talent_node_area",
            advanceOn = "click_highlight",
        },
    },
}

-- ─── 引导组 7 ───
-- 触发：情景28/29/30（离开教堂英雄分支）结束后
-- 解锁：酒馆
TutorialConfig[7] = {
    triggerScenarios = { 28, 29, 30 },
    unlocks = { "tavern" },
    steps = {
        {
            text      = "进入酒馆瞧瞧吧！",
            highlight = "building_tavern",
            advanceOn = "click_highlight",
        },
    },
}

-- ─── 引导组 8 ───
-- 触发：情景31（酒馆入场）结束后
TutorialConfig[8] = {
    triggerScenarios = { 31 },
    steps = {
        {
            text      = "来试试能否招募到其他冒险伙伴吧",
            highlight = "tavern_btn_gacha10",
            advanceOn = "click_highlight",
        },
        {
            -- 无界面步骤：等待招募结果返回后结束引导，确保 newHeroId 已设置
            -- 同时阻止玩家在招募请求进行中离开酒馆（配合 TavernPage pendingGachaPull 检查）
            advanceOn = "gacha10_complete",
            invisible = true,
        },
    },
}

-- ─── 引导组 9 ───
-- 触发：情景32/33/34（离开酒馆英雄分支）结束后
TutorialConfig[9] = {
    triggerScenarios = { 32, 33, 34 },
    steps = {
        {
            text      = "前往角色页面",
            highlight = "tab_character",
            advanceOn = "enter_panel_character",
        },
        {
            text      = "将新角色拖入槽位3上阵吧",
            highlight = "character_new_hero",
            advanceOn = "drag_to_slot_3",
        },
    },
}

-- ─── 引导组 10 ───
-- 触发：情景44/45/46（首通0204）结束后
-- 解锁：铁匠铺
TutorialConfig[10] = {
    triggerScenarios = { 44, 45, 46 },
    unlocks = { "smith" },
    steps = {
        {
            text      = "前往城镇",
            highlight = "tab_town",
            advanceOn = "enter_panel_town",
        },
        {
            text      = "前往铁匠铺",
            highlight = "building_smith",
            advanceOn = "click_highlight",
        },
    },
}

-- ─── 引导组 11 ───
-- 触发：情景47（铁匠铺入场）结束后
TutorialConfig[11] = {
    triggerScenarios = { 47 },
    steps = {
        {
            text      = "点击强化按钮",
            highlight = "smith_btn_enhance",
            advanceOn = "click_highlight",
        },
    },
}

-- ─── 引导组 12 ───
-- 触发：情景51/52/53（首通0205）结束后
-- 解锁：竞技场
TutorialConfig[12] = {
    triggerScenarios = { 51, 52, 53 },
    unlocks = { "arena" },
    steps = {
        {
            text      = "前往城镇",
            highlight = "tab_town",
            advanceOn = "enter_panel_town",
        },
        {
            text      = "前往竞技场",
            highlight = "building_arena",
            advanceOn = "click_highlight",
        },
    },
}

-- ─── 引导组 13 ───
-- 触发：情景54（竞技场入场）结束后
TutorialConfig[13] = {
    triggerScenarios = { 54 },
    steps = {
        {
            text      = "点击开始对战按钮进行挑战",
            highlight = "arena_btn_start",
            advanceOn = "click_highlight",
        },
        -- 第二步已移除：不再强制挑战第一个对手，改为让玩家自行挑选对手
    },
}

-- ─── 引导组 14 ───
-- 触发：情景55/56/57（首通1305）结束后
-- 解锁：冒险者公会
TutorialConfig[14] = {
    triggerScenarios = { 55, 56, 57 },
    unlocks = { "guild" },
    steps = {
        {
            text      = "前往城镇",
            highlight = "tab_town",
            advanceOn = "enter_panel_town",
        },
        {
            text      = "进入冒险者公会",
            highlight = "building_guild",
            advanceOn = "enter_panel_guild",
        },
        {
            text      = "点击遗物标签",
            highlight = "relic_tab",
            advanceOn = "enter_relic_panel",
        },
        {
            text      = "打开遗物背包",
            highlight = "relic_bag_btn",
            advanceOn = "click_highlight",
        },
    },
}

-- ─── 引导组 15 ───
-- 触发：情景58/59/60（首通0305）结束后
-- 解锁：副本面板
TutorialConfig[15] = {
    triggerScenarios = { 58, 59, 60 },
    unlocks = { "dungeon_panel" },
    steps = {
        {
            text      = "前往副本",
            highlight = "tab_dungeon",
            advanceOn = "enter_panel_dungeon",
        },
        {
            text      = "挑战黄金矿洞",
            highlight = "dungeon_gold_mine",
            advanceOn = "click_highlight",
        },
    },
}

--- 构建情景ID → 引导组ID 的反向映射
--- @type table<number, number>  scenarioId → groupId
TutorialConfig.SCENARIO_TO_GROUP = {}
for groupId, group in pairs(TutorialConfig) do
    if type(group) == "table" and group.triggerScenarios then
        for _, sid in ipairs(group.triggerScenarios) do
            ---@diagnostic disable-next-line: assign-type-mismatch
            TutorialConfig.SCENARIO_TO_GROUP[sid] = groupId
        end
    end
end

-- 兼容映射：情景23（卫兵拦截主线）结束后也触发引导组5（教堂解锁）
-- triggerScenarios 不含23，保证 isGroupCompleted(5) 仍以24/25/26为准
-- 适用于英雄分支24/25/26已被旧存档 claim 的玩家
TutorialConfig.SCENARIO_TO_GROUP[23] = 5

return TutorialConfig
