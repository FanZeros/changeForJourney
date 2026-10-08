-- ============================================================================
-- awakening_growth_equivalence_test.lua — 觉醒1 成长层配置化等价回归
-- 验证既有成长口径与属性映射保持，并回归 #17 补齐的任意击杀魔攻成长：
--   1) applyGrowth：逐角色触发条件（any/burning/shocked/marked/nitroKill）
--      与叠层字段（stacks + 专长字段）和旧 if heroId==N 链一致
--   2) 无条件角色在未命中触发条件时不叠层（#2 非燃烧、#6 非感电、#8 非标记、#21 非氮气）
--   3) buildAttrEntries：与旧 bruteEntries 逐条 key/flat 一致（含 #14 双属性、
--      #9/#10/#15/#23 非击杀口径字段、#16/20/21/22 专长字段不产属性）
--   4) 未在 RULES 中的角色（9/10/15/17/23）击杀不叠层
-- 跑法：/workspace/.cli/UrhoXRuntime tests/awakening_growth_equivalence_test.lua \
--       -tapcode_dir=/workspace/game5 -tool_mode -graphicsheadless -nosound
-- 本测试验证纯配置增量/属性映射；ETS 公共钩子的战后结算另见生命生命周期专项。
--   4) 非击杀角色（9/10/15/23）不叠；#17 任意击杀仅复用 stacks、阶段状态只读
-- 跑法: ./.cli/UrhoXRuntime tests/awakening_growth_equivalence_test.lua \
--         -tapcode_dir=<项目根> -tool_mode -graphicsheadless
-- ============================================================================

local failures = {}
local function check(cond, msg)
    if cond then print("[PASS] " .. msg)
    else print("[FAIL] " .. msg); failures[#failures + 1] = msg end
end

local AG = require("systems.AwakeningGrowth")
local AD = require("systems.AttributeDef")

--- 构造一个最小 extra 表（等价 ETS.normalize 的输出）
local function makeExtra()
    return {
        stacks = 0, splitKills = 0, iceStatues = 0, issuedCards = 0, burnKills = 0,
        preciseStored = 0, blockBank = 0, conquerCarry = 0, shockKills = 0, beamCharges = 0,
        overflowCount = 0, shareCount = 0, slashShadows = 0, nitroKills = 0, gatlingKills = 0,
        swordStacks = 0, gateStacks = 0, shieldStacks = 0,
        biteTypes = {}, tickets = {}, markTypes = {},
    }
end

--- 构造击杀上下文；statuses = { burning=true, ... } 模拟 SEM.has
--- killerFlags 挂 attacker；deadFlags 挂死亡敌人（_killedByCrit/_killedByRicochet/_killedByNightSlash）
local function makeCtx(killerFlags, statuses, deadFlags)
    local deadEnemy = { statuses = statuses or {} }
    for k, v in pairs(deadFlags or {}) do deadEnemy[k] = v end
    local killer = {}
    for k, v in pairs(killerFlags or {}) do killer[k] = v end
    deadEnemy._killedBy = killer
    return {
        deadEnemy = deadEnemy, killer = killer, enemies = { deadEnemy },
        hasStatus = function(u, k)
            return u ~= nil and u.statuses ~= nil and u.statuses[k] == true
        end,
    }
end

function Start()
    print("[awakening_growth_equivalence_test] 开始配置增量与属性映射回归")
    local originalRequire = require
    local originalCapRule = AG.RULES[9999]
    ---@type table<number, table>
    local owned = {}
    local panelMock = { getOwnedHero = function(heroId) return owned[heroId] end }
    require = function(name)
        if name == "systems.AttributeDef" then return AD end
        if name == "ui.character.panel.CharacterPanel" then return panelMock end
        return originalRequire(name)
    end
    local ok, err = pcall(function()
        -- ========== 1) 无条件击杀叠层（旧: if n1 then bump() end） ==========
        -- 注意：11/13/14/18 已改为专属口径（杠杆②），不在此列表
        for _, hid in ipairs({ 1, 3, 4, 5, 7, 12, 17, 19, 24, 25 }) do
            local extra = makeExtra()
            local applied = AG.applyGrowth(hid, extra, makeCtx())
            check(applied and extra.stacks == 1,
                string.format("hero%d 任意击杀 stacks 0→1", hid))
        end

        -- ========== 1b) 杠杆②：专属口径 ×2（新条件触发才叠，且叠 2 层） ==========
        do -- #18 老六 / #14 内鬼：暴击击杀 ×2
            for _, hid in ipairs({ 14, 18 }) do
                local eCrit = makeExtra()
                local hit = AG.applyGrowth(hid, eCrit, makeCtx(nil, {}, { _killedByCrit = true }))
                check(hit and eCrit.stacks == 2, string.format("hero%d 暴击击杀 stacks+2", hid))
                local eNorm = makeExtra()
                local miss = AG.applyGrowth(hid, eNorm, makeCtx())
                check(not miss and eNorm.stacks == 0, string.format("hero%d 非暴击击杀不叠层", hid))
            end
        end
        do -- #11 熬夜冠军：通宵斩击杀 ×2（读 deadEnemy._killedByNightSlash 精确标记，
             --        不读 attacker._nightSlashKill 粘性标记）
            local eHit = makeExtra()
            local hit = AG.applyGrowth(11, eHit, makeCtx(nil, {}, { _killedByNightSlash = true }))
            check(hit and eHit.stacks == 2, "hero11 通宵斩击杀 stacks+2")
            -- 回归防护：粘性标记挂在 killer 上时不得误触发
            local eSticky = makeExtra()
            local missSticky = AG.applyGrowth(11, eSticky, makeCtx({ _nightSlashKill = true }))
            check(not missSticky and eSticky.stacks == 0,
                "hero11 attacker 粘性 _nightSlashKill 不误触发(防回归)")
            local eNorm = makeExtra()
            check(not AG.applyGrowth(11, eNorm, makeCtx()) and eNorm.stacks == 0,
                "hero11 普通击杀不叠层")
        end
        do -- #13 弹弹弹：弹射击杀 ×2
            local eHit = makeExtra()
            local hit = AG.applyGrowth(13, eHit, makeCtx(nil, {}, { _killedByRicochet = true }))
            check(hit and eHit.stacks == 2, "hero13 弹射击杀 stacks+2")
            local eNorm = makeExtra()
            check(not AG.applyGrowth(13, eNorm, makeCtx()) and eNorm.stacks == 0,
                "hero13 非弹射击杀不叠层")
        end
        do -- #8 愤怒的小雀：标记击杀 ×2（原 ×1，杠杆②提倍率）
            local eHit = makeExtra()
            local hit = AG.applyGrowth(8, eHit, makeCtx(nil, { marked = true }))
            check(hit and eHit.stacks == 2, "hero8 标记击杀 stacks+2")
            local eNorm = makeExtra()
            check(not AG.applyGrowth(8, eNorm, makeCtx()) and eNorm.stacks == 0,
                "hero8 非标记击杀不叠层")
        end

        -- ========== 2) 条件击杀叠层 ==========
        do -- #2 黄桃龙：仅燃烧击杀
            local e1 = makeExtra()
            local hit = AG.applyGrowth(2, e1, makeCtx(nil, { burning = true }))
            check(hit and e1.burnKills == 1 and e1.stacks == 1, "hero2 燃烧击杀 burnKills+1 stacks+1")
            local e2 = makeExtra()
            local miss = AG.applyGrowth(2, e2, makeCtx(nil, {}))
            check(not miss and e2.burnKills == 0 and e2.stacks == 0, "hero2 非燃烧击杀不叠层")
        end
        do -- #6 压一压：仅感电击杀
            local e1 = makeExtra()
            local hit = AG.applyGrowth(6, e1, makeCtx(nil, { shocked = true }))
            check(hit and e1.shockKills == 1 and e1.stacks == 1, "hero6 感电击杀 shockKills+1 stacks+1")
            local e2 = makeExtra()
            check(not AG.applyGrowth(6, e2, makeCtx(nil, { burning = true }))
                and e2.shockKills == 0, "hero6 燃烧(非感电)击杀不叠层")
        end
        do -- #8 愤怒的小雀：标记口径断言已移至 1b 节（杠杆② ×2）
        end
        do -- #21 雷电麦坤：仅氮气击杀
            local e1 = makeExtra()
            local hit = AG.applyGrowth(21, e1, makeCtx({ _nitroKill = true }))
            check(hit and e1.nitroKills == 1 and e1.stacks == 1, "hero21 氮气击杀 nitroKills+1 stacks+1")
            local e2 = makeExtra()
            check(not AG.applyGrowth(21, e2, makeCtx()) and e2.nitroKills == 0, "hero21 普通击杀不叠层")
        end

        -- ========== 3) 专长字段 + stacks 同叠（旧: 双加） ==========
        do -- #16 万剑归宗
            local e = makeExtra()
            AG.applyGrowth(16, e, makeCtx())
            check(e.swordStacks == 1 and e.stacks == 1, "hero16 击杀 swordStacks+1 stacks+1")
        end
        do -- #20 摘星星星人
            local e = makeExtra()
            AG.applyGrowth(20, e, makeCtx())
            check(e.gateStacks == 1 and e.stacks == 1, "hero20 击杀 gateStacks+1 stacks+1")
        end
        do -- #22 小黑子
            local e = makeExtra()
            AG.applyGrowth(22, e, makeCtx())
            check(e.gatlingKills == 1 and e.stacks == 1, "hero22 击杀 gatlingKills+1 stacks+1")
        end

        -- ========== 4) 无击杀叠层规则的角色（非击杀口径） ==========
        for _, hid in ipairs({ 9, 10, 15, 23 }) do
            local e = makeExtra()
            local applied = AG.applyGrowth(hid, e, makeCtx())
            check(not applied and e.stacks == 0,
                string.format("hero%d 无击杀叠层规则(旧代码亦无分支)", hid))
        end

        -- ========== 5) buildAttrEntries 与旧 bruteEntries 等价 ==========
        local function entriesToMap(entries)
            local m = {}
            for _, e in ipairs(entries) do m[#m + 1] = e.key .. "=" .. tostring(e.flat) end
            return table.concat(m, ",")
        end
        do -- #1: stacks=50 → MAX_HP +50 (系数1)
            local e = makeExtra(); e.stacks = 50
            check(entriesToMap(AG.buildAttrEntries(1, e)) == AD.MAX_HP .. "=50", "hero1 50层→生命+50")
        end
        do -- #2: burnKills=25 → MAG_ATK +5.0
            local e = makeExtra(); e.burnKills = 25
            local got = AG.buildAttrEntries(2, e)
            check(#got == 1 and got[1].key == AD.MAG_ATK and math.abs(got[1].flat - 5.0) < 1e-9,
                "hero2 25燃烧→魔攻+5.0")
        end
        do -- #4: stacks=100 → MAX_HP +50 (系数0.5)
            local e = makeExtra(); e.stacks = 100
            local got = AG.buildAttrEntries(4, e)
            check(#got == 1 and got[1].key == AD.MAX_HP and math.abs(got[1].flat - 50.0) < 1e-9,
                "hero4 100层→生命+50")
        end
        do -- #14: 双属性顺序 PHYS_ATK_BONUS 在前
            local e = makeExtra(); e.stacks = 10
            local got = AG.buildAttrEntries(14, e)
            check(#got == 2 and got[1].key == AD.PHYS_ATK_BONUS and got[2].key == AD.MAG_ATK_BONUS
                and math.abs(got[1].flat - 1.0) < 1e-9 and math.abs(got[2].flat - 1.0) < 1e-9,
                "hero14 10层→双攻%各+1.0(顺序保留)")
        end
        do -- #9/#23: 非击杀口径字段仍映射
            local e9 = makeExtra(); e9.overflowCount = 40
            local g9 = AG.buildAttrEntries(9, e9)
            check(#g9 == 1 and g9[1].key == AD.SPI and math.abs(g9[1].flat - 2.0) < 1e-9,
                "hero9 40溢出治疗→魂火+2.0")
            local e23 = makeExtra(); e23.shieldStacks = 30
            local g23 = AG.buildAttrEntries(23, e23)
            check(#g23 == 1 and g23[1].key == AD.ENERGY_SHIELD and g23[1].flat == 30,
                "hero23 30护盾层→护盾上限+30")
        end
        do -- #19: stacks=40 → 魂火 +2.0；展示改名不改变属性 key/数值。
            local e = makeExtra(); e.stacks = 40
            local got = AG.buildAttrEntries(19, e)
            check(#got == 1 and got[1].key == AD.SPI and math.abs(got[1].flat - 2.0) < 1e-9,
                "hero19 40击杀层→魂火+2.0，仍使用兼容spi存档键")
            check(AD.META[AD.SPI].name == "魂火", "#9/#19共同成长属性的展示名为魂火")
            local ETS = originalRequire("systems.ExtraTalentSystem")
            owned[9] = { awakening = { [1] = true, _awk3Migrated = true } }
            local status = ETS.getStatusLine(9, ETS.normalize({ overflowCount = 40 }))
            check(status:find("魂火 +2.00", 1, true) ~= nil
                and status:find("精神", 1, true) == nil,
                "hero9追加技状态使用属性元数据展示魂火，不再显示旧名精神")
        end
        do -- #10: shareCount=8 → MAX_HP +24
            local e = makeExtra(); e.shareCount = 8
            local got = AG.buildAttrEntries(10, e)
            check(#got == 1 and got[1].flat == 24, "hero10 8分摊→生命+24")
        end
        do -- #16/20/21/22: 专长字段不产属性条目（走系数接口），stacks 也不产
            for _, hid in ipairs({ 16, 20, 21, 22 }) do
                local e = makeExtra(); e.stacks = 99; e.swordStacks = 99; e.gateStacks = 99
                e.nitroKills = 99; e.gatlingKills = 99
                check(#AG.buildAttrEntries(hid, e) == 0,
                    string.format("hero%d 专长字段不进属性表(旧bruteEntries无映射)", hid))
            end
        end
        do -- #17: 任意击杀复用既有 stacks，永久魔攻每层+0.2
            local e = makeExtra(); e.stacks = 99
            local original = makeExtra(); original.stacks = 99
            local applied = AG.applyGrowth(17, e, makeCtx())
            local entries = AG.buildAttrEntries(17, e)
            check(applied and e.stacks == 100 and #entries == 1 and entries[1].key == AD.MAG_ATK
                and math.abs(entries[1].flat - 20) < 1e-9, "hero17 99→100层，永久魔攻+20")
            local onlyStacksChanged = true
            for key, value in pairs(e) do
                if key ~= "stacks" then
                    if type(value) == "table" then
                        if next(value) ~= nil then onlyStacksChanged = false end
                    elseif value ~= original[key] then
                        onlyStacksChanged = false
                    end
                end
            end
            for key in pairs(original) do if e[key] == nil then onlyStacksChanged = false end end
            check(onlyStacksChanged, "hero17 仅改stacks，不新增或修改其他存档字段")
            check(#AG.buildAttrEntries(17, makeExtra()) == 0, "hero17 零层不产魔攻条目")
        end
        do -- 0 层不产条目（旧 data.xxx > 0 守卫）
            local e = makeExtra()
            check(#AG.buildAttrEntries(1, e) == 0, "hero1 0层不产条目")
        end

        -- ========== 6) 上限字段 cap 生效 ==========
        do
            local e = makeExtra()
            -- 用 rule fields cap 验证（当前 RULES 全部无 cap，动态注册一条验证机制）
            AG.RULES[9999] = { cond = "any", fields = { { "beamCharges", 1, 3 } } }
            for _ = 1, 5 do AG.applyGrowth(9999, e, makeCtx()) end
            check(e.beamCharges == 3, "cap 上限机制生效(5次→封顶3)")
            AG.RULES[9999] = originalCapRule
        end

        -- ========== 7) RULES 全覆盖核对：与旧硬编码链的角色集合一致 ==========
        do
            local expected = { 1,2,3,4,5,6,7,8,11,12,13,14,16,17,18,19,20,21,22,24,25 }
            local count = 0
            for _ in pairs(AG.RULES) do count = count + 1 end
            check(count == #expected, string.format("RULES 角色数=%d(期望%d)", count, #expected))
            for _, hid in ipairs(expected) do
                check(AG.hasRule(hid), string.format("hero%d 在 RULES 中", hid))
            end
        end
        -- ========== 8) 阶段状态：真实公式、只读显式快照、调用方门禁 ==========
        do
            local ETS = require("systems.ExtraTalentSystem")
            local CP = require("ui.character.panel.CharacterPanel")
            local I18n = require("core.I18n")
            local oldLanguage = I18n.get()
            local oldGet, oldOwned, oldPatch = CP.getOwnedHero, ETS.getOwned, CP.patchExtraTalent
            local reads, writes = 0, 0
            CP.getOwnedHero = function() reads = reads + 1; error("explicit status read owned") end
            ETS.getOwned = function() reads = reads + 1; error("explicit status called getOwned") end
            CP.patchExtraTalent = function() writes = writes + 1; error("status wrote owned") end
            local statusOk, statusErr = pcall(function()
                I18n.set("zh_CN")
                local e = { stacks = "10.9", biteTypes = { fire = true, ice = true, no = false },
                    tickets = { [1] = true }, markTypes = { shadow = true }, iceStatues = 9,
                    splitKills = 42, preciseStored = 3, blockBank = 7, conquerCarry = 6,
                    beamCharges = 2, slashShadows = 4, gatlingKills = 160 }
                local expected = {
                    [12] = "魔攻 +2.0 · 累计冰冻成长 +0.50%（总概率上限80%）",
                    [15] = "生命上限 +20 · 累计复活成长 +5.0%（总概率上限80%）",
                    [17] = "魔攻 +2.0", [18] = "暴击率 +1.0%", [19] = "魂火 +0.50",
                    [24] = "生命上限 +10", [25] = "物攻 +3.0",
                }
                for id, text in pairs(expected) do
                    check(ETS.getStageStatus(id, 1, e) == text, "hero" .. id .. "初醒累计值不依赖owned觉醒")
                end
                check(ETS.getStageStatus(12, 1, { stacks = 2000 })
                    == "魔攻 +400.0 · 累计冰冻成长 +100.00%（总概率上限80%）",
                    "雪皇高层累计来源不伪装成封顶后的实际总概率")
                check(ETS.getStageStatus(15, 1, { stacks = 240 })
                    == "生命上限 +480 · 累计复活成长 +120.0%（总概率上限80%）",
                    "爱人高层保留raw累计复活成长，80仅标总概率上限")
                check(ETS.getStageStatus(22, 1, { gatlingKills = 240 })
                    == "累计课时缩短 12.00（最短8次攻击）",
                    "课时高层显示既有累计来源与8攻下限，不声称有效减12")
                check(ETS.getStageStatus(22, 1, { gatlingKills = 10 })
                    == "累计课时缩短 0.50（最短8次攻击）",
                    "课时非零小数累计来源准确")
                local inventory = { [1] = "图鉴 2/8", [3] = "预存精准 3/5", [4] = "武德库存 7",
                    [5] = "开场甲片 6", [7] = "预存光线 2/3", [8] = "仇种 1/8", [11] = "斩影 4/4",
                    [12] = "冰雕 3/3", [13] = "分裂击杀 42 · 额外弹射 +5", [15] = "预存票 1",
                    [22] = "预存连打 10/10" }
                for id, text in pairs(inventory) do
                    check(ETS.getStageStatus(id, 2, e) == text, "hero" .. id .. "共鸣真实库存值")
                end
                for id = 1, 25 do
                    check(ETS.getStageStatus(id, 1, e) ~= "", "hero" .. id .. "初醒状态覆盖")
                    check(ETS.getStageStatus(id, 3, e) == "", "hero" .. id .. "蜕变不编造数值")
                end
                for _, id in ipairs({ 2, 6, 9, 10, 14, 16, 17, 18, 19, 20, 21, 23, 24, 25 }) do
                    check(ETS.getStageStatus(id, 2, e) == "", "hero" .. id .. "无真实共鸣库存不编造火种等状态")
                end
                check(ETS.getStageStatus(17, 1, false) == "魔攻 +0.0", "显式false不读档且显示零累计")
                check(ETS.getStageStatus(0, 1) == "" and ETS.getStageStatus(17, 0) == ""
                    and ETS.getStageStatus(17, 4) == "", "未知英雄/非新阶段返回空串且不读档")
                check(e.stacks == "10.9" and e.iceStatues == 9 and e.biteTypes.no == false
                    and e.tickets[1] == true and e.tickets["1"] == nil and e.burnKills == nil,
                    "normalize只操作复制，原表/嵌套map/缺字段保持")
                check(reads == 0 and writes == 0, "显式阶段状态读取owned/getOwned与持久写回均0")
            end)
            CP.getOwnedHero, ETS.getOwned, CP.patchExtraTalent = oldGet, oldOwned, oldPatch
            I18n.set(oldLanguage)
            check(statusOk, "只读阶段状态执行无异常: " .. tostring(statusErr))
            local snapshot = { stacks = "10.9", biteTypes = { fire = true } }
            CP.getOwnedHero = function() return { extraTalent = snapshot, awakening = {} } end
            local omittedOk, omittedStatus = pcall(ETS.getStageStatus, 17, 1)
            CP.getOwnedHero = oldGet
            check(omittedOk and omittedStatus == I18n.format("魔攻 +%.1f", 2), "省略extra只读owned快照")
            check(snapshot.stacks == "10.9" and snapshot.iceStatues == nil
                and snapshot.biteTypes.fire == true, "省略extra也不normalize写回原档")
        end
    end)

    -- 即使cap或状态展示测试异常，也不能把规则替身/require留给下一轮运行。
    AG.RULES[9999] = originalCapRule
    require = originalRequire
    check(AG.RULES[9999] == originalCapRule and require == originalRequire,
        "测试结束恢复临时cap规则和require替身")
    if not ok then
        print("[ERROR] 测试异常: " .. tostring(err))
        failures[#failures + 1] = "exception: " .. tostring(err)
    end

    if #failures == 0 then
        print("[awakening_growth_equivalence_test] ALL PASS")
    else
        print(string.format("[awakening_growth_equivalence_test] %d FAILURES", #failures))
        for _, f in ipairs(failures) do print("  - " .. f) end
    end
    engine:Exit()
end
