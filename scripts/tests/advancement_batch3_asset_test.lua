-- 第三批正式资源专项：只读取真实PNG及配置，不读玩家档、不写资源。
-- UrhoXRuntime tests/advancement_batch3_asset_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
local AVC = require("config.AdvancementConfig")
local CC = require("config.ClassConfig")
local cjson = require("cjson")
local ROOT = "/workspace/assets/image/职业图标/"
local ROWS = {
    {id=4, classId=CC.RANGER, name="回响客", talent="gate_echo_delay", uuid="A_zbOVWpA6ooDKffvnbr4V9K"},
    {id=5, classId=CC.ASSASSIN, name="换面人", talent="gate_mask_steal", uuid="EXQx2crg8Rg83U3tQxlmUzyN"},
    {id=213, classId=CC.RANGER, name="风回", parent=107, talent="gate_213_wind", uuid="A6_CGS4zzelA0DyJW6AJ1TnD"},
    {id=214, classId=CC.RANGER, name="瞳回", parent=107, talent="gate_214_eye", uuid="ERV38UWXv2DOop2vSg2VeQBT"},
    {id=215, classId=CC.RANGER, name="瞄回", parent=108, talent="gate_215_aim", uuid="DeddyS9vH-VQyV_jBHnZRFtf"},
    {id=216, classId=CC.RANGER, name="重回", parent=108, talent="gate_216_heavy", uuid="GKfAIblM3ToBDglDL-pI6NVk"},
    {id=217, classId=CC.ASSASSIN, name="静面", parent=109, talent="gate_217_still", uuid="FVgneXxmitUaW47plfUeB28L"},
    {id=218, classId=CC.ASSASSIN, name="千面", parent=109, talent="gate_218_thousand", uuid="E-OUYV1kDX2TOClA0_ntGjW5"},
    {id=219, classId=CC.ASSASSIN, name="致命面", parent=110, talent="gate_219_lethal", uuid="BFlOwQFezrNst-8AFk8k3pK6"},
    {id=220, classId=CC.ASSASSIN, name="双面", parent=110, talent="adv_220_dual_blade", uuid="Ht54WQvolZILr8zHyPINwd_g"},
}
local passes, failures = 0, 0
---@type Image[]
local images = {}
---@type Image[]
local regenerated = {}
local function check(ok, label)
    if ok then passes = passes+1 else failures = failures+1 end
    print((ok and "[PASS] " or "[FAIL] ") .. label)
end
local function read(path)
    local f = File(path,FILE_READ)
    assert(f:IsOpen(),"无法读取测试资源：" .. path)
    local lines = {}
    while not f:IsEof() do lines[#lines+1] = f:ReadLine() end
    f:Dispose()
    return table.concat(lines,"\n")
end
local function isBone(c) return c.r > 0.55 and c.g > 0.48 and c.b > 0.30 end

-- 记录真实绘图模块的几何（不覆写全局nvg函数），包括暗描边的半宽。
local function geometry(drawer, id, palette)
    local radius, count, finite = 0,0,true
    local pathSignature = {}
    local function point(x,y,margin)
        pathSignature[#pathSignature+1] = string.format("%.6f,%.6f,%.6f",x,y,margin or 0)
        finite = finite and x == x and y == y and math.abs(x)<10000 and math.abs(y)<10000
        radius = math.max(radius,math.sqrt((x-139.5)^2+(y-139.5)^2)+(margin or 0))
    end
    local function polygon(points)
        count = count+1
        for _,p in ipairs(points) do point(p[1],p[2],0) end
    end
    local function stroke(points,width)
        count = count+1
        for _,p in ipairs(points) do point(p[1],p[2],width*0.5) end
    end
    local function line(x0,y0,x1,y1,width)
        count = count+1
        point(x0,y0,width*0.5);point(x1,y1,width*0.5)
    end
    local function curve(points,x1,y1,x2,y2,x3,y3)
        local p = points[#points]
        for i = 1,28 do
            local t,u = i/28,1-i/28
            points[#points+1] = {u^3*p[1]+3*u^2*t*x1+3*u*t^2*x2+t^3*x3,u^3*p[2]+3*u^2*t*y1+3*u*t^2*y2+t^3*y3}
        end
    end
    local function ellipse(cx,cy,rx,ry)
        count = count+1
        for i = 0,96 do local a=i*math.pi/48;point(cx+rx*math.cos(a),cy+ry*math.sin(a),0) end
    end
    local function arc(cx,cy,rx,ry,first,last,width)
        count = count+1
        for i = 0,48 do local a=(first+(last-first)*i/48)*math.pi/180;point(cx+rx*math.cos(a),cy+ry*math.sin(a),width*0.5) end
    end
    drawer({polygon=polygon,line=line,stroke=stroke,curve=curve,ellipse=ellipse,arc=arc,
        emblem=function(points) stroke(points,7);polygon(points) end,
        star=function(cx,cy,r) ellipse(cx,cy,r,r) end,
        DARK=palette and palette.DARK or {14,12,10},GOLD=palette and palette.GOLD or {161,121,64},
        BONE=palette and palette.BONE or {220,206,170},SHADE=palette and palette.SHADE or {77,55,30}},id)
    check(finite and count>10,id .. "主体是有限坐标的实体装备几何")
    check(radius<=110,id .. "含暗描边主体半径<=110，实际=" .. string.format("%.3f",radius))
    return table.concat(pathSignature,";")
end

function Start()
    local ok, err = pcall(function()
        local base = Image()
        images[#images+1] = base
        assert(base:Load(ROOT .. "UI_icon_ZY_111.png"),"加载已确认共用底板图失败")
        local uuids, signatures = {}, {}
        local echo = require("_proc.advancement.BatchEcho")
        local mask = require("_proc.advancement.BatchMask")
        local raster = require("_proc.advancement.Batch3Raster")
        check(not pcall(echo,{},107),"第三批回响客模块拒绝安装范围外107")
        check(not pcall(mask,{},109),"第三批换面人模块拒绝安装范围外109")
        local originalGeometry = geometry(echo,4)
        local recoloredGeometry = geometry(echo,4,{DARK={22,20,18},GOLD={99,72,35},BONE={140,103,55},SHADE={55,37,19}})
        check(originalGeometry == recoloredGeometry,"几何比较器忽略纯换色，不把换色误判为新轮廓")
        for _,row in ipairs(ROWS) do
            local id, classId = row.id,row.classId
            signatures[id] = geometry(classId == CC.RANGER and echo or mask,id)
            local cfg = row.parent and assert(AVC.get(id)) or assert(CC.CLASSES[classId])
            check(cfg.name == row.name and cfg.talentId == row.talent,id .. "职业名与天赋保持原配置")
            if row.parent then
                check(cfg.baseClass == classId and cfg.advLevel == 2 and cfg.parentBranch == row.parent,id .. "二转归属和父分支")
                check(cfg.combatPower == 20,id .. "二转原战力保持")
                local mapped = AVC.SECOND_BRANCHES[row.parent]
                check(mapped[1] == id or mapped[2] == id,id .. "真实二转映射")
                check(AVC.canAdvance(25,100000,2,classId,id,{first=row.parent}),id .. "原等级金币门槛开放")
                check(not AVC.canAdvance(24,100000,2,classId,id,{first=row.parent}),id .. "等级不足拒绝")
                check(not AVC.canAdvance(25,99999,2,classId,id,{first=row.parent}),id .. "金币不足拒绝")
                check(not AVC.canAdvance(25,100000,2,classId,id,nil),id .. "缺父级拒绝")
                check(not AVC.canAdvance(25,100000,2,classId,id,{first=row.parent,second=id}),id .. "重复二转拒绝")
                local otherParent = row.parent == 107 and 108 or (row.parent == 108 and 107 or (row.parent == 109 and 110 or 109))
                check(not AVC.canAdvance(25,100000,2,classId,id,{first=otherParent}),id .. "不串同职业分支")
                check(not AVC.canAdvance(25,100000,1,classId,id,nil),id .. "阶段错用拒绝")
            else
                check(AVC.get(id) == nil,id .. "基础编号不是转职ID")
                local mapped = AVC.FIRST_BRANCHES[classId]
                check(mapped[1] == (id == 4 and 107 or 109) and mapped[2] == (id == 4 and 108 or 110),id .. "基础接原一转树")
                for _,first in ipairs(mapped) do
                    check(AVC.canAdvance(10,10000,1,classId,first,nil),first .. "原一转门槛开放")
                    check(not AVC.canAdvance(9,10000,1,classId,first,nil),first .. "一转等级不足拒绝")
                    check(not AVC.canAdvance(10,9999,1,classId,first,nil),first .. "一转金币不足拒绝")
                end
            end
            local uuid = cjson.decode(read(ROOT .. "UI_icon_ZY_" .. id .. ".png.meta")).uuid
            check(uuid == row.uuid,id .. "正式meta UUID不变")
            check(not uuids[uuid],id .. "本批UUID不重复")
            uuids[uuid] = true
            local resource = cache:GetFile("image/职业图标/UI_icon_ZY_" .. id .. ".png")
            check(resource ~= nil,id .. "资源根路径解析")
            if resource then resource:Dispose() end
            local img = Image()
            images[#images+1] = img
            check(img:Load(ROOT .. "UI_icon_ZY_" .. id .. ".png"),id .. "真实正式PNG加载")
            check(img.width == 280 and img.height == 280 and img.components == 4,id .. "280×280 RGBA")
            local transparent, partial, opaque, dirty, outerMismatch, different = 0,0,0,0,0,0
            for y = 0,279 do
                for x = 0,279 do
                    local c = img:GetPixel(x,y)
                    if c.a == 0 then
                        transparent = transparent+1
                        if c.r ~= 0 or c.g ~= 0 or c.b ~= 0 then dirty = dirty+1 end
                    elseif c.a == 1 then opaque = opaque+1
                    else partial = partial+1 end
                    if (x-139.5)^2+(y-139.5)^2 > 114^2 then
                        if img:GetPixelInt(x,y) ~= base:GetPixelInt(x,y) then outerMismatch = outerMismatch+1 end
                    elseif img:GetPixelInt(x,y) ~= base:GetPixelInt(x,y) then different = different+1 end
                end
            end
            check(transparent>20000 and opaque>50000,id .. "透明四角和实体底板")
            check(partial>100 and dirty == 0,id .. "边缘抗锯齿与零透明残色")
            check(img:GetPixel(0,0).a == 0 and img:GetPixel(279,279).a == 0,id .. "画布角点透明")
            check(outerMismatch == 0,id .. "半径114外与已确认底板逐像素相同")
            check(different>500,id .. "新主体不是司仪旧主体")
            -- 绑定当前真实绘图代码和正式PNG，防止同图换色PNG与另一份代码各自通过。
            -- 仅在内存重绘，不落母图、不改资源；逐像素比较引擎相同8位量化结果。
            local drawer = classId == CC.RANGER and echo or mask
            local master = raster.render(drawer,id,regenerated)
            local expected = raster.reduce(master,regenerated)
            local payloadMismatch = 0
            for y = 0,279 do
                for x = 0,279 do
                    if img:GetPixelInt(x,y) ~= expected:GetPixelInt(x,y) then payloadMismatch = payloadMismatch+1 end
                end
            end
            check(payloadMismatch == 0,id .. "正式PNG逐像素绑定当前绘图代码 mismatch=" .. payloadMismatch)
            for _,image in ipairs(regenerated) do image:Dispose() end
            regenerated = {}
        end
        -- 像素差异＋不含颜色的图元路径签名联合校验；单靠骨白阈值不能排除换色。
        for a = 1,#ROWS-1 do
            for b = a+1,#ROWS do
                check(signatures[ROWS[a].id] ~= signatures[ROWS[b].id],ROWS[a].id .. "/" .. ROWS[b].id .. "发出图元几何不是仅换色副本")
                local imageA,imageB = images[a+1],images[b+1]
                local changed,boneMaskChanged = 0,0
                for y = 30,249 do
                    for x = 30,249 do
                        if (x-139.5)^2+(y-139.5)^2 <= 110^2 then
                            if imageA:GetPixelInt(x,y) ~= imageB:GetPixelInt(x,y) then changed = changed+1 end
                            if isBone(imageA:GetPixel(x,y)) ~= isBone(imageB:GetPixel(x,y)) then boneMaskChanged = boneMaskChanged+1 end
                        end
                    end
                end
                check(changed>500 and boneMaskChanged>200,ROWS[a].id .. "/" .. ROWS[b].id .. "实际像素与骨白占位差异")
            end
        end
        check(AVC.getDualWieldMode({first=110,second=220}) == "same","双面同型双持不变")
        check(AVC.getDualWieldMode({first=104,second=207}) == "different","双械异型双持不变")
        check(AVC.getDualWieldMode({first=110,second=219}) == nil,"致命面不偷用双持规则")
    end)
    for _,image in ipairs(images) do image:Dispose() end
    for _,image in ipairs(regenerated) do image:Dispose() end
    images, regenerated = {}, {}
    if not ok then failures = failures+1;log:Write(LOG_ERROR,"[adv-batch3-test] " .. tostring(err)) end
    print("[advancement_batch3_asset_test] " .. (failures == 0 and "ALL PASS" or "FAILED") .. " passes=" .. passes .. " failures=" .. failures)
    engine:Exit()
end
