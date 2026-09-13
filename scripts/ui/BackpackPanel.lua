-- ============================================================================
-- BackpackPanel - 背包面板（道具/装备 切换）
-- 全屏面板：顶部背景 + 标题框 + 九宫格下方面板 + 可滚动网格 + 底部返回&Tab
-- 坐标系: 设计分辨率 1080x2400，所有位置为中心点坐标
-- ============================================================================

local GameConfig       = require("config.GameConfig")
local EquipmentConfig  = require("config.EquipmentConfig")
local DrawUtil         = require("core.DrawUtil")
local DarkIcon         = require("core.DarkIcon")  -- [暗黑化 P1] 矢量九宫格
local GameState        = require("core.GameState")
local PlayerStore      = require("client.data.PlayerStore")
local ImageCache       = require("ui.ImageCache")
local NumberUtil       = require("core.NumberUtil")
local EquipmentSystem  = require("systems.EquipmentSystem")
local EquipmentDetail  = require("ui.EquipmentDetail")
local HeroConfig       = require("config.HeroConfig")
local HeroAssetUtil    = require("config.HeroAssetUtil")
local UrGachaConfig    = require("config.UrGachaConfig")
local CharacterPanel   = require("ui.CharacterPanel")
local Protocol         = require("shared.Protocol")
local BF               = require("systems.ButtonFeedback")

local Panel = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量 ========================

-- 1. 顶部背景图 UI_BB_BJ.png — 顶端对齐
local TOP_BG = {
    CX = 540, W = 1080, H = 728,
    CY = 728 * 0.5,  -- 364  (顶端对齐)
}

-- 2. 标题标签（一模一样复制教堂页面左上角标题样式）
--    背景图 UI_TJP_MC.png + 白色文字，无图标
local TITLE = {
    BG_CX = 147, BG_CY = 136, BG_W = 294, BG_H = 123,
    TEXT_CX = 148, TEXT_CY = 130, FONT_SIZE = 50,
    TEXT = "背包",
}

-- 3. 下方背景框 UI_TJP_1.png（九宫格）
local LOWER_PANEL = {
    CX = 540, CY = 1425, W = 1080, H = 1949,
    IT = 200, IR = 10, IB = 200, IL = 10,
}

-- 4. 标题装饰 UI_JJC_BTBJ
local DECO = {
    CX = 540, CY = 614, W = 660, H = 60,
}

-- 5. 网格区域标题文字 "装备"/"道具"（跟随当前 tab）
local GRID_TITLE = {
    X = 157, Y = 614,  -- 左对齐（与铁匠铺分解标题对齐）
    FONT_SIZE = 40,
    R = 0x45, G = 0x45, B = 0x45,
}

-- 5b. 品质筛选按钮（装备 tab 专用，与铁匠铺分解界面一致）
local PZSX = {
    FIRST_CX = 558, CY = 610, SIZE = 80, GAP = 23,
}

-- 6. 网格
local GRID = {
    CELL_SIZE = 160,
    CELL_RADIUS = 16,  -- [B-方案] 圆角收紧，贴合古卷硬朗感
    GAP = 30,
    COLS = 5,
    -- 5列列中心 X 坐标: 均匀分布在面板宽度内
    -- 总宽 = 5*160 + 4*30 = 920, 左边距 = (1080-920)/2 = 80
    MARGIN_LEFT = 80,
    -- 第一行顶部 Y
    FIRST_ROW_TOP = 670,
    -- 裁剪底部（上移为按钮留出空间）
    CLIP_BOTTOM = 2020,
}

-- 6b. 分解按钮区（装备 tab 专用，与铁匠铺分解按钮Y对齐）
local BTN_CONFIRM_DEC = {
    CX = 310, CY = 2129, W = 410, H = 100,
    TEXT_R = 0x6d, TEXT_G = 0x4c, TEXT_B = 0x1d,
}
local BTN_BATCH_DEC = {
    CX = 773, CY = 2129, W = 410, H = 100,
    TEXT_R = 0x25, TEXT_G = 0x55, TEXT_B = 0x3d,
}

-- 预计算列中心 X
local CELL_COL_CX = {}
for c = 1, GRID.COLS do
    CELL_COL_CX[c] = GRID.MARGIN_LEFT + (c - 1) * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5
end

-- 裁剪区域
local CLIP_TOP = GRID.FIRST_ROW_TOP
local CLIP_H   = GRID.CLIP_BOTTOM - CLIP_TOP

-- 7. 背包上限文字
local CAP_TEXT = {
    X = 540, Y = 2186,
    FONT_SIZE = 40,
    R = 0x45, G = 0x45, B = 0x45,
}
local BAG_MAX = EquipmentSystem.MAX_INVENTORY

-- 8. 返回按钮（与签到面板一致）
local BTN_BACK = {
    CX = 122, CY = 2308, W = 184, H = 143,
}

-- 9. Tab 栏（与签到面板一致）
local TAB = {
    BG_CX = 639, BG_CY = 2308, BG_W = 810, BG_H = 143,
    SLIDER_W = 410, SLIDER_H = 143,
    INSET_TOP = 10, INSET_BOTTOM = 10, INSET_LEFT = 70, INSET_RIGHT = 70,
    FONT_SIZE = 40,
    ACTIVE_R = 0x81, ACTIVE_G = 0x57, ACTIVE_B = 0x3c,
    INACTIVE_R = 255, INACTIVE_G = 255, INACTIVE_B = 255,
    ANIM_DUR = 0.35,
}

local TAB_ITEMS = {
    { key = "equip", name = "装备", cx = 439, cy = 2308, textX = 439, textY = 2302 },
    { key = "item",  name = "道具", cx = 839, cy = 2308, textX = 839, textY = 2302 },
}

-- 品质边框颜色：[B-方案] 统一引用 DarkIcon.QUALITY_TRIM 古卷色表（粗铁/青铜/秘银/符文/黄金/血钻）
local QUALITY_BORDER = DarkIcon.QUALITY_TRIM

-- [B-方案] 原空格平涂常量已废弃（空格子改用 DarkIcon.drawNine "slot" 暗铁凹槽）

-- 滚动参数
local SCROLL_FRICTION  = 0.90
local SCROLL_MIN_VEL   = 0.5
local SCROLL_WHEEL_STEP = 60

-- ======================== 缓动函数 ========================

local function easeInOutCubic(t)
    if t < 0.5 then return 4 * t * t * t end
    local f = 2 * t - 2; return 0.5 * f * f * f + 1
end

-- ======================== 资源道具定义 ========================

-- key → { iconPath, quality, name, source, desc, getter }
local ITEM_DEFS = {
    { key = "gold",          iconPath = "image/UI_icon_JB.png",     quality = 2, name = "金币",       source = "击杀/通关/任务",         desc = "强化武器，购买资源",                                       getter = function() return GameState.getGold() end },
    { key = "gems",          iconPath = "image/UI_icon_SJ.png",     quality = 5, name = "钻石",       source = "成就/首通/活动",         desc = "酒馆招募抽卡",                                             getter = function() return GameState.getGems() end },
    { key = "essence",       iconPath = "image/UI_icon_JC.png",     quality = 2, name = "精粹",       source = "分解装备获得",           desc = "用于洗练装备",                                             getter = function() return GameState.getEssence() end },
    { key = "enhanceStone",  iconPath = "image/UI_icon_QH_1.png",   quality = 3, name = "洗练石",     source = "市场购买/任务",          desc = "洗练时使用可以只洗练数值高低，不洗练属性",                  getter = function() return GameState.getEnhanceStone() end },
    -- seq5 degradeStone 已隐藏，不在背包显示
    { key = "destroyStone",  iconPath = "image/UI_icon_QH_3.png",   quality = 5, name = "点金石",     source = "市场购买/任务",          desc = "洗练时使用可将装备升阶，最高升到史诗品质",                  getter = function() return GameState.getDestroyStone() end },
    { key = "weaponScroll",    iconPath = "image/UI_icon_JZ_WQ.png",  quality = 3, name = "武器卷轴",   source = "击杀/通关/任务",       desc = "强化装备时进行使用",                                       getter = function() return GameState.getWeaponScroll() end },
    { key = "offhandScroll",   iconPath = "image/UI_icon_JZ_FS.png",  quality = 3, name = "副手卷轴",   source = "击杀/通关/任务",       desc = "强化装备时进行使用",                                       getter = function() return GameState.getOffhandScroll() end },
    { key = "armorScroll",     iconPath = "image/UI_icon_JZ_HJ.png",  quality = 3, name = "护甲卷轴",   source = "击杀/通关/任务",       desc = "强化装备时进行使用",                                       getter = function() return GameState.getArmorScroll() end },
    { key = "accessoryScroll", iconPath = "image/UI_icon_JZ_SP.png",  quality = 3, name = "饰品卷轴",   source = "击杀/通关/任务",       desc = "强化装备时进行使用",                                       getter = function() return GameState.getAccessoryScroll() end },
    { key = "recruitTicket", iconPath = "image/UI_icon_ZMQ_1.png",  quality = 5, name = "冒险招募券", source = "市场/活动/福利",         desc = "酒馆常规招募抽卡",                                       getter = function() return GameState.getRecruitTicket() end },
    { key = "stellarRecruitTicket", iconPath = "image/UI_icon_ZMQ_2.png", quality = 6, name = "星辉招募券", source = "活动/福利", desc = "酒馆星辉招募抽卡", getter = function() return GameState.getStellarRecruitTicket() end },
    { key = "goldenKey", iconPath = "image/UI_icon_HJYS.png", quality = 6, name = "黄金钥匙", source = "首通奖励/市场购买", desc = "开启神器宝箱", getter = function() return GameState.getGoldenKey() end },
    { key = "sweepTicket",   iconPath = "image/UI_icon_SDQ.png",    quality = 4, name = "扫荡券",     source = "活动获得/看广告获得",    desc = "可以立即扫荡获得半小时的离线收益",                          getter = function() return GameState.getSweepTicket() end },
    { key = "arenaTicket",   iconPath = "image/UI_icon_JJCQ.png",   quality = 4, name = "竞技券",     source = "每日获得",              desc = "进行竞技场战斗",                                           getter = function() return GameState.getArenaTicket() end },
    { key = "arenaCoin",     iconPath = "image/UI_icon_JJB.png",    quality = 3, name = "竞技币",     source = "竞技场获得",            desc = "竞技场商店",                                               getter = function() return GameState.getArenaCoin() end },
    { key = "tavernCoin",    iconPath = "image/UI_icon_JGB.png",    quality = 3, name = "酒馆币",     source = "非UR满觉醒碎片分解",  desc = "在酒馆商店兑换自选",                                       getter = function() return GameState.getTavernCoin() end },
    { key = "privilegePoint",iconPath = "image/UI_icon_TQD.png",    quality = 4, name = "特权点",     source = "通过特权商店获得",      desc = "可以消耗掉来购买东西",                                     getter = function() return GameState.getPrivilegePoint() end },
    { key = "arcaneDust",    iconPath = "image/UI_icon_ASFC.png", quality = 3, name = "奥术粉尘",   source = "活动/任务获得",         desc = "用于遗物洗练消耗",                                         getter = function() return GameState.getArcaneDust() end },
    { key = "corruptStone",  iconPath = "image/UI_icon_FHS.png", quality = 3, name = "腐化石",     source = "关卡首通/活动/市场",      desc = "可将装备进行魔化，可能会发生预想不到的事情",                 getter = function() return GameState.getCorruptStone() end },
    { key = "sacredStone",   iconPath = "image/UI_icon_SSS.png", quality = 6, name = "神圣石",     source = "关卡首通/活动/市场",      desc = "可对已经被魔化的装备净化一次，使其去除魔化效果回到普通状态，每件装备只能被净化一次", getter = function() return GameState.getSacredStone() end },
    { key = "speedCard",     iconPath = "image/UI_icon_JSK.png",  quality = 5, name = "加速卡",     source = "市场购买获得",          desc = "提升20%在线挂机收益，包括金币/经验/装备等；获得时即刻开始生效，持续24小时。", getter = function() return GameState.getSpeedCardDisplayCount() end, amountTextGetter = function() return GameState.formatSpeedCardRemain() end, detailAmountTextGetter = function() return "剩余:" .. GameState.formatSpeedCardRemain() end, descGetter = function() return "提升20%在线挂机收益，包括金币/经验/装备等；当前剩余时间：" .. GameState.formatSpeedCardRemain() end },
    { key = "privilegeCard", iconPath = "image/UI_icon_TQK.png", quality = 6, name = "特权卡",     source = "通过活动获得",          desc = "1.每日赠送100个特权点\n2.特权商店每次重置进度时进度直接填满\n\n永久生效", getter = function() return GameState.getPrivilegeCardDisplayCount() end, amountTextGetter = function() return GameState.isPrivilegeCardOwned() and "已激活" or "未拥有" end, detailAmountTextGetter = function() return GameState.isPrivilegeCardOwned() and "已激活" or "未拥有" end },
}

-- ======================== 图片句柄 ========================

local imgTopBg    = -1  -- UI_BB_BJ.png
local imgTitleBg  = -1  -- UI_TJP_MC.png（标题背景，与教堂一致）
local imgDeco     = -1  -- UI_JJC_BTBJ.png（标题装饰）
local imgBtnBack  = -1  -- UI_AN_FH.png（返回按钮）
local imgTabBg    = -1  -- UI_AN_1.png（Tab 背景）

local imgBtnYellow = -1 -- UI_AN_HUANG.png（黄色按钮，碎片转化用）
local imgBtnGreen  = -1 -- UI_AN_LV.png（批量分解/确认分解按钮绿色）
local imgPzsx = {}       -- 品质筛选图标 1~5 (UI_ICON_PZSX_1~5)
local imgCheckmark = -1  -- UI_icon_GOU.png（选中勾选）

--- 分解模式状态（装备 tab 专用）
local decomposeState = {
    active = false,        -- 是否处于分解操作模式
    selectedItems = {},    -- [idx] = true
    pending = false,       -- 是否由背包页发起分解请求
}

-- 道具图标缓存
local itemIconCache = {}  -- [key] = nvgImage handle

-- 英雄头像角标缓存（与 EquipmentBag 一致）
local imgHeroIcons = {}   -- [heroId] = nvgImage handle
local imgLock = -1        -- 锁定角标 UI_ICON_SUO

-- imgShardIcon 已移至 DrawUtil.drawShardIcon 统一管理

-- 道具详情九宫格背景（品质 1-5）

-- NanoVG 上下文
local vg_ = nil

-- ======================== 道具详情状态 ========================

local itemDetState = {
    open      = false,
    def       = nil,    -- 选中的道具定义 (ITEM_DEFS entry)
    openTime  = 0,
    transferConfirmStep = 0,   -- 0=无, 1=第一次确认, 2=第二次确认
    transferConfirmOpenTime = 0,
    transferPending = false,   -- 转区请求进行中
    urConvertOpen = false,     -- UR碎片目标选择弹窗
    urConvertOpenTime = 0,
    urConvertPending = false,
}

-- 道具详情动画常量
local ITEM_DET_ANIM_DUR = 0.2

-- ======================== 碎片转酒馆币 ========================

-- 按钮布局（详情弹窗背景底边下方 18px，与装备详情「前往强化」按钮一致）
-- 背景: CY=1158, H=650 → 底边=1483, 按钮CY=1483+18+50=1551
local CONVERT_BTN = {
    CX = 540, CY = 1551, W = 410, H = 100,
    FONT_SIZE = 40,
}

local UR_CONVERT_BTN = {
    CX = 540, CY = 1551, W = 410, H = 100,
    FONT_SIZE = 40,
}

local UR_CONVERT_DAILY_LIMIT = 30
local UR_CONVERT_RESTORE_COST = 2
local UR_CONVERT_DIALOG = {
    BG_CX = 540, BG_CY = 1170, BG_W = 930, BG_H = 1150,
    TITLE_CX = 540, TITLE_CY = 650, TITLE_FONT = 54,
    INFO_CX = 540, INFO_CY = 760, INFO_FONT = 32,
    GRID_TOP = 840, CELL_SIZE = 118, GAP_X = 44, GAP_Y = 58, COLS = 4,
    CANCEL_CX = 540, CANCEL_CY = 1758, CANCEL_W = 410, CANCEL_H = 100,
    BTN_FONT = 40,
}

local function getUrConvertDailyRemain()
    local heroesData = PlayerStore.Get("heroes")
    local dayId = heroesData and math.floor(tonumber(heroesData.urShardConvertDayId) or 0) or 0
    local used = heroesData and math.max(0, math.floor(tonumber(heroesData.urShardConvertCount) or 0)) or 0
    local today = math.floor((os.time() + 28800) / 86400)
    if dayId ~= today then used = 0 end
    return math.max(0, UR_CONVERT_DAILY_LIMIT - used), used
end

local function isUrShardDef(def)
    if not def or not def.isShard or not def.heroId then return false end
    local cfg = HeroConfig.get(def.heroId)
    return cfg and tonumber(cfg.quality) == HeroConfig.QUALITY_UR
end

-- 特权卡转区按钮（与转化按钮同位置，互斥显示）
local TRANSFER_BTN = {
    CX = 540, CY = 1551, W = 410, H = 100,
    FONT_SIZE = 40,
}

-- 转区二次确认弹窗
local TRANSFER_CONFIRM = {
    BG_CX = 540, BG_CY = 1110, BG_W = 950, BG_H = 647,
    TITLE_CX = 540, TITLE_CY = 856, TITLE_FONT = 60, TITLE_SW = 6,
    TITLE_SR = 0x46, TITLE_SG = 0x2f, TITLE_SB = 0x20,
    BODY_CX = 540, BODY_CY = 1120, BODY_W = 820, BODY_FONT = 36,
    BODY_R = 0xb6, BODY_G = 0xb0, BODY_B = 0x9d,
    BTN_OK_CX = 770, BTN_CANCEL_CX = 310, BTN_CY = 1301, BTN_W = 410, BTN_H = 100,
    BTN_FONT = 40,
    BTN_OK_R = 0x64, BTN_OK_G = 0x51, BTN_OK_B = 0x29,
    BTN_CANCEL_R = 0x25, BTN_CANCEL_G = 0x55, BTN_CANCEL_B = 0x3d,
}

--- 判断英雄是否满觉醒
---@param heroId number
---@return boolean
local function isHeroFullyAwakened(heroId)
    local hero = CharacterPanel.getOwnedHero(heroId)
    if not hero or not hero.awakening then return false end
    local count = 0
    for _ in pairs(hero.awakening) do count = count + 1 end
    return count >= 7
end

--- 获取单枚碎片对应的酒馆币转化数量
---@param heroId number
---@return number
local function getShardCoinValue(heroId)
    return UrGachaConfig.getShardStardustValue(heroId)
end

-- ======================== 面板状态 ========================

local state = {
    open      = false,
    closing   = false,
    openTime  = 0,
    closeTime = 0,
    tab       = "equip",     -- "equip" | "item"
    tabFrom   = "equip",
    tabSwitchTime = 0,
    scrollY   = 0,
    scrollMax = 0,
    dragging  = false,
    lastDragY = 0,
    scrollVel = 0,
}

-- 开关动画参数（与 BlacksmithPage 一致）
local ANIM_OPEN_DUR  = 0.45
local ANIM_CLOSE_DUR = 0.38
local UPPER_SLIDE_DIST = 1200   -- 上半部分从屏幕上方滑入的距离
local LOWER_SLIDE_DIST = 1600   -- 下半部分从屏幕下方滑入的距离

local function easeOutCubic(t)
    local u = 1 - t; return 1 - u * u * u
end

local function easeInCubic(t)
    return t * t * t
end

-- ======================== 辅助函数 ========================

local function getTabIndex(key)
    for i, item in ipairs(TAB_ITEMS) do
        if item.key == key then return i end
    end
    return 1
end

--- 获取道具图标（缓存）
local function getItemIcon(def)
    local cached = itemIconCache[def.key]
    if cached then return cached end
    if not vg_ then return -1 end
    local handle = nvgCreateImage(vg_, def.iconPath, 0)
    itemIconCache[def.key] = handle
    return handle
end
--- 获取背包装备列表（排序: 品质降→等级降）
--- 包含 equippedByHeroId 和 enhanceLevel 字段（与 EquipmentBag 一致）
local function getEquipList()
    local equipData = PlayerStore.Get("equipment")
    if not equipData or not equipData.inventory then return {} end

    -- 构建全局归属映射: seq → heroId
    local equippedByHero = {}  -- [seqStr] = heroId
    if equipData.equipped then
        for hid, heroSlots in pairs(equipData.equipped) do
            if type(heroSlots) == "table" then
                for _, eqSeq in pairs(heroSlots) do
                    equippedByHero[tostring(eqSeq)] = hid
                end
            end
        end
    end

    local list = {}
    for seqStr, equip in pairs(equipData.inventory) do
        local tpl = EquipmentConfig.ITEMS[equip.templateId]
        if tpl then
            list[#list + 1] = {
                seq = tonumber(seqStr) or 0,
                templateId = equip.templateId,
                level = equip.level or 1,
                quality = equip.quality or tpl.quality or 1,
                name = tpl.name or "",
                type = equip.type or tpl.type or "",
                enhanceLevel = equip.enhanceLevel or 0,
                equippedByHeroId = equippedByHero[seqStr] or nil,
                locked = equip.locked or nil,
            }
        end
    end

    -- 排序: 品质降 → 等级降
    table.sort(list, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.level > b.level
    end)

    return list
end

--- 获取背包物品数量（装备数）
local function getInventoryCount()
    local equipData = PlayerStore.Get("equipment")
    if not equipData or not equipData.inventory then return 0 end
    local count = 0
    for _ in pairs(equipData.inventory) do count = count + 1 end
    return count
end

--- 计算网格行数和滚动最大值
local function calcScrollMax(totalItems)
    local rows = math.ceil(totalItems / GRID.COLS)
    local contentH = rows * GRID.CELL_SIZE + math.max(0, rows - 1) * GRID.GAP
    local maxScroll = math.max(0, contentH - CLIP_H)
    return maxScroll
end

local function clampScroll()
    state.scrollY = math.max(0, math.min(state.scrollMax, state.scrollY))
end

-- ======================== 绘制: 装备 tab ========================

local function drawEquipGrid(vg)
    local equipList = getEquipList()
    local totalSlots = math.max(#equipList, 10)  -- 至少显示 10 个格子
    state.scrollMax = calcScrollMax(totalSlots)
    clampScroll()

    nvgSave(vg)
    nvgScissor(vg, 0, CLIP_TOP, DESIGN_W, CLIP_H)
    nvgTranslate(vg, 0, -state.scrollY)

    for idx = 1, totalSlots do
        local col = ((idx - 1) % GRID.COLS) + 1
        local row = math.floor((idx - 1) / GRID.COLS)
        local cx = CELL_COL_CX[col]
        local cy = GRID.FIRST_ROW_TOP + row * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5

        -- 跳过不可见区域（cy 是 translate 前的坐标，减去 scrollY 得到屏幕坐标）
        local screenY = cy - state.scrollY

        -- 新手引导热点：第一个有装备的格子（在可见性裁剪前注册，确保不被 goto 跳过）
        if idx == 1 then
            local _TM = require("systems.TutorialManager")
            if _TM.isActive() then
                _TM.registerHotspot("equip_item_gifted", cx, screenY, GRID.CELL_SIZE, GRID.CELL_SIZE)
            end
        end

        if screenY < CLIP_TOP - GRID.CELL_SIZE then
            goto continue_equip
        end
        if screenY > GRID.CLIP_BOTTOM + GRID.CELL_SIZE then
            break  -- 后续行更远，全部不可见
        end

        local equip = equipList[idx]
        if equip then
            -- 品质背景 [暗黑化 P2-A] 矢量品质框（原 ZBBJ 贴图+fallback 已废弃）
            DarkIcon.drawQualityBg(vg, equip.quality, cx, cy, GRID.CELL_SIZE, GRID.CELL_SIZE, 1.0)

            -- 装备图标
            local icon = ImageCache.getEquipIcon(equip.templateId)
            if icon and icon >= 0 then
                DarkIcon.drawIconDark(vg, icon, cx, cy, GRID.CELL_SIZE - 10, GRID.CELL_SIZE - 10, 1.0)  -- [暗黑化 P2-B]
            end

            -- 等级角标（右下角，16方向描边，与 EquipmentBag 一致）
            do
                local lvlText = "Lv." .. (equip.level or 1)
                local lvlX = cx + GRID.CELL_SIZE * 0.5 - 8
                local lvlY = cy + GRID.CELL_SIZE * 0.5 - 6
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 40)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                -- 黑色描边 16方向
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                local sStep = math.pi * 2 / 16
                for si = 0, 15 do
                    local sa = si * sStep
                    nvgText(vg, lvlX + math.cos(sa) * 4, lvlY + math.sin(sa) * 4, lvlText, nil)
                end
                -- 白色填充
                nvgFillColor(vg, nvgRGBA(0xff, 0xff, 0xff, 255))
                nvgText(vg, lvlX, lvlY, lvlText, nil)
            end

            -- 强化角标（右上角，+X，与 EquipmentBag 一致）
            if equip.enhanceLevel and equip.enhanceLevel > 0 then
                local enhText = "+" .. equip.enhanceLevel
                local enhX = cx + GRID.CELL_SIZE * 0.5 - 8
                local enhY = cy - GRID.CELL_SIZE * 0.5 + 8
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 36)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                -- 黑色描边 16方向
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                local sStep = math.pi * 2 / 16
                for si = 0, 15 do
                    local sa = si * sStep
                    nvgText(vg, enhX + math.cos(sa) * 3, enhY + math.sin(sa) * 3, enhText, nil)
                end
                -- 绿色填充
                nvgFillColor(vg, nvgRGBA(0x00, 0xff, 0x60, 255))
                nvgText(vg, enhX, enhY, enhText, nil)
            end

            -- 左上角英雄头像角标（与 EquipmentBag 一致）
            if equip.equippedByHeroId then
                local ownerIcon = imgHeroIcons[equip.equippedByHeroId]
                if ownerIcon and ownerIcon >= 0 then
                    local badgeSize = 66
                    local badgeX = cx - GRID.CELL_SIZE * 0.5 + badgeSize * 0.5 + 1
                    local badgeY = cy - GRID.CELL_SIZE * 0.5 + badgeSize * 0.5 + 1
                    -- 圆形裁剪绘制头像
                    nvgSave(vg)
                    nvgBeginPath(vg)
                    nvgCircle(vg, badgeX, badgeY, badgeSize * 0.5)
                    nvgFillPaint(vg, nvgImagePattern(vg, badgeX - badgeSize * 0.5, badgeY - badgeSize * 0.5, badgeSize, badgeSize, 0, ownerIcon, 1.0))
                    nvgFill(vg)
                    -- 白色圆形描边
                    nvgBeginPath(vg)
                    nvgCircle(vg, badgeX, badgeY, badgeSize * 0.5)
                    nvgStrokeColor(vg, nvgRGBA(0xff, 0xff, 0xff, 200))
                    nvgStrokeWidth(vg, 2)
                    nvgStroke(vg)
                    nvgRestore(vg)
                end
            end

            -- 分解选中遮罩（与铁匠铺分解面板一致：黑色半透明 + 勾选图标）
            if decomposeState.active and decomposeState.selectedItems[idx] then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx - GRID.CELL_SIZE * 0.5, cy - GRID.CELL_SIZE * 0.5,
                    GRID.CELL_SIZE, GRID.CELL_SIZE, GRID.CELL_RADIUS)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
                nvgFill(vg)
                DrawUtil.drawImageCentered(vg, imgCheckmark, cx, cy, 80, 80, 1.0)
            end

            -- 锁定角标：未装备→左上角（与铁匠铺一致）；已装备→左下角避让头像角标
            if equip.locked and imgLock >= 0 then
                local lockSize = 56
                local lockX = cx - GRID.CELL_SIZE * 0.5 + lockSize * 0.5 + 4
                local lockY
                if equip.equippedByHeroId then
                    lockY = cy + GRID.CELL_SIZE * 0.5 - lockSize * 0.5 - 4
                else
                    lockY = cy - GRID.CELL_SIZE * 0.5 + lockSize * 0.5 + 4
                end
                DrawUtil.drawImageCentered(vg, imgLock, lockX, lockY, lockSize, lockSize, 1.0)
            end
        else
            -- 空格子：暗铁凹槽底（[B-方案] 古卷化，顶部高光+描边材质感）
            DarkIcon.drawNine(vg, "slot", cx - GRID.CELL_SIZE * 0.5, cy - GRID.CELL_SIZE * 0.5,
                GRID.CELL_SIZE, GRID.CELL_SIZE, { radius = GRID.CELL_RADIUS })
        end
        ::continue_equip::
    end

    nvgRestore(vg)
end

-- ======================== 绘制: 道具 tab ========================

--- 构建道具列表（静态资源 + 动态碎片）
local function buildItemList()
    -- 先复制静态道具（跳过持有量为 0 的）
    local list = {}
    for _, def in ipairs(ITEM_DEFS) do
        local count = def.getter and def.getter() or 0
        if count > 0 then
            list[#list + 1] = def
        end
    end
    -- 追加拥有碎片的英雄碎片条目
    local HC = HeroConfig
    local qualityToGridQuality = { [1] = 1, [2] = 3, [3] = 5, [4] = 6 }
    for _, heroId in ipairs(HC.getAllIds()) do
        local shards = CharacterPanel.getShards(heroId)
        if shards > 0 then
            local heroCfg = HC.get(heroId)
            local heroName = heroCfg and heroCfg.name or ("英雄" .. heroId)
            local heroQuality = heroCfg and heroCfg.quality or 1
            local gridQuality = qualityToGridQuality[heroQuality] or 1
            local hid = heroId  -- 闭包捕获
            list[#list + 1] = {
                key = "shard_" .. heroId,
                quality = gridQuality,
                name = heroName .. "碎片",
                source = "抽卡获得",
                desc = "用于激活冒险家或进行冒险家觉醒",
                isShard = true,
                heroId = heroId,
                getter = function() return CharacterPanel.getShards(hid) end,
            }
        end
    end
    return list
end

local function drawItemGrid(vg)
    local itemList = buildItemList()
    local totalSlots = #itemList
    state.scrollMax = calcScrollMax(totalSlots)
    clampScroll()

    nvgSave(vg)
    nvgScissor(vg, 0, CLIP_TOP, DESIGN_W, CLIP_H)
    nvgTranslate(vg, 0, -state.scrollY)

    for idx, def in ipairs(itemList) do
        local col = ((idx - 1) % GRID.COLS) + 1
        local row = math.floor((idx - 1) / GRID.COLS)
        local cx = CELL_COL_CX[col]
        local cy = GRID.FIRST_ROW_TOP + row * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5

        -- 品质背景 [暗黑化 P2-A] 矢量品质框
        DarkIcon.drawQualityBg(vg, def.quality, cx, cy, GRID.CELL_SIZE, GRID.CELL_SIZE, 1.0)

        -- 道具图标
        if def.isShard and def.heroId then
            -- 碎片条目：英雄头像主图标 + 碎片角标（统一框架）
            DrawUtil.drawShardIcon(vg, def.heroId, cx, cy, GRID.CELL_SIZE - 10, 1.0)
        else
            local icon = getItemIcon(def)
            if icon and icon >= 0 then
                DrawUtil.drawImageCentered(vg, icon, cx, cy, GRID.CELL_SIZE - 10, GRID.CELL_SIZE - 10, 1.0)
            end
        end

        -- 数量角标（右下角，16方向描边，与奖励面板一致）
        local amount = def.getter()
        if amount and amount > 0 then
            local amtText = def.amountTextGetter and def.amountTextGetter() or ("×" .. NumberUtil.format(amount))
            local amtX = cx + GRID.CELL_SIZE * 0.5 - 8
            local amtY = cy + GRID.CELL_SIZE * 0.5 - 8
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 40)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
            local sStep = math.pi * 2 / 16
            for si = 0, 15 do
                local sa = si * sStep
                nvgText(vg, amtX + math.cos(sa) * 4, amtY + math.sin(sa) * 4, amtText, nil)
            end
            nvgFillColor(vg, nvgRGBA(0xff, 0xff, 0xff, 255))
            nvgText(vg, amtX, amtY, amtText, nil)
        end
    end

    nvgRestore(vg)
end

-- ======================== 道具详情弹窗 ========================

--- NanoVG 手动换行绘制文本（nvgTextBox 对中文支持不稳定，手动逐字测量换行）
---@param vg any
---@param x number 左边距 X
---@param y number 首行 Y（基线 ALIGN_TOP）
---@param maxW number 最大行宽
---@param text string
---@param fontSize number
---@param r number 0-255
---@param g number 0-255
---@param b number 0-255
local function drawWrappedText(vg, x, y, maxW, text, fontSize, r, g, b)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(r, g, b, 255))

    -- 逐字符分割 UTF-8
    local chars = {}
    local i = 1
    local len = #text
    while i <= len do
        local b0 = string.byte(text, i)
        local charLen = 1
        if b0 >= 0xF0 then charLen = 4
        elseif b0 >= 0xE0 then charLen = 3
        elseif b0 >= 0xC0 then charLen = 2
        end
        chars[#chars + 1] = string.sub(text, i, i + charLen - 1)
        i = i + charLen
    end

    local lineY = y
    local lineHeight = fontSize * 1.4
    local lineStart = 1
    while lineStart <= #chars do
        -- 遇到换行符：直接换行
        if chars[lineStart] == "\n" then
            lineY = lineY + lineHeight
            lineStart = lineStart + 1
        else
            -- 尽可能多地放字符到一行（遇到 \n 也截断）
            local lineEnd = lineStart
            for ci = lineStart, #chars do
                if chars[ci] == "\n" then
                    lineEnd = ci - 1
                    break
                end
                local sub = table.concat(chars, "", lineStart, ci)
                local tw = nvgTextBounds(vg, 0, 0, sub)
                if tw > maxW and ci > lineStart then
                    lineEnd = ci - 1
                    break
                end
                lineEnd = ci
            end
            if lineEnd >= lineStart then
                local lineStr = table.concat(chars, "", lineStart, lineEnd)
                nvgText(vg, x, lineY, lineStr, nil)
            end
            lineY = lineY + lineHeight
            lineStart = lineEnd + 1
        end
    end
end

--- 是否显示特权卡转区按钮（多人模式且已激活特权卡）
---@param def table|nil
---@return boolean
local function shouldShowTransferBtn(def)
    if not def or def.key ~= "privilegeCard" then return false end
    if not PlayerStore.IsReady() then return false end
    return GameState.isPrivilegeCardOwned()
end

--- 绘制转区二次确认弹窗（step=1 或 2）
local function drawTransferConfirm(vg)
    local step = itemDetState.transferConfirmStep
    if step <= 0 then return end

    local C = TRANSFER_CONFIRM
    local title = step == 1 and "转区确认" or "再次确认"
    local body = step == 1
        and "确定要将特权卡转至其他区服吗？\n转区后您将立即退出当前区服。"
        or "特权卡将在您进入其他区服后生效（含挑战者服）。\n请勿选回原区服，否则将自动撤销转区。\n是否继续？"

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
    nvgFill(vg)

    DarkIcon.drawNine(vg, "plain",
        C.BG_CX - C.BG_W * 0.5, C.BG_CY - C.BG_H * 0.5,
        C.BG_W, C.BG_H)

    DrawUtil.drawTextStroke(vg, C.TITLE_CX, C.TITLE_CY, title,
        C.TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, C.TITLE_SW,
        { strokeColor = { C.TITLE_SR, C.TITLE_SG, C.TITLE_SB } })

    local bodyX = C.BODY_CX - C.BODY_W * 0.5
    local bodyY = C.BODY_CY - 60
    drawWrappedText(vg, bodyX, bodyY, C.BODY_W, body, C.BODY_FONT, C.BODY_R, C.BODY_G, C.BODY_B)

    if imgBtnYellow >= 0 then
        DrawUtil.drawImageCentered(vg, imgBtnYellow, C.BTN_OK_CX, C.BTN_CY, C.BTN_W, C.BTN_H, 1.0)
    end
    if imgBtnGreen >= 0 then
        DrawUtil.drawImageCentered(vg, imgBtnGreen, C.BTN_CANCEL_CX, C.BTN_CY, C.BTN_W, C.BTN_H, 1.0)
    end

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, C.BTN_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C.BTN_OK_R, C.BTN_OK_G, C.BTN_OK_B, 255))
    nvgText(vg, C.BTN_OK_CX, C.BTN_CY, "确认", nil)
    nvgFillColor(vg, nvgRGBA(C.BTN_CANCEL_R, C.BTN_CANCEL_G, C.BTN_CANCEL_B, 255))
    nvgText(vg, C.BTN_CANCEL_CX, C.BTN_CY, "取消", nil)
end

--- 关闭转区确认弹窗
local function closeTransferConfirm()
    itemDetState.transferConfirmStep = 0
    itemDetState.transferConfirmOpenTime = 0
end

local function closeUrConvertDialog()
    itemDetState.urConvertOpen = false
    itemDetState.urConvertOpenTime = 0
end

local function getUrConvertAmount(def)
    if not def or not def.getter then return 0 end
    local shardAmount = math.max(0, math.floor(tonumber(def.getter() or 0) or 0))
    local remain = getUrConvertDailyRemain()
    return math.min(shardAmount, remain)
end

local function buildUrConvertTargets(fromHeroId)
    local list = {}
    for _, heroId in ipairs(HeroConfig.getAllIds()) do
        if heroId ~= fromHeroId then
            local cfg = HeroConfig.get(heroId)
            if cfg and tonumber(cfg.quality) == HeroConfig.QUALITY_UR then
                list[#list + 1] = {
                    heroId = heroId,
                    name = cfg.name or ("英雄" .. heroId),
                    quality = cfg.quality or 1,
                    shards = CharacterPanel.getShards(heroId),
                }
            end
        end
    end
    return list
end

local function drawUrConvertDialog(vg)
    if not itemDetState.urConvertOpen then return end
    local def = itemDetState.def
    if not isUrShardDef(def) then return end

    local C = UR_CONVERT_DIALOG
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    DarkIcon.drawNine(vg, "panel",
        C.BG_CX - C.BG_W * 0.5, C.BG_CY - C.BG_H * 0.5,
        C.BG_W, C.BG_H, { titleH = 180 })

    DrawUtil.drawTextStroke(vg, C.TITLE_CX, C.TITLE_CY, "选择目标碎片",
        C.TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 5,
        { strokeColor = { 0x46, 0x2f, 0x20 } })

    local amount = getUrConvertAmount(def)
    local remain = getUrConvertDailyRemain()
    local info = "本次转化" .. tostring(amount) .. "个，今日剩余" .. tostring(remain) .. "/" .. tostring(UR_CONVERT_DAILY_LIMIT)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, C.INFO_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
    nvgText(vg, C.INFO_CX, C.INFO_CY, info, nil)

    local targets = buildUrConvertTargets(def.heroId)
    local totalW = C.COLS * C.CELL_SIZE + (C.COLS - 1) * C.GAP_X
    local startX = (DESIGN_W - totalW) * 0.5 + C.CELL_SIZE * 0.5
    for idx, item in ipairs(targets) do
        local col = ((idx - 1) % C.COLS) + 1
        local row = math.floor((idx - 1) / C.COLS)
        local cx = startX + (col - 1) * (C.CELL_SIZE + C.GAP_X)
        local cy = C.GRID_TOP + row * (C.CELL_SIZE + C.GAP_Y) + C.CELL_SIZE * 0.5
        if cy > C.CANCEL_CY - 110 then break end

        local gridQuality = ({ [1] = 1, [2] = 3, [3] = 5, [4] = 6 })[item.quality] or 1
        DarkIcon.drawQualityBg(vg, gridQuality, cx, cy, C.CELL_SIZE, C.CELL_SIZE, 1.0)  -- [暗黑化 P2-A]
        DrawUtil.drawShardIcon(vg, item.heroId, cx, cy, C.CELL_SIZE - 10, 1.0)
    end

    if imgBtnGreen >= 0 then
        DrawUtil.drawImageCentered(vg, imgBtnGreen, C.CANCEL_CX, C.CANCEL_CY, C.CANCEL_W, C.CANCEL_H, 1.0)
    end
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, C.BTN_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0x25, 0x55, 0x3d, 255))
    nvgText(vg, C.CANCEL_CX, C.CANCEL_CY, "取消", nil)
end

--- 绘制道具详情弹窗
local function drawItemDetail(vg)
    if not itemDetState.open then return end
    local def = itemDetState.def
    if not def then return end

    -- 动画进度（淡入+缩放）
    local elapsed = time.elapsedTime - itemDetState.openTime
    local t = math.min(1.0, elapsed / ITEM_DET_ANIM_DUR)
    local progress = 1 - (1 - t) * (1 - t) * (1 - t)  -- easeOutCubic
    local alpha = math.floor(255 * progress)

    -- 0. 全屏遮罩（纯黑 50%）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * progress)))
    nvgFill(vg)

    -- 缩放动画（从 0.8 到 1.0）
    local scale = 0.8 + 0.2 * progress
    nvgSave(vg)
    nvgTranslate(vg, 540, 1158)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -540, -1158)
    nvgGlobalAlpha(vg, progress)

    -- 1. 品质背景九宫格 X=540 Y=1158 530×650
    local q = math.min(def.quality or 1, 6)
    DarkIcon.drawNine(vg, "panel",
        540 - 530 * 0.5, 1158 - 650 * 0.5, 530, 650,
        { titleH = 400, accent = DarkIcon.QUALITY_ACCENTS[q] })

    -- 2. 道具名称 X左对齐317 Y893 字号40 白色 黑色描边4
    local itemName = def.name or ""
    DrawUtil.drawTextStroke(vg, 317, 893, itemName, 40,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4, nil)

    -- 3. 道具来源 X左对齐312 Y974 字号30 白色 无描边
    local itemSource = def.source or ""
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, 312, 974, itemSource, nil)

    -- 4. 道具图标 X629 Y1075 160×160
    if def.isShard and def.heroId then
        DrawUtil.drawShardIcon(vg, def.heroId, 629, 1075, 160, 1.0)
    else
        local icon = getItemIcon(def)
        if icon and icon >= 0 then
            DrawUtil.drawImageCentered(vg, icon, 629, 1075, 160, 160, 1.0)
        end
    end

    -- 5. 品质文字 X左对齐317 Y1129 字号30 品质颜色 黑色描边4
    local qualityName = ""
    local qualCfg = EquipmentConfig.QUALITY[q]
    if qualCfg then qualityName = qualCfg.name or "" end
    local qc = QUALITY_BORDER[q] or QUALITY_BORDER[1]
    DrawUtil.drawTextStroke(vg, 317, 1129, qualityName, 30,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        qc[1], qc[2], qc[3], 4, nil)

    -- 6. 持有数量 X左对齐317 Y1184 字号42 颜色#f7fe77 黑色描边4
    local amount = 0
    if def.getter then amount = def.getter() or 0 end
    local amountStr = def.detailAmountTextGetter and def.detailAmountTextGetter()
        or (def.amountTextGetter and def.amountTextGetter() or ("持有:" .. NumberUtil.format(amount)))
    DrawUtil.drawTextStroke(vg, 317, 1184, amountStr, 42,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        0xf7, 0xfe, 0x77, 4, nil)

    -- 7. 描述背景 X540 Y1333 460×176 圆角14 纯黑10%
    local descBgW, descBgH = 460, 176
    local descBgX = 540 - descBgW * 0.5  -- 310
    local descBgY = 1333 - descBgH * 0.5 -- 1245
    nvgBeginPath(vg)
    nvgRoundedRect(vg, descBgX, descBgY, descBgW, descBgH, 14)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 25))
    nvgFill(vg)

    -- 8. 描述文本 内间距20 字号34 颜色#725850
    local descText = def.descGetter and def.descGetter() or (def.desc or "")
    if #descText > 0 then
        local textX = descBgX + 20
        local textY = descBgY + 20
        local textMaxW = descBgW - 40
        drawWrappedText(vg, textX, textY, textMaxW, descText, 34, 0x72, 0x58, 0x50)
    end

    -- 9. 满觉醒碎片 → 酒馆币转化按钮（样式与装备详情「前往强化」一致）
    if def.isShard and def.heroId and not isUrShardDef(def) and isHeroFullyAwakened(def.heroId) then
        local coinValue = getShardCoinValue(def.heroId)
        if coinValue > 0 then
            -- 计算批量转化总收益
            local shardAmount = 0
            if def.getter then shardAmount = def.getter() or 0 end
            local totalCoin = coinValue * shardAmount
            -- 按钮背景（黄色图片，与「前往强化」一致）
            if imgBtnYellow >= 0 then
                DrawUtil.drawImageCentered(vg, imgBtnYellow,
                    CONVERT_BTN.CX, CONVERT_BTN.CY,
                    CONVERT_BTN.W, CONVERT_BTN.H, 1.0)
            end
            -- 按钮文字（黑色，与「前往强化」一致）
            local btnText = "转化酒馆币 +" .. totalCoin
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, CONVERT_BTN.FONT_SIZE)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))
            nvgText(vg, CONVERT_BTN.CX, CONVERT_BTN.CY, btnText, nil)
        end
    end

    -- 10. UR碎片转化按钮
    if isUrShardDef(def) then
        local amount = getUrConvertAmount(def)
        local remain = getUrConvertDailyRemain()
        if imgBtnYellow >= 0 then
            DrawUtil.drawImageCentered(vg, imgBtnYellow,
                UR_CONVERT_BTN.CX, UR_CONVERT_BTN.CY,
                UR_CONVERT_BTN.W, UR_CONVERT_BTN.H,
                itemDetState.urConvertPending and 0.55 or 1.0)
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, UR_CONVERT_BTN.FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, itemDetState.urConvertPending and 120 or 191))
        local btnText
        if itemDetState.urConvertPending then
            btnText = "处理中..."
        elseif amount > 0 then
            btnText = "转化为其他碎片"
        else
            btnText = "2点特权点恢复次数"
        end
        nvgText(vg, UR_CONVERT_BTN.CX, UR_CONVERT_BTN.CY, btnText, nil)

        nvgFontSize(vg, 28)
        nvgFillColor(vg, nvgRGBA(0x99, 0x92, 0x8a, 255))
        local hintText = amount > 0
            and ("今日剩余" .. tostring(remain) .. "/" .. tostring(UR_CONVERT_DAILY_LIMIT))
            or ("消耗" .. tostring(UR_CONVERT_RESTORE_COST) .. "点特权点恢复" .. tostring(UR_CONVERT_DAILY_LIMIT) .. "次")
        nvgText(vg, UR_CONVERT_BTN.CX, UR_CONVERT_BTN.CY + 70, hintText, nil)
    end

    -- 11. 特权卡转区按钮
    if shouldShowTransferBtn(def) then
        if imgBtnYellow >= 0 then
            DrawUtil.drawImageCentered(vg, imgBtnYellow,
                TRANSFER_BTN.CX, TRANSFER_BTN.CY,
                TRANSFER_BTN.W, TRANSFER_BTN.H,
                itemDetState.transferPending and 0.6 or 1.0)
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, TRANSFER_BTN.FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))
        nvgText(vg, TRANSFER_BTN.CX, TRANSFER_BTN.CY,
            itemDetState.transferPending and "转区中..." or "转区", nil)
    end

    nvgRestore(vg)

    drawTransferConfirm(vg)
    drawUrConvertDialog(vg)
end

-- ======================== Public API ========================

--- 初始化（加载图片资源）
---@param vg any NanoVG 上下文
function Panel.init(vg)
    vg_ = vg
    imgTopBg   = nvgCreateImage(vg, "image/UI_BB_BJ.png", 0)
    imgTitleBg = nvgCreateImage(vg, "image/UI_TJP_MC.png", 0)
    imgDeco    = nvgCreateImage(vg, "image/UI_JJC_BTBJ.png", 0)
    imgBtnBack = nvgCreateImage(vg, "image/UI_AN_FH.png", 0)
    imgTabBg   = nvgCreateImage(vg, "image/UI_AN_1.png", 0)
    -- [暗黑化 P1-B5] 原 image/UI_AN_2.png 贴图加载已移除（矢量绘制替代）
    imgBtnYellow = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    imgBtnGreen  = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    imgLock      = nvgCreateImage(vg, "image/UI_ICON_SUO.png", 0)
    imgCheckmark = nvgCreateImage(vg, "image/UI_icon_GOU.png", 0)
    -- 品质筛选图标
    for i = 1, 5 do
        imgPzsx[i] = nvgCreateImage(vg, "image/UI_ICON_PZSX_" .. i .. ".png", 0)
    end

    -- imgShardIcon 已移至 DrawUtil.drawShardIcon 统一管理

    -- 加载角色头像角标（与 EquipmentBag 一致）
    HeroAssetUtil.preloadIcons(vg, imgHeroIcons)

    ImageCache.init(vg)
    EquipmentDetail.init(vg)
    print("[BackpackPanel] init OK")
end

--- 打开面板
function Panel.open()
    state.open = true
    state.closing = false
    state.openTime = time.elapsedTime
    require("systems.GameSFX").playUIMove(1)
    state.tab = "equip"
    state.tabFrom = "equip"
    state.tabSwitchTime = 0
    state.scrollY = 0
    state.scrollMax = 0
    state.dragging = false
    state.scrollVel = 0
    -- 关闭道具详情
    itemDetState.open = false
    itemDetState.def = nil
    closeTransferConfirm()
    closeUrConvertDialog()
    itemDetState.transferPending = false
    itemDetState.urConvertPending = false
    print("[BackpackPanel] open")
end

--- 关闭面板
function Panel.close()
    if state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    state.dragging = false
    print("[BackpackPanel] close")
end

--- 是否打开
---@return boolean
function Panel.isOpen()
    return state.open
end

--- 返回打开/关闭动画进度 (0=完全关闭, 1=完全打开)
--- 用于 Client.lua 在动画期间渐变隐藏 TopBar/BottomNav
function Panel.getAnimProgress()
    if not state.open then return 0 end
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        local rawT = math.min(1.0, elapsed / ANIM_CLOSE_DUR)
        return 1 - easeInCubic(rawT)
    else
        local elapsed = time.elapsedTime - state.openTime
        local rawT = math.min(1.0, elapsed / ANIM_OPEN_DUR)
        return easeOutCubic(rawT)
    end
end

--- 更新（惯性滚动 + 关闭动画）
function Panel.update(dt)
    if not state.open then return end
    -- 关闭动画结束后真正关闭
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        if elapsed >= ANIM_CLOSE_DUR then
            state.open = false
            state.closing = false
            print("[BackpackPanel] closed (anim done)")
        end
        return
    end
    if not state.dragging and math.abs(state.scrollVel) > SCROLL_MIN_VEL then
        state.scrollY = state.scrollY + state.scrollVel
        state.scrollVel = state.scrollVel * SCROLL_FRICTION
        clampScroll()
    else
        state.scrollVel = 0
    end
end

--- 绘制
function Panel.draw(vg)
    if not state.open then return end

    -- === 动画进度计算（与 BlacksmithPage 一致） ===
    local progress, lowerProgress
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        local rawT = math.min(1.0, elapsed / ANIM_CLOSE_DUR)
        progress      = 1 - easeInCubic(rawT)
        lowerProgress = progress
    else
        local elapsed = time.elapsedTime - state.openTime
        local rawT = math.min(1.0, elapsed / ANIM_OPEN_DUR)
        progress      = easeOutCubic(rawT)
        lowerProgress = progress
    end

    local upperOY = -UPPER_SLIDE_DIST * (1 - progress)
    local lowerOY =  LOWER_SLIDE_DIST * (1 - lowerProgress)
    local overlayAlpha = math.floor(180 * progress)

    -- === 全屏暗色遮罩 ===
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha))
    nvgFill(vg)

    -- === 上半部分（从屏幕上方滑入）：顶部背景 + 标题 ===
    nvgSave(vg)
    nvgTranslate(vg, 0, upperOY)

    -- 1. 顶部背景图（顶端对齐）
    DrawUtil.drawImageCentered(vg, imgTopBg, TOP_BG.CX, TOP_BG.CY, TOP_BG.W, TOP_BG.H, 1.0)

    -- 3. 标题（与教堂左上角一致：背景图 + 白色文字，无描边）
    DrawUtil.drawImageCentered(vg, imgTitleBg, TITLE.BG_CX, TITLE.BG_CY, TITLE.BG_W, TITLE.BG_H, 1.0)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TITLE.FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, TITLE.TEXT_CX, TITLE.TEXT_CY, TITLE.TEXT, nil)

    nvgRestore(vg)

    -- === 下半部分（从屏幕下方滑入）：面板 + 内容 + Tab ===
    nvgSave(vg)
    nvgTranslate(vg, 0, lowerOY)

    -- 2. 下方背景框（九宫格）[暗黑化 P1: 矢量九宫格]
    DarkIcon.drawNine(vg, "panel",
        LOWER_PANEL.CX - LOWER_PANEL.W * 0.5, LOWER_PANEL.CY - LOWER_PANEL.H * 0.5,
        LOWER_PANEL.W, LOWER_PANEL.H,
        { titleH = LOWER_PANEL.IT })

    -- 4. 标题装饰（装备 tab 不显示，道具 tab 保留）
    if state.tab ~= "equip" then
        DrawUtil.drawImageCentered(vg, imgDeco, DECO.CX, DECO.CY, DECO.W, DECO.H, 1.0)
    end

    -- 5. 网格标题文字（跟随 tab 切换，装备 tab 左对齐+品质筛选）
    local gridTitleText = (state.tab == "equip") and "装备" or "道具"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, GRID_TITLE.FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(GRID_TITLE.R, GRID_TITLE.G, GRID_TITLE.B, 255))
    nvgText(vg, GRID_TITLE.X, GRID_TITLE.Y, gridTitleText, nil)

    -- 5b. 品质筛选按钮（仅装备 tab + 分解模式激活时显示）
    if state.tab == "equip" and decomposeState.active then
        for i = 1, 5 do
            local cx = PZSX.FIRST_CX + (i - 1) * (PZSX.SIZE + PZSX.GAP)
            local didScale = BF.begin(vg, "bp_filter_" .. i, cx, PZSX.CY, PZSX.SIZE, PZSX.SIZE)
            DrawUtil.drawImageCentered(vg, imgPzsx[i], cx, PZSX.CY, PZSX.SIZE, PZSX.SIZE, 1.0)
            BF.finish(vg, didScale)
        end
    end

    -- 6. 网格内容（根据 tab）
    if state.tab == "equip" then
        drawEquipGrid(vg)
    else
        drawItemGrid(vg)
    end

    -- 7. 背包上限文字 + 分解按钮（装备 tab）
    local curCount = getInventoryCount()
    local capStr = "背包上限" .. curCount .. "/" .. BAG_MAX
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 32)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(CAP_TEXT.R, CAP_TEXT.G, CAP_TEXT.B, 255))
    nvgText(vg, CAP_TEXT.X, 2050, capStr, nil)

    -- 7b. 分解按钮（装备 tab 专用）
    if state.tab == "equip" then
        if decomposeState.active then
            -- 分解模式：显示「确认分解」+「取消分解」
            local _bf1 = BF.begin(vg, "bp_confirm_dec", BTN_CONFIRM_DEC.CX, BTN_CONFIRM_DEC.CY, BTN_CONFIRM_DEC.W, BTN_CONFIRM_DEC.H)
            DarkIcon.drawNine(vg, "btn",
                BTN_CONFIRM_DEC.CX - BTN_CONFIRM_DEC.W * 0.5, BTN_CONFIRM_DEC.CY - BTN_CONFIRM_DEC.H * 0.5,
                BTN_CONFIRM_DEC.W, BTN_CONFIRM_DEC.H, { accent = "gold" })
            nvgFontFace(vg, "sans"); nvgFontSize(vg, 40)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(BTN_CONFIRM_DEC.TEXT_R, BTN_CONFIRM_DEC.TEXT_G, BTN_CONFIRM_DEC.TEXT_B, 255))
            nvgText(vg, BTN_CONFIRM_DEC.CX, BTN_CONFIRM_DEC.CY, "确认分解", nil)
            BF.finish(vg, _bf1)

            local _bf2 = BF.begin(vg, "bp_batch_dec", BTN_BATCH_DEC.CX, BTN_BATCH_DEC.CY, BTN_BATCH_DEC.W, BTN_BATCH_DEC.H)
            DarkIcon.drawNine(vg, "btn",
                BTN_BATCH_DEC.CX - BTN_BATCH_DEC.W * 0.5, BTN_BATCH_DEC.CY - BTN_BATCH_DEC.H * 0.5,
                BTN_BATCH_DEC.W, BTN_BATCH_DEC.H, { accent = "green" })
            nvgFontFace(vg, "sans"); nvgFontSize(vg, 40)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(BTN_BATCH_DEC.TEXT_R, BTN_BATCH_DEC.TEXT_G, BTN_BATCH_DEC.TEXT_B, 255))
            nvgText(vg, BTN_BATCH_DEC.CX, BTN_BATCH_DEC.CY, "取消分解", nil)
            BF.finish(vg, _bf2)
        else
            -- 默认模式：仅显示「批量分解」（居中）
            local btnCX = 540
            local _bf2 = BF.begin(vg, "bp_batch_dec", btnCX, BTN_BATCH_DEC.CY, BTN_BATCH_DEC.W, BTN_BATCH_DEC.H)
            DarkIcon.drawNine(vg, "btn",
                btnCX - BTN_BATCH_DEC.W * 0.5, BTN_BATCH_DEC.CY - BTN_BATCH_DEC.H * 0.5,
                BTN_BATCH_DEC.W, BTN_BATCH_DEC.H, { accent = "green" })
            nvgFontFace(vg, "sans"); nvgFontSize(vg, 40)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(BTN_BATCH_DEC.TEXT_R, BTN_BATCH_DEC.TEXT_G, BTN_BATCH_DEC.TEXT_B, 255))
            nvgText(vg, btnCX, BTN_BATCH_DEC.CY, "批量分解", nil)
            BF.finish(vg, _bf2)
        end
    end

    -- 8. 返回按钮
    DrawUtil.drawImageCentered(vg, imgBtnBack, BTN_BACK.CX, BTN_BACK.CY, BTN_BACK.W, BTN_BACK.H, 1.0)

    -- 9. Tab 背景
    DrawUtil.drawImageCentered(vg, imgTabBg, TAB.BG_CX, TAB.BG_CY, TAB.BG_W, TAB.BG_H, 1.0)

    -- 10. Tab 滑块（带动画）
    local tabIdx = getTabIndex(state.tab)
    local fromIdx = getTabIndex(state.tabFrom)
    local tabElapsed = time.elapsedTime - state.tabSwitchTime
    local tabT = math.min(1.0, tabElapsed / TAB.ANIM_DUR)
    local tabEased = easeInOutCubic(tabT)

    local targetItem = TAB_ITEMS[tabIdx]
    local fromItem = TAB_ITEMS[fromIdx]
    local sliderCX = fromItem.cx + (targetItem.cx - fromItem.cx) * tabEased
    local sliderCY = fromItem.cy + (targetItem.cy - fromItem.cy) * tabEased

    DarkIcon.drawNine(vg, "btn", sliderCX - TAB.SLIDER_W * 0.5, sliderCY - TAB.SLIDER_H * 0.5, TAB.SLIDER_W, TAB.SLIDER_H, { accent = "gold" })

    -- 11. Tab 文字
    for i, item in ipairs(TAB_ITEMS) do
        local isActive = (state.tab == item.key)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, TAB.FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(TAB.ACTIVE_R, TAB.ACTIVE_G, TAB.ACTIVE_B, 255))
        else
            nvgFillColor(vg, nvgRGBA(TAB.INACTIVE_R, TAB.INACTIVE_G, TAB.INACTIVE_B, 255))
        end
        nvgText(vg, item.textX, item.textY, item.name, nil)
    end

    nvgRestore(vg)

    -- 装备详情面板（覆盖在最上层）
    EquipmentDetail.draw(vg)

    -- 道具详情弹窗（覆盖在最上层）
    drawItemDetail(vg)
end

-- ======================== 输入处理 ========================

---@return boolean 是否消费了事件
function Panel.handleInput(dx, dy)
    if not state.open then return false end

    -- 道具详情弹窗优先处理
    if itemDetState.open then
        local def = itemDetState.def
        local C = TRANSFER_CONFIRM

        -- UR碎片目标选择弹窗
        if itemDetState.urConvertOpen then
            local U = UR_CONVERT_DIALOG
            if DrawUtil.hitTest(dx, dy, U.CANCEL_CX, U.CANCEL_CY, U.CANCEL_W, U.CANCEL_H) then
                BF.trigger("bp_ur_convert_cancel")
                closeUrConvertDialog()
                return true
            end

            local amount = getUrConvertAmount(def)
            if amount <= 0 then
                local LootBoxPage = require("ui.LootBoxPage")
                if LootBoxPage.showToast then LootBoxPage.showToast("今日转化次数已用完") end
                return true
            end

            local targets = buildUrConvertTargets(def and def.heroId)
            local totalW = U.COLS * U.CELL_SIZE + (U.COLS - 1) * U.GAP_X
            local startX = (DESIGN_W - totalW) * 0.5 + U.CELL_SIZE * 0.5
            for idx, item in ipairs(targets) do
                local col = ((idx - 1) % U.COLS) + 1
                local row = math.floor((idx - 1) / U.COLS)
                local cx = startX + (col - 1) * (U.CELL_SIZE + U.GAP_X)
                local cy = U.GRID_TOP + row * (U.CELL_SIZE + U.GAP_Y) + U.CELL_SIZE * 0.5
                if cy > U.CANCEL_CY - 110 then break end
                if DrawUtil.hitTest(dx, dy, cx, cy, U.CELL_SIZE, U.CELL_SIZE) then
                    BF.trigger("bp_ur_convert_" .. tostring(item.heroId))
                    itemDetState.urConvertPending = true
                    local Client = require("network.Client")
                    Client.sendAction(Protocol.ACTION_TYPES.CONVERT_UR_SHARD, {
                        fromHeroId = def.heroId,
                        toHeroId = item.heroId,
                        amount = amount,
                    })
                    print("[BackpackPanel] 发送UR碎片转化请求 from=" .. tostring(def.heroId)
                        .. " to=" .. tostring(item.heroId)
                        .. " amount=" .. tostring(amount))
                    itemDetState.open = false
                    itemDetState.def = nil
                    closeTransferConfirm()
                    closeUrConvertDialog()
                    return true
                end
            end
            return true
        end

        -- 转区二次确认弹窗
        if itemDetState.transferConfirmStep > 0 then
            if time.elapsedTime - itemDetState.transferConfirmOpenTime < 0.05 then
                return true
            end
            if DrawUtil.hitTest(dx, dy, C.BTN_OK_CX, C.BTN_CY, C.BTN_W, C.BTN_H) then
                BF.trigger("bp_transfer_ok")
                if itemDetState.transferConfirmStep == 1 then
                    itemDetState.transferConfirmStep = 2
                    itemDetState.transferConfirmOpenTime = time.elapsedTime
                else
                    closeTransferConfirm()
                    itemDetState.transferPending = true
                    local Client = require("network.Client")
                    Client.sendAction(Protocol.ACTION_TYPES.TRANSFER_PRIVILEGE_CARD, {})
                    print("[BackpackPanel] 发送特权卡转区请求")
                end
                return true
            end
            if DrawUtil.hitTest(dx, dy, C.BTN_CANCEL_CX, C.BTN_CY, C.BTN_W, C.BTN_H) then
                BF.trigger("bp_transfer_cancel")
                closeTransferConfirm()
                return true
            end
            return true
        end

        -- 特权卡转区按钮
        if shouldShowTransferBtn(def) and not itemDetState.transferPending then
            if DrawUtil.hitTest(dx, dy, TRANSFER_BTN.CX, TRANSFER_BTN.CY, TRANSFER_BTN.W, TRANSFER_BTN.H) then
                BF.trigger("bp_transfer")
                itemDetState.transferConfirmStep = 1
                itemDetState.transferConfirmOpenTime = time.elapsedTime
                print("[BackpackPanel] 打开转区第一次确认")
                return true
            end
        end

        -- UR碎片转化按钮
        if isUrShardDef(def) and not itemDetState.urConvertPending then
            if DrawUtil.hitTest(dx, dy, UR_CONVERT_BTN.CX, UR_CONVERT_BTN.CY, UR_CONVERT_BTN.W, UR_CONVERT_BTN.H) then
                local amount = getUrConvertAmount(def)
                if amount > 0 then
                    BF.trigger("bp_ur_convert")
                    itemDetState.urConvertOpen = true
                    itemDetState.urConvertOpenTime = time.elapsedTime
                    print("[BackpackPanel] 打开UR碎片转化目标选择 heroId=" .. tostring(def.heroId))
                else
                    BF.trigger("bp_ur_convert_restore")
                    itemDetState.urConvertPending = true
                    local Client = require("network.Client")
                    Client.sendAction(Protocol.ACTION_TYPES.RESTORE_UR_SHARD_CONVERT, {})
                    print("[BackpackPanel] 发送UR碎片转化次数恢复请求 cost=" .. tostring(UR_CONVERT_RESTORE_COST))
                end
                return true
            end
        end

        -- 检测转化按钮点击
        if def and def.isShard and def.heroId and not isUrShardDef(def) and isHeroFullyAwakened(def.heroId) then
            local coinValue = getShardCoinValue(def.heroId)
            if coinValue > 0 and DrawUtil.hitTest(dx, dy, CONVERT_BTN.CX, CONVERT_BTN.CY, CONVERT_BTN.W, CONVERT_BTN.H) then
                -- 发送批量转化请求（服务端会一次性转化所有碎片）
                local Client = require("network.Client")
                Client.sendAction(Protocol.ACTION_TYPES.CONVERT_SHARD_TO_COIN, { heroId = def.heroId })
                local shardCount = 0
                if def.getter then shardCount = def.getter() or 0 end
                print("[BackpackPanel] 发送碎片批量转酒馆币请求 heroId=" .. tostring(def.heroId)
                    .. " shards=" .. shardCount .. " totalCoin=" .. (coinValue * shardCount))
                -- 关闭详情弹窗
                itemDetState.open = false
                itemDetState.def = nil
                closeTransferConfirm()
                closeUrConvertDialog()
                return true
            end
        end
        -- 点击其他位置关闭弹窗
        itemDetState.open = false
        itemDetState.def = nil
        closeTransferConfirm()
        closeUrConvertDialog()
        return true
    end

    -- 装备详情优先处理
    if EquipmentDetail.isOpen() then
        return EquipmentDetail.handleInput(dx, dy)
    end

    -- 返回按钮
    if DrawUtil.hitTest(dx, dy, BTN_BACK.CX, BTN_BACK.CY, BTN_BACK.W, BTN_BACK.H) then
        Panel.close()
        return true
    end

    -- Tab 切换
    for i, item in ipairs(TAB_ITEMS) do
        if DrawUtil.hitTest(dx, dy, item.cx, item.cy, TAB.SLIDER_W, TAB.SLIDER_H) then
            if state.tab ~= item.key then
                state.tabFrom = state.tab
                state.tabSwitchTime = time.elapsedTime
                state.tab = item.key
                state.scrollY = 0
                print("[BackpackPanel] 切换到 " .. item.name)
            end
            return true
        end
    end

    -- 装备 tab 分解相关按钮
    if state.tab == "equip" then
        if decomposeState.active then
            -- ---- 分解模式激活中 ----

            -- 品质快速勾选
            for i = 1, 5 do
                local cx = PZSX.FIRST_CX + (i - 1) * (PZSX.SIZE + PZSX.GAP)
                if DrawUtil.hitTest(dx, dy, cx, PZSX.CY, PZSX.SIZE, PZSX.SIZE) then
                    BF.trigger("bp_filter_" .. i)
                    decomposeState.selectedItems = {}
                    local equipList = getEquipList()
                    for idx, equip in ipairs(equipList) do
                        if (equip.quality or 1) <= i and not equip.locked and not equip.equippedByHeroId then
                            decomposeState.selectedItems[idx] = true
                        end
                    end
                    print("[BackpackPanel] 品质筛选: <=" .. i)
                    return true
                end
            end

            -- 确认分解按钮（左）
            if DrawUtil.hitTest(dx, dy, BTN_CONFIRM_DEC.CX, BTN_CONFIRM_DEC.CY, BTN_CONFIRM_DEC.W, BTN_CONFIRM_DEC.H) then
                BF.trigger("bp_confirm_dec")
                local selectedSeqs = {}
                local equipList = getEquipList()
                for idx, selected in pairs(decomposeState.selectedItems) do
                    if selected and equipList[idx] then
                        selectedSeqs[#selectedSeqs + 1] = equipList[idx].seq
                    end
                end
                if #selectedSeqs > 0 then
                    local Client = require("network.Client")
                    decomposeState.pending = true
                    Client.sendAction(Protocol.ACTION_TYPES.DECOMPOSE_EQUIP, { seqs = selectedSeqs })
                    print("[BackpackPanel] 确认分解 " .. #selectedSeqs .. " 件装备")
                end
                decomposeState.selectedItems = {}
                decomposeState.active = false
                return true
            end

            -- 取消分解按钮（右）
            if DrawUtil.hitTest(dx, dy, BTN_BATCH_DEC.CX, BTN_BATCH_DEC.CY, BTN_BATCH_DEC.W, BTN_BATCH_DEC.H) then
                BF.trigger("bp_batch_dec")
                decomposeState.selectedItems = {}
                decomposeState.active = false
                print("[BackpackPanel] 取消分解模式")
                return true
            end

            -- 格子点击：切换选中状态
            if dy >= CLIP_TOP and dy <= GRID.CLIP_BOTTOM then
                local equipList = getEquipList()
                local totalSlots = math.max(#equipList, 10)
                for idx = 1, totalSlots do
                    local equip = equipList[idx]
                    if equip and not equip.locked and not equip.equippedByHeroId then
                        local col = ((idx - 1) % GRID.COLS) + 1
                        local row = math.floor((idx - 1) / GRID.COLS)
                        local cx = CELL_COL_CX[col]
                        local rawCY = GRID.FIRST_ROW_TOP + row * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5
                        local cy = rawCY - state.scrollY
                        if cy >= CLIP_TOP - GRID.CELL_SIZE * 0.5
                           and cy <= GRID.CLIP_BOTTOM + GRID.CELL_SIZE * 0.5
                           and DrawUtil.hitTest(dx, dy, cx, cy, GRID.CELL_SIZE, GRID.CELL_SIZE) then
                            if decomposeState.selectedItems[idx] then
                                decomposeState.selectedItems[idx] = nil
                            else
                                decomposeState.selectedItems[idx] = true
                            end
                            return true
                        end
                    end
                end
            end
        else
            -- ---- 默认模式：点击「批量分解」进入分解模式 ----
            local btnCX = 540
            if DrawUtil.hitTest(dx, dy, btnCX, BTN_BATCH_DEC.CY, BTN_BATCH_DEC.W, BTN_BATCH_DEC.H) then
                BF.trigger("bp_batch_dec")
                decomposeState.active = true
                decomposeState.selectedItems = {}
                print("[BackpackPanel] 进入分解模式")
                return true
            end
        end
    end

    -- 道具 tab 网格区域点击 → 打开道具详情
    if state.tab == "item" and dy >= CLIP_TOP and dy <= GRID.CLIP_BOTTOM then
        local itemList = buildItemList()
        local totalRows = math.ceil(#itemList / GRID.COLS)
        for row = 1, totalRows do
            for col = 1, GRID.COLS do
                local idx = (row - 1) * GRID.COLS + col
                local def = itemList[idx]
                if def then
                    local cx = CELL_COL_CX[col]
                    local rawCY = GRID.FIRST_ROW_TOP + (row - 1) * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5
                    local cy = rawCY - state.scrollY
                    if cy >= CLIP_TOP - GRID.CELL_SIZE * 0.5
                       and cy <= GRID.CLIP_BOTTOM + GRID.CELL_SIZE * 0.5
                       and DrawUtil.hitTest(dx, dy, cx, cy, GRID.CELL_SIZE, GRID.CELL_SIZE) then
                        itemDetState.open = true
                        itemDetState.def = def
                        itemDetState.openTime = time.elapsedTime
                        print("[BackpackPanel] 打开道具详情: " .. (def.name or "?"))
                        return true
                    end
                end
            end
        end
    end

    -- 装备 tab 网格区域点击 → 打开装备详情
    if state.tab == "equip" and dy >= CLIP_TOP and dy <= GRID.CLIP_BOTTOM then
        local equipList = getEquipList()
        local totalSlots = math.max(#equipList, 10)
        local totalRows = math.ceil(totalSlots / GRID.COLS)

        for row = 1, totalRows do
            for col = 1, GRID.COLS do
                local idx = (row - 1) * GRID.COLS + col
                local equip = equipList[idx]
                if equip then
                    local cx = CELL_COL_CX[col]
                    local rawCY = GRID.FIRST_ROW_TOP + (row - 1) * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5
                    local cy = rawCY - state.scrollY
                    -- 检查点击在可见区域内且命中格子
                    if cy >= CLIP_TOP - GRID.CELL_SIZE * 0.5
                       and cy <= GRID.CLIP_BOTTOM + GRID.CELL_SIZE * 0.5
                       and DrawUtil.hitTest(dx, dy, cx, cy, GRID.CELL_SIZE, GRID.CELL_SIZE) then
                        -- 背包模式：slot=nil, heroId=nil → 显示"前往强化"按钮
                        EquipmentDetail.open(equip.seq, nil, nil)
                        return true
                    end
                end
            end
        end
    end

    return true  -- 面板打开时消费所有事件
end

-- ======================== 拖拽/滚轮 ========================

function Panel.handleDragBegin(dx, dy)
    if not state.open then return false end
    if itemDetState.open then return true end
    if EquipmentDetail.isOpen() then return true end
    -- 检查是否在网格区域内
    if dy >= CLIP_TOP and dy <= GRID.CLIP_BOTTOM then
        state.dragging = true
        state.lastDragY = dy
        state.scrollVel = 0
        return true
    end
    return true  -- 面板打开时消费
end

function Panel.handleDragMove(dx, dy)
    if not state.open then return false end
    if itemDetState.open then return true end
    if EquipmentDetail.isOpen() then return true end
    if state.dragging then
        local delta = state.lastDragY - dy
        state.scrollY = state.scrollY + delta
        state.scrollVel = delta
        state.lastDragY = dy
        clampScroll()
        return true
    end
    return true
end

function Panel.handleDragEnd(dx, dy)
    if not state.open then return false end
    if itemDetState.open then return true end
    if EquipmentDetail.isOpen() then return true end
    state.dragging = false
    return true
end

function Panel.handleScroll(wheel)
    if not state.open then return false end
    if itemDetState.open then return true end
    if EquipmentDetail.isOpen() then return true end
    state.scrollY = state.scrollY - wheel * SCROLL_WHEEL_STEP
    clampScroll()
    return true
end

--- 服务端操作结果回调
---@param data table
function Panel.onActionResult(data)
    if data.action == Protocol.ACTION_TYPES.DECOMPOSE_EQUIP then
        if not decomposeState.pending then return end
        decomposeState.pending = false
        if not data.decomposed then return end

        local essenceReward = data.essenceReward or 0
        local RewardPopup = require("ui.RewardPopup")
        local rewards = {}
        if essenceReward > 0 then
            rewards[#rewards + 1] = { type = "essence", amount = essenceReward }
        end
        if #rewards > 0 then
            RewardPopup.show("分解奖励", rewards)
        end
        print("[BackpackPanel] 分解完成，精粹+" .. essenceReward)
        return
    end

    if data.action == Protocol.ACTION_TYPES.TRANSFER_PRIVILEGE_CARD then
        itemDetState.transferPending = false
        if not data.success then
            local LootBoxPage = require("ui.LootBoxPage")
            if LootBoxPage.showToast then
                LootBoxPage.showToast(data.reason or "转区失败")
            end
        end
        return
    end

    if data.action == Protocol.ACTION_TYPES.CONVERT_UR_SHARD then
        itemDetState.urConvertPending = false
        if not data.success then
            local LootBoxPage = require("ui.LootBoxPage")
            if LootBoxPage.showToast then
                LootBoxPage.showToast(data.reason or "转化失败")
            end
        end
        return
    end

    if data.action == Protocol.ACTION_TYPES.RESTORE_UR_SHARD_CONVERT then
        itemDetState.urConvertPending = false
        local LootBoxPage = require("ui.LootBoxPage")
        if data.success then
            if LootBoxPage.showToast then LootBoxPage.showToast("转化次数已恢复") end
        elseif LootBoxPage.showToast then
            LootBoxPage.showToast(data.reason or "恢复失败")
        end
    end
end

return Panel
