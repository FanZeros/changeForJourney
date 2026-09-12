-- ============================================================================
-- DebugPanel - 调试面板（设计区域左侧 screen space）
-- 功能: 增减己方/敌方队伍单位数量, 己方单位使用 HeroConfig 创建完整属性的英雄角色
-- ============================================================================

local BattleScene = require("ui.BattleScene")
local SC = require("config.StageConfig")
local MC = require("config.MonsterConfig")
local HC = require("config.HeroConfig")
local AD = require("systems.AttributeDef")
local HeroRosterPanel = require("ui.HeroRosterPanel")
local CharacterPanel  = require("ui.CharacterPanel")
local EquipmentConfig = require("config.EquipmentConfig")
local ExpTable        = require("config.ExpTable")

-- Client / Protocol 延迟加载（避免与 network.Client 循环依赖）
---@type table
local Client_
---@type table
local Protocol_
local function getClient()
    if not Client_ then Client_ = require("network.Client") end
    return Client_
end
local function getProtocol()
    if not Protocol_ then Protocol_ = require("shared.Protocol") end
    return Protocol_
end

local GameConfig = require("config.GameConfig")
local GameState  = require("core.GameState")

-- Debug 面板仅认服务端推送的 GM 标记。名字白名单可被改客户端绕过，已移除。
local function isDebugAllowed()
    return getClient().isGM() == true
end
local BattleEffects = require("ui.BattleEffects")
local OfflineRewardPanel = require("ui.OfflineRewardPanel")

-- Standalone 延迟加载（避免与 Standalone→DebugPanel 循环依赖）
---@type table
local Standalone_
local function getStandalone()
    if not Standalone_ then Standalone_ = require("network.Standalone") end
    return Standalone_
end

---@type table
local DungeonBattle_
local function getDungeonBattle()
    if not DungeonBattle_ then DungeonBattle_ = require("ui.DungeonBattle") end
    return DungeonBattle_
end

---@type table
local DungeonBattleScene_
local function getDungeonBattleScene()
    if not DungeonBattleScene_ then DungeonBattleScene_ = require("ui.DungeonBattleScene") end
    return DungeonBattleScene_
end

-- IntroCutscene / ScenarioDialogue / CharacterSelect 延迟加载
---@type table
local IntroCutscene_
local function getIntroCutscene()
    if not IntroCutscene_ then IntroCutscene_ = require("ui.IntroCutscene") end
    return IntroCutscene_
end
local ScenarioDialogue_
local function getScenarioDialogue()
    if not ScenarioDialogue_ then ScenarioDialogue_ = require("ui.ScenarioDialogue") end
    return ScenarioDialogue_
end
local ScenarioDialogueConfig_
local function getScenarioDialogueConfig()
    if not ScenarioDialogueConfig_ then ScenarioDialogueConfig_ = require("config.ScenarioDialogueConfig") end
    return ScenarioDialogueConfig_
end
local CharacterSelect_
local function getCharacterSelect()
    if not CharacterSelect_ then CharacterSelect_ = require("ui.CharacterSelect") end
    return CharacterSelect_
end

local DebugPanel = {}

-- ======================== 配置 ========================

local PANEL_W     = 280   -- 面板宽度（screen space 单位）
local PANEL_PAD   = 20    -- 内边距
local BTN_H       = 60    -- 按钮高度
local BTN_GAP     = 12    -- 按钮间距
local TITLE_H     = 50    -- 标题高度
local SECTION_GAP = 24    -- 分组间距

local BG_COLOR     = { 30, 30, 45, 220 }
local TITLE_COLOR  = { 255, 200, 60, 255 }
local LABEL_COLOR  = { 200, 200, 210, 255 }
local BTN_ADD_COLOR = { 50, 160, 80, 255 }
local BTN_SUB_COLOR = { 180, 50, 50, 255 }
local BTN_TEXT_COLOR = { 255, 255, 255, 255 }

-- ======================== 状态 ========================

local vgRef = nil

-- 默认出战英雄 ID 队列（依次添加）
local DEFAULT_HERO_IDS = { 1, 3, 2, 4, 5 }  -- 卡琳, 琳达, 麦琪, 塞西莉亚, 维多利亚

-- 调试用己方等级
local debugAllyLevel = 1

-- 敌方可选怪物 ID 池（普通级 + 精英级，调试用）
local ENEMY_POOL = {}
do
    for _, q in ipairs({1, 2, 3}) do
        for _, id in ipairs(MC.getIdsByQuality(q)) do
            ENEMY_POOL[#ENEMY_POOL + 1] = id
        end
    end
    table.sort(ENEMY_POOL)
end

-- 己方单位列表
local allies = {}

-- 指定英雄 ID 选择器（仅有效 HeroConfig ID）
local heroIdList = HC.getAllIds()
local selectedHeroIdx = 1

local function getSelectedHeroId()
    return heroIdList[selectedHeroIdx] or heroIdList[1] or 1
end

local function cycleSelectedHero(delta)
    if #heroIdList == 0 then return 1 end
    selectedHeroIdx = selectedHeroIdx + delta
    if selectedHeroIdx < 1 then selectedHeroIdx = #heroIdList end
    if selectedHeroIdx > #heroIdList then selectedHeroIdx = 1 end
    return heroIdList[selectedHeroIdx]
end

-- 装备生成参数（4 个槽位独立编号选择器）
local EQUIP_SLOTS = { "weapon", "offhand", "armor", "accessory" }
local EQUIP_SLOT_LABELS = {
    weapon    = "武器",
    offhand   = "副手",
    armor     = "防具",
    accessory = "饰品",
}
local equipNums = { weapon = 1, offhand = 1, armor = 1, accessory = 1 }
local equipQuality    = 1    -- 1~5
local equipLevel      = 1    -- 1~99
local MAX_EQUIP_QUALITY  = 5
local MAX_EQUIP_LEVEL    = 99

-- 遗物生成参数
local relicType    = 1    -- 1~5 (岩龟/毒蛇/白鹿/灰狼/猎鹰)
local relicQuality = 1    -- 1~6
local MAX_RELIC_TYPE    = 5
local MAX_RELIC_QUALITY = 6
local RELIC_TYPE_NAMES  = { "岩龟", "毒蛇", "白鹿", "灰狼", "猎鹰" }
local RELIC_QUALITY_NAMES = { "普通", "优质", "稀有", "史诗", "传说", "至臻" }
local RELIC_QUALITY_COLORS = {
    [1] = { 0xb5, 0xb5, 0xb5 },
    [2] = { 0xa2, 0xff, 0x94 },
    [3] = { 0x72, 0xf2, 0xf5 },
    [4] = { 0xef, 0x79, 0xff },
    [5] = { 0xff, 0xed, 0x00 },
    [6] = { 0xff, 0x00, 0x00 },
}

-- 资源获取选择器
local selectedResIdx = 1   -- 当前选中的资源索引 (1~#GameConfig.Resources)

-- 清除存档二次确认状态（防止误触）
local resetConfirmClock = 0   -- 首次点击的 os.clock()，3秒内再次点击才执行
local RESET_CONFIRM_TIMEOUT = 3.0  -- 确认超时秒数

-- 按钮区域列表（每帧 draw 时重建，用于点击检测）
local buttons = {}

-- ======================== 工具函数 ========================

--- 创建英雄单位（使用 HeroConfig + UnitAttributes 完整属性）
---@param heroId number 英雄序号
---@param level number 等级
---@return table|nil 战斗单位
local function createAllyHero(heroId, level)
    local ownData = CharacterPanel.getOwnedHero(heroId)
    local advBranch = ownData and ownData.advBranch or nil
    local awakening = ownData and ownData.awakening or nil
    local unit = HC.createHero(heroId, level, advBranch, awakening)
    if not unit then
        -- 兜底：如果英雄 ID 无效，创建简单单位
        return {
            name = "未知英雄",
            level = level,
            hp = 150,
            maxHp = 150,
            atkProgress = 0.0,
            atkInterval = 1.5,
        }
    end
    return unit
end

local function syncAlliesToBattle()
    BattleScene.setAllies(allies)
end

local function getAwakeLevel(heroId)
    local ownData = CharacterPanel.getOwnedHero(heroId)
    if not ownData or not ownData.awakening then return 0 end
    local count = 0
    for i = 1, 7 do
        if ownData.awakening[i] then
            count = count + 1
        end
    end
    return count
end

local function drawRoundedBtn(vg, x, y, w, h, r, g, b, a, text, radius)
    radius = radius or 10
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, radius)
    nvgFillColor(vg, nvgRGBA(r, g, b, a))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(BTN_TEXT_COLOR[1], BTN_TEXT_COLOR[2], BTN_TEXT_COLOR[3], BTN_TEXT_COLOR[4]))
    nvgText(vg, x + w * 0.5, y + h * 0.5, text, nil)
end

local function registerBtn(id, x, y, w, h)
    buttons[#buttons + 1] = { id = id, x = x, y = y, w = w, h = h }
end

-- ======================== Public API ========================

function DebugPanel.init(vg)
    vgRef = vg
    -- 从 CharacterPanel 获取已出战阵容（不再硬编码）
    allies = CharacterPanel.getDeployedTeam()
    if #allies == 0 then
        -- 兜底：如果角色面板尚未部署任何英雄，用默认英雄
        allies[1] = createAllyHero(DEFAULT_HERO_IDS[1], debugAllyLevel)
    end
    syncAlliesToBattle()
    print("[DebugPanel] init OK - 初始阵容: " .. #allies .. " 个英雄")
end

--- 绘制调试面板
---@param vg any
---@param designOffsetX number 设计区域左边距（screen space）
---@param screenDesignW number 屏幕设计宽度（screen space）
function DebugPanel.draw(vg, designOffsetX, screenDesignW)
    if not isDebugAllowed() then return end
    buttons = {}

    -- 每帧刷新 allies 引用，避免与 BattleScene 实际阵容脱节
    local freshAllies = BattleScene.getAllies()
    if freshAllies and #freshAllies > 0 then
        allies = freshAllies
    end

    local DESIGN_W = 1080
    local rightEdge = designOffsetX + DESIGN_W
    local panelX = rightEdge + 10
    if panelX + PANEL_W > screenDesignW - 5 then
        panelX = screenDesignW - PANEL_W - 5
    end
    local panelY = 100

    -- 计算面板总高度
    local SLOT_ROW_H = 48  -- 紧凑的槽位行高
    local SLOT_ROW_GAP = 6
    local contentH = TITLE_H + SECTION_GAP
        + 20 + BTN_H + BTN_GAP + BTN_H       -- 己方区域
        + SECTION_GAP
        + BTN_H + BTN_GAP + BTN_H + BTN_GAP + BTN_H + BTN_GAP + BTN_H + BTN_GAP + BTN_H  -- 选择器 + 获得 + 删除 + 升级 + 觉醒
        + SECTION_GAP
        + 20 + BTN_H + BTN_GAP + BTN_H + BTN_GAP + BTN_H + BTN_GAP + BTN_H  -- 关卡控制区域（+立即通关+跳终焉前）
        + SECTION_GAP
        + BTN_H                                -- 角色配置按钮
        + SECTION_GAP
        + 20                                   -- "装备生成" 标签
        + (SLOT_ROW_H + SLOT_ROW_GAP) * 4     -- 4 个槽位行
        + BTN_GAP
        + BTN_H + BTN_GAP                     -- 品质 选择器
        + BTN_H                                -- 等级 选择器
        + SECTION_GAP
        + 20 + BTN_H + BTN_GAP + BTN_H        -- 资源获取区域（标签 + 选择器 + 获取按钮）
        + SECTION_GAP
        + BTN_H                                -- 冒险等级提升按钮
        + SECTION_GAP
        + BTN_H                                -- 离线收益面板按钮
        + SECTION_GAP
        + 20 + BTN_H * 3 + BTN_GAP * 2        -- 受击特效测试（标签 + 3行按钮：2+2+1）
        + SECTION_GAP
        + BTN_H                                -- 清除存档按钮
        + BTN_GAP
        + BTN_H                                -- 测试开场剧情按钮
        + BTN_GAP
        + BTN_H                                -- 测试角色选择按钮
        + PANEL_PAD
    local panelH = contentH + PANEL_PAD * 2

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, PANEL_W, panelH, 14)
    nvgFillColor(vg, nvgRGBA(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], BG_COLOR[4]))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, PANEL_W, panelH, 14)
    nvgStrokeColor(vg, nvgRGBA(100, 100, 120, 180))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    local cx = panelX + PANEL_W * 0.5
    local curY = panelY + PANEL_PAD

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 32)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3], TITLE_COLOR[4]))
    nvgText(vg, cx, curY + TITLE_H * 0.5, "DEBUG", nil)
    curY = curY + TITLE_H + SECTION_GAP

    local btnX = panelX + PANEL_PAD
    local btnW = PANEL_W - PANEL_PAD * 2

    -- ==================== 己方队伍 ====================
    -- 显示当前阵容信息
    local allyInfo = "己方: " .. #allies .. " ("
    for i, a in ipairs(allies) do
        if i > 1 then allyInfo = allyInfo .. "," end
        allyInfo = allyInfo .. a.name
    end
    allyInfo = allyInfo .. ")"

    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], LABEL_COLOR[4]))
    nvgText(vg, btnX, curY + 10, allyInfo, nil)
    curY = curY + 20

    -- 下一个添加的英雄预告
    local nextIdx = #allies + 1
    local nextHeroId = DEFAULT_HERO_IDS[((nextIdx - 1) % #DEFAULT_HERO_IDS) + 1]
    local nextHero = HC.get(nextHeroId)
    local addBtnText = "+ " .. (nextHero and nextHero.name or "英雄")

    drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
        BTN_ADD_COLOR[1], BTN_ADD_COLOR[2], BTN_ADD_COLOR[3], BTN_ADD_COLOR[4],
        addBtnText)
    registerBtn("ally_add", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + BTN_GAP

    drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
        BTN_SUB_COLOR[1], BTN_SUB_COLOR[2], BTN_SUB_COLOR[3], BTN_SUB_COLOR[4],
        "- 己方单位")
    registerBtn("ally_sub", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + SECTION_GAP

    -- ==================== 冒险家管理 ====================
    local selHero = HC.get(getSelectedHeroId())
    local selName = selHero and selHero.name or "?"
    local isOwned = CharacterPanel.isOwned(getSelectedHeroId())
    -- 选择器通用布局变量（冒险家 + 装备生成 共用）
    local arrowW = 50
    local midW = btnW - arrowW * 2 - 8  -- 中间显示区域，两侧各留 4 间距
    local midX  ---@type number
    local rightX ---@type number
    -- 第一行: [◀] [ID:X  名字] [▶]
    -- 左箭头
    drawRoundedBtn(vg, btnX, curY, arrowW, BTN_H,
        80, 80, 100, 255, "◀", 8)
    registerBtn("hero_id_dec", btnX, curY, arrowW, BTN_H)
    -- 中间显示 ID + 名字 + 拥有状态
    midX = btnX + arrowW + 4
    nvgBeginPath(vg)
    nvgRoundedRect(vg, midX, curY, midW, BTN_H, 8)
    nvgFillColor(vg, nvgRGBA(50, 50, 65, 255))
    nvgFill(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 24)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local statusTag = isOwned and " ✓" or ""
    nvgFillColor(vg, isOwned and nvgRGBA(100, 255, 100, 255) or nvgRGBA(255, 255, 255, 255))
    nvgText(vg, midX + midW * 0.5, curY + BTN_H * 0.5,
        selName .. statusTag, nil)
    -- 右箭头
    rightX = midX + midW + 4
    drawRoundedBtn(vg, rightX, curY, arrowW, BTN_H,
        80, 80, 100, 255, "▶", 8)
    registerBtn("hero_id_inc", rightX, curY, arrowW, BTN_H)
    curY = curY + BTN_H + BTN_GAP
    -- 第二行: 获得冒险家按钮
    if isOwned then
        drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
            80, 80, 80, 255, "已拥有 " .. selName)
    else
        drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
            50, 160, 80, 255, "获得 " .. selName)
    end
    registerBtn("add_hero", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + BTN_GAP
    -- 第三行: 删除冒险家按钮
    if isOwned then
        drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
            180, 50, 50, 255, "删除 " .. selName)
    else
        drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
            80, 80, 80, 255, "删除 " .. selName)
    end
    registerBtn("remove_hero", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + BTN_GAP
    -- 第四行: 提升等级按钮
    if isOwned then
        local ownData = CharacterPanel.getOwnedHero(getSelectedHeroId())
        local curLv = ownData and ownData.level or 1
        drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
            60, 140, 180, 255, "Lv " .. curLv .. " → " .. (curLv + 1))
    else
        drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
            80, 80, 80, 255, "提升等级（未拥有）")
    end
    registerBtn("level_up_hero", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + BTN_GAP
    -- 第五行: 提升觉醒按钮
    if isOwned then
        local awakeLv = getAwakeLevel(getSelectedHeroId())
        if awakeLv >= 7 then
            drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
                80, 80, 80, 255, "觉醒已满 Lv7")
        else
            drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
                160, 90, 180, 255, "觉醒 Lv " .. awakeLv .. " → " .. (awakeLv + 1))
        end
    else
        drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
            80, 80, 80, 255, "提升觉醒（未拥有）")
    end
    registerBtn("awakening_up_hero", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + SECTION_GAP

    -- ==================== 关卡控制 ====================
    nvgFontSize(vg, 26)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], LABEL_COLOR[4]))
    local stageId = BattleScene.getCurrentStageId()
    nvgText(vg, btnX, curY + 10, "关卡: " .. tostring(stageId), nil)
    curY = curY + 20

    drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
        80, 130, 200, 255,
        "重载关卡")
    registerBtn("reload_stage", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + BTN_GAP

    drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
        BTN_ADD_COLOR[1], BTN_ADD_COLOR[2], BTN_ADD_COLOR[3], BTN_ADD_COLOR[4],
        "己方满血")
    registerBtn("heal_all", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + BTN_GAP

    drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
        200, 60, 60, 255,
        "立即通关")
    registerBtn("instant_clear", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + BTN_GAP

    -- 跳到终焉神殿前最后一关
    local curDiff = SC.getDifficulty(stageId)
    local preTerminalId = ({
        [SC.DIFFICULTY_NORMAL]    = SC.NORMAL_LAST_STAGE,
        [SC.DIFFICULTY_HARD]      = SC.HARD_LAST_STAGE,
        [SC.DIFFICULTY_NIGHTMARE] = SC.NIGHTMARE_LAST_STAGE,
        [SC.DIFFICULTY_HELL]      = SC.HELL_LAST_STAGE,
        [SC.DIFFICULTY_PURGATORY] = SC.PURGATORY_LAST_STAGE,
        [SC.DIFFICULTY_TORMENT]   = SC.TORMENT_LAST_STAGE,
        [SC.DIFFICULTY_TORMENT2]  = SC.TORMENT2_LAST_STAGE,
        [SC.DIFFICULTY_TORMENT3]  = SC.TORMENT3_LAST_STAGE,
        [SC.DIFFICULTY_TORMENT4]  = SC.TORMENT4_LAST_STAGE,
        [SC.DIFFICULTY_TORMENT5]      = SC.TORMENT5_LAST_STAGE,
        [SC.DIFFICULTY_ANNIHILATION]  = SC.ANNIHILATION_LAST_STAGE,
        [SC.DIFFICULTY_ANNIHILATION2] = SC.ANNIHILATION2_LAST_STAGE,
        [SC.DIFFICULTY_ANNIHILATION3] = SC.ANNIHILATION3_LAST_STAGE,
        [SC.DIFFICULTY_ANNIHILATION4] = SC.ANNIHILATION4_LAST_STAGE,
        [SC.DIFFICULTY_ANNIHILATION5] = SC.ANNIHILATION5_LAST_STAGE,
    })[curDiff] or SC.ANNIHILATION5_LAST_STAGE
    local preTermStage = SC.getStage(preTerminalId)
    local preTermLabel = preTermStage and preTermStage.name or tostring(preTerminalId)
    if stageId == preTerminalId then
        drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
            80, 80, 80, 255,
            "已在终焉前")
    else
        drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
            180, 100, 200, 255,
            "跳到终焉前(" .. preTermLabel .. ")")
    end
    registerBtn("jump_pre_terminal", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + SECTION_GAP

    -- ==================== 角色配置 ====================
    drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
        180, 140, 60, 255,
        "角色配置表")
    registerBtn("hero_roster", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + SECTION_GAP

    -- ==================== 装备生成 ====================
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], LABEL_COLOR[4]))
    nvgText(vg, btnX, curY + 10, "装备生成", nil)
    curY = curY + 20

    -- 4 个槽位行: [◀] [W1 名称] [▶] [生成]
    local slotArrowW = 36
    local slotGenW   = 56
    local slotMidW   = btnW - slotArrowW * 2 - slotGenW - 12  -- 12px gaps (3x4)
    for _, slot in ipairs(EQUIP_SLOTS) do
        local prefix = EquipmentConfig.SLOT_PREFIX[slot]
        local maxNum = EquipmentConfig.SLOT_COUNT[slot] or 1
        local num    = equipNums[slot]
        local tid    = prefix .. num
        local tpl    = EquipmentConfig.ITEMS[tid]
        local label  = EQUIP_SLOT_LABELS[slot]

        -- [◀]
        drawRoundedBtn(vg, btnX, curY, slotArrowW, SLOT_ROW_H, 80, 80, 100, 255, "◀", 6)
        registerBtn("eslot_dec_" .. slot, btnX, curY, slotArrowW, SLOT_ROW_H)

        -- 中间显示区: "W1 练习用剑"
        local smidX = btnX + slotArrowW + 4
        nvgBeginPath(vg)
        nvgRoundedRect(vg, smidX, curY, slotMidW, SLOT_ROW_H, 6)
        nvgFillColor(vg, nvgRGBA(50, 50, 65, 255))
        nvgFill(vg)
        -- 裁剪防止文字溢出
        nvgSave(vg)
        nvgScissor(vg, smidX + 4, curY, slotMidW - 8, SLOT_ROW_H)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 19)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if tpl then
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, smidX + 6, curY + SLOT_ROW_H * 0.5, tid .. " " .. tpl.name, nil)
        else
            nvgFillColor(vg, nvgRGBA(255, 100, 100, 255))
            nvgText(vg, smidX + 6, curY + SLOT_ROW_H * 0.5, tid .. " ???", nil)
        end
        nvgRestore(vg)

        -- [▶]
        local sRightX = smidX + slotMidW + 4
        drawRoundedBtn(vg, sRightX, curY, slotArrowW, SLOT_ROW_H, 80, 80, 100, 255, "▶", 6)
        registerBtn("eslot_inc_" .. slot, sRightX, curY, slotArrowW, SLOT_ROW_H)

        -- [生成] 按钮
        local sGenX = sRightX + slotArrowW + 4
        drawRoundedBtn(vg, sGenX, curY, slotGenW, SLOT_ROW_H, 120, 90, 50, 255, "生成", 6)
        registerBtn("eslot_gen_" .. slot, sGenX, curY, slotGenW, SLOT_ROW_H)

        curY = curY + SLOT_ROW_H + SLOT_ROW_GAP
    end
    curY = curY - SLOT_ROW_GAP + BTN_GAP  -- 调整末尾间距

    -- 品质选择器: [◀] [品质名 + 颜色] [▶]
    drawRoundedBtn(vg, btnX, curY, arrowW, BTN_H, 80, 80, 100, 255, "◀", 8)
    registerBtn("equip_q_dec", btnX, curY, arrowW, BTN_H)
    midX = btnX + arrowW + 4
    nvgBeginPath(vg)
    nvgRoundedRect(vg, midX, curY, midW, BTN_H, 8)
    nvgFillColor(vg, nvgRGBA(50, 50, 65, 255))
    nvgFill(vg)
    local qDef = EquipmentConfig.QUALITY[equipQuality]
    local qName = qDef and qDef.name or "?"
    local qColors = {
        [1] = { 0xb5, 0xb5, 0xb5 },
        [2] = { 0xa2, 0xff, 0x94 },
        [3] = { 0x72, 0xf2, 0xf5 },
        [4] = { 0xef, 0x79, 0xff },
        [5] = { 0xff, 0xed, 0x00 },
    }
    local qc = qColors[equipQuality] or { 255, 255, 255 }
    nvgFontSize(vg, 24)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 255))
    nvgText(vg, midX + midW * 0.5, curY + BTN_H * 0.5, "品质: " .. qName, nil)
    rightX = midX + midW + 4
    drawRoundedBtn(vg, rightX, curY, arrowW, BTN_H, 80, 80, 100, 255, "▶", 8)
    registerBtn("equip_q_inc", rightX, curY, arrowW, BTN_H)
    curY = curY + BTN_H + BTN_GAP

    -- 等级选择器: [◀] [Lv.X] [▶]
    drawRoundedBtn(vg, btnX, curY, arrowW, BTN_H, 80, 80, 100, 255, "◀", 8)
    registerBtn("equip_lv_dec", btnX, curY, arrowW, BTN_H)
    midX = btnX + arrowW + 4
    nvgBeginPath(vg)
    nvgRoundedRect(vg, midX, curY, midW, BTN_H, 8)
    nvgFillColor(vg, nvgRGBA(50, 50, 65, 255))
    nvgFill(vg)
    nvgFontSize(vg, 24)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, midX + midW * 0.5, curY + BTN_H * 0.5, "等级: " .. equipLevel, nil)
    rightX = midX + midW + 4
    drawRoundedBtn(vg, rightX, curY, arrowW, BTN_H, 80, 80, 100, 255, "▶", 8)
    registerBtn("equip_lv_inc", rightX, curY, arrowW, BTN_H)
    curY = curY + BTN_H + SECTION_GAP

    -- ==================== 遗物生成 ====================
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], LABEL_COLOR[4]))
    nvgText(vg, btnX, curY + 10, "遗物生成", nil)
    curY = curY + 20

    -- 类型选择器: [◀] [类型名] [▶]
    drawRoundedBtn(vg, btnX, curY, arrowW, BTN_H, 80, 80, 100, 255, "◀", 8)
    registerBtn("relic_t_dec", btnX, curY, arrowW, BTN_H)
    midX = btnX + arrowW + 4
    nvgBeginPath(vg)
    nvgRoundedRect(vg, midX, curY, midW, BTN_H, 8)
    nvgFillColor(vg, nvgRGBA(50, 50, 65, 255))
    nvgFill(vg)
    nvgFontSize(vg, 24)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, midX + midW * 0.5, curY + BTN_H * 0.5, "类型: " .. RELIC_TYPE_NAMES[relicType], nil)
    rightX = midX + midW + 4
    drawRoundedBtn(vg, rightX, curY, arrowW, BTN_H, 80, 80, 100, 255, "▶", 8)
    registerBtn("relic_t_inc", rightX, curY, arrowW, BTN_H)
    curY = curY + BTN_H + BTN_GAP

    -- 品质选择器: [◀] [品质名 + 颜色] [▶]
    drawRoundedBtn(vg, btnX, curY, arrowW, BTN_H, 80, 80, 100, 255, "◀", 8)
    registerBtn("relic_q_dec", btnX, curY, arrowW, BTN_H)
    midX = btnX + arrowW + 4
    nvgBeginPath(vg)
    nvgRoundedRect(vg, midX, curY, midW, BTN_H, 8)
    nvgFillColor(vg, nvgRGBA(50, 50, 65, 255))
    nvgFill(vg)
    local rqc = RELIC_QUALITY_COLORS[relicQuality] or { 255, 255, 255 }
    nvgFontSize(vg, 24)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(rqc[1], rqc[2], rqc[3], 255))
    nvgText(vg, midX + midW * 0.5, curY + BTN_H * 0.5, "品质: " .. RELIC_QUALITY_NAMES[relicQuality], nil)
    rightX = midX + midW + 4
    drawRoundedBtn(vg, rightX, curY, arrowW, BTN_H, 80, 80, 100, 255, "▶", 8)
    registerBtn("relic_q_inc", rightX, curY, arrowW, BTN_H)
    curY = curY + BTN_H + BTN_GAP

    -- [生成遗物] 按钮
    drawRoundedBtn(vg, btnX, curY, btnW, BTN_H, 60, 140, 120, 255, "生成遗物", 8)
    registerBtn("relic_gen", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + SECTION_GAP

    -- ==================== 资源获取 ====================
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], LABEL_COLOR[4]))
    nvgText(vg, btnX, curY + 10, "资源获取", nil)
    curY = curY + 20

    -- 资源选择器: [◀] [资源名称] [▶]
    local resDef = GameConfig.Resources[selectedResIdx]
    local resName = resDef and resDef.name or "?"
    drawRoundedBtn(vg, btnX, curY, arrowW, BTN_H, 80, 80, 100, 255, "◀", 8)
    registerBtn("res_dec", btnX, curY, arrowW, BTN_H)
    midX = btnX + arrowW + 4
    nvgBeginPath(vg)
    nvgRoundedRect(vg, midX, curY, midW, BTN_H, 8)
    nvgFillColor(vg, nvgRGBA(50, 50, 65, 255))
    nvgFill(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 24)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, midX + midW * 0.5, curY + BTN_H * 0.5, resName, nil)
    rightX = midX + midW + 4
    drawRoundedBtn(vg, rightX, curY, arrowW, BTN_H, 80, 80, 100, 255, "▶", 8)
    registerBtn("res_inc", rightX, curY, arrowW, BTN_H)
    curY = curY + BTN_H + BTN_GAP

    -- 获取按钮
    local giveAmt = resDef and resDef.giveAmount or 0
    drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
        50, 160, 80, 255,
        "获取 " .. resName .. " ×" .. giveAmt)
    registerBtn("res_give", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + SECTION_GAP

    -- ==================== 冒险等级提升 ====================
    local playerLv = GameState.getLevel()
    local isMaxLv = ExpTable.isPlayerMaxLevel(playerLv)
    if isMaxLv then
        drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
            80, 80, 80, 255,
            "冒险等级 Lv." .. playerLv .. " (满级)")
    else
        drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
            160, 120, 50, 255,
            "冒险等级 Lv." .. playerLv .. " → " .. (playerLv + 1))
    end
    registerBtn("player_level_up", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + SECTION_GAP

    -- ==================== 离线收益面板 ====================
    drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
        80, 160, 200, 255,
        "离线收益面板")
    registerBtn("offline_reward", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + SECTION_GAP

    -- ==================== 受击特效测试 ====================
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], LABEL_COLOR[4]))
    nvgText(vg, btnX, curY + 10, "受击特效测试", nil)
    curY = curY + 20

    -- 2 个一行排列: [皮甲] [轻甲]
    local halfW = math.floor((btnW - BTN_GAP) * 0.5)
    drawRoundedBtn(vg, btnX, curY, halfW, BTN_H,
        140, 100, 60, 255, "皮甲(1)")
    registerBtn("fx_test_1", btnX, curY, halfW, BTN_H)
    drawRoundedBtn(vg, btnX + halfW + BTN_GAP, curY, halfW, BTN_H,
        100, 140, 160, 255, "轻甲(2)")
    registerBtn("fx_test_2", btnX + halfW + BTN_GAP, curY, halfW, BTN_H)
    curY = curY + BTN_H + BTN_GAP

    -- [重甲] [板甲]
    drawRoundedBtn(vg, btnX, curY, halfW, BTN_H,
        80, 80, 120, 255, "重甲(3)")
    registerBtn("fx_test_3", btnX, curY, halfW, BTN_H)
    drawRoundedBtn(vg, btnX + halfW + BTN_GAP, curY, halfW, BTN_H,
        140, 140, 150, 255, "板甲(4)")
    registerBtn("fx_test_4", btnX + halfW + BTN_GAP, curY, halfW, BTN_H)
    curY = curY + BTN_H + BTN_GAP

    -- [布甲]
    drawRoundedBtn(vg, btnX, curY, halfW, BTN_H,
        120, 80, 140, 255, "布甲(5)")
    registerBtn("fx_test_5", btnX, curY, halfW, BTN_H)
    curY = curY + BTN_H + SECTION_GAP

    -- ==================== 清除存档（带二次确认） ====================
    local resetInConfirm = (resetConfirmClock > 0) and (os.clock() - resetConfirmClock < RESET_CONFIRM_TIMEOUT)
    if resetInConfirm then
        drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
            255, 0, 0, 255,
            "⚠ 确认清除？再点一次!")
    else
        -- 超时自动取消确认状态
        if resetConfirmClock > 0 then resetConfirmClock = 0 end
        drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
            200, 40, 40, 255,
            "清除存档（重置）")
    end
    registerBtn("reset_save", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + BTN_GAP

    -- ==================== 测试开场剧情 ====================
    drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
        60, 120, 200, 255,
        "测试开场剧情")
    registerBtn("test_intro_cutscene", btnX, curY, btnW, BTN_H)
    curY = curY + BTN_H + BTN_GAP

    -- ==================== 测试角色选择 ====================
    drawRoundedBtn(vg, btnX, curY, btnW, BTN_H,
        160, 100, 200, 255,
        "测试角色选择")
    registerBtn("test_char_select", btnX, curY, btnW, BTN_H)
end

--- 处理点击（screen space 坐标）
---@param sx number screen space X
---@param sy number screen space Y
---@return boolean 是否命中了面板按钮
function DebugPanel.handleInput(sx, sy)
    if not isDebugAllowed() then return false end
    -- 每次处理输入前，从 BattleScene 刷新 allies（防止本地引用过期）
    local freshAllies = BattleScene.getAllies()
    if freshAllies and #freshAllies > 0 then
        allies = freshAllies
    end
    for _, btn in ipairs(buttons) do
        if sx >= btn.x and sx <= btn.x + btn.w
           and sy >= btn.y and sy <= btn.y + btn.h then

            if btn.id == "ally_add" then
                local maxField = BattleScene.getMaxFieldUnits()
                if #allies >= maxField then
                    print("[Debug] 己方已满 " .. maxField .. " 个")
                else
                    local nextIdx = #allies + 1
                    local heroId = DEFAULT_HERO_IDS[((nextIdx - 1) % #DEFAULT_HERO_IDS) + 1]
                    local unit = createAllyHero(heroId, debugAllyLevel)
                    allies[#allies + 1] = unit
                    syncAlliesToBattle()
                    print("[Debug] 己方 +1 " .. unit.name .. " → " .. #allies)
                end
            elseif btn.id == "ally_sub" then
                if #allies > 0 then
                    local removed = allies[#allies]
                    allies[#allies] = nil
                    syncAlliesToBattle()
                    print("[Debug] 己方 -1 " .. removed.name .. " → " .. #allies)
                end
            elseif btn.id == "hero_id_dec" then
                cycleSelectedHero(-1)
            elseif btn.id == "hero_id_inc" then
                cycleSelectedHero(1)
            elseif btn.id == "add_hero" then
                local heroId = getSelectedHeroId()
                if not HC.get(heroId) then
                    print("[Debug] 无效英雄 ID: " .. tostring(heroId))
                elseif CharacterPanel.isOwned(heroId) then
                    print("[Debug] 英雄 " .. heroId .. " 已拥有")
                else
                    getClient().sendAction(getProtocol().ACTION_TYPES.GM_GIVE_HERO, {
                        heroId = heroId,
                    })
                    print("[Debug] 已发送获得冒险家请求: ID " .. heroId)
                end
            elseif btn.id == "remove_hero" then
                local heroId = getSelectedHeroId()
                if not CharacterPanel.isOwned(heroId) then
                    print("[Debug] 英雄 " .. heroId .. " 未拥有")
                else
                    CharacterPanel.removeHero(heroId)
                    print("[Debug] 删除冒险家 ID:" .. heroId)
                end
            elseif btn.id == "level_up_hero" then
                local heroId = getSelectedHeroId()
                if CharacterPanel.isOwned(heroId) then
                    getClient().sendAction(getProtocol().ACTION_TYPES.GM_LEVEL_UP, {
                        heroId = heroId,
                    })
                    print("[Debug] 已发送升级请求: 冒险家 " .. heroId)
                else
                    print("[Debug] 英雄 " .. heroId .. " 未拥有，无法升级")
                end
            elseif btn.id == "awakening_up_hero" then
                local heroId = getSelectedHeroId()
                if not CharacterPanel.isOwned(heroId) then
                    print("[Debug] 英雄 " .. heroId .. " 未拥有，无法觉醒")
                elseif getAwakeLevel(heroId) >= 7 then
                    print("[Debug] 英雄 " .. heroId .. " 已满觉醒")
                else
                    getClient().sendAction(getProtocol().ACTION_TYPES.GM_AWAKENING, {
                        heroId = heroId,
                    })
                    print("[Debug] 已发送觉醒请求: 冒险家 " .. heroId)
                end
            elseif btn.id == "reload_stage" then
                BattleScene.reloadStage()
                print("[Debug] 关卡已重载")
            elseif btn.id == "heal_all" then
                for _, a in ipairs(allies) do
                    if a.attrs then
                        -- 使用 UnitAttributes 的 heal 方法
                        a.attrs:fillHp()
                        a.hp = a.attrs:get(AD.MAX_HP)
                        a.maxHp = a.attrs:get(AD.MAX_HP)
                    else
                        a.hp = a.maxHp
                    end
                end
                -- 注意：不调用 syncAlliesToBattle()，因为 allies 已是 BattleScene
                -- 当前引用，原地修改 HP 即可生效，无需触发 resetBattle
                print("[Debug] 己方全员满血")
            elseif btn.id == "instant_clear" then
                local dungeonScene = getDungeonBattleScene()
                local dungeonBattle = getDungeonBattle()
                if dungeonScene.isOpen and dungeonScene.isOpen() and dungeonBattle.debugInstantWin and dungeonBattle.debugInstantWin() then
                    local cfg = dungeonBattle.getConfig and dungeonBattle.getConfig() or {}
                    if cfg.dungeonId == "babel_tower" then
                        print("[Debug] 立即通关通天塔当前小波")
                    else
                        print("[Debug] 立即通关当前副本")
                    end
                else
                    BattleScene.debugInstantClear()
                    print("[Debug] 立即通关当前主线关卡")
                end
            elseif btn.id == "jump_pre_terminal" then
                local curStageId = BattleScene.getCurrentStageId()
                local curDiff = SC.getDifficulty(curStageId)
                local targetId = ({
                    [SC.DIFFICULTY_NORMAL]    = SC.NORMAL_LAST_STAGE,
                    [SC.DIFFICULTY_HARD]      = SC.HARD_LAST_STAGE,
                    [SC.DIFFICULTY_NIGHTMARE] = SC.NIGHTMARE_LAST_STAGE,
                    [SC.DIFFICULTY_HELL]      = SC.HELL_LAST_STAGE,
                    [SC.DIFFICULTY_PURGATORY] = SC.PURGATORY_LAST_STAGE,
                    [SC.DIFFICULTY_TORMENT]   = SC.TORMENT_LAST_STAGE,
                    [SC.DIFFICULTY_TORMENT2]  = SC.TORMENT2_LAST_STAGE,
                    [SC.DIFFICULTY_TORMENT3]  = SC.TORMENT3_LAST_STAGE,
                    [SC.DIFFICULTY_TORMENT4]  = SC.TORMENT4_LAST_STAGE,
                    [SC.DIFFICULTY_TORMENT5]      = SC.TORMENT5_LAST_STAGE,
                    [SC.DIFFICULTY_ANNIHILATION]  = SC.ANNIHILATION_LAST_STAGE,
                    [SC.DIFFICULTY_ANNIHILATION2] = SC.ANNIHILATION2_LAST_STAGE,
                    [SC.DIFFICULTY_ANNIHILATION3] = SC.ANNIHILATION3_LAST_STAGE,
                    [SC.DIFFICULTY_ANNIHILATION4] = SC.ANNIHILATION4_LAST_STAGE,
                    [SC.DIFFICULTY_ANNIHILATION5] = SC.ANNIHILATION5_LAST_STAGE,
                })[curDiff] or SC.ANNIHILATION5_LAST_STAGE
                if curStageId ~= targetId then
                    getClient().sendAction(getProtocol().ACTION_TYPES.GM_JUMP_STAGE, {
                        stageId = targetId,
                    })
                    BattleScene.debugJumpToStage(targetId)
                    print("[Debug] 跳转到终焉神殿前: " .. targetId .. "（已同步存档）")
                else
                    print("[Debug] 已在终焉前最后一关")
                end
            elseif btn.id == "hero_roster" then
                HeroRosterPanel.toggle()
                print("[Debug] 角色配置表 " .. (HeroRosterPanel.isVisible() and "打开" or "关闭"))

            -- ====== 装备生成（4 槽位选择器） ======
            elseif btn.id == "equip_q_dec" then
                equipQuality = equipQuality - 1
                if equipQuality < 1 then equipQuality = MAX_EQUIP_QUALITY end
            elseif btn.id == "equip_q_inc" then
                equipQuality = equipQuality + 1
                if equipQuality > MAX_EQUIP_QUALITY then equipQuality = 1 end
            elseif btn.id == "equip_lv_dec" then
                equipLevel = equipLevel - 1
                if equipLevel < 1 then equipLevel = MAX_EQUIP_LEVEL end
            elseif btn.id == "equip_lv_inc" then
                equipLevel = equipLevel + 1
                if equipLevel > MAX_EQUIP_LEVEL then equipLevel = 1 end

            -- ====== 遗物生成 ======
            elseif btn.id == "relic_t_dec" then
                relicType = relicType - 1
                if relicType < 1 then relicType = MAX_RELIC_TYPE end
            elseif btn.id == "relic_t_inc" then
                relicType = relicType + 1
                if relicType > MAX_RELIC_TYPE then relicType = 1 end
            elseif btn.id == "relic_q_dec" then
                relicQuality = relicQuality - 1
                if relicQuality < 1 then relicQuality = MAX_RELIC_QUALITY end
            elseif btn.id == "relic_q_inc" then
                relicQuality = relicQuality + 1
                if relicQuality > MAX_RELIC_QUALITY then relicQuality = 1 end
            elseif btn.id == "relic_gen" then
                getClient().sendAction(getProtocol().ACTION_TYPES.GM_GIVE_RELIC, {
                    relicType = relicType,
                    quality   = relicQuality,
                })
                print("[Debug] 生成遗物 type=" .. RELIC_TYPE_NAMES[relicType]
                    .. " quality=" .. RELIC_QUALITY_NAMES[relicQuality])

            elseif btn.id == "res_dec" then
                local total = #GameConfig.Resources
                selectedResIdx = selectedResIdx - 1
                if selectedResIdx < 1 then selectedResIdx = total end
            elseif btn.id == "res_inc" then
                local total = #GameConfig.Resources
                selectedResIdx = selectedResIdx + 1
                if selectedResIdx > total then selectedResIdx = 1 end
            elseif btn.id == "res_give" then
                local resDef = GameConfig.Resources[selectedResIdx]
                if resDef then
                    getClient().sendAction(getProtocol().ACTION_TYPES.GM_GIVE_RESOURCE, {
                        key    = resDef.key,
                        amount = resDef.giveAmount,
                    })
                    print("[Debug] 获取资源 " .. resDef.name .. " ×" .. resDef.giveAmount)
                end
            -- ====== 受击特效测试 ======
            elseif btn.id == "fx_test_1" then
                BattleEffects.spawn(1, 540, 1200)
                print("[Debug] 受击特效: 皮甲(1)")
            elseif btn.id == "fx_test_2" then
                BattleEffects.spawn(2, 540, 1200)
                print("[Debug] 受击特效: 轻甲(2)")
            elseif btn.id == "fx_test_3" then
                BattleEffects.spawn(3, 540, 1200)
                print("[Debug] 受击特效: 重甲(3)")
            elseif btn.id == "fx_test_4" then
                BattleEffects.spawn(4, 540, 1200)
                print("[Debug] 受击特效: 板甲(4)")
            elseif btn.id == "fx_test_5" then
                BattleEffects.spawn(5, 540, 1200)
                print("[Debug] 受击特效: 布甲(5)")
            elseif btn.id == "player_level_up" then
                local lv = GameState.getLevel()
                if ExpTable.isPlayerMaxLevel(lv) then
                    print("[Debug] 冒险等级已满级 Lv." .. lv)
                else
                    getClient().sendAction(getProtocol().ACTION_TYPES.GM_PLAYER_LEVEL_UP, {})
                    print("[Debug] 已发送冒险等级提升请求: Lv." .. lv)
                end
            elseif btn.id == "offline_reward" then
                -- mock 数据打开离线收益面板
                local mockRewards = {}
                local mockTemplates = { "W1", "W2", "W3", "O1", "A1", "A2", "X1", "X2" }
                for i = 1, 12 do
                    mockRewards[i] = {
                        type       = "equip",
                        templateId = mockTemplates[((i - 1) % #mockTemplates) + 1],
                        quality    = ((i - 1) % 5) + 1,
                        level      = 10 + i,
                        count      = (i <= 8) and 1 or (i * 2),
                    }
                end
                OfflineRewardPanel.show({
                    offlineSeconds  = 6 * 3600 + 23 * 60 + 45,
                    maxSeconds      = 12 * 3600,
                    multiplier      = 2,
                    adventureExp    = 128456,
                    adventurerExp   = 56230,
                    rewards         = mockRewards,
                    onClaim         = function(doubled)
                        print("[Debug] 离线收益领取, doubled=" .. tostring(doubled))
                    end,
                })
                print("[Debug] 打开离线收益面板（mock 数据）")
            elseif btn.id == "reset_save" then
                -- 二次确认机制：第一次点击进入确认状态，3秒内再次点击才执行
                local now = os.clock()
                if resetConfirmClock == 0 or (now - resetConfirmClock >= RESET_CONFIRM_TIMEOUT) then
                    -- 首次点击（或已超时）→ 进入确认等待
                    resetConfirmClock = now
                    print("[Debug][RESET] 首次点击 → 进入确认状态，3秒内再次点击执行清档")
                    return true  -- 消费本次点击
                end
                -- 二次确认通过 → 执行清档
                resetConfirmClock = 0  -- 重置确认状态

                -- [DIAG] 记录清档开始时的关键状态
                local PlayerInfoPanel_ = require("ui.PlayerInfoPanel")
                print(string.format("[Debug][DIAG-RESET] START clock=%.4f — PlayerInfoPanel.getUID()=%s",
                    os.clock(),
                    tostring(PlayerInfoPanel_.getUID and PlayerInfoPanel_.getUID() or "no-getter")))

                -- 1. 发送服务端清除存档请求
                getClient().sendAction(getProtocol().ACTION_TYPES.GM_RESET_SAVE, {})
                print(string.format("[Debug][DIAG-RESET] step1: sendAction GM_RESET_SAVE done clock=%.4f", os.clock()))

                -- 2. 重置 DebugPanel 自身局部状态
                allies = {}
                debugAllyLevel = 1
                selectedHeroIdx = 1
                equipNums = { weapon = 1, offhand = 1, armor = 1, accessory = 1 }
                equipQuality = 1
                equipLevel = 1
                relicType = 1
                relicQuality = 1
                selectedResIdx = 1

                -- 3. 调用 Standalone 的重启流程（重置所有客户端状态 + 回到开始界面）
                getStandalone().requestResetToStartScreen()
                print(string.format("[Debug][DIAG-RESET] step3: requestResetToStartScreen done clock=%.4f", os.clock()))
                -- 4. 重置 Client 一次性标志（让开场动画等可重新触发）
                getClient().resetForNewSession()
                print(string.format("[Debug][DIAG-RESET] step4: resetForNewSession done clock=%.4f", os.clock()))
                -- 5. 请求服务端"返回大厅"：清理旧会话 + 重推区服列表
                --    修复：不加这步会导致 StartScreen.serverListData_ 永远为 nil，
                --    玩家点击无响应（"无限重开"现象）
                getClient().requestReturnToLobby()
                print(string.format("[Debug][DIAG-RESET] step5: requestReturnToLobby done clock=%.4f — COMPLETE", os.clock()))
            elseif btn.id == "test_intro_cutscene" then
                local ic = getIntroCutscene()
                if not ic.isActive() then
                    local GameBGM_ = require("systems.GameBGM")
                    GameBGM_.start()
                    ic.start(function()
                        -- 过场结束 → 衔接情景对话 1（与正式流程一致）
                        print("[Debug] 开场剧情结束，启动情景对话 1")
                        local cfg = getScenarioDialogueConfig().SCENARIO_1
                        cfg.onFinish = function()
                            print("[Debug] 情景对话1结束，打开角色选择")
                            getCharacterSelect().show({
                                background = cfg.background,
                                onFinish = function(heroId)
                                    print("[Debug] 角色选择完成: heroId=" .. heroId)
                                    local postMap = {
                                        [1] = getScenarioDialogueConfig().SCENARIO_2,
                                        [2] = getScenarioDialogueConfig().SCENARIO_3,
                                        [3] = getScenarioDialogueConfig().SCENARIO_4,
                                    }
                                    local postScenario = postMap[heroId]
                                    if postScenario then
                                        getScenarioDialogue().show(postScenario)
                                    end
                                end,
                            })
                        end
                        getScenarioDialogue().show(cfg)
                    end)
                    print("[Debug] 开始测试开场剧情，BGM 已切换")
                else
                    print("[Debug] 开场剧情已在播放中")
                end
            elseif btn.id == "test_char_select" then
                local cs = getCharacterSelect()
                if not cs.isActive() then
                    cs.show({
                        background = "image/关卡地图/MAP_1.png",
                        onFinish = function(heroId)
                            print("[Debug] 角色选择完成: heroId=" .. heroId)
                            local postMap = {
                                [1] = getScenarioDialogueConfig().SCENARIO_2,
                                [2] = getScenarioDialogueConfig().SCENARIO_3,
                                [3] = getScenarioDialogueConfig().SCENARIO_4,
                            }
                            local postScenario = postMap[heroId]
                            if postScenario then
                                getScenarioDialogue().show(postScenario)
                            end
                        end,
                    })
                    print("[Debug] 打开角色选择界面")
                else
                    print("[Debug] 角色选择界面已在显示中")
                end
            else
                -- 动态匹配 4 个槽位的 dec/inc/gen 按钮
                for _, slot in ipairs(EQUIP_SLOTS) do
                    local maxNum = EquipmentConfig.SLOT_COUNT[slot] or 1
                    if btn.id == "eslot_dec_" .. slot then
                        equipNums[slot] = equipNums[slot] - 1
                        if equipNums[slot] < 1 then equipNums[slot] = maxNum end
                        break
                    elseif btn.id == "eslot_inc_" .. slot then
                        equipNums[slot] = equipNums[slot] + 1
                        if equipNums[slot] > maxNum then equipNums[slot] = 1 end
                        break
                    elseif btn.id == "eslot_gen_" .. slot then
                        local prefix = EquipmentConfig.SLOT_PREFIX[slot]
                        local tid = prefix .. equipNums[slot]
                        local tpl = EquipmentConfig.ITEMS[tid]
                        if tpl then
                            getClient().sendAction(getProtocol().ACTION_TYPES.GM_GIVE_EQUIP, {
                                templateId = tid,
                                quality    = equipQuality,
                                level      = equipLevel,
                            })
                            print("[Debug] 生成装备 " .. tid .. "(" .. tpl.name .. ")"
                                .. " Q=" .. equipQuality .. " Lv=" .. equipLevel)
                        else
                            print("[Debug] 模板 " .. tid .. " 不存在")
                        end
                        break
                    end
                end
            end
            return true
        end
    end
    return false
end

return DebugPanel
