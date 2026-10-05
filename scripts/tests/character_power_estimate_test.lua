-- ============================================================================
-- character_power_estimate_test.lua — 生产战力/预估接线回归
-- 验证 CharacterPower.bind 重构（抽出 buildHeroAttrs）后：
--   1) calcHeroPower 官方战力不回归（裸英雄 Lv1 > 0，等级越高战力越高）
--   2) calcHeroEstimate 新增预估可用（>0），且与战力共用同一 buildHeroAttrs 管线
--   3) 方向性：同等级同（无）装备下，战士/法师预估都 >0；装备力量戒 vs 智力戒
--      时，战士预估随力量上升、法师随智力上升（复用 CPE 类别区分）
--   4) 缓存/脏标记：markPowerDirty 后预估值可刷新
-- 用真实 HC/AD/EquipmentSystem/AwakeningConfig，mock 存档态与 UI 依赖。
-- 跑法: ./.cli/UrhoXRuntime tests/character_power_estimate_test.lua \
--         -tapcode_dir=<项目根> -tool_mode -graphicsheadless
-- ============================================================================

local failures = {}
local function check(cond, msg)
    if cond then print("[PASS] " .. msg)
    else print("[FAIL] " .. msg); failures[#failures + 1] = msg end
end

-- 真实模块
local AD = require("systems.AttributeDef")
local HC = require("config.HeroConfig")
local EquipmentSystem = require("systems.EquipmentSystem")
local EquipmentConfig = require("config.EquipmentConfig")
local AwakeningConfig = require("config.AwakeningConfig")
local TalentEffect = require("systems.TalentEffect")
local CharacterPower = require("ui.character.panel.CharacterPower")

function Start()
    print("[character_power_estimate_test] start")
    local savedLitNodes = HC._getSavedLitNodes()
    HC.setDefaultLitNodes(nil)
    local ok, err = pcall(function()
        -- 最小存档替身：真实英雄、无装备；第三名已拥有英雄不在任何队伍。
        local ownedSet = { [1] = { level = 1 }, [2] = { level = 1 }, [3] = { level = 1 } }
        local teamSlots = {
            { state = "occupied", heroId = 1 },
            { state = "empty" }, { state = "empty" }, { state = "empty" },
        }
        local teams = {
            { slots = teamSlots },
            { slots = {
                { state = "empty" }, { state = "empty" },
                { state = "occupied", heroId = 2 }, { state = "empty" },
            } },
            { slots = {
                { state = "empty" }, { state = "empty" },
                { state = "empty" }, { state = "empty" },
            } },
        }
        local teamPowerCaches = { {}, {}, {} }
        -- 故意打乱 heroId 顺序，并让未拥有项夹在已拥有项之间。
        local heroRoster = {
            { heroId = 2, owned = true }, { heroId = 999, owned = false },
            { heroId = 1, owned = true }, { heroId = 3, owned = true },
        }
        local rosterPowerCache = { -1, -1, -1, -1 }
        local storeData = { talents = { litNodes = {} } }
        local artifactBonuses = { {}, {}, {} }
        local gamePower = 0
        local runtimeOnlyPower = 0
        local dirtyCount = 0
        local noop = function() end
        local createCount = 0
        -- 不覆写全局HC：仅此bind统计真实属性容器创建次数。
        local countedHC = setmetatable({ createHero = function(...)
            createCount = createCount + 1
            return HC.createHero(...)
        end }, { __index = HC })
        local power = CharacterPower.bind({
            AD = AD, HC = countedHC,
            ClientDispatcher = { get = function(k) return storeData[k] end },
            PlayerStore = { Get = function() return nil end },
            EquipmentSystem = EquipmentSystem, EquipmentConfig = EquipmentConfig,
            RelicBridge = { applyToUnit = noop },
            ArtifactBridge = { applyToUnit = function(attrs, slot, _data, teamIdx)
                local bonuses = artifactBonuses[teamIdx or 1]
                attrs.artifactPowerBonus = bonuses and bonuses[slot] or 0
            end },
            AwakeningConfig = AwakeningConfig, TalentEffect = TalentEffect,
            GameState = { setPower = function(v) gamePower = v end },
            CharacterDetail = { markPowerDirty = function() dirtyCount = dirtyCount + 1 end,
                hasAnyUpgradeForHero = function() return false end,
                hasAwakeningUpgrade = function() return false end },
            CharacterPanel = { isHeroDeployed = function() return false end },
            BottomNav = { setBadge = noop, refreshTownBadge = noop },
            MAX_SLOTS = 4, TEAM_COUNT = 3,
            get = function(k)
                if k == "ownedSet" then return ownedSet
                elseif k == "teamSlots" then return teamSlots
                elseif k == "teams" then return teams
                elseif k == "teamPowerCaches" then return teamPowerCaches
                elseif k == "heroRoster" then return heroRoster
                elseif k == "rosterPowerCache" then return rosterPowerCache end
                return nil
            end,
            set = function(k, v)
                if k == "runtimeOnlyPowerCache" then runtimeOnlyPower = v end
            end,
        })

        check(type(power.calcHeroPower) == "function", "calcHeroPower 已导出")
        check(type(power.calcHeroEstimate) == "function", "calcHeroEstimate 已导出（新增）")

        -- 1) 官方战力不回归
        local p1 = power.calcHeroPower(1, 1)
        check(type(p1) == "number" and p1 > 0, "官方战力 Lv1 战士 > 0（实得 " .. p1 .. "）")
        ownedSet[1].level = 50
        local p50 = power.calcHeroPower(1, 1)
        check(p50 > p1, "官方战力随等级上升（Lv50 " .. p50 .. " > Lv1 " .. p1 .. "）")
        ownedSet[1].level = 1

        -- 2) 预估可用且 >0
        local e1 = power.calcHeroEstimate(1, 1)
        check(type(e1) == "number" and e1 > 0, "预估战力 Lv1 战士 > 0（实得 " .. e1 .. "）")

        -- 3) 预估 ≤ 官方战力×合理上界（异系打折只会更小或相近，不应爆炸）
        check(e1 <= p1 * 1.5, "预估不异常放大（" .. e1 .. " ≤ " .. p1 .. "×1.5）")

        -- 4) 法师预估也 >0，走同一管线
        local e2 = power.calcHeroEstimate(2, nil)
        check(type(e2) == "number" and e2 > 0, "预估战力 Lv1 法师 > 0（实得 " .. e2 .. "）")

        -- 5) 未知英雄返回 0 不崩
        local pBad = power.calcHeroPower(999, nil)
        local eBad = power.calcHeroEstimate(999, nil)
        check(pBad == 0 and eBad == 0, "未知英雄战力/预估均返回 0 不崩")

        -- 6) buildHeroAttrs 共用管线：同一英雄两次调用战力稳定（无状态泄漏）
        local p1b = power.calcHeroPower(1, 1)
        check(p1b == p1, "buildHeroAttrs 重构后战力可重复（" .. p1b .. " == " .. p1 .. "）")

        -- 7) 单件六维饰品在无角色视角也按派生属性折算，升阶投入只计算一次。
        local EquipmentDetail = require("ui.character.equip.EquipmentDetail")
        local function derivedPower(key, value)
            local vm = 0
            for _, derivative in ipairs(AD.DERIVATIVES[key] or {}) do
                local meta = AD.META[derivative.attr]
                if meta and meta.valueModel and meta.valueModel > 0 then
                    local divisor = meta.dataType == AD.TYPE_PCT and 100 or 1
                    vm = vm + derivative.perPoint * meta.valueModel / divisor
                end
            end
            return value * vm
        end
        for _, key in ipairs(AD.BASE_STATS) do
            local item = { baseStats = { { key, 4.28 } }, affixes = {}, ascendLevel = 0 }
            check(EquipmentDetail.calcEquipPower(item, nil) == math.floor(derivedPower(key, 4.28)),
                "无角色视角 " .. key .. " 按派生折算")
        end
        local bonusItem = {
            baseStats = { { "str", 4.28 } }, ascendLevel = 0, affixMult = 1.2,
            affixes = { { key = "str", value = 10, ascBonus = 40, affixId = 1 } },
        }
        local expectedBonus = math.floor(derivedPower("str", 4.28 + 10 * 1.2 + 40))
        check(EquipmentDetail.calcEquipPower(bonusItem, nil) == expectedBonus,
            "单件战力包含栏位倍率和升阶投入且不重复放大")

        -- 8) 不重建名册，仅 refreshPowerCache 就同步每个列表索引。
        createCount = 0
        power.refreshPowerCache()
        check(createCount == 3, "单轮三个已拥有英雄各建一次，名册与队槽不重复计算")
        check(rosterPowerCache[1] == power.calcHeroPower(2)
            and rosterPowerCache[3] == p1 and rosterPowerCache[4] == power.calcHeroPower(3),
            "刷新全部已拥有名册，缓存按列表索引而非 heroId")
        check(rosterPowerCache[2] == 0, "未拥有项的旧缓存清为 0")
        check(teamPowerCaches[1][1] == p1 and teamPowerCaches[2][3] == power.calcHeroPower(2, 3, 2)
            and teamPowerCaches[3][1] == 0, "三队原有槽位缓存继续刷新")
        check(gamePower == p1 and runtimeOnlyPower == 0 and dirtyCount == 1,
            "总战力仍仅主队，保留 runtimeOnly 与详情脏标记")

        local benchBefore = rosterPowerCache[4]
        ownedSet[3].level = 50
        createCount = 0
        power.refreshPowerCache()
        check(createCount == 3, "下次通知重新计算三个英雄，不复用旧属性结果")
        check(rosterPowerCache[4] > benchBefore and rosterPowerCache[4] == power.calcHeroPower(3),
            "未出战角色成长后，仅刷新即可更新名册战力")
        check(gamePower == p1, "未出战角色战力不计入 GameState 总战力")
        ownedSet[3].level = 1
        power.refreshPowerCache()

        -- 使用真实刚力节点，覆盖 talents 订阅仅调用 refreshPowerCache 的路径。
        local talentBefore = { rosterPowerCache[1], rosterPowerCache[3], rosterPowerCache[4] }
        storeData.talents.litNodes = { 2 }
        power.refreshPowerCache()
        check(rosterPowerCache[1] > talentBefore[1] and rosterPowerCache[3] > talentBefore[2]
            and rosterPowerCache[4] > talentBefore[3], "真实天赋变更同步出战与未出战名册战力")
        check(rosterPowerCache[1] == power.calcHeroPower(2) and rosterPowerCache[2] == 0,
            "天赋刷新仍沿用正式公式，未拥有项不产生战力")
        storeData.talents.litNodes = {}
        power.refreshPowerCache()
        check(rosterPowerCache[3] == p1 and gamePower == p1, "清空天赋回到原有正式战力")

        -- 名册和队伍缓存共用英雄所属队神器，不能因活动队改变计价。
        local secondHeroBefore = power.calcHeroPower(2)
        artifactBonuses[1][1] = 37
        artifactBonuses[2][3] = 89
        createCount = 0
        power.refreshPowerCache()
        check(createCount == 3, "正确所属队/槽的名册与编队战力共用本轮计算")
        check(power.calcHeroPower(2, 1, 2) == secondHeroBefore
            and power.calcHeroPower(2, 3, 1) == secondHeroBefore,
            "显式错误槽或错误队不借用所属队神器结果")
        check(rosterPowerCache[3] == p1 + 37 and rosterPowerCache[3] == power.calcHeroPower(1),
            "神器变更刷新名册，英雄1按队1真实槽计价")
        check(teamPowerCaches[2][3] == secondHeroBefore + 89
            and rosterPowerCache[1] == secondHeroBefore + 89,
            "英雄2名册和队伍缓存都计入所属队2槽3神器")
        teamSlots = teams[2].slots
        power.refreshPowerCache()
        check(rosterPowerCache[1] == secondHeroBefore + 89 and rosterPowerCache[3] == p1 + 37,
            "活动队切到队2不改变各英雄所属队战力")
        check(gamePower == p1 + 37 and runtimeOnlyPower == 0 and rosterPowerCache[2] == 0,
            "神器刷新不把全名册或其他队战力加进总战力")

        print(string.format("[summary] 战士 Lv1 官方战力=%d 预估=%d | 法师 Lv1 预估=%d", p1, e1, e2))
    end)
    HC.setDefaultLitNodes(savedLitNodes)
    if not ok then
        print("[FAIL] 测试抛异常: " .. tostring(err))
        failures[#failures + 1] = "exception"
    end
    if #failures == 0 then
        print("[character_power_estimate_test] ALL PASS")
    else
        print("[character_power_estimate_test] FAILURES=" .. #failures)
        for _, m in ipairs(failures) do print("  - " .. m) end
    end
    engine:Exit()
end
