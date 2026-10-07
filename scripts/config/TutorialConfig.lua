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
--         advanceOn  = string,            -- 点击或真实业务事件推进
--         pointerTarget = boolean|nil,    -- 业务事件步骤仅放行目标热点，不把点击当成功
--       }
--     }
--   }
--
-- highlight key 对照表（由各 UI 模块调用 TutorialOverlay.registerHotspot() 注册）：
--   "battle_hero_detail"     — 小队1存活己方战斗卡（屏幕逻辑坐标）
--   "character_slot_1"       — 右栏小队1首个已上阵头像
--   "equip_slot_weapon"      — 角色详情武器槽位
--   "equip_item_gifted"      — 左栏仓库首个可见、可穿戴的武器候选
--   "equip_btn_auto"         — 角色详情「一键装备」按钮
--   "building_church"        — 城镇教堂建筑
--   "building_tavern"        — 城镇酒馆建筑
--   "building_smith"         — 城镇铁匠铺建筑
--   "talent_toggle"          — 天赋滑块按钮
--   "talent_node_area"       — 天赋节点整体区域
--   "tavern_btn_gacha10"     — 酒馆十连抽按钮
--   "character_new_hero"     — 角色面板新角色位置
--   "smith_btn_enhance"      — 铁匠铺强化按钮
--   "building_guild"         — 城镇亡誓公会建筑
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
            text      = "点击战斗中的己方角色卡，打开角色详情",
            highlight = "battle_hero_detail",
            advanceOn = "character_detail_opened",
            entrySource = "battle",
            pointerTarget = true,
        },
        {
            text      = "快来点击武器槽位来为角色装备新武器吧！",
            highlight = "equip_slot_weapon",
            advanceOn = "click_highlight",
        },
        {
            text      = "双击或右键点击左侧仓库中的武器，为角色快捷穿戴",
            highlight = "equip_item_gifted",
            advanceOn = "equipment_equipped",
        },
    },
}

-- ─── 引导组 2 ───
-- 触发：情景8/9/10（首通0102）结束后
TutorialConfig[2] = {
    triggerScenarios = { 8, 9, 10 },
    steps = {
        {
            text      = "又掉落了新装备，点击右侧队伍头像打开角色详情",
            highlight = "character_slot_1",
            advanceOn = "character_detail_opened",
            entrySource = "avatar",
            pointerTarget = true,
        },
        {
            text      = "这次试试一键装备吧！",
            highlight = "equip_btn_auto",
            advanceOn = "equipment_equipped",
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
            text      = "点击左侧「酒馆」，看看如何招募新的远征伙伴；打开酒馆后继续",
            highlight = "building_tavern",
            advanceOn = "enter_tavern",
            pointerTarget = true,
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
            text      = "点击终焉古树，来学习天赋吧",
            highlight = "talent_toggle",
            advanceOn = "click_highlight",
        },
        {
            text      = "尝试点击来学习任意的远征点",
            highlight = "talent_node_area",
            advanceOn = "talent_learned",
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
            text      = "来试试能否招募到其他远征伙伴吧",
            highlight = "tavern_btn_gacha10",
            advanceOn = "gacha10_started",
        },
        {
            -- 无界面步骤：等待真实招募结果；本次新增目标持久排队后才衔接组9。
            -- 招募请求或结果动画在途时不切页面（TavernPage.isRecruitBusy）。
            advanceOn = "gacha10_complete",
            invisible = true,
        },
    },
}

-- ─── 引导组 9 ───
-- 触发：首次成功招募结果后自动衔接；保留情景32/33/34的旧档兼容入口
TutorialConfig[9] = {
    triggerScenarios = { 32, 33, 34 },
    steps = {
        {
            text      = "将新角色拖入右侧小队1的槽位4（后卫）上阵吧",
            highlight = "character_new_hero",
            advanceOn = "drag_to_slot_4",
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


-- ─── 引导组 14 ───
-- 触发：情景55/56/57（首通1305）结束后
-- 解锁：亡誓公会
TutorialConfig[14] = {
    -- [横屏接线 0928] 亡誓公会页(GuildPage)已在去多人化重构中删除，
    -- building_guild/relic_tab 热点与 enter_panel_guild/enter_relic_panel 事件均无注册方，
    -- 触发会永久卡屏。标记 disabled 由 startGroupInternal 跳过（保留配置以便公会功能回归时复用）
    disabled = true,
    triggerScenarios = { 55, 56, 57 },
    unlocks = { "guild" },
    steps = {
        {
            text      = "进入亡誓公会",
            highlight = "building_guild",
            advanceOn = "enter_panel_guild",
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
            text      = "点击右侧1-1关卡，进入黄金矿洞",
            highlight = "dungeon_gold_mine",
            advanceOn = "enter_gold_mine",
            pointerTarget = true,
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
