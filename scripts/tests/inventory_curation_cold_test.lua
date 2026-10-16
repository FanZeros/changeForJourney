-- 两个独立Runtime间传递仅测试虚拟盘JSON，由内部launcher冻结并注入；原生File/FS从不委托。
local F = require("tests.InventoryCurationFixture")
local TAG = "[inventory_curation_cold_test]"
local M = {}
local assertions = 0
local function check(value, label) assertions = assertions + 1; assert(value, label) end
local function eq(a, b, label) check(a == b, label .. " " .. tostring(a) .. "/" .. tostring(b)) end
local function same(a, b, label) assertions = assertions + 1; F.same(a, b, label) end
local function naked(item)
    local out = F.copy(item)
    out.seq = nil
    return out
end
local function allObjects(modules)
    local result = {}
    for _, item in pairs(modules.equipment.inventory) do result[#result + 1] = item end
    for _, seed in ipairs(modules.lootbox.seeds) do if seed.equip then result[#result + 1] = seed.equip end end
    return result
end
local function apply(h)
    local ok, err, p = h.Service.PreviewInventoryCuration(1)
    check(ok, "preview " .. tostring(err))
    local applied, why = h.Service.ApplyInventoryCuration(1, p.token)
    check(applied, "apply " .. tostring(why))
    return p
end
local function produce()
    local h = F.new()
    local modules = F.modules(h, 500)
    modules.equipment.inventory["500"].extraOpaque = { payload = { 2, 3, 5, 7 }, note = "outgoing-full-object" }
    local high = F.item(h, "W1", 60, 5)
    high.affixes = { { affixId = 1, quality = 2, value = 1.25, ascBonus = 0.5 } }
    high.ascendLevel, high.enhanceLevel, high.affixMult, high.refineCount = 11, 11, 1.2, 3
    high.corruptCount, high.corruptBaseMult = 1, 1.1
    high.corruptRevert = { baseMult = 1, affixCount = 1, patches = {} }
    high.extraOpaque = { payload = { 11, 13 }, note = "incoming-full-object" }
    -- 使用正式水合规范化夹具一次，保存恢复测试不把非法夹具规范化当作字段丢失。
    h.require("systems.EquipmentSystem").hydrate(high)
    modules.lootbox = F.box({ high, F.item(h, "W1", 40, 3) })
    h:attach(modules)
    h:connectService()
    local original, total = {}, 0
    for _, item in ipairs(allObjects(modules)) do original[item], total = naked(item), total + 1 end
    local p = apply(h)
    eq(p.moveInCount, 2, "two incoming")
    for _, item in ipairs(allObjects(modules)) do same(naked(item), original[item], "initial full-field transfer") end
    local movedSeq = modules.lootbox.seeds[1].originalSeq
    check(movedSeq ~= nil, "outgoing audit seq exists")
    -- 确定seed反复领取→更强候选替换→回匣；不能合并重复或丢opaque/嵌套字段。
    local LS, ES = h.require("systems.LootBoxSystem"), h.require("systems.EquipmentSystem")
    local curationItem = modules.lootbox.seeds[1].equip
    local originalFields = naked(curationItem)
    for round = 1, 3 do
        -- 测试人为腾一格并将原物放入遗匣，不销毁物品；新seq由正式claimGroup分配。
        local oldKey = tostring(20 + round)
        local old = modules.equipment.inventory[oldKey]
        check(old ~= nil, "reserved ordinary instance exists")
        modules.equipment.inventory[oldKey] = nil
        LS.addEquipment(modules.lootbox, old, "curation")
        local index = 0
        for i, seed in ipairs(modules.lootbox.seeds) do if seed.equip == curationItem then index = i; break end end
        check(index > 0, "same curation item indexed")
        local oldSeq = curationItem.seq
        local claimed, full = LS.claimGroup(modules.lootbox, index, modules.equipment)
        eq(#claimed, 1, "direct reclaim complete object")
        eq(full, false, "one slot available")
        eq(claimed[1], curationItem, "same instance after reclaim")
        check(curationItem.seq > oldSeq, "fresh sequence on reclaim")
        same(naked(curationItem), originalFields, "reclaim non-seq fields unchanged")
        h:resetNotifications()
        -- 未投入普通低分原件会在新高分seed到来时再安全移出。
        local stronger = F.item(h, "W1", 100 + round, 5)
        stronger.extraOpaque = { round = round, note = "retained" }
        LS.addEquipment(modules.lootbox, stronger)
        original[stronger], total = naked(stronger), total + 1
        apply(h)
        eq(ES.getInventoryCount(modules.equipment), 500, "repeated transfer capacity")
    end
    local current = allObjects(modules)
    eq(#current, total, "count preserved across repeated moves plus explicit drops")
    local seen = {}
    for _, item in ipairs(current) do
        check(not seen[item], "no duplicate instance")
        seen[item] = true
        same(naked(item), original[item], "all original full fields after repeated moves")
    end
    eq(h.randomCalls, 0, "save/transfer no random")
    local serialized = h.disk["standalone_save.json"]
    check(type(serialized) == "string", "real StandaloneSave writes virtual disk")
    local parsed = cjson.decode(serialized)
    eq(parsed.version, 1, "existing save version")
    eq(#parsed.modules.lootbox.seeds, #modules.lootbox.seeds, "complete seed array encoded")
    local payload = { disk = serialized, modules = modules, total = total, oldToken = p.token }
    print("[CURATION_COLD_JSON]" .. cjson.encode(payload))
    print(TAG .. " PRODUCER PASS assertions=" .. assertions .. " virtualFile=true")
end

local function restore(payload)
    check(type(payload) == "table" and type(payload.disk) == "string", "fresh process payload")
    local h = F.new({ ["standalone_save.json"] = payload.disk })
    h:attach({})
    h:connectService()
    eq(next(h.Dispatcher.getAll()), nil, "fresh Dispatcher empty")
    check(h.Save.RestoreData(), "real StandaloneSave.RestoreData through closed virtualFile")
    local modules = h.Dispatcher.getAll()
    h.PDM.AttachLocalModules(1, modules)
    h.modules = modules
    local saved = cjson.decode(payload.disk)
    -- 精确复现正式RestoreData的二次JSON+Registry/Schema，不用epsilon或舍入掩盖。
    local registry, schema = h.require("shared.ModuleRegistry"), h.require("shared.schemas.CharacterSchema")
    for _, name in ipairs({ "equipment", "lootbox" }) do
        local expected = cjson.decode(cjson.encode({ modules = { [name] = saved.modules[name] } })).modules[name]
        registry.applyOnLoad(name, expected)
        schema.applyOnLoad(name, expected)
        same(modules[name], expected, "actual cold restore exact dual-onLoad " .. name)
    end
    eq(h.require("systems.EquipmentSystem").getInventoryCount(modules.equipment), 500, "cold capacity")
    eq(#allObjects(modules), payload.total, "cold no lost or extra full equipment")
    local count, opaque = 0, false
    for index, seed in ipairs(saved.modules.lootbox.seeds) do
        if seed.source == "curation" then
            count = count + 1
            eq(modules.lootbox.seeds[index].source, "curation", "curation source preserved " .. index)
            eq(modules.lootbox.seeds[index].originalSeq, seed.originalSeq, "original seq preserved " .. index)
            same(modules.lootbox.seeds[index].equip, seed.equip, "complete full seed object preserved " .. index)
            if seed.equip.extraOpaque then opaque = true end
        end
    end
    check(count > 0 and opaque, "actual curation seed opaque test data survived")
    local before, disk = F.copy(modules), F.copy(h.disk)
    eq(h.Service.ApplyInventoryCuration(1, payload.oldToken), false, "process-private old token not persisted")
    same(modules, before, "old token cold no mutation")
    eq(h.flushCalls, 0, "cold rejected token no Flush")
    for _ = 1, 3 do
        registry.applyOnLoad("equipment", modules.equipment)
        schema.applyOnLoad("equipment", modules.equipment)
        registry.applyOnLoad("lootbox", modules.lootbox)
        schema.applyOnLoad("lootbox", modules.lootbox)
    end
    same(modules, before, "repeated dual schema idempotent")
    same(h.disk, disk, "read only cold restore never rewrites disk")
    local ok, err, preview = h.Service.PreviewInventoryCuration(1)
    check(ok, "cold preview " .. tostring(err))
    eq(preview.changed, false, "already curated cold result idempotent")
    local LS = h.require("systems.LootBoxSystem")
    local essence, pieces = LS.decomposeAll(modules.lootbox)
    eq(essence, 0, "cold curation no recycle essence")
    eq(pieces, 0, "cold curation no recycle pieces")
    same(modules, before, "cold denied recycle preserves every field")
    eq(h.randomCalls, 0, "cold no random")
    print(TAG .. " SUMMARY assertions=" .. assertions .. " failures=0 coldProcess=true virtualFile=true")
    print(TAG .. " ALL PASS")
end

function M.run(payload)
    local ok, err = pcall(function() if payload then restore(payload) else produce() end end)
    if not ok then print(TAG .. " [FAIL] after " .. assertions .. " " .. tostring(err)) end
    engine:Exit()
end
function Start() M.run(nil) end
return M
