 ---@diagnostic disable: param-type-mismatch
 -- ============================================================================
 -- ClientMessageHandler.lua — 消息路由与数据桥接（从 Client.lua 拆分）
 -- 职责: 处理服务端推送的操作结果、状态更新、踢出、离线收益
 -- 拥有的状态: batchMerge_, pendingTutorialNotify_, pendingScenarioDialogue_, 等
 -- ============================================================================

local Protocol         = require("shared.Protocol")
local MarketSchema     = require("shared.market.MarketSchema")
local ArtifactDefs     = require("shared.artifact.ArtifactDefs")
local ClientDispatcher = require("network.ClientDispatcher")
 local GameState        = require("core.GameState")
 local ExpTable         = require("config.ExpTable")
 local HeroConfig       = require("config.HeroConfig")
 local PlayerStore      = require("client.data.PlayerStore")
 local EventBus         = require("core.EventBus")
 local GameEvents       = require("config.GameEvents")
 local ScenarioDialogueConfig = require("config.ScenarioDialogueConfig")

 --= UI 模块（lazy require，在 setup 中注入以避免循环依赖）
 local RewardPopup
 local LootBox, LootBoxPage
 local BlacksmithPage, ChurchPage, TavernPage
 local ArenaPage, ArenaBattleScene, ArenaOpponentDialog
 local MarketPage, GuildPage, DungeonPage, DungeonBattleScene
 local GMConsolePanel, RelicReforgePanel, MailPanel, AnnouncementPanel
 local TopBar, BattleScene, CharacterPanel
 local CharacterSelect
 local EquipmentDetail
 local RedeemCodePanel, SignInPanel, LootBoxSystem
 local TutorialManager
local AdManager

 local M = {}

 --= 跨模块共享的状态 ========================

 M.lastClearedStageId_       = nil
 M.pendingScenarioDialogue_  = nil
 M.pendingFollowUpDialogue_  = nil
 M.pendingTutorialNotify_    = nil

 --= 模块内部状态 ========================

 local sendAction_

 local batchMerge_ = {
     active    = false,
     expected  = 0,
     results   = {},
     timeout   = 0,
 }
 local BATCH_MERGE_TIMEOUT = 5.0

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
     RewardPopup         = require("ui.RewardPopup")
     LootBox             = require("ui.LootBox")
     LootBoxPage         = require("ui.LootBoxPage")
     BlacksmithPage      = require("ui.BlacksmithPage")
     BackpackPanel       = require("ui.BackpackPanel")
     ChurchPage          = require("ui.ChurchPage")
     TavernPage          = require("ui.TavernPage")
     ArenaPage           = require("ui.ArenaPage")
     ArenaBattleScene    = require("ui.ArenaBattleScene")
     ArenaOpponentDialog = require("ui.ArenaOpponentDialog")
     MarketPage          = require("ui.MarketPage")
     GuildPage           = require("ui.GuildPage")
     DungeonPage         = require("ui.DungeonPage")
     DungeonBattleScene  = require("ui.DungeonBattleScene")
     GMConsolePanel      = require("ui.GMConsolePanel")
     RelicReforgePanel   = require("ui.RelicReforgePanel")
     MailPanel           = require("ui.MailPanel")
     TopBar              = require("ui.TopBar")
     BattleScene         = require("ui.BattleScene")
     CharacterPanel      = require("ui.CharacterPanel")
     CharacterSelect     = require("ui.CharacterSelect")
     EquipmentDetail     = require("ui.EquipmentDetail")
     RedeemCodePanel     = require("ui.RedeemCodePanel")
     SignInPanel         = require("ui.SignInPanel")
     LootBoxSystem       = require("systems.LootBoxSystem")
     TutorialManager         = require("systems.TutorialManager")
    AnnouncementPanel       = require("ui.AnnouncementPanel")
    AdManager               = require("systems.AdManager")

     -- 批量合并监听
     EventBus.on("RELIC_BATCH_MERGE_START", function(data)
         local count = data and data.count or 0
         if count > 0 then
             batchMerge_.active   = true
             batchMerge_.expected = count
             batchMerge_.results  = {}
             batchMerge_.timeout  = 0
             print("[ClientMsgHandler] batchMerge started, expecting " .. count .. " results")
         end
     end)
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

 --- 更新 batchMerge_ 超时计时器，返回是否超时
 ---@param dt number
 ---@return boolean
 function M.updateBatchMergeTimeout(dt)
     if batchMerge_.active then
         batchMerge_.timeout = batchMerge_.timeout + dt
         if batchMerge_.timeout >= BATCH_MERGE_TIMEOUT then
             -- 超时：强制弹出已有结果
             if #batchMerge_.results > 0 then
                 RewardPopup.show("合成结果", batchMerge_.results)
             end
             batchMerge_.active = false
             batchMerge_.expected = 0
             batchMerge_.results = {}
             batchMerge_.timeout = 0
             return true
         end
     end
     return false
 end

 --= 数据桥接 ==============================

 function M.onPlayerDataUpdate(data, moduleName)
     if not data then return end
     -- 使用局部 require 确保引用有效（避免 upvalue 为 nil 导致整个函数被 pcall 吞掉）
     local TopBarRef = TopBar or require("ui.TopBar")
     local PlayerInfoPanel = require("ui.PlayerInfoPanel")

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
     if data.avatarFrameId ~= nil then
         pcall(PlayerInfoPanel.setAvatarFrameId, data.avatarFrameId)
     end

     -- player 模块到达时刷新槽位解锁（修复全量推送时 heroes 先于 player 分发导致槽位锁定）
     if data.level then
         local CharacterPanel = require("ui.CharacterPanel")
         pcall(CharacterPanel.refreshSlotUnlocks)
     end
 end

 function M.onCurrencyDataUpdate(data, moduleName)
     if not data then return end
     -- 使用 TopBar 的正确 API：setCurrencyData 处理 gold/gems
     local TopBarRef = TopBar or require("ui.TopBar")
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
                 BattleScene.setAllies(team)
             else
                 print("[DIAG-HERO] WARNING: getDeployedTeam returned EMPTY! deployed=" .. snapshot)
                 BattleScene.setAllies({})
             end
         else
             -- 阵容 ID 未变但等级/属性可能变化（英雄升级/装备/觉醒）：
             -- 调用 refreshAllyStats 让变化以 _pendingSnapshot 存入，下次波次切换时生效
             if BattleScene.refreshAllyStats then
                 BattleScene.refreshAllyStats()
             end
         end
     else
         lastDeployedSnapshot = ""
         BattleScene.setAllies({})
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
     ClientDispatcher.setOnAnyUpdate(function(modules)
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
                         M.onBattleDataUpdate(data, moduleName)
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

 --- 在 mod_relics 中查找遗物（bag + grid，兼容非连续数组）
 ---@param modData table|nil
 ---@param relicId string
 ---@return table|nil
 local function findRelicInModData(modData, relicId)
     if not modData or not relicId then return nil end
     relicId = tostring(relicId)
     for _, list in ipairs({ modData.bag, modData.grid }) do
         if list then
             for _, r in ipairs(list) do
                 if r and tostring(r.id) == relicId then return r end
             end
             for _, r in pairs(list) do
                 if type(r) == "table" and tostring(r.id) == relicId then return r end
             end
         end
     end
     return nil
 end

 --- 洗练确认是否已同步到客户端（词缀已替换且 pending 已清）
 ---@param modData table|nil
 ---@param relicId string
 ---@param newAffixId number|nil
 ---@return boolean
 local function isReforgeConfirmSynced(modData, relicId, newAffixId)
     local relic = findRelicInModData(modData, relicId)
     if not relic then return false end
     if newAffixId and tonumber(relic.affixId) ~= tonumber(newAffixId) then
         return false
     end
     return relic.pendingReforgeAffixId == nil
 end

 --- 等待 mod_relics 同步后再关闭洗练面板（避免结果事件先于数据 / 重连旧包覆盖）
 ---@param relicId string|nil
 ---@param newAffixId number|nil
 local function finishReforgeConfirmWhenSynced(relicId, newAffixId)
     if not relicId then
         pcall(RelicReforgePanel.setConfirmResult, true, nil)
         return
     end
     relicId = tostring(relicId)

     local function applyResult(modData)
         if findRelicInModData(modData, relicId) then
             pcall(RelicReforgePanel.setConfirmResult, true, nil)
         else
             print("[ClientMsgHandler] REFORGE_CONFIRM relic missing after sync id=" .. relicId)
             pcall(RelicReforgePanel.setConfirmResult, false, "遗物数据同步异常，请重新打开背包查看")
         end
     end

     local cur = PlayerStore.Get("mod_relics")
     if isReforgeConfirmSynced(cur, relicId, newAffixId) then
         applyResult(cur)
         return
     end

     PlayerStore.WaitForChange("mod_relics", {
         timeout = 5.0,
         compare = function(old, new)
             if new == old then return false end
             return isReforgeConfirmSynced(new, relicId, newAffixId)
         end,
         onChange = function(newVal)
             applyResult(newVal)
         end,
         onTimeout = function()
             local latest = PlayerStore.Get("mod_relics")
             if isReforgeConfirmSynced(latest, relicId, newAffixId) then
                 applyResult(latest)
             else
                 print("[ClientMsgHandler] REFORGE_CONFIRM sync timeout id=" .. relicId)
                 applyResult(latest)
             end
         end,
     })
 end

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

     local function apply()
         if ChurchPage and ChurchPage.syncTalentFromStore then
             pcall(ChurchPage.syncTalentFromStore)
         end
     end

     local cur = PlayerStore.Get("talents")
     if synced(cur) then
         apply()
         return
     end

     PlayerStore.WaitForChange("talents", {
         timeout = 5.0,
         compare = function(old, new)
             if new == old then return false end
             return synced(new)
         end,
         onChange = function()
             apply()
         end,
         onTimeout = function()
             print("[ClientMsgHandler] talent action sync timeout mode=" .. tostring(expect.mode)
                 .. " nodeId=" .. tostring(expect.nodeId))
             apply()
         end,
     })
 end

 --- 操作结果
 function M.handleActionResult(eventType, eventData)
     local dataStr = eventData["Data"]:GetString()
     local ok, data = pcall(cjson.decode, dataStr)
     if not ok then return end
     if data.action == "server_diag" then
        print("[Client][SDIAG] " .. tostring(data.message or data.reason or ""))
        return
    end

    print("[Client][ActionResult] received action=" .. tostring(data.action)
         .. " success=" .. tostring(data.success)
         .. " mailPush=" .. tostring(data.mailPush)
         .. " announcementPush=" .. tostring(data.announcementPush)
         .. " dataLen=" .. tostring(#dataStr))

     if not data.success then
         print("[Client] action failed: action=" .. tostring(data.action)
             .. " reason=" .. tostring(data.reason))
         if data.action == Protocol.ACTION_TYPES.SELECT_INITIAL_HERO then
             print("[Client][SAVE-BROKEN] initial hero selection blocked: " .. tostring(data.reason))
             if CharacterSelect and CharacterSelect.close then CharacterSelect.close() end
             if LootBoxPage and LootBoxPage.showToast then LootBoxPage.showToast(data.reason or "存档异常，请联系客服") end
             return
         end
         if data.action == Protocol.ACTION_TYPES.CLAIM_BATTLE_REWARDS and tostring(data.reason or ""):find("英雄数据异常") then
             print("[Client][SAVE-BROKEN] battle reward blocked by invalid hero data: " .. tostring(data.reason))
             if LootBoxPage and LootBoxPage.showToast then LootBoxPage.showToast("角色数据异常，奖励未发放，请联系客服") end
             return
         end
         if TavernPage.onActionResult then TavernPage.onActionResult(data) end
         if ArenaOpponentDialog.onActionResult then ArenaOpponentDialog.onActionResult(data) end
         if MarketPage.onActionResult then MarketPage.onActionResult(data) end
         if BlacksmithPage.onActionResult then BlacksmithPage.onActionResult(data) end
         if EquipmentDetail.onActionResult then EquipmentDetail.onActionResult(data) end
         if ChurchPage.onActionResult then ChurchPage.onActionResult(data) end
         if ArenaPage.onActionResult then ArenaPage.onActionResult(data) end
         if GuildPage.onActionResult then GuildPage.onActionResult(data) end
         if DungeonPage.onActionResult then DungeonPage.onActionResult(data) end
         if data.action == Protocol.ACTION_TYPES.RELIC_REFORGE then
             pcall(RelicReforgePanel.setReforgeResult, nil)
         end
         if data.action == Protocol.ACTION_TYPES.RELIC_REFORGE_CONFIRM then
             pcall(RelicReforgePanel.setConfirmResult, false, data.reason)
         end
         if data.action == Protocol.ACTION_TYPES.ACTIVATE_TALENT
             or data.action == Protocol.ACTION_TYPES.RESET_SINGLE_TALENT
             or data.action == Protocol.ACTION_TYPES.RESET_TALENTS then
             if ChurchPage and ChurchPage.syncTalentFromStore then
                 pcall(ChurchPage.syncTalentFromStore)
             end
             if LootBoxPage and LootBoxPage.showToast then
                 LootBoxPage.showToast(data.reason or "天赋操作失败")
             end
         end
         -- AD_CONFIRM 失败时触发重试机制
         if data.action == Protocol.ACTION_TYPES.AD_CONFIRM and AdManager and AdManager.OnAdConfirmResult then
             AdManager.OnAdConfirmResult(data)
         end
         if data.action == Protocol.ACTION_TYPES.TRANSFER_CLOSED_CHALLENGER_CARD then
             local ServerSelectPanel = require("ui.ServerSelectPanel")
             if ServerSelectPanel.setClosedTransferPending then
                 ServerSelectPanel.setClosedTransferPending(false)
             end
             if LootBoxPage and LootBoxPage.showToast then
                 LootBoxPage.showToast(data.reason or "特权卡转出失败")
             end
             return
         end
         if data.action == Protocol.ACTION_TYPES.TRANSFER_PRIVILEGE_CARD
             or data.action == Protocol.ACTION_TYPES.TRANSFER_CLOSED_CHALLENGER_CARD
             or data.action == Protocol.ACTION_TYPES.CONVERT_UR_SHARD
             or data.action == Protocol.ACTION_TYPES.RESTORE_UR_SHARD_CONVERT then
             local BackpackPanel = require("ui.BackpackPanel")
             if BackpackPanel.onActionResult then BackpackPanel.onActionResult(data) end
         end
         return
     end

     -- 登录补发等延迟弹窗（等 LoadingScreen / 离线收益面板关闭后再展示）
     if data.deferredRewardPopup and data.rewards and #data.rewards > 0 then
         pendingDeferredRewardPopup_ = {
             title    = data.popupTitle or "奖励",
             subtitle = data.popupSubtitle,
             rewards  = data.rewards,
         }
         return
     end

     -- AD_CONFIRM 成功时停止重试
     if data.action == Protocol.ACTION_TYPES.AD_CONFIRM and AdManager and AdManager.OnAdConfirmResult then
         AdManager.OnAdConfirmResult(data)
     end
     if data.action == Protocol.ACTION_TYPES.RELIC_REFORGE_CONFIRM then
         finishReforgeConfirmWhenSynced(data.relicId, data.newAffixId)
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
                 armorScroll = "armor_scroll", accessaryScroll = "accessory_scroll",
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
         -- 首通后检查是否有对应的情景对话奖励需要播放
         if M.lastClearedStageId_ then
             local sessionData = PlayerStore.Get("session")
             local heroId = sessionData and sessionData.initialHeroId
             if heroId then
                 local STAGE_HERO_TO_SCENARIO = {
                     ["101"] = { [1]=5,  [2]=6,  [3]=7  }, ["102"] = { [1]=8,  [2]=9,  [3]=10 },
                     ["103"] = { [1]=11, [2]=12, [3]=13 }, ["104"] = { [1]=17, [2]=18, [3]=19 },
                     ["105"] = { [1]=20, [2]=21, [3]=22 }, ["201"] = { [1]=35, [2]=36, [3]=37 },
                     ["204"] = { [1]=44, [2]=45, [3]=46 }, ["205"] = { [1]=51, [2]=52, [3]=53 },
                     ["305"] = { [1]=58, [2]=59, [3]=60 }, ["1305"] = { [1]=55, [2]=56, [3]=57 },
                 }
                 local stageMap = STAGE_HERO_TO_SCENARIO[tostring(M.lastClearedStageId_)]
                 local scenarioId = stageMap and stageMap[heroId]
                 if scenarioId then
                     local claimed = sessionData.claimedScenarios and sessionData.claimedScenarios[tostring(scenarioId)]
                     if not claimed then
                         local configKey = "SCENARIO_" .. scenarioId
                         local config = ScenarioDialogueConfig[configKey]
                         if config then
                             M.pendingScenarioDialogue_ = { config = config, scenarioId = scenarioId }
                         end
                     end
                 end
             end
             M.lastClearedStageId_ = nil
         end
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

     -- 兑换码、邮件、邮件推送
     if (data.redeemAction or data.action == Protocol.ACTION_TYPES.REDEEM_CODE) and RedeemCodePanel.onActionResult then RedeemCodePanel.onActionResult(data) end
     if data.mailAction and MailPanel.onActionResult then MailPanel.onActionResult(data) end
     if data.mailPush and data.mails then
         MailPanel.setMailData(data.mails)
         return
     end
     if data.announcementPush and data.announcements then
         AnnouncementPanel.setAnnouncementData(data.announcements)
         return
     end

     -- 各页面 onActionResult 分发
     if BlacksmithPage.onActionResult then pcall(BlacksmithPage.onActionResult, data) end
     if BackpackPanel.onActionResult then pcall(BackpackPanel.onActionResult, data) end
     if EquipmentDetail.onActionResult then pcall(EquipmentDetail.onActionResult, data) end
     if ChurchPage.onActionResult then pcall(ChurchPage.onActionResult, data) end
     if TavernPage.onActionResult then pcall(TavernPage.onActionResult, data) end
     if ArenaPage.onActionResult then pcall(ArenaPage.onActionResult, data) end
     if ArenaBattleScene.onActionResult then pcall(ArenaBattleScene.onActionResult, data) end
     if DungeonBattleScene.onActionResult then pcall(DungeonBattleScene.onActionResult, data) end
     if ArenaOpponentDialog.onActionResult then pcall(ArenaOpponentDialog.onActionResult, data) end
     if MarketPage.onActionResult then pcall(MarketPage.onActionResult, data) end
     if GuildPage.onActionResult then pcall(GuildPage.onActionResult, data) end
     if GMConsolePanel.onActionResult then pcall(GMConsolePanel.onActionResult, data) end
     if data.action == Protocol.ACTION_TYPES.RELIC_REFORGE and data.newAffixId then
         pcall(RelicReforgePanel.setReforgeResult, data.newAffixId)
     end

     -- 遗物合成结果
     if data.action == Protocol.ACTION_TYPES.RELIC_MERGE and data.relic then
         local r = data.relic
         if batchMerge_.active then
             batchMerge_.results[#batchMerge_.results + 1] = { type = "relic", relicType = r.type, quality = r.quality }
             if #batchMerge_.results >= batchMerge_.expected then
                 RewardPopup.show("合成结果", batchMerge_.results)
                 batchMerge_.active = false; batchMerge_.expected = 0; batchMerge_.results = {}; batchMerge_.timeout = 0
             end
         else
             RewardPopup.show("合成结果", { { type = "relic", relicType = r.type, quality = r.quality } })
         end
     end

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

     -- 遗物锁定：失败时撤销乐观更新；成功时 pushModule 已持久化 locked 字段
     if data.action == Protocol.ACTION_TYPES.RELIC_LOCK and data.relicId then
         local relic = findRelicInModData(PlayerStore.Get("mod_relics"), data.relicId)
         if relic then
             if data.success then
                 if data.locked then
                     relic.locked = true
                 else
                     relic.locked = nil
                 end
             else
                 if relic.locked then
                     relic.locked = nil
                 else
                     relic.locked = true
                 end
                 print("[Client] relic lock failed, reverted optimistic state: "
                     .. tostring(data.reason))
             end
         end
     end

     -- 副本操作
     if DungeonPage.onActionResult then pcall(DungeonPage.onActionResult, data) end

     -- 购买成功
     if data.action == Protocol.ACTION_TYPES.MARKET_BUY and data.rewardType and not data.marketSpecialShown then
         RewardPopup.show("购买成功", { { type = data.rewardType, amount = data.rewardCount or 1 } })
     end
     if data.action == Protocol.ACTION_TYPES.WATCH_PRIVILEGE_AD then
         RewardPopup.show("观看广告奖励", {
             { type = "privilege_point", amount = data.rewardCount or MarketSchema.AD_PRIVILEGE_REWARD_PER_WATCH },
         })
     end
     if data.action == Protocol.ACTION_TYPES.CLAIM_PRIVILEGE_REWARD and data.rewardType then
         RewardPopup.show("里程奖励", { { type = data.rewardType, amount = data.amount or 1 } })
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
         local function fireTutorial()
             if tutorialNotify then TutorialManager.onScenarioClaimed(tutorialNotify.scenarioId) end
         end
         if data.success and data.rewardType == "none" then
             fireTutorial()
         elseif data.success and data.rewardType == "currency" and data.reward then
             local CURRENCY_KEY_TO_POPUP_TYPE = {
                 recruitTicket = "adventure_ticket", sweep_ticket = "sweep_ticket",
                 goldenKey = "golden_key", corruptStone = "corrupt_stone", sacredStone = "sacred_stone",
                 arena_ticket = "arena_ticket", gems = "diamond", gold = "gold", essence = "essence",
                 weaponScroll = "weapon_scroll", offhandScroll = "offhand_scroll",
                 armorScroll = "armor_scroll", accessoryScroll = "accessory_scroll", randomScroll = "random_scroll",
             }
             local key = data.reward.currencyKey; local amount = data.reward.amount or 0
             local popupType = CURRENCY_KEY_TO_POPUP_TYPE[key] or key
             RewardPopup.show("冒险奖励", { { type = popupType, amount = amount } }, { onClose = fireTutorial })
         elseif data.success and data.reward then
             if data.rewardType == "hero" then
                 local heroId = data.reward.heroId; local heroName = data.reward.name or "英雄"
                 local heroQuality = data.reward.quality or 1; local displayQuality = heroQuality + 2
                 local HERO_TO_FOLLOWUP = { [1]=14, [2]=15, [3]=16 }
                 local followUpId = HERO_TO_FOLLOWUP[heroId]
                 local heroConfig = followUpId and ScenarioDialogueConfig["SCENARIO_" .. followUpId]
                 RewardPopup.show("冒险奖励", { { type = "hero", heroId = heroId, name = heroName, quality = displayQuality } }, {
                     onClose = function()
                         fireTutorial()
                         if heroConfig then M.pendingFollowUpDialogue_ = { config = heroConfig } end
                     end
                 })
             elseif data.rewardType == "relic" then
                 RewardPopup.show("冒险奖励", { { type = "relic", relicType = data.reward.relicType, quality = data.reward.quality or 1 } }, { onClose = fireTutorial })
             else
                 RewardPopup.show("冒险奖励", { { type = "equip", templateId = data.reward.templateId, quality = data.reward.quality or 1, level = data.reward.level or 1 } }, { onClose = fireTutorial })
             end
         else
             fireTutorial()
         end
     end

     -- 碎片合成英雄
     if data.action == Protocol.ACTION_TYPES.SYNTHESIZE_HERO then
         if data.success then
             local heroCfg = HeroConfig.get(data.heroId); local hn = heroCfg and heroCfg.name or "英雄"
             local hq = heroCfg and heroCfg.quality or 1
             RewardPopup.show("合成成功", { { type = "hero", heroId = data.heroId, name = hn, quality = hq + 2 } })
         end
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

    -- 特权卡转区：返回选服界面
     if data.action == Protocol.ACTION_TYPES.TRANSFER_PRIVILEGE_CARD and data.success then
         local Client = require("network.Client")
         if Client.transitionToServerSelectAfterTransfer then
             Client.transitionToServerSelectAfterTransfer()
         end
         return
     end

     -- 活动结束后的转出请求在选服界面发起，成功后由服务端重新推送区服列表。
     if data.action == Protocol.ACTION_TYPES.TRANSFER_CLOSED_CHALLENGER_CARD then
         local ServerSelectPanel = require("ui.ServerSelectPanel")
         if ServerSelectPanel.setClosedTransferPending then
             ServerSelectPanel.setClosedTransferPending(false)
         end
         if not data.success and LootBoxPage and LootBoxPage.showToast then
             LootBoxPage.showToast(data.reason or "特权卡转出失败")
         end
         return
     end

     -- 扫荡结果
     if data.action == Protocol.ACTION_TYPES.SWEEP and data.success then
         local rewards = {}
         if (data.gold or 0) > 0 then rewards[#rewards + 1] = { type = "gold", amount = data.gold } end
         local EQUIP_BY_QUALITY = data.equipByQuality or {}
         for q = 5, 1, -1 do
             local cnt = EQUIP_BY_QUALITY[q] or EQUIP_BY_QUALITY[tostring(q)]
             if cnt and cnt > 0 then rewards[#rewards + 1] = { type = "seed", quality = q, amount = cnt } end
         end
         if (data.equipCount or 0) > 0 then LootBox.refreshPage() end
         for scrollField, count in pairs(data.scrollDrops or {}) do
             local SCROLL_MAP = { weaponScroll = "weapon_scroll", offhandScroll = "offhand_scroll", armorScroll = "armor_scroll", accessoryScroll = "accessory_scroll" }
             local rk = SCROLL_MAP[scrollField]
             if rk and count > 0 then rewards[#rewards + 1] = { type = rk, amount = count } end
         end
         RewardPopup.show("扫荡奖励", rewards)
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
     batchMerge_ = {
         active = false,
         expected = 0,
         results = {},
         timeout = 0,
     }
     print("[ClientMsgHandler] session bridge state reset")
 end

 return M
