-- ============================================================================
-- auto_decompose_regress_test.lua — 自动分解统一判定/钳制/分解防刷回归
-- 验证：
--   1) shouldAutoDecompose 语义：双0不分解；单维0=不限制；双维 AND；字符串容错
--   2) SetAutoDecompose 钳制：品质上限6（至臻）、等级上限60，handler 返回钳制值
--   3) calcAutoDecomposeEssence 与手动分解基础公式一致
--   4) recordAutoDecompose 通知 seq 递增、累计 count/essence、带时间戳
--   5) DecomposeEquip 重复 seq 拒绝（防刷精粹），正常分解奖励正确且库存删除
-- 跑法: ./.cli/UrhoXRuntime tests/auto_decompose_regress_test.lua \
--         -tapcode_dir=. -tool_mode -graphicsheadless
-- ============================================================================

local PREFIX = "[auto_decompose_regress] "
local failures = {}
local function check(cond, msg)
    if cond then print(PREFIX .. "[PASS] " .. msg)
    else print(PREFIX .. "[FAIL] " .. msg); failures[#failures + 1] = msg end
end
local function eq(actual, expected, msg)
    check(actual == expected, msg .. " (实际=" .. tostring(actual) .. " 期望=" .. tostring(expected) .. ")")
end

local BC = require("config.BlacksmithConfig")

function Start()
    print(PREFIX .. "start")

    -- ========== 1) 共享判定语义 ==========
    check(BC.shouldAutoDecompose(nil, 1, 1) == false, "settings=nil 不分解")
    check(BC.shouldAutoDecompose({}, 1, 1) == false, "双0（未设置）不分解")
    check(BC.shouldAutoDecompose({ autoQuality = 0, autoLevel = 0 }, 6, 60) == false, "显式双0不分解")
    -- 单维启用：另一维 0 = 不限制
    check(BC.shouldAutoDecompose({ autoQuality = 2, autoLevel = 0 }, 2, 60) == true, "仅品质启用：q<=阈值 分解")
    check(BC.shouldAutoDecompose({ autoQuality = 2, autoLevel = 0 }, 3, 1) == false, "仅品质启用：q>阈值 不分解")
    check(BC.shouldAutoDecompose({ autoQuality = 0, autoLevel = 30 }, 6, 30) == true, "仅等级启用：lv<=阈值 分解")
    check(BC.shouldAutoDecompose({ autoQuality = 0, autoLevel = 30 }, 1, 31) == false, "仅等级启用：lv>阈值 不分解")
    -- 双维 AND
    check(BC.shouldAutoDecompose({ autoQuality = 3, autoLevel = 40 }, 3, 40) == true, "双维边界(=阈值) 分解")
    check(BC.shouldAutoDecompose({ autoQuality = 3, autoLevel = 40 }, 4, 1) == false, "品质超阈 不分解")
    check(BC.shouldAutoDecompose({ autoQuality = 3, autoLevel = 40 }, 1, 41) == false, "等级超阈 不分解")
    -- 至臻档（修复前钳 5 导致永不分解）
    check(BC.shouldAutoDecompose({ autoQuality = 6, autoLevel = 0 }, 6, 60) == true, "至臻(6)档可分解至臻掉落")
    -- 字符串容错
    check(BC.shouldAutoDecompose({ autoQuality = "3", autoLevel = "40" }, 3, 40) == true, "字符串设置 tonumber 容错")
    check(BC.shouldAutoDecompose({ autoQuality = "abc", autoLevel = nil }, 1, 1) == false, "非法设置视为未启用")

    -- ========== 2) 精粹公式与手动分解一致 ==========
    local qCost3 = BC.QUALITY_COST[3]
    local expect3 = math.floor(qCost3.decBase * (1 + 25 * qCost3.decScale))
    eq(BC.calcAutoDecomposeEssence(3, 25), expect3, "自动分解精粹=手动基础公式 q3 lv25")
    eq(BC.calcAutoDecomposeEssence(9, 1), BC.calcAutoDecomposeEssence(1, 1), "越界品质回退 q1 公式")

    -- ========== 3) 通知记录 ==========
    local lootbox = { seeds = {} }
    BC.recordAutoDecompose(lootbox, 2, 10, 12)
    BC.recordAutoDecompose(lootbox, 3, 20, 17)
    local n = lootbox.autoDecomposeNotice
    check(n ~= nil, "notice 已创建")
    eq(n.seq, 2, "notice.seq 递增")
    eq(n.count, 2, "notice.count 累计")
    eq(n.essence, 29, "notice.essence 累计")
    eq(n.quality, 3, "notice.quality 为最近一次")
    check(type(n.time) == "number" and n.time > 0, "notice.time 时间戳存在")

    -- ========== 4) 服务端钳制（真实 PDM 注入） ==========
    local PDM = require("rules.character.PlayerDataManager")
    local oldGetModule, oldMarkDirty = PDM.GetModule, PDM.MarkDirty
    local equipment = { inventory = {}, equipped = {}, settings = {} }
    local currency = { essence = 0 }
    PDM.GetModule = function(_, name)
        return ({ equipment = equipment, currency = currency })[name]
    end
    local dirty = {}
    PDM.MarkDirty = function(_, fieldKey) dirty[fieldKey] = (dirty[fieldKey] or 0) + 1 end

    local EquipmentService = require("rules.equipment.EquipmentService")
    local ok1, _, cq, cl = EquipmentService.SetAutoDecompose(1, 9, 999)
    check(ok1 == true, "SetAutoDecompose 成功")
    eq(cq, 6, "品质钳制上限 6（至臻）")
    eq(cl, 60, "等级钳制上限 60")
    eq(equipment.settings.autoQuality, 6, "存储值为钳制后品质")
    eq(equipment.settings.autoLevel, 60, "存储值为钳制后等级")
    local ok2, _, cq2, cl2 = EquipmentService.SetAutoDecompose(1, -5, -1)
    check(ok2 == true and cq2 == 0 and cl2 == 0, "负值钳制为 0（关闭）")

    -- ========== 5) DecomposeEquip 重复 seq 防刷 ==========
    local EquipmentSystem = require("systems.EquipmentSystem")
    local equipA = EquipmentSystem.generateRandom(10, 2)
    local equipB = EquipmentSystem.generateRandom(10, 2)
    check(equipA ~= nil and equipB ~= nil, "测试装备生成成功")
    equipA.seq, equipB.seq = 9001, 9002
    equipment.inventory = { ["9001"] = equipA, ["9002"] = equipB }
    equipment.equipped = {}
    currency.essence = 0

    local BS = require("rules.blacksmith.BlacksmithService")
    -- 重复 seq：必须拒绝且不发奖
    local dupOk, dupErr = BS.DecomposeEquip(1, { 9001, 9001, 9001 })
    check(dupOk == false, "重复 seq 被拒绝: " .. tostring(dupErr))
    eq(currency.essence, 0, "重复 seq 不发精粹")
    eq(equipment.inventory["9001"] ~= nil, true, "重复 seq 不删库存")

    -- 正常分解两件：奖励 = 两件基础公式和，库存清空
    local qA, lvA = equipA.quality or 1, equipA.level or 1
    local qB, lvB = equipB.quality or 1, equipB.level or 1
    local expectSum = BC.calcAutoDecomposeEssence(qA, lvA) + BC.calcAutoDecomposeEssence(qB, lvB)
    local normOk, normErr, res = BS.DecomposeEquip(1, { 9001, 9002 })
    check(normOk == true, "正常分解成功: " .. tostring(normErr))
    eq(res.decomposeCount, 2, "分解数量 2")
    eq(res.essenceReward, expectSum, "精粹奖励=两件基础和（无洗练/升阶投入）")
    eq(currency.essence, expectSum, "货币入账正确")
    eq(equipment.inventory["9001"], nil, "库存删除 9001")
    eq(equipment.inventory["9002"], nil, "库存删除 9002")

    PDM.GetModule, PDM.MarkDirty = oldGetModule, oldMarkDirty

    -- ========== 汇总 ==========
    if #failures > 0 then
        print(PREFIX .. "RESULT FAIL " .. #failures)
        for _, f in ipairs(failures) do print(PREFIX .. "  - " .. f) end
        error(PREFIX .. #failures .. " assertions failed")
    end
    print(PREFIX .. "RESULT ALL PASS")
end
