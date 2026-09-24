-- ============================================================================
-- BackpackPanel - 背包面板（道具/装备 切换）
-- 全屏面板：顶部背景 + 标题框 + 九宫格下方面板 + 可滚动网格 + 底部返回&Tab
-- 坐标系: 设计分辨率 1080x2400，所有位置为中心点坐标
-- ============================================================================

local GameConfig       = require("config.GameConfig")
local EquipmentConfig  = require("config.EquipmentConfig")
local DrawUtil         = require("core.DrawUtil")
local TownPageChrome   = require("ui.town.TownPageChrome")
local DarkIcon         = require("core.DarkIcon")  -- [暗黑化 P1] 矢量九宫格
local GameState        = require("core.GameState")
local PlayerStore      = require("core.PlayerStore")
local ImageCache       = require("ui.widget.ImageCache")
local QualityMark      = require("ui.widget.QualityMark")
local NumberUtil       = require("core.NumberUtil")
local EquipmentSystem  = require("systems.EquipmentSystem")
local EquipmentDetail  = require("ui.character.EquipmentDetail")
local HeroConfig       = require("config.HeroConfig")
local HeroAssetUtil    = require("config.HeroAssetUtil")
local UrGachaConfig    = require("config.UrGachaConfig")
local CharacterPanel   = require("ui.character.CharacterPanel")
local Protocol         = require("shared.Protocol")
local BF               = require("systems.ButtonFeedback")
local BackpackDialogs  = require("ui.backpack.BackpackDialogs")
local BackpackGrids    = require("ui.backpack.BackpackGrids")

local Panel = {}

--- [横屏] 宿主模式："inline"=随 DiaryPage 内嵌绘制（竖屏）；"window"=全窗居中模态（横屏仓库入口）
local hostMode_ = "inline"

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

-- ======================== [横屏左栏] 紧凑布局 ========================
-- 窗口模态（横屏左栏）下：隐藏顶部大图、面板/网格上移，一屏显示更多装备格。
-- 采用 open 时改写常量表的方式，绘制与输入共用同一套常量，避免双份布局代码。
-- ⚠️ 必须放在全部布局常量（含 CAP_TEXT/BTN_*）定义之后：Lua 词法作用域。
local LAYOUT_ORIG = nil
local function isCompact()
    return hostMode_ == "window" or hostMode_ == "left"
end
local function applyLayout(compact)
    if not LAYOUT_ORIG then
        LAYOUT_ORIG = {
            lowerCY = LOWER_PANEL.CY, lowerH = LOWER_PANEL.H,
            firstRow = GRID.FIRST_ROW_TOP, clipBottom = GRID.CLIP_BOTTOM,
            titleY = GRID_TITLE.Y, pzCy = PZSX.CY,
            btnDecY = BTN_CONFIRM_DEC.CY, btnBatchY = BTN_BATCH_DEC.CY,
            capY = CAP_TEXT.Y,
        }
    end
    if compact then
        LOWER_PANEL.CY, LOWER_PANEL.H = 1300, 2100
        GRID.FIRST_ROW_TOP, GRID.CLIP_BOTTOM = 430, 2060
        GRID_TITLE.Y, PZSX.CY = 380, 375
        BTN_CONFIRM_DEC.CY, BTN_BATCH_DEC.CY = 2160, 2160
        CAP_TEXT.Y = 2230
    else
        LOWER_PANEL.CY, LOWER_PANEL.H = LAYOUT_ORIG.lowerCY, LAYOUT_ORIG.lowerH
        GRID.FIRST_ROW_TOP, GRID.CLIP_BOTTOM = LAYOUT_ORIG.firstRow, LAYOUT_ORIG.clipBottom
        GRID_TITLE.Y, PZSX.CY = LAYOUT_ORIG.titleY, LAYOUT_ORIG.pzCy
        BTN_CONFIRM_DEC.CY, BTN_BATCH_DEC.CY = LAYOUT_ORIG.btnDecY, LAYOUT_ORIG.btnBatchY
        CAP_TEXT.Y = LAYOUT_ORIG.capY
    end
    CLIP_TOP = GRID.FIRST_ROW_TOP
    CLIP_H   = GRID.CLIP_BOTTOM - CLIP_TOP
end

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

-- ======================== 缓动函数（TownPageChrome） ========================
local easeInOutCubic = TownPageChrome.easeInOutCubic

-- ======================== 资源道具定义 ========================

-- key → { iconPath, quality, name, source, desc, getter }
local ITEM_DEFS = {
    { key = "gold",          iconPath = "image/货币道具/UI_icon_JB.png",     quality = 2, name = "金币",       source = "击杀/通关/任务",         desc = "强化武器，购买资源",                                       getter = function() return GameState.getGold() end },
    { key = "gems",          iconPath = "image/货币道具/UI_icon_SJ.png",     quality = 5, name = "钻石",       source = "成就/首通/活动",         desc = "酒馆招募抽卡",                                             getter = function() return GameState.getGems() end },
    { key = "essence",       iconPath = "image/货币道具/UI_icon_JC.png",     quality = 2, name = "精粹",       source = "分解装备获得",           desc = "用于洗练装备",                                             getter = function() return GameState.getEssence() end },
    { key = "enhanceStone",  iconPath = "image/货币道具/UI_icon_QH_1.png",   quality = 3, name = "洗练石",     source = "市场购买/任务",          desc = "洗练时使用可以只洗练数值高低，不洗练属性",                  getter = function() return GameState.getEnhanceStone() end },
    -- seq5 degradeStone 已隐藏，不在背包显示
    { key = "destroyStone",  iconPath = "image/货币道具/UI_icon_QH_3.png",   quality = 5, name = "点金石",     source = "市场购买/任务",          desc = "洗练时使用可将装备升阶，最高升到史诗品质",                  getter = function() return GameState.getDestroyStone() end },
    { key = "weaponScroll",    iconPath = "image/货币道具/UI_icon_JZ_WQ.png",  quality = 3, name = "武器卷轴",   source = "击杀/通关/任务",       desc = "强化装备时进行使用",                                       getter = function() return GameState.getWeaponScroll() end },
    { key = "offhandScroll",   iconPath = "image/货币道具/UI_icon_JZ_FS.png",  quality = 3, name = "副手卷轴",   source = "击杀/通关/任务",       desc = "强化装备时进行使用",                                       getter = function() return GameState.getOffhandScroll() end },
    { key = "armorScroll",     iconPath = "image/货币道具/UI_icon_JZ_HJ.png",  quality = 3, name = "护甲卷轴",   source = "击杀/通关/任务",       desc = "强化装备时进行使用",                                       getter = function() return GameState.getArmorScroll() end },
    { key = "accessoryScroll", iconPath = "image/货币道具/UI_icon_JZ_SP.png",  quality = 3, name = "饰品卷轴",   source = "击杀/通关/任务",       desc = "强化装备时进行使用",                                       getter = function() return GameState.getAccessoryScroll() end },
    { key = "helmetScroll",    iconPath = "image/货币道具/UI_icon_JZ_TK.png",  quality = 3, name = "头盔卷轴",   source = "击杀/通关/任务",       desc = "强化头盔时进行使用",                                       getter = function() return GameState.getHelmetScroll() end },
    { key = "shoesScroll",     iconPath = "image/货币道具/UI_icon_JZ_XZ.png",  quality = 3, name = "鞋子卷轴",   source = "击杀/通关/任务",       desc = "强化鞋子时进行使用",                                       getter = function() return GameState.getShoesScroll() end },
    { key = "recruitTicket", iconPath = "image/货币道具/UI_icon_ZMQ_1.png",  quality = 5, name = "远征招募券", source = "市场/活动/福利",         desc = "酒馆常规招募抽卡",                                       getter = function() return GameState.getRecruitTicket() end },
    { key = "stellarRecruitTicket", iconPath = "image/货币道具/UI_icon_ZMQ_2.png", quality = 6, name = "星辉招募券", source = "活动/福利", desc = "酒馆星辉招募抽卡", getter = function() return GameState.getStellarRecruitTicket() end },
    { key = "goldenKey", iconPath = "image/货币道具/UI_icon_HJYS.png", quality = 6, name = "黄金钥匙", source = "首通奖励/市场购买", desc = "开启神器宝箱", getter = function() return GameState.getGoldenKey() end },
    { key = "sweepTicket",   iconPath = "image/货币道具/UI_icon_SDQ.png",    quality = 4, name = "扫荡券",     source = "活动获得/看广告获得",    desc = "可以立即扫荡获得半小时的离线收益",                          getter = function() return GameState.getSweepTicket() end },
    { key = "tavernCoin",    iconPath = "image/UI_icon_JGB.png",    quality = 3, name = "酒馆币",     source = "非UR满觉醒碎片分解",  desc = "在酒馆商店兑换自选",                                       getter = function() return GameState.getTavernCoin() end },
    { key = "arcaneDust",    iconPath = "image/货币道具/UI_icon_ASFC.png", quality = 3, name = "奥术粉尘",   source = "活动/任务获得",         desc = "用于遗物洗练消耗",                                         getter = function() return GameState.getArcaneDust() end },
    { key = "corruptStone",  iconPath = "image/货币道具/UI_icon_FHS.png", quality = 3, name = "腐化石",     source = "关卡首通/活动/市场",      desc = "可将装备进行魔化，可能会发生预想不到的事情",                 getter = function() return GameState.getCorruptStone() end },
    { key = "sacredStone",   iconPath = "image/货币道具/UI_icon_SSS.png", quality = 6, name = "神圣石",     source = "关卡首通/活动/市场",      desc = "可对已经被魔化的装备净化一次，使其去除魔化效果回到普通状态，每件装备只能被净化一次", getter = function() return GameState.getSacredStone() end },
    { key = "speedCard",     iconPath = "image/货币道具/UI_icon_JSK.png",  quality = 5, name = "加速卡",     source = "市场购买获得",          desc = "提升20%在线挂机收益，包括金币/经验/装备等；获得时即刻开始生效，持续24小时。", getter = function() return GameState.getSpeedCardDisplayCount() end, amountTextGetter = function() return GameState.formatSpeedCardRemain() end, detailAmountTextGetter = function() return "剩余:" .. GameState.formatSpeedCardRemain() end, descGetter = function() return "提升20%在线挂机收益，包括金币/经验/装备等；当前剩余时间：" .. GameState.formatSpeedCardRemain() end },
}

-- ======================== 图片句柄 ========================

local imgTopBg    = -1  -- UI_BB_BJ.png
local imgTitleBg  = -1  -- UI_TJP_MC.png（标题背景，与教堂一致）
local imgDeco     = -1  -- UI_JJC_BTBJ.png（标题装饰）
local imgBtnBack  = -1  -- UI_AN_FH.png（返回按钮）
local imgTabBg    = -1  -- UI_AN_1.png（Tab 背景）

local imgBtnYellow = -1 -- UI_AN_HUANG.png（黄色按钮，碎片转化用）
local imgBtnGreen  = -1 -- UI_AN_LV.png（批量分解/确认分解按钮绿色）
-- 品质筛选小图由 QualityMark 统一加载，背包不再单独持有句柄。
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
    return require("config.AwakeningConfig").isFullyAwakened(hero and hero.awakening)
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

local easeOutCubic = TownPageChrome.easeOutCubic
local easeInCubic  = TownPageChrome.easeInCubic

-- ======================== 辅助函数 ========================

--- 获取道具图标（缓存）
local function getItemIcon(def)
    local cached = itemIconCache[def.key]
    if cached then return cached end
    if not vg_ then return -1 end
    local handle = nvgCreateImage(vg_, def.iconPath, 0)
    itemIconCache[def.key] = handle
    return handle
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

---@type table|nil
local _grids = nil
local function bindBackpackGrids()
    _grids = BackpackGrids.bind({
        GRID = GRID,
        CELL_COL_CX = CELL_COL_CX,
        CLIP_TOP = CLIP_TOP,
        CLIP_H = CLIP_H,
        DESIGN_W = DESIGN_W,
        DarkIcon = DarkIcon,
        DrawUtil = DrawUtil,
        state = state,
        decomposeState = decomposeState,
        ITEM_DEFS = ITEM_DEFS,
        getItemIcon = getItemIcon,
        getImgCheckmark = function() return imgCheckmark end,
        getImgLock = function() return imgLock end,
        getImgHeroIcons = function() return imgHeroIcons end,
        calcScrollMax = calcScrollMax,
        clampScroll = clampScroll,
    })
end
---@return table
local function ensureGrids()
    if not _grids then bindBackpackGrids() end
    ---@type table
    local g = _grids
    return g
end

--- 获取背包装备列表（排序: 品质降→等级降）
---@return table
local function getEquipList()
    return ensureGrids().getEquipList()
end

-- ======================== 绘制: 装备 / 道具 tab ========================

local function drawEquipGrid(vg)
    ensureGrids().drawEquipGrid(vg)
end

local function buildItemList()
    return ensureGrids().buildItemList()
end

local function drawItemGrid(vg)
    ensureGrids().drawItemGrid(vg)
end

-- ======================== 道具详情弹窗 ========================

local _bpDialogs
local function bindBackpackDialogs()
    _bpDialogs = BackpackDialogs.bind({
        DESIGN_W = DESIGN_W,
        DESIGN_H = DESIGN_H,
        TRANSFER_CONFIRM = TRANSFER_CONFIRM,
        itemDetState = itemDetState,
        getImgBtnYellow = function() return imgBtnYellow end,
        getImgBtnGreen = function() return imgBtnGreen end,
    })
end

local function ensureBpDialogs()
    if not _bpDialogs then bindBackpackDialogs() end
    return _bpDialogs
end

local function drawWrappedText(vg, x, y, maxW, text, fontSize, r, g, b)
    return ensureBpDialogs().drawWrappedText(vg, x, y, maxW, text, fontSize, r, g, b)
end

local function shouldShowTransferBtn(def)
    return ensureBpDialogs().shouldShowTransferBtn(def)
end

local function drawTransferConfirm(vg)
    return ensureBpDialogs().drawTransferConfirm(vg)
end

local function closeTransferConfirm()
    return ensureBpDialogs().closeTransferConfirm()
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
        { titleH = 400, accent = DarkIcon.QUALITY_TRIM[q] })

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
    imgTopBg   = nvgCreateImage(vg, "image/界面底板/通用面板/UI_BB_BJ.png", 0)
    imgTitleBg = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_MC.png", 0)
    imgDeco    = nvgCreateImage(vg, "image/界面底板/竞技场排行/UI_JJC_BTBJ.png", 0)
    imgBtnBack = nvgCreateImage(vg, "image/按钮/UI_AN_FH.png", 0)
    imgTabBg   = nvgCreateImage(vg, "image/按钮/UI_AN_1.png", 0)
    -- [暗黑化 P1-B5] 原 image/按钮/UI_AN_2.png 贴图加载已移除（矢量绘制替代）
    imgBtnYellow = nvgCreateImage(vg, "image/按钮/UI_AN_HUANG.png", 0)
    imgBtnGreen  = nvgCreateImage(vg, "image/按钮/UI_AN_LV.png", 0)
    imgLock      = nvgCreateImage(vg, "image/通用图标/UI_ICON_SUO.png", 0)
    imgCheckmark = nvgCreateImage(vg, "image/货币道具/UI_icon_GOU.png", 0)
    QualityMark.init(vg)

    -- imgShardIcon 已移至 DrawUtil.drawShardIcon 统一管理

    -- 加载角色头像角标（与 EquipmentBag 一致）
    HeroAssetUtil.preloadIcons(vg, imgHeroIcons)

    ImageCache.init(vg)
    EquipmentDetail.init(vg)
    print("[BackpackPanel] init OK")
end

--- 打开面板
---@param mode? boolean|"left" true=全窗居中模态(旧)；"left"=横屏左栏页(同铁匠铺/教堂模板)；nil/false=内嵌(竖屏/日志页内)
function Panel.open(mode)
    if mode == "left" then
        hostMode_ = "left"
    elseif mode then
        hostMode_ = "window"
    else
        hostMode_ = "inline"
    end
    applyLayout(isCompact())
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
            applyLayout(false)  -- 恢复竖版原布局
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
function Panel.isWindowMode()
    return hostMode_ == "window"
end

--- [横屏左栏页] 是否以左栏页模式打开（宿主 Viewport(left) 内绘制/输入/中缝返回）
---@return boolean
function Panel.isLeftMode()
    return hostMode_ == "left"
end

local function drawBody(vg)
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

    -- 左栏页模式：整页 seamSlideX 已与中缝条同步，关掉内部分段滑和遮罩淡入
    local seamMode = hostMode_ == "left" or H_SEAM_BACK == true
    local upperOY = seamMode and 0 or (-UPPER_SLIDE_DIST * (1 - progress))
    local lowerOY = seamMode and 0 or (LOWER_SLIDE_DIST * (1 - lowerProgress))
    local overlayAlpha = seamMode and 0 or math.floor(180 * progress)

    -- === 全屏暗色遮罩 ===（[横屏左栏] 页面自带不透明底，不再叠暗罩）
    if not isCompact() then
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha))
    nvgFill(vg)
    end

    -- === 上半部分（从屏幕上方滑入）：顶部背景 + 标题 ===
    -- [横屏左栏紧凑] 窗口模式不画顶部大图，网格从面板顶部开始
    if not isCompact() then
    nvgSave(vg)
    nvgTranslate(vg, 0, upperOY)

    -- 1. 顶部背景图（顶端对齐）
    DrawUtil.drawImageCentered(vg, imgTopBg, TOP_BG.CX, TOP_BG.CY, TOP_BG.W, TOP_BG.H, 1.0)

    -- 3. 标题（与教堂左上角一致）
    TownPageChrome.drawNamePlate(vg, imgTitleBg, require("core.I18n").t("bag"), {
        textCX = TITLE.TEXT_CX, textCY = TITLE.TEXT_CY, font = TITLE.FONT_SIZE,
    })

    nvgRestore(vg)
    end

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
            QualityMark.draw(vg, i, cx, PZSX.CY, PZSX.SIZE, 1.0)
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

    -- 8. 返回按钮（[横屏左栏] 窗口模式由宿主中缝侧边返回条接管，页内不画）
    TownPageChrome.drawBack(vg, { skip = isCompact(), cx = BTN_BACK.CX, cy = BTN_BACK.CY, w = BTN_BACK.W, h = BTN_BACK.H })

    -- 9-11. 底栏 Tab
    local tabIdx, fromIdx, tabEased = TownPageChrome.tabSlide(state, {
        equip = 1, item = 2,
    }, TAB.ANIM_DUR)
    TownPageChrome.drawTabBar(vg, imgTabBg, {
        items = TAB_ITEMS,
        tabIdx = tabIdx, fromIdx = fromIdx, eased = tabEased,
        sliderW = TAB.SLIDER_W, sliderH = TAB.SLIDER_H,
        bgCX = TAB.BG_CX, bgCY = TAB.BG_CY, bgW = TAB.BG_W, bgH = TAB.BG_H,
        font = TAB.FONT_SIZE,
        active = { r = TAB.ACTIVE_R, g = TAB.ACTIVE_G, b = TAB.ACTIVE_B },
        inactive = { r = TAB.INACTIVE_R, g = TAB.INACTIVE_G, b = TAB.INACTIVE_B },
        activePred = function(_, item) return state.tab == item.key end,
    })

    nvgRestore(vg)

    -- 装备详情面板（覆盖在最上层）
    EquipmentDetail.drawIf(vg, "backpack")

    -- 道具详情弹窗（覆盖在最上层）
    drawItemDetail(vg)
end

function Panel.draw(vg)
    if not state.open then return end
    if hostMode_ == "window" then return end  -- 旧全窗模态由 drawWindow 绘制
    if hostMode_ == "left" then
        -- [横屏左栏页模板] 与铁匠铺/教堂一致：seam 滑入 + 不透明底，宿主在 Viewport(left) 内调用
        local ot, ct, od, cd = Panel.getSeamAnim()
        local ox = DrawUtil.seamSlideX(-1, ot, ct, od, cd, 1080)
        if ox ~= 0 then
            nvgSave(vg)
            nvgTranslate(vg, ox, 0)
        end
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0x14, 0x12, 0x10, 255))
        nvgFill(vg)
        drawBody(vg)
        if ox ~= 0 then
            nvgRestore(vg)
        end
        return
    end
    drawBody(vg)
end

--- [横屏中缝] 开合动画四元组（与 BlacksmithPage 等左栏页一致，供宿主中缝返回条同步滑动）
---@return number openTime number closeTime number openDur number closeDur
function Panel.getSeamAnim()
    return state.openTime, state.closeTime, ANIM_OPEN_DUR, ANIM_CLOSE_DUR
end

--- [横屏] 模态绘制：限定矩形内压暗 + 竖版画布等比缩放居中（子弹窗 EquipmentDetail/itemDetail 自动跟随）
--- 三联布局下宿主传中栏矩形，左右栏保持亮且可点；不传 rect = 全窗（竖屏）
---@param vg any
---@param logicalW number 窗口逻辑宽
---@param logicalH number 窗口逻辑高
---@param rect table|nil { x, y, w, h } 限定矩形（窗口坐标）
function Panel.drawWindow(vg, logicalW, logicalH, rect)
    if not state.open then return end
    if hostMode_ ~= "window" then return end
    local rx = rect and rect.x or 0
    local ry = rect and rect.y or 0
    local rw = rect and rect.w or logicalW
    local rh = rect and rect.h or logicalH
    nvgBeginPath(vg)
    nvgRect(vg, rx, ry, rw, rh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)
    local fit = math.min(rw / DESIGN_W, rh / DESIGN_H)
    local dw, dh = DESIGN_W * fit, DESIGN_H * fit
    nvgSave(vg)
    nvgTranslate(vg, rx + (rw - dw) * 0.5, ry + (rh - dh) * 0.5)
    nvgScale(vg, fit, fit)
    drawBody(vg)
    nvgRestore(vg)
end

--- [横屏] 窗口坐标 → 竖版设计坐标（rect 与 drawWindow 一致）
---@param wx number
---@param wy number
---@param logicalW number
---@param logicalH number
---@param rect table|nil { x, y, w, h }
---@return number dx number dy
function Panel.toDesignCoords(wx, wy, logicalW, logicalH, rect)
    local rx = rect and rect.x or 0
    local ry = rect and rect.y or 0
    local rw = rect and rect.w or logicalW
    local rh = rect and rect.h or logicalH
    local fit = math.min(rw / DESIGN_W, rh / DESIGN_H)
    local dw, dh = DESIGN_W * fit, DESIGN_H * fit
    return (wx - (rx + (rw - dw) * 0.5)) / fit, (wy - (ry + (rh - dh) * 0.5)) / fit
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
                local LootBoxPage = require("ui.loot.LootBoxPage")
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
                    local Client = require("runtime.GameAction")
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
                    local Client = require("runtime.GameAction")
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
                    local Client = require("runtime.GameAction")
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
                local Client = require("runtime.GameAction")
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

    -- 返回按钮（[横屏左栏] 窗口/左栏模式由宿主中缝侧边返回条接管）
    if TownPageChrome.hitBack(dx, dy, { skip = isCompact(), cx = BTN_BACK.CX, cy = BTN_BACK.CY, w = BTN_BACK.W, h = BTN_BACK.H }) then
        Panel.close()
        return true
    end

    -- Tab 切换
    do
        local i = TownPageChrome.hitTab(dx, dy, TAB_ITEMS, TAB.SLIDER_W, TAB.SLIDER_H)
        if i then
            local item = TAB_ITEMS[i]
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
                    local Client = require("runtime.GameAction")
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
                local totalSlots = math.max(#equipList, 35)
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
        local totalSlots = math.max(#equipList, 35)
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
                        EquipmentDetail.open(equip.seq, nil, nil, false, "backpack")
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
    if EquipmentDetail.isOpen() then
        return EquipmentDetail.handleDragBegin(dx, dy)
    end
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
    if EquipmentDetail.isOpen() then
        return EquipmentDetail.handleDragMove(dx, dy)
    end
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
    if EquipmentDetail.isOpen() then
        return EquipmentDetail.handleDragEnd(dx, dy)
    end
    state.dragging = false
    return true
end

function Panel.handleScroll(wheel, dx, dy)
    if not state.open then return false end
    if itemDetState.open then return true end
    if EquipmentDetail.isOpen() then
        if dx == nil or EquipmentDetail.containsPoint(dx, dy) then
            return EquipmentDetail.handleScroll(wheel, dx, dy)
        end
    end
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
        local RewardPopup = require("ui.hud.RewardPopup")
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

    if data.action == Protocol.ACTION_TYPES.CONVERT_UR_SHARD then
        itemDetState.urConvertPending = false
        if not data.success then
            local LootBoxPage = require("ui.loot.LootBoxPage")
            if LootBoxPage.showToast then
                LootBoxPage.showToast(data.reason or "转化失败")
            end
        end
        return
    end

    if data.action == Protocol.ACTION_TYPES.RESTORE_UR_SHARD_CONVERT then
        itemDetState.urConvertPending = false
        local LootBoxPage = require("ui.loot.LootBoxPage")
        if data.success then
            if LootBoxPage.showToast then LootBoxPage.showToast("转化次数已恢复") end
        elseif LootBoxPage.showToast then
            LootBoxPage.showToast(data.reason or "恢复失败")
        end
    end
end

return Panel
