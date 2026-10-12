-- 招募实体器物离线烘焙：复用 dark_fx_assets.lua / advancement/Batch3Raster.lua 的 CPU 扫描、
-- source-over 合成及预乘 2× 降采样脚手架；固定解析几何，无随机、旧图输入、GPU或运行时玩法。
-- UrhoXRuntime _proc/recruit_fx_assets.lua -tapcode_dir=/workspace/game3 -tool_mode -graphicsheadless
-- -verify-only 只读检查本批产物；-verify-repeat 重绘逐像素比较，可与 -verify-only 组合。
local ROOT, SCALE, PI = "/workspace/game3", 2, math.pi
local IRON, BRONZE, BONE = {24,23,25}, {162,116,66}, {239,224,195}
local SHADOW, PATINA = {9,9,12}, {49,68,59}
local ORDER = {
    {name="gate_leaf",w=224,h=640,uuid="84a0e860-7c7f-4a56-861e-667a47fa7deb"},
    {name="seal",w=256,h=256,uuid="e367168c-157c-4f32-a3d7-7b5d07b7d359"},
    {name="rune_ring",w=512,h=512,uuid="1c5f3714-0978-45da-aaf8-465736638f80"},
    {name="card_back",w=198,h=360,uuid="43f82c7f-0fd4-4954-bda1-ec2f2f57c124"},
    {name="rift",w=128,h=640,uuid="62e04f05-7e81-495c-8f72-20966edcdfdb"},
    {name="halo",w=512,h=512,uuid="55f280f0-c823-4a3e-9bb4-4e1aefcfffed"},
    {name="spark",w=32,h=64,uuid="505f3bd3-5d18-4a5e-b661-0a1db15b6798"},
    {name="shard",w=64,h=96,uuid="942a80ea-970e-448d-9140-ad22134b075d"},
}
-- UUID首次由系统随机生成，仅用于meta身份；像素函数不使用随机源，复绘不更换UUID。
---@type Image[]
local ownedImages = {}
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function mix(a,b,t) return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t} end
---@param image Image
---@return Image
local function track(image) ownedImages[#ownedImages+1]=image; return image end
local function release()
    for _,image in ipairs(ownedImages) do image:Dispose() end
    ownedImages={}; collectgarbage("collect")
end
local function text(path,value)
    local f=File(path,value and FILE_WRITE or FILE_READ)
    assert(f:IsOpen(),"打开meta失败："..path)
    local result=""
    if value then
        -- WriteString会追加NUL，标准JSON使用原始UTF-8字节。
        local buffer=VectorBuffer()
        for i=1,#value do assert(buffer:WriteUByte(string.byte(value,i)),"编码meta失败") end
        assert(f:Write(buffer)==#value,"保存meta失败："..path)
    else
        local buffer=f:Read(f:GetSize()); local bytes={}
        for i=1,buffer:GetSize() do bytes[i]=string.char(buffer:ReadUByte()) end
        result=table.concat(bytes)
    end
    f:Close(); f:Dispose(); return result
end
local function meta(path,uuid,readOnly)
    if fileSystem:FileExists(path) then
        assert(cjson.decode(text(path)).uuid==uuid,"meta身份不符，拒绝覆盖："..path)
    else
        assert(not readOnly,"缺少meta："..path)
        text(path,"{\n  \"uuid\": \""..uuid.."\"\n}\n")
    end
end

-- 可变尺寸画布：复制dark_fx的预乘通道累积；Batch3Raster的点中心扫描、线段投影和奇偶填充。
---@param w integer
---@param h integer
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
            local py=(y+.5)/SCALE; local t=clamp((py-y0)/math.max(1,y1-y0),0,1)
            local base=bottom and mix(top,bottom,t) or top
            for x=math.max(0,math.floor(x0*SCALE)),math.min(W-1,math.ceil(x1*SCALE)) do
                local px=(x+.5)/SCALE; local coverage=inside(px,py)
                if coverage and coverage~=0 then
                    local a=(opacity or 1)*(type(coverage)=="number" and coverage or 1); local color=base
                    if metal then
                        -- 连续反光、极轻拉丝、低频氧化色差，不制造噪点棋盘。
                        local key=math.exp(-((px-w*.30)^2+(py-h*.23)^2)/(w*h*.09))*.15
                        local f=.91+key+math.sin(py*2.7+math.sin(px*.06))*.009
                            +math.sin(px*.045+py*.027)*math.sin(py*.037-px*.012)*.028
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
        -- 比既有小图增至128段，512px铜环无可见多边形折角。
        local points={}
        for i=0,128 do local a=(first+(last-first)*i/128)*PI/180; points[#points+1]={cx+math.cos(a)*r,cy+math.sin(a)*r} end
        stroke(points,width,color,false,opacity)
    end
    local function curve(points,x1,y1,x2,y2,x3,y3)
        local p=points[#points]
        for i=1,32 do local t,u=i/32,1-i/32
            points[#points+1]={u^3*p[1]+3*u*u*t*x1+3*u*t*t*x2+t^3*x3,u^3*p[2]+3*u*u*t*y1+3*u*t*t*y2+t^3*y3}
        end
    end
    local function bevel(points,top,bottom,width)
        stroke(points,(width or 2)+3,SHADOW,true); polygon(points,top,bottom,1,true)
        stroke(points,width or 2,BRONZE,true)
        for i=1,#points do local p,q=points[i],points[i%#points+1]
            if q[2]<p[2] or (q[2]==p[2] and q[1]>p[1]) then line(p[1],p[2],q[1],q[2],.8,BONE,.55) end
        end
    end
    local function rivet(x,y,r)
        ellipse(x+.5,y+1,r+1,r+1,SHADOW); ellipse(x,y,r,r,{181,142,87},{58,40,27},1,true)
        line(x-r*.5,y-r*.4,x+r*.4,y-r*.4,.8,BONE,.8)
    end
    local function glow(cx,cy,rx,ry,color,opacity,power)
        scan(cx-rx,cy-ry,cx+rx,cy+ry,function(x,y)
            local d=((x-cx)/rx)^2+((y-cy)/ry)^2; return d<1 and (1-d)^(power or 3) or 0
        end,color,nil,opacity)
    end
    local function finish()
        local image=track(Image()); assert(image:SetSize(w,h,4),"创建成图失败")
        for y=0,h-1 do for x=0,w-1 do
            local r,g,b,a=0,0,0,0
            for sy=0,SCALE-1 do for sx=0,SCALE-1 do local i=(y*SCALE+sy)*W+x*SCALE+sx+1
                r,g,b,a=r+red[i],g+green[i],b+blue[i],a+alpha[i]
            end end
            -- 先预乘均值，再解除预乘；明确量化RGBA，零alpha必须同步清空RGB。
            local qa=math.floor(clamp(a/(SCALE*SCALE),0,1)*255+.5)
            if qa>0 then
                local qr,qg,qb=math.floor(clamp(r/a,0,255)+.5),math.floor(clamp(g/a,0,255)+.5),math.floor(clamp(b/a,0,255)+.5)
                image:SetPixelInt(x,y,qr|(qg<<8)|(qb<<16)|(qa<<24))
            else image:SetPixelInt(x,y,0) end
        end end
        return image
    end
    return {scan=scan,polygon=polygon,line=line,stroke=stroke,ellipse=ellipse,arc=arc,curve=curve,
        bevel=bevel,rivet=rivet,glow=glow,finish=finish}
end
-- 虚构实体封印刻：两组断开的折钩/菱刻，不使用字库或可读文字，可沿铜环旋转。
local function glyph(d,x,y,s,n,a)
    local shapes={{{-.4,-.35},{0,-.08},{-.28,.25}},{{.12,-.3},{.4,.02},{.05,.4}}}
    for j,p in ipairs(shapes) do local points={}
        for _,v in ipairs(p) do local u,z=v[1]*s*(n%2==0 and -1 or 1),v[2]*s
            points[#points+1]={x+math.cos(a)*u-math.sin(a)*z,y+math.sin(a)*u+math.cos(a)*z}
        end
        d.stroke(points,s*.16,SHADOW,false); d.stroke(points,s*.08,j==1 and BRONZE or {192,151,94},false)
    end
end
local function gothic(d,x,y,w,h)
    local p={{x-w*.5,y+h*.5},{x-w*.5,y-h*.1}}
    d.curve(p,x-w*.5,y-h*.31,x-w*.17,y-h*.43,x,y-h*.5)
    d.curve(p,x+w*.17,y-h*.43,x+w*.5,y-h*.31,x+w*.5,y-h*.1)
    p[#p+1]={x+w*.5,y+h*.5}; return p
end
local function drawGate(d)
    -- 左扇门：左肩低、右侧尖顶和直门缝，右扇由宿主镜像；边框/铰链均保留透明安全边。
    local p={{24,614},{24,213}}
    d.curve(p,25,120,110,53,202,17); p[#p+1]={202,614}
    d.bevel(p,{112,91,65},{35,30,29},3.5)
    local inset={{39,598},{39,218}}
    d.curve(inset,40,139,111,79,184,46); inset[#inset+1]={184,598}
    d.bevel(inset,{40,39,40},{17,17,21},1.4)
    for _,x in ipairs({60,102,144}) do
        local y=219-(x-60)*.78; local arch=gothic(d,x,y+91,30,166)
        d.bevel(arch,{67,60,48},{24,24,27},1.1)
        local slit=gothic(d,x,y+89,18,143)
        d.polygon(slit,IRON,{12,13,17},1,true); d.line(x,y+53,x,y+146,.8,BRONZE,.75)
    end
    for _,y in ipairs({376,492}) do
        d.bevel({{48,y-36},{170,y-36},{174,y+45},{48,y+45}},{51,47,41},{20,21,25},1.4)
        d.bevel({{68,y+5},{110,y-22},{153,y+5},{110,y+30}},{95,73,44},{36,31,28},1)
        glyph(d,110,y+4,25,1,0)
        d.line(57,y-28,162,y-28,.8,PATINA,.55)
    end
    for _,y in ipairs({264,430,574}) do
        d.bevel({{13,y-12},{49,y-12},{77,y-4},{92,y},{77,y+5},{49,y+12},{13,y+12}},
            {144,110,67},{43,33,26},1.7)
        d.rivet(28,y,4); d.rivet(58,y,2.8)
        d.line(13,y-9,13,y+9,2,{96,74,49})
    end
    d.bevel({{167,324},{187,312},{208,329},{208,371},{187,386},{167,373}},{169,128,75},{55,38,28},1.4)
    d.ellipse(189,343,8,11,SHADOW); d.arc(189,349,11,0,360,3,BRONZE)
    d.rivet(187,325,2.4); d.rivet(187,376,2.4)
    d.line(199,45,199,603,1.5,{195,159,103},.7)
    d.line(46,586,173,586,2,BRONZE,.6)
    for i=1,4 do glyph(d,61+i*25,571,10,i,0) end
end
local function drawSeal(d)
    local rim={}
    for i=0,11 do local a=(-105+i*30)*PI/180; rim[#rim+1]={128+math.cos(a)*111,128+math.sin(a)*111} end
    d.bevel(rim,{174,136,81},{45,34,29},3)
    d.ellipse(128,128,97,97,IRON,{12,12,16},1,true)
    d.arc(128,128,100,0,360,2,BRONZE); d.arc(128,128,89,0,360,1.4,{99,72,42})
    d.arc(128,128,98,198,308,1,BONE,.6)
    for i=0,15 do local a=i*PI/8-PI/2
        glyph(d,128+math.cos(a)*80,128+math.sin(a)*80,12,i,a+PI/2)
        if i%4==0 then d.rivet(128+math.cos(a)*105,128+math.sin(a)*105,3.4) end
    end
    for _,x in ipairs({113,140}) do
        d.bevel({{x-8,146},{x+8,147},{x+13,205},{x,196},{x-13,210}},{99,62,45},{34,23,23},1)
    end
    local wax={}
    for i=0,63 do local a=i*PI/32; local r=43+2.4*math.sin(a*7)+1.2*math.sin(a*11)
        wax[#wax+1]={128+math.cos(a)*r,126+math.sin(a)*r}
    end
    d.stroke(wax,4,{30,12,14},true); d.polygon(wax,{170,48,38},{63,17,24},1,true)
    d.stroke(wax,1.6,{118,35,28},true)
    d.arc(128,126,34,195,306,1.1,{222,100,72},.75)
    local crest=gothic(d,128,125,36,48)
    d.stroke(crest,3,{60,14,19},true); d.stroke(crest,.85,{185,68,47},true)
    d.line(128,106,128,146,2,{58,14,20}); d.line(120,119,120,141,1.6,{66,17,22})
    d.line(136,119,136,141,1.6,{66,17,22}); d.ellipse(111,103,3.2,1.5,{239,140,99},nil,.65)
end
local function drawRing(d)
    -- 不叠全盘glow：内径严格透明，只有薄铜双环、分段实体符刻与四个接头。
    d.arc(256,256,224,0,360,6,SHADOW); d.arc(256,256,224,0,360,3.2,{133,95,54})
    d.arc(256,256,185,0,360,4,SHADOW); d.arc(256,256,185,0,360,2.1,BRONZE)
    d.arc(256,256,223,193,307,.85,BONE,.78)
    for i=0,31 do local a=i*PI/16-PI/2; local r=204
        local x,y=256+math.cos(a)*r,256+math.sin(a)*r
        glyph(d,x,y,19,i,a+PI/2)
        if i%4==0 then d.arc(256,256,233,i*11.25-94,i*11.25-86,2,{121,83,46}) end
    end
    for i=0,3 do local a=i*PI/2+PI/4; local p={}
        for _,v in ipairs({{223,-5},{235,0},{223,5},{215,0}}) do
            p[#p+1]={256+math.cos(a)*v[1]-math.sin(a)*v[2],256+math.sin(a)*v[1]+math.cos(a)*v[2]}
        end
        d.bevel(p,{184,146,86},{49,35,27},.9)
    end
end
local function drawCard(d)
    local function rim(inset,cut)
        return {{inset+cut,inset},{198-inset-cut,inset},{198-inset,inset+cut},{198-inset,360-inset-cut},
            {198-inset-cut,360-inset},{inset+cut,360-inset},{inset,360-inset-cut},{inset,inset+cut}}
    end
    d.bevel(rim(8,11),{116,94,66},{32,28,28},2.2)
    d.bevel(rim(14,8),{48,44,38},{19,19,23},1.1)
    d.polygon(rim(23,8),IRON,{15,15,19},1,true); d.stroke(rim(22,8),.85,{107,76,44},true)
    -- 小型压花菱纹被限制在角区，不干扰完整门纹章。
    for _,y in ipairs({46,68,90,270,292,314}) do for _,x in ipairs({42,65,88,111,134,157}) do
        d.stroke({{x,y-5},{x+5,y},{x,y+5},{x-5,y}},.65,{49,42,34},true,.65)
    end end
    d.bevel({{99,88},{149,117},{145,225},{126,253},{99,272},{72,253},{53,225},{49,117}},
        {109,83,49},{35,29,26},1.5)
    d.polygon({{99,99},{139,122},{135,221},{117,245},{99,258},{81,245},{63,221},{59,122}},IRON,{13,14,18},1,true)
    local gate=gothic(d,99,177,59,117)
    d.bevel(gate,{145,111,65},{40,32,27},1.3)
    d.polygon(gothic(d,99,179,47,101),{37,36,35},{17,18,22},1,true)
    d.line(99,139,99,225,2.1,SHADOW); d.line(97.5,141,97.5,224,.85,BRONZE)
    for _,x in ipairs({86,112}) do d.stroke(gothic(d,x,178,15,66),1.1,BRONZE,true,.8) end
    for _,y in ipairs({184,212}) do d.line(78,y,120,y,2,{119,86,47}); d.rivet(81,y,1.5); d.rivet(117,y,1.5) end
    d.ellipse(99,196,7,7,{86,29,26},{40,16,20},1,true)
    for _,x in ipairs({31,167}) do for _,y in ipairs({32,328}) do
        d.bevel({{x,y-8},{x+7,y},{x,y+8},{x-7,y}},{163,124,72},{49,34,25},.8); d.rivet(x,y,1.7)
    end end
    for _,y in ipairs({42,317}) do glyph(d,99,y,15,2,0) end
    d.line(34,17,164,17,.9,BONE,.55); d.line(17,42,17,318,.9,{178,142,88},.55)
    d.line(28,342,170,342,.8,{88,59,33}); d.line(181,36,181,324,.8,PATINA,.55)
end
local function drawRift(d)
    d.glow(64,320,59,307,{245,218,170},.26,3)
    d.glow(64,320,29,299,BONE,.63,2.3)
    -- 温暖骨白直裂光；横向高斯核＋纵向平滑窗，避免端点截断或黑色RGB边。
    d.scan(52,18,76,622,function(x,y)
        local t=clamp((y-18)/604,0,1); local fade=math.sin(t*PI)^1.1
        local center=64+1.25*math.sin(y*.014); return fade*math.exp(-((x-center)/3.2)^2)
    end,{255,247,225},nil,.98)
end
local function drawHalo(d)
    -- RGB恒白，亮度完全来自alpha，乘法染色不带原始铜/血色；中间亮、外围渐隐。
    d.glow(256,256,248,248,{255,255,255},.76,3.2)
    d.glow(256,256,128,128,{255,255,255},.73,2.4)
    d.glow(256,256,47,47,{255,255,255},.64,2.1)
end
local function drawSpark(d)
    d.glow(16,32,14,29,BONE,.4,3)
    d.polygon({{16,8},{18.5,27},{27,32},{18.5,36},{16,56},{13.5,36},{5,32},{13.5,27}},
        {255,246,223},{218,198,159},.97)
    d.glow(16,32,4,10,{255,252,239},.85,2)
end
local function drawShard(d)
    d.bevel({{10,73},{16,17},{42,8},{53,30},{41,53},{49,80},{24,87}},
        {164,128,78},{42,31,28},1.5)
    d.polygon({{17,64},{22,25},{39,18},{45,32},{29,54}},IRON,{39,35,30},1,true)
    d.line(18,66,29,54,.85,PATINA,.7); glyph(d,31,35,15,3,-.18)
    d.polygon({{41,53},{47,72},{39,62}}, {136,105,62},{49,35,28},1,true)
    d.rivet(27,73,2.5)
end
local DRAWERS={gate_leaf=drawGate,seal=drawSeal,rune_ring=drawRing,card_back=drawCard,
    rift=drawRift,halo=drawHalo,spark=drawSpark,shard=drawShard}
local function render(r) local d=canvas(r.w,r.h); DRAWERS[r.name](d); return d.finish() end
local function verify(r,path,repeatRender)
    local image=track(Image()); assert(image:Load(path),"加载本批产物失败："..path)
    assert(image:GetWidth()==r.w and image:GetHeight()==r.h and image:GetComponents()==4,"尺寸/通道不符："..r.name)
    local visible,partial,clear,dirty,border,opaque=0,0,0,0,0,0
    for y=0,r.h-1 do for x=0,r.w-1 do local pixel=image:GetPixelInt(x,y); local a=(pixel>>24)&255
        if a==0 then clear=clear+1; if (pixel&0xffffff)~=0 then dirty=dirty+1 end
        else
            visible=visible+1; if a<255 then partial=partial+1 else opaque=opaque+1 end
            if x==0 or y==0 or x==r.w-1 or y==r.h-1 then border=border+1 end
            if r.name=="halo" then assert((pixel&0xffffff)==0xffffff,"halo不是白色染色基底") end
        end
        if r.name=="rune_ring" and (x-256)^2+(y-256)^2<170^2 then assert(a==0,"符环中心不透明") end
    end end
    assert(visible>20 and partial>20 and clear>20 and dirty==0 and border==0,"透明/裁边检查失败："..r.name)
    if r.name=="gate_leaf" or r.name=="seal" or r.name=="card_back" or r.name=="shard" then
        assert(opaque>visible*.70,"实体器物过度透明："..r.name)
    end
    if r.name=="halo" then assert(image:GetPixel(256,256).a>image:GetPixel(400,256).a,"halo未向外围衰减") end
    if repeatRender then local redraw=render(r)
        for y=0,r.h-1 do for x=0,r.w-1 do assert(redraw:GetPixelInt(x,y)==image:GetPixelInt(x,y),"CPU复绘不一致："..r.name) end end
    end
    print(string.format("[招募烘焙] PASS %s %dx%d 可见%d 半透明%d 全透明%d 残色%d 裁边%d 复绘=%s",
        r.name,r.w,r.h,visible,partial,clear,dirty,border,tostring(repeatRender)))
end
function Start()
    local ok,err=pcall(function()
        local args=GetArguments(); local verifyOnly,repeatRender=false,false
        for i,arg in ipairs(args) do
            if arg=="-verify-only" then verifyOnly=true elseif arg=="-verify-repeat" then repeatRender=true
            elseif arg=="-tapcode_dir" then ROOT=assert(args[i+1],"缺少项目ROOT")
            elseif arg:match("^-tapcode_dir=") then ROOT=arg:sub(14) end
        end
        ROOT=ROOT:gsub("/+$","")
        assert(ROOT:sub(1,1)=="/" and not ROOT:match("/%.%./") and ROOT~="","ROOT必须为项目绝对路径")
        local out=ROOT.."/assets/image/招募特效/"
        if not verifyOnly then assert(fileSystem:CreateDir(out),"创建招募目录失败") end
        meta(ROOT.."/scripts/_proc/recruit_fx_assets.lua.meta","5e2f5cd0-99c2-4e2e-8901-7fb5ad685dda",verifyOnly)
        local count=0
        for _,r in ipairs(ORDER) do
            local path=out..r.name..".png"; meta(path..".meta",r.uuid,verifyOnly)
            if not verifyOnly then
                print(string.format("[招募烘焙] CPU 2x开始 %s %dx%d",r.name,r.w,r.h))
                local image=render(r); assert(image:SavePNG(path),"PNG保存失败："..r.name); release()
            end
            verify(r,path,repeatRender); release(); count=count+r.w*r.h
        end
        print(string.format("[招募烘焙] ALL PASS：8张RGBA PNG，%d像素；无裁边、零alpha无残色，UUID固定唯一",count))
    end)
    release()
    if not ok then log:Write(LOG_ERROR,"[招募烘焙] FAILED："..tostring(err)) end
    engine:Exit()
end
