-- 已确认一转资源契约：真实PNG/配置检查，不加载游戏或读写玩家存档。
-- UrhoXRuntime tests/advancement_icon_asset_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
local AVC = require("config.AdvancementConfig")
local CC = require("config.ClassConfig")
local ROOT = "image/职业图标/"
local passes, failures = 0, 0
---@type Image[]
local images = {}
local function check(ok, label)
    if ok then passes = passes + 1 else failures = failures + 1 end
    print((ok and "[PASS] " or "[FAIL] ") .. label)
end

-- 第一批授权十图；UUID固定为替换前已存在meta，不生成/更新meta。
local BATCH1 = {
    { 1, "seal", 0, 0, "gate_seal_rift", "C3oGqRUwT4JIgJbzeaf22GKu" },
    { 6, "debt", 0, 0, "gate_debt_defer", "EqKL8cj5hYzTbivPK1PReDae" },
    { 201, "seal", 2, 101, "gate_201_seal_strip", "FbAHKVA_AC4-re6Ah9F9iqLh" },
    { 202, "seal", 2, 101, "gate_202_martyr", "EPqGOZ9lN2Koe4xtmCWny9fZ" },
    { 203, "seal", 2, 102, "gate_203_deadgate", "FPW2UTFvEKZP_TxlPuow_scH" },
    { 204, "seal", 2, 102, "gate_204_recoil", "DRmG2VchHcYWvUe_wlESnogy" },
    { 221, "debt", 2, 111, "gate_221_war", "F-odcdRFd8wpRTKdQFtQmwLe" },
    { 222, "debt", 2, 111, "gate_222_blood", "EHro2TVyOjH-U5Kimsd7jOsn" },
    { 223, "debt", 2, 112, "gate_223_pardon", "CpRuCRRv9b__jAc7DuA0CcDa" },
    { 224, "debt", 2, 112, "gate_224_punish", "C642ARpXZT1fGVPXzUs6Rnqp" },
}
---@type table<number, Image>
local batchImages = {}
local function readMeta(id)
    -- ReadString读的是零终止串，不是整份JSON；与现有源码夹具同用ReadLine/IsEof。
    local file = File("/workspace/assets/" .. ROOT .. "UI_icon_ZY_" .. id .. ".png.meta", FILE_READ)
    local ok, text = pcall(function()
        assert(file:IsOpen(), "无法打开meta " .. id)
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        return table.concat(lines, "\n")
    end)
    file:Dispose()
    assert(ok, text)
    return cjson.decode(text)
end
local function testBatch1()
    check(CC.KNIGHT == "seal" and CC.PRIEST == "debt", "第一批真实classId为seal/debt")
    check(AVC.COST[1].level == 10 and AVC.COST[1].gold == 10000, "保留一转10级10000金币")
    check(AVC.COST[2].level == 25 and AVC.COST[2].gold == 100000, "保留二转25级100000金币")
    local uuids = {}
    for _, row in ipairs(BATCH1) do
        local id, classId, level, parent, talentId = row[1], row[2], row[3], row[4], row[5]
        local cfg = level == 0 and CC.get(classId) or AVC.get(id)
        check(cfg ~= nil, id .. "真实配置存在")
        if level == 0 then
            check(AVC.get(id) == nil and CC.get(classId).name == (id == 1 and "封门人" or "司仪"), id .. "基础职业归属不误作转职分支")
            check(CC.get(classId).talentId == talentId, id .. "基础天赋保持")
        else
            check(cfg.baseClass == classId and cfg.advLevel == 2 and cfg.combatPower == 20, id .. "二转职业归属阶段战力保持")
            check(cfg.parentBranch == parent and AVC.get(parent).baseClass == classId, id .. "parent与baseClass一致")
            local siblings = AVC.SECOND_BRANCHES[parent]
            check(siblings and (siblings[1] == id or siblings[2] == id), id .. "原父分支映射包含自身")
            check(cfg.talentId == talentId, id .. "原天赋保持")
            check(not AVC.canAdvance(24, 1000000, 2, classId, id, { first = parent }), id .. "二十四级拒绝")
            check(AVC.canAdvance(25, 100000, 2, classId, id, { first = parent }), id .. "二十五级精确金币门槛开放")
            check(not AVC.canAdvance(25, 99999, 2, classId, id, { first = parent }), id .. "少一金币拒绝")
            check(not AVC.canAdvance(30, 1000000, 2, classId, id, nil), id .. "缺一转拒绝")
            check(not AVC.canAdvance(30, 1000000, 2, classId, id, { first = parent, second = id }), id .. "已有二转拒绝")
            local wrongParent = classId == "seal" and 111 or 101
            check(not AVC.canAdvance(30, 1000000, 2, classId, id, { first = wrongParent }), id .. "不串另一基础职业父分支")
            local otherParent = parent % 2 == 1 and parent + 1 or parent - 1
            check(not AVC.canAdvance(30, 1000000, 2, classId, id, { first = otherParent }), id .. "不串同职业另一路父分支")
            check(not AVC.canAdvance(30, 1000000, 1, classId, id, nil), id .. "二转图不走一转门槛")
        end
        local meta = readMeta(id)
        check(meta.uuid == row[6], id .. "原meta UUID逐字保持")
        check(not uuids[meta.uuid], id .. "UUID无重复归属")
        uuids[meta.uuid] = true
        local file = assert(cache:GetFile(ROOT .. "UI_icon_ZY_" .. id .. ".png"))
        file:Dispose()
        local image = Image()
        images[#images + 1] = image
        batchImages[id] = image
        local loaded = image:Load("/workspace/assets/" .. ROOT .. "UI_icon_ZY_" .. id .. ".png")
        check(loaded, id .. "第一批真实PNG可加载")
        check(image.width == 280 and image.height == 280 and image.components == 4, id .. "第一批280×280 RGBA")
        if loaded and image.width == 280 and image.height == 280 then
            local transparent, opaque, partial, dirty, outside, changed = 0, 0, 0, 0, 0, 0
            for y = 0, 279 do
                for x = 0, 279 do
                    local c = image:GetPixel(x, y)
                    if c.a == 0 then
                        transparent = transparent + 1
                        if c.r ~= 0 or c.g ~= 0 or c.b ~= 0 then dirty = dirty + 1 end
                    elseif c.a == 1 then opaque = opaque + 1
                    else partial = partial + 1 end
                    local differs = image:GetPixelInt(x, y) ~= images[1]:GetPixelInt(x, y)
                    if (x - 139.5) ^ 2 + (y - 139.5) ^ 2 > 114 ^ 2 then
                        if differs then outside = outside + 1 end
                    elseif differs then changed = changed + 1 end
                end
            end
            check(transparent > 20000 and opaque > 50000, id .. "第一批透明四角与实体底板")
            check(partial > 100 and dirty == 0, id .. "第一批抗锯齿无透明残色")
            check(image:GetPixel(0, 0).a == 0 and image:GetPixel(279, 279).a == 0, id .. "第一批画布边界透明")
            check(outside == 0, id .. "半径114外与111共用底板逐像素相同 mismatch=" .. outside)
            check(changed > 500, id .. "半径114内不是复制111 changed=" .. changed)
        end
    end
    -- 全十图两两比较，防止不同职业/不同父分支误装成另一已通过的图。
    for i = 1, #BATCH1 - 1 do
        for j = i + 1, #BATCH1 do
            local idA, idB = BATCH1[i][1], BATCH1[j][1]
            local a, b = batchImages[idA], batchImages[idB]
            local changed = 0
            for y = 26, 253 do
                for x = 26, 253 do
                    if (x - 139.5) ^ 2 + (y - 139.5) ^ 2 <= 114 ^ 2
                        and a:GetPixelInt(x, y) ~= b:GetPixelInt(x, y) then
                        changed = changed + 1
                    end
                end
            end
            check(changed > 500, idA .. "/" .. idB .. "第一批无重复主体 changed=" .. changed)
        end
    end
    -- 不仅比较文件或RGBA不同，也比较骨白主轮廓占位；纯统一换色不能替代职业结构差异。
    for _, pair in ipairs({ { 1, 6 }, { 201, 202 }, { 203, 204 }, { 221, 222 }, { 223, 224 } }) do
        local a, b = batchImages[pair[1]], batchImages[pair[2]]
        local changed, shapeChanged = 0, 0
        for y = 26, 253 do
            for x = 26, 253 do
                if (x - 139.5) ^ 2 + (y - 139.5) ^ 2 <= 114 ^ 2 then
                    if a:GetPixelInt(x, y) ~= b:GetPixelInt(x, y) then changed = changed + 1 end
                    local ca, cb = a:GetPixel(x, y), b:GetPixel(x, y)
                    local brightA = ca.a > 0.5 and (ca.r + ca.g + ca.b) / 3 > 0.55
                    local brightB = cb.a > 0.5 and (cb.r + cb.g + cb.b) / 3 > 0.55
                    if brightA ~= brightB then shapeChanged = shapeChanged + 1 end
                end
            end
        end
        local label = pair[1] .. "/" .. pair[2]
        check(changed > 500, label .. "主体像素差异=" .. changed)
        check(shapeChanged > 200, label .. "骨白主轮廓占位差异=" .. shapeChanged)
    end
end

function Start()
    local ok, err = pcall(function()
        for _, id in ipairs({ 111, 112 }) do
            local cfg = AVC.get(id)
            check(cfg.baseClass == CC.PRIEST and cfg.advLevel == 1, id .. "司仪一转归属")
            check(cfg.combatPower == 15, id .. "原战力不变")
            check(not AVC.canAdvance(9, 1000000, 1, CC.PRIEST, id, nil), id .. "九级不开放")
            check(AVC.canAdvance(10, 10000, 1, CC.PRIEST, id, nil), id .. "十级原金币门槛")
            check(not AVC.canAdvance(10, 9999, 1, CC.PRIEST, id, nil), id .. "金币不足拒绝")
            check(not AVC.canAdvance(10, 10000, 1, CC.KNIGHT, id, nil), id .. "错职业拒绝")
            check(not AVC.canAdvance(30, 1000000, 1, CC.PRIEST, id, { first = id }), id .. "不重复一转")
            local image = Image()
            images[#images + 1] = image
            -- 单独核验资源根解析；Image:Load采用现有烘焙脚本已实测的文件名重载。
            local file = assert(cache:GetFile(ROOT .. "UI_icon_ZY_" .. id .. ".png"))
            file:Dispose()
            local loaded = image:Load("/workspace/assets/" .. ROOT .. "UI_icon_ZY_" .. id .. ".png")
            check(loaded, id .. "真实PNG资源可加载")
            check(image.width == 280 and image.height == 280 and image.components == 4, id .. "280×280 RGBA")
            local transparent, partial, opaque, dirty = 0, 0, 0, 0
            for y = 0, 279 do
                for x = 0, 279 do
                    local c = image:GetPixel(x, y)
                    if c.a == 0 then
                        transparent = transparent + 1
                        if c.r ~= 0 or c.g ~= 0 or c.b ~= 0 then dirty = dirty + 1 end
                    elseif c.a == 1 then opaque = opaque + 1
                    else partial = partial + 1 end
                end
            end
            check(transparent > 20000 and opaque > 50000, id .. "透明四角和实体底板")
            check(partial > 100 and dirty == 0, id .. "抗锯齿边缘与零透明残色")
            check(image:GetPixel(0, 0).a == 0 and image:GetPixel(279, 279).a == 0, id .. "画布边界透明")
        end
        check(AVC.get(111).talentId == "gate_111_defer2", "延祷机制不变")
        check(AVC.get(112).talentId == "gate_112_confess", "领忏机制不变")
        for _, row in ipairs({ { 111, 221, 223 }, { 112, 223, 221 } }) do
            local branch = { first = row[1] }
            check(not AVC.canAdvance(24, 100000, 2, CC.PRIEST, row[2], branch), "二转二十四级拒绝")
            check(AVC.canAdvance(25, 100000, 2, CC.PRIEST, row[2], branch), "二转二十五级原门槛")
            check(not AVC.canAdvance(25, 100000, 2, CC.PRIEST, row[3], branch), "二转不串分支")
        end
        local shared, different = true, false
        for y = 0, 279 do
            for x = 0, 279 do
                local a, b = images[1]:GetPixelInt(x, y), images[2]:GetPixelInt(x, y)
                -- 主体断链最外端含描边/降采样到半径111；底板从内圈114外核验。
                if (x - 139.5) ^ 2 + (y - 139.5) ^ 2 > 114 ^ 2 then
                    if a ~= b then shared = false end
                elseif a ~= b then different = true end
            end
        end
        check(shared, "两图全新外圈底板逐像素一致")
        check(different, "两分支不是同图换色")
        -- 封门人本轮由用户确认替换，新增覆盖而不删除司仪原34项。
        for _, id in ipairs({ 101, 102 }) do
            local cfg = AVC.get(id)
            check(cfg.baseClass == CC.KNIGHT and cfg.advLevel == 1, id .. "封门人一转归属")
            check(cfg.combatPower == 15, id .. "原战力不变")
            check(not AVC.canAdvance(9, 1000000, 1, CC.KNIGHT, id, nil), id .. "九级不开放")
            check(AVC.canAdvance(10, 10000, 1, CC.KNIGHT, id, nil), id .. "十级原金币门槛")
            check(not AVC.canAdvance(10, 9999, 1, CC.KNIGHT, id, nil), id .. "金币不足拒绝")
            check(not AVC.canAdvance(10, 10000, 1, CC.PRIEST, id, nil), id .. "错职业拒绝")
            local file = assert(cache:GetFile(ROOT .. "UI_icon_ZY_" .. id .. ".png"))
            file:Dispose()
            local image = Image()
            images[#images + 1] = image
            check(image:Load("/workspace/assets/" .. ROOT .. "UI_icon_ZY_" .. id .. ".png"), id .. "真实PNG资源可加载")
            check(image.width == 280 and image.height == 280 and image.components == 4, id .. "280×280 RGBA")
            local transparent, partial, dirty = 0, 0, 0
            for y = 0, 279 do
                for x = 0, 279 do
                    local c = image:GetPixel(x, y)
                    if c.a == 0 then
                        transparent = transparent + 1
                        if c.r ~= 0 or c.g ~= 0 or c.b ~= 0 then dirty = dirty + 1 end
                    elseif c.a < 1 then partial = partial + 1 end
                end
            end
            check(transparent > 20000 and partial > 100 and dirty == 0, id .. "透明外缘抗锯齿无残色")
        end
        check(AVC.get(101).talentId == "gate_101_latch", "门闩机制保持")
        check(AVC.get(102).talentId == "gate_102_sluice", "闸门机制保持")
        for _, row in ipairs({ { 101, 201, 203 }, { 102, 203, 201 } }) do
            check(AVC.canAdvance(25, 100000, 2, CC.KNIGHT, row[2], { first = row[1] }), row[1] .. "二转原路径开放")
            check(not AVC.canAdvance(25, 100000, 2, CC.KNIGHT, row[3], { first = row[1] }), row[1] .. "二转不串分支")
        end
        local allShare, sealDifferent = true, false
        for y = 0, 279 do
            for x = 0, 279 do
                local a = images[3]:GetPixelInt(x, y)
                local b = images[4]:GetPixelInt(x, y)
                if (x - 139.5) ^ 2 + (y - 139.5) ^ 2 > 114 ^ 2 then
                    if a ~= b or a ~= images[1]:GetPixelInt(x, y) then allShare = false end
                elseif a ~= b then sealDifferent = true end
            end
        end
        check(allShare, "四枚已确认图共用全新底板")
        check(sealDifferent, "门闩与闸门不是同图换色")
        check(passes + failures == 60, "原60项断言完整执行")
        testBatch1()
    end)
    for _, image in ipairs(images) do image:Dispose() end
    images = {}
    if not ok then failures = failures + 1; log:Write(LOG_ERROR, tostring(err)) end
    print("[advancement_icon_asset_test] " .. (failures == 0 and "ALL PASS" or "FAILED")
        .. " passes=" .. passes .. " failures=" .. failures)
    engine:Exit()
end
