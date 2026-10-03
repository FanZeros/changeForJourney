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
local newHeroId_ = nil ---@type number|nil
local restored_ = false
local resumePending_ = false
local lastUnlockState_ = {}
local overlay_ = { w = GameConfig.Design.WIDTH, h = GameConfig.Design.HEIGHT, hs = nil }
local overlayLayout_ = nil ---@type any
local stepElapsed_ = 0

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
    if not activeGroup_ then return end
    completed_[tostring(activeGroup_)] = true
    print("[TutorialManager] 引导完成: " .. activeGroup_)
    animState_, animT_ = "out", 0
    save()
end
local function advance()
    local current = step()
    if not current or animState_ == "out" then return end
    activeStep_, stepElapsed_ = activeStep_ + 1, 0
    overlayLayout_ = nil
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
    activeGroup_, activeStep_ = id, 1
    animState_, animT_, groupElapsed_, stepElapsed_ = "in", 0, 0, 0
    overlayLayout_ = nil
    if id == 1 or id == 2 or id == 6 or id == 9 or id == 15 then resumePending_ = true end
    applyUnlocks(id)
    print("[TutorialManager] 启动引导: " .. id)
    save()
end
function TutorialManager.startGroup(id)
    if isGroupCompleted(id) or activeGroup_ == id then return end
    if activeGroup_ then
        for _, queued in ipairs(queue_) do if queued == id then return end end
        queue_[#queue_ + 1] = id
        save()
    else start(id) end
end
function TutorialManager.onScenarioClaimed(sid)
    local id = Config.SCENARIO_TO_GROUP[sid]
    if id then TutorialManager.startGroup(id) end
end
function TutorialManager.notifyEvent(name)
    if not activeGroup_ or animState_ == "out" then return end
    if name == "gacha10_failed" and activeGroup_ == 8 then
        activeStep_, stepElapsed_ = 1, 0
        overlayLayout_ = nil
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
    return not (RP.isOpen and RP.isOpen())
end
function TutorialManager.setOverlayRect(w, h, hs)
    overlay_ = { w = w, h = h, hs = hs }
    local Overlay = require("ui.tutorial.TutorialOverlay")
    overlayLayout_ = Overlay.layout(w, h, hs)
end
local function hit(rect, x, y)
    return rect and DrawUtil.hitTest(x, y, rect.cx, rect.cy, rect.w, rect.h)
end
function TutorialManager.canPointerStart(x, y)
    if not TutorialManager.isInputActive() then return true end
    if groupElapsed_ >= 1 and overlayLayout_ and hit(overlayLayout_.skip, x, y) then return false end
    local current = step()
    if not current or current.invisible or current.advanceOn ~= "click_highlight" then return true end
    -- 真正按钮边界才放行；光环外扩不是按钮可点击区域。
    return hit(overlay_.hs, x, y) == true
end
function TutorialManager.handleScreenClick(x, y)
    if not TutorialManager.isInputActive() then return false end
    if groupElapsed_ >= 1 and overlayLayout_ and hit(overlayLayout_.skip, x, y) then
        finish()
        return true
    end
    local current = step()
    if not current or current.invisible then return false end
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
    animState_, animT_, groupElapsed_, stepElapsed_ = "idle", 0, 0, 0
    overlayLayout_, restored_, resumePending_ = nil, false, false
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
local function prepareResume()
    if not resumePending_ then return end
    resumePending_ = false
    if activeGroup_ == 1 or activeGroup_ == 2 or activeGroup_ == 9 then
        require("ui.character.detail.CharacterDetail").forceClose()
        local panel = require("ui.character.panel.CharacterPanel")
        if panel.prepareTutorial then panel.prepareTutorial(newHeroId_) end
    elseif activeGroup_ == 5 or activeGroup_ == 6 or activeGroup_ == 7 or activeGroup_ == 10 then
        require("ui.church.ChurchPage").forceClose()
        local page = require("ui.church.talent.TalentPage")
        if page.forceClose then page.forceClose() end
    elseif activeGroup_ == 15 then
        -- 横屏常驻布局隐藏旧副本页签，恢复/启动时直接打开合法副本面板入口。
        require("ui.hud.BottomNav").setSelectedIndex(5)
        activeStep_ = math.max(2, activeStep_)
        save()
    elseif activeGroup_ == 8 then
        require("ui.tavern.TavernPage").open()
    elseif activeGroup_ == 11 then
        require("ui.blacksmith.BlacksmithPage").open()
    end
end
function TutorialManager.update(dt)
    elapsed_ = elapsed_ + dt
    if not restored_ then restore() end
    if not activeGroup_ then
        if #queue_ > 0 and not Scenario.isActive() then start(table.remove(queue_, 1)) end
        return
    end
    if TutorialManager.isInputActive() then
        groupElapsed_, stepElapsed_ = groupElapsed_ + dt, stepElapsed_ + dt
        prepareResume()
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
    local hs = current.invisible and nil or overlay_.hs
    overlayLayout_ = Overlay.draw(vg_, overlay_.w, overlay_.h, hs, text, elapsed_, groupElapsed_, alpha,
        current.invisible == true, activeGroup_ == 9)
end
return TutorialManager
