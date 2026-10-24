 ---@diagnostic disable: param-type-mismatch
 -- ============================================================================
 -- ClientMessageHandler.lua — 消息路由与数据桥接（从 Client.lua 拆分）
 -- 职责: 处理服务端推送的操作结果、状态更新、踢出、离线收益
 -- 拥有的状态: pendingTutorialNotify_, pendingScenarioDialogue_, 等
 -- ============================================================================

local Protocol         = require("shared.Protocol")
local ArtifactDefs     = require("shared.artifact.ArtifactDefs")
local ClientDispatcher = require("runtime.ClientDispatcher")
 local GameState        = require("core.GameState")
 local ExpTable         = require("config.ExpTable")
 local HeroConfig       = require("config.HeroConfig")
 local PlayerStore      = require("core.PlayerStore")
 local GameEvents       = require("config.GameEvents")
 local ScenarioDialogueConfig = require("config.ScenarioDialogueConfig")

 --= UI 模块（lazy require，在 setup 中注入以避免循环依赖）
 local RewardPopup
 local LootBox, LootBoxPage
 local BlacksmithPage, ChurchPage, TalentPage, TavernPage
 local MarketPage, DungeonPage, DungeonBattleScene
 local GMConsolePanel
 local TopBar, BattleScene, CharacterPanel
 local EquipmentDetail
 local RedeemCodePanel, LootBoxSystem
 local TutorialManager

 local M = {}

 --= 跨模块共享的状态 ========================

 M.lastClearedStageId_       = nil
 M.pendingScenarioDialogue_  = nil
 M.pendingFollowUpDialogue_  = nil
 M.pendingTutorialNotify_    = nil

 --= 模块内部状态 ========================

 local sendAction_

 --= 数据桥接状态 ========================

 local lastDeployedSnapshot = nil
 local heroesInitialLoaded  = false
 local firstBattleLoaded    = false
 local pendingDeferredRewardPopup_ = nil

 --= 初始化 ===============================

 --- 注入外部依赖并初始化
 ---@param deps { sendAction: function, ui: table }
 function M.setup(deps)
     sendAction_ = deps.sendAction

     -- 懒加载 UI 模块引用
     RewardPopup         = require("ui.hud.popup.RewardPopup")
     LootBox             = require("ui.loot.LootBox")
     LootBoxPage         = require("ui.loot.LootBoxPage")
     BlacksmithPage      = require("ui.blacksmith.BlacksmithPage")
     BackpackPanel       = require("ui.backpack.BackpackPanel")
     ChurchPage          = require("ui.church.ChurchPage")
     TalentPage          = require("ui.church.talent.TalentPage")
     TavernPage          = require("ui.tavern.TavernPage")
     MarketPage          = require("ui.market.MarketPage")
     DungeonPage         = require("ui.dungeon.DungeonPage")
     DungeonBattleScene  = require("ui.dungeon.DungeonBattleScene")
     GMConsolePanel      = require("ui.dev.GMConsolePanel")
     TopBar              = require("ui.hud.TopBar")
     BattleScene         = require("ui.battle.scene.BattleScene")
     CharacterPanel      = require("ui.character.panel.CharacterPanel")
     EquipmentDetail     = require("ui.character.equip.EquipmentDetail")
     RedeemCodePanel     = require("ui.hud.popup.RedeemCodePanel")
     LootBoxSystem       = require("systems.LootBoxSystem")
     TutorialManager         = require("systems.TutorialManager")
 end

 --= 状态访问器（供 HandleUpdate_Client 消费）========================

 --- 消费并清空 pendingTutorialNotify_，HandleUpdate 每帧调用
 function M.consumePendingTutorialNotify()
     local v = M.pendingTutorialNotify_
     M.pendingTutorialNotify_ = nil
     return v
 end

 function M.setPendingTutorialNotify(scenarioId)
     M.pendingTutorialNotify_ = { scenarioId = scenarioId }
 end

 --- 消费 pendingScenarioDialogue_（延迟播放的情景对话）
 function M.consumePendingScenarioDialogue()
     local v = M.pendingScenarioDialogue_
     M.pendingScenarioDialogue_ = nil
     return v
 end

 --- 消费 pendingFollowUpDialogue_（角色奖励后的后续对话）
 function M.consumePendingFollowUpDialogue()
     local v = M.pendingFollowUpDialogue_
     M.pendingFollowUpDialogue_ = nil
     return v
 end


 --= 数据桥接 ==============================

 function M.onPlayerDataUpdate(data, moduleName)
     if not data then return end
     -- 使用局部 require 确保引用有效（避免 upvalue 为 nil 导致整个函数被 pcall 吞掉）
     local TopBarRef = TopBar or require("ui.hud.TopBar")
     local PlayerInfoPanel = require("ui.hud.popup.PlayerInfoPanel")

     if data.name then
         TopBarRef.setPlayerName(data.name)
         pcall(PlayerInfoPanel.setPlayerName, data.name)
     end
     if data.totalPower then
         TopBarRef.setTotalPower(data.totalPower)
     end
     -- 使用 TopBar 的正确 API：setPlayerData 处理 level/exp/maxExp/avatarHeroId
     TopBarRef.setPlayerData(data)

     -- 同步头像到 PlayerInfoPanel
     if data.avatarHeroId ~= nil then
         pcall(PlayerInfoPanel.setAvatarHeroId, data.avatarHeroId)
     end

     -- player 模块到达时刷新槽位解锁（修复全量推送时 heroes 先于 player 分发导致槽位锁定）
     if data.level then
         local CharacterPanel = require("ui.character.panel.CharacterPanel")
         pcall(CharacterPanel.refreshSlotUnlocks)
     end
 end

 function M.onCurrencyDataUpdate(data, moduleName)
     if not data then return end
     -- 使用 TopBar 的正确 API：setCurrencyData 处理 gold/gems
     local TopBarRef = TopBar or require("ui.hud.TopBar")
     TopBarRef.setCurrencyData(data)
 end

 function M.onHeroesDataUpdate(data, moduleName)
     if not data then return end
     local roster = data.roster
     if not roster then return end

     -- [DIAG-HERO] 打印完整的 deployed 和 roster keys，辅助角色异常定位
     do
         local deployedStr = "nil"
         if data.deployed and type(data.deployed) == "table" then
             local ids = {}
             for i, v in ipairs(data.deployed) do ids[i] = tostring(v) end
             deployedStr = "[" .. table.concat(ids, ",") .. "]"
         end
         local rosterKeys = {}
         for hid, hd in pairs(roster) do
             rosterKeys[#rosterKeys + 1] = tostring(hid) .. "(lv" .. tostring(hd.level or "?") .. ")"
         end
         print(string.format("[DIAG-HERO] onHeroesDataUpdate ENTER deployed=%s rosterKeys={%s} lastSnapshot=%s",
             deployedStr, table.concat(rosterKeys, ","), tostring(lastDeployedSnapshot or "nil")))
     end

     -- 同步阵容到 battle（使用 CharacterPanel 构建完整单位数据）
     -- 注意：此回调在 CharacterPanel.setHeroesData 之后执行（subscribe 先于 onAnyUpdate），
     -- 因此 CharacterPanel 内部的 ownedSet/teamSlots 已经是最新数据。
     local deployed = data.deployed
     local triPage = require("ui.battle.tri.BattleTriPage")
     local triActive = triPage.isOpen()
     if deployed and type(deployed) == "table" and #deployed > 0 then
         local snapshot = M.deployedToString(deployed)
         if snapshot ~= (lastDeployedSnapshot or "") then
             lastDeployedSnapshot = snapshot
             -- 阵容变化：重建完整单位列表
             local team = CharacterPanel.getDeployedTeam()
             -- [DIAG-HERO] 打印 getDeployedTeam 返回结果
             do
                 local teamIds = {}
                 for i, u in ipairs(team) do teamIds[i] = tostring(u.heroId or "?") .. "(lv" .. tostring(u.level or "?") .. ")" end
                 print(string.format("[DIAG-HERO] onHeroesDataUpdate newSnapshot=%s teamFromPanel={%s} len=%d",
                     snapshot, table.concat(teamIds, ","), #team))
             end
             if #team > 0 then
                 if not triActive then BattleScene.setAllies(team) end
                 local BattleTriPage = triPage
                 if BattleTriPage.invalidateTeams then
                     -- [三队隔离] deployed 仅代表 team1；只失效 team1，
                     -- 避免无参调用把三队全部签名清 nil 导致未变动队也重启。
                     -- team2/3 的精确失效由 CharacterHeroSync.invalidateTeams(changed) 处理。
                     BattleTriPage.invalidateTeams({ [1] = true })
                 end
             else
                 print("[DIAG-HERO] WARNING: getDeployedTeam returned EMPTY! deployed=" .. snapshot)
                 if not triActive then BattleScene.setAllies({}) end
             end
         else
             -- CharacterPanel 订阅已按冻结差异做过一次轻刷新，不能在全局路由重复刷新。
         end
     elseif type(deployed) == "table" then
         local wasDeployed = lastDeployedSnapshot ~= nil and lastDeployedSnapshot ~= ""
         lastDeployedSnapshot = ""
         if wasDeployed and triPage.invalidateTeams then triPage.invalidateTeams({ [1] = true }) end
         if not triActive then BattleScene.setAllies({}) end
         TopBar.setTotalPower(0)
         print("[DIAG-HERO] onHeroesDataUpdate empty deployed/roster, cleared battle allies")
     end

     if not heroesInitialLoaded then
         heroesInitialLoaded = true
         -- 初次加载时也刷新一次战力显示
         TopBar.setTotalPower(CharacterPanel.getTotalPower())
     end
 end

 function M.onBattleDataUpdate(data, moduleName)
     if not data then return end
     -- 直接把完整 battle 数据交给 BattleScene.setBattleData 恢复状态
     -- （包含 currentStageId, maxStageId, clearedStages, autoBattle 等字段）
     BattleScene.setBattleData(data)

     if not firstBattleLoaded then
         firstBattleLoaded = true
         if data.maxStageId and tonumber(data.maxStageId) > 0 then
             BattleScene.resume()
         end
     end
 end

 function M.setupDataSubscriptions()
     ClientDispatcher.setOnAnyUpdate(function(modules, context)
         if not modules then return end
         for moduleName, data in pairs(modules) do
             if data then
                 local ok, err = pcall(function()
                     if moduleName == "player" then
                         M.onPlayerDataUpdate(data, moduleName)
                     elseif moduleName == "currency" then
                         M.onCurrencyDataUpdate(data, moduleName)
                     elseif moduleName == "heroes" then
                         M.onHeroesDataUpdate(data, moduleName)
                     elseif moduleName == "battle" then
                         if not (context and context.live) then M.onBattleDataUpdate(data, moduleName) end
                     elseif moduleName == "privilege" then
                         MarketPage.setPrivilegeData(data)
                     end
                 end)
                 if not ok then
                     print("[ClientMsgHandler] onAnyUpdate error in module '" .. tostring(moduleName) .. "': " .. tostring(err))
                 end
             end
         end
     end)
 end

 --= 网络事件处理 ==========================


 --- litNodes 中是否包含指定节点
 ---@param modData table|nil
 ---@param nodeId number|string
 ---@return boolean
 local function isTalentNodeLit(modData, nodeId)
     if not modData or not modData.litNodes or nodeId == nil then return false end
     ---@diagnostic disable-next-line: assign-type-mismatch
     nodeId = tonumber(nodeId)
     for _, id in ipairs(modData.litNodes) do
         if tonumber(id) == nodeId then return true end
     end
     for _, id in pairs(modData.litNodes) do
         if tonumber(id) == nodeId then return true end
     end
     return false
 end

 --- 等待 talents 同步到期望状态（激活/单点重置/全重置）
 ---@param expect table { mode="activate"|"deactivate"|"reset_all", nodeId=number|nil }
 local function finishTalentActionWhenSynced(expect)
     local function synced(modData)
         if not modData then return false end
         if expect.mode == "reset_all" then
             return modData.litNodes and #modData.litNodes == 1 and tonumber(modData.litNodes[1]) == 0
         end
         if expect.mode == "activate" then
             return isTalentNodeLit(modData, expect.nodeId)
         end
         if expect.mode == "deactivate" then
             return not isTalentNodeLit(modData, expect.nodeId)
         end
         return false
     end

     local function apply(completed)
         if TalentPage and TalentPage.syncTalentFromStore then
             pcall(TalentPage.syncTalentFromStore)
         elseif ChurchPage and ChurchPage.syncTalentFromStore then
             pcall(ChurchPage.syncTalentFromStore)
         end
         -- 仅成功激活且目标已同步才结束古树教学；重置或超时刷新不算学习。
         if completed and expect.mode == "activate" and synced(PlayerStore.Get("talents")) then
             TutorialManager.notifyEvent("talent_learned")
         end
     end

     local cur = PlayerStore.Get("talents")
     if synced(cur) then
         apply(true)
         return
     end

     PlayerStore.WaitForChange("talents", {
         timeout = 5.0,
         compare = function(old, new)
             if new == old then return false end
             return synced(new)
         end,
         onChange = function()
             apply(true)
         end,
         onTimeout = function()
             print("[ClientMsgHandler] talent action sync timeout mode=" .. tostring(expect.mode)
                 .. " nodeId=" .. tostring(expect.nodeId))
             apply()
         end,
     })
 end

 --- 操作结果
 local function isSweepResult(data)
     return data.action == Protocol.ACTION_TYPES.SWEEP
         or (data.action == Protocol.ACTION_TYPES.DUNGEON_SWEEP
             and require("config.DungeonConfig").isResourceDungeon(data.dungeonId))
 end

 -- 完整私有展示候选：Bridge协程在到账后调用，组装/排序均完成才交给最终回执。
 -- 此处不发奖、不关页面、不修改源装备；checkpoint可yield，活事务不调用它。
 function M.prepareSweepPresentation(data, checkpoint)
     if data.success ~= true or not isSweepResult(data) then return nil end
     local rewards, equips = {}, data.equips or {}
     if (data.gold or 0) > 0 then rewards[#rewards + 1] = { type = "gold", amount = data.gold } end
     if (data.autoDecomposeEssence or 0) > 0 then
         rewards[#rewards + 1] = { type = "essence", amount = data.autoDecomposeEssence }
     end
     if (data.diamond or 0) > 0 then rewards[#rewards + 1] = { type = "diamond", amount = data.diamond } end
     for i, equip in ipairs(equips) do
         -- SweepService已提供完整只读展示行，可复用而不为巨量装备再复制一层。
         local reward = equip
         if equip.type ~= "equip" then
             reward = {}
             for key, value in pairs(equip) do reward[key] = value end
             reward.type = "equip" -- 旧回执无type时只在副本补齐。
         end
         rewards[#rewards + 1] = reward
         if checkpoint then checkpoint("presentation", i, #equips) end
     end
     local scrollMap = { weaponScroll = "weapon_scroll", offhandScroll = "offhand_scroll",
         armorScroll = "armor_scroll", accessoryScroll = "accessory_scroll",
         helmetScroll = "helmet_scroll", shoesScroll = "shoes_scroll" }
     for field, count in pairs(data.scrollDrops or {}) do
         local kind = scrollMap[field]
         if kind and count > 0 then rewards[#rewards + 1] = { type = kind, amount = count } end
     end
     local summary = {}
     local NumberUtil = require("core.NumberUtil")
     local I18n = require("core.I18n")
     if (data.playerExp or 0) > 0 then
         summary[#summary + 1] = I18n.format("远征经验 +%s", NumberUtil.format(data.playerExp))
     end
     if (data.heroExp or 0) > 0 then
         summary[#summary + 1] = I18n.format("队%d每名队员经验 +%s", data.teamIdx or 1, NumberUtil.format(data.heroExp))
     elseif (data.heroExpTotal or 0) > 0 then
         summary[#summary + 1] = I18n.format("队员经验合计 +%s", NumberUtil.format(data.heroExpTotal))
     end
     local popup = RewardPopup or require("ui.hud.popup.RewardPopup")
     return { version = 1, rewards = rewards, subtitle = table.concat(summary, " · "),
         preparedRewards = checkpoint and popup.prepareRewards(rewards, checkpoint) or nil }
 end

 -- 情景英雄/碎片只展示实际到账；旧回执仍兼容，但不以原配置数量补造奖励。
 local function scenarioHeroRewards(data, heroReward)
     local reward = data.reward or {}
     local rewards, hasCoin = {}, false
     if type(data.rewards) == "table" then
         for _, item in ipairs(data.rewards) do
             local amount = tonumber(item.shardGain) or tonumber(item.amount) or 0
             if item.type ~= "shard" or amount > 0 then
                 local shown = {}
                 for key, value in pairs(item) do shown[key] = value end
                 if item.type == "shard" then shown.amount = amount end
                 rewards[#rewards + 1] = shown
                 if item.type == "tavernCoin" or item.type == "tavern_coin" then hasCoin = true end
             end
         end
     else
         if heroReward and reward.isNew ~= false then
             rewards[#rewards + 1] = { type = "hero", heroId = reward.heroId,
                 name = reward.name or "英雄", quality = (reward.quality or 1) + 2 }
         end
         local amount = math.max(0, tonumber(reward.shardGain) or tonumber(reward.amount) or 0)
         if amount > 0 then rewards[#rewards + 1] = { type = "shard", heroId = reward.heroId, amount = amount } end
     end
     local coins = math.max(0, tonumber(reward.tavernCoin) or 0)
     if coins > 0 and not hasCoin then rewards[#rewards + 1] = { type = "tavernCoin", amount = coins } end
     return rewards
 end

 function M.handleActionResult(eventType, eventData)
     ---@type table
     local data
     if type(eventType) == "table" and eventType.action ~= nil then
         data = eventType
     else
         local dataStr = eventData["Data"]:GetString()
         local ok
         ok, data = pcall(cjson.decode, dataStr)
         if not ok then return end
     end
     -- 优选回执单独路由，成功/失败同一身份门禁，不落入领取/奖励等通用分支。
     if data.action == "PreviewInventoryCuration" or data.action == "ApplyInventoryCuration"
         or data.action == "CancelInventoryCuration" then
         if data.action == "ApplyInventoryCuration" and data.success then
             EquipmentDetail.close()
             if BackpackPanel.onCurationCommitted then BackpackPanel.onCurationCommitted() end
         end
         require("ui.loot.InventoryCurationDialog").onActionResult(data)
         return
     end
     if data.action == "server_diag" then
        print("[Client][SDIAG] " .. tostring(data.message or data.reason or ""))
        return
    end

    print("[Client][ActionResult] received action=" .. tostring(data.action)
         .. " success=" .. tostring(data.success)
         .. " mailPush=" .. tostring(data.mailPush)
         .. " announcementPush=" .. tostring(data.announcementPush))

     if data.action == Protocol.ACTION_TYPES.EQUIP_ALL_BEST and data.quickEquipId then
         local key = "equip_failed"
         if data.success then
             key = data.notificationFailed and "equip_notify_fail"
                 or ((tonumber(data.changes) or 0) > 0 and "equip_done" or "equip_no_gain")
             if (tonumber(data.changes) or 0) > 0 then require("systems.GameSFX").play("install") end
         elseif data.reason == "quick_equip_stale" then
             key = "equip_stale"
         end
         require("core.UiToast").show(require("core.I18n").t(key))
         if data.success then TutorialManager.notifyEvent("equipment_equipped") end
         return -- 异步回执不转发给计算期间新打开的锻炉等无关页面。
     end
     if isSweepResult(data) then
         local SweepDialog = require("ui.battle.stage.SweepDialog")
         local shown, showError = true, nil
         if data.success == true then
             shown, showError = pcall(function()
                 local presentation = data.sweepPresentation
                 if not presentation or presentation.version ~= 1 then presentation = M.prepareSweepPresentation(data) end
                 RewardPopup.show("扫荡奖励", presentation.rewards, { subtitle = presentation.subtitle,
                     preparedRewards = presentation.preparedRewards })
             end)
         end
         -- 正常show返回后才关页；已到账后的展示异常也必须先释放两个所属identity，
         -- 再运行可能失败的提示。某一页cleanup异常不能跳过另一页。
         local cleaned, cleanupError = pcall(SweepDialog.onActionResult, data)
         if not cleaned then print("[ClientMessageHandler] sweep dialog cleanup failed: " .. tostring(cleanupError)) end
         if data.action == Protocol.ACTION_TYPES.DUNGEON_SWEEP and DungeonPage and DungeonPage.onActionResult then
             local pageCleaned, pageError = pcall(DungeonPage.onActionResult, data)
             if not pageCleaned then print("[ClientMessageHandler] sweep page cleanup failed: " .. tostring(pageError)) end
         end
         if data.success ~= true then
             require("core.UiToast").show(require("core.I18n").lookup(data.reason or "扫荡失败，请重试"))
         elseif not shown then
             print("[ClientMessageHandler] sweep committed, presentation failed: " .. tostring(showError))
             require("core.UiToast").show(require("core.I18n").lookup("扫荡奖励已到账，展示失败"))
         end
         return -- 专属回执不通知计算期间新开的锻炉、商店等无关页面。
     end
     if not data.success then
         print("[Client] action failed: action=" .. tostring(data.action)
             .. " reason=" .. tostring(data.reason))
         if data.action == Protocol.ACTION_TYPES.CLAIM_TASK
             or data.action == Protocol.ACTION_TYPES.CLAIM_ALL_TASKS then
             local reasons = {
                 save_failed = "存档失败，奖励未领取，请重试",
                 invalid_reward = "奖励配置异常，本次未发放",
                 reward_failed = "奖励发放失败，请重试",
                 already_claimed = "该奖励已经领取",
                 not_complete = "尚未达到领奖条件",
                 nothing_to_claim = "当前没有可领取奖励",
             }
             require("core.UiToast").show(reasons[data.reason] or "领取失败，请重试")
             return
         end
         if data.action == Protocol.ACTION_TYPES.SELECT_INITIAL_HERO then
             print("[Client][SAVE-BROKEN] initial hero selection blocked: " .. tostring(data.reason))
             if LootBoxPage and LootBoxPage.showToast then LootBoxPage.showToast(data.reason or "存档异常，请联系客服") end
             return
         end
         if data.action == Protocol.ACTION_TYPES.CLAIM_BATTLE_REWARDS and tostring(data.reason or ""):find("英雄数据异常") then
             print("[Client][SAVE-BROKEN] battle reward blocked by invalid hero data: " .. tostring(data.reason))
             if LootBoxPage and LootBoxPage.showToast then LootBoxPage.showToast("角色数据异常，奖励未发放，请联系客服") end
             return
         end
         if data.action == Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD then
             -- 失败领取不启动教程，也不让这次通知串到后续成功情景。
             M.pendingTutorialNotify_ = nil
         end
         if TavernPage.onActionResult then TavernPage.onActionResult(data) end
         if MarketPage.onActionResult then MarketPage.onActionResult(data) end
         if BlacksmithPage.onActionResult then BlacksmithPage.onActionResult(data) end
         if EquipmentDetail.onActionResult then EquipmentDetail.onActionResult(data) end
         if ChurchPage.onActionResult then ChurchPage.onActionResult(data) end
         if DungeonPage.onActionResult then DungeonPage.onActionResult(data) end
         if data.action == Protocol.ACTION_TYPES.ACTIVATE_TALENT
             or data.action == Protocol.ACTION_TYPES.RESET_SINGLE_TALENT
             or data.action == Protocol.ACTION_TYPES.RESET_TALENTS then
             if TalentPage and TalentPage.syncTalentFromStore then
                 pcall(TalentPage.syncTalentFromStore)
             elseif ChurchPage and ChurchPage.syncTalentFromStore then
                 pcall(ChurchPage.syncTalentFromStore)
             end
             if LootBoxPage and LootBoxPage.showToast then
                 LootBoxPage.showToast(data.reason or "天赋操作失败")
             end
         end
             if data.action == Protocol.ACTION_TYPES.CONVERT_UR_SHARD
             or data.action == Protocol.ACTION_TYPES.RESTORE_UR_SHARD_CONVERT
             or data.action == Protocol.ACTION_TYPES.SET_AUTO_DECOMPOSE
             or data.action == Protocol.ACTION_TYPES.DECOMPOSE_EQUIP
             or data.action == Protocol.ACTION_TYPES.TOGGLE_EQUIP_LOCK
             or data.action == Protocol.ACTION_TYPES.EQUIP_ITEM then
             -- 穿戴/分解失败也转发仓库，释放自己的待响应状态并显示拒绝原因。
             local BackpackPanel = require("ui.backpack.BackpackPanel")
             if BackpackPanel.onActionResult then BackpackPanel.onActionResult(data) end
         end
         return
     end

     -- 登录补发等延迟弹窗（等离线收益面板关闭后再展示）
     if data.deferredRewardPopup and data.rewards and #data.rewards > 0 then
         pendingDeferredRewardPopup_ = {
             title    = data.popupTitle or "奖励",
             subtitle = data.popupSubtitle,
             rewards  = data.rewards,
         }
         return
     end

     if data.action == Protocol.ACTION_TYPES.ACTIVATE_TALENT and data.nodeId then
         finishTalentActionWhenSynced({ mode = "activate", nodeId = data.nodeId })
     end
     if data.action == Protocol.ACTION_TYPES.RESET_SINGLE_TALENT and data.nodeId then
         finishTalentActionWhenSynced({ mode = "deactivate", nodeId = data.nodeId })
     end
     if data.action == Protocol.ACTION_TYPES.RESET_TALENTS then
         finishTalentActionWhenSynced({ mode = "reset_all" })
     end

     -- 首通奖励弹窗
     local fcr = data.firstClearRewards
     if fcr then
         local rewards = {}
         if fcr.gold and fcr.gold > 0 then rewards[#rewards + 1] = { type = "gold", amount = fcr.gold } end
         if fcr.diamond and fcr.diamond > 0 then rewards[#rewards + 1] = { type = "diamond", amount = fcr.diamond } end
         if fcr.essence and fcr.essence > 0 then rewards[#rewards + 1] = { type = "essence", amount = fcr.essence } end
         if fcr.arcaneDust and fcr.arcaneDust > 0 then rewards[#rewards + 1] = { type = "arcane_dust", amount = fcr.arcaneDust } end
         if fcr.goldenKey and fcr.goldenKey > 0 then rewards[#rewards + 1] = { type = "golden_key", amount = fcr.goldenKey } end
         if fcr.corruptStone and fcr.corruptStone > 0 then rewards[#rewards + 1] = { type = "corrupt_stone", amount = fcr.corruptStone } end
         if fcr.sacredStone and fcr.sacredStone > 0 then rewards[#rewards + 1] = { type = "sacred_stone", amount = fcr.sacredStone } end
         if fcr.equips then
             for _, e in ipairs(fcr.equips) do
                 rewards[#rewards + 1] = { type = "equip", templateId = e.templateId, quality = e.quality or 1, level = e.level or 1 }
             end
         end
         if fcr.scroll then
             local SCROLL_TO_REWARD = {
                 weaponScroll = "weapon_scroll", offhandScroll = "offhand_scroll",
                 armorScroll = "armor_scroll", accessoryScroll = "accessory_scroll",
                 helmetScroll = "helmet_scroll", shoesScroll = "shoes_scroll",
             }
             if fcr.scroll.scrolls then
                 for st, n in pairs(fcr.scroll.scrolls) do
                     local rk = SCROLL_TO_REWARD[st]
                     if rk and n > 0 then rewards[#rewards + 1] = { type = rk, amount = n } end
                 end
             elseif fcr.scroll.type then
                 local rk = SCROLL_TO_REWARD[fcr.scroll.type]
                 if rk and fcr.scroll.amount and fcr.scroll.amount > 0 then rewards[#rewards + 1] = { type = rk, amount = fcr.scroll.amount } end
             end
         end
         if #rewards > 0 then RewardPopup.show("首通奖励", rewards) end
    end
    -- 首通情景交给 StoryPlayer 排队，等奖励弹窗关掉再播
    if M.lastClearedStageId_ then
        local clearedId = M.lastClearedStageId_
        M.lastClearedStageId_ = nil
        print("[ClientMessageHandler] first clear story stage=" .. tostring(clearedId))
        require("systems.StoryPlayer").onStage(clearedId, "clear")
    end

     -- 签到结果
     if data.reward and data.reward.type then
         local action = data.action or ""
         if action == Protocol.ACTION_TYPES.WEEKLY_SIGN or action == Protocol.ACTION_TYPES.DAILY_SIGN or action == Protocol.ACTION_TYPES.RETRO_SIGN then
             local title = action == Protocol.ACTION_TYPES.RETRO_SIGN and "补签奖励" or "签到奖励"
             RewardPopup.show(title, { { type = data.reward.type, amount = data.reward.amount } })
         end
     end

     -- 任务领取结果
     if data.action == Protocol.ACTION_TYPES.CLAIM_TASK and data.reward then
         RewardPopup.show("任务奖励", { { type = data.reward.type, amount = data.reward.amount } })
     end
     if data.action == Protocol.ACTION_TYPES.CLAIM_ALL_TASKS and data.rewards and #data.rewards > 0 then
         RewardPopup.show("功绩奖励", data.rewards)
     end

     -- 兑换码
     if (data.redeemAction or data.action == Protocol.ACTION_TYPES.REDEEM_CODE) and RedeemCodePanel.onActionResult then RedeemCodePanel.onActionResult(data) end
     -- 无玩家入口的旧公告面板已移除，公告推送不再转发给 UI。
     if data.announcementPush and data.announcements then
         return
     end

     -- 实际一键穿戴成功后才结束教程，不把按钮点击等同于业务完成。
     if data.action == Protocol.ACTION_TYPES.EQUIP_ALL_BEST and data.success == true then
         TutorialManager.notifyEvent("equipment_equipped")
     end

     -- 各页面 onActionResult 分发
     if BlacksmithPage.onActionResult then pcall(BlacksmithPage.onActionResult, data) end
     if BackpackPanel.onActionResult then pcall(BackpackPanel.onActionResult, data) end
     if EquipmentDetail.onActionResult then pcall(EquipmentDetail.onActionResult, data) end
     if ChurchPage.onActionResult then pcall(ChurchPage.onActionResult, data) end
     if TavernPage.onActionResult then pcall(TavernPage.onActionResult, data) end
     if DungeonBattleScene.onActionResult then pcall(DungeonBattleScene.onActionResult, data) end
     if MarketPage.onActionResult then pcall(MarketPage.onActionResult, data) end
     if GMConsolePanel.onActionResult then pcall(GMConsolePanel.onActionResult, data) end

     -- 神器合成/置换结果
     if data.action == Protocol.ACTION_TYPES.ARTIFACT_MERGE or data.action == Protocol.ACTION_TYPES.ARTIFACT_REROLL then
         local artifacts = data.artifacts or (data.artifact and { data.artifact }) or nil
         if artifacts and #artifacts > 0 then
             local rewards = {}
             for _, a in ipairs(artifacts) do
                 rewards[#rewards + 1] = {
                     type = "artifact",
                     id = a.id,
                     artifactId = a.artifactId,
                     name = ArtifactDefs.getName(a),
                     quality = a.quality or 1,
                     value = a.value or 0,
                     valueRatio = a.valueRatio,
                     threatClearValue = a.threatClearValue,
                     threatClearRatio = a.threatClearRatio,
                 }
             end
             RewardPopup.show(data.action == Protocol.ACTION_TYPES.ARTIFACT_REROLL and "置换结果" or "合成结果", rewards)
         end
     end

     -- 副本操作
     if DungeonPage.onActionResult then pcall(DungeonPage.onActionResult, data) end

     -- 购买成功
     if data.action == Protocol.ACTION_TYPES.MARKET_BUY and data.rewardType and not data.marketSpecialShown then
         RewardPopup.show("购买成功", { { type = data.rewardType, amount = data.rewardCount or 1 } })
     end

     -- 战利品领取
     if data.claimed and data.claimedCount and data.claimedCount > 0 then
         LootBox.refreshPage()
         local rewards = {}
         for _, e in ipairs(data.claimed) do
             rewards[#rewards + 1] = { type = "equip", templateId = e.templateId, quality = e.quality or 1, level = e.level or 1 }
         end
         RewardPopup.show("领取了" .. data.claimedCount .. " 件装备", rewards)
         if data.bagFull then LootBoxPage.showToast("背包已满，请先分解多余装备") end
     end
     if data.bagFull and (not data.claimedCount or data.claimedCount == 0) then
         LootBoxPage.showToast("背包已满，请先分解多余装备")
     end

     -- 战利品一键分解
     if data.lootDecomposed and data.decomposeCount and data.decomposeCount > 0 then
         LootBox.refreshPage()
         local rewards = {}
         if data.essenceReward and data.essenceReward > 0 then rewards[#rewards + 1] = { type = "essence", amount = data.essenceReward } end
         if #rewards > 0 then RewardPopup.show("分解奖励", rewards) end
     end

     -- 击杀掉落确认
     if data.droppedSeeds then
         for _, seed in ipairs(data.droppedSeeds) do LootBox.addSeedHint(seed.quality or 1, seed.level or 1) end
     end

     -- 情景对话奖励
     if data.action == Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD then
         local tutorialNotify = M.pendingTutorialNotify_
         M.pendingTutorialNotify_ = nil
         local tutorialNotified = false
         local function fireTutorial()
             if tutorialNotify and not tutorialNotified then
                 tutorialNotified = true
                 TutorialManager.onScenarioClaimed(tutorialNotify.scenarioId)
             end
         end
         -- 成功回执即持久化待触发组；实际启动由TM等窗口关闭和安静期，避免关窗前退出丢教程。
         if data.success then fireTutorial() end
         if data.success and data.rewardType == "none" then
             fireTutorial()
         elseif data.success and data.rewardType == "currency" and data.reward then
             local CURRENCY_KEY_TO_POPUP_TYPE = {
                 recruitTicket = "adventure_ticket", sweep_ticket = "sweep_ticket",
                 goldenKey = "golden_key", corruptStone = "corrupt_stone", sacredStone = "sacred_stone",
                 gems = "diamond", gold = "gold", essence = "essence",
                 weaponScroll = "weapon_scroll", offhandScroll = "offhand_scroll",
                 armorScroll = "armor_scroll", accessoryScroll = "accessory_scroll",
                 helmetScroll = "helmet_scroll", shoesScroll = "shoes_scroll", randomScroll = "random_scroll",
             }
             local key = data.reward.currencyKey; local amount = data.reward.amount or 0
             local popupType = CURRENCY_KEY_TO_POPUP_TYPE[key] or key
             RewardPopup.show("远征奖励", { { type = popupType, amount = amount } }, { onClose = fireTutorial })
         elseif data.success and (data.rewardType == "hero" or data.rewardType == "shard") then
             local reward = data.reward or {}
             local heroId = reward.heroId
             if not heroId then
                 for _, item in ipairs(data.rewards or {}) do if item.heroId then heroId = item.heroId; break end end
             end
             local HERO_TO_FOLLOWUP = { [1]=14, [2]=15, [3]=16 }
             local followUpId = data.rewardType == "hero" and HERO_TO_FOLLOWUP[heroId]
             local heroConfig = followUpId and ScenarioDialogueConfig["SCENARIO_" .. followUpId]
             local rewards = scenarioHeroRewards(data, data.rewardType == "hero")
             local function onClose()
                 fireTutorial()
                 if data.rewardType == "hero" then
                     if heroConfig then M.pendingFollowUpDialogue_ = { config = heroConfig } end
                 elseif heroId then
                     local okCd, CharacterDetail = pcall(require, "ui.character.detail.CharacterDetail")
                     if okCd and CharacterDetail then CharacterDetail.open(heroId, "awaken") end
                 end
             end
             if #rewards > 0 then RewardPopup.show("远征奖励", rewards, { onClose = onClose }) else onClose() end
         elseif data.success and data.reward then
             RewardPopup.show("远征奖励", { {
                 type = "equip", templateId = data.reward.templateId,
                 quality = data.reward.quality or 1, level = data.reward.level or 1,
                 slot = data.reward.slot, equip = data.reward.equip,
                 destination = data.reward.destination,
             } }, { onClose = fireTutorial })
         else
             fireTutorial()
         end
     end

     -- 碎片合成英雄
     if data.action == Protocol.ACTION_TYPES.SYNTHESIZE_HERO then
         if data.success then
             local heroCfg = HeroConfig.get(data.heroId); local hn = heroCfg and heroCfg.name or "英雄"
             local hq = heroCfg and heroCfg.quality or 1
             local joinedHeroId = data.heroId
             local rewards = { { type = "hero", heroId = joinedHeroId, name = hn, quality = hq + 2 } }
             if (tonumber(data.tavernCoin) or 0) > 0 then
                 rewards[#rewards + 1] = { type = "tavernCoin", amount = data.tavernCoin }
             end
             RewardPopup.show("合成成功", rewards, {
                 onClose = function()
                     require("ui.character.hero.HeroScenario").onOpenHero(joinedHeroId)
                 end,
             })
         end
     end

     -- 觉醒的页面回调已在上方正常分发；这里只告知旧库存归并的实际到账币。
     if data.action == Protocol.ACTION_TYPES.ACTIVATE_AWAKENING and data.success
         and (tonumber(data.tavernCoin) or 0) > 0 then
         RewardPopup.show("转化成功", { { type = "tavernCoin", amount = data.tavernCoin } })
     end

     -- 碎片转酒馆币
     if data.action == Protocol.ACTION_TYPES.CONVERT_SHARD_TO_COIN and data.success then
         RewardPopup.show("转化成功", { { type = "tavernCoin", name = "酒馆币", amount = data.coinGained or 0, quality = 3 } })
     end

     -- UR碎片转化
     if data.action == Protocol.ACTION_TYPES.CONVERT_UR_SHARD and data.success then
         RewardPopup.show("转化成功", {
             { type = "shard", heroId = data.toHeroId, amount = data.amount or 0 },
         })
     end
     -- 离线领取完成后说明溢出装备的实际去向；仅展示，不再次发奖。
     if data.action == Protocol.ACTION_TYPES.CLAIM_OFFLINE_REWARDS
         and data.lootboxEquips and #data.lootboxEquips > 0 then
         RewardPopup.show("离线装备已入遗匣", data.lootboxEquips, { panel = "left" })
     end

 end

 --- 状态更新（服务端推送的模块数据）

--- 将 deployed 数组序列化为可比较的字符串
function M.deployedToString(deployed)
    if not deployed or #deployed == 0 then return "" end
    local sorted = {}
    for _, id in ipairs(deployed) do
        sorted[#sorted + 1] = tostring(id)
    end
    table.sort(sorted)
    return table.concat(sorted, ",")
end

--- 外部设置快照（Client.lua 本地换阵容时调用，防止服务端回推时重复 reload）
function M.setLastDeployedSnapshot(snapshot)
    lastDeployedSnapshot = snapshot
end

function M.handleStateUpdate(eventType, eventData)
     local dataStr = eventData["Data"]:GetString()
     if not dataStr or dataStr == "" then return end
     ClientDispatcher.handleStateUpdate(dataStr)
 end

 --- 被踢出
 function M.handleKicked(eventType, eventData)
     local dataStr = eventData["Data"]:GetString()
     local ok, data = pcall(cjson.decode, dataStr)
     local reason = (ok and data and data.reason) or "被服务器踢出"
     print("[Client] kicked: " .. reason)
     return reason  -- 外部负责更新 Client 状态和遮罩
 end

 --- 离线收益推送
 function M.handleOfflineReward(eventType, eventData)
     local dataStr = eventData["Data"]:GetString()
     local ok, data = pcall(cjson.decode, dataStr)
     if not ok then return nil end
     return data
 end

 --- 是否有待展示的登录延迟奖励弹窗
 ---@return boolean
 function M.hasPendingDeferredRewardPopup()
     return pendingDeferredRewardPopup_ ~= nil
 end

 --- 取出并清除待展示的登录延迟奖励弹窗
 ---@return table|nil { title, subtitle, rewards }
 function M.takePendingDeferredRewardPopup()
     local pending = pendingDeferredRewardPopup_
     pendingDeferredRewardPopup_ = nil
     return pending
 end

 --- 清除待展示的登录延迟奖励弹窗（新会话/清档时调用）
 function M.clearPendingDeferredRewardPopup()
     pendingDeferredRewardPopup_ = nil
 end

 --- 清理同会话切区时的消息桥接状态，避免旧区快照阻止新区首包刷新
 function M.resetSessionBridgeState()
     lastDeployedSnapshot = nil
     heroesInitialLoaded = false
     firstBattleLoaded = false
     pendingDeferredRewardPopup_ = nil
     M.lastClearedStageId_ = nil
     M.pendingScenarioDialogue_ = nil
     M.pendingFollowUpDialogue_ = nil
     M.pendingTutorialNotify_ = nil
     print("[ClientMsgHandler] session bridge state reset")
 end

 return M
