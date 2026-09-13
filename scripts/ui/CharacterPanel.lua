-- ============================================================================
-- CharacterPanel - 角色界面（标签栏第1个标签"角色"）
-- 上半部分：队伍配置（5 编队槽位，3 种状态）
-- ============================================================================

local HC = require("config.HeroConfig")
local CC = require("config.ClassConfig")
local AD = require("systems.AttributeDef")
local GameConfig = require("config.GameConfig")
local GameState       = require("core.GameState")
local CharacterDetail = require("ui.CharacterDetail")
local ExpTable        = require("config.ExpTable")
local ClientDispatcher = require("network.ClientDispatcher")
local PlayerStore      = require("client.data.PlayerStore")
local EquipmentSystem  = require("systems.EquipmentSystem")
local EquipmentConfig  = require("config.EquipmentConfig")
local TalentEffect     = require("systems.TalentEffect")
local AwakeningConfig  = require("config.AwakeningConfig")
local BottomNav        = require("ui.BottomNav")
local RelicBridge      = require("systems.RelicBridge")
local ArtifactBridge   = require("systems.ArtifactBridge")
local AvatarFrameBridge = require("systems.AvatarFrameBridge")
local Draw             = require("ui.CharacterPanelDraw2")
local HeroResonance    = require("shared.heroes.HeroResonance")

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
---@type fun(dx: number, dy: number): number?
local hitTestTeamSlot = Draw.hitTestTeamSlot

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
    for i = 1, MAX_SLOTS do
        local slot = teamSlots[i]
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

--- 对 UnitAttributes 应用指定英雄已穿戴的装备属性
--- 同时供 BattleScene.refreshAllyStats 等外部调用
---@param attrs table UnitAttributes 实例
---@param heroId number
local function applyEquippedItems(attrs, heroId, partySlot)
    -- 优先从 ClientDispatcher 读最新数据（见 refreshPowerCache 注释）
    local eqData = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
    if not eqData or not eqData.equipped or not eqData.equipped[heroId] or not eqData.inventory then
        return nil
    end

    -- 获取槽位强化数据和出战槽位索引
    local slotEnhanceData = ClientDispatcher.get("slotEnhance") or PlayerStore.Get("slotEnhance")
    local heroesData = ClientDispatcher.get("heroes") or PlayerStore.Get("heroes")
    if partySlot == nil then
        partySlot = EquipmentSystem.findPartySlot(heroesData and heroesData.deployed, heroId)
    end

    local heroEq = eqData.equipped[heroId]
    local appliedSeqs = {}
    local equippedArmorType = nil  -- 穿戴护甲对应的护甲类型枚举
    for _, slotKey in ipairs(EquipmentConfig.SLOTS) do
        local seq = heroEq[slotKey]
        if seq and not appliedSeqs[seq] then
            local equip = eqData.inventory[tostring(seq)]
            if equip then
                EquipmentSystem.hydrate(equip)
                -- 计算槽位强化加成
                local slotBoost = 0
                if partySlot and slotEnhanceData then
                    slotBoost = EquipmentSystem.calcSlotBoost(slotEnhanceData, partySlot, slotKey, equip.grip)
                end
                EquipmentSystem.applyToUnit(attrs, equip, seq, slotBoost)
                appliedSeqs[seq] = true
                -- 护甲槽：根据装备 type 字符串映射护甲类型枚举
                if slotKey == "armor" and equip.type then
                    equippedArmorType = AD.ARMOR_TYPE_ENUM[equip.type]
                end
            end
        end
    end
    return equippedArmorType
end

--- 计算角色战斗力（基于 valueModel 加权求和）
--- 遍历所有属性最终值 × 价值权重，跳过六围（已通过派生反映）和运行时/派生属性
local POWER_SKIP = {
    [AD.STR] = true, [AD.AGI] = true, [AD.INT] = true,
    [AD.VIT] = true, [AD.LUK] = true, [AD.SPI] = true,
    [AD.HP]           = true,   -- 运行时当前生命
    [AD.ATK_INTERVAL] = true,   -- 由 atkSpeed 体现
    [AD.PHYS_RES]     = true,   -- 由护甲派生，valueModel=0
    [AD.MAG_RES]      = true,   -- 由护甲派生，valueModel=0
}

local function getHeroLevel(heroId)
    local ownData = ownedSet[heroId]
    return ownData and ownData.level or 1
end

local function getUnlockedAvatarFrames()
    local challenger = ClientDispatcher.get("challenger") or PlayerStore.Get("challenger")
    return challenger and challenger.unlockedAvatarFrames or nil
end

local function applyAvatarFrameAttributes(attrs)
    return AvatarFrameBridge.applyToUnit(attrs, getUnlockedAvatarFrames())
end

local function calcHeroPower(heroId, partySlot)
    if not partySlot then
        for i = 1, MAX_SLOTS do
            local slot = teamSlots[i]
            if slot.state == "occupied" and slot.heroId == heroId then
                partySlot = i
                break
            end
        end
    end
    local level = getHeroLevel(heroId)
    local ownData = ownedSet[heroId]
    local advBranch = ownData and ownData.advBranch or nil
    local awakening = ownData and ownData.awakening or nil
    local hero = HC.createHero(heroId, level, advBranch, awakening)
    if not hero or not hero.attrs then return 0 end
    local a = hero.attrs

    -- 应用已穿戴装备的属性
    applyEquippedItems(a, heroId, partySlot)

    -- 应用遗物无条件常驻属性（A类），使战斗力反映遗物加成
    RelicBridge.applyToUnit(a, hero.classId)

    -- 头像框收藏属性由解锁状态永久累计，不依赖当前穿戴外观
    applyAvatarFrameAttributes(a)

    -- 应用当前出战槽位的神器属性，使战斗力反映神器加成
    if partySlot then
        ArtifactBridge.applyToUnit(a, partySlot)
    end

    local total = 0
    for key, meta in pairs(AD.META) do
        if not POWER_SKIP[key] and meta.valueModel and meta.valueModel > 0 then
            local val = a:get(key)
            if meta.dataType == AD.TYPE_PCT then
                total = total + val * (meta.valueModel / 100)
            else
                total = total + val * meta.valueModel
            end
        end
    end
    -- 加上觉醒节点的固定战力
    total = total + AwakeningConfig.calcTotalCombatPower(heroId, awakening)
    total = total + (a.artifactPowerBonus or 0)

    return math.floor(total + 0.5)
end

--- 刷新所有槽位的战斗力缓存，并同步总战斗力到 GameState（触发 PLAYER_POWER_CHANGED 事件）
local function refreshPowerCache()
    -- 确保天赋数据已同步到 HeroConfig（解决重进游戏时缓存早于服务器数据的时序问题）
    -- 注意: 使用 ClientDispatcher.get() 而非 PlayerStore.Get()，因为本回调的
    -- 注册顺序早于 PlayerStore，ClientDispatcher 的 moduleData 在分发前已更新，
    -- 而 PlayerStore 缓存要等自己的回调才刷新，读它会拿到旧值。
    local talentsData = ClientDispatcher.get("talents") or PlayerStore.Get("talents")
    local litNodes = talentsData and talentsData.litNodes or nil
    if litNodes then
        HC.setDefaultLitNodes(litNodes)
    end

    -- 统计上阵角色数（用于 RUNTIME_ONLY 天赋战力计算）
    local deployedCount = 0
    for i = 1, MAX_SLOTS do
        local slot = teamSlots[i]
        if slot.state == "occupied" and slot.heroId then
            slotPowerCache[i] = calcHeroPower(slot.heroId, i)
            deployedCount = deployedCount + 1
        else
            slotPowerCache[i] = 0
        end
    end

    -- 同步总战斗力到 GameState（触发事件，驱动 SpinePowerUpEffect 等）
    local total = 0
    for i = 1, MAX_SLOTS do
        total = total + (slotPowerCache[i] or 0)
    end

    -- 加上 RUNTIME_ONLY 天赋节点的固定战力（每个节点 × 上阵角色数）
    if litNodes and deployedCount > 0 then
        runtimeOnlyPowerCache = TalentEffect.calcRuntimeOnlyPower(litNodes) * deployedCount
    else
        runtimeOnlyPowerCache = 0
    end
    total = total + runtimeOnlyPowerCache

    GameState.setPower(total)

    -- 标脏 CharacterDetailDraw 的战斗力/装备升级缓存，下次 draw 时按需重算
    CharacterDetail.markPowerDirty()
end

--- 刷新"可提升"角标缓存（仅在数据变更时调用，避免每帧计算）
local function refreshUpgradeBadgeCache()
    upgradeBadgeCache = {}
    for heroId, _ in pairs(ownedSet) do
        if CharacterPanel.isHeroDeployed(heroId) then
            upgradeBadgeCache[heroId] = CharacterDetail.hasAnyUpgradeForHero(heroId)
                or CharacterDetail.hasAwakeningUpgrade(heroId)
        else
            upgradeBadgeCache[heroId] = CharacterDetail.hasAwakeningUpgrade(heroId)
        end
    end
end

--- 刷新 BottomNav "角色"标签(Tab 1)的装备可提升角标
--- 同时刷新 "城镇"标签(Tab 4)的转职可提升角标
local function refreshNavBadge()
    -- 先刷新角标缓存（供 draw 使用，避免每帧重算）
    refreshUpgradeBadgeCache()

    -- Tab 1: 直接复用 upgradeBadgeCache
    local hasUpgrade = false
    for _, v in pairs(upgradeBadgeCache) do
        if v then
            hasUpgrade = true
            break
        end
    end
    BottomNav.setBadge(1, hasUpgrade)

    -- Tab 4: 城镇角标（教堂天赋/转职 + 铁匠铺可强化）
    BottomNav.refreshTownBadge()
end

--- 判断某英雄是否在队伍中出战
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
            -- 2) 已出战排最前，且按槽位顺序排列
            local aSlot = getDeployedSlotIndex(a.heroId)
            local bSlot = getDeployedSlotIndex(b.heroId)
            if aSlot ~= bSlot then
                return aSlot < bSlot
            end
            -- 3) 品质从高到低
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
    local contentBottom = lastRowCY + NAME_BG_DY + NAME_BG_H * 0.5 + 50  -- 50px 底部边距
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
        local totalW = rowCount * CARD_W + (rowCount - 1) * CARD_SPACING
        local startCX = (DESIGN_W - totalW) * 0.5 + CARD_W * 0.5
        local cx = startCX + (col - 1) * (CARD_W + CARD_SPACING)
        local cy = rowCY
        if dx >= cx - CARD_W * 0.5 and dx <= cx + CARD_W * 0.5
           and dy >= cy - CARD_H * 0.5 and dy <= cy + CARD_H * 0.5
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
        getUpgradeBadgeCache = function() return upgradeBadgeCache end,
        getActiveTeamIdx     = function() return activeTeamIdx end,
        getUnlockedTeamCount = function() return ExpTable.getUnlockedTeamCount(GameState.getLevel()) end,
        getTeamOccupiedCounts = function() return CharacterPanel.getTeamOccupiedCounts() end,
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
        local ok, BS = pcall(require, "ui.BattleScene")
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
        local ok, BS = pcall(require, "ui.BattleScene")
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
        local ok, BS = pcall(require, "ui.BattleScene")
        if ok and BS and BS.refreshAllyStats then
            BS.refreshAllyStats()
        end
    end)

    -- 监听挑战者头像框解锁 → 刷新永久收藏属性、战力和战斗待定快照
    PlayerStore.Subscribe("challenger", function()
        refreshPowerCache()
        rebuildRoster()
        local ok, BS = pcall(require, "ui.BattleScene")
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

--- 查询英雄所在队伍索引（不在任何队返回 nil）
---@param heroId number
---@return number|nil
local function findHeroTeamIdx(heroId)
    for t = 1, TEAM_COUNT do
        local slots = teams[t] and teams[t].slots
        if slots then
            for i = 1, #slots do
                local slot = slots[i]
                if slot.state == "occupied" and slot.heroId == heroId then
                    return t
                end
            end
        end
    end
    return nil
end

--- 将英雄部署到指定槽位
---@param heroId number 英雄 ID
---@param slotIdx number 槽位索引（1~MAX_SLOTS）
---@return boolean 是否成功
local function deployHeroToSlot(heroId, slotIdx)
    local slot = teamSlots[slotIdx]
    if not slot then return false end
    if slot.state == "locked" then return false end

    local ownData = ownedSet[heroId]
    if not ownData then
        print("[CharacterPanel] 英雄 " .. heroId .. " 未拥有，无法出战")
        return false
    end

    -- [三队并行] 跨队唯一性: 已在其他队 → 拒绝
    local otherTeam = findHeroTeamIdx(heroId)
    if otherTeam and otherTeam ~= activeTeamIdx then
        print("[CharacterPanel] 英雄已在队伍 " .. otherTeam .. " 中，同一英雄只能在一队")
        return false
    end

    -- 如果该英雄已在其他槽位，先移除
    for i = 1, MAX_SLOTS do
        if teamSlots[i].state == "occupied" and teamSlots[i].heroId == heroId then
            teamSlots[i] = { state = "empty" }
            slotPowerCache[i] = 0
            break
        end
    end

    -- 如果目标槽位已有角色，先取消（回到列表）
    if slot.state == "occupied" and slot.heroId then
        print("[CharacterPanel] 槽位 " .. slotIdx .. " 原角色 " .. slot.heroId .. " 被替换")
    end

    -- 部署
    teamSlots[slotIdx] = {
        state  = "occupied",
        heroId = heroId,
        level  = ownData.level,
        exp    = ownData.exp,
        maxExp = ownData.maxExp,
    }
    slotPowerCache[slotIdx] = calcHeroPower(heroId, slotIdx)

    local heroCfg = HC.get(heroId)
    print("[CharacterPanel] 部署 " .. (heroCfg and heroCfg.name or "?") .. " 到槽位 " .. slotIdx)

    -- 重建列表（排序会变化）
    rebuildRoster()
    refreshPowerCache()
    refreshNavBadge()

    -- 通知阵容变更
    if onTeamChangedCallback then onTeamChangedCallback(activeTeamIdx) end

    require("systems.GameSFX").play("ui_loosen")

    -- 新手引导：若拖拽的是引导高亮的新英雄，触发 drag_to_slot_3 推进
    do
        local _TM = require("systems.TutorialManager")
        if _TM.isActive() and _TM.getNewHeroId() == heroId and slotIdx == 3 then
            _TM.notifyEvent("drag_to_slot_3")
        end
    end

    return true
end

--- 查找第一个可用的空槽位
---@return number|nil 空槽位索引
local function findFirstEmptySlot()
    for i = 1, MAX_SLOTS do
        if teamSlots[i].state == "empty" then
            return i
        end
    end
    return nil
end

-- ======================== 输入处理 ========================

--- 处理点击释放（设计空间坐标）— MouseUp / TouchEnd 时调用
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费了该事件
function CharacterPanel.handleInput(dx, dy)
    -- 0) 详情界面打开时委托给 CharacterDetail
    if CharacterDetail.isOpen() then
        return CharacterDetail.handleInput(dx, dy)
    end

    -- 0.5) [三队并行] 队伍页签点击（释放拖拽到页签上会取消拖拽并切队）
    local tabIdx = Draw.hitTestTeamTabs(dx, dy)
    if tabIdx then
        CharacterPanel.setActiveTeam(tabIdx)
        return true
    end

    -- A) 如果正在拖拽卡片，释放时检测目标槽位
    if dragState.active then
        local slotIdx = hitTestTeamSlot(dx, dy)
        if slotIdx and dragState.fromSlot then
            -- 从出战槽位拖拽到另一个槽位：执行交换
            local srcIdx = dragState.fromSlot
            if slotIdx ~= srcIdx then
                local srcSlot = teamSlots[srcIdx]
                local dstSlot = teamSlots[slotIdx]
                if dstSlot.state == "locked" then
                    print("[CharacterPanel] 目标槽位 " .. slotIdx .. " 未解锁，无法交换")
                elseif dstSlot.state == "empty" then
                    -- 移动到空槽位
                    teamSlots[slotIdx] = srcSlot
                    teamSlots[srcIdx] = { state = "empty" }
                    slotPowerCache[slotIdx] = slotPowerCache[srcIdx] or 0
                    slotPowerCache[srcIdx] = 0
                    print("[CharacterPanel] 移动槽位 " .. srcIdx .. " → " .. slotIdx)
                    rebuildRoster()
                    refreshNavBadge()
                    if onTeamChangedCallback then onTeamChangedCallback(activeTeamIdx) end
                else
                    -- 两个都有角色，交换
                    teamSlots[srcIdx], teamSlots[slotIdx] = teamSlots[slotIdx], teamSlots[srcIdx]
                    slotPowerCache[srcIdx], slotPowerCache[slotIdx] = slotPowerCache[slotIdx], slotPowerCache[srcIdx]
                    print("[CharacterPanel] 交换槽位 " .. srcIdx .. " ↔ " .. slotIdx)
                    rebuildRoster()
                    refreshNavBadge()
                    if onTeamChangedCallback then onTeamChangedCallback(activeTeamIdx) end
                end
            end
        elseif slotIdx and not dragState.fromSlot then
            -- 从角色列表拖拽到槽位：部署
            local slot = teamSlots[slotIdx]
            if slot.state == "empty" or slot.state == "occupied" then
                deployHeroToSlot(dragState.heroId, slotIdx)
            end
        elseif not slotIdx and dragState.fromSlot then
            -- 从出战槽位拖拽到非槽位区域：解除出战
            local srcIdx = dragState.fromSlot
            local srcSlot = teamSlots[srcIdx]
            if srcSlot.state == "occupied" then
                print("[CharacterPanel] 解除出战 槽位 " .. srcIdx .. " 英雄 " .. (srcSlot.heroId or "?"))
                teamSlots[srcIdx] = { state = "empty" }
                slotPowerCache[srcIdx] = 0
                rebuildRoster()
                refreshPowerCache()
                refreshNavBadge()
                if onTeamChangedCallback then onTeamChangedCallback(activeTeamIdx) end
            end
        end
        -- 取消拖拽
        dragState.active = false
        dragState.heroId = nil
        dragState.rosterIdx = nil
        dragState.fromSlot = nil
        return true
    end

    -- B) "选择角色"模式下，点击 roster 卡片进行部署
    if selectSlotState.active then
        local rosterIdx = hitTestRosterCard(dx, dy)
        if rosterIdx then
            local entry = heroRoster[rosterIdx]
            if entry and entry.owned and not isHeroDeployed(entry.heroId) then
                deployHeroToSlot(entry.heroId, selectSlotState.slotIndex)
                selectSlotState.active = false
                selectSlotState.slotIndex = nil
                return true
            elseif entry and entry.owned and isHeroDeployed(entry.heroId) then
                print("[CharacterPanel] 该角色已在出战中")
                return true
            elseif entry and not entry.owned then
                print("[CharacterPanel] 该角色未拥有")
                return true
            end
        end
        -- 点击其他区域取消选择模式
        selectSlotState.active = false
        selectSlotState.slotIndex = nil
        -- 继续后续判断
    end

    -- C) 点击编队槽位
    local slotIdx = hitTestTeamSlot(dx, dy)
    if slotIdx then
        local slot = teamSlots[slotIdx]
        if slot.state == "locked" then
            print("[CharacterPanel] 槽位 " .. slotIdx .. " 未解锁")
        elseif slot.state == "empty" then
            -- 进入"选择角色"模式
            selectSlotState.active = true
            selectSlotState.slotIndex = slotIdx
            print("[CharacterPanel] 槽位 " .. slotIdx .. " 已选中，请点击下方角色出战")
        elseif slot.state == "occupied" then
            -- 点击已出战角色 → 打开角色详情
            print("[CharacterPanel] 查看已出战角色详情: heroId=" .. tostring(slot.heroId))
            require("systems.GameSFX").play("ui_pick")
            CharacterDetail.open(slot.heroId)
        end
        return true
    end

    -- D) 点击角色列表卡片 → 打开角色详情 / 碎片合成
    local rosterIdx = hitTestRosterCard(dx, dy)
    if rosterIdx then
        local entry = heroRoster[rosterIdx]
        if entry and entry.owned then
            -- 引导组9第2步（拖动上阵）：禁止点击打开详情，引导玩家通过拖拽操作上阵
            local _TM = require("systems.TutorialManager")
            if _TM.isActive() and _TM.getCurrentHighlight() == "character_new_hero" then
                print("[CharacterPanel] 引导中：禁止点击打开详情，请拖拽将角色上阵")
                return true
            end
            require("systems.GameSFX").play("ui_pick")
            CharacterDetail.open(entry.heroId)
            return true
        elseif entry and not entry.owned then
            -- 未拥有英雄：检查碎片是否足够合成
            local shards = shardMap[entry.heroId] or 0
            if shards >= HC.SHARD_SYNTHESIZE_COST then
                CharacterPanel.requestSynthesizeHero(entry.heroId)
                return true
            else
                local heroCfg = HC.get(entry.heroId)
                print("[CharacterPanel] " .. (heroCfg and heroCfg.name or "?")
                    .. " 碎片不足，需要 " .. HC.SHARD_SYNTHESIZE_COST
                    .. " 个，当前 " .. shards .. " 个")
            end
            return true
        end
    end

    return false
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
    local Client   = require("network.Client")
    local Protocol = require("shared.Protocol")
    Client.sendAction(Protocol.ACTION_TYPES.SYNTHESIZE_HERO, {
        heroId = heroId,
    })
end

--- 判断坐标是否在滚动区域内
local function isInScrollArea(dx, dy)
    return dx >= SCROLL_LEFT and dx <= SCROLL_RIGHT
       and dy >= SCROLL_TOP  and dy <= SCROLL_BOTTOM
end

--- 拖拽开始（鼠标按下/触摸开始）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
function CharacterPanel.handleDragBegin(dx, dy)
    -- 详情界面打开时委托给 CharacterDetail
    if CharacterDetail.isOpen() then
        return CharacterDetail.handleDragBegin(dx, dy)
    end

    -- 检测是否点中了已占用的出战槽位（用于槽位间拖拽换位）
    local slotIdx = hitTestTeamSlot(dx, dy)
    if slotIdx then
        local slot = teamSlots[slotIdx]
        if slot.state == "occupied" and slot.heroId then
            dragState.startX = dx
            dragState.startY = dy
            dragState.cx = dx
            dragState.cy = dy
            dragState.heroId = slot.heroId
            dragState.fromSlot = slotIdx
            dragState.rosterIdx = nil
            dragState.active = false
            dragState.moved = false
            return true
        end
    end

    -- 在滚动区域内检测是否点中了拥有的角色卡片
    if isInScrollArea(dx, dy) then
        local rosterIdx = hitTestRosterCard(dx, dy)
        if rosterIdx then
            local entry = heroRoster[rosterIdx]
            if entry and entry.owned then
                -- 记录起始位置，但不立即进入拖拽模式（等 move 时判断距离）
                dragState.startX = dx
                dragState.startY = dy
                dragState.cx = dx
                dragState.cy = dy
                dragState.heroId = entry.heroId
                dragState.rosterIdx = rosterIdx
                dragState.fromSlot = nil
                dragState.active = false
                dragState.moved = false
            end
        end
    end

    -- 同时开始滚动拖拽
    if isInScrollArea(dx, dy) then
        isDragging = true
        dragLastY = dy
        dragDeltaY = 0
        scrollVelocity = 0
        return true
    end
    return false
end

local DRAG_THRESHOLD = 30  -- 拖动距离超过此值才进入卡片拖拽模式

--- 拖拽移动（鼠标移动/触摸移动）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
function CharacterPanel.handleDragMove(dx, dy)
    -- 详情界面打开时委托给 CharacterDetail
    if CharacterDetail.isOpen() then
        return CharacterDetail.handleDragMove(dx, dy)
    end

    -- 卡片拖拽检测
    if dragState.heroId and not dragState.active then
        local distX = math.abs(dx - dragState.startX)
        local distY = math.abs(dy - dragState.startY)

        if dragState.fromSlot then
            -- 从出战槽位拖拽：任意方向超过阈值即可
            if distX > DRAG_THRESHOLD or distY > DRAG_THRESHOLD then
                dragState.active = true
                dragState.moved = true
                require("systems.GameSFX").play("ui_pick")
            end
        else
            -- 从角色列表拖拽：向上拖动超过阈值
            if distY > DRAG_THRESHOLD and (dragState.startY - dy) > DRAG_THRESHOLD then
                dragState.active = true
                dragState.moved = true
                require("systems.GameSFX").play("ui_pick")
                -- 停止滚动拖拽
                isDragging = false
                scrollVelocity = 0
            end
        end
    end

    -- 卡片拖拽模式
    if dragState.active then
        dragState.cx = dx
        dragState.cy = dy
        return true
    end

    -- 普通滚动拖拽
    if isDragging then
        dragDeltaY = dragLastY - dy
        scrollY = scrollY + dragDeltaY
        clampScroll()
        dragLastY = dy
        return true
    end

    return false
end

--- 拖拽结束（鼠标释放/触摸结束）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
function CharacterPanel.handleDragEnd(dx, dy)
    -- 详情界面打开时：清除本面板拖拽状态 + 委托给 CharacterDetail
    if CharacterDetail.isOpen() then
        isDragging = false
        dragState.active = false
        dragState.heroId = nil
        dragState.rosterIdx = nil
        dragState.fromSlot = nil
        CharacterDetail.handleDragEnd(dx, dy)
        return true
    end

    -- 如果有待定的卡片拖拽但没真正移动，清除
    if dragState.heroId and not dragState.active then
        dragState.heroId = nil
        dragState.rosterIdx = nil
        dragState.fromSlot = nil
    end

    -- 普通滚动惯性
    if isDragging then
        isDragging = false
        scrollVelocity = -dragDeltaY
    end

    return true
end

--- 鼠标滚轮滚动
---@param wheel number 滚轮值（正=向上，负=向下）
function CharacterPanel.handleScroll(wheel)
    -- 详情界面打开时委托给 CharacterDetail
    if CharacterDetail.isOpen() then
        CharacterDetail.handleScroll(wheel)
        return
    end

    scrollY = scrollY - wheel * SCROLL_WHEEL_STEP
    clampScroll()
    scrollVelocity = 0
end

--- 是否正在进行卡片拖拽（用于输入层判断拖拽落点）
function CharacterPanel.isDraggingCard()
    return dragState.active == true
end

-- ======================== Public API（供 DebugPanel 调用） ========================

--- 获得冒险家（添加到拥有列表）
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
    }
    if not shardMap[heroId] then
        shardMap[heroId] = ownedSet[heroId].shards
    end
    print("[CharacterPanel] 获得冒险家: " .. cfg.name)
    applyResonanceSync()
    rebuildRoster()
    refreshPowerCache()
    refreshNavBadge()
    return true
end

--- 删除冒险家（从拥有列表移除）
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
    print("[CharacterPanel] 删除冒险家: " .. (heroCfg and heroCfg.name or "ID:" .. heroId))
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
            local unit = HC.createHero(slot.heroId, getHeroLevel(slot.heroId), advBranch, awakening)
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
                    -- 应用已解锁头像框的永久累计收藏属性
                    applyAvatarFrameAttributes(unit.attrs)
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

--- 公开当前玩家头像框收藏属性应用方法，供战斗快照刷新与属性展示复用
CharacterPanel.applyAvatarFrameAttributes = applyAvatarFrameAttributes

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
        print(string.format("[CharacterPanel] 队伍%d未解锁（需要冒险等级%s）", idx, tostring(needLv)))
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

--- 刷新槽位解锁状态（冒险等级提升后调用）
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

--- 服务端推送英雄数据时调用（多人模式）
--- 将服务端的 roster/deployed 同步到客户端 ownedSet/teamSlots
---@param data table { roster = { [heroId] = {level,exp,...} }, deployed = { heroId, ... } }
function CharacterPanel.setHeroesData(data)
    if not data then return end

    -- [DIAG-HERO] 入口日志：打印原始 deployed 数组
    do
        local deployedStr = "nil"
        if data.deployed and type(data.deployed) == "table" then
            local ids = {}
            for i, v in ipairs(data.deployed) do ids[i] = tostring(v) end
            deployedStr = "[" .. table.concat(ids, ",") .. "]"
        end
        local rosterCount = 0
        if data.roster then
            for _ in pairs(data.roster) do rosterCount = rosterCount + 1 end
        end
        print(string.format("[DIAG-HERO] setHeroesData ENTER deployed=%s rosterFieldCount=%d",
            deployedStr, rosterCount))
    end

    -- 同步 roster → ownedSet + shardMap。服务端 heroes 是权威源，必须先清空旧区缓存；
    -- 否则特权卡转区后，新区 roster 为空时会继续显示旧区角色。
    ownedSet = {}
    shardMap = {}
    if data.roster then
        for heroId, heroData in pairs(data.roster) do
            local numId = tonumber(heroId) or heroId
            -- 同步碎片（无论是否拥有英雄）
            shardMap[numId] = heroData.shards or 0

            -- 有 level 字段的才是已拥有英雄
            if heroData.level then
                local level = heroData.level
                local exp   = heroData.exp or 0
                local maxExp = heroData.maxExp
                if not maxExp or maxExp == 0 then
                    maxExp = ExpTable.getHeroExpForLevel(level) or 5
                end
                ownedSet[numId] = {
                    level  = level,
                    exp    = exp,
                    maxExp = maxExp,
                    advBranch = heroData.advBranch,
                    awakening = heroData.awakening,
                    dupeCount = heroData.dupeCount or 0,
                    shards = heroData.shards or 0,
                }
            end
        end
    end

    -- [DIAG-HERO] roster同步后，打印 ownedSet 所有key
    do
        local ownedKeys = {}
        for k, v in pairs(ownedSet) do
            ownedKeys[#ownedKeys + 1] = tostring(k) .. "(lv" .. tostring(v.level) .. ")"
        end
        print(string.format("[DIAG-HERO] setHeroesData AFTER_ROSTER ownedSet={%s}",
            table.concat(ownedKeys, ",")))
    end

    -- [三队并行] 同步 deployed/teams → teams[1..3].slots
    -- 队1 以 deployed 为源（兼容镜像）；队2/3 以 data.teams[2..3].slots 为源
    ---@param ids table? heroId 数组（可为 nil）
    ---@return table slots
    local function buildSlotsFromIds(ids)
        local unlocked = ExpTable.getUnlockedSlotCountForTeam(GameState.getLevel())
        -- 🔴 防竞态：全量推送时 player 模块可能尚未分发，getLevel() 返回默认值 1
        -- 此时 unlocked 会偏小。用已部署长度作为下限保证已部署槽位不被锁定
        local cnt = ids and #ids or 0
        if cnt > unlocked then
            unlocked = cnt
        end
        local slots = {}
        for i = 1, MAX_SLOTS do
            slots[i] = { state = (i <= unlocked) and "empty" or "locked" }
        end
        for idx, heroId in ipairs(ids or {}) do
            local numId = tonumber(heroId) or heroId
            if idx <= MAX_SLOTS then
                local ownData = ownedSet[numId]
                if ownData then
                    slots[idx] = {
                        state  = "occupied",
                        heroId = numId,
                        level  = ownData.level,
                        exp    = ownData.exp,
                        maxExp = ownData.maxExp,
                    }
                else
                    -- [DIAG-HERO] 关键：阵容里的英雄不在 ownedSet 中！
                    print(string.format("[DIAG-HERO] WARNING: slots[%d]=%s NOT in ownedSet! Slot stays empty.",
                        idx, tostring(numId)))
                end
            end
        end
        return slots
    end

    if data.deployed then
        teams[1].slots = buildSlotsFromIds(data.deployed)
    end
    if data.teams and type(data.teams) == "table" then
        for t = 2, TEAM_COUNT do
            local tdata = data.teams[t]
            if type(tdata) == "table" and type(tdata.slots) == "table" then
                teams[t].slots = buildSlotsFromIds(tdata.slots)
            end
        end
    end

    -- 重算三队战力缓存 + 重指向当前激活队
    for t = 1, TEAM_COUNT do
        ---@type table
        local cache = teamPowerCaches[t]
        for k in pairs(cache) do cache[k] = nil end
        local slots = teams[t].slots
        for i = 1, #slots do
            if slots[i].state == "occupied" and slots[i].heroId then
                cache[i] = calcHeroPower(slots[i].heroId, i)
            end
        end
    end
    teamSlots = teams[activeTeamIdx].slots
    slotPowerCache = teamPowerCaches[activeTeamIdx]
    -- [DIAG-HERO] 填充后的三队状态
    do
        local teamsInfo = {}
        for t = 1, TEAM_COUNT do
            local ids = {}
            local slots = teams[t].slots
            for i = 1, #slots do
                ids[i] = tostring(slots[i].heroId or (slots[i].state == "locked" and "L" or "-"))
            end
            teamsInfo[t] = "T" .. t .. "[" .. table.concat(ids, ",") .. "]"
        end
        print(string.format("[DIAG-HERO] setHeroesData AFTER_TEAMS active=%d %s",
            activeTeamIdx, table.concat(teamsInfo, " ")))
    end

    -- 重建显示列表
    rebuildRoster()
    refreshPowerCache()
    refreshNavBadge()
end

--- 重置本地角色会话缓存（切区/返回选服时调用）
--- 服务端数据到达前不保留旧区角色，避免新区空 roster 继续显示旧角色。
function CharacterPanel.resetSessionData()
    -- [三队并行] 重置全部队伍
    for t = 1, TEAM_COUNT do
        teams[t].slots = buildDefaultSlots(t)
        teamPowerCaches[t] = {}
    end
    activeTeamIdx = 1
    teamSlots = teams[1].slots
    slotPowerCache = teamPowerCaches[1]
    runtimeOnlyPowerCache = 0
    ownedSet = {}
    shardMap = {}
    heroRoster = {}
    rosterPowerCache = {}
    upgradeBadgeCache = {}
    scrollY = 0
    scrollVelocity = 0
    isDragging = false
    dragState.active = false
    dragState.heroId = nil
    dragState.rosterIdx = nil
    dragState.fromSlot = nil
    selectSlotState.active = false
    selectSlotState.slotIndex = nil
    rebuildRoster()
    refreshPowerCache()
    refreshNavBadge()
    print("[CharacterPanel] session data reset")
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

--- 为英雄增加经验值（支持自动升级）
---@param heroId number 英雄 ID
---@param amount number 经验值数量
function CharacterPanel.addHeroExp(heroId, amount)
    local ownData = ownedSet[heroId]
    if not ownData or amount <= 0 then return end

    ownData.exp = (ownData.exp or 0) + amount

    -- 自动升级循环
    while true do
        local currentLevel = ownData.level or 1
        if ExpTable.isHeroMaxLevel(currentLevel) then
            ownData.exp = 0
            ownData.maxExp = 0
            break
        end
        local needed = ExpTable.getHeroExpForLevel(currentLevel)
        ownData.maxExp = needed or 5
        if not needed or ownData.exp < needed then
            break
        end
        ownData.exp = ownData.exp - needed
        ownData.level = currentLevel + 1
    end

    applyResonanceSync()
    syncTeamSlotsFromOwned()
    rebuildRoster()
    refreshPowerCache()
    refreshNavBadge()
end

--- 同步英雄等级到出战槽位（供 Debug 调用）
---@param heroId number
---@param newLevel number
function CharacterPanel.syncSlotLevel(heroId, newLevel)
    local ownData = ownedSet[heroId]
    if not ownData then return end
    for i = 1, MAX_SLOTS do
        local slot = teamSlots[i]
        if slot.state == "occupied" and slot.heroId == heroId then
            slot.level  = newLevel
            slot.exp    = ownData.exp
            slot.maxExp = ownData.maxExp
            break
        end
    end
    rebuildRoster()
    refreshPowerCache()
    refreshNavBadge()
end

--- 更新英雄的转职分支数据（转职成功后调用，使天赋立即生效）
---@param heroId number 英雄 ID
---@param branchId number 转职分支 ID
---@param advLevel number 转职阶段（1=一转, 2=二转）
function CharacterPanel.setHeroAdvBranch(heroId, branchId, advLevel)
    local ownData = ownedSet[heroId]
    if not ownData then return end
    if not ownData.advBranch then
        ownData.advBranch = {}
    end
    if advLevel == 1 then
        ownData.advBranch.first = branchId
    elseif advLevel == 2 then
        ownData.advBranch.second = branchId
    end
    -- 触发阵容重建，使战斗单元立即获得新的 advTalentIds
    -- 转职变更影响战斗单元 → 固定重建队1
    if onTeamChangedCallback then onTeamChangedCallback(1) end
end

--- 重置英雄转职（清除 advBranch）
---@param heroId number
function CharacterPanel.resetHeroAdvBranch(heroId)
    local ownData = ownedSet[heroId]
    if not ownData then return end
    ownData.advBranch = nil
    -- 触发阵容重建，清除战斗单元上的 advTalentIds
    -- 转职变更影响战斗单元 → 固定重建队1
    if onTeamChangedCallback then onTeamChangedCallback(1) end
end

--- 立即重算并刷新角标（供装备/卸下后即时更新调用）
function CharacterPanel.refreshBadge()
    refreshNavBadge()
end

return CharacterPanel
