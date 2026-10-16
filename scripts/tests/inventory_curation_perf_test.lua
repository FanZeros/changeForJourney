-- 纯规划软件CPU样本，不设设备FPS/用户等待阈值。File/FS封闭且禁用随机。
local F = require("tests.InventoryCurationFixture")
local TAG = "[inventory_curation_perf_test]"
function Start()
    local ok, err = pcall(function()
        local h = F.new()
        local Curation = h.require("systems.InventoryCuration")
        local bag = F.bag(h, 500)
        local templates = { "W1", "C1", "A1", "H1", "S1", "O1" }
        for _, count in ipairs({ 500, 2000, 10000 }) do
            local seeds = {}
            for i = 1, count do
                local item = F.item(h, templates[(i - 1) % #templates + 1], (i - 1) % 200 + 1, (i - 1) % 6 + 1)
                seeds[i] = { quality = item.quality, level = item.level, count = 1, equip = item, source = "overflow" }
            end
            local box = { seeds = seeds }
            local beforeBag, beforeBox = F.copy(bag), F.copy(box)
            local samples, moves = {}, 0
            for run = 1, 3 do
                local started = os.clock()
                local p, why = Curation.plan(bag, box)
                local elapsed = (os.clock() - started) * 1000
                assert(p, tostring(why))
                samples[run], moves = elapsed, p.moveInCount + p.moveOutCount
                assert(p.counts.inventoryAfter <= 500 and p.moveInCount == p.moveOutCount, "full bag conservation")
            end
            F.same(bag, beforeBag, "perf inventory read only")
            F.same(box, beforeBox, "perf lootbox read only")
            print(TAG .. string.format(" SAMPLE inventory=500 lootbox=%d cpu_ms=%.3f,%.3f,%.3f moves=%d",
                count, samples[1], samples[2], samples[3], moves))
        end
        assert(h.randomCalls == 0 and h.fileCalls == 0 and h.fsCalls == 0, "perf no RNG/File/FS")
        for _, boxCount in ipairs({ 500, 10000 }) do
        local tx = F.new()
        local modules = F.modules(tx, 500)
        modules.lootbox.seeds = {}
        for i = 1, boxCount do
            local item = F.item(tx, "W1", i % 200 + 1, 5)
            modules.lootbox.seeds[i] = { quality = item.quality, level = item.level, count = 1, equip = item, source = "overflow" }
        end
        tx:attach(modules)
        tx:connectService()
        local started = os.clock()
        local previewed, why, preview = tx.Service.PreviewInventoryCuration(1)
        local previewMS = (os.clock() - started) * 1000
        assert(previewed, tostring(why))
        local confirmStarted = os.clock()
        local applied, applyErr = tx.Service.ApplyInventoryCuration(1, preview.token)
        local confirmMS = (os.clock() - confirmStarted) * 1000
        assert(applied, tostring(applyErr))
        local totalMS = (os.clock() - started) * 1000
        assert(tx.pushes.equipment == 1 and tx.pushes.lootbox == 1 and tx.randomCalls == 0, "complete transaction contract")
        print(TAG .. string.format(" TRANSACTION inventory=500 lootbox=%d preview_cpu_ms=%.3f apply_including_virtualSave_cpu_ms=%.3f total_cpu_ms=%.3f bytes=%d",
            boxCount, previewMS, confirmMS, totalMS, #tx.disk["standalone_save.json"]))
        end
        print(TAG .. " ALL PASS softwareCPUOnly=true planSamples=9 transactionSamples=2 virtualFile=true")
    end)
    if not ok then print(TAG .. " [FAIL] " .. tostring(err)) end
    engine:Exit()
end
