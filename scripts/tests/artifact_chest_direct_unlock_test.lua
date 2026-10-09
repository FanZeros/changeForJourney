-- 神器宝箱直接开放回归：真实抽取服务/Handler/面板，内存夹具不读写玩家存档。
local assertions = 0
local function eq(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end

function Start()
    local restores = {}
    local function replace(owner, key, value)
        local old = owner[key]
        restores[#restores + 1] = function() owner[key] = old end
        owner[key] = value
    end
    local ok, err = pcall(function()
        local PDM = require("rules.character.PlayerDataManager")
        local Schema = require("shared.artifact.ArtifactSchema")
        local Defs = require("shared.artifact.ArtifactDefs")
        local Service = require("rules.artifact.ArtifactService")
        local Handler = require("rules.artifact.ArtifactHandler")
        local Protocol = require("shared.Protocol")
        local TaskService = require("rules.task.TaskService")
        local PlayerStore = require("core.PlayerStore")
        local GameState = require("core.GameState")
        local DrawUtil = require("core.DrawUtil")
        local BF = require("systems.ButtonFeedback")
        local uid, now = 987654, 1791021600
        local today = math.floor((now + 28800) / 86400)
        ---@type table
        local modules = {}
        local dirty, taskDraws, flushes = 0, 0, 0
        replace(os, "time", function() return now end)
        replace(PDM, "GetModule", function(_, name) return modules[name] end)
        replace(PDM, "MarkDirty", function() dirty = dirty + 1 end)
        replace(PDM, "FlushImmediate", function() flushes = flushes + 1 end)
        replace(TaskService, "UpdateProgress", function(_, event, count)
            eq(event, "artifact_draw", "抽取任务事件不变")
            taskDraws = taskDraws + count
        end)
        replace(PlayerStore, "Get", function(name) return modules[name] end)
        replace(GameState, "getGoldenKey", function() return modules.currency.goldenKey end)
        replace(GameState, "getGems", function() return modules.currency.gems end)
        local function reset(battle, keys, gems, size)
            modules = {
                battle = battle,
                player = { level = 1 },
                currency = { goldenKey = keys or 0, gems = gems or 0, gold = 12345 },
                artifacts = Schema.Fields.artifacts.getDefault(),
            }
            for i = 1, size or 0 do
                modules.artifacts.bag[i] = { id = tostring(i), artifactId = 1, quality = 1, valueRatio = 5000 }
            end
            modules.artifacts.nextId = (size or 0) + 1
            dirty, taskDraws, flushes = 0, 0, 0
        end
        local function reject(count, payment, message)
            local data = modules.artifacts
            local bagSize, total, freeDay = #data.bag, data.totalDraws, data.dailyFreeDrawDayId
            local keys, gems = modules.currency.goldenKey, modules.currency.gems
            local d, tasks, f = dirty, taskDraws, flushes
            local success, reason = Service.Draw(uid, count, payment)
            eq(success, false, message .. "拒绝")
            eq(#data.bag, bagSize, message .. "不发神器")
            eq(data.totalDraws, total, message .. "不推进抽数")
            eq(data.dailyFreeDrawDayId, freeDay, message .. "不消耗免费次数")
            eq(modules.currency.goldenKey, keys, message .. "不扣钥匙")
            eq(modules.currency.gems, gems, message .. "不扣黑晶")
            eq(dirty, d, message .. "不标脏")
            eq(taskDraws, tasks, message .. "不推进任务")
            eq(flushes, f, message .. "不请求落盘")
            assert(reason and #reason > 0, message .. "必须有拒绝原因")
        end

        -- nil/普通/噩梦边界/旧档字符串键均不再构成宝箱解锁条件。
        local progressCases = {
            { label = "无战斗模块" },
            { label = "空进度", battle = {} },
            { label = "普通新档", battle = { currentStageId = 101, maxStageId = 101 } },
            { label = "噩梦之前", battle = { currentStageId = 4699, maxStageId = 4699 } },
            { label = "抵达噩梦", battle = { currentStageId = 4701, maxStageId = 4701 } },
            { label = "旧档字符串进度", battle = { currentStageId = "101", maxStageId = "101" } },
        }
        for _, case in ipairs(progressCases) do
            reset(case.battle)
            local response = Handler.actionHandlers[Protocol.ACTION_TYPES.ARTIFACT_DRAW](uid,
                { count = 1, payType = "free_daily" })
            eq(response.success, true, case.label .. "可直接抽取")
            eq(response.action, Protocol.ACTION_TYPES.ARTIFACT_DRAW, "Handler回包动作不变")
            eq(#modules.artifacts.bag, 1, case.label .. "获得一件神器")
            eq(modules.artifacts.totalDraws, 1, case.label .. "抽数正确")
            eq(modules.artifacts.dailyFreeDrawDayId, today, case.label .. "记录今日免费")
            eq(modules.currency.gems, 0, case.label .. "免费不扣黑晶")
            eq(modules.currency.goldenKey, 0, case.label .. "免费不扣钥匙")
            eq(modules.currency.gold, 12345, case.label .. "神器单抽不赠金币")
            eq(taskDraws, 1, case.label .. "只推进一次任务")
            reject(1, "free_daily", case.label .. "当天重复免费")
            now = now + 86400
            eq(Service.Draw(uid, 1, "free_daily"), true, case.label .. "次日恢复免费")
            now = now - 86400
        end
        reset({ maxStageId = 101 })
        reject(10, "free_daily", "免费十连")
        reject(1, "key", "钥匙不足")
        reject(1, "diamond", "黑晶不足")
        reject(2, "key", "非法抽数")
        reset({}, 10, 100)
        local success, _, result = Service.Draw(uid, 10, "key")
        assert(success and result, "抽取成功必须返回奖励")
        eq(success, true, "低进度钥匙十连成功")
        eq(result.keysUsed, 10, "十连消耗十把钥匙")
        eq(modules.currency.goldenKey, 0, "十连钥匙余额正确")
        eq(modules.currency.gems, 100, "钥匙十连不扣黑晶")
        eq(modules.currency.gold, 12345, "神器十连不赠金币")
        eq(#modules.artifacts.bag, 10, "十连获得十件")
        eq(modules.artifacts.drawStats.ten, 1, "十连统计正确")
        eq(taskDraws, 10, "十连任务计数正确")
        reset({}, 3, 1050)
        success, _, result = Service.Draw(uid, 10, "diamond")
        assert(success and result, "抽取成功必须返回奖励")
        eq(success, true, "低进度混合支付成功")
        eq(result.keysUsed, 3, "优先使用已有钥匙")
        eq(result.diamondCost, 7 * Defs.KEY_DIAMOND_PRICE, "只补购缺少的七把")
        eq(modules.currency.gems, 0, "补购黑晶余额正确")
        eq(modules.currency.goldenKey, 0, "补购钥匙余额正确")
        reset({}, 3, 1049)
        reject(10, "diamond", "补购差一黑晶")

        for _, boundary in ipairs({
            { size = 299, count = 1, allowed = true },
            { size = 300, count = 1, allowed = false },
            { size = 290, count = 10, allowed = true },
            { size = 291, count = 10, allowed = false },
        }) do
            reset({}, 10, 6000, boundary.size)
            if boundary.allowed then
                eq(Service.Draw(uid, boundary.count, "key"), true, "容量边界可抽 " .. boundary.size)
                eq(#modules.artifacts.bag, 300, "恰好装满300件")
            else
                reject(boundary.count, "key", "容量超限 " .. boundary.size)
            end
        end
        reset({}, 0, 0, 300)
        reject(1, "free_daily", "满包免费单抽")
        -- 所有神器抽取独立随机，旧计数、免费、十连与高级档位均不强制品质。
        local originalRandom = math.random
        local forcedQualityRoll = 1
        replace(math, "random", function(a, b)
            if a == 1 and b == 10000 then return forcedQualityRoll end
            if a == nil then return originalRandom() end
            if b == nil then return originalRandom(a) end
            return originalRandom(a, b)
        end)
        for _, chestType in ipairs({ "normal", "advanced" }) do
            local cumulative = 0
            for _, rate in ipairs(Defs.getChest(chestType).rates) do
                for _, roll in ipairs({ cumulative + 1, cumulative + rate.weight }) do
                    forcedQualityRoll = roll
                    reset({ clearedStages = { ["2305"] = true } }, 5)
                    modules.artifacts.pityRare, modules.artifacts.pityEpic = 19, 99
                    success, _, result = Service.Draw(uid, 1, "key", chestType)
                    assert(success and result, "档位边界必须抽取成功")
                    eq(result.artifacts[1].quality, rate.quality, chestType .. "精确概率区间 " .. roll)
                    eq(result.pityRare, 0, "回包没有保底进度")
                    eq(#result.pityHits, 0, "没有保底命中")
                    eq(modules.artifacts.pityRare, 19, "旧稀有计数不推进")
                    eq(modules.artifacts.pityEpic, 99, "旧史诗计数不推进")
                end
                cumulative = cumulative + rate.weight
            end
            eq(cumulative, 10000, "档位概率总和100%")
            forcedQualityRoll = 1
            reset({ maxStageId = 2401 }, 50)
            modules.artifacts.pityRare, modules.artifacts.pityEpic = 20000, 20000
            success, _, result = Service.Draw(uid, 10, "key", chestType)
            assert(success and result, "十连必须成功")
            for _, artifact in ipairs(result.artifacts) do eq(artifact.quality, 1, "十连不保底") end
            eq(modules.artifacts.drawStats.byChest[chestType], 10, "分档统计正确")
        end
        forcedQualityRoll = 1
        reset({ maxStageId = 101 })
        modules.artifacts.pityRare, modules.artifacts.pityEpic = 19, 99
        success, _, result = Service.Draw(uid, 1, "free_daily")
        assert(success and result, "免费必须成功")
        eq(result.artifacts[1].quality, 1, "免费单抽也不触发保底")
        math.random = originalRandom

        for _, gate in ipairs({
            { battle = {}, unlocked = false },
            { battle = { maxStageId = 2305 }, unlocked = false },
            { battle = { maxStageId = 2305, clearedStages = { [2305] = true } }, unlocked = true },
            { battle = { maxStageId = "2305", clearedStages = { ["2305"] = true } }, unlocked = true },
            { battle = { maxStageId = 999 }, unlocked = true },
            { battle = { maxStageId = "2401" }, unlocked = true },
            { battle = { maxStageId = 1999 }, unlocked = true },
            { battle = { maxStageId = 9999999 }, unlocked = false },
            { battle = { maxStageId = 101, currentStageId = 2401 }, unlocked = false },
        }) do
            reset(gate.battle, 5, 750)
            eq(Defs.isChestUnlocked("advanced", gate.battle), gate.unlocked, "高级23-5通关边界")
            local beforeKeys, beforeGems = modules.currency.goldenKey, modules.currency.gems
            local response = Handler.actionHandlers[Protocol.ACTION_TYPES.ARTIFACT_DRAW](uid,
                { count = 1, payType = "key", chestType = "advanced" })
            eq(response.success, gate.unlocked, "Handler权威高级门槛")
            if gate.unlocked then eq(response.keysUsed, 5, "高级每次5把同种钥匙")
            else
                eq(#modules.artifacts.bag, 0, "未解锁不发奖")
                eq(modules.currency.goldenKey, beforeKeys, "未解锁不扣钥匙")
                eq(modules.currency.gems, beforeGems, "未解锁不扣钻石")
            end
        end
        reset({ maxStageId = 2401 }, 0, 750)
        success, _, result = Service.Draw(uid, 1, "diamond", "advanced")
        assert(success and result, "高级纯钻支付成功")
        eq(result.diamondCost, 750, "高级单抽750钻")
        eq(modules.currency.gems, 0, "高级750钻余额正确")
        reset({ maxStageId = 2401 }, 2, 450)
        success, _, result = Service.Draw(uid, 1, "diamond", "advanced")
        assert(success and result, "高级混合支付成功")
        eq(result.keysUsed, 2, "高级消耗已有2把")
        eq(result.diamondCost, 450, "高级补齐3把450钻")
        reset({ maxStageId = 2401 }, 0, 749)
        eq(Service.Draw(uid, 1, "diamond", "advanced"), false, "高级差1钻不够")
        eq(modules.currency.gems, 749, "高级不足不扣费")
        reset({ maxStageId = 2401 }, 50, 7500)
        eq(Service.Draw(uid, 1, "free_daily", "advanced"), false, "高级不能领取普通免费")
        eq(Service.Draw(uid, 1, "diamond", "invalid"), false, "未知档位不降级普通")
        eq(Service.Draw(uid, 1, "invalid", "normal"), false, "未知支付方式拒绝")
        success, _, result = Service.Draw(uid, 10, "key", "advanced")
        assert(success and result, "高级十连必须成功")
        eq(result.keysUsed, 50, "高级十连50把")
        eq(result.chestType, "advanced", "回包保留档位")

        -- 生成失败不能留下前面成功的神器，免费标记与付费资源都不改变。
        local originalRollId = Defs.rollArtifactId
        local creates = 0
        replace(Defs, "rollArtifactId", function(quality)
            creates = creates + 1
            if creates == 2 then return nil end
            return originalRollId(quality)
        end)
        reset({}, 10, 1500)
        reject(10, "diamond", "第二件生成失败回滚整批")
        eq(modules.artifacts.nextId, 1, "失败不推进实例序列")
        Defs.rollArtifactId = originalRollId

        -- 压缩旧档往返不添加解锁字段，不重置已用免费次数、实例和装配。
        local saved = {
            av = 1, b = { { 7, 1, 2, 5678 } }, et = { ["1"] = { ["1"] = { ["1"] = 7 } } },
            n = 8, r = 11, p = 51, t = 71,
            s = { total = 71, single = 1, ten = 7, byQuality = { ["2"] = 71 }, byArtifactId = { ["1"] = 71 } },
            df = today,
        }
        Schema.normalizeModule(saved)
        local lean = Schema.dehydrateModule(saved)
        local restored = cjson.decode(cjson.encode(lean))
        Schema.normalizeModule(restored)
        eq(restored.bag[1].id, "7", "旧档实例ID保留")
        eq(restored.bag[1].valueRatio, 5678, "旧档数值保留")
        eq(Schema.getEquippedId(restored, 1, 1, 1), "7", "旧档装配保留")
        eq(restored.pityRare, 11, "旧档稀有保底保留")
        eq(restored.pityEpic, 51, "旧档史诗保底保留")
        eq(restored.totalDraws, 71, "旧档总抽数保留")
        eq(restored.drawStats.ten, 7, "旧档十连统计保留")
        eq(restored.dailyFreeDrawDayId, today, "旧档免费日标记保留")
        reset({ maxStageId = 101 }, 1)
        modules.artifacts = restored
        reject(1, "free_daily", "旧档已用免费")
        eq(Service.Draw(uid, 1, "key"), true, "旧低进度档无需迁移即可付费抽取")
        eq(modules.battle.maxStageId, 101, "不伪造噩梦进度")
        eq(Service.Equip(uid, "7", 1, 1, 1), false, "Lv1仍不能装配神器")
        modules.player.level = 30
        eq(Service.Equip(uid, "7", 1, 1, 1), true, "Lv30首格装配不变")
        eq(Service.Equip(uid, "7", 1, 2, 1), false, "Lv30次格仍锁")
        modules.player.level = 60
        eq(Service.Equip(uid, "7", 1, 2, 1), true, "Lv60次格装配不变")
        eq(Service.Equip(uid, "7", 1, 1, 2), false, "低进度队2仍锁")

        -- 传说保留完整数值、装配引用与养成流程；无需新增品质编号或美术资产。
        local legendary = { av = 1, b = { { 90, 2, 5, 7000, 8000 } },
            et = { ["1"] = { ["1"] = { ["1"] = 90 } } }, n = 1, r = 19, p = 99, df = today }
        Schema.normalizeModule(legendary)
        eq(legendary.bag[1].quality, 5, "传说品质旧档保留")
        eq(legendary.bag[1].value, 77.5, "传说主属性比例还原")
        eq(legendary.bag[1].threatClearValue, 62, "传说次属性比例还原")
        eq(legendary.nextId, 91, "旧序列落后不覆盖已有神器")
        local legendaryRoundTrip = cjson.decode(cjson.encode(Schema.dehydrateModule(legendary)))
        Schema.normalizeModule(legendaryRoundTrip)
        eq(legendaryRoundTrip.bag[1].quality, 5, "传说JSON往返品质不降级")
        eq(Schema.getEquippedId(legendaryRoundTrip, 1, 1), "90", "传说装配往返保留")
        eq(Defs.getQualityName(5), "传说", "Q5名称不回落普通")
        assert(Defs.getQualityColor(5) ~= Defs.getQualityColor(1), "传说颜色独立")

        local function fillSame(quality, amount)
            reset({ maxStageId = 2401 }, 0, 0)
            for i = 1, amount do
                modules.artifacts.bag[i] = { id = tostring(i), artifactId = 2, quality = quality,
                    valueRatio = 5000, threatClearRatio = 5000 }
            end
            modules.artifacts.nextId = amount + 1
        end
        fillSame(4, 3)
        success, _, result = Service.Merge(uid, { "1", "2", "3" })
        assert(success and result, "史诗合成成功")
        eq(result.artifact.quality, 5, "三件史诗合成传说")
        fillSame(5, 3)
        success, _, result = Service.Merge(uid, { "1", "2", "3" })
        assert(success and result, "传说合成成功")
        eq(result.artifact.quality, 6, "三件传说合成至臻")
        fillSame(5, 2)
        success, _, result = Service.Reroll(uid, { "1", "2" })
        assert(success and result, "传说置换成功")
        eq(result.artifact.quality, 5, "置换保留传说品质")
        eq(#modules.artifacts.bag, 1, "置换消耗2件获得1件")
        modules.currency.privilegePoint = 1
        local refineId = result.artifact.id
        eq(Service.RefineValue(uid, refineId), true, "传说支持洗练数值")
        eq(modules.currency.privilegePoint, 0, "洗练仅扣特权点")

        local Bridge = require("systems.ArtifactBridge")
        local Runtime = require("systems.ArtifactRuntime")
        local HeroConfig = require("config.HeroConfig")
        local AD = require("systems.AttributeDef")
        for _, typeId in ipairs(Defs.getEligibleIds(5)) do
            local artifact = { id = "1", artifactId = typeId, quality = 5,
                valueRatio = 5000, threatClearRatio = typeId == 2 and 5000 or nil }
            Defs.normalizeInstanceValue(artifact)
            local def = Defs.get(typeId)
            assert(artifact.value ~= 0 and Defs.getEffectText(artifact) ~= "", "传说效果完整 " .. typeId)
            assert(Defs.getPower(artifact) > 0, "传说战力完整 " .. typeId)
            local hero = HeroConfig.createHero(1, 60)
            local targetSlot = typeId == 7 and 1 or (typeId == 8 and 3 or 2)
            local data = { bag = { artifact }, equippedByTeam = { { [2] = { "1" } } } }
            local effects = Bridge.applyToUnit(hero.attrs, targetSlot, data, 1)
            if #effects > 0 then eq(effects[1].value, artifact.value, "运行时使用完整传说数值") end
            hero.artifactEffects = effects
            Runtime.initBattle({ hero })
            if def.effectType == "dodge_decay" then
                local before = hero.attrs:get(AD.DODGE_BONUS)
                Runtime.onDodge(hero)
                assert(hero.attrs:get(AD.DODGE_BONUS) < before, "传说闪避衰减生效")
            elseif def.effectType == "hp_bonus_no_heal" then
                eq(Runtime.canHeal(hero), false, "传说生命杯治疗限制生效")
            elseif def.effectType == "revive_damage_bonus" then
                eq(Runtime.onAllyDeath(hero), true, "传说十架复活生效")
                eq(hero.attrs.artifactExtraDamageMult, 1 + artifact.value / 100, "传说复活增益生效")
            elseif def.effectType == "ghost_damage_bonus" then
                eq(Runtime.onAllyDeath(hero), true, "传说亡魂生效")
                eq(hero.artifactUntargetable, true, "传说亡魂不可选中")
            elseif def.effectType == "ignore_armor_armor_penalty" then
                eq(hero.attrs.artifactIgnoreArmor, true, "传说忽略护甲生效")
            elseif def.effectType == "crit_dmg_mult_rate_half" then
                eq(hero.attrs.artifactCritDmgMult, artifact.value / 100, "传说暴伤倍率生效")
            elseif def.effectType == "slow_attack_damage_bonus" or def.effectType == "taunt_mask" then
                eq(hero.attrs.artifactExtraDamageMult, 1 + artifact.value / 100, "传说独立增伤生效")
            elseif def.effectType == "block_cap_up" then
                eq(hero.attrs.artifactBlockCap, artifact.value, "传说格挡上限生效")
            end
            Runtime.reset({ hero })
        end

        -- 市场直接/批量钥匙购买与抽取补购使用同一150钻单价。
        local MarketService = require("rules.market.MarketService")
        reset({}, 0, 750)
        modules.market = { purchased = {}, shopConfigVersion = 8 }
        success, _, result = MarketService.Buy(uid, 20, 5)
        assert(success and result, "市场5把钥匙购买成功")
        eq(modules.currency.gems, 0, "市场5把钥匙750钻")
        eq(modules.currency.goldenKey, 5, "市场发放5把同种钥匙")
        eq(result.rewardType, "golden_key", "市场钥匙类型不变")
        reset({}, 0, 149)
        modules.market = { purchased = {}, shopConfigVersion = 8 }
        eq(MarketService.Buy(uid, 20, 1), false, "市场149钻不能买钥匙")
        eq(modules.currency.goldenKey, 0, "市场不足不发钥匙")
        eq(modules.currency.gems, 149, "市场不足不扣费")

        -- 真实面板的绘制/点击函数；仅替换绘图底层，非完整实机视觉验收。
        local texts, actions = {}, {}
        local buttons = {}
        local imagePaths, nextImage = {}, 0
        local strokes, icons = {}, {}
        local function noop() return {} end
        replace(DrawUtil, "drawTextStroke", function(_, x, y, text, font, align, r, g, b)
            texts[#texts + 1] = text
            strokes[#strokes + 1] = { text = tostring(text), x = x, y = y, r = r, g = g, b = b }
        end)
        replace(DrawUtil, "drawImageCentered", function(_, icon, cx, cy, w, h)
            icons[#icons + 1] = { icon = icon, cx = cx, cy = cy, w = w, h = h }
        end)
        replace(_G, "nvgCreateImage", function(_, path)
            nextImage = nextImage + 1
            imagePaths[nextImage] = path
            return nextImage
        end)
        replace(BF, "begin", function(_, id) buttons[id] = true return {} end)
        replace(BF, "finish", noop)
        replace(BF, "trigger", noop)
        local DarkIcon = require("core.DarkIcon")
        replace(DarkIcon, "drawNine", noop)
        replace(DarkIcon, "drawQualityBg", noop)
        for _, name in ipairs({ "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgFillColor", "nvgSave", "nvgRestore", "nvgGlobalAlpha",
            "nvgTranslate", "nvgScale", "nvgRect", "nvgBeginPath", "nvgRoundedRect", "nvgFill" }) do replace(_G, name, noop) end
        replace(_G, "nvgText", function(_, _, _, text) texts[#texts + 1] = text end)
        replace(_G, "nvgTextBounds", function(_, _, _, text) return #text * 10 end)
        replace(_G, "nvgRGBA", function() return {} end)
        replace(_G, "time", { elapsedTime = 100 })
        -- 同步钟固定为+8时区，覆盖免费、钥匙优先、混合补购与资源不足显示。
        local panelNow = 1800000000
        local panelToday = math.floor((panelNow + 28800) / 86400)
        replace(os, "time", function() return panelNow end)
        local Panel = require("ui.church.ChurchArtifactDrawPanel")
        Panel.setContext({
            state = {}, getProtocol = function() return Protocol end,
            getClient = function() return { sendAction = function(action, params)
                actions[#actions + 1] = { action = action, params = params }
            end } end,
        })
        Panel.init({})
        local function check(value, label)
            assertions = assertions + 1
            assert(value, label)
        end
        local function costTextsFor(chestType)
            local top = chestType == "advanced" and 1140 or 320
            local costY = top + 686
            local result = {}
            for _, stroke in ipairs(strokes) do
                if stroke.y == costY then result[#result + 1] = stroke end
            end
            return result
        end
        local function costIconsFor(chestType)
            local top = chestType == "advanced" and 1140 or 320
            local costY = top + 686
            local result = {}
            for _, icon in ipairs(icons) do
                if icon.cy == costY then result[#result + 1] = icon end
            end
            return result
        end
        local function resetDrawCalls()
            texts, actions = {}, {}
            buttons, strokes, icons = {}, {}, {}
        end
        for _, case in ipairs(progressCases) do
            reset(case.battle)
            Panel.reset()
            eq(Panel.isArtifactChestUnlocked(), true, case.label .. "面板查询直接开放")
            resetDrawCalls()
            Panel.drawContent({})
            eq(buttons.church_artifact_draw_1_normal, true, case.label .. "绘制普通单抽按钮")
            eq(buttons.church_artifact_draw_10_normal, true, case.label .. "绘制普通十连按钮")
            check(table.concat(texts, "|"):find("免费单抽", 1, true) ~= nil, case.label .. "免费单抽标签")
            check(table.concat(texts, "|"):find("金币", 1, true) == nil, case.label .. "宝箱文案不再承诺金币")
            local costs = costTextsFor("normal")
            eq(costs[1].text, "免费", case.label .. "单抽免费成本")
            eq(costs[2].text, "1500", case.label .. "无钥匙十连黑晶价")
            eq(#costIconsFor("normal"), 1, case.label .. "免费无图标且十连仅显示黑晶")
            eq(imagePaths[costIconsFor("normal")[1].icon], "image/货币道具/UI_icon_SJ_X.png", case.label .. "十连价格显示黑晶图标")
            eq(Panel.handleTabInput(320, 980), true, case.label .. "普通单抽点击被处理")
            eq(#actions, 1, case.label .. "单抽动作发出")
            eq(actions[1].params.payType, "free_daily", "未用每日免费优先")
            eq(actions[1].action, Protocol.ACTION_TYPES.ARTIFACT_DRAW, "面板抽取协议不变")
            eq(actions[1].params.count, 1, "面板单抽次数正确")
            Panel.onArtifactDrawResult()  -- 模拟本轮回执，下一轮夹具不继承请求中的状态。
        end

        reset({}, 0, 6000)
        modules.artifacts.dailyFreeDrawDayId = panelToday
        Panel.reset()
        resetDrawCalls()
        Panel.drawContent({})
        eq(costTextsFor("normal")[1].text, "150", "无钥匙付费单抽显示150黑晶")
        eq(costTextsFor("normal")[2].text, "1500", "无钥匙十连显示1500黑晶")
        eq(#costIconsFor("normal"), 2, "付费单抽和十连各显示黑晶图标")
        eq(imagePaths[costIconsFor("normal")[1].icon], "image/货币道具/UI_icon_SJ_X.png", "单抽显示黑晶图标")
        eq(imagePaths[costIconsFor("normal")[2].icon], "image/货币道具/UI_icon_SJ_X.png", "十连显示黑晶图标")

        reset({}, 3, 1000)
        modules.artifacts.dailyFreeDrawDayId = panelToday
        Panel.reset()
        resetDrawCalls()
        Panel.drawContent({})
        local mixed = costTextsFor("normal")
        eq(mixed[1].text, "1", "有钥匙时单抽仅展示实际消耗钥匙数")
        eq(mixed[2].text, "3", "十连先展示现有钥匙数")
        eq(mixed[3].text, "1050", "十连黑晶仅补足七把钥匙")
        eq(#costIconsFor("normal"), 3, "混合十连成本显示两种资源图标")
        eq(imagePaths[costIconsFor("normal")[1].icon], "image/货币道具/UI_icon_HJYS.png", "单抽成本为钥匙图标")
        eq(imagePaths[costIconsFor("normal")[2].icon], "image/货币道具/UI_icon_HJYS.png", "十连钥匙部分图标")
        eq(imagePaths[costIconsFor("normal")[3].icon], "image/货币道具/UI_icon_SJ_X.png", "十连补购部分黑晶图标")
        eq(mixed[1].r, 255, "钥匙足够时成本为亮色")
        eq(mixed[3].r, 0x8b, "黑晶余额不足时补购价置灰")

        reset({}, 10)
        modules.artifacts.dailyFreeDrawDayId = today
        actions = {}
        Panel.reset()
        Panel.handleTabInput(760, 980)
        eq(#actions, 1, "低进度十连动作发出")
        eq(actions[1].params.count, 10, "十连次数正确")
        eq(actions[1].params.payType, "diamond", "十连保持原支付方式")
        eq(actions[1].params.chestType, "normal", "普通卡十连使用普通档位")
        Panel.onArtifactDrawResult()
        reset({}, 0, 6000)
        actions = {}
        Panel.reset()
        Panel.handleTabInput(760, 980)
        eq(Panel.isKeyConfirmVisible(), true, "钥匙不足仍弹补购确认")
        eq(#actions, 0, "未确认不抽取")
        time.elapsedTime = 101
        Panel.handleTabInput(0, 0)
        time.elapsedTime = 102
        Panel.drawKeyConfirmDialog({})
        eq(Panel.isKeyConfirmVisible(), false, "点击框外可取消补购")
        eq(#actions, 0, "取消补购不发送抽取")
        Panel.reset()
        Panel.handleTabInput(760, 980)
        time.elapsedTime = 103
        Panel.handleTabInput(540, 1301)
        eq(#actions, 1, "确认补购后才发送抽取")
        eq(actions[1].params.count, 10, "补购保持十连次数")
        Panel.reset()
        Panel.onArtifactDrawResult()
        reset({ maxStageId = 2305 }, 0, 7500)
        modules.artifacts.dailyFreeDrawDayId = panelToday
        resetDrawCalls()
        Panel.handleTabInput(540, 1200)
        eq(Panel.isArtifactChestUnlocked(), false, "高级未通关23-5锁定")
        Panel.drawContent({})
        eq(costTextsFor("advanced")[1].text, "750", "锁定高级仍显示单抽750")
        eq(costTextsFor("advanced")[2].text, "7500", "高级十连7500")
        local allText = table.concat(texts, "|")
        check(not allText:find("通关普通23-5解锁", 1, true), "高级卡片不显示解锁说明")
        check(not allText:find("无保底", 1, true), "卡片不显示抽取规则说明")
        for _, description in ipairs({ "直接开放", "普通宝箱每日免费单抽一次（UTC+8）",
            "当前进度：", "优先使用钥匙", "至臻品质不进入宝箱抽池" }) do
            check(not allText:find(description, 1, true), "宝箱页不显示说明 " .. description)
        end
        for _, chestType in ipairs({ "normal", "advanced" }) do
            local found = false
            for _, icon in ipairs(icons) do
                local path = imagePaths[icon.icon] or ""
                if path:find(chestType == "normal" and "UI_SQBX_PT" or "UI_SQBX_GJ", 1, true) then
                    found = icon.w == 916 and icon.h == 756 and icon.cx == 540
                        and icon.cy == (chestType == "normal" and 710 or 1530)
                end
            end
            check(found, chestType .. "场景填满卡片而非独立小图标")
        end
        for _, qualityText in ipairs({ "普通：30%", "优质：40%", "稀有：20%", "史诗：9%", "传说：1%" }) do
            check(allText:find(qualityText, 1, true), "高级全部概率 " .. qualityText)
        end
        Panel.handleTabInput(320, 1800)
        eq(#actions, 0, "高级锁定不发送动作")
        eq(Panel.isKeyConfirmVisible(), false, "锁定不弹补购")
        eq(Panel.isArtifactChestUnlocked("advanced"), false, "隐藏文案不改变高级解锁门槛")
        modules.battle.clearedStages = { ["2305"] = true }
        eq(Panel.isArtifactChestUnlocked(), true, "高级通关后UI开放")
        Panel.handleTabInput(320, 1800)
        eq(Panel.isKeyConfirmVisible(), true, "高级钥匙不足确认")
        time.elapsedTime = 104
        Panel.handleTabInput(540, 1301)
        eq(#actions, 1, "高级确认后发送")
        eq(actions[1].params.chestType, "advanced", "高级档位发送到Handler")
        eq(actions[1].params.payType, "diamond", "高级不使用普通免费")
        Panel.onArtifactDrawResult()
        Panel.reset()
        resetDrawCalls()
        Panel.drawContent({})
        allText = table.concat(texts, "|")
        for _, qualityText in ipairs({ "普通：75%", "优质：20%", "稀有：4%", "史诗：0.9%", "传说：0.1%" }) do
            check(allText:find(qualityText, 1, true), "普通全部概率 " .. qualityText)
        end
        check(not allText:find("次内必得", 1, true), "普通不再显示保底承诺")
        Panel.setContext(nil)
    end)
    for i = #restores, 1, -1 do restores[i]() end
    print("[artifact_chest_direct_unlock_test] RESULT: " .. (ok and "PASS" or "FAIL")
        .. " assertions=" .. assertions .. " reason=" .. tostring(err))
    if not ok then
        print("[artifact_chest_direct_unlock_test] FAIL: " .. tostring(err) .. " (" .. assertions .. " assertions)")
        log:Write(LOG_ERROR, "[artifact_chest_direct_unlock_test] " .. tostring(err))
    else
        print("[artifact_chest_direct_unlock_test] ALL PASS: " .. assertions .. " assertions")
    end
    engine:Exit()
end
