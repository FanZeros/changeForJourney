-- ============================================================================
-- ascend_hint_test.lua — 升阶页词条提示回归（buildAffixHint / buildAffixPreview 纯函数）
-- 需求①：里程碑新增词条信息由占位词条行承载（》 ??? +?），小字不再输出里程碑文案
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

    -- 1) 需求①：+4 升 +5（下一阶是里程碑）且未满员 → 小字走常规文案，占位行承载新增信息
    local h = Enhance.buildAffixHint(
        { isMaxLevel = false, nextLevel = 5 },
        equipWith({ normalAffix(1) }))
    check(h.text == "每升5阶必得1条随机词条（最多4条）", "里程碑不再输出小字，走常规文案 (实际=" .. h.text .. ")")
    check(h.r == 0xbc and h.g == 0x9b and h.b == 0x58, "里程碑小字为金棕色常规色")
    local p = Enhance.buildAffixPreview(
        { isMaxLevel = false, nextLevel = 5 },
        equipWith({ normalAffix(1) }))
    check(p ~= nil and p.name == "???" and p.val == "+?", "里程碑占位行内容为 》??? +?")

    -- 2) +9 升 +10 同理
    h = Enhance.buildAffixHint(
        { isMaxLevel = false, nextLevel = 10 },
        equipWith({ normalAffix(1), normalAffix(2) }))
    check(h.text == "每升5阶必得1条随机词条（最多4条）", "+10 里程碑走常规文案 (实际=" .. h.text .. ")")
    p = Enhance.buildAffixPreview(
        { isMaxLevel = false, nextLevel = 10 },
        equipWith({ normalAffix(1), normalAffix(2) }))
    check(p ~= nil, "+10 占位行存在")

    -- 3) 非里程碑（+3 升 +4）→ 常规规则提示
    h = Enhance.buildAffixHint(
        { isMaxLevel = false, nextLevel = 4 },
        equipWith({ normalAffix(1) }))
    check(h.text == "每升5阶必得1条随机词条（最多4条）", "非里程碑常规提示 (实际=" .. h.text .. ")")
    check(h.r == 0xbc and h.g == 0x9b and h.b == 0x58, "常规提示为金棕色")

    -- 4) 0 词条装备也走同样分支
    h = Enhance.buildAffixHint({ isMaxLevel = false, nextLevel = 5 }, equipWith({}))
    check(h.text == "每升5阶必得1条随机词条（最多4条）", "0词条里程碑走常规文案 (实际=" .. h.text .. ")")
    p = Enhance.buildAffixPreview({ isMaxLevel = false, nextLevel = 5 }, equipWith({}))
    check(p ~= nil, "0词条里程碑占位行存在")
    h = Enhance.buildAffixHint({ isMaxLevel = false, nextLevel = 1 }, equipWith({}))
    check(h.text == "每升5阶必得1条随机词条（最多4条）", "0词条常规提示 (实际=" .. h.text .. ")")
    p = Enhance.buildAffixPreview({ isMaxLevel = false, nextLevel = 1 }, equipWith({}))
    check(p == nil, "非里程碑无占位行")

    -- 5) 需求②：满员（4 普通）→ 倍率提示，即使下一阶是里程碑也不显示"新增词条"
    h = Enhance.buildAffixHint(
        { isMaxLevel = false, nextLevel = 5 },
        equipWith({ normalAffix(1), normalAffix(2), normalAffix(3), normalAffix(4) }))
    check(h.text == "词条已满 · 每升5阶倍率+10%（洗练不丢）", "满员倍率提示 (实际=" .. h.text .. ")")
    check(h.r == 0xbc and h.g == 0x9b and h.b == 0x58, "满员提示为金棕色")
    p = Enhance.buildAffixPreview(
        { isMaxLevel = false, nextLevel = 5 },
        equipWith({ normalAffix(1), normalAffix(2), normalAffix(3), normalAffix(4) }))
    check(p == nil, "满员里程碑不画占位行")

    -- 6) 魔化词条不占普通上限：3普通+1魔化 未满员，里程碑仍有占位行
    h = Enhance.buildAffixHint(
        { isMaxLevel = false, nextLevel = 15 },
        equipWith({ normalAffix(1), normalAffix(2), normalAffix(3), corruptAffix() }))
    check(h.text == "每升5阶必得1条随机词条（最多4条）", "3普通+1魔化未满员走常规文案 (实际=" .. h.text .. ")")
    p = Enhance.buildAffixPreview(
        { isMaxLevel = false, nextLevel = 15 },
        equipWith({ normalAffix(1), normalAffix(2), normalAffix(3), corruptAffix() }))
    check(p ~= nil, "3普通+1魔化里程碑占位行存在")

    -- 7) 满级时不显示占位行（nextLevel 可能恰为 5 的倍数）
    h = Enhance.buildAffixHint(
        { isMaxLevel = true, nextLevel = 10 },
        equipWith({ normalAffix(1) }))
    check(h.text == "每升5阶必得1条随机词条（最多4条）", "满级走常规提示 (实际=" .. h.text .. ")")
    p = Enhance.buildAffixPreview({ isMaxLevel = true, nextLevel = 10 }, equipWith({ normalAffix(1) }))
    check(p == nil, "满级无占位行")

    -- 8) nil 装备不崩
    h = Enhance.buildAffixHint({ isMaxLevel = false, nextLevel = 5 }, nil)
    check(h.text == "每升5阶必得1条随机词条（最多4条）", "nil 装备小字安全 (实际=" .. h.text .. ")")
    p = Enhance.buildAffixPreview({ isMaxLevel = false, nextLevel = 5 }, nil)
    check(p ~= nil, "nil 装备占位行安全")

    if #failures == 0 then
        print(PREFIX .. "RESULT ALL PASS (" .. passes .. " assertions)")
    else
        print(PREFIX .. "RESULT " .. passes .. " PASS / " .. #failures .. " FAILURES")
    end
    if engine and engine.Exit then engine:Exit() end
end
