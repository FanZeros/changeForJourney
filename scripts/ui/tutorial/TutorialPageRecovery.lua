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

local function page(path)
    return require(path)
end
local function isOpen(p)
    return p.isOpen and p.isOpen() == true
end
local function isClosing(p)
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
    local slots = panel.getTeamSlotsData and panel.getTeamSlotsData()
    local first = slots and slots[1]
    if first and first.state == "occupied" and first.heroId then return tonumber(first.heroId) end
    local heroes = store and store.Get("heroes")
    local deployed = heroes and heroes.deployed
    return deployed and tonumber(deployed[1]) or nil
end
local function detailClosed()
    return close(page("ui.character.detail.CharacterDetail"))
end
local function prepareRoster(heroId, initial)
    local panel = page("ui.character.panel.CharacterPanel")
    local wrongTeam = panel.getActiveTeamIdx and panel.getActiveTeamIdx() ~= 1
    if (initial or wrongTeam) and panel.prepareTutorial then
        panel.prepareTutorial(heroId)
        return true
    end
    return false
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

--- 返回是否改变页面；宿主据此等待动画结束，再显示/放行引导目标。
function M.prepare(vg, store, target, newHeroId, initial)
    if not target then return false end
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
    elseif target == "character_slot_1" or target == "character_new_hero" then
        changed = detailClosed() or changed
        changed = closeLeft({}) or changed
        changed = prepareRoster(target == "character_new_hero" and newHeroId or nil, initial) or changed
    elseif target == "equip_slot_weapon" or target == "equip_btn_auto" or target == "equip_item_gifted" then
        changed = closeLeft({ ["ui.backpack.BackpackPanel"] = true }) or changed
        changed = prepareRoster(nil, initial) or changed
        local heroId = firstHero(store)
        if heroId and (not isOpen(detail) or isClosing(detail) or not detail.isEquipTab or not detail.isEquipTab()
            or detail.getHeroId() ~= heroId) then
            detail.open(heroId, "equip")
            changed = true
        end
        if heroId then
            local bag = page("ui.backpack.BackpackPanel")
            local slot = target == "equip_item_gifted" and "weapon" or nil
            if bag.ensureTutorialEquipment then
                changed = bag.ensureTutorialEquipment(heroId, slot) or changed
            end
        end
    elseif target == "talent_node_area" then
        changed = closeLeft({ ["ui.church.talent.TalentPage"] = true }) or changed
        changed = detailClosed() or changed
        local talent = page("ui.church.talent.TalentPage")
        if not isOpen(talent) or isClosing(talent) then
            if talent.init then talent.init(vg) end
            talent.open()
            changed = true
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
