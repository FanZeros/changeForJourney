-- ============================================================================
-- CharacterPanel - 角色界面（标签栏第1个标签"角色"）
-- 上半部分：队伍配置（5 编队槽位，3 种状态）
-- ============================================================================

local HC = require("config.HeroConfig")
local CC = require("config.ClassConfig")
local AD = require("systems.AttributeDef")
local GameConfig = require("config.GameConfig")
local GameState       = require("core.GameState")
local CharacterDetail = require("ui.character.detail.CharacterDetail")
local ExpTable        = require("config.ExpTable")
local ClientDispatcher = require("runtime.ClientDispatcher")
local PlayerStore      = require("core.PlayerStore")
local EquipmentSystem  = require("systems.EquipmentSystem")
local EquipmentConfig  = require("config.EquipmentConfig")
local TalentEffect     = require("systems.TalentEffect")
local AwakeningConfig  = require("config.AwakeningConfig")
local BottomNav        = require("ui.hud.BottomNav")
local RelicBridge      = require("systems.RelicBridge")
local ArtifactBridge   = require("systems.ArtifactBridge")
local Draw             = require("ui.character.panel.CharacterPanelDraw2")
local HeroResonance    = require("shared.heroes.HeroResonance")
local CharacterDeploy  = require("ui.character.panel.CharacterDeploy")
local CharacterInput   = require("ui.character.panel.CharacterInput")
local CharacterHeroSync = require("ui.character.panel.CharacterHeroSync")
local CharacterPower    = require("ui.character.panel.CharacterPower")
local CharacterProgress = require("ui.character.panel.CharacterProgress")

local CharacterPanel = {}

-- ======================== 从 Draw 子模块导入共享常量 ========================

local MAX_SLOTS    = Draw.MAX_SLOTS
local CARD_W       = Draw.CARD_W
local CARD_H       = Draw.CARD_H
local CARD_SPACING = Draw.CARD_SPACING
local CARD_CY      = Draw.CARD_CY
local MAX_PER_ROW  = Draw.MAX_PER_ROW
local ROW1_CY      = Draw.ROW1_CY
local ROW_SPACING  = Draw.ROW_SPACING
local NAME_BG_DY   = Draw.NAME_BG_DY
local NAME_BG_H    = Draw.NAME_BG_H
local SCROLL_TOP   = Draw.SCROLL_TOP
local SCROLL_BOTTOM = Draw.SCROLL_BOTTOM
local SCROLL_LEFT  = Draw.SCROLL_LEFT
local SCROLL_RIGHT = Draw.SCROLL_RIGHT
local DESIGN_W     = Draw.DESIGN_W
local DESIGN_H     = GameConfig.Design.HEIGHT  -- 2400

---@type fun(index: number): number
local getSlotCX       = Draw.getSlotCX

-- ======================== 队伍数据 ========================
-- [三队并行] 3 支队伍，每队 4 槽（Draw.MAX_SLOTS）；teamSlots 恒指向当前激活队的槽位数组，
-- 页面既有逻辑（部署/拖拽/交换/绘制）继续读写 teamSlots，页签切换时重指向。
-- 槽位状态: locked=未解锁 / empty=已解锁空位 / occupied=已有角色
local TEAM_COUNT = ExpTable.TEAM_COUNT or 3

---@type table[] teams[i] = { slots = slot[] }
local teams = {}
local activeTeamIdx = 1
local teamSlots = {}       -- = teams[activeTeamIdx].slots（切换页签时重指向）

--- 构建一支队伍的默认槽位
---@param teamIdx number
---@return table slots
local function buildDefaultSlots(teamIdx)
    local unlocked = ExpTable.getUnlockedSlotCountForTeam(GameState.getLevel())
    local slots = {}
    for i = 1, MAX_SLOTS do
        slots[i] = { state = (i <= unlocked) and "empty" or "locked" }
    end
    if teamIdx == 1 then
        -- 队1 保留旧版默认开局阵容（服务端数据到达后会被 setHeroesData 覆盖）
        slots[1] = { state = "occupied", heroId = 1, level = 5, exp = 60, maxExp = ExpTable.getHeroExpForLevel(5) or 40 }
        slots[2] = { state = "occupied", heroId = 3, level = 3, exp = 30, maxExp = ExpTable.getHeroExpForLevel(3) or 18 }
        slots[3] = { state = "empty" }
        slots[4] = { state = "locked" }
    end
    return slots
end

for i = 1, TEAM_COUNT do
    teams[i] = { slots = buildDefaultSlots(i) }
end
teamSlots = teams[activeTeamIdx].slots

--- 每队独立的槽位战力缓存（与 teams 同构切换）
---@type table[] teamPowerCaches[i] = slotPowerCache（索引对应该队槽位）
local teamPowerCaches = {}
for i = 1, TEAM_COUNT do teamPowerCaches[i] = {} end
---@type table
local slotPowerCache = teamPowerCaches[activeTeamIdx]  -- = 当前队的战力缓存

-- ======================== 滚动状态 ========================
local scrollY        = 0      -- 当前滚动偏移（>0 表示内容上移）
local scrollMaxY     = 0      -- 最大滚动值（根据内容高度动态计算）
local scrollVelocity = 0      -- 惯性速度
local isDragging     = false  -- 是否正在拖拽
local dragLastY      = 0      -- 上一帧拖拽 Y 坐标
local dragDeltaY     = 0      -- 拖拽帧间差值（用于计算惯性）
local SCROLL_FRICTION = 0.92  -- 惯性摩擦系数（每帧衰减）
local SCROLL_MIN_VEL  = 0.5   -- 速度低于此值停止惯性
local SCROLL_WHEEL_STEP = 80  -- 鼠标滚轮每格滚动像素

-- 缓存每个槽位的战斗力（避免每帧 createHero）——见上方 teamPowerCaches
local runtimeOnlyPowerCache = 0  -- RUNTIME_ONLY 天赋节点的固定战力总额

-- 缓存"可提升"角标状态（避免每帧全量扫描背包计算装备战力）
-- upgradeBadgeCache[heroId] = boolean
local upgradeBadgeCache = {}


-- 拥有的英雄集合: ownedSet[heroId] = { level, exp, maxExp }
-- 未拥有的英雄不在此表中
local ownedSet = {}

--- 将出战槽位等级与 ownedSet 对齐（共鸣同步后调用）
local function syncTeamSlotsFromOwned()
    -- [三队并行] 同步全部队伍的槽位快照（非激活队也要跟随等级/共鸣变化，否则编队槽显示过期等级）
    for t = 1, TEAM_COUNT do
        local slots = teams[t] and teams[t].slots
        if slots then
            for i = 1, MAX_SLOTS do
                local slot = slots[i]
                if slot.state == "occupied" and slot.heroId then
                    local own = ownedSet[slot.heroId]
                    if own then
                        slot.level  = own.level
                        slot.exp    = own.exp
                        slot.maxExp = own.maxExp
                    end
                end
            end
        end
    end
end

--- 共鸣同步：前 5 高等级最低值提升时，将其余英雄 level 拉到共鸣地板
local function applyResonanceSync()
    local _, boosted = HeroResonance.syncRosterToResonance(ownedSet)
    if boosted > 0 then
        syncTeamSlotsFromOwned()
    end
end

local function getDeployedHeroIds()
    local ids = {}
    for i = 1, MAX_SLOTS do
        local slot = teamSlots[i]
        if slot.state == "occupied" and slot.heroId then
            ids[#ids + 1] = slot.heroId
        end
    end
    return ids
end

-- 碎片缓存: shardMap[heroId] = number（所有英雄，含未拥有的）
local shardMap = {}

-- 角色列表数据（显示用，包含全部英雄，按排序规则排列）
-- 每项: { heroId, level, exp, maxExp, owned }
local heroRoster = {}

-- 缓存角色列表的战斗力
local rosterPowerCache = {}  -- rosterPowerCache[i] = number

-- ======================== 阵容变更回调 ========================

--- 当队伍阵容变更时调用（外部通过 setOnTeamChanged 注册）
---@type fun()|nil
local onTeamChangedCallback = nil

-- ======================== 初始角色配置 ========================

--- 初始英雄 ID 列表（默认为空，由服务端数据推送填充）
--- 可通过 setInitialHeroes() 在新手引导"三选一"后动态设置
local INITIAL_HERO_IDS = {}

-- ======================== 出战交互状态 ========================

-- 拖拽出战状态
local dragState = {
    active   = false,   -- 是否正在拖拽卡牌
    heroId   = nil,     -- 被拖拽的英雄 ID
    rosterIdx = nil,    -- 被拖拽的 roster 索引（从列表拖拽时有值）
    fromSlot  = nil,    -- 被拖拽的槽位索引（从出战槽位拖拽时有值）
    fromTeam  = nil,    -- 被拖拽头像所属队伍（跨队拖放保持源队正确）
    cx       = 0,       -- 当前拖拽位置 X（设计空间）
    cy       = 0,       -- 当前拖拽位置 Y（设计空间）
    startX   = 0,       -- 拖拽起始 X
    startY   = 0,       -- 拖拽起始 Y
    moved    = false,   -- 是否真正产生了位移（区分点击和拖拽）
}

-- 点击选择空槽出战状态
local selectSlotState = {
    active    = false,   -- 是否处于"选择角色"模式
    slotIndex = nil,     -- 选中的空槽位索引
}

-- ======================== 工具函数 ========================

local _power
local function bindPower()
    _power = CharacterPower.bind({
        AD = AD,
        HC = HC,
        ClientDispatcher = ClientDispatcher,
        PlayerStore = PlayerStore,
        EquipmentSystem = EquipmentSystem,
        EquipmentConfig = EquipmentConfig,
        RelicBridge = RelicBridge,
        ArtifactBridge = ArtifactBridge,
        AwakeningConfig = AwakeningConfig,
        TalentEffect = TalentEffect,
        GameState = GameState,
        CharacterDetail = CharacterDetail,
        CharacterPanel = CharacterPanel,
        BottomNav = BottomNav,
        MAX_SLOTS = MAX_SLOTS,
        TEAM_COUNT = TEAM_COUNT,
        get = function(k)
            if k == "ownedSet" then return ownedSet
            elseif k == "teamSlots" then return teamSlots
            elseif k == "teams" then return teams
            elseif k == "teamPowerCaches" then return teamPowerCaches
            end
            return nil
        end,
        set = function(k, v)
            if k == "runtimeOnlyPowerCache" then runtimeOnlyPowerCache = v
            elseif k == "upgradeBadgeCache" then upgradeBadgeCache = v
            end
        end,
    })
end
local function ensurePower()
    if not _power then bindPower() end
    return _power
end

local function applyEquippedItems(attrs, heroId, partySlot)
    return ensurePower().applyEquippedItems(attrs, heroId, partySlot)
end

local function getHeroLevel(heroId)
    return ensurePower().getHeroLevel(heroId)
end

local function calcHeroPower(heroId, partySlot)
    return ensurePower().calcHeroPower(heroId, partySlot)
end

local function refreshPowerCache()
    return ensurePower().refreshPowerCache()
end

local function refreshUpgradeBadgeCache()
    return ensurePower().refreshUpgradeBadgeCache()
end

local function refreshNavBadge()
    return ensurePower().refreshNavBadge()
end

local function isHeroDeployed(heroId)
    for i = 1, MAX_SLOTS do
        local slot = teamSlots[i]
        if slot.state == "occupied" and slot.heroId == heroId then
            return true
        end
    end
    return false
end

--- 获取英雄在出战槽位中的索引（用于排序），未出战返回 MAX_SLOTS+1
local function getDeployedSlotIndex(heroId)
    for i = 1, MAX_SLOTS do
        local slot = teamSlots[i]
        if slot.state == "occupied" and slot.heroId == heroId then
            return i
        end
    end
    return MAX_SLOTS + 1
end

-- 前向声明（rebuildRoster 需要调用 recalcScrollMax）
local recalcScrollMax

--- 重建 heroRoster 列表（全部英雄，按排序规则排列）
--- 排序：拥有且出战 > 拥有未出战（品质高→低，等级高→低）> 未拥有（品质高→低）
local function rebuildRoster()
    heroRoster = {}
    local allIds = HC.getAllIds()
    for _, id in ipairs(allIds) do
        local ownData = ownedSet[id]
        local shards = shardMap[id] or 0
        if ownData then
            heroRoster[#heroRoster + 1] = {
                heroId = id,
                level  = ownData.level,
                exp    = ownData.exp,
                maxExp = ownData.maxExp,
                owned  = true,
                shards = shards,
            }
        else
            heroRoster[#heroRoster + 1] = {
                heroId = id,
                level  = 1,
                exp    = 0,
                maxExp = ExpTable.getHeroExpForLevel(1) or 5,
                owned  = false,
                shards = shards,
            }
        end
    end
    -- 排序
    table.sort(heroRoster, function(a, b)
        -- 1) 拥有的排在未拥有前面
        if a.owned ~= b.owned then
            return a.owned
        end
        if a.owned then
            -- 已出战角色固定排在未出战角色前，但不按编队槽位重排下方名册。
            local aDeployed = getDeployedSlotIndex(a.heroId) <= MAX_SLOTS
            local bDeployed = getDeployedSlotIndex(b.heroId) <= MAX_SLOTS
            if aDeployed ~= bDeployed then
                return aDeployed
            end
            -- 品质从高到低
            local aq = HC.get(a.heroId).quality or 0
            local bq = HC.get(b.heroId).quality or 0
            if aq ~= bq then return aq > bq end
            -- 4) 等级从高到低
            if a.level ~= b.level then return a.level > b.level end
        else
            -- 未拥有的按品质从高到低
            local aq = HC.get(a.heroId).quality or 0
            local bq = HC.get(b.heroId).quality or 0
            if aq ~= bq then return aq > bq end
        end
        -- 5) 相同则按 ID 排序
        return a.heroId < b.heroId
    end)
    -- 刷新战斗力缓存
    for i, entry in ipairs(heroRoster) do
        if entry.owned then
            rosterPowerCache[i] = calcHeroPower(entry.heroId)
        else
            rosterPowerCache[i] = 0
        end
    end
    recalcScrollMax()
end

--- 根据角色总数计算最大滚动值
recalcScrollMax = function()
    local numRows = math.ceil(#heroRoster / MAX_PER_ROW)
    if numRows <= 0 then
        scrollMaxY = 0
        return
    end
    -- 最后一行的名字背景底边 + 底部留白
    local lastRowCY = ROW1_CY + (numRows - 1) * ROW_SPACING
    -- 名字在图标下方 22，再留字高和边距，保证滚到底名字完整
    local contentBottom = lastRowCY + 148 * 0.5 + 64
    scrollMaxY = math.max(0, contentBottom - SCROLL_BOTTOM)
end

--- 限制滚动值在合法范围内
local function clampScroll()
    scrollY = math.max(0, math.min(scrollMaxY, scrollY))
end

--- 根据设计空间坐标找到对应的 roster 卡片索引
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return number|nil roster 索引
local function hitTestRosterCard(dx, dy)
    local rosterCount = #heroRoster
    for idx = 1, rosterCount do
        local row = math.ceil(idx / MAX_PER_ROW)
        local col = idx - (row - 1) * MAX_PER_ROW
        local rowStart = (row - 1) * MAX_PER_ROW + 1
        local rowEnd   = math.min(row * MAX_PER_ROW, rosterCount)
        local rowCount = rowEnd - rowStart + 1
        local rowCY = ROW1_CY + (row - 1) * ROW_SPACING - scrollY
        local iconSize = 148
        local iconGap = 24
        local totalW = rowCount * iconSize + (rowCount - 1) * iconGap
        local startCX = (DESIGN_W - totalW) * 0.5 + iconSize * 0.5
        local cx = startCX + (col - 1) * (iconSize + iconGap)
        local cy = rowCY
        if dx >= cx - iconSize * 0.5 and dx <= cx + iconSize * 0.5
           and dy >= cy - iconSize * 0.5 and dy <= cy + iconSize * 0.5 + 28
           and dy >= SCROLL_TOP and dy <= SCROLL_BOTTOM then
            return idx
        end
    end
    return nil
end

-- ======================== Public API ========================

function CharacterPanel.init(vg)
    -- 绘制子模块：注入共享状态 + 加载图片
    Draw.setContext({
        getTeamSlots        = function() return teamSlots end,
        getHeroRoster       = function() return heroRoster end,
        getSlotPowerCache   = function() return slotPowerCache end,
        getRosterPowerCache = function() return rosterPowerCache end,
        getDragState        = function() return dragState end,
        getSelectSlotState  = function() return selectSlotState end,
        isHeroDeployed      = isHeroDeployed,
        getHeroDeployTeams  = function(h) return CharacterPanel.getHeroDeployTeams(h) end,
        getUpgradeBadgeCache = function() return upgradeBadgeCache end,
        getActiveTeamIdx     = function() return activeTeamIdx end,
        getUnlockedTeamCount = function() return ExpTable.getUnlockedTeamCount(GameState.getLevel()) end,
        getTeamOccupiedCounts = function() return CharacterPanel.getTeamOccupiedCounts() end,
        getTeams = function() return teams end,
        getTeamPowerCaches = function() return teamPowerCaches end,
    })
    Draw.initImages(vg)

    -- 详情界面模块初始化（共享图片句柄来自 Draw 子模块）
    CharacterDetail.init(vg)
    local sharedImg = Draw.getSharedImages()
    CharacterDetail.setContext({
        imgHeroCards   = sharedImg.imgHeroCards,
        imgClassIcons  = sharedImg.imgClassIcons,
        imgPower       = sharedImg.imgPower,
        imgLvlBadge    = sharedImg.imgLvlBadge,
        imgExpBarBg    = sharedImg.imgExpBarBg,
        imgExpBarFill  = sharedImg.imgExpBarFill,
        getOwnedData      = function(heroId) return ownedSet[heroId] end,
        calcHeroPower     = calcHeroPower,
        getHeroRoster     = function() return heroRoster end,
    })

    -- 初始化：清空队伍和拥有列表（[三队并行] 三队重置为默认槽位）
    for t = 1, TEAM_COUNT do
        teams[t].slots = buildDefaultSlots(t)
        teamPowerCaches[t] = {}
    end
    activeTeamIdx = 1
    teamSlots = teams[1].slots
    slotPowerCache = teamPowerCaches[1]
    ownedSet = {}

    -- 解锁并部署初始英雄
    for idx, heroId in ipairs(INITIAL_HERO_IDS) do
        ownedSet[heroId] = { level = 1, exp = 0, maxExp = ExpTable.getHeroExpForLevel(1) or 5 }
        if idx <= 3 then
            teamSlots[idx] = {
                state  = "occupied",
                heroId = heroId,
                level  = 1,
                exp    = 0,
                maxExp = ExpTable.getHeroExpForLevel(1) or 5,
            }
        end
    end

    applyResonanceSync()
    -- 初始化战斗力缓存
    refreshPowerCache()

    -- 监听英雄数据变更 → 碎片/拥有状态变化时刷新列表
    ClientDispatcher.subscribe("heroes", function()
        local heroesData = ClientDispatcher.get("heroes") or PlayerStore.Get("heroes")
        if heroesData then
            CharacterPanel.setHeroesData(heroesData)
        end
        refreshPowerCache()
        local ok, BS = pcall(require, "ui.battle.scene.BattleScene")
        if ok and BS and BS.refreshAllyStats then
            BS.refreshAllyStats()
        end
    end)

    -- 监听装备数据变更 → 穿戴/卸下后自动刷新战斗力缓存
    -- ⚠️ 必须用 PlayerStore.Subscribe 而非 ClientDispatcher.subscribe：
    -- CharacterPanel.init() 早于 PlayerStore.Init() 执行，ClientDispatcher 按注册顺序
    -- 回调，CharacterPanel 的回调会先于 PlayerStore 缓存更新触发，导致
    -- refreshNavBadge() 里 PlayerStore.Get("equipment") 拿到旧数据，角标不刷新。
    -- PlayerStore.Subscribe 的回调在 PlayerStore 更新缓存后才触发，保证数据最新。
    PlayerStore.Subscribe("equipment", function()
        refreshPowerCache()
        rebuildRoster()
        refreshNavBadge()
        -- 装备晚于 heroes 到达时，setAllies 快照不含词缀；需刷新战斗 pending 快照
        local ok, BS = pcall(require, "ui.battle.scene.BattleScene")
        if ok and BS and BS.refreshAllyStats then
            BS.refreshAllyStats()
        end
    end)

    -- 监听天赋数据变更 → 立即刷新战斗力缓存（不能只标记脏，因为用户可能在教堂页面，CharacterPanel 不 draw）
    ClientDispatcher.subscribe("talents", function()
        refreshPowerCache()
    end)

    -- 监听遗物数据变更 → 镶嵌/卸下/洗练后自动刷新战斗力缓存
    PlayerStore.Subscribe("mod_relics", function()
        refreshPowerCache()
    end)

    -- 监听神器数据变更 → 装配/卸下后刷新战斗力与战斗待定快照
    PlayerStore.Subscribe("artifacts", function()
        refreshPowerCache()
        local ok, BS = pcall(require, "ui.battle.scene.BattleScene")
        if ok and BS and BS.refreshAllyStats then
            BS.refreshAllyStats()
        end
    end)

    -- 构建 roster
    rebuildRoster()
    refreshNavBadge()

    print("[CharacterPanel] init OK, roster count: " .. #heroRoster
        .. ", initial heroes: " .. #INITIAL_HERO_IDS
        .. ", scrollMaxY: " .. scrollMaxY)
end

function CharacterPanel.draw(vg)
    -- 委托给 Draw 子模块绘制主界面（编队槽位 + 角色列表 + 拖拽浮层）
    Draw.draw(vg, scrollY)

    -- 角色详情二级界面（覆盖在一切之上）
    CharacterDetail.draw(vg)
end

function CharacterPanel.update(dt)
    -- 惯性滚动（非拖拽卡片时才惯性）
    if not isDragging and not dragState.active and math.abs(scrollVelocity) > SCROLL_MIN_VEL then
        scrollY = scrollY - scrollVelocity
        scrollVelocity = scrollVelocity * SCROLL_FRICTION
        clampScroll()
    else
        if not isDragging and not dragState.active then
            scrollVelocity = 0
        end
    end
end

-- ======================== 出战操作 ========================

local _deploy
local function bindDeploy()
    _deploy = CharacterDeploy.bind({
        HC = HC,
        MAX_SLOTS = MAX_SLOTS,
        TEAM_COUNT = TEAM_COUNT,
        getTeams = function() return teams end,
        getTeamSlots = function() return teamSlots end,
        getActiveTeamIdx = function() return activeTeamIdx end,
        getOwnedSet = function() return ownedSet end,
        getTeamPowerCaches = function() return teamPowerCaches end,
        getSlotPowerCache = function() return slotPowerCache end,
        calcHeroPower = calcHeroPower,
        rebuildRoster = rebuildRoster,
        refreshPowerCache = refreshPowerCache,
        refreshNavBadge = refreshNavBadge,
        getOnTeamChanged = function() return onTeamChangedCallback end,
    })
end

local function findHeroTeamIdx(heroId)
    if not _deploy then bindDeploy() end
    return _deploy.findHeroTeamIdx(heroId)
end

local function deployHeroToSlot(heroId, slotIdx)
    if not _deploy then bindDeploy() end
    return _deploy.deployHeroToSlot(heroId, slotIdx)
end

local function findFirstEmptySlot()
    if not _deploy then bindDeploy() end
    return _deploy.findFirstEmptySlot()
end

-- ======================== 输入处理 ========================

local function isInScrollArea(dx, dy)
    return dx >= SCROLL_LEFT and dx <= SCROLL_RIGHT
       and dy >= SCROLL_TOP  and dy <= SCROLL_BOTTOM
end

local _input
local function bindInput()
    _input = CharacterInput.bind({
        CharacterDetail = CharacterDetail,
        Draw = Draw,
        CharacterPanel = CharacterPanel,
        hitTestRosterCard = hitTestRosterCard,
        getTeamSlots = function() return teamSlots end,
        getSlotPowerCache = function() return slotPowerCache end,
        getDragState = function() return dragState end,
        getSelectSlotState = function() return selectSlotState end,
        getTeams = function() return teams end,
        getTeamPowerCaches = function() return teamPowerCaches end,
        getHeroRoster = function() return heroRoster end,
        getShardMap = function() return shardMap end,
        getActiveTeamIdx = function() return activeTeamIdx end,
        getOnTeamChanged = function() return onTeamChangedCallback end,
        deployHeroToSlot = deployHeroToSlot,
        rebuildRoster = rebuildRoster,
        refreshPowerCache = refreshPowerCache,
        refreshNavBadge = refreshNavBadge,
        isHeroDeployed = isHeroDeployed,
        isInScrollArea = isInScrollArea,
        clampScroll = clampScroll,
        getScroll = function() return scrollY end,
        setScroll = function(v) scrollY = v end,
        getIsDragging = function() return isDragging end,
        setIsDragging = function(v) isDragging = v end,
        getDragLastY = function() return dragLastY end,
        setDragLastY = function(v) dragLastY = v end,
        getDragDeltaY = function() return dragDeltaY end,
        setDragDeltaY = function(v) dragDeltaY = v end,
        setScrollVelocity = function(v) scrollVelocity = v end,
        SCROLL_WHEEL_STEP = SCROLL_WHEEL_STEP,
        HC = HC,
    })
end
local function ensureInput()
    if not _input then bindInput() end
    return _input
end

function CharacterPanel.handleInput(dx, dy)
    return ensureInput().handleInput(dx, dy)
end

---@param dx number
---@param dy number
---@return boolean
function CharacterPanel.handleRightClick(dx, dy)
    return ensureInput().handleRightClick(dx, dy)
end

--- 请求合成英雄（碎片→解锁）
---@param heroId number
function CharacterPanel.requestSynthesizeHero(heroId)
    local heroCfg = HC.get(heroId)
    local heroName = heroCfg and heroCfg.name or ("ID:" .. heroId)
    local shards = shardMap[heroId] or 0
    if shards < HC.SHARD_SYNTHESIZE_COST then
        print("[CharacterPanel] 碎片不足，无法合成 " .. heroName)
        return
    end
    print("[CharacterPanel] 发送合成请求 - heroId=" .. heroId
        .. " 消耗碎片: " .. HC.SHARD_SYNTHESIZE_COST .. " / " .. shards)
    local Client   = require("runtime.GameAction")
    local Protocol = require("shared.Protocol")
    Client.sendAction(Protocol.ACTION_TYPES.SYNTHESIZE_HERO, {
        heroId = heroId,
    })
end

function CharacterPanel.handleDragBegin(dx, dy)
    return ensureInput().handleDragBegin(dx, dy)
end

function CharacterPanel.handleDragMove(dx, dy)
    return ensureInput().handleDragMove(dx, dy)
end

function CharacterPanel.handleHover(dx, dy)
    local CharacterDetail = require("ui.character.detail.CharacterDetail")
    if CharacterDetail.isOpen() and CharacterDetail.handleHover then
        CharacterDetail.handleHover(dx, dy)
    end
end


function CharacterPanel.handleDragEnd(dx, dy)
    return ensureInput().handleDragEnd(dx, dy)
end

function CharacterPanel.handleScroll(wheel, dx, dy)
    return ensureInput().handleScroll(wheel, dx, dy)
end

--- 是否正在进行卡片拖拽（用于输入层判断拖拽落点）
function CharacterPanel.isDraggingCard()
    return dragState.active == true
end

-- ======================== Public API（供 DebugPanel 调用） ========================

--- 获得远征队员（添加到拥有列表）
---@param heroId number 英雄 ID
---@param level number|nil 等级（默认1）
---@return boolean ok
function CharacterPanel.addHero(heroId, level)
    local cfg = HC.get(heroId)
    if not cfg then
        print("[CharacterPanel] 无效英雄 ID: " .. tostring(heroId))
        return false
    end
    if ownedSet[heroId] then
        print("[CharacterPanel] 英雄 " .. heroId .. " 已拥有（碎片由服务端处理）")
        return false
    end
    level = level or 1
    ownedSet[heroId] = {
        level     = level,
        exp       = 0,
        maxExp    = ExpTable.getHeroExpForLevel(level) or 5,
        dupeCount = 0,
        shards    = shardMap[heroId] or 0,
        advBranch = nil,
        awakening = nil,
        extraTalent = require("systems.ExtraTalentSystem").normalize(nil),
    }
    if not shardMap[heroId] then
        shardMap[heroId] = ownedSet[heroId].shards
    end
    print("[CharacterPanel] 获得远征队员: " .. cfg.name)
    applyResonanceSync()
    rebuildRoster()
    refreshPowerCache()
    refreshNavBadge()
    return true
end

--- 删除远征队员（从拥有列表移除）
---@param heroId number 英雄 ID
function CharacterPanel.removeHero(heroId)
    if not ownedSet[heroId] then
        print("[CharacterPanel] 英雄 " .. heroId .. " 未拥有，无法删除")
        return
    end
    -- 如果该英雄在队伍中，先移除（[三队并行] 扫描全部队伍）
    local wasInTeam = nil
    for t = 1, TEAM_COUNT do
        local slots = teams[t].slots
        for i = 1, #slots do
            if slots[i].state == "occupied" and slots[i].heroId == heroId then
                slots[i] = { state = "empty" }
                teamPowerCaches[t][i] = 0
                wasInTeam = wasInTeam or t
            end
        end
    end
    ownedSet[heroId] = nil
    local heroCfg = HC.get(heroId)
    print("[CharacterPanel] 删除远征队员: " .. (heroCfg and heroCfg.name or "ID:" .. heroId))
    refreshPowerCache()
    rebuildRoster()
    refreshNavBadge()

    -- 如果被删除的英雄原本在队伍中，通知阵容变更（队1 需重建战斗单元）
    if wasInTeam then
        if wasInTeam == 1 then
            if onTeamChangedCallback then onTeamChangedCallback(1) end
        elseif wasInTeam == activeTeamIdx then
            if onTeamChangedCallback then onTeamChangedCallback(activeTeamIdx) end
        end
    end
end

--- 检查某英雄是否已拥有
---@param heroId number
---@return boolean
function CharacterPanel.isOwned(heroId)
    return ownedSet[heroId] ~= nil
end

--- 获取某英雄的拥有数据（level, exp, maxExp）
---@param heroId number
---@return table|nil
function CharacterPanel.getOwnedHero(heroId)
    return ownedSet[heroId]
end

--- 写入追加技永久层（本地 ownedSet + Dispatcher 镜像，不触发整表重建）
---@param heroId number
---@param extra table
function CharacterPanel.patchExtraTalent(heroId, extra)
    heroId = tonumber(heroId)
    if not heroId then return end
    extra = require("systems.ExtraTalentSystem").normalize(extra)
    local owned = ownedSet[heroId]
    if owned then
        owned.extraTalent = extra
    end
    local disp = ClientDispatcher.get("heroes")
    if disp and disp.roster then
        local hd = disp.roster[heroId] or disp.roster[tostring(heroId)]
        if hd then
            hd.extraTalent = extra
        end
    end
end

--- 获取某英雄的重复获得次数（旧接口，兼容保留）
---@param heroId number
---@return number dupeCount 0-7
function CharacterPanel.getDupeCount(heroId)
    local d = ownedSet[heroId]
    return d and (d.dupeCount or 0) or 0
end

--- 获取某英雄当前碎片数
---@param heroId number
---@return number shards
function CharacterPanel.getShards(heroId)
    return shardMap[heroId] or 0
end

--- 判断某英雄是否已出战（轻量版，不创建 hero 实例）
--- [三队并行] 扫描全部队伍（同一英雄同一时刻只能在一队）
---@param heroId number
---@return boolean
function CharacterPanel.isHeroDeployed(heroId)
    for t = 1, TEAM_COUNT do
        local slots = teams[t] and teams[t].slots
        if slots then
            for i = 1, #slots do
                local slot = slots[i]
                if slot.state == "occupied" and slot.heroId == heroId then
                    return true
                end
            end
        end
    end
    return false
end

--- 获取英雄出战的所有队伍编号（[三队并行] 队1/队2/队3），未出战返回空表
---@param heroId number
---@return integer[]
function CharacterPanel.getHeroDeployTeams(heroId)
    local result = {}
    for t = 1, TEAM_COUNT do
        local slots = teams[t] and teams[t].slots
        if slots then
            for i = 1, #slots do
                local slot = slots[i]
                if slot.state == "occupied" and slot.heroId == heroId then
                    result[#result + 1] = t
                    break
                end
            end
        end
    end
    return result
end

--- 槽位阵容签名：只包含英雄 ID 与槽位顺序，经验/属性刷新不应重开战斗
---@param teamIdx number
---@return string
function CharacterPanel.getTeamSignature(teamIdx)
    local slots = (teams[teamIdx] and teams[teamIdx].slots) or {}
    local ids = {}
    for i = 1, MAX_SLOTS do
        local slot = slots[i]
        ids[i] = tostring(slot and slot.state == "occupied" and slot.heroId or 0)
    end
    return table.concat(ids, ",")
end

--- 获取指定队伍的战斗单位列表（供 BattleScene / 三栏并行战斗使用）
--- [三队并行] 缺省 teamIdx=1（主线战斗沿用队1，与旧行为一致）
---@param teamIdx? number 队伍索引（1~3），缺省 1
---@return table[] 战斗单位列表，每项由 HC.createHero 生成，并应用已穿戴装备属性
function CharacterPanel.getDeployedTeam(teamIdx)
    teamIdx = tonumber(teamIdx) or 1
    local slots = (teams[teamIdx] and teams[teamIdx].slots) or {}
    -- [DIAG-HERO] 入口：打印当前队伍槽位快照
    do
        local slotInfo = {}
        for i = 1, #slots do
            local s = slots[i]
            slotInfo[i] = string.format("%d:%s(%s)", i, s.state, tostring(s.heroId or "-"))
        end
        print(string.format("[DIAG-HERO] getDeployedTeam ENTER team=%d slots={%s}", teamIdx, table.concat(slotInfo, ",")))
    end
    local team = {}
    for i = 1, #slots do
        local slot = slots[i]
        if slot.state == "occupied" and slot.heroId then
            local ownData = ownedSet[slot.heroId]
            local advBranch = ownData and ownData.advBranch or nil
            local awakening = ownData and ownData.awakening or nil
            local unit = HC.createHero(slot.heroId, getHeroLevel(slot.heroId), advBranch, awakening, ownData and ownData.extraTalent)
            if unit then
                -- 应用已穿戴装备属性
                if unit.attrs then
                    local eqArmorType = applyEquippedItems(unit.attrs, slot.heroId, i)
                    if eqArmorType then
                        unit.armorType = eqArmorType
                    end
                    -- 应用遗物词条属性加成（A类无条件 + 返回B/C类条件词条供战斗运行时使用）
                    local relicConds = RelicBridge.applyToUnit(unit.attrs, unit.classId)
                    if relicConds and #relicConds > 0 then
                        unit.relicConditions = relicConds
                    end
                    -- 应用神器属性加成与战斗运行时效果
                    local artifactEffects = ArtifactBridge.applyToUnit(unit.attrs, i)
                    if artifactEffects and #artifactEffects > 0 then
                        unit.artifactEffects = artifactEffects
                    end
                    -- 装备可能增加 maxHp，recalc 不会自动抬升 HP，需重新满血
                    unit.attrs:fillHp()
                    -- 重新同步 flat 字段
                    unit.maxHp      = unit.attrs.final[AD.MAX_HP]
                    unit.hp         = unit.attrs.final[AD.HP]
                    unit.atkInterval = unit.attrs:getActualInterval()
                end
                team[#team + 1] = unit
            end
        end
    end
    return team
end

--- 公开装备属性应用方法，供 BattleScene 等外部模块使用
CharacterPanel.applyEquippedItems = applyEquippedItems

--- 注册阵容变更回调（队伍出战变化时自动调用）
---@param callback fun() 回调函数
function CharacterPanel.setOnTeamChanged(callback)
    onTeamChangedCallback = callback
end

--- 设置初始英雄列表（新手引导"三选一"后调用）
--- 会解锁这些英雄并自动部署到出战槽位
---@param heroIds number[] 英雄 ID 列表
---@param level? number 初始等级，默认 1
function CharacterPanel.setInitialHeroes(heroIds, level)
    level = level or 1
    INITIAL_HERO_IDS = heroIds
    -- [三队并行] 重置三队默认槽位，初始英雄部署到队1（新手阶段仅队1解锁）
    for t = 1, TEAM_COUNT do
        teams[t].slots = buildDefaultSlots(t)
    end
    activeTeamIdx = 1
    teamSlots = teams[1].slots
    slotPowerCache = teamPowerCaches[1]
    ownedSet = {}
    -- 解锁并部署初始英雄（队1）
    for idx, heroId in ipairs(heroIds) do
        ownedSet[heroId] = { level = level, exp = 0, maxExp = ExpTable.getHeroExpForLevel(level) or 5 }
        if idx <= 3 then -- 只部署到前3个可用槽位
            teamSlots[idx] = {
                state  = "occupied",
                heroId = heroId,
                level  = level,
                exp    = 0,
                maxExp = ExpTable.getHeroExpForLevel(level) or 5,
            }
            slotPowerCache[idx] = calcHeroPower(heroId, idx)
        end
    end
    applyResonanceSync()
    refreshPowerCache()
    rebuildRoster()
    refreshNavBadge()
    print("[CharacterPanel] 初始英雄设置完成, 数量: " .. #heroIds)
    -- 通知阵容变更
    if onTeamChangedCallback then onTeamChangedCallback(activeTeamIdx) end
end

--- 获取当前队伍总战斗力（各出战槽位战斗力之和）
---@return number
function CharacterPanel.getTotalPower()
    local total = 0
    for i = 1, MAX_SLOTS do
        total = total + (slotPowerCache[i] or 0)
    end
    return total + runtimeOnlyPowerCache
end

--- 强制重新计算所有槽位战力缓存并刷新 TopBar（供外部模块触发，如槽位强化后）
function CharacterPanel.refreshPower()
    refreshPowerCache()
end

--- 获取队伍槽位数据（只读，供 PlayerInfoPanel 显示队伍配置）
--- 返回当前激活队的 teamSlots 数组和 slotPowerCache 数组
---@return table[] teamSlots
---@return table slotPowerCache
function CharacterPanel.getTeamSlotsData()
    return teamSlots, slotPowerCache
end

-- ======================== [三队并行] 队伍页签 ========================

--- 当前激活队伍索引
---@return number
function CharacterPanel.getActiveTeamIdx()
    return activeTeamIdx
end

--- 已解锁的队伍数量
---@return number
function CharacterPanel.getUnlockedTeamCount()
    return ExpTable.getUnlockedTeamCount(GameState.getLevel())
end

--- 各队上阵人数（供页签角标显示）
---@return number[]
function CharacterPanel.getTeamOccupiedCounts()
    local counts = {}
    for t = 1, TEAM_COUNT do
        local n = 0
        local slots = teams[t] and teams[t].slots
        if slots then
            for i = 1, #slots do
                if slots[i].state == "occupied" then n = n + 1 end
            end
        end
        counts[t] = n
    end
    return counts
end

--- 切换当前编辑的队伍（不触发阵容提交，也不影响队1战斗）
---@param idx number 队伍索引（1~3）
---@return boolean 是否切换成功
function CharacterPanel.setActiveTeam(idx)
    idx = tonumber(idx)
    if not idx or idx < 1 or idx > TEAM_COUNT then return false end
    if idx == activeTeamIdx then return true end
    if idx > ExpTable.getUnlockedTeamCount(GameState.getLevel()) then
        local needLv = ExpTable.getTeamUnlockLevel(idx)
        print(string.format("[CharacterPanel] 队伍%d未解锁（需要远征等级%s）", idx, tostring(needLv)))
        return false
    end
    activeTeamIdx = idx
    teamSlots = teams[activeTeamIdx].slots
    slotPowerCache = teamPowerCaches[activeTeamIdx]
    -- 取消进行中的拖拽/选择，避免跨队错位
    dragState.active = false
    dragState.heroId = nil
    dragState.rosterIdx = nil
    dragState.fromSlot = nil
    dragState.fromTeam = nil
    selectSlotState.active = false
    selectSlotState.slotIndex = nil
    rebuildRoster()
    refreshPowerCache()
    refreshNavBadge()
    print("[CharacterPanel] 切换到队伍 " .. idx)
    return true
end

--- 查询详情界面是否打开（供外部判断是否需要隐藏 TopBar/BottomNav）
---@return boolean
function CharacterPanel.isDetailOpen()
    return CharacterDetail.isOpen()
end

--- 刷新槽位解锁状态（远征等级提升后调用）
--- 将 locked 但已达到解锁等级的槽位变为 empty，不影响已占用的槽位
--- [三队并行] 三支队伍的槽位解锁状态一起刷新
function CharacterPanel.refreshSlotUnlocks()
    local unlocked = ExpTable.getUnlockedSlotCountForTeam(GameState.getLevel())
    for t = 1, TEAM_COUNT do
        local slots = teams[t] and teams[t].slots
        if slots then
            for i = 1, #slots do
                if slots[i].state == "locked" and i <= unlocked then
                    slots[i] = { state = "empty" }
                    print("[CharacterPanel] 队伍" .. t .. " 槽位 " .. i .. " 已解锁")
                end
            end
        end
    end
    refreshPowerCache()
    rebuildRoster()
end

local _heroSync
local function bindHeroSync()
    _heroSync = CharacterHeroSync.bind({
        ExpTable = ExpTable,
        GameState = GameState,
        MAX_SLOTS = MAX_SLOTS,
        TEAM_COUNT = TEAM_COUNT,
        get = function(k)
            if k == "teams" then return teams
            elseif k == "teamPowerCaches" then return teamPowerCaches
            elseif k == "activeTeamIdx" then return activeTeamIdx
            elseif k == "dragState" then return dragState
            elseif k == "selectSlotState" then return selectSlotState
            end
            return nil
        end,
        set = function(k, v)
            if k == "ownedSet" then ownedSet = v
            elseif k == "shardMap" then shardMap = v
            elseif k == "teamSlots" then teamSlots = v
            elseif k == "slotPowerCache" then slotPowerCache = v
            elseif k == "activeTeamIdx" then activeTeamIdx = v
            elseif k == "runtimeOnlyPowerCache" then runtimeOnlyPowerCache = v
            elseif k == "heroRoster" then heroRoster = v
            elseif k == "rosterPowerCache" then rosterPowerCache = v
            elseif k == "upgradeBadgeCache" then upgradeBadgeCache = v
            elseif k == "scrollY" then scrollY = v
            elseif k == "scrollVelocity" then scrollVelocity = v
            elseif k == "isDragging" then isDragging = v
            end
        end,
        buildDefaultSlots = buildDefaultSlots,
        calcHeroPower = calcHeroPower,
        rebuildRoster = rebuildRoster,
        refreshPowerCache = refreshPowerCache,
        refreshNavBadge = refreshNavBadge,
    })
end
local function ensureHeroSync()
    if not _heroSync then bindHeroSync() end
    return _heroSync
end

function CharacterPanel.setHeroesData(data)
    return ensureHeroSync().setHeroesData(data)
end

function CharacterPanel.resetSessionData()
    return ensureHeroSync().resetSessionData()
end

--- 获取当前共鸣等级（全队前 5 高等级中的最低值）
function CharacterPanel.getResonanceLevel()
    return HeroResonance.computeResonanceLevel(ownedSet)
end

--- 获取英雄等级（兼容旧接口名）
---@param heroId number
---@return number
function CharacterPanel.getEffectiveLevel(heroId)
    return getHeroLevel(heroId)
end

local _progress
local function bindProgress()
    _progress = CharacterProgress.bind({
        ExpTable = ExpTable,
        MAX_SLOTS = MAX_SLOTS,
        get = function(k)
            if k == "ownedSet" then return ownedSet
            elseif k == "teamSlots" then return teamSlots
            elseif k == "onTeamChangedCallback" then return onTeamChangedCallback
            end
            return nil
        end,
        applyResonanceSync = applyResonanceSync,
        syncTeamSlotsFromOwned = syncTeamSlotsFromOwned,
        rebuildRoster = rebuildRoster,
        refreshPowerCache = refreshPowerCache,
        refreshNavBadge = refreshNavBadge,
    })
end
local function ensureProgress()
    if not _progress then bindProgress() end
    return _progress
end

function CharacterPanel.addHeroExp(heroId, amount)
    return ensureProgress().addHeroExp(heroId, amount)
end

function CharacterPanel.syncSlotLevel(heroId, newLevel)
    return ensureProgress().syncSlotLevel(heroId, newLevel)
end

function CharacterPanel.setHeroAdvBranch(heroId, branchId, advLevel)
    return ensureProgress().setHeroAdvBranch(heroId, branchId, advLevel)
end

function CharacterPanel.resetHeroAdvBranch(heroId)
    return ensureProgress().resetHeroAdvBranch(heroId)
end

--- 立即重算并刷新角标（供装备/卸下后即时更新调用）
function CharacterPanel.refreshBadge()
    refreshNavBadge()
end

return CharacterPanel
