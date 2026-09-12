-- ============================================================================
-- CharacterDetail - 角色详情二级界面
-- 从 CharacterPanel 拆分出来的独立模块
-- 职责：管理角色详情界面的状态、输入和生命周期
-- 绘制逻辑已拆分到 CharacterDetailDraw.lua
-- ============================================================================

local HC               = require("config.HeroConfig")
local CC               = require("config.ClassConfig")
local AD               = require("systems.AttributeDef")
local GameConfig       = require("config.GameConfig")
local GameState        = require("core.GameState")
local ExpTable         = require("config.ExpTable")
local EquipmentBag     = require("ui.EquipmentBag")
local PlayerStore      = require("client.data.PlayerStore")
local EquipmentConfig  = require("config.EquipmentConfig")
local EquipmentSystem  = require("systems.EquipmentSystem")
local DetailAttrs      = require("ui.CharacterDetailAttrs")
local BF              = require("systems.ButtonFeedback")
local Draw             = require("ui.CharacterDetailDraw")
local AwakeningPanel   = require("ui.AwakeningPanel")

local CharacterDetail = {}

-- 挂在模块表上，避免 local 超限（CharacterDetail 已接近 200 local 上限）
CharacterDetail._ImageCache = require("ui.ImageCache")
CharacterDetail._EquipDetail = require("ui.EquipmentDetail")
CharacterDetail._EquipPanel = require("ui.CharacterDetailEquip")

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 从 Draw 子模块引用的布局常量（handleInput 使用） ========================

local DT_SLOT_SIZE           = Draw.DT_SLOT_SIZE
local DT_SLOTS               = Draw.DT_SLOTS
local BTN_BACK_CX            = Draw.BTN_BACK_CX
local BTN_BACK_CY            = Draw.BTN_BACK_CY
local BTN_BACK_W             = Draw.BTN_BACK_W
local BTN_BACK_H             = Draw.BTN_BACK_H
local BTN_TAB_SLIDER_W       = Draw.BTN_TAB_SLIDER_W
local BTN_TAB_SLIDER_H       = Draw.BTN_TAB_SLIDER_H
local BTN_TAB_ATTR_CX        = Draw.BTN_TAB_ATTR_CX
local BTN_TAB_ATTR_CY        = Draw.BTN_TAB_ATTR_CY
local BTN_TAB_EQUIP_CX       = Draw.BTN_TAB_EQUIP_CX
local BTN_TAB_EQUIP_CY       = Draw.BTN_TAB_EQUIP_CY
local BTN_TAB_AWAKEN_CX      = Draw.BTN_TAB_AWAKEN_CX
local BTN_TAB_AWAKEN_CY      = Draw.BTN_TAB_AWAKEN_CY
local ATTR_BOX_W              = Draw.ATTR_BOX_W
local ATTR_BOX_H              = Draw.ATTR_BOX_H
local ATTR_COL1_CX            = Draw.ATTR_COL1_CX
local ATTR_COL2_CX            = Draw.ATTR_COL2_CX
local ATTR_ROW_GAP             = Draw.ATTR_ROW_GAP
local ATTR_FIRST_ROW_Y        = Draw.ATTR_FIRST_ROW_Y
local ATTR_CLIP_TOP            = Draw.ATTR_CLIP_TOP
local ATTR_CLIP_HEIGHT         = Draw.ATTR_CLIP_HEIGHT
local ATTR_SCROLL_WHEEL_STEP   = Draw.ATTR_SCROLL_WHEEL_STEP
local STAT_BOX_W               = Draw.STAT_BOX_W
local STAT_BOX_H               = Draw.STAT_BOX_H
local STAT_COL1_CX             = Draw.STAT_COL1_CX
local STAT_COL2_CX             = Draw.STAT_COL2_CX
local STAT_ROW1_CY             = Draw.STAT_ROW1_CY
local STAT_ROW_STEP            = Draw.STAT_ROW_STEP
local STAT_LAYOUT              = Draw.STAT_LAYOUT
local ARROW_BG_W               = Draw.ARROW_BG_W
local ARROW_BG_H               = Draw.ARROW_BG_H
local ARROW_CY                 = Draw.ARROW_CY
local ARROW_LEFT_CX            = Draw.ARROW_LEFT_CX
local ARROW_RIGHT_CX           = Draw.ARROW_RIGHT_CX
local ARROW_BG_LEFT_CX         = Draw.ARROW_BG_LEFT_CX
local ARROW_BG_RIGHT_CX        = Draw.ARROW_BG_RIGHT_CX

-- ======================== 状态 ========================

local detailState = {
    open          = false,
    heroId        = nil,
    tab           = "attr",   -- "attr" 属性页 | "equip" 配装页 | "awaken" 觉醒页
    openTime      = 0,        -- 打开时刻（time.elapsedTime）
    closing       = false,    -- 是否正在播放关闭动画
    closeTime     = 0,        -- 关闭时刻
    tabFrom       = "attr",   -- Tab 切换前的页签
    tabSwitchTime = 0,        -- Tab 切换时刻
    equipSlot     = "weapon", -- 配装页当前选中槽位
    -- 属性区域滚动
    attrScrollY   = 0,        -- 像素滚动偏移（>0 表示内容上移）
    attrScrollMax = 0,        -- 最大滚动值
    attrDragging  = false,    -- 是否在属性区域拖拽
    attrDragLastY = 0,        -- 上一帧拖拽 Y
    attrScrollVel = 0,        -- 惯性速度
    -- 属性说明气泡
    attrTip       = nil,      -- { boxCX, boxCY, desc, area } or nil; area="attr"|"stat"
    -- 属性缓存（handleInput 使用）
    cachedLeft    = nil,
    cachedRight   = nil,
}

-- collectAttributes → DetailAttrs 模块
local collectAttributes = DetailAttrs.collectAttributes

--- 限制属性滚动值（需在 setContext 之前定义，传递给 Draw）
local function clampAttrScroll()
    detailState.attrScrollY = math.max(0, math.min(detailState.attrScrollMax, detailState.attrScrollY))
end

-- ======================== 装备可提升判断 ========================

--- 检查指定槽位是否有可提升装备（背包中存在战斗力更高的可穿戴装备）
---@param heroId number
---@param slotName string "weapon"|"offhand"|"armor"|"accessory"
---@param equipData table PlayerStore.Get("equipment") 返回的数据
---@return boolean
function CharacterDetail._hasUpgradeForSlot(heroId, slotName, equipData)
    if not equipData or not equipData.inventory then return false end

    local inventory = equipData.inventory
    local heroEquipped = equipData.equipped and equipData.equipped[heroId]

    -- 1) 当前已装备物品的战斗力（空槽 = 0）
    local equippedPower = 0
    if heroEquipped then
        local seq = heroEquipped[slotName]
        if seq then
            local eqItem = inventory[tostring(seq)]
            if eqItem then
                equippedPower = CharacterDetail._EquipDetail.calcEquipPower(eqItem, heroId)
            end
        end
    end

    -- 1.5) 主手槽：预计算副手战斗力（供双手武器对比用）
    --      双手武器替换主手+副手，基准应为两者之和（与 EquipmentBag 一致）
    local offhandPower = 0
    if slotName == "weapon" and heroEquipped then
        local ohSeq = heroEquipped["offhand"]
        if ohSeq then
            local ohItem = inventory[tostring(ohSeq)]
            if ohItem then
                offhandPower = CharacterDetail._EquipDetail.calcEquipPower(ohItem, heroId)
            end
        end
    end

    -- 2) 收集所有英雄已装备的 seq（这些装备不可用于提升判断）
    --    使用 tonumber 做数字比较，避免 tostring(int) vs tostring(float) 不匹配
    local equippedSeqNums = {}  -- [number] = true
    if equipData.equipped then
        for _, heroSlots in pairs(equipData.equipped) do
            if type(heroSlots) == "table" then
                for _, eqSeq in pairs(heroSlots) do
                    local n = tonumber(eqSeq)
                    if n then equippedSeqNums[n] = true end
                end
            end
        end
    end

    -- 3) 构建英雄可穿戴子类型集合
    local wearableSet = nil  -- nil = 不限制
    local heroCfg = HC.get(heroId)
    if heroCfg then
        if slotName == "weapon" then
            local types = heroCfg.weaponTypes
            if types and #types > 0 then
                wearableSet = {}
                for _, t in ipairs(types) do wearableSet[t] = true end
            end
        elseif slotName == "offhand" then
            local types = heroCfg.offhandTypes
            if types and #types > 0 then
                wearableSet = {}
                for _, t in ipairs(types) do wearableSet[t] = true end
            end
        elseif slotName == "armor" then
            local classCfg = CC.get(heroCfg.classId)
            if classCfg and classCfg.armorTypes and #classCfg.armorTypes > 0 then
                wearableSet = {}
                for _, armorEnum in ipairs(classCfg.armorTypes) do
                    local name = AD.ARMOR_TYPE_NAME[armorEnum]
                    if name then wearableSet[name] = true end
                end
            end
        end
        -- accessory: wearableSet 保持 nil，不限制
    end

    -- 4) 遍历背包，找到任一可穿戴且战斗力更高的未装备装备即返回 true
    for seq, equip in pairs(inventory) do
        local seqNum = tonumber(seq)
        if equip.slot == slotName and seqNum and not equippedSeqNums[seqNum] then
            -- 可穿戴类型检查
            if not wearableSet or wearableSet[equip.type] then
                local itemPower = CharacterDetail._EquipDetail.calcEquipPower(equip, heroId)
                -- 双手武器替换主手+副手，基准用两者之和（与 EquipmentBag 一致）
                local baseline = equippedPower
                if slotName == "weapon" and equip.grip == "twohand" then
                    baseline = equippedPower + offhandPower
                end
                if itemPower > baseline then
                    return true
                end
            end
        end
    end
    return false
end

--- 检查指定英雄是否有任意槽位可提升（用于入口链路角标）
--- 需要复刻 CharacterDetail 渲染中的双手武器占用副手判断，
--- 避免副手被双手武器占用时仍误报可提升。
---@param heroId number
---@return boolean
function CharacterDetail.hasAnyUpgradeForHero(heroId)
    local equipData = PlayerStore.Get("equipment")
    if not equipData then return false end

    local inventory = equipData.inventory
    local heroEquipped = equipData.equipped and equipData.equipped[heroId]

    -- 检测主手是否为双手武器 → 副手槽位被占用则跳过
    local offhandOccupied = false
    if heroEquipped and inventory then
        local offSeq = heroEquipped["offhand"]
        -- 副手本身没装备时，检查主手 grip
        if not offSeq or not inventory[tostring(offSeq)] then
            local wpnSeq = heroEquipped["weapon"]
            if wpnSeq then
                local wpnItem = inventory[tostring(wpnSeq)]
                if wpnItem and wpnItem.grip == "twohand" then
                    offhandOccupied = true
                end
            end
        end
    end

    for _, slot in ipairs(DT_SLOTS) do
        -- 双手武器占用副手时，跳过 offhand 槽位
        if not (slot.slot == "offhand" and offhandOccupied) then
            if CharacterDetail._hasUpgradeForSlot(heroId, slot.slot, equipData) then
                return true
            end
        end
    end
    return false
end

--- 检查指定英雄的碎片是否足够点亮下一个未激活的觉醒节点
--- 用于入口链路角标：BottomNav → 角色卡片 → 觉醒Tab
---@param heroId number
---@return boolean
function CharacterDetail.hasAwakeningUpgrade(heroId)
    local CharacterPanel = require("ui.CharacterPanel")
    local ownData = CharacterPanel.getOwnedHero(heroId)
    if not ownData then return false end
    local AwakeningConfig = require("config.AwakeningConfig")
    -- 计算已激活节点数（节点按顺序激活：1, 2, 3, ...）
    local awakening = ownData.awakening
    local activatedCount = 0
    if awakening then
        for _ in pairs(awakening) do
            activatedCount = activatedCount + 1
        end
    end
    -- 下一个待点亮的节点
    local nextNode = activatedCount + 1
    local cost = AwakeningConfig.getShardCost(nextNode)
    if cost <= 0 then return false end  -- 所有节点已点亮，无需角标
    -- 检查碎片是否足够
    local shards = ownData.shards or 0
    return shards >= cost
end

-- ======================== Public API ========================

--- 初始化（加载详情界面专用图片）
function CharacterDetail.init(vg)
    -- 装备图标/品质背景缓存已迁移至 ImageCache 共享模块
    CharacterDetail._ImageCache.init(vg)
    -- imgIconUp 挂在模块表上，供 Draw 通过 CharacterDetailRef 访问
    CharacterDetail._imgIconUp = nvgCreateImage(vg, "image/ICON_UP.png", 0)
    -- 委托 Draw 子模块加载所有详情界面图片
    Draw.initImages(vg)
    -- 初始化觉醒面板图片
    AwakeningPanel.initImages(vg)
    -- 初始化装备背包子界面
    EquipmentBag.init(vg)
    print("[CharacterDetail] init OK")
end

--- 获取装备图标（委托 ImageCache 共享缓存）
---@param templateId string 模板 ID（如 "W1"）
---@return number nvgImage handle (-1 if failed)
function CharacterDetail._getEquipIcon(templateId)
    return CharacterDetail._ImageCache.getEquipIcon(templateId)
end

--- 获取品质背景框（委托 ImageCache 共享缓存）
---@param quality number 品质等级（1-5）
---@return number nvgImage handle (-1 if failed)
function CharacterDetail._getQualityBg(quality)
    return CharacterDetail._ImageCache.getQualityBg(quality)
end

--- 注入来自 CharacterPanel 的共享资源
---@param ctx table { imgHeroCards, imgClassIcons, imgPower, imgLvlBadge, imgExpBarBg, imgExpBarFill, getOwnedData, calcHeroPower, getHeroRoster }
function CharacterDetail.setContext(ctx)
    -- 保存 roster 获取函数（用于左右切换角色）
    CharacterDetail._getHeroRoster = ctx.getHeroRoster
    -- 扩展 ctx 并传递给 Draw 子模块
    Draw.setContext({
        detailState       = detailState,
        getOwnedData      = ctx.getOwnedData,
        calcHeroPower     = ctx.calcHeroPower,
        CharacterDetail   = CharacterDetail,
        collectAttributes = collectAttributes,
        clampAttrScroll   = clampAttrScroll,
        imgHeroCards      = ctx.imgHeroCards,
        imgClassIcons     = ctx.imgClassIcons,
        imgPower          = ctx.imgPower,
        imgLvlBadge       = ctx.imgLvlBadge,
        imgExpBarBg       = ctx.imgExpBarBg,
        imgExpBarFill     = ctx.imgExpBarFill,
    })
    -- 配装面板绘制函数注入 Draw 模块
    Draw._drawEquipPanel = CharacterDetail._EquipPanel.draw
    -- 觉醒面板注入职业图标和数据获取
    AwakeningPanel.setClassIcons(ctx.imgClassIcons)
    AwakeningPanel.setOwnedDataGetter(ctx.getOwnedData)
end

--- 打开详情界面
---@param heroId number
function CharacterDetail.open(heroId)
    detailState.open = true
    detailState.closing = false
    detailState.heroId = heroId
    detailState.tab = "attr"
    detailState.tabFrom = "attr"
    detailState.tabSwitchTime = 0
    detailState.openTime = time.elapsedTime
    detailState.switchDir = nil  -- 普通打开：使用垂直滑入动画
    detailState.attrScrollY   = 0
    detailState.attrScrollMax = 0
    detailState.attrDragging  = false
    detailState.attrScrollVel = 0
    detailState.attrTip       = nil
    AwakeningPanel.reset(heroId)
    local heroCfg = HC.get(heroId)
    print("[CharacterDetail] 打开角色详情: " .. (heroCfg and heroCfg.name or "?"))
end

--- 关闭详情界面（启动关闭动画）
function CharacterDetail.close()
    if detailState.closing then return end
    detailState.closing = true
    detailState.closeTime = time.elapsedTime
    print("[CharacterDetail] 关闭角色详情（动画）")
end

--- 立即关闭详情界面（跳过关闭动画，用于跨页面跳转）
function CharacterDetail.forceClose()
    detailState.open    = false
    detailState.closing = false
    detailState.heroId  = nil
    print("[CharacterDetail] 强制关闭角色详情（跳过动画）")
end

--- 切换到前/后一个角色（direction: -1=上一个, 1=下一个）
function CharacterDetail._switchHero(direction)
    local getRoster = CharacterDetail._getHeroRoster
    if not getRoster then return end
    local roster = getRoster()
    if not roster or #roster == 0 then return end

    -- 在 roster 中查找当前角色的索引
    local curIdx = nil
    for i, entry in ipairs(roster) do
        if entry.heroId == detailState.heroId then
            curIdx = i
            break
        end
    end
    if not curIdx then return end

    -- 循环切换（跳过未解锁角色）
    local nextIdx = curIdx
    for _ = 1, #roster - 1 do
        nextIdx = nextIdx + direction
        if nextIdx < 1 then nextIdx = #roster end
        if nextIdx > #roster then nextIdx = 1 end
        if roster[nextIdx].owned then
            break
        end
    end
    -- 如果绕了一圈没有找到其他已拥有角色，不切换
    if nextIdx == curIdx or not roster[nextIdx].owned then return end

    local nextHeroId = roster[nextIdx].heroId
    -- 切换角色：使用水平滑动动画，保持当前tab不变
    local currentTab = detailState.tab
    detailState.heroId = nextHeroId
    detailState.tab = currentTab
    detailState.tabFrom = currentTab
    detailState.tabSwitchTime = 0
    detailState.openTime = time.elapsedTime
    detailState.switchDir = direction  -- -1=左切, 1=右切（触发水平滑入动画）
    detailState.attrScrollY   = 0
    detailState.attrScrollMax = 0
    detailState.attrDragging  = false
    detailState.attrScrollVel = 0
    detailState.attrTip       = nil
    AwakeningPanel.reset(nextHeroId)
    print("[CharacterDetail] 箭头切换角色: " .. tostring(detailState.heroId))
end

--- 是否打开
---@return boolean
function CharacterDetail.isOpen()
    return detailState.open
end

--- 标记战斗力/装备缓存为脏（外部数据变化时由 CharacterPanel.refreshPowerCache 调用）
function CharacterDetail.markPowerDirty()
    Draw.markPowerDirty()
end

--- 判断点击是否在矩形区域内（中心坐标+尺寸）
local function hitTest(dx, dy, cx, cy, w, h)
    return dx >= cx - w * 0.5 and dx <= cx + w * 0.5
       and dy >= cy - h * 0.5 and dy <= cy + h * 0.5
end

--- 处理输入
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function CharacterDetail.handleInput(dx, dy)
    if not detailState.open then return false end
    if detailState.closing then return true end  -- 关闭动画中，消费事件但不处理

    -- 装备详情弹窗优先处理
    if CharacterDetail._EquipDetail.isOpen() then
        return CharacterDetail._EquipDetail.handleInput(dx, dy)
    end

    -- 装备背包优先处理
    if EquipmentBag.isOpen() then
        return EquipmentBag.handleInput(dx, dy)
    end

    -- 装备槽位点击
    for _, s in ipairs(DT_SLOTS) do
        if hitTest(dx, dy, s.cx, s.cy, DT_SLOT_SIZE, DT_SLOT_SIZE) then
            if detailState.tab == "equip" then
                -- 配装Tab：切换选中槽位，触发背包重新排序
                detailState.equipSlot = s.slot
                if CharacterDetail._EquipPanel then
                    CharacterDetail._EquipPanel.onSlotChanged(s.slot, detailState.heroId)
                end
            else
                -- 其他Tab：打开装备背包
                EquipmentBag.open(s.slot, s.name, detailState.heroId)
            end
            return true
        end
    end

    -- 一键卸下按钮
    if math.abs(dx - Draw.BTN_UNEQUIP_CX) <= Draw.BTN_BATCH_W * 0.5
       and math.abs(dy - Draw.BTN_UNEQUIP_CY) <= Draw.BTN_BATCH_H * 0.5 then
        BF.trigger("unequip_all")
        print("[CharacterDetail] 一键卸下: heroId=" .. tostring(detailState.heroId))
        require("network.Client").sendAction(
            require("shared.Protocol").ACTION_TYPES.UNEQUIP_ALL,
            { heroId = detailState.heroId }
        )
        return true
    end

    -- 一键装备按钮
    if math.abs(dx - Draw.BTN_EQUIP_CX) <= Draw.BTN_BATCH_W * 0.5
       and math.abs(dy - Draw.BTN_EQUIP_CY) <= Draw.BTN_BATCH_H * 0.5 then
        BF.trigger("equip_all")
        print("[CharacterDetail] 一键装备: heroId=" .. tostring(detailState.heroId))
        require("network.Client").sendAction(
            require("shared.Protocol").ACTION_TYPES.EQUIP_ALL_BEST,
            { heroId = detailState.heroId }
        )
        require("systems.GameSFX").play("install")
        return true
    end

    -- 返回按钮
    if hitTest(dx, dy, BTN_BACK_CX, BTN_BACK_CY, BTN_BACK_W, BTN_BACK_H) then
        CharacterDetail.close()
        return true
    end

    -- 左箭头切换上一个角色（热区覆盖整个背景）
    if hitTest(dx, dy, ARROW_BG_LEFT_CX, ARROW_CY, ARROW_BG_W, ARROW_BG_H) then
        CharacterDetail._switchHero(-1)
        return true
    end

    -- 右箭头切换下一个角色（热区覆盖整个背景）
    if hitTest(dx, dy, ARROW_BG_RIGHT_CX, ARROW_CY, ARROW_BG_W, ARROW_BG_H) then
        CharacterDetail._switchHero(1)
        return true
    end

    -- 如果已有气泡，点击任何位置关闭
    if detailState.attrTip then
        detailState.attrTip = nil
        return true
    end

    -- Tab 切换 —— 属性区域
    if hitTest(dx, dy, BTN_TAB_ATTR_CX, BTN_TAB_ATTR_CY, BTN_TAB_SLIDER_W, BTN_TAB_SLIDER_H) then
        if detailState.tab ~= "attr" then
            detailState.tabFrom = detailState.tab
            detailState.tabSwitchTime = time.elapsedTime
            detailState.tab = "attr"
            print("[CharacterDetail] 切换到属性页")
        end
        return true
    end

    -- Tab 切换 —— 配装区域
    if hitTest(dx, dy, BTN_TAB_EQUIP_CX, BTN_TAB_EQUIP_CY, BTN_TAB_SLIDER_W, BTN_TAB_SLIDER_H) then
        if detailState.tab ~= "equip" then
            detailState.tabFrom = detailState.tab
            detailState.tabSwitchTime = time.elapsedTime
            detailState.tab = "equip"
            print("[CharacterDetail] 切换到配装页")
        end
        return true
    end

    -- Tab 切换 —— 觉醒区域
    if hitTest(dx, dy, BTN_TAB_AWAKEN_CX, BTN_TAB_AWAKEN_CY, BTN_TAB_SLIDER_W, BTN_TAB_SLIDER_H) then
        if detailState.tab ~= "awaken" then
            detailState.tabFrom = detailState.tab
            detailState.tabSwitchTime = time.elapsedTime
            detailState.tab = "awaken"
            print("[CharacterDetail] 切换到觉醒页")
        end
        return true
    end

    -- === 配装面板输入委托 ===
    if detailState.tab == "equip" then
        if CharacterDetail._EquipPanel then
            return CharacterDetail._EquipPanel.handleInput(dx, dy, detailState.heroId, detailState)
        end
        return false
    end

    -- === 觉醒面板输入委托 ===
    if detailState.tab == "awaken" then
        return AwakeningPanel.handleInput(dx, dy, detailState.heroId)
    end

    -- === 属性区域点击检测（仅属性页） ===
    if detailState.tab == "attr" then
        local rowStep = ATTR_BOX_H + ATTR_ROW_GAP
        local cachedL = detailState.cachedLeft or {}
        local cachedR = detailState.cachedRight or {}
        local totalRows = math.max(#cachedL, #cachedR)

        -- 杂项属性区域（可滚动）
        if dy >= ATTR_CLIP_TOP and dy <= ATTR_CLIP_TOP + ATTR_CLIP_HEIGHT then
            for row = 1, totalRows do
                local rowY = ATTR_FIRST_ROW_Y + (row - 1) * rowStep - detailState.attrScrollY
                if rowY >= ATTR_CLIP_TOP - ATTR_BOX_H * 0.5
                   and rowY <= ATTR_CLIP_TOP + ATTR_CLIP_HEIGHT + ATTR_BOX_H * 0.5 then
                    -- 左列
                    if row <= #cachedL and math.abs(dx - ATTR_COL1_CX) <= ATTR_BOX_W * 0.5
                       and math.abs(dy - rowY) <= ATTR_BOX_H * 0.5 then
                        local attr = cachedL[row]
                        local desc = attr.desc or AD.getDesc(attr.key)
                        if desc and desc ~= "" then
                            detailState.attrTip = {
                                boxCX = ATTR_COL1_CX, boxTopY = rowY - ATTR_BOX_H * 0.5,
                                desc = desc, name = attr.name, area = "attr",
                            }
                        end
                        return true
                    end
                    -- 右列
                    if row <= #cachedR and math.abs(dx - ATTR_COL2_CX) <= ATTR_BOX_W * 0.5
                       and math.abs(dy - rowY) <= ATTR_BOX_H * 0.5 then
                        local attr = cachedR[row]
                        local desc = attr.desc or AD.getDesc(attr.key)
                        if desc and desc ~= "" then
                            detailState.attrTip = {
                                boxCX = ATTR_COL2_CX, boxTopY = rowY - ATTR_BOX_H * 0.5,
                                desc = desc, name = attr.name, area = "attr",
                            }
                        end
                        return true
                    end
                end
            end
        end

        -- 六围区域点击检测
        for _, st in ipairs(STAT_LAYOUT) do
            local boxCX = (st.col == 1) and STAT_COL1_CX or STAT_COL2_CX
            local boxCY = STAT_ROW1_CY + (st.row - 1) * STAT_ROW_STEP
            if math.abs(dx - boxCX) <= STAT_BOX_W * 0.5
               and math.abs(dy - boxCY) <= STAT_BOX_H * 0.5 then
                local desc = AD.getDesc(st.key)
                if desc ~= "" then
                    detailState.attrTip = {
                        boxCX = boxCX, boxTopY = boxCY - STAT_BOX_H * 0.5,
                        desc = desc, name = st.name, area = "stat",
                    }
                end
                return true
            end
        end
    end

    -- 点击详情面板内其他区域 —— 消费事件，不关闭
    return true
end

--- 判断坐标是否在属性区域内（需考虑下半部分的滑入偏移，但动画结束后偏移为0）
local function isInAttrArea(dx, dy)
    return dx >= 0 and dx <= DESIGN_W
       and dy >= ATTR_CLIP_TOP and dy <= ATTR_CLIP_TOP + ATTR_CLIP_HEIGHT
end

--- 拖拽开始（由 CharacterPanel 委托）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function CharacterDetail.handleDragBegin(dx, dy)
    if not detailState.open or detailState.closing then return true end
    if CharacterDetail._EquipDetail.isOpen() then return true end
    if EquipmentBag.isOpen() then return EquipmentBag.handleDragBegin(dx, dy) end
    detailState.attrTip = nil  -- 拖拽时关闭气泡
    -- 配装面板滚动（只在格子区域内启动）
    if detailState.tab == "equip" and CharacterDetail._EquipPanel then
        if CharacterDetail._EquipPanel.isInGridArea(dy) then
            detailState.equipDragging = true
            CharacterDetail._EquipPanel.onDragStart(dy)
            return true
        end
    end
    if isInAttrArea(dx, dy) then
        detailState.attrDragging  = true
        detailState.attrDragLastY = dy
        detailState.attrScrollVel = 0
        return true
    end
    return true  -- 详情打开时消费所有拖拽
end

--- 拖拽移动（由 CharacterPanel 委托）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function CharacterDetail.handleDragMove(dx, dy)
    if not detailState.open or detailState.closing then return true end
    if CharacterDetail._EquipDetail.isOpen() then return true end
    if EquipmentBag.isOpen() then return EquipmentBag.handleDragMove(dx, dy) end
    -- 配装面板滚动
    if detailState.equipDragging and CharacterDetail._EquipPanel then
        local panel = CharacterDetail._EquipPanel
        local delta = panel.getDragLastY() - dy
        panel.onDrag(delta)
        panel.setDragLastY(dy)
        return true
    end
    if detailState.attrDragging then
        local delta = detailState.attrDragLastY - dy
        detailState.attrScrollY = detailState.attrScrollY + delta
        clampAttrScroll()
        detailState.attrScrollVel = delta  -- 记录帧间速度
        detailState.attrDragLastY = dy
    end
    return true
end

--- 拖拽结束（由 CharacterPanel 委托）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function CharacterDetail.handleDragEnd(dx, dy)
    if not detailState.open then return false end
    if CharacterDetail._EquipDetail.isOpen() then return true end
    if EquipmentBag.isOpen() then return EquipmentBag.handleDragEnd(dx, dy) end
    -- 配装面板滚动结束
    if detailState.equipDragging and CharacterDetail._EquipPanel then
        detailState.equipDragging = false
        CharacterDetail._EquipPanel.onDragEnd()
        return true
    end
    if detailState.attrDragging then
        detailState.attrDragging = false
        -- attrScrollVel 已在 handleDragMove 中记录，用于惯性
    end
    return true
end

--- 鼠标滚轮滚动（由 CharacterPanel 委托）
---@param wheel number 滚轮值（正=向上，负=向下）
function CharacterDetail.handleScroll(wheel)
    if not detailState.open or detailState.closing then return end
    if CharacterDetail._EquipDetail.isOpen() then return end
    if EquipmentBag.isOpen() then EquipmentBag.handleScroll(wheel); return end
    -- 配装面板滚轮
    if detailState.tab == "equip" and CharacterDetail._EquipPanel then
        CharacterDetail._EquipPanel.onDrag(wheel * ATTR_SCROLL_WHEEL_STEP)
        return
    end
    detailState.attrScrollY = detailState.attrScrollY - wheel * ATTR_SCROLL_WHEEL_STEP
    clampAttrScroll()
    detailState.attrScrollVel = 0
end

--- 绘制角色详情二级界面
function CharacterDetail.draw(vg)
    if not detailState.open then return end
    Draw.draw(vg)
end

return CharacterDetail
