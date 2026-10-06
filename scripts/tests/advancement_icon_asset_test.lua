-- 司仪一转资源契约：真实PNG/配置检查，不加载游戏或读写玩家存档。
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
    end)
    for _, image in ipairs(images) do image:Dispose() end
    images = {}
    if not ok then failures = failures + 1; log:Write(LOG_ERROR, tostring(err)) end
    print("[advancement_icon_asset_test] " .. (failures == 0 and "ALL PASS" or "FAILED")
        .. " passes=" .. passes .. " failures=" .. failures)
    engine:Exit()
end
