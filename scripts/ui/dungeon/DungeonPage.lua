-- ============================================================================
-- DungeonPage - 副本页面（标签5：副本系统）
-- 坐标系: 设计分辨率 1080x2400，所有位置为中心点坐标
-- 基于: 副本栅格化.JSON 设计稿
-- ============================================================================

local DrawUtil      = require("core.DrawUtil")
local PlayerStore   = require("core.PlayerStore")
local BF            = require("systems.ButtonFeedback")
local Protocol      = require("shared.Protocol")
local DungeonIdleConfig = require("config.DungeonIdleConfig")
local DarkIcon = require("core.DarkIcon")  -- 矢量九宫格
local ExpTable      = require("config.ExpTable")
local ClientDispatcher = require("runtime.ClientDispatcher")
local DungeonConfig = require("config.DungeonConfig")
local DungeonRewards = require("ui.dungeon.DungeonRewards")

local DungeonPage = {}

-- ======================== 网络请求状态 ========================
local pendingSweep     = false
local pendingSweepTime = 0
local pendingChallenge = false
---@type number|nil
local pendingChallengeTeam = nil
---@type table|nil
local pendingChallengeRequest = nil
local pendingIdleClaim     = false
local pendingIdleClaimTime = 0
local pendingChallengeTime = 0  -- 超时安全阀（秒）
local PENDING_TIMEOUT = 5.0     -- 5秒无响应自动重置

-- ======================== 图片句柄 ========================

local imgTopPattern  = -1   -- UI_FB_BJ.png    顶部花纹
local imgCard1       = -1   -- 金币副本背景
local imgCard2       = -1   -- 装备副本背景
local imgCard3       = -1   -- 黑钻副本背景
local imgCard4       = -1   -- 通天塔独立背景
local imgGold        = -1   -- UI_icon_JB_X.png 金币图标
local imgGem         = -1   -- UI_icon_SJ_X.png 宝石图标
local imgDust        = -1   -- UI_icon_ASFC.png 奥术尘图标
local imgQualityBg   = {}   -- UI_icon_ZBBJ_N.png 品质背景 (1-5)

-- 详情面板图片

local imgFloorBg1    = -1   -- ICON_LXBJ_1.png 上一层背景
local imgFloorBg2    = -1   -- ICON_LXBJ_2.png 当前层背景
local imgFloorBg3    = -1   -- ICON_LXBJ_3.png 下一层背景
local imgArrow       = -1   -- UI_TJP_JIANTOU.png 过渡箭头


local imgRedDot      = -1   -- ICON_HD.png 红点提示
local imgChest       = -1   -- UI_icon_FBBX.png 挂机宝箱

-- ======================== 布局常量（来自 JSON 设计稿）========================

-- 背景色 #EBE8DC
local BG_R, BG_G, BG_B = 0xEB, 0xE8, 0xDC

-- 顶部花纹（左上角定位）
local TOP_X, TOP_Y   = 0, 0
local TOP_W, TOP_H   = 1080, 198

-- 资源栏（与 TopBar 一致的样式）
local GOLD_BG_CX, GOLD_BG_CY = 732, 100
local GOLD_BG_W, GOLD_BG_H   = 170, 47
local GOLD_ICON_CX, GOLD_ICON_CY = 653, 100
local GOLD_ICON_SIZE = 73
local GEM_BG_CX, GEM_BG_CY   = 965, 100
local GEM_BG_W, GEM_BG_H     = 170, 47
local GEM_ICON_CX, GEM_ICON_CY = 884, 100
local GEM_ICON_SIZE  = 76
local RES_FONT_SIZE  = 33
local RES_STROKE_W   = 4
local RES_BG_ROUND   = 18

-- 副本卡片
local CARD_X, CARD_Y = 40, 300     -- 左上角（下移给 TopBar 页面入口留空）
local CARD_W, CARD_H = 1000, 408
local CARD_SCALE = 0.90 -- 四张卡完整落在 TopBar 与底部导航之间
local CARD_STEP = CARD_H * CARD_SCALE + 24
local CARD_ROUND     = 20

-- 卡片内文本（绝对坐标）
local TITLE_X, TITLE_Y   = 714, 343    -- "黄金矿洞"
local TITLE_SIZE         = 70
local TITLE_R, TITLE_G, TITLE_B = 0xFF, 0xF9, 0x68  -- #FFF968

-- 层级徽章
local BADGE_X, BADGE_Y   = 784, 438    -- 左上角
local BADGE_W, BADGE_H   = 206, 63
local BADGE_ROUND        = 28
local LEVEL_TXT_X, LEVEL_TXT_Y = 837, 449

-- 奖励标题
local REWARD_TITLE_X, REWARD_TITLE_Y = 72, 449

-- 奖励图标（左上角定位）
local REWARD1_X, REWARD1_Y = 72, 503
local REWARD2_X, REWARD2_Y = 246, 503
local REWARD_ICON_SIZE     = 160
-- 奖励数量文字（绝对坐标，右对齐）
local REWARD1_TXT_X, REWARD1_TXT_Y = 121, 615
local REWARD2_TXT_X, REWARD2_TXT_Y = 297, 615

-- 今日次数
local DAILY_TXT_X, DAILY_TXT_Y = 732, 611
local DAILY_R, DAILY_G, DAILY_B = 0x8D, 0xFF, 0x87  -- #8DFF87

-- 页面标题
local PAGE_TITLE_X, PAGE_TITLE_Y = 540, 160
local PAGE_TITLE_SIZE = 70

-- 通用描边宽度
local STROKE_W       = 6
local TEXT_SIZE_MD   = 40

-- ======================== 副本数据 ========================

-- 副本配置
-- 副本详情面板设计常量归组
local DT = {
    TITLE_FONT = 60,
    TITLE_SW = 6,
    TYPE_FONT = 40,
    CONTENT_ROUND = 16,
    FLOOR_BG_SIZE = 182,
    FLOOR_FONT = 65,
    FLOOR_SW = 5,
    ARROW_SIZE = 48,
    CURLVL_FONT = 36,
    CURLVL_SW = 5,
    REW_BG_ROUND = 16,
    DAILY_FONT = 40,
    DAILY_SW = 5,
    SWEEP_FONT = 40,
    FIGHT_FONT = 40,
    CHEST_GAP = 24,
    CHEST_CX = 540,
    CHEST_SIZE = 140,
    CHEST_HINT_FONT = 32,
    CHEST_REWARD_FONT = 30,
    BG_CX = 540,
    BG_CY = 1195,
    BG_W = 950,
    BG_H = 1117,
    BG_IT = 180,
    BG_IR = 40,
    BG_IB = 50,
    BG_IL = 40,
    TITLE_X = 540,
    TITLE_Y = 705,
    TITLE_SR = 0x59,
    TITLE_SG = 0x32,
    TITLE_SB = 0x19,
    TYPE_X = 540,
    TYPE_Y = 816,
    TYPE_R = 0xB6,
    TYPE_G = 0xB0,
    TYPE_B = 0x9D,
    CONTENT_CX = 540,
    CONTENT_CY = 1019,
    CONTENT_W = 800,
    CONTENT_H = 325,
    FLOOR_PREV_CX = 253,
    FLOOR_PREV_CY = 1002,
    FLOOR_CURR_CX = 540,
    FLOOR_CURR_CY = 1002,
    FLOOR_NEXT_CX = 828,
    FLOOR_NEXT_CY = 1002,
    ARROW1_CX = 395,
    ARROW1_CY = 1003,
    ARROW2_CX = 688,
    ARROW2_CY = 1003,
    CURLVL_X = 540,
    CURLVL_Y = 1134,
    REW_BG_CX = 540,
    REW_BG_CY = 1328,
    REW_BG_W = 800,
    REW_BG_H = 220,
    DAILY_X = 540,
    DAILY_Y = 1530,
    DAILY_R = 0x8D,
    DAILY_G = 0xFF,
    DAILY_B = 0x88,
    SWEEP_CX = 330,
    SWEEP_CY = 1633,
    SWEEP_W = 390,
    SWEEP_H = 100,
    FIGHT_CX = 750,
    FIGHT_CY = 1633,
    FIGHT_W = 390,
    FIGHT_H = 100,
    BTN_NP_T = 15,
    BTN_NP_R = 60,
    BTN_NP_B = 15,
    BTN_NP_L = 60,
}
DT.PANEL_BOTTOM = DT.BG_CY + DT.BG_H * 0.5
DT.CHEST_CY = DT.PANEL_BOTTOM + DT.CHEST_GAP + 70
DT.CHEST_HINT_Y = DT.CHEST_CY + 70 + 24
DT.CHEST_REWARD_Y = DT.CHEST_HINT_Y + 42

-- 横屏采用1920×1080设计空间；旧入口仍保留原布局。
local portraitDetail = {}
for key, value in pairs(DT) do portraitDetail[key] = value end
local landscapeMode = false
local pageWidth, pageHeight = 1080, 2400

function DungeonPage.setLandscapeMode(enabled)
    if landscapeMode == enabled then return end
    landscapeMode = enabled == true
    for key, value in pairs(portraitDetail) do DT[key] = value end
    pageWidth, pageHeight = 1080, 2400
    if not landscapeMode then return end
    pageWidth, pageHeight = 1920, 1080
    local layout = {
        BG_CX = 960, BG_CY = 550, BG_W = 1760, BG_H = 860, BG_IT = 130,
        TITLE_X = 960, TITLE_Y = 185, TYPE_X = 960, TYPE_Y = 260,
        CONTENT_CX = 540, CONTENT_CY = 460, CONTENT_W = 780, CONTENT_H = 330,
        FLOOR_PREV_CX = 260, FLOOR_PREV_CY = 440,
        FLOOR_CURR_CX = 540, FLOOR_CURR_CY = 440,
        FLOOR_NEXT_CX = 820, FLOOR_NEXT_CY = 440,
        ARROW1_CX = 400, ARROW1_CY = 440, ARROW2_CX = 680, ARROW2_CY = 440,
        CURLVL_X = 540, CURLVL_Y = 570,
        REW_BG_CX = 1370, REW_BG_CY = 430, REW_BG_W = 720, REW_BG_H = 220,
        DAILY_X = 1370, DAILY_Y = 590,
        SWEEP_CX = 1150, SWEEP_CY = 700, FIGHT_CX = 1580, FIGHT_CY = 700,
        CHEST_CX = 540, CHEST_CY = 760, CHEST_HINT_Y = 865, CHEST_REWARD_Y = 915,
    }
    for key, value in pairs(layout) do DT[key] = value end
    print("[DungeonPage] 横屏选关布局已启用 1920x1080")
end

local function cardRect(cardIdx)
    if landscapeMode then
        local col = (cardIdx - 1) % 2
        local row = math.floor((cardIdx - 1) / 2)
        return 490 + col * 940, 340 + row * 390, 0.84
    end
    return CARD_X + CARD_W * 0.5,
        CARD_Y + (cardIdx - 1) * CARD_STEP + CARD_H * CARD_SCALE * 0.5, CARD_SCALE
end


local dungeonList = {}
for _, id in ipairs(DungeonConfig.RESOURCE_IDS) do
    local def = DungeonConfig.DEFINITIONS[id]
    dungeonList[#dungeonList + 1] = {
        id = id, name = def.name, cardImage = def.cardImage,
        rewards = {
            { type = def.rewardType, icon = def.rewardIcon, quality = def.quality, label = "扫荡" },
            { type = def.rewardType, icon = def.rewardIcon, quality = def.quality, label = "首通" },
        },
    }
end
dungeonList[#dungeonList + 1] = {
    id = "babel_tower", name = "通天塔", titleColor = { 255, 215, 0 },
    cardImage = "image/战斗背景/通天塔.png",
    rewards = { { type = "diamond", icon = "image/货币道具/UI_icon_SJ_X.png", quality = 5, label = "黑晶" } },
}

--- 预览奖励与后端 getFloor 同源，金币/装备/黑晶不混用。
local function getFloorRewards(dungeonId, floor)
    if dungeonId == "babel_tower" then
        local tower = require("config.TowerConfig").getFloor(floor)
        return tower and tower.sweepDiamond or 0, 0
    end
    local data = DungeonConfig.getFloor(dungeonId, floor)
    if not data then return 0, 0 end
    local sub = (PlayerStore.Get("dungeon") or {})[dungeonId]
    local highest = DungeonConfig.getHighestClearedFloor(sub, dungeonId)
    local stageId = DungeonConfig.getStageId(dungeonId, highest)
    local entry = stageId and DungeonConfig.getStage(stageId)
    local sweepAmount = entry and DungeonConfig.getStageRewardAmount(stageId, entry.idleCount or 0) or 0
    -- 资源扫荡预估是一场重复战斗的期望，不再显示旧12小时基准奖励。
    if dungeonId == "gold_mine" then return sweepAmount, data.firstGold or 0 end
    if dungeonId == "equipment_vault" then return sweepAmount, data.firstEquip or 0 end
    if dungeonId == "black_diamond" then return sweepAmount, data.firstDiamond or 0 end
    return 0, 0
end

--- 预览当前副本可领取挂机奖励
---@param dungeonId string
---@return number amount
---@return number accumSec
local function getIdleClaimPreview(dungeonId)
    local dungeon = PlayerStore.Get("dungeon")
    if not dungeon then return 0, 0 end
    local sub = dungeon[dungeonId]
    if not sub then return 0, 0 end
    local idleFloor = DungeonIdleConfig.getIdleFloorFromSub(sub, dungeonId)
    local accumSec = sub.idleAccumSec or 0
    local amount = DungeonIdleConfig.calcReward(dungeonId, idleFloor, accumSec, sub.idleConsumedSec)
    return amount, accumSec
end

local function getIdleMaxHourText()
    local hours = math.floor((DungeonIdleConfig.FULL_RATE_SEC or 0) / 3600 + 0.5)
    return tostring(hours) .. "h"
end

--- 格式化挂机累积时长（显示用，不截断）
---@param sec number
---@return string
local function formatIdleDuration(sec)
    sec = math.floor(tonumber(sec) or 0)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then
        return string.format("%d:%02d", h, m)
    end
    return tostring(m) .. "分"
end

--- 判断副本是否已解锁
---@param dungeonId string
---@return boolean unlocked
---@return string|nil lockText 未解锁时的提示文字
local function isDungeonUnlocked(dungeonId)
    local unlockReq = require("config.DungeonConfig").UNLOCK_CONDITIONS[dungeonId]
    if not unlockReq or unlockReq <= 0 then return true, nil end
    local battleData = PlayerStore.Get("battle")
    local maxStageId = battleData and tonumber(battleData.maxStageId) or 0
    if maxStageId >= unlockReq then return true, nil end
    -- 格式化关卡号: 0305 → "3-5关", 1305 → "13-5关"
    local chapter = math.floor(unlockReq / 100)
    local stage   = unlockReq % 100
    local txt = "抵达" .. chapter .. "-" .. stage .. "关时解锁"
    return false, txt
end

-- ======================== 详情面板布局常量 ========================

-- 背景框（九宫格）

-- 标题

-- 副本类型文本

-- 上方内容背景

-- 层数显示

-- 过渡箭头

-- "当前层数" 文本

-- 奖励区域背景（下方）

-- 剩余次数文本

-- 扫荡按钮

-- 挑战按钮

-- 按钮九宫格 insets（UI_AN_HUANG / UI_AN_LV 统一）

-- 挂机宝箱（详情面板底边下方）

-- ======================== 状态 ========================

-- 奖励图标缓存
local rewardIconCache = {}

-- 运行时状态（per-dungeon）
local dungeonState = {}
for _, dungeon in ipairs(dungeonList) do
    dungeonState[dungeon.id] = { floor = 1, dailyUsed = 0, dailyMax = 2, idleAccumSec = 0 }
end

-- 当前选中副本状态（兼容旧代码的快捷引用）
local currentFloor = 1
local dailyUsed    = 0
local dailyMax     = 2

-- 详情面板状态
local detailOpen = false
---@type table|nil
local detailDungeon = nil  -- 当前打开的副本数据
---@type number|nil
local detailTeamIdx = nil -- 选关行号快照；旧列表入口仍按挑战时activeTeam

local function clearPendingChallenge()
    pendingChallenge = false
    pendingChallengeTime = 0
    pendingChallengeTeam = nil
    pendingChallengeRequest = nil
end

-- 详情面板弹出动画
local detailAnimT   = 1.0   -- 动画进度 0→1
local DETAIL_ANIM_DUR = 0.25 -- 动画时长（秒）

-- ======================== 工具函数 ========================

--- 居中绘制图片
local function drawImageCentered(vg, img, cx, cy, w, h, alpha)
    if img < 0 then return end
    alpha = alpha or 1.0
    local x = cx - w * 0.5
    local y = cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha)
    ---@cast paint NVGpaint
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 左上角定位绘图；仅新副本横图启用 cover，旧图片保持原缩放。
local function drawImageTopLeft(vg, img, x, y, w, h, alpha, cover)
    if img < 0 then return end
    alpha = alpha or 1.0
    local px, py, pw, ph = x, y, w, h
    if cover then
        local iw, ih = nvgImageSize(vg, img)
        if iw <= 0 or ih <= 0 then return end
        local scale = math.max(w / iw, h / ih)
        pw, ph = iw * scale, ih * scale
        px, py = x + (w - pw) * 0.5, y + (h - ph) * 0.5
    end
    local paint = nvgImagePattern(vg, px, py, pw, ph, 0, img, alpha)
    ---@cast paint NVGpaint
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 绘制圆角矩形（左上角定位）
local function drawRoundedRect(vg, x, y, w, h, r, rr, gg, bb, aa)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgFillColor(vg, nvgRGBA(rr, gg, bb, aa))
    nvgFill(vg)
end

--- 格式化数字（委托给 require("core.NumberUtil")，支持 K/M/B/T）
local function formatNumber(n)
    return require("core.NumberUtil").format(n)
end

--- 从 PlayerStore 获取货币数据
local function getGold()
    local currency = PlayerStore.Get("currency")
    if currency and currency.gold then return currency.gold end
    return 0
end

local function getGem()
    local currency = PlayerStore.Get("currency")
    if currency then return currency.gems or 0 end
    return 0
end

--- 获取副本数据（从 PlayerStore 读取）
local function getDungeonData()
    local dungeon = PlayerStore.Get("dungeon")
    if not dungeon then return end

    -- 只读取三资源与独立塔；旧遗迹数据留在规则/存档层，绝不迁移为装备副本。
    for _, entry in ipairs(dungeonList) do
        local sub = dungeon[entry.id]
        local st = dungeonState[entry.id]
        st.floor = sub and sub.floor or 1
        st.dailyUsed = sub and sub.dailyUsed or 0
        st.dailyMax = DungeonConfig.DAILY_SWEEP_LIMIT[entry.id] or 2
        st.idleAccumSec = sub and sub.idleAccumSec or 0
    end

    -- 更新快捷引用（默认使用当前打开的面板，或 gold_mine）
    local activeId = (detailDungeon and detailDungeon.id) or "gold_mine"
    local s = dungeonState[activeId] or dungeonState.gold_mine
    currentFloor = s.floor
    dailyUsed    = s.dailyUsed
    dailyMax     = s.dailyMax
end

local function toast(msg)
    local ok, LootBoxPage = pcall(require, "ui.loot.LootBoxPage")
    if ok and LootBoxPage and LootBoxPage.showToast then
        LootBoxPage.showToast(msg)
    end
    print("[DungeonPage] " .. tostring(msg))
end

--- 通天塔三军攻坚：三队均需解锁且各至少 1 人
---@return table|nil teamAllies
---@return string|nil err
local function collectTowerTeams()
    local CharacterPanel = require("ui.character.panel.CharacterPanel")
    local unlocked = ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle"))
    if unlocked < 3 then
        return nil, "三军攻坚需三队解锁（" .. ExpTable.getTeamUnlockText(3) .. "队伍3）"
    end
    local teams = {}
    for t = 1, 3 do
        local allies = CharacterPanel.getDeployedTeam(t) or {}
        if #allies == 0 then
            return nil, "三军攻坚需三队均有出战（队" .. t .. "为空）"
        end
        teams[t] = allies
    end
    return teams, nil
end

-- ======================== Public API ========================

local dungeonInited_ = false
local dungeonVg_ = nil

---@param dungeonId string
---@param teamIdx number 选关行的显式队号，必须保存而非读取activeTeam
---@return boolean
function DungeonPage.openResource(dungeonId, teamIdx)
    if not DungeonConfig.isResourceDungeon(dungeonId) then toast("未知资源副本") return false end
    local team = math.tointeger(tonumber(teamIdx) or 0)
    if not team or team < 1 or team > ExpTable.TEAM_COUNT then toast("无效的队伍编号") return false end
    if team > ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle")) then
        toast(ExpTable.getTeamUnlockText(team))
        return false
    end
    DungeonPage.close()
    require("ui.hud.BottomNav").setSelectedIndex(3)
    require("ui.battle.tri.BattleTriPage").open()
    require("ui.battle.stage.StageSelectDialog").openDungeon(team, dungeonId)
    return true
end

---@return boolean
function DungeonPage.isDetailOpen()
    return detailOpen
end

--- 兼容旧塔入口：只定位同一张选关表的塔分组，不再打开详情或挑战当前层。
---@param teamIdx number|nil
---@return boolean
function DungeonPage.openTower(teamIdx)
    if pendingChallenge then toast("挑战请求处理中") return false end
    local unlocked, lockText = isDungeonUnlocked("babel_tower")
    if not unlocked then toast(lockText or "通天塔未解锁") return false end
    local team = math.tointeger(tonumber(teamIdx or 1) or 0)
    if not team or team < 1 or team > ExpTable.TEAM_COUNT then toast("无效的队伍编号") return false end
    if team > ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle")) then
        toast(ExpTable.getTeamUnlockText(team))
        return false
    end
    DungeonPage.close()
    require("ui.hud.BottomNav").setSelectedIndex(3)
    require("ui.battle.tri.BattleTriPage").open()
    require("ui.battle.stage.StageSelectDialog").openDungeon(team, "babel_tower")
    return true
end

--- 选关点击只发起请求；本地桥可同步回执，必须先记录 pending 再 send。
---@param requestedFloor number|nil
---@return boolean
function DungeonPage.requestTowerChallenge(requestedFloor)
    if pendingChallenge or pendingSweep or pendingIdleClaim
        or require("ui.tower.TowerBattleScene").isActive()
        or require("ui.dungeon.DungeonBattleScene").isOpen() then
        toast("挑战请求处理中或战斗尚未结束")
        return false
    end
    local unlocked, lockText = isDungeonUnlocked("babel_tower")
    if not unlocked then toast(lockText or "通天塔未解锁") return false end
    local TowerConfig = require("config.TowerConfig")
    local bt = (PlayerStore.Get("dungeon") or {}).babel_tower or {}
    local maxFloor = TowerConfig.getMaxUnlockedCheckpoint(bt)
    local floor = requestedFloor == nil and maxFloor
        or math.tointeger(tonumber(requestedFloor) or 0)
    if not floor or not TowerConfig.isCheckpointFloor(floor) then
        toast("无效的层数")
        return false
    end
    if floor > maxFloor then toast("层数未解锁") return false end
    local teams, err = collectTowerTeams()
    if not teams then toast(err or "三军攻坚条件未满足") return false end

    local request = { dungeonId = "babel_tower", floor = floor }
    pendingChallenge = true
    pendingChallengeTime = 0
    pendingChallengeTeam = nil
    pendingChallengeRequest = request
    print("[DungeonPage] sending TOWER_CHALLENGE floor=" .. floor
        .. " teams=" .. #teams[1] .. "/" .. #teams[2] .. "/" .. #teams[3])
    local called, sent = pcall(function()
        return require("runtime.GameAction").sendAction(
            Protocol.ACTION_TYPES.TOWER_CHALLENGE, { floor = floor })
    end)
    if not called or sent == false then
        if pendingChallengeRequest == request then clearPendingChallenge() end
        print("[DungeonPage] TOWER_CHALLENGE send failed: " .. tostring(sent))
        toast("通天塔挑战发送失败，请重试")
        return false
    end
    -- 旧 send 无返回值也兼容；同步失败回执则留在选关表，不误关闭。
    return request.accepted ~= false
end

---@return boolean
function DungeonPage.isTowerChallengePending()
    return pendingChallenge and pendingChallengeRequest ~= nil
        and pendingChallengeRequest.dungeonId == "babel_tower"
end

--- 宿主离开tab5/关闭详情时调用；迟到CHALLENGE不可重新打开场景。
function DungeonPage.close()
    clearPendingChallenge()
    pendingSweep, pendingSweepTime = false, 0
    pendingIdleClaim, pendingIdleClaimTime = false, 0
    detailOpen, detailDungeon, detailTeamIdx = false, nil, nil
end

function DungeonPage.init(vg)
    if dungeonInited_ then return end
    dungeonInited_ = true
    dungeonVg_ = vg
    imgTopPattern = nvgCreateImage(vg, "image/界面底板/副本秘境/UI_FB_BJ.png", 0)
    imgCard1      = nvgCreateImage(vg, DungeonConfig.DEFINITIONS.gold_mine.cardImage, 0)
    imgCard2      = nvgCreateImage(vg, DungeonConfig.DEFINITIONS.equipment_vault.cardImage, 0)
    imgCard3      = nvgCreateImage(vg, DungeonConfig.DEFINITIONS.black_diamond.cardImage, 0)
    imgCard4      = nvgCreateImage(vg, "image/战斗背景/通天塔.png", 0)
    imgGold       = nvgCreateImage(vg, "image/货币道具/UI_icon_JB_X.png", 0)
    imgGem        = nvgCreateImage(vg, "image/货币道具/UI_icon_SJ_X.png", 0)
    imgDust       = nvgCreateImage(vg, "image/货币道具/UI_icon_ASFC.png", 0)
    -- 加载品质背景 1-6
    for i = 1, 6 do
        imgQualityBg[i] = nvgCreateImage(vg, "image/品质框/UI_icon_ZBBJ_" .. tostring(i) .. ".png", 0)
    end

    -- 详情面板图片
    imgFloorBg1  = nvgCreateImage(vg, "image/通用图标/ICON_LXBJ_1.png", 0)
    imgFloorBg2  = nvgCreateImage(vg, "image/通用图标/ICON_LXBJ_2.png", 0)
    imgFloorBg3  = nvgCreateImage(vg, "image/通用图标/ICON_LXBJ_3.png", 0)
    imgBtnGreen  = nvgCreateImage(vg, "image/按钮/UI_AN_LV.png", 0)
    imgRedDot    = nvgCreateImage(vg, "image/通用图标/ICON_HD.png", 0)
    imgChest     = nvgCreateImage(vg, "image/货币道具/UI_icon_FBBX.png", 0)

    print("[DungeonPage] init OK")
end

function DungeonPage.refreshFromStore()
    getDungeonData()
end

function DungeonPage.draw(vg)
    if not dungeonInited_ then
        DungeonPage.init(vg)
    end
    if not dungeonInited_ then return end
    -- 刷新数据
    getDungeonData()

    -- 1. 全屏背景色
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, pageWidth, pageHeight)
    nvgFillColor(vg, nvgRGBA(BG_R, BG_G, BG_B, 255))
    nvgFill(vg)

    -- 2. 顶部花纹
    drawImageTopLeft(vg, imgTopPattern, TOP_X, TOP_Y, TOP_W, TOP_H, 1.0)

    -- 3. 横屏标题；竖版资源栏仍由 TopBar 绘制。
    if landscapeMode then
        DrawUtil.drawTextStroke(vg, pageWidth * 0.5, 60, "副本秘境", 60,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 5)
    end

    -- 6. 副本卡片（循环绘制所有副本）
    local cardImages = { imgCard1, imgCard2, imgCard3, imgCard4 }

    for cardIdx, dungeon in ipairs(dungeonList) do
        local cardCX, cardCY, cardScale = cardRect(cardIdx)
        local actualY = cardCY - CARD_H * cardScale * 0.5
        local cardY = CARD_Y
        local sourceCX = CARD_X + CARD_W * 0.5

        -- 获取该副本的状态
        local st = dungeonState[dungeon.id] or dungeonState.gold_mine
        local cardFloor = st.floor
        local cardDailyUsed = st.dailyUsed
        local cardDailyMax = st.dailyMax

        local _bf = (not detailOpen) and BF.begin(vg, "dungeon_card_" .. cardIdx, cardCX, cardCY, CARD_W * cardScale, CARD_H * cardScale)

        -- 只变换卡片内部，绘制/命中共用cardRect，不重复应用DPR。
        nvgSave(vg)
        nvgTranslate(vg, cardCX, actualY)
        nvgScale(vg, cardScale, cardScale)
        nvgTranslate(vg, -sourceCX, -CARD_Y)
        nvgIntersectScissor(vg, CARD_X, cardY, CARD_W, CARD_H)
        local cardImg = cardImages[cardIdx] or imgCard1
        drawImageTopLeft(vg, cardImg, CARD_X, cardY, CARD_W, CARD_H, 1.0, true)

        -- 解锁判断
        local unlocked, lockText = isDungeonUnlocked(dungeon.id)

        if not unlocked then
            -- 未解锁：黑色遮罩 + 提示文字
            nvgBeginPath(vg)
            nvgRect(vg, CARD_X, cardY, CARD_W, CARD_H)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
            nvgFill(vg)
            -- 居中显示解锁条件文字
            DrawUtil.drawTextStroke(vg, CARD_X + CARD_W * 0.5, cardY + CARD_H * 0.5, lockText or "未解锁",
                44, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, STROKE_W)
        else
            -- 已解锁：正常绘制卡片内容
            -- 卡片内部元素（相对于当前卡片 Y 偏移）
            local yOff = cardY - CARD_Y

            -- 副本名称（斜体 + 右对齐 X=993）
            nvgSave(vg)
            local titleAnchorX, titleAnchorY = 993, TITLE_Y + yOff + TITLE_SIZE * 0.5
            nvgTranslate(vg, titleAnchorX, titleAnchorY)
            nvgSkewX(vg, -math.tan(math.rad(12)))
            nvgTranslate(vg, -titleAnchorX, -titleAnchorY)
            local tR = dungeon.titleColor and dungeon.titleColor[1] or TITLE_R
            local tG = dungeon.titleColor and dungeon.titleColor[2] or TITLE_G
            local tB = dungeon.titleColor and dungeon.titleColor[3] or TITLE_B
            DrawUtil.drawTextStroke(vg, 993, titleAnchorY, dungeon.name,
                TITLE_SIZE, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                tR, tG, tB, STROKE_W)
            nvgRestore(vg)

            -- 层级徽章背景（半透明黑色）
            drawRoundedRect(vg, BADGE_X, BADGE_Y + yOff, BADGE_W, BADGE_H, BADGE_ROUND, 0, 0, 0, 128)

            -- 层级文字
            local levelText = "第" .. cardFloor .. "层"
            DrawUtil.drawTextStroke(vg, BADGE_X + BADGE_W * 0.5, BADGE_Y + yOff + BADGE_H * 0.5, levelText,
                TEXT_SIZE_MD, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, STROKE_W)

            -- 奖励标题
            DrawUtil.drawTextStroke(vg, REWARD_TITLE_X, REWARD_TITLE_Y + yOff + TEXT_SIZE_MD * 0.5, "副本奖励",
                TEXT_SIZE_MD, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                255, 255, 255, STROKE_W)

            -- 奖励图标（品质背景 + 资源图标内缩 + 数量角标）
            local REWARD_POSITIONS = {
                { x = REWARD1_X, y = REWARD1_Y + yOff },
                { x = REWARD2_X, y = REWARD2_Y + yOff },
            }
            local REWARD_INNER = REWARD_ICON_SIZE - 24
            local BADGE_FONT_SZ = 36
            local BADGE_STROKE_W = 4
            local r1, r2 = getFloorRewards(dungeon.id, cardFloor)
            local rewardAmounts = { r1, r2 }

            for i, reward in ipairs(dungeon.rewards) do
                local pos = REWARD_POSITIONS[i]
                if not pos then break end
                local rx, ry = pos.x, pos.y
                local cx = rx + REWARD_ICON_SIZE * 0.5
                local cy = ry + REWARD_ICON_SIZE * 0.5

                -- 1) 品质背景
                DarkIcon.drawQualityBg(vg, reward.quality or 1, cx, cy, REWARD_ICON_SIZE, REWARD_ICON_SIZE, 1.0)  --

                -- 2) 资源图标（内缩绘制）
                if not rewardIconCache[reward.icon] then
                    rewardIconCache[reward.icon] = nvgCreateImage(vg, reward.icon, 0)
                end
                local icon = rewardIconCache[reward.icon]
                if icon and icon >= 0 then
                    drawImageCentered(vg, icon, cx, cy, REWARD_INNER, REWARD_INNER, 1.0)
                end

                -- 3) 数量角标（右下角偏移8px，16方向描边）
                local amt = rewardAmounts[i] or 0
                if amt > 0 then
                    local amtStr = formatNumber(amt)
                    local bx = cx + REWARD_ICON_SIZE * 0.5 - 8
                    local by = cy + REWARD_ICON_SIZE * 0.5 - 8
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, BADGE_FONT_SZ)
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                    -- 黑色描边（16方向）
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                    local sStep = math.pi * 2 / 16
                    for si = 0, 15 do
                        local sa = si * sStep
                        nvgText(vg, bx + math.cos(sa) * BADGE_STROKE_W, by + math.sin(sa) * BADGE_STROKE_W, amtStr, nil)
                    end
                    -- 白色前景
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                    nvgText(vg, bx, by, amtStr, nil)
                end
            end

            -- 三资源显示券余额，不再暗示存在每日次数限制；塔仍保留旧玩法标识。
            local resourceDungeon = DungeonConfig.isResourceDungeon(dungeon.id)
            local cardRemain = math.max(0, cardDailyMax - cardDailyUsed)
            if resourceDungeon then
                cardRemain = math.max(0, math.floor(tonumber((PlayerStore.Get("currency") or {}).sweepTicket) or 0))
            end
            local dailyTxt = dungeon.id == "babel_tower" and ("独立玩法 · 三军攻坚")
                or (resourceDungeon and ("扫荡券：" .. cardRemain .. "（1券/场）")
                    or ("今日扫荡：" .. cardRemain .. "/" .. cardDailyMax))
            local cardDR, cardDG, cardDB = DAILY_R, DAILY_G, DAILY_B
            if cardRemain <= 0 then
                cardDR, cardDG, cardDB = 0xFF, 0x44, 0x44
            end
            DrawUtil.drawTextStroke(vg, 993, DAILY_TXT_Y + yOff + TEXT_SIZE_MD * 0.5, dailyTxt,
                TEXT_SIZE_MD, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                cardDR, cardDG, cardDB, STROKE_W)

            -- 红点：有剩余扫荡次数时，在卡片右上角显示
            if cardRemain > 0 and imgRedDot >= 0 then
                local rdSz = 44
                local rdX = CARD_X + CARD_W - 30
                local rdY = cardY + 30
                drawImageCentered(vg, imgRedDot, rdX, rdY, rdSz, rdSz, 1.0)
            end
        end

        nvgRestore(vg)  -- 恢复圆角裁剪

        BF.finish(vg, _bf)
    end

   -- 8. 详情面板（覆盖在最上层）
    -- 新手引导热点注册
    do
        local TM = require("systems.TutorialManager")
        if TM.isActive() then
            local cardCX, cardCY, cardScale = cardRect(1)
            TM.registerHotspot("dungeon_gold_mine", cardCX, cardCY, CARD_W * cardScale, CARD_H * cardScale, "modal")
        end
    end

    if detailOpen and detailDungeon then
        DungeonPage.drawDetailPanel(vg)
    end
    if landscapeMode then
        DarkIcon.drawNine(vg, "btn", 40, 35, 190, 75, { accent = "gold" })
        DrawUtil.drawTextStroke(vg, 135, 72, "返回", 36,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
    end
end

-- ======================== 详情面板绘制 ========================

function DungeonPage.drawDetailPanel(vg)
    -- easeOutBack 缓动函数
    local function easeOutBack(t)
        local c1 = 1.70158
        local c3 = c1 + 1
        return 1 + c3 * ((t - 1) ^ 3) + c1 * ((t - 1) ^ 2)
    end

    -- 动画缩放值
    local scale = easeOutBack(detailAnimT)
    local maskAlpha = math.floor(128 * detailAnimT)

    -- 1. 全屏遮罩（透明度跟随动画）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, pageWidth, pageHeight)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, maskAlpha))
    nvgFill(vg)

    -- 2. 面板内容整体缩放（以面板中心为锚点）
    nvgSave(vg)
    nvgTranslate(vg, DT.BG_CX, DT.BG_CY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -DT.BG_CX, -DT.BG_CY)

    -- 3. 九宫格弹窗背景 UI_TY_EJQRK
    local bgX = DT.BG_CX - DT.BG_W * 0.5
    local bgY = DT.BG_CY - DT.BG_H * 0.5
    DarkIcon.drawNine(vg, "panel", bgX, bgY, DT.BG_W, DT.BG_H, { titleH = DT.BG_IT })

    -- 3. 标题（白色 + #593219描边6）
    DrawUtil.drawTextStroke(vg, DT.TITLE_X, DT.TITLE_Y, detailDungeon.name,
        DT.TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DT.TITLE_SW,
        { strokeColor = { DT.TITLE_SR, DT.TITLE_SG, DT.TITLE_SB } })

    -- 4. 副本类型文本（无描边）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, DT.TYPE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(DT.TYPE_R, DT.TYPE_G, DT.TYPE_B, 255))
    local typeText = detailDungeon.id == "babel_tower" and "独立通天塔 · 三军攻坚"
        or ("资源副本 · 队伍" .. tostring(detailTeamIdx or require("ui.character.panel.CharacterPanel").getActiveTeamIdx()))
    nvgText(vg, DT.TYPE_X, DT.TYPE_Y, typeText, nil)

    -- 5. 上方内容区域背景（圆角矩形，黑色5%透明度）
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        DT.CONTENT_CX - DT.CONTENT_W * 0.5,
        DT.CONTENT_CY - DT.CONTENT_H * 0.5,
        DT.CONTENT_W, DT.CONTENT_H, DT.CONTENT_ROUND)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))  -- 5% of 255 ≈ 13
    nvgFill(vg)

    -- 6. 三个层数背景图
    -- 上一层 (ICON_LXBJ_1)
    drawImageCentered(vg, imgFloorBg1, DT.FLOOR_PREV_CX, DT.FLOOR_PREV_CY,
        DT.FLOOR_BG_SIZE, DT.FLOOR_BG_SIZE, 1.0)
    -- 当前层 (ICON_LXBJ_2)
    drawImageCentered(vg, imgFloorBg2, DT.FLOOR_CURR_CX, DT.FLOOR_CURR_CY,
        DT.FLOOR_BG_SIZE, DT.FLOOR_BG_SIZE, 1.0)
    -- 下一层 (ICON_LXBJ_3)
    drawImageCentered(vg, imgFloorBg3, DT.FLOOR_NEXT_CX, DT.FLOOR_NEXT_CY,
        DT.FLOOR_BG_SIZE, DT.FLOOR_BG_SIZE, 1.0)

    -- 7. 层数数字（白色 + 黑色描边5）
    local prevFloor = currentFloor - 1  -- 第1层时显示0
    local nextFloor = math.min(currentFloor + 1, DungeonConfig.MAX_FLOOR[detailDungeon.id] or require("config.TowerConfig").MAX_FLOOR)

    DrawUtil.drawTextStroke(vg, DT.FLOOR_PREV_CX, DT.FLOOR_PREV_CY, tostring(prevFloor),
        DT.FLOOR_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DT.FLOOR_SW)

    DrawUtil.drawTextStroke(vg, DT.FLOOR_CURR_CX, DT.FLOOR_CURR_CY, tostring(currentFloor),
        DT.FLOOR_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DT.FLOOR_SW)

    DrawUtil.drawTextStroke(vg, DT.FLOOR_NEXT_CX, DT.FLOOR_NEXT_CY, tostring(nextFloor),
        DT.FLOOR_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DT.FLOOR_SW)

    -- 8. 过渡箭头（两个，在层数图标之间）
    drawImageCentered(vg, imgArrow, DT.ARROW1_CX, DT.ARROW1_CY,
        DT.ARROW_SIZE, DT.ARROW_SIZE, 1.0)
    drawImageCentered(vg, imgArrow, DT.ARROW2_CX, DT.ARROW2_CY,
        DT.ARROW_SIZE, DT.ARROW_SIZE, 1.0)

    -- ==================== 下半部分 ====================

    -- 14. "当前层数" 文本（白色 + 黑色描边5）
    local curLvlText = "当前层数"
    DrawUtil.drawTextStroke(vg, DT.CURLVL_X, DT.CURLVL_Y, curLvlText,
        DT.CURLVL_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DT.CURLVL_SW)

    -- 15. 奖励区域背景（圆角矩形，黑色5%透明度）
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        DT.REW_BG_CX - DT.REW_BG_W * 0.5,
        DT.REW_BG_CY - DT.REW_BG_H * 0.5,
        DT.REW_BG_W, DT.REW_BG_H, DT.REW_BG_ROUND)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))  -- 5% of 255 ≈ 13
    nvgFill(vg)

    -- 16. 奖励图标（居中排布在奖励区域内，参考 OfflineRewardPanel 样式）
    local rewards = detailDungeon.rewards
    if rewards and #rewards > 0 then
        local REWARD_SZ = REWARD_ICON_SIZE  -- 160
        local REWARD_IN = REWARD_SZ - 24    -- 136 内缩
        local REWARD_GAP = 20
        local totalW = #rewards * REWARD_SZ + (#rewards - 1) * REWARD_GAP
        local startX = DT.REW_BG_CX - totalW * 0.5 + REWARD_SZ * 0.5

        -- 动态获取当前层奖励数值
        local dtSweepGold, dtFirstGold = getFloorRewards(detailDungeon.id, currentFloor)
        local dtRewardAmounts = { dtSweepGold, dtFirstGold }

        for i, reward in ipairs(rewards) do
            local cx = startX + (i - 1) * (REWARD_SZ + REWARD_GAP)
            local cy = DT.REW_BG_CY

            -- 品质背景
            DarkIcon.drawQualityBg(vg, reward.quality or 1, cx, cy, REWARD_SZ, REWARD_SZ, 1.0)

            -- 资源图标（内缩绘制）
            if not rewardIconCache[reward.icon] then
                rewardIconCache[reward.icon] = nvgCreateImage(vg, reward.icon, 0)
            end
            local icon = rewardIconCache[reward.icon]
            if icon and icon >= 0 then
                drawImageCentered(vg, icon, cx, cy, REWARD_IN, REWARD_IN, 1.0)
            end

            -- 数量角标（右下角偏移8px，16方向描边）
            local dtAmt = dtRewardAmounts[i] or 0
            if dtAmt > 0 then
                local amtStr = formatNumber(dtAmt)
                local bx = cx + REWARD_SZ * 0.5 - 8
                local by = cy + REWARD_SZ * 0.5 - 8
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 36)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                -- 黑色描边（16方向）
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                local sStep = math.pi * 2 / 16
                for si = 0, 15 do
                    local sa = si * sStep
                    nvgText(vg, bx + math.cos(sa) * 4, by + math.sin(sa) * 4, amtStr, nil)
                end
                -- 白色前景
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                nvgText(vg, bx, by, amtStr, nil)
            end
        end
    end

    -- 资源副本一券一场；塔/遗迹保留日次。
    local resourceDungeon = DungeonConfig.isResourceDungeon(detailDungeon.id)
    local ticketCount = math.max(0, math.floor(tonumber((PlayerStore.Get("currency") or {}).sweepTicket) or 0))
    local dailyRemain = math.max(0, dailyMax - dailyUsed)
    local sweepRemain = resourceDungeon and ticketCount or dailyRemain
    local dailyText = resourceDungeon and ("扫荡券：" .. ticketCount .. "（1券/场）")
        or ("今日次数:" .. dailyRemain .. "/" .. dailyMax)
    local dtR, dtG, dtB = DT.DAILY_R, DT.DAILY_G, DT.DAILY_B
    if sweepRemain <= 0 then
        dtR, dtG, dtB = 0x8b, 0x95, 0xa5  -- 耗尽=灰蓝色
    end
    DrawUtil.drawTextStroke(vg, DT.DAILY_X, DT.DAILY_Y, dailyText,
        DT.DAILY_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        dtR, dtG, dtB, DT.DAILY_SW)

    -- 18. 扫荡按钮背景 UI_AN_HUANG（九宫格）
    local sub = (PlayerStore.Get("dungeon") or {})[detailDungeon.id]
    local sweepFloor = resourceDungeon
        and DungeonConfig.getHighestClearedFloor(sub, detailDungeon.id) or math.max(0, currentFloor - 1)
    local sweepDisabled = sweepFloor < 1 or sweepRemain <= 0 or pendingSweep
    local _bfSweep = BF.begin(vg, "dt_sweep_btn", DT.SWEEP_CX, DT.SWEEP_CY, DT.SWEEP_W, DT.SWEEP_H)
    nvgGlobalAlpha(vg, sweepDisabled and 0.45 or 1.0)
    DarkIcon.drawNine(vg, "btn", DT.SWEEP_CX - DT.SWEEP_W * 0.5, DT.SWEEP_CY - DT.SWEEP_H * 0.5, DT.SWEEP_W, DT.SWEEP_H, { accent = "gold" })
    BF.finish(vg, _bfSweep)
    nvgGlobalAlpha(vg, 1.0)  -- 底图变暗即可恢复，文字单独按条件着色

    -- 19. 扫荡按钮文本 "扫荡上一层"（禁用=棕色，可用=深色亮字）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, DT.SWEEP_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if sweepDisabled then
        nvgFillColor(vg, nvgRGBA(0x8b, 0x95, 0xa5, 255))
    else
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))
    end
    nvgText(vg, DT.SWEEP_CX, DT.SWEEP_CY, "扫荡最高已通层", nil)

    -- 20. 挑战按钮背景 UI_AN_LV（九宫格）
    local _bfFight = BF.begin(vg, "dt_fight_btn", DT.FIGHT_CX, DT.FIGHT_CY, DT.FIGHT_W, DT.FIGHT_H)
    DarkIcon.drawNine(vg, "btn", DT.FIGHT_CX - DT.FIGHT_W * 0.5, DT.FIGHT_CY - DT.FIGHT_H * 0.5, DT.FIGHT_W, DT.FIGHT_H, { accent = "green" })
    BF.finish(vg, _bfFight)

    -- 21. 挑战按钮文本 "挑战"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, DT.FIGHT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))  -- 纯黑不透明度75%
    local fightLabel = (detailDungeon and detailDungeon.id == "babel_tower") and "三军攻坚" or "挑战"
    nvgText(vg, DT.FIGHT_CX, DT.FIGHT_CY, fightLabel, nil)

    -- 22. 挂机宝箱（面板正下方）
    local idleAmount = 0
    if detailDungeon then
        idleAmount = select(1, getIdleClaimPreview(detailDungeon.id))
    end
    local _bfChest = BF.begin(vg, "dt_idle_chest", DT.CHEST_CX, DT.CHEST_CY, DT.CHEST_SIZE, DT.CHEST_SIZE)
    drawImageCentered(vg, imgChest, DT.CHEST_CX, DT.CHEST_CY, DT.CHEST_SIZE, DT.CHEST_SIZE, 1.0)
    BF.finish(vg, _bfChest)
    if idleAmount > 0 and imgRedDot >= 0 then
        local rdX = DT.CHEST_CX + DT.CHEST_SIZE * 0.5 - 18
        local rdY = DT.CHEST_CY - DT.CHEST_SIZE * 0.5 + 18
        drawImageCentered(vg, imgRedDot, rdX, rdY, 44, 44, 1.0)
    end

    -- 23. 挂机时长 / 上限提示
    if detailDungeon then
        local _, accumSec = getIdleClaimPreview(detailDungeon.id)
        accumSec = accumSec or 0
        local timeTxt
        local maxHourText = getIdleMaxHourText()
        local capDays = math.floor((DungeonIdleConfig.HARD_CAP_SEC or 604800) / 86400)
        if DungeonIdleConfig.getFillRatio(accumSec) >= 1 then
            local tailPct = math.floor((DungeonIdleConfig.TAIL_RATIO or 0.5) * 100 + 0.5)
            timeTxt = "超过" .. maxHourText .. "按" .. tailPct .. "%，" .. capDays .. "日封顶"
        else
            timeTxt = "挂机 " .. formatIdleDuration(accumSec) .. "/" .. maxHourText
        end
        DrawUtil.drawTextStroke(vg, DT.CHEST_CX, DT.CHEST_HINT_Y, timeTxt,
            DT.CHEST_HINT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            0xB6, 0xB0, 0x9D, 4)
        DrawUtil.drawTextStroke(vg, DT.CHEST_CX, DT.CHEST_REWARD_Y, "已存" .. DungeonRewards.rewardLabel(detailDungeon.id) .. "：" .. formatNumber(idleAmount),
            DT.CHEST_REWARD_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            0xFF, 0xEA, 0x00, 4)
    end

    nvgRestore(vg)  -- 结束面板缩放变换
end

function DungeonPage.update(dt)
    -- 详情面板弹出动画
    if detailOpen and detailAnimT < 1.0 then
        detailAnimT = detailAnimT + dt / DETAIL_ANIM_DUR
        if detailAnimT > 1.0 then detailAnimT = 1.0 end
    end

    -- pending 超时安全阀：防止服务端无响应时按钮永久卡死
    if pendingChallenge then
        pendingChallengeTime = pendingChallengeTime + dt
        if pendingChallengeTime >= PENDING_TIMEOUT then
            print("[DungeonPage] pendingChallenge timeout, force reset")
            clearPendingChallenge()
        end
    end
    if pendingSweep then
        pendingSweepTime = pendingSweepTime + dt
        if pendingSweepTime >= PENDING_TIMEOUT then pendingSweep, pendingSweepTime = false, 0 end
    end

    if pendingIdleClaim then
        pendingIdleClaimTime = pendingIdleClaimTime + dt
        if pendingIdleClaimTime >= PENDING_TIMEOUT then
            print("[DungeonPage] pendingIdleClaim timeout, force reset")
            pendingIdleClaim = false
            pendingIdleClaimTime = 0
        end
    end
end

function DungeonPage.handleInput(dx, dy)
    if not dungeonInited_ and dungeonVg_ then
        DungeonPage.init(dungeonVg_)
    end
    if not dungeonInited_ then return true end
    if landscapeMode and DrawUtil.hitTest(dx, dy, 135, 72, 190, 75) then
        if detailOpen then DungeonPage.close()
        else require("ui.hud.BottomNav").setSelectedIndex(3) end
        return true
    end
    -- 详情面板打开时，优先处理面板内交互
    if detailOpen then
        -- 挂机宝箱绘制在详情面板外侧，必须先于“点击背景外关闭面板”处理
        if DrawUtil.hitTest(dx, dy, DT.CHEST_CX, DT.CHEST_CY, DT.CHEST_SIZE, DT.CHEST_SIZE) then
            BF.trigger("dt_idle_chest")
            if pendingIdleClaim then
                print("[DungeonPage] idle claim pending, skip")
                return true
            end
            local dId = detailDungeon and detailDungeon.id
            if not dId then return true end
            local amount = select(1, getIdleClaimPreview(dId))
            if amount <= 0 then
                print("[DungeonPage] no idle reward to claim dungeon=" .. dId)
                return true
            end
            pendingIdleClaim = true
            pendingIdleClaimTime = 0
            print("[DungeonPage] sending DUNGEON_IDLE_CLAIM dungeon=" .. dId)
            require("runtime.GameAction").sendAction(
                Protocol.ACTION_TYPES.DUNGEON_IDLE_CLAIM,
                { dungeonId = dId }
            )
            return true
        end

        -- 点击九宫格背景外区域 → 关闭面板
        if not DrawUtil.hitTest(dx, dy, DT.BG_CX, DT.BG_CY, DT.BG_W, DT.BG_H) then
            DungeonPage.close()
            return true
        end

        -- 扫荡按钮
        if DrawUtil.hitTest(dx, dy, DT.SWEEP_CX, DT.SWEEP_CY, DT.SWEEP_W, DT.SWEEP_H) then
            BF.trigger("dt_sweep_btn")
            local dId = detailDungeon.id
            local resourceDungeon = DungeonConfig.isResourceDungeon(dId)
            local sub = (PlayerStore.Get("dungeon") or {})[dId]
            local highest = resourceDungeon
                and DungeonConfig.getHighestClearedFloor(sub, dId) or math.max(0, currentFloor - 1)
            if pendingSweep then
                print("[DungeonPage] sweep request pending, skip")
            elseif highest < 1 then
                toast("暂无可扫荡层")
            elseif resourceDungeon and (tonumber((PlayerStore.Get("currency") or {}).sweepTicket) or 0) < 1 then
                toast("扫荡券不足")
            elseif not resourceDungeon and dailyUsed >= dailyMax then
                print("[DungeonPage] daily sweep limit reached")
            else
                pendingSweep = true
                pendingSweepTime = 0
                if dId == "babel_tower" then
                    print("[DungeonPage] sending TOWER_SWEEP")
                    require("runtime.GameAction").sendAction(
                        Protocol.ACTION_TYPES.TOWER_SWEEP, {}
                    )
                else
                    print("[DungeonPage] sending DUNGEON_SWEEP dungeon=" .. dId .. " floor=" .. highest)
                    local teamIdx = detailTeamIdx or require("ui.character.panel.CharacterPanel").getActiveTeamIdx()
                    -- 资源兼容入口同样一券一场；显式冻结最高已通层，不靠处理时再猜。
                    local params = { dungeonId = dId, teamIdx = teamIdx }
                    if resourceDungeon then params.count, params.floor = 1, highest end
                    require("runtime.GameAction").sendAction(
                        Protocol.ACTION_TYPES.DUNGEON_SWEEP, params
                    )
                end
            end
            return true
        end

        -- 挑战按钮
        if DrawUtil.hitTest(dx, dy, DT.FIGHT_CX, DT.FIGHT_CY, DT.FIGHT_W, DT.FIGHT_H) then
            BF.trigger("dt_fight_btn")
            if detailDungeon.id == "babel_tower" then
                DungeonPage.requestTowerChallenge(currentFloor)
                return true
            end
            if pendingChallenge then
                print("[DungeonPage] challenge request pending, skip")
            else
                pendingChallenge = true
                pendingChallengeTime = 0
                local dId = detailDungeon.id
                do
                    local CharacterPanel = require("ui.character.panel.CharacterPanel")
                    local teamIdx = detailTeamIdx or CharacterPanel.getActiveTeamIdx()
                    local unlocked = ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle"))
                    if teamIdx < 1 or teamIdx > unlocked then
                        clearPendingChallenge()
                        toast(ExpTable.getTeamUnlockText(teamIdx))
                        return true
                    end
                    if #(CharacterPanel.getDeployedTeam(teamIdx) or {}) == 0 then
                        clearPendingChallenge()
                        toast("未编队，请在右侧部署队员")
                        return true
                    end
                    -- 本地桥同步回调：必须在 sendAction 前锁定本次挑战的队伍。
                    pendingChallengeTeam = teamIdx
                    pendingChallengeRequest = { dungeonId = dId, floor = currentFloor, teamIdx = teamIdx }
                    print("[DungeonPage] sending DUNGEON_CHALLENGE dungeon=" .. dId
                        .. " floor=" .. currentFloor .. " team=" .. teamIdx)
                    require("runtime.GameAction").sendAction(
                        Protocol.ACTION_TYPES.DUNGEON_CHALLENGE,
                        { dungeonId = dId, floor = currentFloor, teamIdx = teamIdx }
                    )
                end
            end
            return true
        end

        return true  -- 消费所有点击，阻止穿透
    end

    -- 卡片点击统一进入选关表，不再打开旧详情。
    for cardIdx, dungeon in ipairs(dungeonList) do
        local cardCX, cardCY, cardScale = cardRect(cardIdx)
        if DrawUtil.hitTest(dx, dy, cardCX, cardCY, CARD_W * cardScale, CARD_H * cardScale) then
            if DungeonConfig.isResourceDungeon(dungeon.id) then
                DungeonPage.openResource(dungeon.id, 1)
            else
                DungeonPage.openTower()
            end
            return true
        end
    end
    return false
end

-- ======================== 网络响应处理 ========================

--- 扫荡奖励弹出时自动离开副本页（回到主视图页签）。
--- 横屏下副本页是全窗模态层，绘制在全局弹窗层之上；不离开的话
--- 奖励弹窗会被副本页盖住，玩家看不到扫荡奖励。
local function leaveDungeonPageForReward()
    local BottomNav = require("ui.hud.BottomNav")
    if BottomNav.getSelectedIndex() == 5 then
        BottomNav.setSelectedIndex(3)
        print("[DungeonPage] sweep reward shown, auto leave dungeon page -> tab 3")
    end
end

--- 服务端操作结果回调（由 Client.lua 调用）
---@param data table { action, success, reason, ... }
function DungeonPage.onActionResult(data)
    local action = data.action

    -- 扫荡结果
    if action == Protocol.ACTION_TYPES.DUNGEON_SWEEP then
        pendingSweep, pendingSweepTime = false, 0
        if data.success then
            local dId = data.dungeonId or "gold_mine"
            if DungeonConfig.isResourceDungeon(dId) then
                -- 新资源回执由 ClientMessageHandler 一次展示完整奖励与经验。
                -- 先关闭遮挡副本页；不再更新旧日次，也不重复打开奖励弹窗。
                local overflow = DungeonRewards.overflowText(data)
                if overflow then toast(overflow) end
                leaveDungeonPageForReward()
                return
            end
            print("[DungeonPage] SWEEP OK: floor=" .. tostring(data.sweepFloor)
                .. " gold=" .. tostring(data.gold)
                .. " dust=" .. tostring(data.dust)
                .. " daily=" .. tostring(data.dailyUsed) .. "/" .. tostring(data.dailyMax))
            -- 更新本地显示数据
            dailyUsed = data.dailyUsed or dailyUsed
            dailyMax  = data.dailyMax or dailyMax
            -- 同步 dungeonState
            if dungeonState[dId] then
                dungeonState[dId].dailyUsed = dailyUsed
                dungeonState[dId].dailyMax  = dailyMax
            end

            -- 组装奖励列表并弹出奖励面板
            local rewards = DungeonRewards.build(data)
            local overflow = DungeonRewards.overflowText(data)
            if overflow then toast(overflow) end
            -- [928 修复] 奖励弹出前自动离开副本页，避免奖励被模态页盖住
            leaveDungeonPageForReward()
            require("ui.hud.popup.RewardPopup").show("扫荡奖励", rewards)
        else
            print("[DungeonPage] SWEEP FAIL: " .. tostring(data.reason))
        end
        return
    end

    -- 副本挂机/离线收益领取
    if action == Protocol.ACTION_TYPES.DUNGEON_IDLE_CLAIM then
        pendingIdleClaim = false
        pendingIdleClaimTime = 0
        if data.success then
            local amount = data.amount or 0
            local rewardType = data.rewardType or "gold"
            print("[DungeonPage] IDLE CLAIM OK: dungeon=" .. tostring(data.dungeonId)
                .. " amount=" .. tostring(amount)
                .. " type=" .. tostring(rewardType))
            getDungeonData()
            local dId = data.dungeonId
            if dId and dungeonState[dId] and data.accumSec ~= nil then
                dungeonState[dId].idleAccumSec = data.accumSec
            end
            local rewards = DungeonRewards.build(data)
            local overflow = DungeonRewards.overflowText(data)
            if overflow then toast(overflow) end
            if #rewards > 0 then
                leaveDungeonPageForReward()
                require("ui.hud.popup.RewardPopup").show("挂机奖励", rewards)
            end
        else
            print("[DungeonPage] IDLE CLAIM FAIL: " .. tostring(data.reason))
        end
        return
    end

    -- 挑战结果（服务端返回战斗配置，进入副本战斗场景）
    if action == Protocol.ACTION_TYPES.DUNGEON_CHALLENGE then
        local request = pendingChallengeRequest
        if not pendingChallenge or not request or data.dungeonId ~= request.dungeonId
            or data.floor ~= request.floor or data.teamIdx ~= request.teamIdx then
            print("[DungeonPage] ignored stale/mismatched CHALLENGE")
            return
        end
        if data.success and (data.challengeId == nil or data.stageEntry == nil) then
            print("[DungeonPage] ignored incomplete resource CHALLENGE")
            return
        end
        local teamIdx = request.teamIdx
        clearPendingChallenge()
        if data.success then
            print("[DungeonPage] CHALLENGE OK: dungeon=" .. tostring(data.dungeonId)
                .. " floor=" .. tostring(data.floor)
                .. " monsterLv=" .. tostring(data.monsterLevel))
            -- 关闭详情面板
            local openedDungeonId = data.dungeonId
            detailOpen = false
            detailDungeon = nil
            detailTeamIdx = nil
            -- 打开独立副本战斗场景（类似竞技场）
            local DungeonBattleScene = require("ui.dungeon.DungeonBattleScene")
            local CharacterPanel = require("ui.character.panel.CharacterPanel")
            if dungeonVg_ then DungeonBattleScene.init(dungeonVg_) end
            local allies = CharacterPanel.getDeployedTeam(teamIdx)
            print("[DungeonPage] opening DungeonBattleScene with " .. #allies
                .. " allies, team=" .. teamIdx .. " dungeon=" .. tostring(openedDungeonId))
            DungeonBattleScene.open({
                allies    = allies,
                data      = data,
                dungeonId = openedDungeonId,
                teamIdx = teamIdx,
                onClose   = function()
                    print("[DungeonPage] DungeonBattleScene closed")
                end,
            })
        else
            print("[DungeonPage] CHALLENGE FAIL: " .. tostring(data.reason))
        end
        return
    end

    -- ==================== 通天塔协议处理 ====================

    -- 通天塔挑战结果 → 打开 TowerBattleScene
    if action == Protocol.ACTION_TYPES.TOWER_CHALLENGE then
        local request = pendingChallengeRequest
        if not pendingChallenge or not request or request.dungeonId ~= "babel_tower"
            or data.floor ~= request.floor then
            print("[DungeonPage] ignored stale/mismatched TOWER_CHALLENGE")
            return
        end
        if data.success and (not data.runId or data.wave ~= 1
            or type(data.monsters) ~= "table" or not data.monsterLevel) then
            print("[DungeonPage] ignored incomplete TOWER_CHALLENGE")
            return
        end
        request.accepted = false
        clearPendingChallenge()
        if data.success then
            print("[DungeonPage] TOWER_CHALLENGE OK: floor=" .. tostring(data.floor)
                .. " wave=" .. tostring(data.wave) .. " monsterLv=" .. tostring(data.monsterLevel))
            detailOpen, detailDungeon, detailTeamIdx = false, nil, nil
            local TowerBattleScene = require("ui.tower.TowerBattleScene")
            if dungeonVg_ then
                require("ui.tower.TowerTriBattle").init(dungeonVg_)
                require("ui.tower.TowerBuffPick").init(dungeonVg_)
            end
            local teamAllies, err = collectTowerTeams()
            if not teamAllies then
                require("rules.tower.TowerService").Cleanup(1, data.runId)
                toast(err or "三军攻坚条件未满足")
                return
            end
            TowerBattleScene.open({
                teamAllies = teamAllies,
                allies     = teamAllies[1],
                data       = data,
                sendAction = function(act, params)
                    return require("runtime.GameAction").sendAction(act, params)
                end,
                onCleanup = function(runId)
                    require("rules.tower.TowerService").Cleanup(1, runId)
                end,
                onClose    = function()
                    print("[DungeonPage] TowerBattleScene closed")
                end,
            })
            if TowerBattleScene.isActive() then
                require("ui.hud.BottomNav").setSelectedIndex(3)
                require("ui.battle.tri.BattleTriPage").close()
                request.accepted = true
            else
                require("rules.tower.TowerService").Cleanup(1, data.runId)
                toast("通天塔战斗未能打开，请重试")
            end
        else
            print("[DungeonPage] TOWER_CHALLENGE FAIL: " .. tostring(data.reason))
            toast(data.reason or "通天塔挑战失败")
        end
        return
    end

    -- 通天塔扫荡结果
    if action == Protocol.ACTION_TYPES.TOWER_SWEEP then
        pendingSweep, pendingSweepTime = false, 0
        if data.success then
            print("[DungeonPage] TOWER_SWEEP OK: floor=" .. tostring(data.sweepFloor)
                .. " diamond=" .. tostring(data.diamondReward))
            dungeonState.babel_tower.dailyUsed = data.dailyUsed or 0
            dailyUsed = dungeonState.babel_tower.dailyUsed
            local rewards = data.rewards or {}
            if #rewards == 0 and (data.diamondReward or 0) > 0 then
                rewards[#rewards + 1] = { type = "diamond", amount = data.diamondReward }
            end
            leaveDungeonPageForReward()
            require("ui.hud.popup.RewardPopup").show("扫荡奖励", rewards)
        else
            print("[DungeonPage] TOWER_SWEEP FAIL: " .. tostring(data.reason))
        end
        return
    end

    -- 通天塔波次胜利 → 转发给 TowerBattleScene
    if action == Protocol.ACTION_TYPES.TOWER_WAVE_WIN then
        local TowerBattleScene = require("ui.tower.TowerBattleScene")
        if TowerBattleScene.isActive() then
            TowerBattleScene.onWaveWinResult(data)
        end
        return
    end

    -- 通天塔选卡回执：Scene 自行验证全部请求身份，失败也必须转发以释放对应 pending。
    if action == Protocol.ACTION_TYPES.TOWER_PICK_BUFF then
        local TowerBattleScene = require("ui.tower.TowerBattleScene")
        if TowerBattleScene.isActive() then
            TowerBattleScene.onPickBuffResult(data)
        end
        return
    end

    -- 通天塔整层通关 → 转发给 TowerBattleScene + 更新本地层数
    if action == Protocol.ACTION_TYPES.TOWER_FLOOR_WIN then
        local TowerBattleScene = require("ui.tower.TowerBattleScene")
        if TowerBattleScene.isActive() and TowerBattleScene.onFloorWinResult(data) and data.success then
            dungeonState.babel_tower.floor = math.max(dungeonState.babel_tower.floor,
                data.progressFloor or data.nextFloor or dungeonState.babel_tower.floor)
            currentFloor = dungeonState.babel_tower.floor
        end
        return
    end

    -- ==================== 常规副本协议处理 ====================

    -- 战斗胜利结果
    if action == Protocol.ACTION_TYPES.DUNGEON_WIN then
        local Scene = require("ui.dungeon.DungeonBattleScene")
        if not Scene.onActionResult(data) then return end
        if data.success then
            local st = dungeonState[data.dungeonId]
            if st then st.floor = data.nextFloor or st.floor end
            if detailDungeon and detailDungeon.id == data.dungeonId then currentFloor = st and st.floor or currentFloor end
        else
            toast(data.reason or "副本结算失败")
        end
        return
    end
end

return DungeonPage
