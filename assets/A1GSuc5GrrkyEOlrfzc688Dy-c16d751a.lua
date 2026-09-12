-- ============================================================================
-- TutorialManager.lua — 新手引导状态管理 + 蒙层渲染
-- 职责:
--   1. 跟踪当前激活的引导组和步骤
--   2. 提供 registerHotspot() 供各 UI 模块每帧注册热点坐标
--   3. 渲染半透明蒙层 + 高亮镂空 + 引导气泡文字
--   4. 检查advanceOn 事件（click_highlight / enter_panel_*），推进步骤
--   5. 提供 isBuildingUnlocked(key) 替代 ExpTable.isBuildingUnlocked
-- ============================================================================

local TutorialConfig     = require("config.TutorialConfig")
local DrawUtil           = require("core.DrawUtil")
local GameConfig         = require("config.GameConfig")
local ScenarioDialogue   = require("ui.ScenarioDialogue")

local TutorialManager = {}

-- ======================== 设计常量 ========================
local DW = GameConfig.Design.WIDTH   -- 1080
local DH = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 蒙层/气泡 UI 参数 ========================
local MASK_ALPHA       = 180      -- 蒙层不透明度 0-255
local HIGHLIGHT_PAD    = 20       -- 高亮区域外扩像素
local HIGHLIGHT_RADIUS = 16       -- 高亮圆角半径
local BUBBLE_W         = 760      -- 气泡宽度
local BUBBLE_H         = 140      -- 气泡高度（最小，随文本增长）
local BUBBLE_RADIUS    = 24       -- 气泡圆角半径
local BUBBLE_BG        = { 255, 248, 220, 255 } -- 暖米白色 RGBA（完全不透明，避免蒙层透出导致偏暗）
local BUBBLE_TEXT_COLOR = { 0x28, 0x14, 0x08 }  -- 深棕色（加深以保证对比度）
local BUBBLE_FONT_SIZE = 40
local BUBBLE_LINE_HEIGHT = 1.4
local BUBBLE_PADDING   = 40      -- 气泡内边距
local ARROW_SIZE       = 28      -- 气泡小三角尺寸

-- 高亮闪烁参数
local PULSE_SPEED   = 2.0    -- Hz
local PULSE_MIN_A   = 80     -- 最小不透明度 0-255
local PULSE_MAX_A   = 200    -- 最大不透明度 0-255

-- 跳过按钮参数
local SKIP_BTN_W       = 300     -- 跳过按钮宽度
local SKIP_BTN_H       = 96      -- 跳过按钮高度
local SKIP_BTN_RADIUS  = 20      -- 跳过按钮圆角半径
local SKIP_BTN_CX      = 540     -- 跳过按钮中心 X（屏幕底部居中）
local SKIP_BTN_CY      = 2100    -- 跳过按钮中心 Y（底部留出游戏区域）
local SKIP_BTN_FONT    = 40      -- 跳过按钮字体大小
local SKIP_BTN_DELAY   = 1.0     -- 引导开始后延迟显示跳过按钮（秒）

-- 入场/离场动画时长（秒）
local ANIM_IN_DUR      = 0.25    -- 引导蒙层入场动画时长
local ANIM_OUT_DUR     = 0.2     -- 引导蒙层离场动画时长
-- ======================== 内部状态========================
---@type any
local vg_           = nil   -- NanoVG context

--- 当前激活的引导组ID（nil = 无引导）
---@type number|nil
local activeGroup_  = nil

--- 当前步骤索引（1-based）
---@type number
local activeStep_   = 1

--- 入场/离场动画状态
--- "in" | "out" | "idle"
---@type string
local animState_    = "idle"

---@type number
local animT_        = 0

--- 离场完成后要启动的下一组（nil=引导结束）
---@type number|nil
local nextGroup_    = nil

--- 全局计时（用于闪烁动画）
---@type number
local elapsed_      = 0

--- 当前引导组启动后经过的时间（用于跳过按钮延迟显示）
---@type number
local groupElapsed_ = 0

--- 本帧注册的热点表: key →{ cx, cy, w, h }
--- 每帧开始时清空，由各 UI 模块的 draw() 时调用 registerHotspot 填充
---@type table<string, {cx:number, cy:number, w:number, h:number}>
local hotspots_     = {}

--- PlayerStore 引用（由 init 注入，避免循环依赖）
---@type table|nil
local playerStore_  = nil

--- 上次各建筑面板解锁状态（用于变化检测，防止每帧刷屏）
---@type table<string, boolean>
local lastUnlockState_ = {}

-- ======================== 内部工具 ========================

local function easeOutCubic(t)
    t = math.max(0, math.min(1, t))
    return 1 - (1 - t) ^ 3
end

--- 检查指定情景ID 是否已被领取
---@param scenarioId number
---@return boolean
local function isScenarioClaimed(scenarioId)
    if not playerStore_ then return false end
    local sessionData = playerStore_.Get("session")
    if not sessionData then return false end
    local claimed = sessionData.claimedScenarios
    if not claimed then return false end
    -- 同时检查字符串 key 和数字 key（防止 cjson 反序列化后 key 类型不一致）
    local byStr = claimed[tostring(scenarioId)] == true
    local byNum = claimed[scenarioId] == true
    return byStr or byNum
end

--- 检查引导组是否已完成（任意一个 triggerScenario 已领取）
---@param groupId number
---@return boolean
-- excludeScenarioId: 排除的 id 在 claimed 检查（用于 startGroup 时避免把触发 id 误判为已完成）
local function isGroupCompleted(groupId, excludeScenarioId)
    local group = TutorialConfig[groupId]
    if not group or not group.triggerScenarios then return true end
    for _, sid in ipairs(group.triggerScenarios) do
        if sid ~= excludeScenarioId and isScenarioClaimed(sid) then
            return true
        end
    end
    return false
end

--- 获取当前步骤配置
---@return table|nil
local function getCurrentStep()
    if not activeGroup_ then return nil end
    local group = TutorialConfig[activeGroup_]
    if not group or not group.steps then return nil end
    return group.steps[activeStep_]
end

--- 处理引导组完成时的解锁逻辑（面板 Tab 解锁）
---@param groupId number
local function applyGroupUnlocks(groupId)
    local group = TutorialConfig[groupId]
    if not group or not group.unlocks then return end

    local ok, BN = pcall(require, "ui.BottomNav")
    if not ok then return end

    -- panelKey → tabIndex 映射
       local PANEL_TO_TAB = {
           character_panel = 1,
           log_panel       = 2,
           town_panel      = 4,
            dungeon_panel   = 5,
       }
    for _, uk in ipairs(group.unlocks) do
        local tabIdx = PANEL_TO_TAB[uk]
        if tabIdx then
            BN.setTabLocked(tabIdx, false)
            print("[TutorialManager] unlocked panel " .. uk .. " → tab " .. tabIdx)
        end
    end
end

--- 内部：推进到下一步；若已是最后一步则触发离场动画
local function advanceStep()
    if not activeGroup_ then return end
    local group = TutorialConfig[activeGroup_]
    if not group then return end

    activeStep_ = activeStep_ + 1
    if activeStep_ > #group.steps then
        -- 本组全部步骤完成 → 离场动画
        animState_ = "out"
        animT_     = 0
        nextGroup_ = nil
        print("[TutorialManager] group " .. activeGroup_ .. " completed, fading out")
    else
        print("[TutorialManager] advance to step " .. activeStep_)
    end
end

-- ======================== 公开接口 ========================

--- 初始化（在 Client Start() 中调用一次）
---@param vg any NanoVG context
---@param playerStoreRef table  PlayerStore 模块引用（注入，避免循环 require）
function TutorialManager.init(vg, playerStoreRef)
    vg_ = vg
    playerStore_ = playerStoreRef
    -- 重置解锁状态变化检测缓存，确保本局首次调用时总能打出日志
    lastUnlockState_ = {}
    print("[TM][init] playerStore_=" .. tostring(playerStoreRef ~= nil)
        .. " battleData=" .. tostring(playerStoreRef and playerStoreRef.Get("battle") ~= nil)
        .. " maxStageId=" .. tostring(playerStoreRef and playerStoreRef.Get("battle") and playerStoreRef.Get("battle").maxStageId or "N/A"))

    -- playerStore 注入后，重新刷新 BottomNav 的解锁状态
    -- （BottomNav.init 先于 TutorialManager.init 执行，所以需要在此补刷一次）
    local okBN, BN = pcall(require, "ui.BottomNav")
    if okBN then
        print("[TM][init] calling refreshUnlockState...")
        BN.refreshUnlockState()
        print("[TM][init] refreshUnlockState done")
    end
end

--- 检查引导组是否已完成（供外部查询）
---@param groupId number
---@return boolean
function TutorialManager.isGroupCompleted(groupId)
    return isGroupCompleted(groupId)
end

-- ======================== maxStageId 解锁阈值========================
-- stageId 格式：chapter * 100 + stage，如 101=1-1，204=2-4
-- "大于阈值"意为玩家已通关对应关卡，该功能即可解锁
-- maxStageId 记录的是通关后进入的【下一关】ID（见 BattleService.lua）
-- 例：通关 1-1 → nextId=102 → maxStageId=102；通关 1-4 → maxStageId=105
local PANEL_UNLOCK_THRESHOLDS = {
    character_panel = 101,   -- 通关 1-1 后解锁（maxStageId 变为 102 > 101）
    log_panel       = 104,   -- 通关 1-4 后解锁（maxStageId 变为 105 > 104）
    town_panel      = 105,   -- 通关 1-5 后解锁（maxStageId 变为下章首关 > 105）
}

local BUILDING_UNLOCK_THRESHOLDS = {
    -- church 和 tavern 默认开放，不设阈值
    -- 解锁判定：maxStageId > threshold（maxStageId = 下一个 stageId）
    smith   = 204,   -- 首通 2-4 后解锁（通 2-4 → maxStageId=205 > 204）
    arena   = 205,   -- 首通 2-5 后解锁（通 2-5 → maxStageId=301 > 205）
}

--- 获取当前最远通关 stageId（0 表示未通关任何关卡）
---@return number
local function getMaxStageId()
    if not playerStore_ then return 0 end
    local battleData = playerStore_.Get("battle")
    return battleData and tonumber(battleData.maxStageId) or 0
end

--- 检查某建筑是否已被解锁（基于 maxStageId 和 clearedStages 判断）
--- 解锁条件（满足任一即可）：
---   1. maxStageId > threshold（玩家已前进到下一关）
---   2. clearedStages[threshold] == true（玩家已通关阈值关卡，但尚未点击前进）
---@param buildingKey string  如 "church" / "tavern" / "smith" / "arena"
---@return boolean
function TutorialManager.isBuildingUnlocked(buildingKey)
    local threshold = BUILDING_UNLOCK_THRESHOLDS[buildingKey]
    if not threshold then
        -- 未配置阈值的建筑默认解锁
        return true
    end

    local battleData = playerStore_ and playerStore_.Get("battle")
    if not battleData then return false end

    local maxSId = tonumber(battleData.maxStageId) or 0
    local result = maxSId > threshold

    -- 补充判定：阈值关卡已被标记通关（解决玩家通关后未点前进按钮的情况）
    if not result then
        local clearedStages = battleData.clearedStages
        if clearedStages and clearedStages[tostring(threshold)] then
            result = true
        end
    end

    -- 变化检测：只在状态改变时打日志
    local stateKey = "building:" .. buildingKey
    if lastUnlockState_[stateKey] ~= result then
        lastUnlockState_[stateKey] = result
        if result then
            print("[TM][isBuildingUnlocked] →" .. buildingKey
                .. " -> UNLOCKED maxStageId=" .. maxSId .. " threshold=" .. threshold)
        else
            print("[TM][isBuildingUnlocked] →" .. buildingKey
                .. " -> LOCKED maxStageId=" .. maxSId .. " threshold=" .. threshold)
        end
    end

    return result
end

--- 检查某面板 key 是否已解锁（基于 maxStageId 和 clearedStages 判断）
---@param panelKey string  如 "character_panel" / "log_panel" / "town_panel"
---@return boolean
function TutorialManager.isPanelUnlocked(panelKey)
    local threshold = PANEL_UNLOCK_THRESHOLDS[panelKey]
    if not threshold then
        return false
    end

    local battleData = playerStore_ and playerStore_.Get("battle")
    if not battleData then return false end

    local maxSId = tonumber(battleData.maxStageId) or 0
    local result = maxSId > threshold

    -- 补充判定：阈值关卡已被标记通关（与 isBuildingUnlocked 保持一致）
    if not result then
        local clearedStages = battleData.clearedStages
        if clearedStages and clearedStages[tostring(threshold)] then
            result = true
        end
    end

    -- 变化检测：只在状态改变时打日志
    local stateKey = "panel:" .. panelKey
    if lastUnlockState_[stateKey] ~= result then
        lastUnlockState_[stateKey] = result
        if result then
            print("[TM][isPanelUnlocked] →" .. panelKey
                .. " -> UNLOCKED maxStageId=" .. maxSId .. " threshold=" .. threshold)
        else
            print("[TM][isPanelUnlocked] →" .. panelKey
                .. " -> LOCKED maxStageId=" .. maxSId .. " threshold=" .. threshold)
        end
    end

    return result
end

--- 注册热点坐标（UI 模块的 draw() 时调用）
--- 本帧注册的坐标供蒙层渲染和点击检测使用
---@param key string 热点标识 key（与 TutorialConfig 中的 highlight 对应）
---@param cx number  中心 X（设计坐标）
---@param cy number  中心 Y（设计坐标）
---@param w  number  宽度
---@param h  number  高度
function TutorialManager.registerHotspot(key, cx, cy, w, h)
    hotspots_[key] = { cx = cx, cy = cy, w = w, h = h }
end

--- 清空本帧热点缓存（在每帧 update 开始时调用，确保热点数据是最新帧注册的）
function TutorialManager.clearHotspots()
    hotspots_ = {}
end

--- 判断当前是否有引导激活
---@return boolean
function TutorialManager.isActive()
    return activeGroup_ ~= nil
end

--- 获取当前引导步骤的高亮 key（供 UI 判断是否禁止特定交互）
---@return string|nil
function TutorialManager.getCurrentHighlight()
    if not activeGroup_ then return nil end
    local group = TutorialConfig[activeGroup_]
    if not group or not group.steps then return nil end
    local step = group.steps[activeStep_]
    return step and step.highlight or nil
end

--- 设置新获得英雄的 ID（用于 character_new_hero 热点定位）
local newHeroId_ = nil
---@param heroId number|nil
function TutorialManager.setNewHeroId(heroId)
    newHeroId_ = heroId
end

--- 获取新获得英雄的 ID
---@return number|nil
function TutorialManager.getNewHeroId()
    return newHeroId_
end

--- 启动指定引导组
---@param groupId number
-- triggerScenarioId: 触发本次启动的情景 ID（排除在完成检查之外，避免"刚 claim 就被认为已完成"）
local function startGroupInternal(groupId, triggerScenarioId)
    local group = TutorialConfig[groupId]
    if not group then return end
    -- 排除触发 id 本身，检查是否还有其他 triggerScenario 被 claimed（说明真的完成过了）
    if isGroupCompleted(groupId, triggerScenarioId) then
        return
    end
    if activeGroup_ == groupId then return end

    activeGroup_ = groupId
    activeStep_  = 1
    animState_   = "in"
    animT_       = 0
    groupElapsed_ = 0
    applyGroupUnlocks(groupId)
end

--- 启动指定引导组（外部直接调用，不排除任何 scenario）
---@param groupId number
function TutorialManager.startGroup(groupId)
    startGroupInternal(groupId, nil)
end

--- 在情景对话 claim 后调用，检查是否需要启动对应引导组
---@param scenarioId number 刚被领取的情景 ID
function TutorialManager.onScenarioClaimed(scenarioId)
    local groupId = TutorialConfig.SCENARIO_TO_GROUP[scenarioId]
    if not groupId then return end
    if activeGroup_ == groupId then return end
    startGroupInternal(groupId, scenarioId)
end

--- 通知引导事件（用于 enter_panel_* 类型的步骤推进）
---@param eventName string  如 "enter_panel_character" / "enter_panel_town" 等
function TutorialManager.notifyEvent(eventName)
    if not activeGroup_ or animState_ == "out" then return end
    local step = getCurrentStep()
    if not step then return end
    if step.advanceOn == eventName then
        advanceStep()
    end
end

--- 强制跳过当前引导组（跳过按钮触发）
function TutorialManager.skipCurrentGroup()
    if not activeGroup_ then return end
    print("[TutorialManager] force skipping group " .. activeGroup_)
    -- 触发离场动画
    animState_ = "out"
    animT_     = 0
    nextGroup_ = nil
end

--- 处理点击事件（由 ClientInput 的 dispatchDragEndAndTap 中调用）
--- 返回 true 表示点击已被引导层消费（外部应阻止穿透）
--- 返回 false 表示引导层未消费（正常透传）
---@param dx number 设计坐标 X
---@param dy number 设计坐标 Y
---@return boolean consumed
function TutorialManager.handleClick(dx, dy)
    if not activeGroup_ or animState_ == "out" then return false end

    -- 跳过按钮点击检测（延迟显示后才可点击）
    if groupElapsed_ >= SKIP_BTN_DELAY then
        if DrawUtil.hitTest(dx, dy, SKIP_BTN_CX, SKIP_BTN_CY, SKIP_BTN_W, SKIP_BTN_H) then
            print("[TutorialManager] skip button clicked, skipping group " .. tostring(activeGroup_))
            TutorialManager.skipCurrentGroup()
            return true
        end
    end

    local step = getCurrentStep()
    if not step then return false end

    -- invisible 步骤：不绘制 UI 也不拦截点击，仅等待 notifyEvent 触发
    if step.invisible then return false end

    -- click_highlight 类型：点击高亮区域推进，点击其他区域拦截
    if step.advanceOn == "click_highlight" then
        local hs = hotspots_[step.highlight]
        if hs then
            local padW = hs.w + HIGHLIGHT_PAD * 2
            local padH = hs.h + HIGHLIGHT_PAD * 2
            if DrawUtil.hitTest(dx, dy, hs.cx, hs.cy, padW, padH) then
                advanceStep()
                return false  -- 允许点击穿透到实际 UI（让按钮正常响应）
            end
        end
        -- 点击非高亮区域 → 拦截，不穿透
        return true
    end

    -- enter_panel_* 类型：不拦截点击（等 notifyEvent 触发）
    return false
end

--- 每帧更新
---@param dt number 帧间隔
function TutorialManager.update(dt)
    elapsed_ = elapsed_ + dt

    if not activeGroup_ then return end

    -- 跳过按钮延迟计时
    groupElapsed_ = groupElapsed_ + dt

    -- 动画推进
    if animState_ ~= "idle" then
        animT_ = animT_ + dt
        local dur = animState_ == "in" and ANIM_IN_DUR or ANIM_OUT_DUR
        if animT_ >= dur then
            animT_ = dur
            if animState_ == "out" then
                -- 离场完成，清除状态
                activeGroup_ = nil
                activeStep_  = 1
                animState_   = "idle"
                animT_       = 0
                if nextGroup_ then
                    TutorialManager.startGroup(nextGroup_)
                    nextGroup_ = nil
                end
            else
                animState_ = "idle"
                animT_     = 0
            end
        end
    end
end

-- ======================== 渲染 ========================

--- 绘制半透明蒙层，带高亮镂空（偶奇规则）
---@param hs {cx:number, cy:number, w:number, h:number}|nil 高亮热点（nil = 无镂空）
---@param alpha number 蒙层整体透明度 0~1
local function drawMask(hs, alpha)
    local maskA = math.floor(MASK_ALPHA * alpha + 0.5)
    if maskA <= 0 then return end

    nvgSave(vg_)
    -- 使用偶奇填充规则实现镂空
    nvgBeginPath(vg_)
    -- 外层：全屏矩形（顺时针）
    nvgRect(vg_, 0, 0, DW, DH)

    -- 内层镂空：高亮区域圆角矩形（逆时针，偶奇规则下会镂空）
    if hs then
        local hx = hs.cx - hs.w * 0.5 - HIGHLIGHT_PAD
        local hy = hs.cy - hs.h * 0.5 - HIGHLIGHT_PAD
        local hw = hs.w + HIGHLIGHT_PAD * 2
        local hh = hs.h + HIGHLIGHT_PAD * 2
        -- 逆时针方向绘制圆角矩形（顺时针 + pathWinding 逆向）
        nvgPathWinding(vg_, NVG_HOLE)
        nvgRoundedRect(vg_, hx, hy, hw, hh, HIGHLIGHT_RADIUS)
    end

    nvgFillColor(vg_, nvgRGBA(0, 0, 0, maskA))
    nvgFill(vg_)
    nvgRestore(vg_)
end

--- 绘制高亮区域边框（闪烁脉冲效果）
---@param hs {cx:number, cy:number, w:number, h:number}
---@param alpha number 整体透明度 0~1
local function drawHighlightBorder(hs, alpha)
    local pulse = PULSE_MIN_A + (PULSE_MAX_A - PULSE_MIN_A)
        * (0.5 + 0.5 * math.sin(elapsed_ * PULSE_SPEED * math.pi * 2))
    local borderA = math.floor(pulse * alpha + 0.5)
    if borderA <= 0 then return end

    local hx = hs.cx - hs.w * 0.5 - HIGHLIGHT_PAD
    local hy = hs.cy - hs.h * 0.5 - HIGHLIGHT_PAD
    local hw = hs.w + HIGHLIGHT_PAD * 2
    local hh = hs.h + HIGHLIGHT_PAD * 2

    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, hx, hy, hw, hh, HIGHLIGHT_RADIUS)
    nvgStrokeColor(vg_, nvgRGBA(255, 220, 60, borderA))
    nvgStrokeWidth(vg_, 4)
    nvgStroke(vg_)
end

--- 绘制引导气泡（文字 + 背景 + 小三角指向高亮区域）
---@param text string
---@param hs {cx:number, cy:number, w:number, h:number}|nil
---@param alpha number 整体透明度 0~1
local function drawBubble(text, hs, alpha)
    if not text or text == "" then return end
    if alpha <= 0.01 then return end

    -- 计算气泡位置：优先在高亮区域上方，空间不足则在下方
    -- 同时避免与跳过按钮区域重叠
    local bubbleCX = DW * 0.5
    local bubbleCY

    local MARGIN = 20  -- 气泡与高亮区域间距
    -- 跳过按钮占用区域（需要避开）
    local skipBtnTop = SKIP_BTN_CY - SKIP_BTN_H * 0.5 - 20
    local skipBtnBot = SKIP_BTN_CY + SKIP_BTN_H * 0.5 + 20

    if hs then
        local hsTop = hs.cy - hs.h * 0.5 - HIGHLIGHT_PAD
        local hsBot = hs.cy + hs.h * 0.5 + HIGHLIGHT_PAD

        -- 计算上方和下方候选位置
        local aboveCY = hsTop - ARROW_SIZE - BUBBLE_H * 0.5 - MARGIN
        local belowCY = hsBot + ARROW_SIZE + BUBBLE_H * 0.5 + MARGIN

        -- 检查各方向是否可行
        local aboveOk = aboveCY - BUBBLE_H * 0.5 > 60
        local belowOk = belowCY + BUBBLE_H * 0.5 < skipBtnTop

        if aboveOk then
            bubbleCY = aboveCY
        elseif belowOk then
            bubbleCY = belowCY
        else
            -- 上下都有冲突，选择上方并贴近顶部安全区
            bubbleCY = math.max(BUBBLE_H * 0.5 + 60, aboveCY)
        end
    else
        -- 无高亮热点：显示在屏幕中部偏上（避开跳过按钮）
        bubbleCY = math.min(DH * 0.5, skipBtnTop - BUBBLE_H * 0.5 - MARGIN)
    end

    -- 确保气泡在设计区域内且不与跳过按钮重叠
    bubbleCY = math.max(BUBBLE_H * 0.5 + 20, math.min(skipBtnTop - BUBBLE_H * 0.5 - 10, bubbleCY))
    bubbleCX = math.max(BUBBLE_W * 0.5 + 20, math.min(DW - BUBBLE_W * 0.5 - 20, bubbleCX))

    local bgR  = BUBBLE_BG[1]
    local bgG  = BUBBLE_BG[2]
    local bgB  = BUBBLE_BG[3]
    local bgA  = math.floor(BUBBLE_BG[4] * alpha + 0.5)

    nvgSave(vg_)

    -- 气泡背景圆角矩形
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, bubbleCX - BUBBLE_W * 0.5, bubbleCY - BUBBLE_H * 0.5,
        BUBBLE_W, BUBBLE_H, BUBBLE_RADIUS)
    nvgFillColor(vg_, nvgRGBA(bgR, bgG, bgB, bgA))
    nvgFill(vg_)

    -- 气泡边框
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, bubbleCX - BUBBLE_W * 0.5, bubbleCY - BUBBLE_H * 0.5,
        BUBBLE_W, BUBBLE_H, BUBBLE_RADIUS)
    nvgStrokeColor(vg_, nvgRGBA(200, 160, 80, math.floor(200 * alpha)))
    nvgStrokeWidth(vg_, 3)
    nvgStroke(vg_)

    -- 小三角（指向高亮区域方向）
    if hs then
        local hsTop = hs.cy - hs.h * 0.5 - HIGHLIGHT_PAD
        local hsBot = hs.cy + hs.h * 0.5 + HIGHLIGHT_PAD
        local arrowX = math.max(bubbleCX - BUBBLE_W * 0.5 + BUBBLE_RADIUS * 2,
                          math.min(bubbleCX + BUBBLE_W * 0.5 - BUBBLE_RADIUS * 2,
                            hs.cx))
        local triA = math.floor(bgA)
        if bubbleCY < hs.cy then
            -- 气泡在上方 → 三角在气泡底部朝下
            local ty = bubbleCY + BUBBLE_H * 0.5
            nvgBeginPath(vg_)
            nvgMoveTo(vg_, arrowX - ARROW_SIZE, ty)
            nvgLineTo(vg_, arrowX + ARROW_SIZE, ty)
            nvgLineTo(vg_, arrowX, ty + ARROW_SIZE)
            nvgClosePath(vg_)
            nvgFillColor(vg_, nvgRGBA(bgR, bgG, bgB, triA))
            nvgFill(vg_)
        else
            -- 气泡在下方 → 三角在气泡顶部朝上
            local ty = bubbleCY - BUBBLE_H * 0.5
            nvgBeginPath(vg_)
            nvgMoveTo(vg_, arrowX - ARROW_SIZE, ty)
            nvgLineTo(vg_, arrowX + ARROW_SIZE, ty)
            nvgLineTo(vg_, arrowX, ty - ARROW_SIZE)
            nvgClosePath(vg_)
            nvgFillColor(vg_, nvgRGBA(bgR, bgG, bgB, triA))
            nvgFill(vg_)
        end
    end

    -- 文本（描边用气泡背景色，确保文字在不透明背景上清晰可读）
    DrawUtil.drawTextStroke(vg_,
        bubbleCX, bubbleCY,
        text, BUBBLE_FONT_SIZE,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        BUBBLE_TEXT_COLOR[1], BUBBLE_TEXT_COLOR[2], BUBBLE_TEXT_COLOR[3],
        3,
        { alpha = alpha, strokeColor = { BUBBLE_BG[1], BUBBLE_BG[2], BUBBLE_BG[3] } })

    nvgRestore(vg_)
end

--- 绘制跳过按钮（右上角半透明胶囊按钮）
---@param alpha number 整体透明度 0~1
local function drawSkipButton(alpha)
    if groupElapsed_ < SKIP_BTN_DELAY then return end
    local skipAlpha = math.min(1.0, (groupElapsed_ - SKIP_BTN_DELAY) / 0.3) * alpha
    if skipAlpha <= 0.01 then return end

    local btnX = SKIP_BTN_CX - SKIP_BTN_W * 0.5
    local btnY = SKIP_BTN_CY - SKIP_BTN_H * 0.5

    nvgSave(vg_)

    -- 悬浮动画：让跳过按钮微微上下浮动，吸引注意
    local floatOffset = math.sin(elapsed_ * 3.0) * 6.0

    -- 外发光圈（金色光晕）
    local glowAlpha = math.floor(60 * skipAlpha * (0.5 + 0.5 * math.sin(elapsed_ * 2.0)))
    if glowAlpha > 5 then
        nvgBeginPath(vg_)
        nvgRoundedRect(vg_, btnX - 4, btnY - 4 + floatOffset, SKIP_BTN_W + 8, SKIP_BTN_H + 8, SKIP_BTN_RADIUS + 4)
        nvgFillColor(vg_, nvgRGBA(255, 200, 50, glowAlpha))
        nvgFill(vg_)
    end

    -- 按钮主体填充（金色/橙色）
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, btnX, btnY + floatOffset, SKIP_BTN_W, SKIP_BTN_H, SKIP_BTN_RADIUS)
    nvgFillColor(vg_, nvgRGBA(255, 180, 50, math.floor(210 * skipAlpha)))
    nvgFill(vg_)

    -- 按钮内高光条（高光效果，居中对齐）
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, btnX + 6, btnY + 4 + floatOffset, SKIP_BTN_W - 12, SKIP_BTN_H * 0.45, 10)
    nvgFillColor(vg_, nvgRGBA(255, 220, 120, math.floor(80 * skipAlpha)))
    nvgFill(vg_)

    -- 按钮边框（金色）
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, btnX, btnY + floatOffset, SKIP_BTN_W, SKIP_BTN_H, SKIP_BTN_RADIUS)
    nvgStrokeColor(vg_, nvgRGBA(220, 140, 20, math.floor(200 * skipAlpha)))
    nvgStrokeWidth(vg_, 3)
    nvgStroke(vg_)

    -- 按钮文字（深色，高对比度）
    nvgFontFace(vg_, "sans")
    nvgFontSize(vg_, SKIP_BTN_FONT)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg_, nvgRGBA(60, 30, 0, math.floor(240 * skipAlpha)))
    nvgText(vg_, btnX + SKIP_BTN_W * 0.5 - 20, btnY + SKIP_BTN_H * 0.5 + floatOffset, "跳过", nil)

    -- 右侧小箭头指示
    nvgFontSize(vg_, 36)
    nvgFillColor(vg_, nvgRGBA(60, 30, 0, math.floor(200 * skipAlpha)))
    nvgText(vg_, btnX + SKIP_BTN_W * 0.5 + 100, btnY + SKIP_BTN_H * 0.5 + floatOffset, ">", nil)

    nvgRestore(vg_)
end

--- 绘制引导蒙层（在 NanoVGRender 回调中调用）
--- 应在 ScenarioDialogue.draw() 和 CharacterSelect.draw() 之后调用
function TutorialManager.draw()
    if not activeGroup_ then return end
    -- 情景对话播放时隐藏教程遮罩，避免与对话框同时出现产生冲突
    if ScenarioDialogue.isActive() then return end
    -- 奖励弹窗打开时隐藏教程遮罩，等玩家领完奖励再显示
    local okRP, RewardPopup = pcall(require, "ui.RewardPopup")
    if okRP and RewardPopup.isOpen and RewardPopup.isOpen() then return end

    -- 计算整体透明度（入场/离场动画）
    local alpha = 1.0
    if animState_ == "in" then
        alpha = easeOutCubic(animT_ / ANIM_IN_DUR)
    elseif animState_ == "out" then
        alpha = 1.0 - (animT_ / ANIM_OUT_DUR)
    end
    alpha = math.max(0, math.min(1, alpha))
    if alpha <= 0.01 then return end

    local step = getCurrentStep()
    if not step then return end

    -- invisible 步骤：不绘制蒙层/高亮/气泡，但仍显示跳过按钮（防止卡住）
    if step.invisible then
        drawSkipButton(alpha)
        return
    end

    -- 获取当前步骤的高亮热点
    local hs = hotspots_[step.highlight]

    -- 绘制蒙层（带镂空）
    drawMask(hs, alpha)

    -- 绘制高亮边框闪烁
    if hs then
        drawHighlightBorder(hs, alpha)
    end

    -- 绘制引导气泡
    if step.text then
        drawBubble(step.text, hs, alpha)
    end

    -- 绘制跳过按钮（延迟显示，避免误触）
    drawSkipButton(alpha)
end

return TutorialManager
