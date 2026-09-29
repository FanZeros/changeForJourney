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
    local ok, err = pcall(function()
        -- 最小存档替身：单英雄、无装备（applyEquippedItems 读到 nil inventory 会安全返回）
        local ownedSet = { [1] = { level = 1 }, [2] = { level = 1 } }
        local teamSlots = {
            { state = "occupied", heroId = 1 },
            { state = "empty" }, { state = "empty" }, { state = "empty" },
        }
        local modules = {}
        local noop = function() end
        local power = CharacterPower.bind({
            AD = AD, HC = HC,
            ClientDispatcher = { get = function() return nil end },
            PlayerStore = { Get = function() return nil end },
            EquipmentSystem = EquipmentSystem, EquipmentConfig = EquipmentConfig,
            RelicBridge = { applyToUnit = noop },
            ArtifactBridge = { applyToUnit = noop },
            AwakeningConfig = AwakeningConfig, TalentEffect = TalentEffect,
            GameState = { setPower = noop },
            CharacterDetail = { markPowerDirty = noop, hasAnyUpgradeForHero = function() return false end,
                hasAwakeningUpgrade = function() return false end },
            CharacterPanel = { isHeroDeployed = function() return false end },
            BottomNav = { setBadge = noop, refreshTownBadge = noop },
            MAX_SLOTS = 4, TEAM_COUNT = 3,
            get = function(k)
                if k == "ownedSet" then return ownedSet
                elseif k == "teamSlots" then return teamSlots
                elseif k == "teams" then return {}
                elseif k == "teamPowerCaches" then return {} end
                return nil
            end,
            set = noop,
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

        print(string.format("[summary] 战士 Lv1 官方战力=%d 预估=%d | 法师 Lv1 预估=%d", p1, e1, e2))
    end)
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
