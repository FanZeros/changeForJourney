-- 通天塔暗契独立离线资源。基于 dark_fx_assets.lua 的 CPU 扫描/预乘降采样/稳定JSON/VectorBuffer脚手架。
-- 不引用该生成器、不读取旧PNG、不使用随机数，不接游戏逻辑，也不创建NanoVG/GPU上下文。
-- 运行：UrhoXRuntime _proc/tower_dark_assets.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless -nosound
-- -verify-only 不写正式资产；-verify-repeat 在内存重绘，逐像素绑定所有成图与图集。
-- Spine API约定：awaken 0.8秒，调用方loop=false；idle 3秒，调用方loop=true。
-- Spine格式本身不存loop开关；idle首尾色值/位移/缩放一致，旋转整周，避免接缝跳变。
local ROOT = "/workspace/assets/image/通天塔暗契/"
local EVIDENCE = "/workspace/.git/validation/tower/"
local SCRIPT = "/workspace/scripts/_proc/tower_dark_assets.lua"
local SCALE, ATLAS_SIZE, EXTRUDE = 2, 1024, 2
local PI = math.pi
local IRON, BRONZE, BONE, BLOOD = {23,23,26}, {162,116,66}, {226,212,180}, {148,38,33}
local SHADOW = {8,8,11}
local ORDER = {
    {name="blade",w=192,h=192}, {name="tome",w=192,h=192},
    {name="blood",w=192,h=192}, {name="eye",w=192,h=192},
    {name="shield",w=192,h=192}, {name="chain",w=192,h=192},
    {name="bell",w=192,h=192}, {name="seal_ring",w=256,h=256},
    {name="rift",w=64,h=256}, {name="ember",w=32,h=64},
}
-- 一次性新生成的32位安全UUID。生成器运行不消费随机数；已有meta逐字节保留。
local IDS = {
    generator="769ffb9878c9467c884e85cd8e8e4d00",
    ["blade.png"]="02448c85b992479292d997713817b65c",
    ["tome.png"]="776ced47ae274b43b5fa3d24c34fc665",
    ["blood.png"]="eee4f14463834955a07c3cff959b72af",
    ["eye.png"]="ef5acf723af7422eb5ee6185989d25c4",
    ["shield.png"]="6b28df5b3b524b5c921cee72d5769288",
    ["chain.png"]="589472723a844bdea698b783a964a5d8",
    ["bell.png"]="7be1c03df0e94a09bcafd6ba5e476aa7",
    ["seal_ring.png"]="5065e27ed0e24631983769396a0826e1",
    ["rift.png"]="9484e39cdb3a4da48302a72477fc001e",
    ["ember.png"]="f8278a2cea3140429198007b685c0d7a",
    ["atlas.png"]="9244aa05fa784c8a82de943f2b562dd7",
    ["tower_oath.json"]="6ef552977051445abd5eb7ed8c786666",
    ["tower_oath.atlas"]="1799d81cb659404c930164889050eee7",
}
---@type Image[]
local ownedImages = {}
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function mix(a,b,t) return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t} end
---@param image Image
---@return Image
local function track(image) ownedImages[#ownedImages+1]=image; return image end
local function releaseImages()
    for _,image in ipairs(ownedImages) do image:Dispose() end
    ownedImages={}
end
local function writeText(path,text)
    local f=File(path,FILE_WRITE)
    assert(f:IsOpen(),"打开输出失败："..path)
    -- WriteString追加NUL，不用于标准JSON/atlas。原始UTF-8字节写出并校验长度。
    local buffer=VectorBuffer()
    for i=1,#text do assert(buffer:WriteUByte(string.byte(text,i)),"编码字节失败") end
    local written=f:Write(buffer)
    f:Close(); f:Dispose()
    assert(written==#text,"输出长度异常："..path)
end
local function readText(path)
    local f=File(path,FILE_READ)
    assert(f:IsOpen(),"打开输入失败："..path)
    local buffer=f:Read(f:GetSize())
    local bytes={}
    for i=1,buffer:GetSize() do bytes[i]=string.char(buffer:ReadUByte()) end
    f:Close(); f:Dispose()
    return table.concat(bytes)
end
local function stableJSON(value)
    if type(value)~="table" then
        if type(value)=="number" then
            assert(value==value and math.abs(value)<math.huge,"JSON含非法数值")
            local result=string.format("%.6f",value):gsub("0+$",""):gsub("%.$","")
            return result=="-0" and "0" or result
        end
        return cjson.encode(value)
    end
    local count,numeric=0,true
    for k in pairs(value) do count=count+1; if type(k)~="number" then numeric=false end end
    if numeric and count>0 and count==#value then
        local values={}
        for _,v in ipairs(value) do values[#values+1]=stableJSON(v) end
        return "["..table.concat(values,",").."]"
    end
    local keys={}
    for k in pairs(value) do assert(type(k)=="string","JSON非连续数组必须使用字符串键"); keys[#keys+1]=k end
    table.sort(keys)
    local values={}
    for _,k in ipairs(keys) do values[#values+1]=cjson.encode(k)..":"..stableJSON(value[k]) end
    return "{"..table.concat(values,",").."}"
end

-- CPU可变画布：2倍母图、连续金属光面、扫描填充；RGBA内部预乘，最终成图straight alpha。
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
            local py=(y+.5)/SCALE
            local base=bottom and mix(top,bottom,clamp((py-y0)/math.max(1,y1-y0),0,1)) or top
            for x=math.max(0,math.floor(x0*SCALE)),math.min(W-1,math.ceil(x1*SCALE)) do
                local px=(x+.5)/SCALE; local coverage=inside(px,py)
                if coverage and coverage~=0 then
                    local color=base
                    if metal then
                        -- 无噪声或旧图采样，只有克制的大面明暗。
                        local key=math.exp(-((px-w*.32)^2+(py-h*.23)^2)/(w*h*.1))*.13
                        local f=.91+key+math.sin(py*.044+px*.018)*.022
                        color={clamp(base[1]*f,0,255),clamp(base[2]*f,0,255),clamp(base[3]*f,0,255)}
                    end
                    blend(x,y,color,(opacity or 1)*(type(coverage)=="number" and coverage or 1))
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
    local function arc(cx,cy,rx,ry,first,last,width,color,opacity)
        local points={}
        for i=0,96 do local a=(first+(last-first)*i/96)*PI/180; points[#points+1]={cx+math.cos(a)*rx,cy+math.sin(a)*ry} end
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
        for i=1,32 do local t,u=i/32,1-i/32
            points[#points+1]={u^3*p[1]+3*u*u*t*x1+3*u*t*t*x2+t^3*x3,u^3*p[2]+3*u*u*t*y1+3*u*t*t*y2+t^3*y3}
        end
    end
    local function bevel(points,top,bottom,width)
        stroke(points,(width or 2)+3,SHADOW,true)
        polygon(points,top,bottom,1,true)
        stroke(points,width or 2,BRONZE,true)
        for i=1,#points-1 do
            if points[i+1][2]<=points[i][2]+.1 then line(points[i][1],points[i][2],points[i+1][1],points[i+1][2],.85,BONE,.65) end
        end
    end
    local function rivet(x,y,r)
        ellipse(x+.5,y+1,r+1,r+1,SHADOW)
        ellipse(x,y,r,r,{188,151,95},{66,45,29},1,true)
        line(x-r*.5,y-r*.35,x+r*.45,y-r*.35,.8,BONE,.75)
    end
    local function rune(x,y,s,n,color,opacity)
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
        local image=track(Image()); assert(image:SetSize(w,h,4),"成图创建失败")
        for y=0,h-1 do for x=0,w-1 do
            local r,g,b,a=0,0,0,0
            for sy=0,SCALE-1 do for sx=0,SCALE-1 do local i=(y*SCALE+sy)*W+x*SCALE+sx+1
                r,g,b,a=r+red[i],g+green[i],b+blue[i],a+alpha[i]
            end end
            local qa=math.floor(clamp(a/(SCALE*SCALE),0,1)*255+.5)
            if qa>0 then
                local qr,qg,qb=math.floor(clamp(r/a,0,255)+.5),math.floor(clamp(g/a,0,255)+.5),math.floor(clamp(b/a,0,255)+.5)
                image:SetPixelInt(x,y,Color(qr/255,qg/255,qb/255,qa/255):ToUInt())
            else image:SetPixelInt(x,y,0) end
        end end
        return image
    end
    return {w=w,h=h,scan=scan,polygon=polygon,line=line,stroke=stroke,ellipse=ellipse,arc=arc,
        glow=glow,curve=curve,bevel=bevel,rivet=rivet,rune=rune,finish=finish}
end

-- 七主题不共用满圆底板，让装备/仪式器物的轮廓在小尺寸仍清楚。
-- blade：骨刃直剑、实体十字护手、缠带柄与铜首，不是箭头。
local function drawBlade(d)
    d.bevel({{42,157},{35,144},{49,127},{72,126},{76,144},{60,157}}, {118,99,70},{43,36,31},1.8)
    d.bevel({{58,134},{68,122},{99,153},{91,168},{78,165}}, {150,119,76},{53,38,29},1.6)
    d.line(66,137,78,129,2,SHADOW,.9); d.line(72,143,84,135,2,SHADOW,.9)
    d.line(78,149,90,141,2,SHADOW,.9)
    local blade={{79,107},{125,33},{150,20},{151,52},{107,126},{95,129}}
    d.bevel(blade,{231,215,180},{112,115,119},2)
    d.polygon({{99,110},{139,40},{146,29},{146,53},{106,120}}, {88,91,101},{36,39,46},1,true)
    d.line(93,110,137,36,1.2,BONE,.9)
    d.stroke({{121,57},{117,73},{126,78}},1.5,SHADOW,false,.9)
    d.bevel({{51,113},{58,99},{115,130},{124,125},{132,140},{121,150},{68,116},{59,123}},
        {194,150,90},{67,46,32},1.8)
    d.rivet(86,121,4); d.rune(105,135,8,2,BONE,.8)
    d.bevel({{79,162},{92,150},{108,158},{103,174},{91,181},{78,175}},{173,129,78},{55,38,29},1.5)
    d.rivet(94,166,3)
end
-- tome：厚页法典、两段铜书脊、锁扣与镶晶，封面不画大箭头。
local function drawTome(d)
    d.bevel({{40,41},{133,29},{161,50},{161,147},{65,166},{38,146}}, {126,96,63},{39,33,31},2.4)
    d.polygon({{53,49},{141,41},{151,52},{151,140},{61,155},{52,145}}, {208,194,158},{122,111,91},1,true)
    for y=64,140,10 do d.line(137,y-15,151,y-12,1.1,{65,57,46},.72) end
    d.bevel({{40,37},{135,24},{142,35},{142,136},{50,153},{40,145}}, {53,52,53},{22,23,28},2)
    d.bevel({{43,41},{62,39},{63,147},{48,151},{42,143}}, {175,134,78},{56,41,31},1.5)
    for _,y in ipairs({58,115}) do
        d.bevel({{39,y},{65,y-4},{66,y+11},{39,y+15}}, {184,140,80},{64,44,31},1.1)
        d.rivet(51,y+5,2.3)
    end
    d.bevel({{76,63},{112,52},{128,65},{127,111},{94,126},{76,111}}, {125,98,65},{39,36,35},1.3)
    d.bevel({{101,63},{115,81},{110,107},{95,115},{90,89}}, {155,70,56},{62,26,28},1.3)
    d.polygon({{102,65},{111,80},{99,99},{93,88}}, {220,188,144},{129,87,70},.85)
    d.line(101,82,106,92,1.2,BONE,.9)
    d.bevel({{125,91},{156,88},{161,98},{155,107},{126,110}}, {184,144,85},{61,44,34},1.2)
    d.rivet(145,99,3); d.rune(89,140,9,5,BRONZE,.92)
    d.polygon({{73,152},{83,150},{83,178},{75,172},{69,180}}, BLOOD,{68,21,25},1,true)
end
-- blood：刻血杯、暗红液面与骨柄祭刃，以祭器实体表达，不是爱心/掉血机制图。
local function drawBlood(d)
    d.bevel({{35,47},{109,47},{105,86},{93,106},{80,116},{80,145},{103,158},{103,168},{41,168},{41,158},{63,145},{63,116},{50,106},{38,85}},
        {152,123,86},{52,39,32},2)
    d.ellipse(72,48,37,11,SHADOW)
    d.ellipse(72,48,30,7,{145,42,36},{61,21,26},1,true)
    d.arc(72,48,34,9,175,365,1.2,BONE,.6)
    d.line(44,59,49,85,1.6,BONE,.68); d.line(68,120,68,143,1.1,BONE,.65)
    d.rune(72,86,18,6,{194,154,96},.9)
    d.bevel({{118,97},{126,49},{144,28},{151,52},{141,102},{131,112}}, {230,215,184},{108,102,95},1.5)
    d.line(128,89,143,47,1.1,BONE,.9)
    d.polygon({{123,88},{128,67},{132,77},{128,101}}, BLOOD,{68,24,25},.93)
    d.bevel({{111,103},{147,112},{145,121},{110,113}}, {170,126,73},{48,35,28},1.5)
    d.bevel({{122,120},{133,122},{126,160},{112,165},{110,154}}, {71,65,54},{29,28,31},1.4)
    for y=127,151,8 do d.line(116,y,130,y+4,1.4,BRONZE,.85) end
    d.rivet(118,160,3)
    local drop={{91,126}}; d.curve(drop,81,139,83,149,91,151); d.curve(drop,101,149,101,138,91,126)
    d.polygon(drop,{166,42,35},{60,20,27},.95)
end
-- eye：占卜面甲/第三眼镶座，额盔和双颊护片赋予职业轮廓。
local function drawEye(d)
    d.bevel({{45,41},{69,25},{124,25},{148,41},{151,96},{136,134},{111,167},{95,179},{78,166},{56,134},{40,96}},
        {97,94,89},{28,29,33},2.2)
    d.bevel({{46,67},{65,37},{95,30},{84,64},{55,93},{44,93}}, {190,153,96},{67,50,36},1.4)
    d.bevel({{106,31},{131,40},{145,68},{146,93},{133,93},{107,66}}, {142,117,80},{50,41,33},1.4)
    d.bevel({{50,105},{74,118},{86,157},{69,141},{53,126}}, {134,132,119},{41,41,43},1.2)
    d.bevel({{143,105},{118,118},{106,157},{124,140},{140,123}}, {133,116,88},{42,37,33},1.2)
    local eye={{53,83}}; d.curve(eye,77,54,112,54,139,82); d.curve(eye,113,108,80,110,53,83)
    d.stroke(eye,6,SHADOW,true); d.polygon(eye,{208,195,163},{114,102,83},1,true); d.stroke(eye,1.6,BRONZE,true)
    d.ellipse(96,82,16,20,{150,48,37},{59,21,25},1,true)
    d.ellipse(96,82,4,16,SHADOW); d.line(89,68,92,71,2.1,BONE,.86)
    d.bevel({{88,116},{103,116},{111,142},{96,157},{81,142}}, {170,144,101},{57,43,33},1.2)
    d.polygon({{91,125},{101,125},{104,141},{96,145},{88,140}}, SHADOW)
    d.rivet(95,41,3); d.rivet(59,119,2); d.rivet(131,119,2)
end
-- shield：尖底门盾、铜铰链和实体封扣；正视轮廓非抽象防御箭头。
local function drawShield(d)
    local p={{43,31},{95,19},{149,31},{151,101},{139,131},{96,174},{53,131},{41,100}}
    d.bevel(p,{165,132,86},{51,40,32},2.8)
    d.bevel({{55,41},{96,32},{137,41},{138,96},{127,120},{96,154},{65,120},{54,96}},
        {53,53,55},{21,23,29},1.8)
    d.bevel({{87,38},{105,38},{105,144},{96,155},{86,143}}, {161,128,83},{63,46,32},1.2)
    d.bevel({{49,79},{143,79},{147,89},{142,101},{50,101},{46,89}}, {180,142,84},{56,39,30},1.6)
    d.bevel({{86,73},{108,73},{114,89},{108,105},{86,105},{79,89}}, {205,165,98},{72,49,30},1.5)
    d.ellipse(96,89,5,9,SHADOW); d.line(95,94,97,99,2,SHADOW)
    for _,p0 in ipairs({{53,51},{138,51},{58,113},{134,113}}) do d.rivet(p0[1],p0[2],3) end
    d.line(63,54,63,75,1.1,BONE,.65); d.line(127,104,119,120,1.1,BONE,.7)
    d.rune(96,132,12,4,BLOOD,.86)
end
-- chain：交错实体铁链、刻印铜锁和骨扣，链环开孔保持透明而非涂满背景。
local function drawChain(d)
    local function link(cx,cy,rotation,rx,ry,top)
        local points={}
        local a=rotation*PI/180
        for i=0,48 do local t=i*PI/24; local x,y=math.cos(t)*rx,math.sin(t)*ry
            points[#points+1]={cx+x*math.cos(a)-y*math.sin(a),cy+x*math.sin(a)+y*math.cos(a)}
        end
        d.stroke(points,14,SHADOW,true)
        d.stroke(points,9,{65,63,64},true)
        d.stroke(points,4,top,true)
        d.stroke({points[28],points[29],points[30],points[31],points[32],points[33]},1.1,BONE,false,.8)
    end
    link(47,45,-38,18,28,{149,132,103})
    link(71,76,38,15,26,{132,120,99})
    link(139,45,38,18,28,{150,124,85})
    link(116,76,-38,15,26,{132,109,77})
    d.arc(95,102,28,32,180,360,15,SHADOW)
    d.arc(95,102,28,32,180,360,9,{122,115,98})
    d.arc(95,102,28,32,193,300,1.2,BONE,.75)
    d.bevel({{65,100},{125,100},{132,111},{132,152},{118,170},{74,170},{58,153},{58,113}},
        {171,132,76},{52,38,30},2)
    d.bevel({{72,111},{120,111},{122,146},{112,156},{79,156},{68,146}}, {49,47,43},{21,23,28},1.3)
    d.ellipse(96,129,7,8,SHADOW); d.polygon({{93,134},{100,134},{104,147},{89,147}},SHADOW)
    d.rune(115,143,8,5,BRONZE,.9)
    d.rivet(69,110,2.5); d.rivet(121,110,2.5)
    d.line(78,164,112,164,1,BONE,.75)
end
-- bell：手铃、铸铜罩、环柄与露出的钟舌，轮廓不依赖声波图解。
local function drawBell(d)
    d.arc(97,43,17,23,0,360,10,SHADOW)
    d.arc(97,43,17,23,0,360,5,{167,132,80})
    d.arc(97,43,17,23,200,320,1.1,BONE,.75)
    d.bevel({{89,59},{105,59},{109,73},{86,73}}, {174,139,87},{60,42,31},1.4)
    local p={{43,136},{53,126},{60,92}}; d.curve(p,64,66,128,63,135,92)
    p[#p+1]={143,126}; p[#p+1]={151,136}; p[#p+1]={149,146}; p[#p+1]={44,146}
    d.bevel(p,{191,151,93},{71,49,33},2.3)
    d.polygon({{65,123},{72,89},{84,80},{82,119}}, {213,191,149},{128,105,71},.65,true)
    d.line(132,98,139,126,1.1,{46,32,27},.8)
    d.bevel({{40,134},{152,134},{156,145},{149,154},{46,154},{37,145}}, {197,159,99},{63,44,30},1.8)
    d.ellipse(97,151,47,8,SHADOW)
    d.arc(97,151,48,8,0,180,1.3,BRONZE,.9)
    d.bevel({{91,149},{102,149},{105,165},{99,173},{90,167}}, {188,165,120},{79,64,43},1.2)
    d.rune(98,104,20,3,{226,208,165},.82)
    for _,x in ipairs({57,137}) do d.rivet(x,142,2.5) end
end
local function drawRing(d)
    local cx,cy=128,128
    -- 中央完全透明：提供环而非发光圆盘，静态fallback可叠任意主题纹章。
    d.arc(cx,cy,104,104,0,360,10,SHADOW)
    d.arc(cx,cy,104,104,0,360,5.5,{142,100,57})
    d.arc(cx,cy,104,104,187,315,1.15,BONE,.86)
    d.arc(cx,cy,85,85,0,360,2.1,BRONZE,.88)
    d.arc(cx,cy,80,80,0,360,1,{84,59,42},.8)
    for i=0,23 do
        local a=(i*15-90)*PI/180
        d.rune(cx+math.cos(a)*94,cy+math.sin(a)*94,9,i+1,i%6==0 and BONE or BRONZE,.92)
        if i%3==0 then
            local p={}
            for _,v in ipairs({{111,-4},{118,0},{111,4},{107,0}}) do
                p[#p+1]={cx+math.cos(a)*v[1]-math.sin(a)*v[2],cy+math.sin(a)*v[1]+math.cos(a)*v[2]}
            end
            d.bevel(p,{179,139,82},{55,38,28},.8)
        end
    end
    for i=0,3 do local a=(i*90+45)*PI/180; d.rivet(cx+math.cos(a)*104,cy+math.sin(a)*104,2.5) end
    for _,a0 in ipairs({0,90,180,270}) do local a=a0*PI/180
        d.line(cx+math.cos(a)*81,cy+math.sin(a)*81,cx+math.cos(a)*85,cy+math.sin(a)*85,1.6,BLOOD,.75)
    end
end
local function drawRift(d)
    d.glow(32,128,29,120,BLOOD,.23,2.7)
    d.glow(32,128,13,113,{162,92,59},.28,2.5)
    local p={{31,13},{27,46},{34,69},{29,94},{35,125},{28,154},{34,182},{30,213},{32,244}}
    d.stroke(p,7,{83,26,25},false,.75)
    d.stroke(p,2.7,{192,136,83},false,.86)
    d.stroke(p,.9,BONE,false,.82)
    d.stroke({{33,69},{43,85},{47,110}},1.2,BRONZE,false,.52)
    d.stroke({{28,154},{20,181},{16,205}},1.1,BLOOD,false,.58)
end
local function drawEmber(d)
    d.glow(16,34,14,27,BLOOD,.3,3)
    d.polygon({{14,10},{21,25},{20,43},{14,54},{10,32}}, {188,125,66},{105,29,27},.92)
    d.polygon({{14,22},{17,29},{16,43},{13,39}}, BONE,{154,97,54},.82)
    d.line(14,26,16,34,.8,BONE,.7)
end
local DRAWERS={blade=drawBlade,tome=drawTome,blood=drawBlood,eye=drawEye,shield=drawShield,
    chain=drawChain,bell=drawBell,seal_ring=drawRing,rift=drawRift,ember=drawEmber}
local function renderRegion(region)
    local d=canvas(region.w,region.h); DRAWERS[region.name](d); return d.finish()
end
local REGIONS={}
for _,r in ipairs(ORDER) do REGIONS[r.name]=r end
local function packAtlas()
    local x,y,rowH=4,4,0
    for _,r in ipairs(ORDER) do
        if x+r.w+4>ATLAS_SIZE then x,y,rowH=4,y+rowH+8,0 end
        assert(y+r.h+4<=ATLAS_SIZE,"图集容量不足")
        r.x,r.y=x,y; x=x+r.w+8; rowH=math.max(rowH,r.h)
    end
end
local function atlasText()
    local rows={"atlas.png","size: 1024, 1024","format: RGBA8888","filter: Linear, Linear","repeat: none"}
    for _,r in ipairs(ORDER) do
        rows[#rows+1]=r.name; rows[#rows+1]="  rotate: false"
        rows[#rows+1]=string.format("  xy: %d, %d",r.x,r.y)
        rows[#rows+1]=string.format("  size: %d, %d",r.w,r.h)
        rows[#rows+1]=string.format("  orig: %d, %d",r.w,r.h)
        rows[#rows+1]="  offset: 0, 0"; rows[#rows+1]="  index: -1"
    end
    return table.concat(rows,"\n").."\n"
end
---@param atlas Image
---@param image Image
local function copyToAtlas(atlas,image,r)
    for y=-EXTRUDE,r.h+EXTRUDE-1 do for x=-EXTRUDE,r.w+EXTRUDE-1 do
        atlas:SetPixelInt(r.x+x,r.y+y,image:GetPixelInt(clamp(x,0,r.w-1),clamp(y,0,r.h-1)))
    end end
end

-- 真4.2：skins数组、region附件、rgba时间轴、rotate.value，不只是改版本字符串。
-- root + 2环 + 2裂光 + 12余烬 = 17骨；主题图标独立给UI，不固定绑在骨架里。
local function oathSkeleton()
    local s={skeleton={hash="tower-oath-cpu-v1",spine="4.2.43",x=-120,y=-120,width=240,height=240,images="./"},
        bones={{name="root"}},slots={},skins={{name="default",attachments={}}},animations={}}
    local function add(name,region,x,y,w,h,rotation,color)
        s.bones[#s.bones+1]={name=name,parent="root",x=x,y=y,rotation=rotation or 0}
        s.slots[#s.slots+1]={name=name,bone=name,attachment=region,color=color}
        s.skins[1].attachments[name]={[region]={type="region",path=region,width=w,height=h}}
    end
    add("wheel","seal_ring",0,0,164,164,0,"ffffffb3")
    add("inner_wheel","seal_ring",0,0,112,112,15,"c8bba080")
    add("rift_left","rift",-78,0,14,150,-3,"ffffff59")
    add("rift_right","rift",78,0,14,150,3,"ffffff59")
    for side=1,2 do for i=1,6 do
        local sign=side==1 and -1 or 1
        add("ember_"..side.."_"..i,"ember",sign*(75+(i%3)*9),-65+(i-1)*22,
            5+(i%3),10+(i%3)*2,sign*(i*7-23),"ffffff66")
    end end
    local a={bones={root={translate={{time=0,x=0,y=0},{time=.8,x=0,y=0}}}},slots={}}
    local idle={bones={root={translate={{time=0,x=0,y=0},{time=3,x=0,y=0}}}},slots={}}
    s.animations.awaken=a; s.animations.idle=idle
    for _,slot in ipairs(s.slots) do
        local name=slot.name; local rgb=slot.color:sub(1,6); local alpha=slot.color:sub(7,8)
        a.slots[name]={rgba={{time=0,color=rgb.."00"},{time=.08,color=rgb.."00"},
            {time=.27,color=rgb.."cc"},{time=.8,color=rgb..alpha}}}
        idle.slots[name]={rgba={{time=0,color=slot.color},{time=1.5,color=rgb.."cc"},{time=3,color=slot.color}}}
    end
    a.bones.wheel={rotate={{time=0,value=-24},{time=.8,value=0}},
        scale={{time=0,x=.68,y=.68},{time=.25,x=1,y=1},{time=.8,x=1,y=1}}}
    a.bones.inner_wheel={rotate={{time=0,value=28},{time=.8,value=0}},
        scale={{time=0,x=.5,y=.5},{time=.36,x=1,y=1},{time=.8,x=1,y=1}}}
    idle.bones.wheel={rotate={{time=0,value=0},{time=3,value=360}}}
    idle.bones.inner_wheel={rotate={{time=0,value=0},{time=3,value=-360}},
        scale={{time=0,x=1,y=1},{time=1.5,x=.94,y=.94},{time=3,x=1,y=1}}}
    for _,name in ipairs({"rift_left","rift_right"}) do
        a.bones[name]={scale={{time=0,x=.3,y=.6},{time=.36,x=1,y=1},{time=.8,x=1,y=1}}}
        idle.bones[name]={scale={{time=0,x=1,y=1},{time=1.5,x=.72,y=.94},{time=3,x=1,y=1}}}
        idle.slots[name]={rgba={{time=0,color="ffffff59"},{time=1.15,color="ffffff80"},{time=2.25,color="ffffff40"},{time=3,color="ffffff59"}}}
    end
    for side=1,2 do for i=1,6 do
        local n="ember_"..side.."_"..i; local sign=side==1 and -1 or 1
        local peak=.75+i*.18
        a.slots[n]={rgba={{time=0,color="ffffff00"},{time=.07+i*.018,color="ffffff00"},
            {time=.3+i*.025,color="ffffffb3"},{time=.8,color="ffffff66"}}}
        a.bones[n]={translate={{time=0,x=-sign*7,y=-12},{time=.45,x=0,y=0},{time=.8,x=0,y=0}},
            scale={{time=0,x=.3,y=.3},{time=.42,x=1,y=1},{time=.8,x=1,y=1}}}
        idle.slots[n]={rgba={{time=0,color="ffffff66"},{time=peak,color="ffffffa6"},{time=peak+.65,color="ffffff33"},{time=3,color="ffffff66"}}}
        idle.bones[n]={translate={{time=0,x=0,y=0},{time=peak,x=sign*3,y=10+(i%3)*2},{time=3,x=0,y=0}},
            rotate={{time=0,value=0},{time=peak,value=sign*12},{time=3,value=0}},
            scale={{time=0,x=1,y=1},{time=peak,x=.82,y=1},{time=3,x=1,y=1}}}
    end end
    return s
end
local function checkSkeleton(s)
    assert(s.skeleton.spine=="4.2.43" and s.skeleton.width==240 and s.skeleton.height==240,"Spine版本/尺寸异常")
    assert(#s.bones==17 and #s.slots==16 and #s.skins==1 and s.skins[1].name=="default","骨架层数异常")
    local bones,slots={},{}
    for _,b in ipairs(s.bones) do
        assert(not bones[b.name],"重复bone")
        if b.parent then assert(bones[b.parent],"无效parent") end
        bones[b.name]=b
    end
    for _,slot in ipairs(s.slots) do
        assert(bones[slot.bone] and not slots[slot.name],"slot绑定异常")
        slots[slot.name]=slot
        local r=REGIONS[slot.attachment]; assert(r,"attachment不在图集")
        local attachment=s.skins[1].attachments[slot.name][slot.attachment]
        assert(attachment.type=="region" and attachment.path==slot.attachment,"region附件异常")
        assert(attachment.width>0 and attachment.height>0,"附件尺寸异常")
    end
    for name,duration in pairs({awaken=.8,idle=3}) do
        local animation=s.animations[name]; assert(animation,"缺动画："..name)
        local maximum=0
        for b,timelines in pairs(animation.bones) do
            assert(bones[b],"timeline无效bone")
            for kind,keys in pairs(timelines) do
                assert(kind=="translate" or kind=="scale" or kind=="rotate","非4.2骨骼时间轴")
                local previous=-1
                for _,key in ipairs(keys) do
                    assert(key.time>=previous and key.time<=duration,"关键帧时间异常")
                    if kind=="rotate" then assert(type(key.value)=="number" and key.angle==nil,"不是4.2 rotate.value")
                    else assert(type(key.x)=="number" and type(key.y)=="number","缺变换值") end
                    previous=key.time; maximum=math.max(maximum,key.time)
                end
                if name=="idle" then
                    local first,last=keys[1],keys[#keys]
                    if kind=="rotate" then assert((last.value-first.value)%360==0,"旋转循环接缝异常")
                    else assert(first.x==last.x and first.y==last.y,"位移/缩放循环接缝异常") end
                end
            end
        end
        for _,slot in ipairs(s.slots) do
            local timeline=animation.slots[slot.name]
            assert(timeline and timeline.rgba and not timeline.color,"不是4.2 rgba时间轴")
            local previous=-1
            for _,key in ipairs(timeline.rgba) do
                assert(key.time>=previous and key.time<=duration and key.color:match("^%x%x%x%x%x%x%x%x$"),"RGBA关键帧异常")
                previous=key.time; maximum=math.max(maximum,key.time)
            end
            local first,last=timeline.rgba[1],timeline.rgba[#timeline.rgba]
            assert(last.color==slot.color,"动画结束未落到idle设置态")
            if name=="idle" then assert(first.color==last.color,"颜色循环接缝异常")
            else assert(first.color:sub(7,8)=="00","awaken起始未透明") end
        end
        assert(maximum==duration,"动画时长异常")
        -- 采样每个附件的变换矩形，包含透明像素的全quad均必须落在±120内。
        -- 当前全为root直子骨、线性时间轴，没有未验证的Bezier/父骨变换。
        local function sample(keys,t,key,default)
            if not keys then return default end
            for i=2,#keys do if t<=keys[i].time then
                local a,b=keys[i-1],keys[i]
                local ratio=clamp((t-a.time)/math.max(.000001,b.time-a.time),0,1)
                return a[key]+(b[key]-a[key])*ratio
            end end
            return keys[#keys][key]
        end
        local maximumExtent=0
        for frame=0,300 do
            local t=duration*frame/300
            for _,slot in ipairs(s.slots) do
                local b=bones[slot.bone]; local transform=animation.bones[slot.bone] or {}
                local attachment=s.skins[1].attachments[slot.name][slot.attachment]
                local x=(b.x or 0)+sample(transform.translate,t,"x",0)
                local y=(b.y or 0)+sample(transform.translate,t,"y",0)
                local angle=((b.rotation or 0)+sample(transform.rotate,t,"value",0))*PI/180
                local hw=attachment.width*sample(transform.scale,t,"x",1)*.5
                local hh=attachment.height*sample(transform.scale,t,"y",1)*.5
                local ex=math.abs(math.cos(angle))*hw+math.abs(math.sin(angle))*hh
                local ey=math.abs(math.sin(angle))*hw+math.abs(math.cos(angle))*hh
                local extent=math.max(math.abs(x)+ex,math.abs(y)+ey)
                assert(extent<=120,"附件超出240x240："..name.."/"..slot.name)
                maximumExtent=math.max(maximumExtent,extent)
            end
        end
        print(string.format("[tower-assets] 骨架 %s %.1fs bones=%d slots=%d extent=%.3f",name,duration,#s.bones,#s.slots,maximumExtent))
    end
end
local function outputNames()
    local names={}
    for _,r in ipairs(ORDER) do names[#names+1]=r.name..".png" end
    names[#names+1]="atlas.png"; names[#names+1]="tower_oath.json"; names[#names+1]="tower_oath.atlas"
    return names
end
local function metaPaths()
    local paths={{path=SCRIPT..".meta",uuid=IDS.generator}}
    for _,name in ipairs(outputNames()) do paths[#paths+1]={path=ROOT..name..".meta",uuid=IDS[name]} end
    return paths
end
local function checkExistingMeta(requireAll)
    local seen={}
    for _,entry in ipairs(metaPaths()) do
        assert(entry.uuid:match("^%x+$") and #entry.uuid==32 and not seen[entry.uuid],"UUID格式或唯一性异常")
        seen[entry.uuid]=true
        if fileSystem:FileExists(entry.path) then
            assert(cjson.decode(readText(entry.path)).uuid==entry.uuid,"已有meta不匹配，拒绝覆盖："..entry.path)
        else assert(not requireAll,"缺meta："..entry.path) end
    end
    -- 产物路径存在而缺本任务meta时拒绝任何覆盖，避免把别人的新资源认领为本任务。
    if not requireAll then for _,name in ipairs(outputNames()) do
        assert(not fileSystem:FileExists(ROOT..name) or fileSystem:FileExists(ROOT..name..".meta"),"现有资源未归属本生成器："..name)
    end end
end
local function ensureMeta()
    for _,entry in ipairs(metaPaths()) do
        if not fileSystem:FileExists(entry.path) then writeText(entry.path,"{\n  \"uuid\": \""..entry.uuid.."\"\n}\n") end
    end
end
local function generate()
    checkExistingMeta(false)
    assert(fileSystem:CreateDir(ROOT),"资源目录创建失败")
    -- meta先预留仅本任务路径；已有meta不会打开写入。
    ensureMeta()
    local atlas=track(Image()); assert(atlas:SetSize(ATLAS_SIZE,ATLAS_SIZE,4),"图集创建失败"); atlas:Clear(Color(0,0,0,0))
    for _,r in ipairs(ORDER) do
        print(string.format("[tower-assets] 开始 %s %dx%d CPU2x",r.name,r.w,r.h))
        local image=renderRegion(r)
        assert(image:SavePNG(ROOT..r.name..".png"),"成图保存失败："..r.name)
        copyToAtlas(atlas,image,r)
    end
    assert(atlas:SavePNG(ROOT.."atlas.png"),"图集保存失败")
    local skeleton=oathSkeleton(); checkSkeleton(skeleton)
    writeText(ROOT.."tower_oath.atlas",atlasText())
    writeText(ROOT.."tower_oath.json",stableJSON(skeleton).."\n")
end
---@return Image
local function loadImage(path)
    local image=track(Image()); assert(image:Load(path),"图片加载失败："..path); return image
end
local function verify(repeatRender)
    checkExistingMeta(true)
    local atlas=loadImage(ROOT.."atlas.png")
    assert(atlas:GetWidth()==1024 and atlas:GetHeight()==1024 and atlas:GetComponents()==4,"图集尺寸/通道异常")
    local checked=0; local occupied={}
    local summary={generator="scripts/_proc/tower_dark_assets.lua",pngCount=11,resourceCount=13,metadataCount=14,
        spine="4.2.43",repeatRender=repeatRender,regions={},atlas={width=1024,height=1024,extrude=2,straightAlpha=true},
        nativeLoad="pending:主线程统一build后真实NVG上下文验证",animations={awaken={duration=.8,loop=false},idle={duration=3,loop=true}}}
    for _,r in ipairs(ORDER) do
        local image=loadImage(ROOT..r.name..".png")
        assert(image:GetWidth()==r.w and image:GetHeight()==r.h and image:GetComponents()==4,"region尺寸/通道异常："..r.name)
        local visible,partial,clear,dirty=0,0,0,0
        local minX,minY,maxX,maxY=r.w,r.h,0,0
        for y=0,r.h-1 do for x=0,r.w-1 do
            local c=image:GetPixel(x,y)
            if c.a==0 then clear=clear+1; if c.r~=0 or c.g~=0 or c.b~=0 then dirty=dirty+1 end
            else
                visible=visible+1; if c.a<1 then partial=partial+1 end
                minX,minY,maxX,maxY=math.min(minX,x),math.min(minY,y),math.max(maxX,x),math.max(maxY,y)
            end
            assert(image:GetPixelInt(x,y)==atlas:GetPixelInt(r.x+x,r.y+y),"atlas子区不一致："..r.name)
        end end
        assert(visible>40 and partial>20 and clear>40 and dirty==0,"透明/内容检查失败："..r.name)
        assert(minX>=1 and minY>=1 and maxX<r.w-1 and maxY<r.h-1,"成图轮廓裁边："..r.name)
        for y=-EXTRUDE,r.h+EXTRUDE-1 do for x=-EXTRUDE,r.w+EXTRUDE-1 do
            local index=(r.y+y)*ATLAS_SIZE+r.x+x+1
            assert(not occupied[index],"atlas子区/挤边重叠")
            occupied[index]=true
            assert(atlas:GetPixelInt(r.x+x,r.y+y)==image:GetPixelInt(clamp(x,0,r.w-1),clamp(y,0,r.h-1)),"2px挤边不一致")
        end end
        if repeatRender then
            local rendered=renderRegion(r)
            for y=0,r.h-1 do for x=0,r.w-1 do assert(rendered:GetPixelInt(x,y)==image:GetPixelInt(x,y),"绘图与产物不一致："..r.name) end end
        end
        summary.regions[#summary.regions+1]={name=r.name,width=r.w,height=r.h,x=r.x,y=r.y,visible=visible,
            partialAlpha=partial,transparent=clear,transparentDirty=dirty,bounds={minX,minY,maxX,maxY}}
        checked=checked+r.w*r.h
        print(string.format("[tower-assets] 验证 %s visible=%d partial=%d clear=%d dirty=%d",r.name,visible,partial,clear,dirty))
    end
    -- 完整图集：透明RGB为0，所有未分配像素为0，防止拼包残色/遗漏区域。
    local atlasClear,atlasDirty=0,0
    for y=0,1023 do for x=0,1023 do
        local c=atlas:GetPixel(x,y); local index=y*ATLAS_SIZE+x+1
        if c.a==0 then atlasClear=atlasClear+1; if c.r~=0 or c.g~=0 or c.b~=0 then atlasDirty=atlasDirty+1 end end
        if not occupied[index] then assert(atlas:GetPixelInt(x,y)==0,"图集空白区残像素") end
    end end
    assert(atlasDirty==0,"图集透明RGB残色")
    local json=readText(ROOT.."tower_oath.json"); local skeleton=oathSkeleton()
    assert(json==stableJSON(skeleton).."\n","JSON与生成器不一致")
    checkSkeleton(cjson.decode(json))
    assert(readText(ROOT.."tower_oath.atlas")==atlasText(),"atlas文本不匹配")
    assert(not json:find("\0",1,true),"JSON含NUL")
    -- 七实体主题必须不同，不允许仅换颜色：比较alpha剪影即可证明轮廓不同。
    for i=1,7 do for j=i+1,7 do
        local left=loadImage(ROOT..ORDER[i].name..".png"); local right=loadImage(ROOT..ORDER[j].name..".png")
        local differences=0
        for y=0,191 do for x=0,191 do if left:GetPixel(x,y).a~=right:GetPixel(x,y).a then differences=differences+1 end end end
        assert(differences>800,"职业纹章仅换色或过度相似")
    end end
    summary.regionPixels=checked; summary.atlas.transparent=atlasClear; summary.atlas.transparentDirty=atlasDirty
    summary.boundsSampleCount=602; summary.bones=17; summary.slots=16; summary.silhouettePairs=21
    assert(fileSystem:CreateDir(EVIDENCE),"验证目录创建失败")
    writeText(EVIDENCE..(repeatRender and "assets-verification-repeat.json" or "assets-verification.json"),stableJSON(summary).."\n")
    print(string.format("[tower-assets] ALL PASS 10 sprites + atlas=11 PNG / 1 Spine JSON + 1 atlas / 14 unique metas / pixels=%d repeat=%s",checked,tostring(repeatRender)))
end
function Start()
    local ok,err=pcall(function()
        local verifyOnly,repeatRender=false,false
        for _,arg in ipairs(GetArguments()) do
            if arg=="-verify-only" then verifyOnly=true elseif arg=="-verify-repeat" then repeatRender=true end
        end
        packAtlas()
        if not verifyOnly then generate() end
        releaseImages()
        verify(repeatRender)
    end)
    releaseImages()
    if not ok then log:Write(LOG_ERROR,"[tower-assets] FAILED："..tostring(err)) end
    engine:Exit()
end
