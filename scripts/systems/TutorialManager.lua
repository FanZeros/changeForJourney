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
local newHeroId_ = nil ---@type number|nil
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

local function resetTarget()
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
    completed_[tostring(finishedGroup)] = true
    print("[TutorialManager] 引导完成: " .. finishedGroup)
    animState_, animT_, triggerQuiet_ = "out", 0, 0
    save()
    if finishedGroup == 6 then
        -- 古树教学已自动收起教堂；完成后接离场对话，再触发酒馆教学，避免丢失入口。
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
function TutorialManager.getProgress() return snapshot() end
function TutorialManager.clearHotspots() hotspots_ = {} end
function TutorialManager.registerHotspot(key, cx, cy, w, h, panel)
    if w <= 0 or h <= 0 then return end
    hotspots_[key] = { cx = cx, cy = cy, w = w, h = h,
        panel = (panel == "left" or panel == "right" or panel == "modal") and panel or "center" }
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
    return newHeroId_ and roster and (roster[newHeroId_] or roster[tostring(newHeroId_)]) ~= nil
end
local function start(id)
    if isGroupCompleted(id) then return end
    if id == 9 and not validNewHero() then
        -- 全重复招募/旧档无目标时，不要求玩家拖一个不存在的角色。
        completed_[tostring(id)] = true
        print("[TutorialManager] 无新增角色，略过上阵教学")
        save()
        return
    end
    if id == 9 and validNewHero() then
        local panel = require("ui.character.panel.CharacterPanel")
        local layout = panel.getTeamSlotLayout and panel.getTeamSlotLayout(1)
        if layout and tonumber(layout[3]) == newHeroId_ then
            completed_["9"] = true
            print("[TutorialManager] 新角色已在队一槽位3，免重复上阵教学")
            save()
            return
        end
    end
    activeGroup_, activeStep_ = id, 1
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
    else start(id) end
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
    return activeGroup_ == nil or animState_ == "out"
end
function TutorialManager.notifyEvent(name)
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
                print("[TutorialManager] 待触发阶段已完成真实十连，免重复教学")
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
    if current and current.advanceOn == name then advance() end
end
function TutorialManager.skipCurrentGroup() finish() end

-- 当前覆盖层被更高优先级窗口挡住时，输入同样让位，不能只隐藏绘制。
function TutorialManager.isInputActive()
    if not activeGroup_ or animState_ == "out" or Scenario.isActive() then return false end
    local RP = require("ui.hud.popup.RewardPopup")
    if RP.isOpen and RP.isOpen() then return false end
    return not require("ui.tutorial.TutorialPageRecovery").isBlocked()
end
function TutorialManager.setOverlayRect(w, h, hs)
    local target = hs
    if settleRemaining_ > 0 then target = nil end
    overlay_ = { w = w, h = h, hs = target }
    local Overlay = require("ui.tutorial.TutorialOverlay")
    overlayLayout_ = Overlay.layout(w, h, target)
end
local function hit(rect, x, y)
    return rect and DrawUtil.hitTest(x, y, rect.cx, rect.cy, rect.w, rect.h)
end
function TutorialManager.canPointerStart(x, y)
    if not TutorialManager.isInputActive() then return true end
    if groupElapsed_ >= 1 and overlayLayout_ and hit(overlayLayout_.skip, x, y) then return false end
    if prepareResume then prepareResume() end
    if settleRemaining_ > 0 then return false end
    local current = step()
    if not current or current.invisible or current.advanceOn ~= "click_highlight" then return true end
    -- 真正按钮边界才放行；光环外扩不是按钮可点击区域。
    return hit(overlay_.hs, x, y) == true
end
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
    if current.advanceOn == "click_highlight" then
        if hit(overlay_.hs, x, y) then advance(); return false end
        return true
    end
    return false
end
-- 兼容面板设计坐标入口，横屏宿主使用 handleScreenClick。
function TutorialManager.handleClick(x, y, pid)
    if not TutorialManager.isInputActive() then return false end
    local current = step()
    local hs = TutorialManager.getCurrentHotspot()
    if current and current.advanceOn == "click_highlight" and hs and pid and pid ~= hs.panel then return true end
    if current and current.advanceOn == "click_highlight" then
        if hit(hs, x, y) then advance(); return false end
        return true
    end
    return false
end

function TutorialManager.init(vg, playerStore, persist)
    vg_, store_, persist_ = vg, playerStore, persist
    activeGroup_, activeStep_, newHeroId_ = nil, 1, nil
    completed_, queue_, hotspots_, lastUnlockState_ = {}, {}, {}, {}
    queuedRecruitStarted_ = false
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
            start(id)
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
    if Recovery.isBlocked() then return end
    local initial = resumePending_
    resumePending_, recoveryElapsed_ = false, 0
    if activeGroup_ == 15 and activeStep_ == 1 then
        -- 横屏已移除旧页签，沿用直接打开副本列表的恢复契约。
        activeStep_, stepElapsed_ = 2, 0
        current = step()
        save()
    end
    if current and Recovery.prepare(vg_, store_, current.highlight, newHeroId_, initial) then
        settleRemaining_, missingElapsed_ = PAGE_SETTLE_TIME, 0
        hotspots_, overlay_.hs, overlayLayout_ = {}, nil, nil
    end
end
function TutorialManager.update(dt)
    elapsed_ = elapsed_ + dt
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
                start(table.remove(queue_, 1))
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
