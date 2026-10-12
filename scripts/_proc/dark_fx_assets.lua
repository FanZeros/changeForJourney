-- 暗黑特效离线烘焙：CPU Image 像素 + 真 Spine 4.2.43 骨架，不进入游戏每帧业务。
-- 复用 _proc/advancement/Batch3Raster 的扫描填充、直通 alpha 合成与预乘 2× 降采样脚手架。
-- 固定解析纹理和几何，不使用随机数、不读取旧 PNG，不改旧 Spine 或玩法。
-- 执行：UrhoXRuntime _proc/dark_fx_assets.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
-- 可选 -verify-only 仅检查现有产物，-verify-repeat 在内存重绘并逐像素比较。
local ROOT = "/workspace/assets/image/暗黑特效/"
local EVIDENCE = "/workspace/.git/validation/dark-rich/"
local SCALE, ATLAS_SIZE, EXTRUDE = 2, 1024, 2
local PI = math.pi
local IRON, BRONZE, BONE, BLOOD = {22,21,23}, {166,117,63}, {233,218,182}, {169,43,30}
local SHADOW, VERDIGRIS = {8,8,11}, {48,72,65}
local ORDER = {
    {name="nameplate",w=640,h=144}, {name="copper_wing",w=256,h=96},
    {name="gate_leaf",w=96,h=320}, {name="rift_light",w=80,h=320},
    {name="smoke_flame",w=192,h=256}, {name="soul_flame",w=128,h=192},
    {name="seal_plate",w=192,h=192}, {name="rune_ring",w=256,h=256},
    {name="impact_glow",w=256,h=256}, {name="rune_strip",w=128,h=256},
    {name="seal_shard",w=64,h=96}, {name="ember",w=32,h=64},
    {name="ash_flake",w=64,h=64}, {name="light_sweep",w=256,h=64},
}
---@type Image[]
local ownedImages = {}
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function mix(a,b,t) return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t} end
local function track(image) ownedImages[#ownedImages+1]=image; return image end
local function releaseImages()
    for _,image in ipairs(ownedImages) do image:Dispose() end
    ownedImages = {}
end
local function writeText(path, text)
    local f=File(path,FILE_WRITE)
    assert(f:IsOpen(),"打开输出失败："..path)
    -- WriteString 是引擎二进制字符串格式，会追加NUL；标准JSON/atlas按原始UTF-8字节写出。
    local buffer=VectorBuffer()
    for i=1,#text do assert(buffer:WriteUByte(string.byte(text,i)),"编码文本失败") end
    local written=f:Write(buffer)
    f:Close(); f:Dispose()
    assert(written==#text,"写入输出失败："..path)
end
local function readText(path)
    local f=File(path,FILE_READ)
    assert(f:IsOpen(),"打开输入失败："..path)
    local buffer=f:Read(f:GetSize())
    local bytes={}
    for i=1,buffer:GetSize() do bytes[i]=string.char(buffer:ReadUByte()) end
    local result=table.concat(bytes)
    f:Close(); f:Dispose()
    return result
end

-- 确定性 JSON：字符串仍由 cjson 编码；对象键排序，数字精确到六位小数。
-- 不直接 cjson.encode 大表，避免 Lua 哈希随机种子改变对象键的输出顺序。
local function stableJSON(value)
    if type(value)~="table" then
        if type(value)=="number" then
            assert(value==value and math.abs(value)<math.huge,"JSON 含非法数字")
            return string.format("%.6f",value):gsub("0+$",""):gsub("%.$","")
        end
        return cjson.encode(value)
    end
    local count, numeric=0,true
    for k in pairs(value) do count=count+1; if type(k)~="number" then numeric=false end end
    if numeric and count>0 and count==#value then
        local values={}
        for _,v in ipairs(value) do values[#values+1]=stableJSON(v) end
        return "["..table.concat(values,",").."]"
    end
    local keys={}
    for k in pairs(value) do keys[#keys+1]=k end
    table.sort(keys)
    local values={}
    for _,k in ipairs(keys) do values[#values+1]=cjson.encode(k)..":"..stableJSON(value[k]) end
    return "{"..table.concat(values,",").."}"
end

-- 可变尺寸 CPU 画布。扫描在2×母图，颜色缓存为预乘值，不累积色边。
local function canvas(w,h)
    local W,H=w*SCALE,h*SCALE
    local red,green,blue,alpha={},{},{},{}
    for i=1,W*H do red[i],green[i],blue[i],alpha[i]=0,0,0,0 end
    local function blend(x,y,c,a)
        if a<=0 then return end
        a=clamp(a,0,1)
        local i=y*W+x+1; local remain=1-a
        red[i],green[i],blue[i]=c[1]*a+red[i]*remain,c[2]*a+green[i]*remain,c[3]*a+blue[i]*remain
        alpha[i]=a+alpha[i]*remain
    end
    local function scan(x0,y0,x1,y1,inside,top,bottom,opacity,metal)
        for y=math.max(0,math.floor(y0*SCALE)),math.min(H-1,math.ceil(y1*SCALE)) do
            local py=(y+0.5)/SCALE
            local t=clamp((py-y0)/math.max(1,y1-y0),0,1)
            local base=bottom and mix(top,bottom,t) or top
            for x=math.max(0,math.floor(x0*SCALE)),math.min(W-1,math.ceil(x1*SCALE)) do
                local px=(x+0.5)/SCALE
                local coverage=inside(px,py)
                if coverage and coverage~=0 then
                    local a=(opacity or 1)*(type(coverage)=="number" and coverage or 1)
                    local color=base
                    if metal then
                        -- 连续大面明暗，极轻拉丝/氧化；不做棋盘噪声或高频斑驳。
                        local key=math.exp(-((px-w*.32)^2+(py-h*.23)^2)/(w*h*.1))*.12
                        local brush=math.sin(py*2.7+math.sin(px*.06))*.009
                        local patina=math.sin(px*.045+py*.027)*math.sin(py*.037-px*.012)*.025
                        local f=.91+key+brush+patina
                        color={clamp(base[1]*f,0,255),clamp(base[2]*f,0,255),clamp(base[3]*f,0,255)}
                    end
                    blend(x,y,color,a)
                end
            end
        end
    end
    local function polygon(points,top,bottom,opacity,metal)
        local x0,y0,x1,y1=w,h,0,0
        for _,p in ipairs(points) do x0,y0,x1,y1=math.min(x0,p[1]),math.min(y0,p[2]),math.max(x1,p[1]),math.max(y1,p[2]) end
        scan(x0,y0,x1,y1,function(x,y)
            local inside,last=false,points[#points]
            for _,p in ipairs(points) do
                if (p[2]>y)~=(last[2]>y) and x<(last[1]-p[1])*(y-p[2])/(last[2]-p[2])+p[1] then inside=not inside end
                last=p
            end
            return inside
        end,top,bottom,opacity,metal)
    end
    local function line(x0,y0,x1,y1,width,color,opacity)
        local vx,vy=x1-x0,y1-y0; local len=vx*vx+vy*vy; local r=width*.5
        scan(math.min(x0,x1)-r,math.min(y0,y1)-r,math.max(x0,x1)+r,math.max(y0,y1)+r,function(x,y)
            local t=len>0 and clamp(((x-x0)*vx+(y-y0)*vy)/len,0,1) or 0
            return (x-x0-vx*t)^2+(y-y0-vy*t)^2<=r*r
        end,color,nil,opacity)
    end
    local function stroke(points,width,color,closed,opacity)
        for i=1,#points-1 do line(points[i][1],points[i][2],points[i+1][1],points[i+1][2],width,color,opacity) end
        if closed then line(points[#points][1],points[#points][2],points[1][1],points[1][2],width,color,opacity) end
    end
    local function ellipse(cx,cy,rx,ry,top,bottom,opacity,metal)
        scan(cx-rx,cy-ry,cx+rx,cy+ry,function(x,y) return ((x-cx)/rx)^2+((y-cy)/ry)^2<=1 end,top,bottom,opacity,metal)
    end
    local function arc(cx,cy,r,first,last,width,color,opacity)
        local points={}
        for i=0,64 do local a=(first+(last-first)*i/64)*PI/180; points[#points+1]={cx+math.cos(a)*r,cy+math.sin(a)*r} end
        stroke(points,width,color,false,opacity)
    end
    local function glow(cx,cy,rx,ry,color,opacity,power)
        scan(cx-rx,cy-ry,cx+rx,cy+ry,function(x,y)
            local d=((x-cx)/rx)^2+((y-cy)/ry)^2
            return d<1 and (1-d)^(power or 2.8) or 0
        end,color,nil,opacity)
    end
    local function curve(points,x1,y1,x2,y2,x3,y3)
        local p=points[#points]
        for i=1,32 do
            local t,u=i/32,1-i/32
            points[#points+1]={u^3*p[1]+3*u*u*t*x1+3*u*t*t*x2+t^3*x3,u^3*p[2]+3*u*u*t*y1+3*u*t*t*y2+t^3*y3}
        end
    end
    local function bevel(points,top,bottom,width)
        stroke(points,(width or 2)+3,SHADOW,true)
        polygon(points,top,bottom,1,true)
        stroke(points,width or 2,BRONZE,true)
        for i=1,#points-1 do
            if points[i+1][2]<=points[i][2]+.1 then line(points[i][1],points[i][2],points[i+1][1],points[i+1][2],.85,BONE,.7) end
        end
    end
    local function rivet(x,y,r)
        ellipse(x+.5,y+1,r+1,r+1,SHADOW)
        ellipse(x,y,r,r,{194,156,94},{62,42,25},1,true)
        line(x-r*.5,y-r*.35,x+r*.45,y-r*.35,.8,BONE,.8)
    end
    local function rune(x,y,s,n,color,opacity)
        -- 六种虚构封印刻痕，几何清楚，不使用可读文字或机制图解。
        local patterns={
            {{-.38,-.4},{.38,-.4},{0,0},{0,.5}}, {{-.32,.45},{-.32,-.45},{.32,0},{-.32,.1}},
            {{-.35,-.4},{.35,.4},{0,0},{.35,-.4},{-.35,.4}}, {{0,-.5},{0,.5},{0,0},{-.4,-.15},{.4,-.15}},
            {{-.3,-.4},{.3,-.4},{.3,.4},{-.3,.4},{-.3,-.4}}, {{0,-.45},{-.35,0},{0,.45},{.35,0},{0,-.45}},
        }
        local points={}
        for _,p in ipairs(patterns[(n-1)%6+1]) do points[#points+1]={x+p[1]*s,y+p[2]*s} end
        stroke(points,math.max(.75,s*.085),color,false,opacity)
    end
    local function finish()
        local image=track(Image()); assert(image:SetSize(w,h,4),"创建成图失败")
        for y=0,h-1 do for x=0,w-1 do
            local r,g,b,a=0,0,0,0
            for sy=0,SCALE-1 do for sx=0,SCALE-1 do
                local i=(y*SCALE+sy)*W+x*SCALE+sx+1
                r,g,b,a=r+red[i],g+green[i],b+blue[i],a+alpha[i]
            end end
            -- 明确量化8位RGBA，alpha量化成0时同步清RGB；不依赖native ToUInt的舍入方式。
            local qa=math.floor(clamp(a/(SCALE*SCALE),0,1)*255+.5)
            if qa>0 then
                local qr,qg,qb=math.floor(clamp(r/a,0,255)+.5),math.floor(clamp(g/a,0,255)+.5),math.floor(clamp(b/a,0,255)+.5)
                image:SetPixelInt(x,y,Color(qr/255,qg/255,qb/255,qa/255):ToUInt())
            else image:SetPixelInt(x,y,0) end
        end end
        return image
    end
    return {w=w,h=h,scan=scan,polygon=polygon,line=line,stroke=stroke,ellipse=ellipse,arc=arc,glow=glow,
        curve=curve,bevel=bevel,rivet=rivet,rune=rune,finish=finish}
end

-- 名牌只有金属轮廓与暗底，中间保留洁净大面供真实 UI 文本使用。
local function drawNameplate(d)
    local p={{20,36},{50,15},{590,15},{620,36},{620,108},{590,129},{50,129},{20,108}}
    d.glow(320,72,316,70,{130,51,24},.24)
    d.bevel(p,{102,84,62},{39,32,28},3)
    d.bevel({{41,34},{65,22},{575,22},{599,34},{599,110},{575,122},{65,122},{41,110}},
        {28,27,28},{13,13,17},1.1)
    d.line(72,26,568,26,1,{217,180,116},.8)
    d.line(75,118,565,118,1,{117,76,38},.7)
    for _,x in ipairs({32,608}) do
        d.bevel({{x,42},{x+10,72},{x,102},{x-9,72}},{196,150,77},{83,53,31},1)
        d.rivet(x,72,3)
    end
    for i=1,5 do d.rune(75+(i-1)*12,22,7,i,BONE,.64); d.rune(565-(i-1)*12,122,7,i+1,BRONZE,.7) end
    d.line(58,41,58,103,.8,VERDIGRIS,.55); d.line(581,41,581,103,.8,VERDIGRIS,.5)
end
local function drawWing(d)
    -- 单侧六片实体铜翼/护片，右侧实例翻X；根部有铭刻钉和机械接座。
    for i=6,1,-1 do
        local x,y=18+i*31,49-i*5
        local p={{18,48},{x,math.max(10,y-20)},{x+20,math.max(7,y-26)},{x+8,y+8},{32,78}}
        d.bevel(p,mix(BONE,BRONZE,.18+i*.06),{76,48,28},1.4)
        d.line(27,60,x+6,y-10,1.2,{224,188,124},.62)
    end
    d.bevel({{8,39},{32,26},{50,41},{48,67},{29,83},{8,69}},{151,118,72},{43,34,27},2)
    d.rivet(26,55,6); d.rune(41,52,10,2,BONE,.8)
end
local function drawGate(d)
    local p={{10,300},{10,54},{26,24},{78,11},{85,29},{85,300},{70,311},{24,311}}
    d.bevel(p,{130,106,76},{43,34,29},2.8)
    d.bevel({{23,292},{23,58},{34,40},{71,29},{74,44},{74,293}}, {49,47,46},{19,19,24},1.4)
    for i=0,3 do
        local y=69+i*57
        d.bevel({{29,y},{66,y-4},{68,y+39},{29,y+43}},{62,58,50},{22,23,28},1)
        d.line(34,y+5,60,y+2,.8,VERDIGRIS,.66)
        d.rune(49,y+22,17,i+1,{154,113,60},.8)
    end
    for _,y in ipairs({64,164,263}) do
        d.bevel({{5,y-7},{21,y-9},{27,y-2},{27,y+7},{7,y+10}}, {175,127,65},{61,41,25},1.3)
        d.rivet(17,y,3)
    end
    d.bevel({{65,147},{82,145},{89,161},{82,177},{65,175}},{172,132,76},{70,42,28},1.5)
    d.ellipse(78,161,4,7,SHADOW); d.line(77,165,79,171,2,SHADOW)
    d.line(86,35,86,292,1,BONE,.8)
    d.rivet(36,38,2); d.rivet(69,298,2.5)
end
local function drawSeal(d)
    local cx,cy=96,96
    local ring={}
    for i=0,11 do local a=(-105+i*30)*PI/180; ring[#ring+1]={cx+math.cos(a)*79,cy+math.sin(a)*79} end
    d.glow(cx,cy,95,95,{139,59,28},.22)
    d.bevel(ring,{194,151,87},{57,38,29},3)
    d.ellipse(cx,cy,68,68,{29,28,29},{11,12,16},1,true)
    d.arc(cx,cy,70,0,360,1.3,BRONZE,.9)
    d.arc(cx,cy,62,192,342,1,BONE,.8)
    for i=0,11 do
        local a=(i*30-90)*PI/180; local x,y=cx+math.cos(a)*57,cy+math.sin(a)*57
        d.rune(x,y,10,i+1,BRONZE,.9)
        if i%3==0 then d.rivet(cx+math.cos(a)*74,cy+math.sin(a)*74,2.7) end
    end
    d.bevel({{71,126},{71,75},{82,57},{110,57},{122,75},{122,126},{105,140},{88,140}},
        {197,164,106},{75,48,33},1.6)
    d.polygon({{82,120},{82,79},{91,69},{103,69},{112,79},{112,120}},IRON,{11,11,15},1,true)
    d.line(96,71,96,120,1.3,BLOOD,.9)
    d.bevel({{77,91},{114,91},{117,100},{77,101}},{191,151,86},{67,43,28},1)
    d.rivet(82,96,2); d.rivet(110,96,2)
    d.rune(97,129,10,6,BONE,.94)
end
local function drawRuneRing(d)
    local cx,cy=128,128
    d.glow(cx,cy,126,126,{133,52,26},.12)
    d.arc(cx,cy,105,0,360,9,SHADOW,1)
    d.arc(cx,cy,105,0,360,5.2,{133,92,51},1)
    d.arc(cx,cy,105,185,307,1.2,BONE,.9)
    d.arc(cx,cy,88,0,360,2.3,{192,144,81},.92)
    d.arc(cx,cy,82,0,360,1.2,{106,66,39},.85)
    for i=0,23 do
        local a=(i*15-90)*PI/180
        d.rune(cx+math.cos(a)*96,cy+math.sin(a)*96,9,i+1,i%4==0 and BONE or BRONZE,.9)
        if i%3==0 then
            local p={}
            for _,v in ipairs({{113,-4},{121,0},{113,4},{109,0}}) do
                p[#p+1]={cx+math.cos(a)*v[1]-math.sin(a)*v[2],cy+math.sin(a)*v[1]+math.cos(a)*v[2]}
            end
            d.bevel(p,{183,141,76},{50,35,26},.8)
        end
    end
    for i=0,3 do local a=(i*90+45)*PI/180; d.rivet(cx+math.cos(a)*105,cy+math.sin(a)*105,2.4) end
end
local function drawRift(d)
    d.glow(40,158,39,157,{169,45,26},.35,2)
    d.glow(40,158,19,152,{238,108,40},.48,1.9)
    local points={{40,12},{33,56},{43,83},{35,119},{45,154},{36,185},{44,223},{37,261},{40,307}}
    d.stroke(points,10,{116,29,20},false,.7)
    d.stroke(points,4,{248,153,72},false,.93)
    d.stroke(points,1.4,{255,232,183},false,.98)
    d.stroke({{40,83},{56,110},{61,145}},2,{224,91,37},false,.55)
    d.stroke({{37,185},{24,218},{20,248}},1.6,{224,91,37},false,.6)
end
local function drawFlame(d,soul)
    local w,h=d.w,d.h; local cx=w*.5
    local color=soul and {119,132,110} or {150,48,29}
    d.glow(cx,h*.65,w*.49,h*.34,color,.36)
    -- 四条 Bézier 烟焰，体积与扭曲可见；透明灰烟和高亮内焰分层。
    for i=1,4 do
        local x=cx+(i-2.5)*w*.115; local tip=h*(.08+i*.035)
        local p={{x-w*.11,h*.91}}
        d.curve(p,x-w*.3,h*.64,x+w*.28,h*.55,x+w*.045,h*.36)
        d.curve(p,x-w*.12,h*.25,x+w*.10,tip+.03*h,x+w*.04,tip)
        d.curve(p,x+w*.30,h*.40,x-w*.12,h*.52,x+w*.17,h*.71)
        d.curve(p,x+w*.29,h*.87,x+w*.16,h*.94,x-w*.11,h*.91)
        d.polygon(p,soul and {122,143,127} or {100,48,40},soul and {49,64,57} or {25,22,26},.38)
    end
    local p={{cx-w*.25,h*.88}}
    d.curve(p,cx-w*.33,h*.67,cx+w*.20,h*.57,cx-w*.035,h*.18)
    d.curve(p,cx+w*.29,h*.48,cx+w*.31,h*.74,cx+w*.20,h*.89)
    d.curve(p,cx+w*.04,h*.95,cx-w*.15,h*.94,cx-w*.25,h*.88)
    d.polygon(p,soul and {198,201,165} or {216,82,33},soul and {85,110,86} or {86,24,23},.88)
    local core={{cx-w*.10,h*.9}}
    d.curve(core,cx-w*.18,h*.75,cx+w*.12,h*.7,cx+w*.005,h*.48)
    d.curve(core,cx+w*.17,h*.71,cx+w*.12,h*.83,cx+w*.065,h*.9)
    d.polygon(core,{248,228,170},soul and {192,190,140} or {235,142,61},.88)
    d.glow(cx,h*.83,w*.18,h*.10,{253,216,147},.65)
end
local function drawShard(d)
    d.bevel({{10,74},{18,14},{45,8},{54,34},{38,58},{48,84},{24,88}},
        {177,142,88},{44,32,29},1.6)
    d.polygon({{18,63},{23,23},{42,18},{45,33},{29,52}},IRON,{50,42,32},1,true)
    d.rune(30,34,13,3,BONE,.84)
    d.line(24,68,37,59,1.2,{199,86,38},.8)
    d.rivet(28,76,2.3)
end
local function drawEmber(d)
    d.glow(16,35,15,28,{178,45,22},.45)
    d.polygon({{14,10},{22,26},{20,46},{12,54},{10,29}},{247,180,78},{139,44,25},.96)
    d.line(15,22,17,39,1.6,BONE,.92)
end
local function drawAsh(d)
    d.polygon({{10,30},{22,15},{39,17},{51,34},{34,49},{17,42}},{125,119,102},{35,35,40},.9,true)
    d.polygon({{15,28},{24,20},{36,23},{31,35}},{189,178,145},{77,76,66},.9)
    d.line(20,39,39,29,1,{25,25,29},.8)
end
local function drawGlow(d)
    d.glow(128,128,125,125,{144,46,26},.35,3)
    d.glow(128,128,71,71,{233,116,46},.46,3)
    d.glow(128,128,25,25,{251,217,149},.85,2)
    for i=0,7 do
        local a=i*PI/4; local r=i%2==0 and 107 or 68
        local p={{128+math.cos(a)*r,128+math.sin(a)*r},
            {128+math.cos(a+.17)*15,128+math.sin(a+.17)*15},
            {128+math.cos(a-.17)*15,128+math.sin(a-.17)*15}}
        d.polygon(p,{241,182,96},nil,.30)
    end
end
local function drawRunes(d)
    for i=0,7 do
        local y=20+i*30; local x=64+math.sin(i*1.9)*20
        d.glow(x,y,26,20,{140,49,26},.21)
        d.rune(x,y,18,i+1,{231,175,103},.9)
        if i%2==0 then d.line(x+22,y-2,x+26,y+2,1.3,BONE,.5) end
    end
end
local function drawSweep(d)
    d.glow(128,32,126,29,{191,75,31},.33,2)
    d.glow(128,32,114,10,{244,164,79},.52,2)
    d.glow(128,32,86,2.5,{254,228,175},.88,1.5)
    d.polygon({{37,32},{128,29},{219,32},{128,35}},BONE,nil,.72)
end
local DRAWERS={nameplate=drawNameplate,copper_wing=drawWing,gate_leaf=drawGate,seal_plate=drawSeal,
    rune_ring=drawRuneRing,rift_light=drawRift,smoke_flame=function(d) drawFlame(d,false) end,
    soul_flame=function(d) drawFlame(d,true) end,seal_shard=drawShard,ember=drawEmber,ash_flake=drawAsh,
    impact_glow=drawGlow,rune_strip=drawRunes,light_sweep=drawSweep}
local function renderRegion(region)
    local d=canvas(region.w,region.h)
    DRAWERS[region.name](d)
    return d.finish()
end

local function packAtlas()
    local x,y,rowH=4,4,0
    for _,r in ipairs(ORDER) do
        if x+r.w+4>ATLAS_SIZE then x,y,rowH=4,y+rowH+8,0 end
        assert(y+r.h+4<=ATLAS_SIZE,"图集容量不足")
        r.x,r.y=x,y
        x=x+r.w+8; rowH=math.max(rowH,r.h)
    end
end
local function atlasText()
    local rows={"atlas.png", "size: 1024, 1024", "format: RGBA8888", "filter: Linear, Linear", "repeat: none"}
    for _,r in ipairs(ORDER) do
        rows[#rows+1]=r.name
        rows[#rows+1]="  rotate: false"
        rows[#rows+1]=string.format("  xy: %d, %d",r.x,r.y)
        rows[#rows+1]=string.format("  size: %d, %d",r.w,r.h)
        rows[#rows+1]=string.format("  orig: %d, %d",r.w,r.h)
        rows[#rows+1]="  offset: 0, 0"
        rows[#rows+1]="  index: -1"
    end
    return table.concat(rows,"\n").."\n"
end
local function copyToAtlas(atlas,image,r)
    -- 四边/四角2px复制，间隔仍≥4透明像素。PNG为 straight alpha，atlas不写 pma:true。
    for y=-EXTRUDE,r.h+EXTRUDE-1 do for x=-EXTRUDE,r.w+EXTRUDE-1 do
        local sx,sy=clamp(x,0,r.w-1),clamp(y,0,r.h-1)
        atlas:SetPixelInt(r.x+x,r.y+y,image:GetPixelInt(sx,sy))
    end end
end

-- 真4.2骨架构造：skins数组、region附件、slot.rgba时间轴、rotate.value关键帧。
-- 初次按用户3.8规格生成被真实UrhoX4.2拒绝，按官方4.2 parser修正格式而非仅换版本串。
local REGIONS={}
for _,r in ipairs(ORDER) do REGIONS[r.name]=r end
local function skeleton(w,h)
    return {skeleton={hash="dark-rich-procedural-v1",spine="4.2.43",x=-w*.5,y=-h*.5,width=w,height=h,images="./"},
        bones={{name="root"}},slots={},skins={{name="default",attachments={}}},animations={}}
end
local function add(s,name,region,x,y,w,h,rotation,blend,parent)
    local bone={name=name,parent=parent or "root",x=x or 0,y=y or 0}
    if rotation then bone.rotation=rotation end
    s.bones[#s.bones+1]=bone
    local slot={name=name,bone=name,attachment=region,color="ffffff00"}
    if blend then slot.blend=blend end
    s.slots[#s.slots+1]=slot
    local r=REGIONS[region]
    s.skins[1].attachments[name]={[region]={type="region",path=region,width=w or r.w,height=h or r.h}}
end
local function newAnimation(s,name,duration)
    local a={bones={},slots={}}
    s.animations[name]=a
    for _,slot in ipairs(s.slots) do
        a.slots[slot.name]={rgba={{time=0,color="ffffff00"},{time=duration,color="ffffff00"}}}
    end
    -- 所有动画终点是完全透明，隐藏未参与的槽也保有严格时长。
    a.bones.root={translate={{time=0,x=0,y=0},{time=duration,x=0,y=0}}}
    return a
end
local function colorKeys(a,name,keys) a.slots[name]={rgba=keys} end
local function appear(a,name,duration,on,peak,hold,color)
    local rgb=color or "ffffff"
    colorKeys(a,name,{{time=0,color=rgb.."00"},{time=on,color=rgb.."00"},
        {time=peak,color=rgb.."ff"},{time=hold,color=rgb.."e6"},{time=duration,color=rgb.."00"}})
end
local function transform(a,name,key,values)
    a.bones[name]=a.bones[name] or {}; a.bones[name][key]=values
end
local function scale(a,name,keys) transform(a,name,"scale",keys) end
local function translate(a,name,keys) transform(a,name,"translate",keys) end
local function rotate(a,name,keys) transform(a,name,"rotate",keys) end
local function particles(s,a,duration,kind,count)
    for i=1,count do
        local n=kind..i; local sign=i%2==0 and 1 or -1
        local angle=i*2.399963; local r=30+(i%4)*12
        local x,y=math.cos(angle)*r,math.sin(angle)*r
        add(s,n,kind=="ash" and "ash_flake" or (kind=="chip" and "seal_shard" or "ember"),x,y,
            kind=="chip" and 17 or 9,kind=="chip" and 25 or 15,i*47,nil)
        -- newAnimation之后添加的粒子槽，显式补color。
        local start=.04+(i%4)*.025
        appear(a,n,duration,start,start+.17,duration*.62)
        if kind=="ash" then
            translate(a,n,{{time=0,x=x*1.5,y=y*1.2},{time=duration*.65,x=-x,y=-y},{time=duration,x=-x,y=-y}})
            scale(a,n,{{time=0,x=.65,y=.65},{time=duration*.6,x=1,y=1},{time=duration,x=.1,y=.1}})
        else
            translate(a,n,{{time=0,x=0,y=0},{time=duration*.35,x=x*.7,y=30+math.abs(y)},
                {time=duration,x=x*1.3,y=kind=="chip" and -100-math.abs(y) or 100+math.abs(y)}})
            scale(a,n,{{time=0,x=.2,y=.2},{time=duration*.25,x=1,y=1},{time=duration,x=.35,y=.35}})
        end
        rotate(a,n,{{time=0,value=-30*sign},{time=duration,value=115*sign}})
    end
end
local function cardSkeleton()
    local s=skeleton(200,350)
    add(s,"haze","smoke_flame",0,-30,185,270)
    add(s,"aura","impact_glow",0,-30,200,200,nil,"additive")
    add(s,"wheel","rune_ring",0,-30,177,177)
    add(s,"seal","seal_plate",0,-30,108,108)
    add(s,"doorL","gate_leaf",-45,0,83,301)
    add(s,"doorR","gate_leaf",45,0,83,301)
    s.bones[#s.bones].scaleX=-1
    add(s,"crack","rift_light",0,0,66,330,nil,"additive")
    add(s,"runes","rune_strip",0,0,112,265,nil,"additive")
    add(s,"fireL","smoke_flame",-49,-31,85,200)
    add(s,"fireR","smoke_flame",49,-31,85,200)
    add(s,"soul","soul_flame",0,-20,128,192)
    add(s,"wingL","copper_wing",-39,-55,108,45)
    add(s,"wingR","copper_wing",39,-55,108,45)
    s.bones[#s.bones].scaleX=-1
    add(s,"sweep","light_sweep",0,-30,184,46,nil,"additive")
    local D=1.3333; local a=newAnimation(s,"level",D)
    for _,n in ipairs({"haze","aura","wheel","seal","fireL","fireR","sweep"}) do appear(a,n,D,.03,.24,.86) end
    rotate(a,"wheel",{{time=0,value=-22},{time=.67,value=9},{time=D,value=27}})
    scale(a,"wheel",{{time=0,x=.72,y=.72},{time=.3,x=1.1,y=1.1},{time=.5,x=1,y=1},{time=D,x=1.15,y=1.15}})
    scale(a,"seal",{{time=0,x=.3,y=.3},{time=.27,x=1.08,y=1.08},{time=.42,x=1,y=1},{time=D,x=.92,y=.92}})
    for _,n in ipairs({"fireL","fireR"}) do
        scale(a,n,{{time=0,x=.4,y=.1},{time=.35,x=1,y=1},{time=.65,x=.84,y=1.05},{time=D,x=.65,y=1.24}})
        translate(a,n,{{time=0,x=0,y=-60},{time=.35,x=0,y=0},{time=D,x=0,y=65}})
        rotate(a,n,{{time=0,value=-5},{time=.5,value=7},{time=D,value=-3}})
    end
    scale(a,"aura",{{time=0,x=.2,y=.2},{time=.22,x=1,y=1},{time=D,x=1.26,y=1.26}})
    scale(a,"sweep",{{time=0,x=.1,y=.4},{time=.27,x=1,y=1},{time=D,x=1.05,y=.3}})
    translate(a,"sweep",{{time=0,x=0,y=-50},{time=.3,x=0,y=0},{time=D,x=0,y=70}})
    particles(s,a,D,"spark",10)
    local b=newAnimation(s,"job",D)
    for _,n in ipairs({"haze","aura","doorL","doorR","crack","runes","wingL","wingR"}) do appear(b,n,D,.01,.24,.78) end
    for _,n in ipairs({"doorL","doorR"}) do
        local sign=n=="doorL" and -1 or 1
        translate(b,n,{{time=0,x=-sign*7,y=0},{time=.35,x=0,y=0},{time=.72,x=sign*30,y=0},{time=D,x=sign*50,y=8}})
        scale(b,n,{{time=0,x=.9,y=.96},{time=.28,x=1,y=1},{time=.85,x=.67,y=1},{time=D,x=.2,y=1.02}})
        rotate(b,n,{{time=0,value=0},{time=.7,value=-sign*3},{time=D,value=-sign*8}})
    end
    scale(b,"crack",{{time=0,x=.1,y=.2},{time=.4,x=.3,y=1},{time=.7,x=1,y=1},{time=D,x=1.7,y=1.04}})
    translate(b,"runes",{{time=0,x=0,y=-50},{time=.45,x=0,y=0},{time=D,x=0,y=80}})
    for _,n in ipairs({"wingL","wingR"}) do rotate(b,n,{{time=0,value=0},{time=.48,value=n=="wingL" and 19 or -19},{time=D,value=0}}) end
    scale(b,"aura",{{time=0,x=.2,y=.3},{time=.65,x=1,y=1},{time=D,x=1.3,y=1.6}})
    local c=newAnimation(s,"revive",.9)
    for _,n in ipairs({"haze","aura","soul","wheel","wingL","wingR","sweep"}) do appear(c,n,.9,.01,.32,.65) end
    colorKeys(c,"haze",{{time=0,color="adb7a800"},{time=.2,color="adb7a88c"},{time=.9,color="adb7a800"}})
    scale(c,"soul",{{time=0,x=.25,y=.25},{time=.35,x=1,y=1},{time=.65,x=.86,y=1.1},{time=.9,x=.64,y=1.3}})
    translate(c,"soul",{{time=0,x=0,y=-50},{time=.45,x=0,y=0},{time=.9,x=0,y=70}})
    scale(c,"wheel",{{time=0,x=1.2,y=.6},{time=.48,x=.82,y=.41},{time=.9,x=.4,y=.2}})
    rotate(c,"wheel",{{time=0,value=-18},{time=.9,value=28}})
    scale(c,"aura",{{time=0,x=.6,y=.6},{time=.5,x=1,y=1},{time=.9,x=.5,y=1.3}})
    particles(s,c,.9,"ash",10)
    -- 后加槽在此前动画里必须明确隐藏，不能继承其他动画的粒子alpha。
    for _,animation in pairs(s.animations) do
        local duration=animation.bones.root.translate[2].time
        for _,slot in ipairs(s.slots) do if not animation.slots[slot.name] then
            animation.slots[slot.name]={rgba={{time=0,color="ffffff00"},{time=duration,color="ffffff00"}}}
        end end
    end
    return s
end
local function resultSkeleton()
    local s=skeleton(200,200)
    add(s,"smoke","smoke_flame",0,-12,180,180)
    add(s,"glow","impact_glow",0,0,200,200,nil,"additive")
    add(s,"wheel","rune_ring",0,0,180,180)
    add(s,"seal","seal_plate",0,0,110,110)
    add(s,"wingL","copper_wing",-43,-8,105,44)
    add(s,"wingR","copper_wing",43,-8,105,44); s.bones[#s.bones].scaleX=-1
    add(s,"sweep","light_sweep",0,0,190,46,nil,"additive")
    local D=1.6667; local a=newAnimation(s,"success",D)
    for _,n in ipairs({"smoke","glow","wheel","seal","wingL","wingR","sweep"}) do appear(a,n,D,.02,.35,1.13) end
    for _,n in ipairs({"wingL","wingR"}) do
        local sign=n=="wingL" and -1 or 1
        translate(a,n,{{time=0,x=sign*35,y=-10},{time=.45,x=0,y=0},{time=D,x=sign*4,y=0}})
        rotate(a,n,{{time=0,value=sign*18},{time=.45,value=0},{time=D,value=sign*3}})
    end
    rotate(a,"wheel",{{time=0,value=-42},{time=.7,value=0},{time=D,value=10}})
    scale(a,"seal",{{time=0,x=.15,y=.15},{time=.36,x=1.15,y=1.15},{time=.55,x=1,y=1},{time=D,x=.94,y=.94}})
    scale(a,"glow",{{time=0,x=.1,y=.1},{time=.4,x=1.16,y=1.16},{time=D,x=1.3,y=1.3}})
    translate(a,"sweep",{{time=0,x=-90,y=-15},{time=.6,x=0,y=0},{time=1,x=80,y=25},{time=D,x=90,y=40}})
    particles(s,a,D,"spark",8)
    local b=newAnimation(s,"failure",1.3333)
    for _,n in ipairs({"smoke","wheel","seal","glow"}) do appear(b,n,1.3333,.01,.18,.48,"c67d66") end
    scale(b,"seal",{{time=0,x=.8,y=.8},{time=.16,x=1,y=1},{time=.42,x=1.06,y=1.06},{time=.7,x=.05,y=.05},{time=1.3333,x=.01,y=.01}})
    rotate(b,"seal",{{time=0,value=0},{time=.23,value=-4},{time=.3,value=5},{time=.4,value=-2},{time=.75,value=30}})
    scale(b,"wheel",{{time=0,x=.7,y=.7},{time=.22,x=1,y=1},{time=1.3333,x=1.2,y=1.2}})
    rotate(b,"wheel",{{time=0,value=0},{time=1.3333,value=-30}})
    colorKeys(b,"glow",{{time=0,color="bb493600"},{time=.38,color="bb4936b3"},{time=.65,color="bb493600"},{time=1.3333,color="bb493600"}})
    particles(s,b,1.3333,"chip",12)
    for _,animation in pairs(s.animations) do local duration=animation.bones.root.translate[2].time
        for _,slot in ipairs(s.slots) do if not animation.slots[slot.name] then
            animation.slots[slot.name]={rgba={{time=0,color="ffffff00"},{time=duration,color="ffffff00"}}}
        end end
    end
    return s
end
local function powerSkeleton()
    local s=skeleton(760,200)
    add(s,"halo","impact_glow",0,0,680,190,nil,"additive")
    add(s,"wingL","copper_wing",-260,0,190,75)
    add(s,"wingR","copper_wing",260,0,190,75); s.bones[#s.bones].scaleX=-1
    add(s,"plate","nameplate",0,0,740,340)
    add(s,"seal","seal_plate",-280,0,87,87)
    add(s,"wheel","rune_ring",-280,0,108,108)
    add(s,"fire","smoke_flame",-282,5,90,145)
    add(s,"sweep","light_sweep",0,0,630,80,nil,"additive")
    local D=3.2; local a=newAnimation(s,"power",D)
    for _,n in ipairs({"halo","wingL","wingR","plate","seal","wheel","fire"}) do appear(a,n,D,.01,.34,2.63) end
    colorKeys(a,"sweep",{{time=0,color="ffffff00"},{time=.32,color="ffffff00"},{time=.55,color="ffffffb3"},
        {time=.95,color="ffffff00"},{time=2.4,color="ffffff00"},{time=2.72,color="ffffff66"},{time=D,color="ffffff00"}})
    scale(a,"root",{{time=0,x=.82,y=.65},{time=.3,x=1.02,y=1.04},{time=.46,x=1,y=1},{time=2.65,x=1,y=1},{time=D,x=.96,y=.86}})
    translate(a,"root",{{time=0,x=0,y=-12},{time=.4,x=0,y=0},{time=2.65,x=0,y=0},{time=D,x=0,y=8}})
    rotate(a,"wheel",{{time=0,value=-25},{time=D,value=38}})
    for _,n in ipairs({"wingL","wingR"}) do local sign=n=="wingL" and -1 or 1
        translate(a,n,{{time=0,x=-sign*40,y=-5},{time=.36,x=0,y=0},{time=D,x=sign*7,y=0}})
        rotate(a,n,{{time=0,value=sign*15},{time=.4,value=0},{time=D,value=sign*2}})
    end
    translate(a,"sweep",{{time=0,x=-160,y=0},{time=1,x=140,y=0},{time=2.4,x=-140,y=0},{time=D,x=180,y=0}})
    scale(a,"sweep",{{time=0,x=.5,y=.6},{time=.65,x=1,y=1},{time=D,x=.8,y=.5}})
    scale(a,"fire",{{time=0,x=.5,y=.2},{time=.4,x=1,y=1},{time=1.2,x=.85,y=1.1},{time=2.2,x=1,y=.96},{time=D,x=.65,y=1.1}})
    return s
end
local function buildSkeletons()
    return {card_fx=cardSkeleton(),result_fx=resultSkeleton(),power_fx=powerSkeleton()}
end
local function checkSkeleton(s,n)
    assert(s.skeleton.spine=="4.2.43","Spine版本不符")
    assert(#s.bones>5 and #s.slots>5,"骨架未分层")
    assert(s.skins[1].name=="default","缺少default skin")
    local bones,slots={},{}
    for _,b in ipairs(s.bones) do assert(not bones[b.name],"重复bone"); if b.parent then assert(bones[b.parent],"无效bone parent") end; bones[b.name]=true end
    for _,slot in ipairs(s.slots) do
        assert(bones[slot.bone] and not slots[slot.name],"slot骨骼或命名无效")
        slots[slot.name]=true
        assert(REGIONS[slot.attachment],"attachment不在图集")
        assert(s.skins[1].attachments[slot.name][slot.attachment],"skin缺少attachment")
    end
    local expected=n=="card_fx" and {level=1.3333,job=1.3333,revive=.9} or (n=="result_fx" and {success=1.6667,failure=1.3333} or {power=3.2})
    for name,duration in pairs(expected) do
        local a=s.animations[name]; assert(a,"缺少动画"..name)
        local maximum=0
        for b,timelines in pairs(a.bones) do assert(bones[b],"timeline无效bone")
            for kind,keys in pairs(timelines) do
                assert(kind=="translate" or kind=="scale" or kind=="rotate","未知bone timeline")
                local previous=-1
                for _,key in ipairs(keys) do
                    assert(key.time>=previous and key.time<=duration,"关键帧时间异常")
                    if kind=="rotate" then assert(type(key.value)=="number" and key.angle==nil,"不是4.2 rotate.value关键帧") end
                    previous=key.time; maximum=math.max(maximum,key.time)
                end
            end
        end
        for slot,timeline in pairs(a.slots) do
            assert(slots[slot] and timeline.rgba and not timeline.color,"不是4.2 rgba timeline")
            local previous=-1
            for _,key in ipairs(timeline.rgba) do
                assert(key.time>=previous and key.time<=duration and key.color:match("^%x%x%x%x%x%x%x%x$"),"color关键帧异常")
                previous=key.time; maximum=math.max(maximum,key.time)
            end
            assert(timeline.rgba[#timeline.rgba].color:sub(7,8)=="00","动画末帧未透明")
        end
        assert(math.abs(maximum-duration)<.000001,"动画时长不符")
        print(string.format("[暗黑烘焙] 骨架 %s/%s %.4f秒 骨%d 槽%d",n,name,duration,#s.bones,#s.slots))
    end
end
local function ensureResourceMeta()
    local names={}
    for _,r in ipairs(ORDER) do names[#names+1]=r.name..".png" end
    names[#names+1]="atlas.png"
    for _,n in ipairs({"card_fx","result_fx","power_fx"}) do
        names[#names+1]=n..".json"; names[#names+1]=n..".atlas"
    end
    for i,name in ipairs(names) do
        local path=ROOT..name..".meta"
        local uuid=string.format("DarkFx20261007Asset%05d",i)
        if fileSystem:FileExists(path) then
            -- 已有meta绝不覆盖：不匹配直接报错，保持原UUID/文件字节。
            assert(cjson.decode(readText(path)).uuid==uuid,"已有资源meta不匹配，拒绝覆盖："..name)
        else writeText(path,"{\n  \"uuid\": \""..uuid.."\"\n}\n") end
    end
end
local function generate()
    assert(fileSystem:CreateDir(ROOT),"无法创建暗黑特效目录")
    local atlas=track(Image()); assert(atlas:SetSize(ATLAS_SIZE,ATLAS_SIZE,4),"图集创建失败"); atlas:Clear(Color(0,0,0,0))
    for _,r in ipairs(ORDER) do
        print(string.format("[暗黑烘焙] 开始 %s %dx%d CPU 2x",r.name,r.w,r.h))
        local image=renderRegion(r)
        assert(image:SavePNG(ROOT..r.name..".png"),"PNG保存失败："..r.name)
        copyToAtlas(atlas,image,r)
    end
    assert(atlas:SavePNG(ROOT.."atlas.png"),"图集保存失败")
    local text=atlasText(); local skeletons=buildSkeletons()
    for _,n in ipairs({"card_fx","result_fx","power_fx"}) do
        checkSkeleton(skeletons[n],n)
        writeText(ROOT..n..".atlas",text)
        writeText(ROOT..n..".json",stableJSON(skeletons[n]).."\n")
    end
end
local function loadImage(path)
    local image=track(Image())
    assert(image:Load(path),"图片加载失败："..path)
    return image
end
local function verify(repeatRender)
    local atlas=loadImage(ROOT.."atlas.png")
    assert(atlas:GetWidth()==ATLAS_SIZE and atlas:GetHeight()==ATLAS_SIZE and atlas:GetComponents()==4,"图集尺寸/通道异常")
    local checked=0; local summary={regions={},atlas={width=ATLAS_SIZE,height=ATLAS_SIZE,extrude=EXTRUDE,straightAlpha=true},
        generator="scripts/_proc/dark_fx_assets.lua",spine="4.2.43",repeatRender=repeatRender,nativeLoad="需现有NVG上下文由宿主另测"}
    for _,r in ipairs(ORDER) do
        local image=loadImage(ROOT..r.name..".png")
        assert(image:GetWidth()==r.w and image:GetHeight()==r.h and image:GetComponents()==4,"region尺寸/通道异常："..r.name)
        local visible,partial,clear,dirty=0,0,0,0
        for y=0,r.h-1 do for x=0,r.w-1 do
            local c=image:GetPixel(x,y)
            if c.a==0 then clear=clear+1; if c.r~=0 or c.g~=0 or c.b~=0 then dirty=dirty+1 end
            else visible=visible+1; if c.a<1 then partial=partial+1 end end
            assert(image:GetPixelInt(x,y)==atlas:GetPixelInt(r.x+x,r.y+y),"atlas与region像素不一致："..r.name)
        end end
        assert(visible>20 and clear>20 and partial>20 and dirty==0,"透明/内容检查失败："..r.name)
        for y=-EXTRUDE,r.h+EXTRUDE-1 do for x=-EXTRUDE,r.w+EXTRUDE-1 do
            assert(atlas:GetPixelInt(r.x+x,r.y+y)==image:GetPixelInt(clamp(x,0,r.w-1),clamp(y,0,r.h-1)),"图集extrude失败")
        end end
        if repeatRender then local rendered=renderRegion(r)
            for y=0,r.h-1 do for x=0,r.w-1 do assert(rendered:GetPixelInt(x,y)==image:GetPixelInt(x,y),"CPU复绘不一致："..r.name) end end
        end
        summary.regions[#summary.regions+1]={name=r.name,width=r.w,height=r.h,x=r.x,y=r.y,visible=visible,partialAlpha=partial,transparent=clear,transparentDirty=dirty}
        checked=checked+r.w*r.h
        print(string.format("[暗黑烘焙] 校验 %s 可见%d 半透明%d 全透明%d 残色%d",r.name,visible,partial,clear,dirty))
    end
    local skeletons=buildSkeletons()
    for _,n in ipairs({"card_fx","result_fx","power_fx"}) do
        local json=readText(ROOT..n..".json")
        assert(json==stableJSON(skeletons[n]).."\n","JSON不匹配生成器："..n)
        checkSkeleton(cjson.decode(json),n)
        assert(readText(ROOT..n..".atlas")==atlasText(),"atlas文本不一致")
    end
    summary.regionPixels=checked
    assert(fileSystem:CreateDir(EVIDENCE),"验证目录创建失败")
    writeText(EVIDENCE.."assets-verification.json",stableJSON(summary).."\n")
    print(string.format("[暗黑烘焙] ALL PASS：14独立PNG + 共享atlas.png + 三套Spine4.2.43；像素%d，CPU复绘=%s",checked,tostring(repeatRender)))
end
function Start()
    local ok,err=pcall(function()
        local verifyOnly,repeatRender,textOnly=false,false,false
        for _,arg in ipairs(GetArguments()) do
            if arg=="-verify-only" then verifyOnly=true elseif arg=="-verify-repeat" then repeatRender=true
            elseif arg=="-text-only" then textOnly=true end
        end
        packAtlas()
        if textOnly then
            local skeletons=buildSkeletons()
            for _,n in ipairs({"card_fx","result_fx","power_fx"}) do
                checkSkeleton(skeletons[n],n)
                writeText(ROOT..n..".atlas",atlasText())
                writeText(ROOT..n..".json",stableJSON(skeletons[n]).."\n")
            end
        elseif not verifyOnly then generate() end
        if not verifyOnly then ensureResourceMeta() end
        releaseImages()
        verify(repeatRender)
    end)
    releaseImages()
    if not ok then log:Write(LOG_ERROR,"[暗黑烘焙] FAILED："..tostring(err)) end
    -- 无论失败成功都退出；不把业务异常或engine:Exit置于pcall内部。
    engine:Exit()
end
