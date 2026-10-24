-- 旧铜 / 骨白 / 魂焰仪式补层：原生 Spine、PNG 与矢量共用，不替换主体媒体。
-- 纯 elapsed/duration 与给定尺寸采样；无随机、文件、事件、业务回调或逐帧粒子列表。
-- 前奏聚光 → 主题铸纹 / 薄扫线 → 局部冲击 → 下落余烬；不是六种换色圆盘。
-- 保持宿主 transform / scissor / globalAlpha；所有内部透明度乘入颜色，不覆盖宿主 alpha。
-- 局部包络：card |x|≤98 |y|≤160（200×350），result |x|≤98 |y|≤98（200×200）；
-- power |x|∈[296,378] |y|≤143（760×340），整条中央580宽文字通道永久留空。
local M = {}
local COPPER = {201, 151, 59}
local BONE = {216, 201, 163}
local EMBER = {231, 126, 53}
local SOUL = {164, 157, 143}
local BLOOD = {166, 58, 48}
local TAU = math.pi * 2
-- 只缓存 API 能力，不持有播放或媒体。缺 API/绘图失败在同 context 单次锁存。
---@type table<any, integer>
local modes = setmetatable({}, {__mode="k"})

local function finite(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function clamp(value) return math.max(0, math.min(1, value)) end
local function smooth(value)
    local p=clamp(value)
    return p*p*(3-2*p)
end
local function stage(p,from,to) return smooth((p-from)/(to-from)) end
local function box(cx,cy,w,h)
    return finite(cx) and finite(cy) and finite(w) and finite(h)
        and math.abs(cx)<=1e6 and math.abs(cy)<=1e6
        and w>=1e-4 and h>=1e-4 and w<=1e6 and h<=1e6
end

-- 数值多返回值，无采样表、无时钟积累；同输入 / A→B→A 得到逐值相同样本。
---@param kind string
---@param elapsed number
---@param duration number
---@param alpha? number
---@return number p
---@return number opacity
---@return number gather
---@return number impact
---@return number sustain
---@return number fall
function M.sample(kind,elapsed,duration,alpha)
    local a=alpha==nil and 1 or alpha
    if (kind~="level" and kind~="job" and kind~="revive" and kind~="success" and kind~="failure" and kind~="power")
        or not finite(elapsed) or not finite(duration) or not finite(a) or duration<=0
        or elapsed<=0 or elapsed>=duration then return 0,0,0,0,0,0 end
    local p=elapsed/duration
    local peak=kind=="revive" and .51 or (kind=="success" and .43 or (kind=="failure" and .23 or .30))
    local impact=stage(p,peak-.08,peak) * (1-stage(p,peak+.035,peak+.19))
    local gather=stage(p,.025,kind=="revive" and .48 or .29)
    local sustain=stage(p,.10,peak+.06) * (1-stage(p,.66,.90))
    local fall=stage(p,kind=="failure" and .38 or .64,.98)
    return p,clamp(a)*stage(p,0,.10)*(1-stage(p,.80,1)),gather,impact,sustain,fall
end

local function api(vg)
    local mode=modes[vg]
    if mode~=nil then return mode end
    local basic=type(nvgSave)=="function" and type(nvgRestore)=="function"
        and type(nvgTranslate)=="function" and type(nvgScale)=="function"
        and type(nvgBeginPath)=="function" and type(nvgMoveTo)=="function"
        and type(nvgLineTo)=="function" and type(nvgClosePath)=="function"
        and type(nvgRGBA)=="function" and type(nvgFillColor)=="function" and type(nvgFill)=="function"
    mode=basic and 1 or 0
    if basic and type(nvgLinearGradient)=="function" and type(nvgFillPaint)=="function" then mode=2 end
    modes[vg]=mode
    if mode<2 then print("[DarkRitualMotion] 程序补层单次降级: "..(mode==0 and "基础绘图 API 不完整" or "使用无渐变铸纹")) end
    return mode
end
local function color(rgb,a)
    local value=nvgRGBA(rgb[1],rgb[2],rgb[3],math.floor(clamp(a)*255+.5))
    ---@cast value NVGcolor
    return value
end
local function fill(vg,rgb,a)
    nvgFillColor(vg,color(rgb,a))
    nvgFill(vg)
end
local function quad(vg,x0,y0,x1,y1,x2,y2,x3,y3,rgb,a)
    if a<=0 then return end
    nvgBeginPath(vg)
    nvgMoveTo(vg,x0,y0);nvgLineTo(vg,x1,y1);nvgLineTo(vg,x2,y2);nvgLineTo(vg,x3,y3)
    nvgClosePath(vg);fill(vg,rgb,a)
end
local function thread(vg,x0,y0,x1,y1,width,rgb,a)
    if a<=0 then return end
    local dx,dy=x1-x0,y1-y0
    local length=math.sqrt(dx*dx+dy*dy)
    if length<1e-6 then return end
    local nx,ny=-dy/length*width*.5,dx/length*width*.5
    quad(vg,x0+nx,y0+ny,x1+nx,y1+ny,x1-nx,y1-ny,x0-nx,y0-ny,rgb,a)
end
local function diamond(vg,x,y,rx,ry,rgb,a)
    quad(vg,x,y-ry,x+rx,y,x,y+ry,x-rx,y,rgb,a)
end
-- 细带用小段四边形组成；不需要 Arc/Stroke 扩展，空 API 能够干净停用。
local function arc(vg,x,y,rx,ry,from,to,width,rgb,a,segments)
    if a<=0 then return end
    for i=1,segments do
        local t0=from+(to-from)*(i-1)/segments
        local t1=from+(to-from)*i/segments
        local c0,s0,c1,s1=math.cos(t0),math.sin(t0),math.cos(t1),math.sin(t1)
        quad(vg,x+(rx+width*.5)*c0,y+(ry+width*.5)*s0,
            x+(rx+width*.5)*c1,y+(ry+width*.5)*s1,
            x+(rx-width*.5)*c1,y+(ry-width*.5)*s1,
            x+(rx-width*.5)*c0,y+(ry-width*.5)*s0,rgb,a)
    end
end
-- 有限局部聚光：边缘透明的窄锥，不用白色铺屏，也不画灰雾背景。
local function beam(vg,mode,x,y,half,height,rgb,a)
    if a<=0 then return end
    nvgBeginPath(vg)
    nvgMoveTo(vg,x-half,y);nvgLineTo(vg,x-half*.22,y-height)
    nvgLineTo(vg,x+half*.22,y-height);nvgLineTo(vg,x+half,y);nvgClosePath(vg)
    if mode==2 then
        local paint=nvgLinearGradient(vg,x,y,x,y-height,color(rgb,a),color(rgb,0))
        ---@cast paint NVGpaint
        nvgFillPaint(vg,paint);nvgFill(vg)
    else fill(vg,rgb,a*.40) end
end
local function ember(vg,x,y,life,fall,rgb,a,i)
    local wobble=math.sin(life*5+i*.93)*1.7
    local length=2.8+life*3.2
    thread(vg,x-wobble,y+length*.9,x,y-length*.8,1.1,rgb,a*.24)
    diamond(vg,x,y,1.15+i%3*.18,1.8+fall*1.3,rgb,a)
end

local function level(vg,mode,p,a,g,hit,hold,fall)
    local lift=stage(p,.24,.73)
    beam(vg,mode,0,78,36-12*g,193,COPPER,a*(.10*(1-g)+hold*.13))
    -- 阶梯式椭圆铸纹：三段升阶梯次点亮，不包住整张卡的头像/文字。
    for i=1,3 do
        local lit=stage(p,.05+i*.028,.23+i*.032)*(1-stage(p,.67+i*.035,.93))
        local y=80-(i-1)*18-lift*(i-1)*4
        local rx=60-(i-1)*12+hit*5
        arc(vg,0,y,rx,13,-math.pi+.17,-.17,1.05,COPPER,a*lit*.50,12)
        arc(vg,0,y,rx,13,.22,math.pi-.22,.70,BONE,a*lit*.30,12)
        diamond(vg,-rx,y,1.5,3.5,BONE,a*lit*.56)
        diamond(vg,rx,y,1.5,3.5,BONE,a*lit*.56)
    end
    for side=-1,1,2 do
        local x=side*(28-lift*8)
        thread(vg,x,66-lift*24,x+side*8,-49-lift*71,1.2,COPPER,a*hold*.38)
        for j=1,3 do
            local y=43-j*28-lift*24
            thread(vg,x-side*5,y+3,x+side*5,y-3,.8,BONE,a*hold*.43)
        end
    end
    local sweep=stage(p,.18,.43)
    local y=62-sweep*128
    thread(vg,-76,y+10,76,y-10,1.25,BONE,a*hit*.47)
    thread(vg,-67,y+12,66,y-6,4,COPPER,a*hit*.10)
    -- 只在封印附近有短冲击，不全屏亮闪。
    for side=-1,1,2 do thread(vg,side*33,66,side*(50+hit*21),54-hit*9,1.1,EMBER,a*hit*.67) end
    for i=1,10 do
        local q=clamp((p-.22-i*.018)/.72)
        local life=stage(q,0,.13)*(1-stage(q,.78,1))
        local side=i%2==0 and 1 or -1
        local x=side*(28+i*3+q*13)
        local y=63-q*(91+i*4)+fall*fall*(63+i*2)
        ember(vg,x,y,q,fall,i%3==0 and BONE or EMBER,a*life*.66,i)
    end
end
local function job(vg,mode,p,a,g,hit,hold,fall)
    local open=stage(p,.13,.57)
    beam(vg,mode,0,110,22+open*15,252,EMBER,a*hold*.11)
    -- 交错长菱门契，不复用升级圆环；侧边铸纹随开门向外张开。
    for side=-1,1,2 do
        local x=side*(48+open*25)
        thread(vg,x,111,x,-115,1.1,COPPER,a*hold*.58)
        thread(vg,side*7,-137,side*(73+hit*8),-43,1.1,COPPER,a*hold*.40)
        thread(vg,side*(73+hit*8),-43,side*7,105,1.1,COPPER,a*hold*.40)
        for i=1,5 do
            local y=-97+(i-1)*43
            local pulse=stage(p,.08+i*.021,.25+i*.025)*(1-stage(p,.73,.96))
            diamond(vg,x,y,3.2,5.2,BONE,a*pulse*.54)
            thread(vg,x-side*7,y+7,x,y+14,.85,COPPER,a*pulse*.40)
        end
        local sweep=-131+stage(p,.20,.56)*250
        thread(vg,x-side*3,sweep-17,x+side*3,sweep+17,1.2,BONE,a*hit*.69)
        thread(vg,side*37,-35,side*(63+hit*27),-66,1.1,EMBER,a*hit*.66)
    end
    for i=1,10 do
        local q=clamp((p-.22-i*.020)/.72)
        local life=stage(q,0,.12)*(1-stage(q,.80,1))
        local side=i%2==0 and 1 or -1
        local x=side*(38+q*(23+i*2))
        local y=-103+i*18-q*31+fall*fall*57
        ember(vg,x,y,q,fall,i%4==0 and BONE or COPPER,a*life*.69,i)
    end
end
local function revive(vg,mode,p,a,g,hit,hold,fall)
    local rise=stage(p,.43,.82)
    beam(vg,mode,0,80,27,188,SOUL,a*(1-g)*.14)
    -- 骨白尖拱 + 内聚魂针；上尖下窄、纵向不对称，不是橙焰换色。
    for side=-1,1,2 do
        local x=side*(55-g*15)
        thread(vg,side*6,-117-rise*17,x,-56-rise*12,1.0,SOUL,a*hold*.63)
        thread(vg,x,-56-rise*12,side*(48-g*8),41,1.0,SOUL,a*hold*.63)
        thread(vg,side*(48-g*8),41,side*9,79,1.0,SOUL,a*hold*.63)
        for i=1,4 do
            local y=39-i*32-rise*10
            diamond(vg,side*(45-g*12),y,1.5,4.1,BONE,a*hold*.47)
        end
        thread(vg,side*21,67,side*(42+hit*18),66-hit*13,1.0,BONE,a*hit*.48)
    end
    arc(vg,0,79,58+hit*8,14,.11,math.pi-.11,.8,SOUL,a*hold*.43,14)
    for i=1,10 do
        local q=clamp((p-.03-i*.017)/.52)
        local life=stage(q,0,.14)*(1-stage(q,.84,1))
        local side=i%2==0 and 1 or -1
        local x=side*((41+i*3)*(1-g)+math.sin(g*math.pi)*9)
        local y=(-91+i*18)*(1-g)+g*38-rise*20
        ember(vg,x,y,q,fall,SOUL,a*life*.70,i)
    end
    for i=1,6 do
        local q=clamp((p-.55-i*.016)/.42)
        local life=stage(q,0,.13)*(1-stage(q,.82,1))
        local side=i%2==0 and 1 or -1
        ember(vg,side*(21+i*3+q*10),-53+i*8+q*q*66,q,fall,BONE,a*life*.47,i)
    end
end
local function success(vg,mode,p,a,g,hit,hold,fall)
    beam(vg,mode,0,31,36,119,COPPER,a*hold*.12)
    local stamp=stage(p,.28,.52)
    -- 开口桂冠扇叶与顶部六角冠，主体圆印仍归 Spine；补层只沿外缘镶金。
    for side=-1,1,2 do
        local turn=side*stamp*.10
        arc(vg,0,1,83+hit*4,81+hit*4,side<0 and 1.74+turn or -.16+turn,
            side<0 and 4.54+turn or 1.42+turn,1.1,COPPER,a*hold*.50,17)
        for i=1,6 do
            local angle=side<0 and (2.06+i*.31) or (1.08-i*.31)
            local x,y=math.cos(angle)*86,math.sin(angle)*81
            local leaf=stage(p,.08+i*.027,.25+i*.031)
            thread(vg,x,y,x+side*(5+stamp*4),y-7,1.8,BONE,a*hold*leaf*.46)
        end
        thread(vg,side*6,-91,side*29,-78,1.1,BONE,a*stamp*.59)
        thread(vg,side*29,-78,side*43,-85,1.0,COPPER,a*stamp*.58)
        thread(vg,side*67,-24,side*(80+hit*15),-42,1.1,EMBER,a*hit*.71)
    end
    diamond(vg,0,-89,3.2,6.5,BONE,a*stamp*.68)
    local y=52-stage(p,.32,.55)*106
    thread(vg,-76,y+5,76,y-5,1.2,BONE,a*hit*.52)
    for i=1,10 do
        local q=clamp((p-.25-i*.018)/.73)
        local life=stage(q,0,.12)*(1-stage(q,.80,1))
        local angle=TAU*i/10-.31
        local radius=71+q*16
        local x=math.cos(angle)*radius
        local y=math.sin(angle)*70-q*16+fall*fall*33
        ember(vg,x,y,q,fall,i%3==0 and BONE or COPPER,a*life*.62,i)
    end
end
local function failure(vg,mode,p,a,g,hit,hold,fall)
    -- 断裂斜纹分离并下沉；没有成功桂冠、白色扫线或持续亮圆。
    local fracture=stage(p,.12,.37)
    for side=-1,1,2 do
        local x=side*(49+fracture*19)
        local y=-50+fall*fall*48
        thread(vg,x,y,x+side*16,y+34,1.3,SOUL,a*hold*.45)
        thread(vg,x+side*16,y+34,x+side*5,y+53,1.0,SOUL,a*hold*.40)
        thread(vg,side*13,-36,side*(45+hit*29),-58+hit*7,1.2,BLOOD,a*hit*.71)
        thread(vg,side*33,32+fall*20,side*67,42+fall*39,.9,SOUL,a*hold*.38)
    end
    for i=1,10 do
        local q=clamp((p-.15-i*.017)/.82)
        local life=stage(q,0,.10)*(1-stage(q,.82,1))
        local side=i%2==0 and 1 or -1
        local x=side*(29+i*3+q*21)
        local y=-59+i*9-q*17+q*q*65
        ember(vg,x,y,q,fall,i%4==0 and BLOOD or SOUL,a*life*.61,i)
    end
end
local function power(vg,mode,p,a,g,hit,hold,fall)
    -- 两侧各宽不到80；聚光 / 铸纹 / 薄扫线 / 粒子都不进入中央580文字通道。
    for side=-1,1,2 do
        local x=side*337
        beam(vg,mode,x,62,25,153,COPPER,a*(.09*(1-g)+hold*.13))
        local spread=stage(p,.12,.42)
        for i=1,4 do
            local y=-64+(i-1)*41
            local endX=side*(361+spread*11)
            thread(vg,side*307,y+10,endX,y-9,1.1,COPPER,a*hold*.58)
            thread(vg,endX,y-9,side*352,y+17,.9,BONE,a*hold*.34)
            diamond(vg,side*306,y+10,2.4,4,BONE,a*hold*.48)
        end
        -- 峰值是侧翼短放射，不能重新引入原 Spine sweep 被屏蔽的中央白线。
        thread(vg,side*324,-21,side*(353+hit*21),-52,1.2,EMBER,a*hit*.75)
        local y=74-stage(p,.20,.47)*142
        thread(vg,side*302,y+7,side*371,y-7,1.05,COPPER,a*hit*.59)
        diamond(vg,side*337,-84,2.4,6,BONE,a*hold*.51)
    end
    for i=1,12 do
        local q=clamp((p-.18-i*.014)/.80)
        local life=stage(q,0,.12)*(1-stage(q,.83,1))
        local side=i%2==0 and 1 or -1
        local x=side*(307+i*3+q*9)
        local y=46-q*(54+i*3)+fall*fall*(58+i*2)
        ember(vg,x,y,q,fall,i%4==0 and BONE or EMBER,a*life*.65,i)
    end
end

---@param vg NVGContextWrapper
---@param kind string
---@param cx number
---@param cy number
---@param width number
---@param height number
---@param elapsed number
---@param duration number
---@param alpha? number
---@return boolean
function M.draw(vg,kind,cx,cy,width,height,elapsed,duration,alpha)
    if not vg or not box(cx,cy,width,height) then return false end
    local p,a,g,hit,hold,fall=M.sample(kind,elapsed,duration,alpha)
    if a<=0 then return true end
    local mode=api(vg)
    if mode==0 then return false end
    -- Save/Restore 未成功时不尝试其它层，防止污染未知宿主状态栈。
    nvgSave(vg)
    local ok,err=pcall(function()
        local baseW=kind=="power" and 760 or 200
        local baseH=(kind=="level" or kind=="job" or kind=="revive") and 350 or (kind=="power" and 340 or 200)
        nvgTranslate(vg,cx,cy);nvgScale(vg,width/baseW,height/baseH)
        if kind=="level" then level(vg,mode,p,a,g,hit,hold,fall)
        elseif kind=="job" then job(vg,mode,p,a,g,hit,hold,fall)
        elseif kind=="revive" then revive(vg,mode,p,a,g,hit,hold,fall)
        elseif kind=="success" then success(vg,mode,p,a,g,hit,hold,fall)
        elseif kind=="failure" then failure(vg,mode,p,a,g,hit,hold,fall)
        else power(vg,mode,p,a,g,hit,hold,fall) end
    end)
    local restored,restoreError=pcall(nvgRestore,vg)
    if not restored then error(tostring(err).." [NanoVG restore failed: "..tostring(restoreError).."]",0) end
    if not ok then
        modes[vg]=0
        print("[DarkRitualMotion] 程序补层单次停用: "..tostring(err))
    end
    return ok
end
return M
