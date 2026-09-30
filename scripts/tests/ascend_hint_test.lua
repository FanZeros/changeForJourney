-- ============================================================================
-- ascend_hint_test.lua — 升阶页词条提示文案回归（buildAffixHint 纯函数）
-- 需求①：下一阶恰为 +5 里程碑且未满员 → 「升至 +N 将新增 1 条随机词条」（亮绿）
-- 需求②：满员文案精简为「词条已满 · 每升5阶倍率+10%（洗练不丢）」，绘制层右对齐不再独占整行
-- 跑法: cd /workspace && ./.cli/UrhoXRuntime tests/ascend_hint_test.lua \
--         -tapcode_dir=. -tool_mode -graphicsheadless
-- ============================================================================

local PREFIX = "[ascend_hint] "
local failures = {}
local passes = 0
local function check(cond, msg)
    if cond then passes = passes + 1; print(PREFIX .. "[PASS] " .. msg)
    else print(PREFIX .. "[FAIL] " .. msg); failures[#failures + 1] = msg end
end

local AffixConfig = require("config.AffixConfig")
local Enhance = require("ui.blacksmith.BlacksmithEnhance")

--- 构造普通词条（id 1~N 均为普通词条）
local function normalAffix(id)
    return { affixId = id, key = "k" .. id, name = "词条" .. id, quality = 3, value = 1 }
end
--- 构造魔化词条（CORRUPT_AFFIXES id 1001+）
local function corruptAffix()
    return { affixId = 1001, key = "finalPhysAtkBonus", name = "最终物攻", quality = 3, value = 1.7 }
end

local function equipWith(affixes)
    return { affixes = affixes, quality = 3, level = 10, ascendLevel = 0 }
end

function Start()
    check(type(Enhance.buildAffixHint) == "function", "buildAffixHint 已导出")

    -- 前置：魔化判定可用
    check(AffixConfig.isCorruptAffix(corruptAffix()) == true, "魔化词条判定正确")
    check(AffixConfig.isCorruptAffix(normalAffix(1)) == false, "普通词条判定正确")

    -- 1) 需求①：+4 升 +5（下一阶是里程碑）且未满员 → 里程碑提示
    local h = Enhance.buildAffixHint(
        { isMaxLevel = false, nextLevel = 5 },
        equipWith({ normalAffix(1) }))
    check(h.text == "升至 +5 将新增 1 条随机词条", "里程碑提示文案 (实际=" .. h.text .. ")")
    check(h.r == 0x7a and h.g == 0xc8 and h.b == 0x6e, "里程碑提示为亮绿色")

    -- 2) +9 升 +10 同理
    h = Enhance.buildAffixHint(
        { isMaxLevel = false, nextLevel = 10 },
        equipWith({ normalAffix(1), normalAffix(2) }))
    check(h.text == "升至 +10 将新增 1 条随机词条", "+10 里程碑提示 (实际=" .. h.text .. ")")

    -- 3) 非里程碑（+3 升 +4）→ 常规规则提示
    h = Enhance.buildAffixHint(
        { isMaxLevel = false, nextLevel = 4 },
        equipWith({ normalAffix(1) }))
    check(h.text == "每升5阶必得1条随机词条（最多4条）", "非里程碑常规提示 (实际=" .. h.text .. ")")
    check(h.r == 0xbc and h.g == 0x9b and h.b == 0x58, "常规提示为金棕色")

    -- 4) 0 词条装备也走同样分支
    h = Enhance.buildAffixHint({ isMaxLevel = false, nextLevel = 5 }, equipWith({}))
    check(h.text == "升至 +5 将新增 1 条随机词条", "0词条里程碑提示 (实际=" .. h.text .. ")")
    h = Enhance.buildAffixHint({ isMaxLevel = false, nextLevel = 1 }, equipWith({}))
    check(h.text == "每升5阶必得1条随机词条（最多4条）", "0词条常规提示 (实际=" .. h.text .. ")")

    -- 5) 需求②：满员（4 普通）→ 倍率提示，即使下一阶是里程碑也不显示"新增词条"
    h = Enhance.buildAffixHint(
        { isMaxLevel = false, nextLevel = 5 },
        equipWith({ normalAffix(1), normalAffix(2), normalAffix(3), normalAffix(4) }))
    check(h.text == "词条已满 · 每升5阶倍率+10%（洗练不丢）", "满员倍率提示 (实际=" .. h.text .. ")")
    check(h.r == 0xbc and h.g == 0x9b and h.b == 0x58, "满员提示为金棕色")

    -- 6) 魔化词条不占普通上限：3普通+1魔化 未满员，里程碑仍提示新增
    h = Enhance.buildAffixHint(
        { isMaxLevel = false, nextLevel = 15 },
        equipWith({ normalAffix(1), normalAffix(2), normalAffix(3), corruptAffix() }))
    check(h.text == "升至 +15 将新增 1 条随机词条", "3普通+1魔化未满员 (实际=" .. h.text .. ")")

    -- 7) 满级时不显示里程碑提示（nextLevel 可能恰为 5 的倍数）
    h = Enhance.buildAffixHint(
        { isMaxLevel = true, nextLevel = 10 },
        equipWith({ normalAffix(1) }))
    check(h.text == "每升5阶必得1条随机词条（最多4条）", "满级走常规提示 (实际=" .. h.text .. ")")

    -- 8) nil 装备不崩
    h = Enhance.buildAffixHint({ isMaxLevel = false, nextLevel = 5 }, nil)
    check(h.text == "升至 +5 将新增 1 条随机词条", "nil 装备安全 (实际=" .. h.text .. ")")

    if #failures == 0 then
        print(PREFIX .. "RESULT ALL PASS (" .. passes .. " assertions)")
    else
        print(PREFIX .. "RESULT " .. passes .. " PASS / " .. #failures .. " FAILURES")
    end
    if engine and engine.Exit then engine:Exit() end
end
