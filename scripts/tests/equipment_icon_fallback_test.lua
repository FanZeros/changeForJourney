-- 装备图标与防具套装回归测试
-- 文件存在不等于部位正确：H13/H19 原图是胸甲，H25/H31 原图是全身重铠。
-- 除全部模板的有效句柄外，还校验实际命中路径、同系列套装归属及旧精简存档水合。

local ImageCache = require("ui.widget.ImageCache")
local EquipmentConfig = require("config.EquipmentConfig")
local EquipmentSetConfig = require("config.EquipmentSetConfig")
local EquipmentSetSystem = require("systems.EquipmentSetSystem")
local EquipmentSystem = require("systems.EquipmentSystem")

local pass, fail = 0, 0
local function check(cond, label)
    if cond then
        pass = pass + 1
        print("[icon_fallback] [PASS] " .. label)
    else
        fail = fail + 1
        print("[icon_fallback] [FAIL] " .. label)
    end
end

-- 独立预期，不从待测模板的 setId/iconTemplateId 反推答案。
local OLD_SET_IDS = {
    "emberscout", "faceless", "nitros", "nitros", "carapace",
    "carapace", "ironwall", "ironwall", "tidepress", "last_rite",
}
local NEW_SET_IDS = {
    "emberscout", "swordgate", "bonehunger", "riftcrystal", "starless", "gambler",
}
-- 根据实际 PNG 逐张确认的同部位来源；轻甲/重甲源不得是 H13/H19/H25/H31。
local HELMET_SOURCES = { "H1", "H7", "H37", "H37", "H43", "H43", "H37", "H43", "H49", "H55" }
local NEW_HELMET_SOURCES = { "H1", "H43", "H43", "H55", "H49", "H7" }
local NEW_ARMOR_SOURCES = { "A1", "A31", "A31", "A55", "A49", "A7" }
local NEW_SHOES_SOURCES = { "S1", "S25", "S25", "S55", "S49", "S7" }
local ARMOR_SLOTS = { "armor", "helmet", "shoes" }

local function expectedSetId(slot, num)
    if slot == "helmet" and num == 6 then return "faceless" end -- 保留旧影皮归属
    if num <= 60 then return OLD_SET_IDS[math.floor((num - 1) / 6) + 1] end
    return NEW_SET_IDS[num - 60]
end

local function checkArmorMappings(handlePaths, createdPaths)
    local total = 0
    for _, slot in ipairs(ARMOR_SLOTS) do
        local prefix = EquipmentConfig.SLOT_PREFIX[slot]
        for _, id in ipairs(EquipmentConfig.BY_SLOT[slot]) do
            total = total + 1
            local tpl = EquipmentConfig.ITEMS[id]
            local num = tonumber(string.sub(id, 2)) or 0
            local expected = expectedSetId(slot, num)
            check(expected ~= nil and tpl.setId == expected
                and EquipmentSetConfig.getSetIdForTemplate(tpl) == expected
                and EquipmentSetConfig.get(expected) ~= nil, id .. " 显式归属=" .. tostring(expected))
            check(EquipmentSetConfig.getSetIdForTemplate({ name = "无套装关键词", slot = slot,
                type = tpl.type, setId = tpl.setId }) == expected, id .. " 改展示名不改变归属")

            local source = prefix .. tostring(math.floor((num - 1) / 6) * 6 + 1)
            if slot == "helmet" then
                source = num <= 60 and HELMET_SOURCES[math.floor((num - 1) / 6) + 1]
                    or NEW_HELMET_SOURCES[num - 60]
            elseif num > 60 then
                source = slot == "armor" and NEW_ARMOR_SOURCES[num - 60] or NEW_SHOES_SOURCES[num - 60]
            end
            local sourceTpl = source and EquipmentConfig.ITEMS[source]
            local expectedPath = "image/装备图标/UI_icon_ZB_" .. tostring(source) .. ".png"
            check(sourceTpl ~= nil and sourceTpl.slot == slot
                and handlePaths[ImageCache.getEquipIcon(id)] == expectedPath,
                id .. " 实际命中同部位图=" .. tostring(source))
            if slot == "helmet" and ((num >= 13 and num <= 36) or num == 62 or num == 63) then
                check(tpl.iconTemplateId == source and EquipmentConfig.getIconPath(id) == expectedPath,
                    id .. " 模板直接绕开错部位原图")
            end
        end
    end
    check(total == 198, "旧180件与新增18件防具全部覆盖 (实际=" .. total .. ")")
    for _, id in ipairs({ "H13", "H19", "H25", "H31" }) do
        check(createdPaths["image/装备图标/UI_icon_ZB_" .. id .. ".png"] == nil,
            "加载全过程未触达错部位原图 " .. id)
    end
end

local function sameData(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not sameData(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

local function checkLegacyHydrate()
    -- 每个旧/新增防具编号构造一组真实精简档；不生成装备，不消费随机数。
    for num = 1, 66 do
        local inventory, equipped = {}, {}
        for i, slot in ipairs(ARMOR_SLOTS) do
            local id = EquipmentConfig.SLOT_PREFIX[slot] .. tostring(num)
            local tpl = EquipmentConfig.ITEMS[id]
            local seq = 200 + i
            local equip = { templateId = id, level = tpl.levelRange[1], quality = (num - 1) % 6 + 1,
                locked = true, ascendLevel = 2, affixes = {} }
            inventory[i == 1 and seq or tostring(seq)] = equip -- 兼容两种库存键
            equipped[slot] = seq
            local hydrated = EquipmentSystem.hydrate(equip)
            check(hydrated == equip and equip.templateId == id and equip.slot == slot
                and equip.name == tpl.name and equip.type == tpl.type,
                id .. " 旧精简档原地水合且ID/部位不变")
            check(equip.level == tpl.levelRange[1] and equip.quality == (num - 1) % 6 + 1
                and equip.locked == true and equip.ascendLevel == 2
                and equip.baseStats ~= nil, id .. " 水合保留等级/品质/锁定/升阶并还原属性")
            local lean = EquipmentSystem.dehydrate(equip)
            local restored = EquipmentSystem.hydrate(lean)
            check(sameData(equip.baseStats, restored.baseStats) and restored.templateId == id
                and restored.level == equip.level and restored.quality == equip.quality
                and restored.locked == true and restored.ascendLevel == 2,
                id .. " 脱水再水合属性与持久字段不变")
            -- 即使旧实例残留错误展示归属，正式计数仍读模板，不能靠修一个实例解决。
            equip.setId = "旧实例残留"
        end
        local eqData = { inventory = inventory, equipped = { ["9"] = equipped } }
        local counts = EquipmentSetSystem.countSets(eqData, 9,
            EquipmentSystem.getFromInventory, EquipmentSystem.getHeroSlots)
        local expected = expectedSetId("armor", num)
        local expectedCounts = { [expected] = 3 }
        if num == 6 then expectedCounts = { emberscout = 2, faceless = 1 } end
        check(sameData(counts, expectedCounts), "编号" .. num .. " 三部位正式套装计数一致（H6保留旧例外）")
    end
end

function Start()
    pass, fail = 0, 0
    local originalCreateImage, originalDeleteImage = nvgCreateImage, nvgDeleteImage
    -- 探针式 mock：纹理文件存在 → 返回正 handle；不存在 → 返回 -1（复现原 bug 的加载失败条件）
    local nextHandle = 1000
    local createdPaths, handlePaths = {}, {}
    nvgCreateImage = function(_vg, path, _flags)
        createdPaths[path] = (createdPaths[path] or 0) + 1
        local tex = cache:GetResource("Texture2D", path)
        if tex then
            nextHandle = nextHandle + 1
            handlePaths[nextHandle] = path
            return nextHandle
        end
        return -1
    end
    nvgDeleteImage = function() end -- 假句柄不能交给原生释放接口

    ImageCache.init({})  -- 假 vg 上下文（mock 不依赖真实 vg）

    -- 收集配置里全部 templateId
    local ids = {}
    for id in pairs(EquipmentConfig.ITEMS) do ids[#ids + 1] = id end
    table.sort(ids)
    check(#ids >= 300, "配置模板 ID 数量充足 (实际=" .. #ids .. ")")

    -- 断言 1：每个 ID 经 ImageCache.getEquipIcon 都返回正 handle（fallback 全覆盖）
    local ok, bad = 0, {}
    for _, id in ipairs(ids) do
        local h = ImageCache.getEquipIcon(id)
        if h and h > 0 then ok = ok + 1 else bad[#bad + 1] = id end
    end
    check(ok == #ids, "全部 " .. #ids .. " 个 ID 经 fallback 返回有效图标 (成功=" .. ok .. " 失败=" .. #bad
        .. (bad[1] and (" 首例=" .. bad[1]) or "") .. ")")

    -- 断言 2：非组首 ID（如 W2）确实走了 fallback，最终命中的是组首图 W1 的 path
    local w2 = ImageCache.getEquipIcon("W2")
    check(w2 and w2 > 0, "W2（非组首）返回有效 handle=" .. tostring(w2))
    check(createdPaths["image/装备图标/UI_icon_ZB_W1.png"] ~= nil,
        "W2 的加载尝试触达了组首图 W1（fallback 生效）")

    -- 断言 3：组首 ID 本身直接命中（无需 fallback）
    local w7 = ImageCache.getEquipIcon("W7")
    check(w7 and w7 > 0, "W7（组首）返回有效 handle=" .. tostring(w7))

    -- 断言 4：缓存幂等——同 ID 第二次取不重复创建纹理
    local before = createdPaths["image/装备图标/UI_icon_ZB_W1.png"] or 0
    ImageCache.getEquipIcon("W2")
    local after = createdPaths["image/装备图标/UI_icon_ZB_W1.png"] or 0
    check(before == after, "重复获取 W2 命中缓存，不再重复加载 W1 (前=" .. before .. " 后=" .. after .. ")")

    -- 断言 5：同部位图标及旧/新增防具套装归属；原图存在也不能绕过这组检查。
    checkArmorMappings(handlePaths, createdPaths)
    checkLegacyHydrate()

    nvgCreateImage, nvgDeleteImage = originalCreateImage, originalDeleteImage
    ImageCache.init(nil) -- 假上下文不留给后续测试/退出释放
    print("[icon_fallback] RESULT " .. (fail == 0 and ("ALL PASS (" .. pass .. ")") or (pass .. " PASS / " .. fail .. " FAIL")))
    if engine and engine.Exit then engine:Exit() end
end
