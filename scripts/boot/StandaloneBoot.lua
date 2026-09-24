-- ============================================================================
-- StandaloneBoot - 单机启动接线（原 Standalone._bootWiring）
-- ============================================================================

local GameState         = require("core.GameState")
local ExpTable          = require("config.ExpTable")
local StageConfig       = require("config.StageConfig")
local DropSystem        = require("systems.DropSystem")
local EquipmentSystem   = require("systems.EquipmentSystem")
local LootBoxSystem     = require("systems.LootBoxSystem")
local ClientDispatcher  = require("runtime.ClientDispatcher")
local TopBar            = require("ui.TopBar")
local BottomNav         = require("ui.BottomNav")
local BattleScene       = require("ui.BattleScene")
local CharacterPanel    = require("ui.CharacterPanel")
local RewardPopup       = require("ui.RewardPopup")
local TownScene         = require("ui.TownScene")
local BlacksmithPage    = require("ui.BlacksmithPage")
local ChurchPage        = require("ui.ChurchPage")
local TavernPage        = require("ui.TavernPage")
local MarketPage        = require("ui.MarketPage")
local LootBox           = require("ui.LootBox")
local LootBoxPage       = require("ui.LootBoxPage")
local PlayerInfoPanel   = require("ui.PlayerInfoPanel")
local MailPanel         = require("ui.MailPanel")
local BattleTriPage     = require("ui.BattleTriPage")
local PlayerStore       = require("core.PlayerStore")
local IntroCutscene     = require("ui.IntroCutscene")
local LocalActionBridge = require("runtime.LocalActionBridge")
local TaskPanel         = require("ui.TaskPanel")
local SignInPanel       = require("ui.SignInPanel")
local BackpackPanel     = require("ui.BackpackPanel")

local M = {}

-- 首通战斗击杀掉落先暂存。通关并入首通奖励；失败保留为「战斗掉落」；挂机仍进遗匣。
local pendingFcSeeds = {}
local pendingFcScrolls = {}

local SCROLL_DROP_TO_REWARD = {
    weaponScroll    = "weapon_scroll",
    offhandScroll   = "offhand_scroll",
    armorScroll     = "armor_scroll",
    accessoryScroll = "accessory_scroll",
    helmetScroll    = "helmet_scroll",
    shoesScroll     = "shoes_scroll",
}

--- 取出暂存掉落；背包满时完整存入遗匣。
---@return table[]
local function takePendingFcRewards()
    local dropSeeds = pendingFcSeeds
    local dropScrolls = pendingFcScrolls
    pendingFcSeeds = {}
    pendingFcScrolls = {}
    local rewards = {}
    local equipData = ClientDispatcher.get("equipment")
    local lootboxData = ClientDispatcher.get("lootbox")
    for _, seed in ipairs(dropSeeds) do
        local equip = EquipmentSystem.generateRandom(seed.level, seed.quality)
        if equip then
            local destination = LootBoxSystem.deliverEquipment(lootboxData, equipData, equip)
            rewards[#rewards + 1] = {
                type       = "equip",
                templateId = equip.templateId,
                quality    = equip.quality,
                level      = equip.level,
                destination = destination,
            }
        else
            LootBoxSystem.addSeed(lootboxData, 0, seed.quality, seed.level)
        end
    end
    for field, amount in pairs(dropScrolls) do
        local getter = GameState["get" .. field:sub(1,1):upper() .. field:sub(2)]
        local setter = GameState["set" .. field:sub(1,1):upper() .. field:sub(2)]
        if getter and setter and amount > 0 then
            setter(getter() + amount)
            local rewardKey = SCROLL_DROP_TO_REWARD[field]
            if rewardKey then
                rewards[#rewards + 1] = { type = rewardKey, amount = amount }
            end
        end
    end
    if #dropSeeds > 0 then
        ClientDispatcher.notifySubscribers("equipment")
        ClientDispatcher.notifySubscribers("lootbox")
    end
    if #rewards > 0 then
        print("[Standalone] 结算暂存掉落 n=" .. tostring(#rewards))
    end
    return rewards
end

local function showKeptDrops(title)
    if #pendingFcSeeds == 0 then
        local hasScroll = false
        for _ in pairs(pendingFcScrolls) do
            hasScroll = true
            break
        end
        if not hasScroll then return end
    end
    local rewards = takePendingFcRewards()
    if #rewards > 0 then
        print("[Standalone] " .. title .. " 显示掉落 n=" .. tostring(#rewards))
        RewardPopup.show(title, rewards, { row = 1, cascade = false })
    end
end

---@param rt table { vg: userdata, localSendAction: fun(action:string, params:table|nil), setLocalBridgeReady: fun() }
function M.run(rt)
    local vg = rt.vg
    local localSendAction = rt.localSendAction
    local localBridgeReady_ = false

    -- 5.1 阵容变更回调：角色面板出战变动 → 同步战斗画面 → 重载关卡 → 更新 TopBar 战力
    -- [三队并行] 回调携带 teamIdx：队1 同步战斗画面；队2/3 编队先本地生效（并行战斗 Phase 3 接入）
    CharacterPanel.setOnTeamChanged(function(teamIdx)
        teamIdx = tonumber(teamIdx) or 1
        local team = CharacterPanel.getDeployedTeam(teamIdx)
        local deployedIds = {}
        for _, unit in ipairs(team) do
            if unit.heroId then
                deployedIds[#deployedIds + 1] = unit.heroId
            end
        end
        if localBridgeReady_ then
            localSendAction(require("shared.Protocol").ACTION_TYPES.SET_TEAM, {
                teamIdx = teamIdx,
                heroIds = deployedIds,
            })
        end
        if teamIdx ~= 1 then
            print("[Standalone] 队伍" .. teamIdx .. " 编队变更")
            return
        end
        TopBar.setTotalPower(CharacterPanel.getTotalPower())
        if #team > 0 then
            BattleScene.setAllies(team)
            BattleScene.reloadStage()
            print("[Standalone] 阵容变更，同步 " .. #team .. " 个英雄到战斗，重载关卡")
        else
            print("[Standalone] 阵容变更，当前无出战英雄")
        end
    end)

    -- 5.2 击杀奖励回调：经验平分给每个上场远征队员，金币/远征等级经验照常
    -- [三栏并行] 提取为局部函数，BattleScene（栏1）与 BattleTriPage（栏2/3）共用
    local handleKillRewards = function(data)
        local baseExp  = data.expReward  or 0
        local baseGold = data.goldReward or 0
        local heroIds  = data.heroIds    or {}
        local allyCount = data.allyCount or 1

        -- 金币直接加
        if baseGold > 0 then
            GameState.setGold(GameState.getGold() + baseGold)
        end

        -- 玩家（远征等级）经验 = 怪物基础经验（不乘倍率）
        if baseExp > 0 then
            GameState.addExp(baseExp)
        end

        -- 远征队员经验：总池 = 基础经验 × 倍率，平分给每个上场英雄
        if baseExp > 0 and #heroIds > 0 then
            local expMult = ExpTable.getHeroCountExpMult(allyCount)
            local totalExp = baseExp * expMult
            local perHeroExp = math.floor(totalExp / #heroIds + 0.5)
            if perHeroExp > 0 then
                for _, hid in ipairs(heroIds) do
                    CharacterPanel.addHeroExp(hid, perHeroExp)
                end
                -- 升级后刷新战斗单位属性（同步 _pendingLevel + _pendingSnapshot）
                if BattleScene.refreshAllyStats then
                    BattleScene.refreshAllyStats()
                end
            end
        end
    end
    BattleScene.setOnEnemyKill(handleKillRewards)
    BattleTriPage.setOnKill(handleKillRewards)  -- [三栏并行] 栏2/3 击杀奖励同源

    -- 5.15 城镇铁匠铺点击 → 打开铁匠铺界面
    TownScene.setOnSmithClick(function()
        BlacksmithPage.init(vg)
        BlacksmithPage.open()
    end)
    -- 城郊礼拜堂点击 → 打开教堂界面（转职/神器）
    TownScene.setOnChurchClick(function()
        ChurchPage.init(vg)
        ChurchPage.open()
    end)
    -- 终焉古树点击 → 打开独立天赋页
    TownScene.setOnTreeClick(function()
        local TalentPage = require("ui.TalentPage")
        TalentPage.init(vg)
        TalentPage.open()
    end)
    -- 5.16 城镇酒馆点击 → 打开酒馆界面
    TownScene.setOnTavernClick(function()
        TavernPage.init(vg)
        TavernPage.open()
    end)
    -- 5.18 城镇市场点击 → 打开市场界面
    TownScene.setOnMarketClick(function()
        MarketPage.init(vg)
        MarketPage.open()
    end)
    -- 5.25 城镇仓库点击 → 打开背包（横屏全窗模态）
    TownScene.setOnWarehouseClick(function()
        BackpackPanel.open("left")
    end)
    TownScene.setOnLootBoxClick(function()
        LootBox.openPage()
    end)

    -- 5.24 装备数据初始化（Standalone 模式下 ClientDispatcher 不会收到 Server 推送）
    if not ClientDispatcher.get("equipment") then
        local initEquipData = { inventory = {}, equipped = {}, nextSeq = 1 }
        -- 通过 handleStateUpdate 注入，触发订阅者通知
        local cjson = cjson
        ClientDispatcher.handleStateUpdate(cjson.encode({
            modules = { equipment = initEquipData }
        }))
        print("[Standalone] 初始化 equipment 数据")
    end

    -- 5.241 战利品缓冲区初始化
    if not ClientDispatcher.get("lootbox") then
        local initLootboxData = { seeds = {} }
        local cjson = cjson
        ClientDispatcher.handleStateUpdate(cjson.encode({
            modules = { lootbox = initLootboxData }
        }))
        print("[Standalone] 初始化 lootbox 数据")
    end

    -- 5.242 heroes 初始状态注入：Standalone 模式无 Server 推送，右面板"我的远征队员"
    -- （CharacterPanel.ownedSet）依赖 heroes 模块状态；默认大狗嚼 Lv1 已部署
    if not ClientDispatcher.get("heroes") then
        local cjson = cjson
        ClientDispatcher.handleStateUpdate(cjson.encode({
            modules = { heroes = {
                roster = { [1] = { level = 1, exp = 0, shards = 0 } },
                deployed = { 1 },
            } }
        }))
        print("[Standalone] 初始化 heroes 数据（大狗嚼 Lv1）")
    end

    PlayerStore.Subscribe("signin", function(data, _fieldKey)
        if data then SignInPanel.setSignInData(data) end
    end)
    PlayerStore.Subscribe("task", function(data, _fieldKey)
        if data then TaskPanel.setTaskData(data) end
    end)
    PlayerStore.Subscribe("market", function(data, _fieldKey)
        if data then MarketPage.setMarketData(data) end
    end)

    LocalActionBridge.init()
    localBridgeReady_ = true
    if rt.setLocalBridgeReady then rt.setLocalBridgeReady() end
    do
        local mailData = ClientDispatcher.get("mail")
        if mailData then
            local okMail, MailService = pcall(require, "rules.mail.MailService")
            if okMail and MailService.BuildMailList then
                MailPanel.setMailData(MailService.BuildMailList(1))
            end
        end
    end

    -- 订阅 lootbox 数据变化 → 刷新 LootBox UI
    ClientDispatcher.subscribe("lootbox", function(data, moduleName)
        LootBoxSystem.consolidateSeeds(data) -- 合并旧存档中按 stageId 分开的同类种子
        -- 版本兼容：clamp 旧版高等级种子到当前关卡怪物等级
        local capStageId = BattleScene.getMaxStageId() or BattleScene.getCurrentStageId()
        local capEntry = capStageId and StageConfig.getStage(capStageId)
        if capEntry and capEntry.monsterLevel and capEntry.monsterLevel > 0 then
            local cap = capEntry.monsterLevel
            LootBoxSystem.levelCap = cap
            local fixed = false
            for _, seed in ipairs(data.seeds or {}) do
                if not seed.equip and seed.level and seed.level > cap then
                    seed.level = cap
                    fixed = true
                end
            end
            if fixed then
                LootBoxSystem.consolidateSeeds(data) -- 降级后再合并重复项
                print("[Standalone] lootbox seeds clamped to Lv." .. cap)
            end
        end
        LootBox.updateSeedData(data)
        print("[Standalone] lootbox data updated, seedCount=" .. LootBoxSystem.getTotalCount(data))
    end)
    -- 存档恢复早于订阅注册，首次打开也必须能看到已保存的遗匣。
    LootBox.updateSeedData(ClientDispatcher.get("lootbox"))

    -- 5.245 击杀掉落：挂机进遗匣；首通暂存，通关后并入首通奖励
    BattleScene.setOnEnemyDrop(function(data)
        local stageEntry = StageConfig.getStage(data.stageId)
        if not stageEntry then return end
        local quality = DropSystem.rollKillDrop(stageEntry)
        local scrollType = DropSystem.rollScrollDrop(stageEntry)
        if data.isFirstClear then
            if quality then
                local level = stageEntry.monsterLevel or 1
                pendingFcSeeds[#pendingFcSeeds + 1] = { quality = quality, level = level }
                print("[Standalone] 首通掉落暂存: q=" .. quality .. " lv=" .. level
                    .. " pending=" .. #pendingFcSeeds)
            end
            if scrollType then
                pendingFcScrolls[scrollType] = (pendingFcScrolls[scrollType] or 0) + 1
                print("[Standalone] 首通卷轴暂存: type=" .. scrollType
                    .. " n=" .. tostring(pendingFcScrolls[scrollType]))
            end
            return
        end
        -- 装备掉落（挂机）
        if quality then
            local level = stageEntry.monsterLevel or 1
            local lootboxData = ClientDispatcher.get("lootbox")
            if lootboxData then
                LootBoxSystem.addSeed(lootboxData, data.stageId, quality, level)
                LootBox.addSeedHint(quality, level)
                LootBox.updateSeedData(lootboxData)
                print("[Standalone] seed added: q=" .. quality .. " lv=" .. level
                    .. " total=" .. LootBoxSystem.getTotalCount(lootboxData))
            end
        end
        -- 卷轴掉落（挂机直接加入货币）
        if scrollType then
            local getter = GameState["get" .. scrollType:sub(1,1):upper() .. scrollType:sub(2)]
            local setter = GameState["set" .. scrollType:sub(1,1):upper() .. scrollType:sub(2)]
            if getter and setter then
                local current = getter()
                local nextValue = 1
                if type(current) == "number" then
                    nextValue = current + 1
                end
                setter(nextValue)
                print("[Standalone] scroll drop: type=" .. scrollType)
            end
        end
    end)

    BattleScene.setOnAllDead(function()
        showKeptDrops("战斗掉落")
    end)

    BattleScene.setOnStageLoaded(function(stageId, _)
        if #pendingFcSeeds == 0 then
            local hasScroll = false
            for _ in pairs(pendingFcScrolls) do
                hasScroll = true
                break
            end
            if not hasScroll then return end
        end
        print("[Standalone] 离开关卡仍保留掉落 stage=" .. tostring(stageId))
        showKeptDrops("战斗掉落")
    end)

    -- 遗匣领取统一刷新：装备先入包，再显示实际到账的内容。
    local function claimLoot(seedIndex, quality)
        local lootboxData = ClientDispatcher.get("lootbox")
        local equipData = ClientDispatcher.get("equipment")
        if not lootboxData or not equipData then return end
        ---@type table[]
        local claimed = {}
        local bagFull = false
        if seedIndex then
            claimed, bagFull = LootBoxSystem.claimGroup(lootboxData, seedIndex, equipData)
        else
            claimed, bagFull = LootBoxSystem.claimAll(lootboxData, equipData, quality)
        end
        ClientDispatcher.notifySubscribers("lootbox")
        if #claimed > 0 then
            ClientDispatcher.notifySubscribers("equipment")
            TopBar.setTotalPower(CharacterPanel.getTotalPower())
            BattleScene.refreshAllyStats()
            local rewards = {}
            for _, equip in ipairs(claimed) do
                rewards[#rewards + 1] = {
                    type = "equip", templateId = equip.templateId,
                    quality = equip.quality, level = equip.level,
                }
            end
            RewardPopup.show("遗匣领取", rewards, {
                subtitle = bagFull and "背包已满，其余装备保留在遗匣" or nil,
            })
        elseif bagFull then
            LootBoxPage.showToast("背包已满，其余装备保留在遗匣")
        else
            LootBoxPage.showToast("遗匣为空")
        end
        print("[Standalone] 遗匣领取: claimed=" .. #claimed
            .. " remaining=" .. LootBoxSystem.getTotalCount(lootboxData))
    end
    LootBox.setOnClaimAll(function(quality) claimLoot(nil, quality) end)
    LootBox.setOnClaimOne(claimLoot)

    local function decomposeLoot(seedIndex, quality)
        local lootboxData = ClientDispatcher.get("lootbox")
        if not lootboxData then return end
        local essence, pieces
        if seedIndex then
            essence, pieces = LootBoxSystem.decomposeOne(lootboxData, seedIndex)
        else
            essence, pieces = LootBoxSystem.decomposeAll(lootboxData, quality)
        end
        if pieces <= 0 then return end
        GameState.setEssence(GameState.getEssence() + essence)
        ClientDispatcher.notifySubscribers("lootbox")
        if essence > 0 then
            RewardPopup.show("回收奖励", { { type = "essence", amount = essence } })
        end
    end
    LootBox.setOnDecomposeAll(function(quality) decomposeLoot(nil, quality) end)
    LootBox.setOnDecomposeOne(decomposeLoot)

    -- 5.249 自动分解设置回调：打开铁匠铺分解弹窗
    LootBox.setOnAutoDecompose(function()
        LootBoxPage.hide()
        BottomNav.setSelectedIndex(4)
        BlacksmithPage.openToAutoDecompose()
    end)

    -- 5.24 轮回回调：倒计时结束 → 播放开场动画 → 完成关卡加载
    BattleScene.setOnReincarnate(function(data)
        print("[Standalone] reincarnation triggered, starting intro cutscene (difficulty "
            .. tostring(data.fromDifficulty) .. " → " .. tostring(data.toDifficulty) .. ")")
        IntroCutscene.reset()
        IntroCutscene.start(function()
            print("[Standalone] reincarnation intro finished, completing stage load")
            BattleScene.completeReincarnation()
        end)
    end)

    -- 5.25 首通奖励回调：本地计算首通金币+装备，弹出 RewardPopup
    BattleScene.setOnFirstClear(function(clearedStageId)
        local stageEntry = StageConfig.getStage(clearedStageId)
        if not stageEntry then return end

        local rewards = {}
        -- 首通金币
        local fcGold = stageEntry.fcGold or 0
        if fcGold > 0 then
            GameState.setGold(GameState.getGold() + fcGold)
            rewards[#rewards + 1] = { type = "gold", amount = fcGold }
        end
        -- 首通经验
        local fcExp = stageEntry.fcExp or 0
        if fcExp > 0 then
            GameState.addExp(fcExp)
        end
        -- 首通钻石
        local fcDiamond = stageEntry.fcDiamond or 0
        if fcDiamond > 0 then
            GameState.setGems(GameState.getGems() + fcDiamond)
            rewards[#rewards + 1] = { type = "diamond", amount = fcDiamond }
        end
        -- 首通精粹
        local fcEssence = stageEntry.fcEssence or 0
        if fcEssence > 0 then
            GameState.setEssence(GameState.getEssence() + fcEssence)
            rewards[#rewards + 1] = { type = "essence", amount = fcEssence }
        end
        -- 首通奥术粉尘
        local fcArcaneDust = stageEntry.fcArcaneDust or 0
        if fcArcaneDust > 0 then
            GameState.setArcaneDust(GameState.getArcaneDust() + fcArcaneDust)
            rewards[#rewards + 1] = { type = "arcane_dust", amount = fcArcaneDust }
        end
        -- 首通装备与击杀掉落共用投递规则，满包时完整入匣。
        local fcEquips = DropSystem.generateFirstClearEquips(stageEntry)
        local equipData = ClientDispatcher.get("equipment")
        local lootboxData = ClientDispatcher.get("lootbox")
        for _, equip in ipairs(fcEquips) do
            local destination = LootBoxSystem.deliverEquipment(lootboxData, equipData, equip)
            rewards[#rewards + 1] = {
                type       = "equip",
                templateId = equip.templateId,
                quality    = equip.quality,
                level      = equip.level,
                destination = destination,
            }
        end
        if #fcEquips > 0 then
            ClientDispatcher.notifySubscribers("equipment")
            ClientDispatcher.notifySubscribers("lootbox")
        end
        -- 首通卷轴（每个独立随机，按类型聚合）
        local scrollReward = DropSystem.generateFirstClearScrolls(stageEntry)
        if scrollReward and scrollReward.scrolls then
            local SCROLL_TO_REWARD = {
                weaponScroll    = "weapon_scroll",
                offhandScroll   = "offhand_scroll",
                armorScroll     = "armor_scroll",
                accessoryScroll = "accessory_scroll",
                helmetScroll    = "helmet_scroll",
                shoesScroll     = "shoes_scroll",
            }
            for field, amount in pairs(scrollReward.scrolls) do
                local getter = GameState["get" .. field:sub(1,1):upper() .. field:sub(2)]
                local setter = GameState["set" .. field:sub(1,1):upper() .. field:sub(2)]
                if getter and setter then
                    local current = getter()
                    local base = 0
                    if type(current) == "number" then
                        base = math.floor(current)
                    end
                    local add = 0
                    if type(amount) == "number" then
                        add = math.floor(amount)
                    end
                    setter(math.floor(base + add))
                    local rewardKey = SCROLL_TO_REWARD[field]
                    if rewardKey then
                        rewards[#rewards + 1] = {
                            type   = rewardKey,
                            amount = amount,
                        }
                    end
                    print("[Standalone] 首通卷轴: type=" .. field .. " amount=" .. tostring(amount))
                end
            end
        end
        -- 噩梦及以后各章 X-5 首通：黄金钥匙 ×2
        local fcGoldenKey = StageConfig.getFirstClearGoldenKey(clearedStageId, stageEntry)
        if fcGoldenKey > 0 then
            GameState.setGoldenKey(GameState.getGoldenKey() + fcGoldenKey)
            rewards[#rewards + 1] = { type = "golden_key", amount = fcGoldenKey }
        end
        -- 单机预览：与挑战者首通规则一致（X-5 腐化石；相对 4/8/12/16/20 章 X-5 神圣石）
        local fcCorruptStone = StageConfig.getFirstClearCorruptStone
            and StageConfig.getFirstClearCorruptStone(clearedStageId, stageEntry) or 0
        if fcCorruptStone > 0 then
            GameState.setCorruptStone(GameState.getCorruptStone() + fcCorruptStone)
            rewards[#rewards + 1] = { type = "corrupt_stone", amount = fcCorruptStone }
        end
        local fcSacredStone = StageConfig.getFirstClearSacredStone
            and StageConfig.getFirstClearSacredStone(clearedStageId, stageEntry) or 0
        if fcSacredStone > 0 then
            GameState.setSacredStone(GameState.getSacredStone() + fcSacredStone)
            rewards[#rewards + 1] = { type = "sacred_stone", amount = fcSacredStone }
        end
        -- 本关击杀掉落并入首通奖励；超出背包容量的装备标记为已入遗匣。
        local dropRewards = takePendingFcRewards()
        for _, item in ipairs(dropRewards) do
            rewards[#rewards + 1] = item
        end
        if #rewards > 0 then
            print("[Standalone] 首通奖励: gold=" .. tostring(fcGold)
                .. " diamond=" .. tostring(fcDiamond)
                .. " equips=" .. tostring(#fcEquips)
                .. " killDrops=" .. tostring(#dropRewards))
            RewardPopup.show("首通奖励", rewards, { row = 1 })  -- [三行并行] 卡在行1内显示
        end
    end)

    -- 5.3 初始阵容同步/关卡重载已拆到 boot 队列独立步 firstStage
    --     （loadStage 内生成敌人+重置战斗，原与全部接线同帧执行会撑爆帧预算）

    -- 5.3 本地昵称。不读 clientCloud / lobby / GetUserNickname。
    local player = ClientDispatcher.get("player")
    local localName = player and player.name or nil
    if not localName or localName == "" then
        localName = GameState.getName()
    end
    if not localName or localName == "" then
        localName = "玩家"
    end
    TopBar.setPlayerName(localName)
    PlayerInfoPanel.setPlayerName(localName)
    PlayerInfoPanel.setUID("本地")
    print("[Standalone] 本地昵称: " .. tostring(localName))

    print("[Standalone] boot wiring done")

end

return M
