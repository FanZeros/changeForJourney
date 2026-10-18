-- 引导页面恢复只整理视图，不发穿戴/招募/领奖操作，不修改剧情或奖励账本。
local M = {}
local LEFT_PAGES = {
    "ui.church.ChurchPage", "ui.church.talent.TalentPage", "ui.tavern.TavernPage",
    "ui.market.MarketPage", "ui.loot.LootBoxPage", "ui.story.task.TaskPage",
    "ui.blacksmith.BlacksmithPage", "ui.backpack.BackpackPanel",
}
local TOWN_TARGETS = {
    town_overview = true, building_church = true, talent_toggle = true,
    building_tavern = true, building_smith = true,
}

local RESTORABLE_TARGETS = {
    battle_hero_detail = true, character_slot_1 = true, character_new_hero = true,
    equip_slot_weapon = true, equip_btn_auto = true, equip_item_gifted = true,
    talent_node_area = true, tavern_btn_gacha10 = true, smith_btn_enhance = true,
    tab_dungeon = true, dungeon_gold_mine = true,
}

function M.canRestoreTarget(target)
    return TOWN_TARGETS[target] == true or RESTORABLE_TARGETS[target] == true
end

local function page(path)
    return require(path)
end
local function isOpen(p)
    return p.isOpen and p.isOpen() == true
end
local function isClosing(p)
    -- 锻炉滑入有错峰延迟，不能用未来openTime与closeTime比较推断真实关闭状态。
    if p.isClosing then return p.isClosing() == true end
    if not p.getSeamAnim then return false end
    local opened, closed = p.getSeamAnim()
    return type(closed) == "number" and closed > 0
        and type(opened) == "number" and closed >= opened
end
local function close(p)
    if not isOpen(p) then return false end
    if p.forceClose then p.forceClose()
    elseif p.close then p.close() end
    return true
end
local function closeLeft(keep)
    local changed = false
    -- 先释放锻炉持有，再关闭仓库，避免release把手动仓库视图恢复到上层。
    for _, path in ipairs(LEFT_PAGES) do
        if not keep[path] then changed = close(page(path)) or changed end
    end
    return changed
end
local function firstHero(store)
    local panel = page("ui.character.panel.CharacterPanel")
    local slots = panel.getTeamSlotsData and panel.getTeamSlotsData(1)
    for _, slot in ipairs(slots or {}) do
        if slot.state == "occupied" and slot.heroId then return tonumber(slot.heroId) end
    end
    local heroes = store and store.Get("heroes")
    local deployed = heroes and heroes.deployed
    return deployed and tonumber(deployed[1]) or nil
end
local function detailClosed()
    return close(page("ui.character.detail.CharacterDetail"))
end
local function prepareRoster(heroId, initial, force)
    local panel = page("ui.character.panel.CharacterPanel")
    local wrongTeam = panel.getActiveTeamIdx and panel.getActiveTeamIdx() ~= 1
    if (initial or wrongTeam or force) and panel.prepareTutorial then
        return panel.prepareTutorial(heroId) == true
    end
    return false
end
local function ownedHero(store, heroId)
    if not heroId then return false end
    local panel = page("ui.character.panel.CharacterPanel")
    if panel.getOwnedHero then return panel.getOwnedHero(heroId) ~= nil end
    local heroes = store and store.Get("heroes")
    local hero = heroes and heroes.roster and (heroes.roster[heroId] or heroes.roster[tostring(heroId)])
    return type(hero) == "table" and (tonumber(hero.level) or 0) > 0
end

local function pageReady(p)
    if not isOpen(p) or isClosing(p) then return false end
    if p.getSeamAnim then
        local opened, _, duration = p.getSeamAnim()
        if type(opened) == "number" and type(duration) == "number"
            and time.elapsedTime < opened + duration then return false end
    end
    return true
end

--- 热点还必须等真实滑入完成；锻炉错峰时间来自页面，不猜固定等待长度。
function M.isTargetReady(target)
    if target == "equip_slot_weapon" or target == "equip_btn_auto" or target == "equip_item_gifted" then
        local detail = page("ui.character.detail.CharacterDetail")
        if not pageReady(detail) or not detail.isEquipTab or not detail.isEquipTab() then return false end
        return target ~= "equip_item_gifted" or pageReady(page("ui.backpack.BackpackPanel"))
    elseif target == "talent_node_area" then
        return pageReady(page("ui.church.talent.TalentPage"))
    elseif target == "tavern_btn_gacha10" then
        return pageReady(page("ui.tavern.TavernPage"))
    elseif target == "smith_btn_enhance" then
        return pageReady(page("ui.blacksmith.BlacksmithPage"))
    elseif target == "tab_dungeon" or target == "dungeon_gold_mine" then
        return isOpen(page("ui.battle.tri.BattleTriPage"))
            and isOpen(page("ui.battle.stage.StageSelectDialog"))
    end
    return true
end

--- 高优先级剧情/领奖/战斗保持原流程，恢复器不能抢走它们的页面。
function M.isBlocked(target)
    local ownsStageSelect = target == "tab_dungeon" or target == "dungeon_gold_mine"
    local checks = {
        { "ui.hud.popup.OfflineRewardPanel", "isOpen" },
        { "ui.hud.popup.UpdateNoticePopup", "isOpen" },
        { "ui.hud.popup.LevelUpPopup", "isOpen" },
        { "ui.story.gate.DarkTitleScreenGate", "isOpen" },
        { "ui.story.gate.LetterIntro", "isOpen" },
        { "ui.story.gate.IntroCutscene", "isActive" },
        { "ui.dungeon.DungeonBattleScene", "isOpen" },
        { "ui.tower.TowerBattleScene", "isActive" },
        { "ui.tavern.TavernPage", "isRecruitConfirmOpen" },
        { "ui.battle.stage.SweepDialog", "isOpen" },
        { "ui.battle.popup.DamageStatsPanel", "isOpen" },
        { "ui.battle.stage.StageSelectDialog", "isOpen" },
        { "ui.battle.popup.TerminalConfirmDialog", "isOpen" },
    }
    for _, check in ipairs(checks) do
        -- 只豁免当前教程自己的选关窗；无参故事/队列及其他教程仍等待它关闭。
        if not (ownsStageSelect and check[1] == "ui.battle.stage.StageSelectDialog") then
            local ok, p = pcall(require, check[1])
            if ok and p and p[check[2]] and p[check[2]]() == true then return true end
        end
    end
    return false
end

local STORY_PAGES = {
    church = "ui.church.ChurchPage", tavern = "ui.tavern.TavernPage",
    smith = "ui.blacksmith.BlacksmithPage",
}

--- 剧情按真实菜单归属播放，不能把锻炉队列带入酒馆或其他菜单。
function M.getStoryPlace()
    for _, place in ipairs({ "smith", "tavern", "church" }) do
        local p = page(STORY_PAGES[place])
        if isOpen(p) and not isClosing(p) then return place end
    end
    for _, path in ipairs(LEFT_PAGES) do
        if isOpen(page(path)) then return "other" end
    end
    local nav = page("ui.hud.BottomNav").getSelectedIndex()
    if nav == 4 then return "town" end
    -- 正式三行页签是3，左栏城镇与中栏主线同时可见，不能靠旧tab4判断离场。
    if nav == 3 and isOpen(page("ui.battle.tri.BattleTriPage")) then return "battle_town" end
    return "battle"
end

--- 只豁免当前剧情所属菜单；锻炉联动仓库属于同一操作区。
---@param place string|nil
function M.isPendingStoryBlocked(place)
    if M.isBlocked() then return true end
    if place == "tavern" then
        local tavern = page(STORY_PAGES.tavern)
        if tavern.isRecruitBusy and tavern.isRecruitBusy() then return true end
    end
    local owner = place and STORY_PAGES[place]
    local smith = place == "smith" and page(STORY_PAGES.smith)
    local smithOpen = smith and isOpen(smith) and not isClosing(smith)
    for _, path in ipairs(LEFT_PAGES) do
        local p = page(path)
        if isOpen(p) and (path ~= owner or isClosing(p)) then
            local smithWarehouse = smithOpen and path == "ui.backpack.BackpackPanel"
                and not isClosing(p)
            if not smithWarehouse then return true end
        end
    end
    return false
end

--- 返回是否改变页面；宿主据此等待动画结束，再显示/放行引导目标。
---@param force? boolean 缺失目标时重新定位，不重播剧情、不推进教程。
function M.prepare(vg, store, target, newHeroId, initial, equipmentHeroId, force)
    if not target or M.isBlocked(target) then return false end
    if page("ui.story.ScenarioDialogue").isActive() or isOpen(page("ui.hud.popup.RewardPopup")) then
        return false
    end
    local tavern = page("ui.tavern.TavernPage")
    if tavern.isRecruitBusy and tavern.isRecruitBusy() then return false end
    if initial then
        local town = page("ui.town.TownScene")
        if town.cancelPendingPageOpen then town.cancelPendingPageOpen() end
    end
    local changed = false
    local detail = page("ui.character.detail.CharacterDetail")
    if target ~= "equip_item_gifted" then
        changed = close(page("ui.character.equip.EquipmentDetail")) or changed
    end
    changed = close(page("ui.hud.popup.PlayerInfoPanel")) or changed
    local nav = page("ui.hud.BottomNav")
    if target ~= "tab_dungeon" and target ~= "dungeon_gold_mine"
        and nav.getSelectedIndex and nav.getSelectedIndex() == 5 then
        nav.setSelectedIndex(3)
        changed = true
    end
    if TOWN_TARGETS[target] then
        changed = closeLeft({}) or changed
        changed = detailClosed() or changed
    elseif target == "battle_hero_detail" then
        changed = detailClosed() or changed
        changed = closeLeft({}) or changed
        changed = prepareRoster(nil, initial, force) or changed
        if nav.getSelectedIndex and nav.getSelectedIndex() ~= 3 then
            nav.setSelectedIndex(3)
            changed = true
        end
        local tri = page("ui.battle.tri.BattleTriPage")
        if not isOpen(tri) then
            tri.open()
            changed = isOpen(tri) or changed
        end
    elseif target == "character_slot_1" or target == "character_new_hero" then
        changed = detailClosed() or changed
        changed = closeLeft({}) or changed
        changed = prepareRoster(target == "character_new_hero" and newHeroId or nil, initial, force) or changed
    elseif target == "equip_slot_weapon" or target == "equip_btn_auto" or target == "equip_item_gifted" then
        changed = closeLeft({ ["ui.backpack.BackpackPanel"] = true }) or changed
        changed = prepareRoster(nil, initial, force) or changed
        local heroId = equipmentHeroId or firstHero(store)
        if ownedHero(store, heroId) then
            if not isOpen(detail) or isClosing(detail) or not detail.isEquipTab or not detail.isEquipTab()
                or detail.getHeroId() ~= heroId then
                detail.open(heroId, "equip")
                changed = (isOpen(detail) and detail.isEquipTab and detail.isEquipTab()
                    and detail.getHeroId() == heroId) or changed
            end
            if isOpen(detail) and detail.isEquipTab and detail.isEquipTab() and detail.getHeroId() == heroId then
                local bag = page("ui.backpack.BackpackPanel")
                local slot = target == "equip_item_gifted" and "weapon" or nil
                if bag.ensureTutorialEquipment then
                    changed = bag.ensureTutorialEquipment(heroId, slot, force) or changed
                end
            end
        end
    elseif target == "talent_node_area" then
        changed = closeLeft({ ["ui.church.talent.TalentPage"] = true }) or changed
        changed = detailClosed() or changed
        local talent = page("ui.church.talent.TalentPage")
        if not isOpen(talent) or isClosing(talent) then
            if talent.init and vg then talent.init(vg) end
            talent.open()
            changed = isOpen(talent) or changed
        end
    elseif target == "tavern_btn_gacha10" then
        changed = closeLeft({ ["ui.tavern.TavernPage"] = true }) or changed
        changed = detailClosed() or changed
        if tavern.prepareTutorial then changed = tavern.prepareTutorial(vg) or changed
        elseif not isOpen(tavern) then tavern.open(); changed = true end
    elseif target == "smith_btn_enhance" then
        changed = closeLeft({ ["ui.blacksmith.BlacksmithPage"] = true,
            ["ui.backpack.BackpackPanel"] = true }) or changed
        changed = detailClosed() or changed
        local smith = page("ui.blacksmith.BlacksmithPage")
        if smith.prepareTutorial then changed = smith.prepareTutorial(vg) or changed
        elseif not isOpen(smith) then smith.open(); changed = true end
    elseif target == "tab_dungeon" or target == "dungeon_gold_mine" then
        changed = closeLeft({}) or changed
        changed = detailClosed() or changed
        if not nav.getSelectedIndex or nav.getSelectedIndex() ~= 3 then
            nav.setSelectedIndex(3)
            changed = true
        end
        local tri = page("ui.battle.tri.BattleTriPage")
        if not isOpen(tri) then
            tri.open()
            changed = isOpen(tri) or changed
        end
        if isOpen(tri) then
            changed = page("ui.battle.stage.StageSelectDialog").prepareTutorial() or changed
        end
    end
    if changed then print("[TutorialPageRecovery] 恢复目标页面: " .. target) end
    return changed
end

return M
