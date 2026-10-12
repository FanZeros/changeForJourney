-- 新手引导：流程与真实动作完成解耦，热点保留面板坐标，横屏覆盖层使用屏幕逻辑坐标。
local Config = require("config.TutorialConfig")
local DrawUtil = require("core.DrawUtil")
local GameConfig = require("config.GameConfig")
local Scenario = require("ui.story.ScenarioDialogue")
local TutorialManager = {}

---@type any
local vg_ = nil
---@type any
local store_ = nil
---@type function|nil
local persist_ = nil
local activeGroup_ = nil ---@type number|nil
local activeStep_ = 1
local elapsed_, groupElapsed_, animT_ = 0, 0, 0
local animState_ = "idle"
local hotspots_ = {}
local completed_ = {}
local queue_ = {}
local queuedRecruitStarted_ = false
local recruitCount_ = nil ---@type number|nil
local newHeroId_ = nil ---@type number|nil
local equipmentHeroId_ = nil ---@type number|nil
local detailEntryPress_ = nil ---@type any
local restored_ = false
local resumePending_ = false
local lastUnlockState_ = {}
local overlay_ = { w = GameConfig.Design.WIDTH, h = GameConfig.Design.HEIGHT, hs = nil }
local overlayLayout_ = nil ---@type any
local stepElapsed_ = 0
local recoveryElapsed_, settleRemaining_, missingElapsed_ = 0, 0, 0
local RECOVERY_INTERVAL, PAGE_SETTLE_TIME = 0.5, 0.45
local triggerQuiet_ = 0
local TRIGGER_QUIET_TIME = 0.25
---@type fun()?
local prepareResume

local function invalidateDetailEntryPress()
    if detailEntryPress_ then detailEntryPress_.invalid = true end
    detailEntryPress_ = nil
end
local function resetTarget()
    invalidateDetailEntryPress()
    resumePending_ = true
    recoveryElapsed_, settleRemaining_, missingElapsed_ = 0, 0, 0
    overlayLayout_, overlay_.hs = nil, nil
end

local function step()
    local group = activeGroup_ and Config[activeGroup_]
    return group and group.steps and group.steps[activeStep_]
end
local function snapshot()
    local done, pending = {}, {}
    for k, v in pairs(completed_) do done[tostring(k)] = v end
    for i, v in ipairs(queue_) do pending[i] = v end
    return { version = 1, completed = done, queue = pending,
        group = activeGroup_, step = activeStep_, newHeroId = newHeroId_ }
end
local function save()
    if persist_ then persist_(snapshot()) end
end
local function claimed(sid)
    local session = store_ and store_.Get("session")
    local claims = session and session.claimedScenarios
    return claims and (claims[sid] == true or claims[tostring(sid)] == true) or false
end
local function isGroupCompleted(id)
    return completed_[tostring(id)] == true or not Config[id] or Config[id].disabled == true
end
local function applyUnlocks(id)
    local group = Config[id]
    if not group or not group.unlocks then return end
    local BN = require("ui.hud.BottomNav")
    local tabs = { character_panel = 1, town_panel = 4, dungeon_panel = 5 }
    for _, key in ipairs(group.unlocks) do
        if tabs[key] then BN.setTabLocked(tabs[key], false) end
    end
end
local function finish()
    if not activeGroup_ or animState_ == "out" then return end
    local finishedGroup = activeGroup_
    invalidateDetailEntryPress()
    completed_[tostring(finishedGroup)] = true
    print("[TutorialManager] 引导完成: " .. finishedGroup)
    animState_, animT_, triggerQuiet_ = "out", 0, 0
    save()
    if finishedGroup == 6 then
        local talent = require("ui.church.talent.TalentPage")
        if talent.isOpen() then talent.close() end
        -- 收起本组目标页，再排离场对话，避免宽页挡住待展示奖励。
        require("systems.StoryPlayer").onPlace("church", "leave")
    end
end
local function advance()
    local current = step()
    if not current or animState_ == "out" then return end
    activeStep_, stepElapsed_ = activeStep_ + 1, 0
    resetTarget()
    if not step() then finish()
    else print("[TutorialManager] 步骤: " .. activeGroup_ .. "/" .. activeStep_); save() end
end

function TutorialManager.getPreferredCharacterTab()
    if activeGroup_ == 1 or activeGroup_ == 2 then return "equip" end
    return nil
end
function TutorialManager.getCurrentGroup() return activeGroup_ end
function TutorialManager.getCurrentHighlight()
    local current = step()
    return current and current.highlight or nil
end
function TutorialManager.isActive() return activeGroup_ ~= nil end
function TutorialManager.isGroupCompleted(id) return isGroupCompleted(id) end
function TutorialManager.setNewHeroId(id)
    newHeroId_ = tonumber(id)
    save()
end
function TutorialManager.getNewHeroId() return newHeroId_ end
function TutorialManager.getEquipmentHeroId() return equipmentHeroId_ end
function TutorialManager.getProgress() return snapshot() end
function TutorialManager.clearHotspots() hotspots_ = {} end
--- spotlight 仅控制视觉开洞，点击继续仍使用 cx/cy/w/h。
---@param spotlight? TutorialOverlayRect
function TutorialManager.registerHotspot(key, cx, cy, w, h, panel, spotlight)
    if w <= 0 or h <= 0 then return end
    hotspots_[key] = { cx = cx, cy = cy, w = w, h = h, spotlight = spotlight,
        panel = (panel == "left" or panel == "right" or panel == "modal" or panel == "tri_modal"
            or panel == "screen") and panel or "center" }
end
--- 入口目标携带真实英雄，后续配装不再按名册排序或默认槽位换人。
function TutorialManager.registerCharacterDetailHotspot(key, heroId, cx, cy, w, h, panel)
    local current = step()
    local id = tonumber(heroId)
    if not current or current.highlight ~= key or not current.entrySource or not id or id <= 0
        or w <= 0 or h <= 0 then return end
    TutorialManager.registerHotspot(key, cx, cy, w, h, panel)
    hotspots_[key].heroId = id
end
function TutorialManager.notifyCharacterDetailOpened(source, heroId)
    local current = step()
    local hs = current and hotspots_[current.highlight]
    local id = tonumber(heroId)
    if not current or not id or id <= 0 or animState_ == "out" or current.entrySource ~= source
        or current.advanceOn ~= "character_detail_opened" or not hs or hs.heroId ~= id
        or settleRemaining_ > 0 then return false end
    if detailEntryPress_ and (detailEntryPress_.invalid or detailEntryPress_.heroId ~= id
        or detailEntryPress_.source ~= source) then return false end
    local detail = require("ui.character.detail.CharacterDetail")
    if not detail.isOpen() or tonumber(detail.getHeroId()) ~= id or not detail.isEquipTab() then return false end
    equipmentHeroId_ = id
    print("[TutorialManager] 详情入口完成: " .. source .. " hero=" .. id)
    advance()
    return true
end
function TutorialManager.getCurrentHotspot()
    local current = step()
    return current and current.highlight and hotspots_[current.highlight] or nil
end
function TutorialManager.getHotspotPanel()
    local hs = TutorialManager.getCurrentHotspot()
    return hs and hs.panel or "center"
end

local function validNewHero()
    local heroes = store_ and store_.Get("heroes")
    local roster = heroes and heroes.roster
    local hero = newHeroId_ and roster and (roster[newHeroId_] or roster[tostring(newHeroId_)])
    if hero and tonumber(hero.level) and tonumber(hero.level) > 0 then return true end
    local panel = require("ui.character.panel.CharacterPanel")
    return newHeroId_ ~= nil and panel.isOwned and panel.isOwned(newHeroId_) == true
end
local function start(id)
    if isGroupCompleted(id) then return end
    if id == 9 then
        local panel = require("ui.character.panel.CharacterPanel")
        -- 冷启动默认槽位仍是 locked；等真实英雄/阵容同步，不把未就绪当已满编。
        if panel.isHeroesDataApplied and not panel.isHeroesDataApplied() then return false end
        local slots = panel.getTeamSlotsData and panel.getTeamSlotsData(1)
        local target = slots and slots[4]
        local reason = nil ---@type string|nil
        if not validNewHero() then
            reason = "无新增角色"
        else
            for teamIdx = 1, 3 do
                local layout = panel.getTeamSlotLayout and panel.getTeamSlotLayout(teamIdx)
                for _, heroId in ipairs(layout or {}) do
                    if tonumber(heroId) == newHeroId_ then reason = "目标角色已上阵"; break end
                end
                if reason then break end
            end
            if not reason and (not target or target.state ~= "empty") then
                reason = "小队1槽位4已占用或未解锁，保留现有阵容"
            end
        end
        if reason then
            completed_["9"] = true
            print("[TutorialManager] " .. reason .. "，略过上阵教学")
            save()
            return
        end
    end
    activeGroup_, activeStep_, equipmentHeroId_ = id, 1, nil
    animState_, animT_, groupElapsed_, stepElapsed_ = "in", 0, 0, 0
    resetTarget()
    applyUnlocks(id)
    print("[TutorialManager] 启动引导: " .. id)
    save()
end
local function queueGroup(id)
    if isGroupCompleted(id) or activeGroup_ == id then return end
    for _, queued in ipairs(queue_) do if queued == id then return end end
    queue_[#queue_ + 1] = id
    triggerQuiet_ = 0
    save()
end
function TutorialManager.startGroup(id)
    if isGroupCompleted(id) or activeGroup_ == id then return end
    if activeGroup_ then queueGroup(id)
    elseif start(id) == false then queueGroup(id) end
end
function TutorialManager.onScenarioClaimed(sid)
    if sid == 23 then
        local follow = require("systems.StoryPlayer").followOf(sid)
        -- 城镇23尚有本角色分支对话时，等24/25/26真实播完领奖；旧档已播仍兼容。
        if follow and not claimed(follow) then return end
    end
    local id = Config.SCENARIO_TO_GROUP[sid]
    if id then queueGroup(id) end
end

--- 未消费的新剧情不能抢正在进行的操作教学；组结束后按原队列继续。
function TutorialManager.canPlayPendingStory()
    return activeGroup_ == nil and #queue_ == 0
end
function TutorialManager.notifyEvent(name)
    if name == "gacha10_started" or name == "gacha_started" then
        recruitCount_ = name == "gacha10_started" and 10 or 1
        if not isGroupCompleted(9) and activeGroup_ ~= 9 then
            local deployQueued = false
            for _, id in ipairs(queue_) do if id == 9 then deployQueued = true; break end end
            if not deployQueued then newHeroId_ = nil; save() end
        end
    elseif name == "gacha10_failed" or name == "gacha_failed" then
        recruitCount_ = nil
    end
    -- 首次单抽也算已学会招募，不要求额外消费十连。
    if name == "gacha_started" then name = "gacha10_started"
    elseif name == "gacha_failed" then name = "gacha10_failed" end
    if activeGroup_ ~= 8 then
        local queuedRecruit = false
        for _, id in ipairs(queue_) do if id == 8 then queuedRecruit = true; break end end
        if queuedRecruit then
            if name == "gacha10_started" then queuedRecruitStarted_ = true
            elseif name == "gacha10_failed" then queuedRecruitStarted_ = false
            elseif name == "gacha10_complete" and queuedRecruitStarted_ then
                queuedRecruitStarted_ = false
                completed_["8"] = true
                for i = #queue_, 1, -1 do if queue_[i] == 8 then table.remove(queue_, i) end end
                print("[TutorialManager] 待触发阶段已完成真实招募，免重复教学")
                save()
            end
        end
    end
    if not activeGroup_ or animState_ == "out" then return end
    if name == "gacha10_failed" and activeGroup_ == 8 then
        activeStep_, stepElapsed_ = 1, 0
        resetTarget()
        save()
        print("[TutorialManager] 招募未完成，恢复可重试步骤")
        return
    end
    local current = step()
    if current and not current.entrySource and current.advanceOn == name then advance() end
end
--- 仅消费本次真实招募；先排教程，再让招募动画关闭回调中的闲聊参与仲裁。
function TutorialManager.onRecruitCompleted(results, count)
    if recruitCount_ == nil or recruitCount_ ~= count or type(results) ~= "table" or #results == 0 then
        return false
    end
    recruitCount_, queuedRecruitStarted_ = nil, false
    -- 完成组8与选择新增英雄/排组9一次保存，避免持久化回调观察到不完整的后续教学状态。
    completed_["8"] = true
    for i = #queue_, 1, -1 do if queue_[i] == 8 then table.remove(queue_, i) end end
    if activeGroup_ == 8 then
        activeStep_, stepElapsed_ = #Config[8].steps + 1, 0
        animState_, animT_, triggerQuiet_ = "out", 0, 0
        resetTarget()
        print("[TutorialManager] 引导完成: 8")
    end
    if isGroupCompleted(9) or activeGroup_ == 9 then save(); return true end
    for _, id in ipairs(queue_) do if id == 9 then save(); return true end end
    newHeroId_ = nil
    for _, result in ipairs(results) do
        local heroId = tonumber(result.heroId)
        if result.type == "hero" and result.isNew == true and heroId and heroId > 0 then
            newHeroId_ = heroId
            break
        end
    end
    if newHeroId_ then
        print("[TutorialManager] 首次招募新增角色=" .. newHeroId_ .. "，排入槽位4上阵教学")
        queueGroup(9)
    else
        completed_["9"] = true
        print("[TutorialManager] 本次招募无新增角色，略过上阵教学")
        save()
    end
    return true
end

--- 编队提交/回滚后读回真实布局；错误槽、错误队和未成功提交都不算完成。
function TutorialManager.notifyHeroDeployed(heroId, teamIdx, slotIdx)
    if activeGroup_ ~= 9 or animState_ == "out" or tonumber(heroId) ~= newHeroId_
        or teamIdx ~= 1 or slotIdx ~= 4 then return false end
    local layout = require("ui.character.panel.CharacterPanel").getTeamSlotLayout(1)
    if not layout or tonumber(layout[4]) ~= newHeroId_ then return false end
    TutorialManager.notifyEvent("drag_to_slot_4")
    return true
end
function TutorialManager.skipCurrentGroup() finish() end

-- 当前覆盖层被更高优先级窗口挡住时，输入同样让位，不能只隐藏绘制。
function TutorialManager.isInputActive()
    if not activeGroup_ or animState_ == "out" or Scenario.isActive() then return false end
    local RP = require("ui.hud.popup.RewardPopup")
    if RP.isOpen and RP.isOpen() then return false end
    local current = step()
    return not require("ui.tutorial.TutorialPageRecovery").isBlocked(current and current.highlight)
end
function TutorialManager.setOverlayRect(w, h, hs)
    local target = hs
    if settleRemaining_ > 0 then target = nil end
    overlay_ = { w = w, h = h, hs = target }
    if detailEntryPress_ then
        local current = step()
        local hsNow = TutorialManager.getCurrentHotspot()
        if not target or not current or not hsNow or hsNow.heroId ~= detailEntryPress_.heroId
            or hsNow.panel ~= detailEntryPress_.panel or current.highlight ~= detailEntryPress_.key
            or current.entrySource ~= detailEntryPress_.source then
            invalidateDetailEntryPress()
        end
    end
    local Overlay = require("ui.tutorial.TutorialOverlay")
    overlayLayout_ = Overlay.layout(w, h, target)
end
local function hit(rect, x, y)
    return rect and DrawUtil.hitTest(x, y, rect.cx, rect.cy, rect.w, rect.h)
end
function TutorialManager.canPointerStart(x, y, button)
    if not TutorialManager.isInputActive() then return true end
    local current = step()
    -- 入口教学只接受左键/触摸；其它步骤仍保留右键快捷穿戴。
    if current and current.entrySource and button and button ~= MOUSEB_LEFT then return false end
    if groupElapsed_ >= 1 and overlayLayout_ and hit(overlayLayout_.skip, x, y) then return false end
    if prepareResume then prepareResume() end
    if settleRemaining_ > 0 then return false end
    current = step()
    if not current or current.invisible then return true end
    if current.advanceOn ~= "click_highlight" and not current.pointerTarget then return true end
    -- 真正按钮边界才放行；光环外扩不是按钮可点击区域。
    return hit(overlay_.hs, x, y) == true
end
-- 只为详情入口保存按下身份；逐帧热点重建不是新的手势。
function TutorialManager.beginDetailEntryPress()
    invalidateDetailEntryPress()
    local current = step()
    local hs = TutorialManager.getCurrentHotspot()
    if not current or not current.entrySource or not hs or not hs.heroId then return nil end
    detailEntryPress_ = { group = activeGroup_, step = activeStep_, key = current.highlight,
        source = current.entrySource, heroId = hs.heroId, panel = hs.panel, invalid = false }
    return detailEntryPress_
end
function TutorialManager.isDetailEntryPressValid(press)
    if not press then return true end
    local current = step()
    local hs = TutorialManager.getCurrentHotspot()
    return not press.invalid and press == detailEntryPress_ and TutorialManager.isInputActive()
        and current ~= nil and hs ~= nil and overlay_.hs ~= nil and settleRemaining_ == 0
        and activeGroup_ == press.group and activeStep_ == press.step
        and current.highlight == press.key and current.entrySource == press.source
        and hs.heroId == press.heroId and hs.panel == press.panel
end
function TutorialManager.cancelDetailEntryPress() invalidateDetailEntryPress() end
function TutorialManager.handleScreenClick(x, y, blockedPress)
    if not TutorialManager.isInputActive() then return false end
    if groupElapsed_ >= 1 and overlayLayout_ and hit(overlayLayout_.skip, x, y) then
        finish()
        return true
    end
    if blockedPress then return true end
    local current = step()
    if not current or current.invisible then return false end
    if settleRemaining_ > 0 then return true end
    if current.advanceOn == "click_highlight" or current.pointerTarget then
        if hit(overlay_.hs, x, y) then
            if current.advanceOn == "click_highlight" then advance() end
            return false
        end
        return true
    end
    return false
end
-- 兼容面板设计坐标入口，横屏宿主使用 handleScreenClick。
function TutorialManager.handleClick(x, y, pid)
    if not TutorialManager.isInputActive() then return false end
    local current = step()
    local hs = TutorialManager.getCurrentHotspot()
    local targeted = current and (current.advanceOn == "click_highlight" or current.pointerTarget)
    if targeted and hs and pid and pid ~= hs.panel then return true end
    if targeted then
        if hit(hs, x, y) then
            if current.advanceOn == "click_highlight" then advance() end
            return false
        end
        return true
    end
    return false
end

function TutorialManager.init(vg, playerStore, persist)
    vg_, store_, persist_ = vg, playerStore, persist
    invalidateDetailEntryPress()
    activeGroup_, activeStep_, newHeroId_, equipmentHeroId_ = nil, 1, nil, nil
    completed_, queue_, hotspots_, lastUnlockState_ = {}, {}, {}, {}
    queuedRecruitStarted_, recruitCount_ = false, nil
    animState_, animT_, groupElapsed_, stepElapsed_ = "idle", 0, 0, 0
    overlayLayout_, restored_, resumePending_ = nil, false, false
    overlay_.hs = nil
    recoveryElapsed_, settleRemaining_, missingElapsed_, triggerQuiet_ = 0, 0, 0, 0
    print("[TutorialManager] 初始化，等待会话数据恢复")
end
local function restore()
    if activeGroup_ then restored_ = true; return end
    local session = store_ and store_.Get("session")
    if not session then return end
    restored_ = true
    local progress = session.tutorialProgress
    if type(progress) == "table" and progress.version == 1 then
        for k, v in pairs(progress.completed or {}) do completed_[tostring(k)] = v == true end
        for _, id in ipairs(progress.queue or {}) do if Config[id] then queue_[#queue_ + 1] = id end end
        newHeroId_ = tonumber(progress.newHeroId)
        local id = tonumber(progress.group)
        if completed_["6"] and not isGroupCompleted(7) then
            -- 上次完成古树后可能尚未来得及消费内存离场剧情；去重补回，不重复发奖。
            require("systems.StoryPlayer").onPlace("church", "leave")
        end
        if id and not isGroupCompleted(id) then
            -- 重启后目标页面已关闭，重新走本组入口；不重播剧情或重复发奖励。
            if start(id) == false then
                -- 原正在执行的组优先于旧待启动队列，冷恢复不能把它追加到队尾。
                for i = #queue_, 1, -1 do if queue_[i] == id then table.remove(queue_, i) end end
                table.insert(queue_, 1, id)
                save()
            end
            resumePending_ = true
        end
    else
        -- 旧存档迁移：已有剧情视为历史完成；首轮装备教学没有武器时补回，避免旧断线永久丢失。
        for id, group in pairs(Config) do
            if type(id) == "number" and group.triggerScenarios then
                for _, sid in ipairs(group.triggerScenarios) do
                    if claimed(sid) then completed_[tostring(id)] = true; break end
                end
            end
        end
        local equipment = store_.Get("equipment")
        local hasWeapon = false
        for _, slots in pairs(equipment and equipment.equipped or {}) do
            if type(slots) == "table" and slots.weapon then hasWeapon = true end
        end
        if completed_["1"] and not hasWeapon then
            completed_["1"] = nil
            start(1)
            resumePending_ = true
        end
        save()
    end
end
prepareResume = function()
    local current = step()
    if not current or current.invisible then resumePending_ = false; return end
    local Recovery = require("ui.tutorial.TutorialPageRecovery")
    if Recovery.isBlocked(current.highlight) then return end
    local initial = resumePending_
    resumePending_, recoveryElapsed_ = false, 0
    if activeGroup_ == 15 and activeStep_ == 1 then
        -- 横屏已移除旧页签，沿用直接打开副本列表的恢复契约。
        activeStep_, stepElapsed_ = 2, 0
        current = step()
        save()
    end
    if activeGroup_ == 15 and current and current.highlight == "dungeon_gold_mine" then
        -- 旧档已在金币任务时只补完成状态，不回退关卡、不重新入场或领奖。
        local stageId = require("ui.battle.tri.BattleTriPage").getTeamStageId(1)
        if stageId and require("config.DungeonConfig").decodeStageId(stageId) == "gold_mine" then
            print("[TutorialManager] 小队1已进入黄金矿洞，补齐副本引导完成状态")
            TutorialManager.notifyEvent("enter_gold_mine")
            return
        end
    end
    if current and Recovery.prepare(vg_, store_, current.highlight, newHeroId_, initial, equipmentHeroId_) then
        settleRemaining_, missingElapsed_ = PAGE_SETTLE_TIME, 0
        hotspots_, overlay_.hs, overlayLayout_ = {}, nil, nil
    end
end
function TutorialManager.update(dt)
    elapsed_ = elapsed_ + dt
    if detailEntryPress_ and not TutorialManager.isInputActive() then invalidateDetailEntryPress() end
    if not restored_ then restore() end
    if not activeGroup_ then
        local Recovery = require("ui.tutorial.TutorialPageRecovery")
        local reward = require("ui.hud.popup.RewardPopup")
        local tavern = require("ui.tavern.TavernPage")
        local blocked = Scenario.isActive() or reward.isOpen() or Recovery.isBlocked()
            or (tavern.isRecruitBusy and tavern.isRecruitBusy())
        if #queue_ == 0 or blocked then triggerQuiet_ = 0
        else
            triggerQuiet_ = triggerQuiet_ + dt
            if triggerQuiet_ >= TRIGGER_QUIET_TIME then
                triggerQuiet_ = 0
                local id = table.remove(queue_, 1)
                if start(id) == false then table.insert(queue_, 1, id) end
            end
        end
        return
    end
    if TutorialManager.isInputActive() then
        groupElapsed_, stepElapsed_ = groupElapsed_ + dt, stepElapsed_ + dt
        recoveryElapsed_ = recoveryElapsed_ + dt
        settleRemaining_ = math.max(0, settleRemaining_ - dt)
        if overlay_.hs and settleRemaining_ == 0 then missingElapsed_ = 0
        else missingElapsed_ = missingElapsed_ + dt end
        if resumePending_ or recoveryElapsed_ >= RECOVERY_INTERVAL then prepareResume() end
    end
    if activeGroup_ == 8 and step() and step().invisible and stepElapsed_ > 12 then
        TutorialManager.notifyEvent("gacha10_failed")
    end
    if animState_ ~= "idle" then
        animT_ = animT_ + dt
        local duration = animState_ == "in" and 0.25 or 0.2
        if animT_ >= duration then
            if animState_ == "out" then
                activeGroup_, activeStep_, animState_, animT_ = nil, 1, "idle", 0
                save()
            else animState_, animT_ = "idle", 0 end
        end
    end
end

local PANEL_UNLOCK_THRESHOLDS = { character_panel = 101, town_panel = 105 }
local BUILDING_UNLOCK_THRESHOLDS = { smith = 204 }
local function unlocked(key, thresholds, default)
    local threshold = thresholds[key]
    if not threshold then return default end
    local battle = store_ and store_.Get("battle")
    if not battle then return false end
    local maxStage = tonumber(battle.maxStageId) or 0
    local cleared = battle.clearedStages or {}
    local result = maxStage > threshold or cleared[threshold] == true or cleared[tostring(threshold)] == true
    if lastUnlockState_[key] ~= result then
        lastUnlockState_[key] = result
        print("[TutorialManager] 解锁 " .. key .. "=" .. tostring(result))
    end
    return result
end
function TutorialManager.getBuildingUnlockStageId(key) return BUILDING_UNLOCK_THRESHOLDS[key] end
function TutorialManager.isBuildingUnlocked(key) return unlocked(key, BUILDING_UNLOCK_THRESHOLDS, true) end
function TutorialManager.isPanelUnlocked(key) return unlocked(key, PANEL_UNLOCK_THRESHOLDS, false) end
function TutorialManager.draw()
    if not TutorialManager.isInputActive() then return end
    local current = step()
    if not current then return end
    local Overlay = require("ui.tutorial.TutorialOverlay")
    local alpha = animState_ == "in" and math.min(1, animT_ / 0.25) or 1
    local text = current.invisible and "" or current.text
    if not current.invisible and not overlay_.hs and missingElapsed_ < 2 then
        text = "正在准备引导页面，请稍候…"
    end
    local hs = current.invisible and nil or overlay_.hs
    overlayLayout_ = Overlay.draw(vg_, overlay_.w, overlay_.h, hs, text, elapsed_, groupElapsed_, alpha,
        current.invisible == true, activeGroup_ == 9, missingElapsed_ < 2)
end
return TutorialManager
