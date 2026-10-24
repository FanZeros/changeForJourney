-- 通天塔选择卡暗契装饰：每张卡使用独立table token，关闭/重抽时release，Stop时destroy在vg销毁前。
-- 仅按真实elapsed采样，不订阅事件、不加载玩家存档、不消费随机数。尺寸坐标由宿主给出，沿宿主NVG变换。
-- 不创建NVG上下文/BeginFrame，不乘DPR，不改globalAlpha/scissor，PNG和native各自Save/Restore。
-- API: preload(vg), draw(vg,cx,cy,size,elapsed,token,quality?), release(token), destroy(), drawIcon(...).
-- quality可为1..6稀有度（只调克制透明度），或"png"强制PNG用于验证/低画质；缺省正常native优先。
local M={}
local ROOT="image/通天塔暗契/"
local THEMES={blade=true,tome=true,blood=true,eye=true,shield=true,chain=true,bell=true}
local REGIONS={"blade","tome","blood","eye","shield","chain","bell","seal_ring","rift","ember"}
local BRONZE,BONE,IRON,BLOOD={162,116,66},{226,212,180},{23,23,26},{148,38,33}
---@class TowerOathContext
---@field vg NVGContextWrapper
---@field images table<string, integer>
---@field badImages table<string, boolean>
---@field prepared boolean
---@field broken boolean
---@class TowerOathPlayback
---@field vg NVGContextWrapper
---@field attempted boolean
---@field failed boolean
---@field pngFailed boolean
---@field vectorFailed boolean
---@field released boolean
---@field idle boolean
---@field posed boolean
---@field instance SpineInstance|nil
---@field lastElapsed number
---@field lastFallback number
---@field lastCx number?
---@field lastCy number?
---@field lastSize number?
---@type table<any, TowerOathContext>
local contexts={}
---@type table<table, TowerOathPlayback>
local playbacks={}
---@type table<table, boolean>
local retired=setmetatable({},{__mode="k"})
local destroying=false
local function finite(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end
local function clamp(value) return math.max(0,math.min(1,value)) end
local function validBox(cx,cy,size)
    return finite(cx) and finite(cy) and finite(size) and math.abs(cx)<=1e6 and math.abs(cy)<=1e6 and size>=.0001 and size<=1e6
end
local function hasMethod(object,name)
    local ok,value=pcall(function() return object[name] end)
    return ok and type(value)=="function"
end
---@param entry TowerOathPlayback
local function unload(entry)
    local instance=entry.instance; entry.instance=nil
    if not instance then return end
    -- 官方UI.Spine一致：单Unload→清引用；不串Dispose，不把C++崩溃当pcall可捕获。
    if hasMethod(instance,"Unload") then
        local ok,err=pcall(function() instance:Unload() end)
        if not ok then print("[TowerOathEffect] Unload失败："..tostring(err)) end
    end
end
---@param token? table
function M.release(token)
    if type(token)~="table" then return end
    retired[token]=true
    local entry=playbacks[token]; playbacks[token]=nil
    if not entry or entry.released then return end
    entry.released=true; unload(entry)
end
---@param vg NVGContextWrapper
---@param painter fun()
local function isolated(vg,painter)
    local saved,saveError=pcall(nvgSave,vg)
    if not saved then return false,saveError,false end
    local ok,err=pcall(painter)
    local restored,restoreError=pcall(nvgRestore,vg)
    if not restored then return false,tostring(err).." [Restore失败："..tostring(restoreError).."]",false end
    return ok,err,true
end
---@param vg NVGContextWrapper
---@return TowerOathContext
local function contextFor(vg)
    local old=contexts[vg]; if old then return old end
    local entry={vg=vg,images={},badImages={},prepared=false,broken=false}
    contexts[vg]=entry; return entry
end
local function imageAPI()
    return type(nvgCreateImage)=="function" and type(nvgDeleteImage)=="function"
        and type(nvgBeginPath)=="function" and type(nvgMoveTo)=="function" and type(nvgLineTo)=="function"
        and type(nvgClosePath)=="function" and type(nvgFillPaint)=="function" and type(nvgFill)=="function"
        and ((type(nvgImagePatternTinted)=="function" and type(nvgRGBA)=="function") or type(nvgImagePattern)=="function")
end
---@param vg? NVGContextWrapper
function M.preload(vg)
    if not vg or destroying then return end
    local context=contextFor(vg)
    if context.prepared then return end
    context.prepared=true
    if not imageAPI() then context.broken=true; print("[TowerOathEffect] 图片API不足，使用几何兜底"); return end
    local loaded=0
    for _,name in ipairs(REGIONS) do
        context.images[name]=0
        local ok,image=pcall(function() return nvgCreateImage(vg,ROOT..name..".png",0) end)
        if ok and finite(image) and image>0 and image==math.floor(image) then
            context.images[name]=math.floor(image); loaded=loaded+1
        else print("[TowerOathEffect] 图片失败已锁存："..name) end
    end
    print("[TowerOathEffect] PNG预热 "..loaded.."/10")
end
---@param vg NVGContextWrapper
---@param token table
---@return TowerOathPlayback|nil
local function playbackFor(vg,token)
    local old=playbacks[token]
    if old then
        if old.vg~=vg then M.release(token); return nil end -- context更换必须新token，禁止跨context移交native。
        return old
    end
    local entry={vg=vg,attempted=false,failed=false,pngFailed=false,vectorFailed=false,released=false,
        idle=false,posed=false,instance=nil,lastElapsed=0,lastFallback=0}
    playbacks[token]=entry; return entry
end
---@param entry TowerOathPlayback
local function attemptNative(entry)
    if entry.attempted or entry.released then return end
    entry.attempted=true
    if type(nvgSpineCreate)~="function" or type(nvgSpineRender)~="function" then entry.failed=true; return end
    local ok,err=pcall(function()
        local instance=nvgSpineCreate(entry.vg)
        if not instance then error("Spine创建失败",0) end
        entry.instance=instance
        for _,name in ipairs({"Load","SetAnimation","Update","SetScale","SetPosition","SetColor","Unload"}) do
            if not hasMethod(instance,name) then error("Spine缺API："..name,0) end
        end
        if instance:Load(ROOT.."tower_oath.json")~=true then error("Spine Load失败",0) end
        if entry.released then return end
        if instance:SetAnimation(0,"awaken",false)~=true then error("awaken失败",0) end
        if entry.released then return end
        if hasMethod(instance,"SetDefaultMix") then instance:SetDefaultMix(0) end
        if hasMethod(instance,"SetMix") then instance:SetMix("awaken","idle",0) end
        if hasMethod(instance,"SetSpeed") then instance:SetSpeed(1) end
        if hasMethod(instance,"SetTimeScale") then instance:SetTimeScale(1) end
        if hasMethod(instance,"SetPremultipliedAlpha") then instance:SetPremultipliedAlpha(false) end
    end)
    if not ok then
        entry.failed=true; unload(entry)
        print("[TowerOathEffect] native单次降级："..tostring(err))
    end
end
local function qualityAlpha(quality)
    if finite(quality) then return .65+clamp((quality-1)/5)*.25 end
    return .85
end
---@param vg NVGContextWrapper
---@param entry TowerOathPlayback
local function drawNative(vg,entry,cx,cy,size,elapsed,alpha)
    attemptNative(entry)
    local instance=entry.instance
    if entry.released or entry.failed or not instance then return false end
    local ok,err,restored=isolated(vg,function()
        local changed=entry.lastCx~=cx or entry.lastCy~=cy or entry.lastSize~=size
        local sampled=math.max(elapsed,entry.lastElapsed,entry.lastFallback) -- 同token旧快照不可回退原生时间。
        local function setTransform()
            instance:SetScale(size/240,-size/240)
            instance:SetPosition(cx,cy)
            instance:SetColor(1,1,1,alpha)
        end
        local function advance(dt)
            setTransform() -- 每次Update前先变换，不依赖前帧尺寸。
            instance:Update(dt); entry.posed=true
        end
        local advanced=false
        if not entry.idle then
            local awakeTime=math.min(sampled,.8)
            local delta=math.max(0,awakeTime-entry.lastElapsed)
            if delta>0 then advance(delta); advanced=true end
            if entry.released then return end
            if sampled>=.8 then
                -- 大dt/首帧已晚于.8：先采样awaken末态，再且只一次切idle并采样真实余时。
                entry.idle=true
                if instance:SetAnimation(0,"idle",true)~=true then error("idle切换失败",0) end
                if entry.released then return end
                advance(sampled-.8); advanced=true
            end
        else
            local delta=math.max(0,sampled-entry.lastElapsed)
            if delta>0 then advance(delta); advanced=true end
        end
        if entry.released then return end
        entry.lastElapsed=sampled
        if not advanced then
            setTransform()
            if not entry.posed then advance(0)
            elseif changed then
                if hasMethod(instance,"UpdateWorldTransform") then instance:UpdateWorldTransform()
                else advance(0) end
            end
        end
        if entry.released then return end
        entry.lastCx,entry.lastCy,entry.lastSize=cx,cy,size
        nvgSpineRender(vg,instance)
    end)
    if ok then return not entry.released end
    entry.failed=true; unload(entry)
    if not restored then error(err,0) end
    print("[TowerOathEffect] native绘制单次降级："..tostring(err))
    return false
end
---@param vg NVGContextWrapper
---@param context TowerOathContext
local function sprite(vg,context,name,cx,cy,w,h,angle,alpha)
    if alpha<=0 then return end
    local image=context.images[name] or 0
    if image<=0 or context.badImages[name] then error("缺PNG："..name,0) end
    local c,s=math.cos(angle),math.sin(angle); local hw,hh=w*.5,h*.5
    nvgBeginPath(vg)
    nvgMoveTo(vg,cx-hw*c+hh*s,cy-hw*s-hh*c)
    nvgLineTo(vg,cx+hw*c+hh*s,cy+hw*s-hh*c)
    nvgLineTo(vg,cx+hw*c-hh*s,cy+hw*s+hh*c)
    nvgLineTo(vg,cx-hw*c-hh*s,cy-hw*s+hh*c); nvgClosePath(vg)
    local ox,oy=cx-hw*c+hh*s,cy-hw*s-hh*c
    if type(nvgImagePatternTinted)=="function" and type(nvgRGBA)=="function" then
        local color=nvgRGBA(255,255,255,math.floor(clamp(alpha)*255+.5))
        ---@cast color NVGcolor
        local paint=nvgImagePatternTinted(vg,ox,oy,w,h,angle,image,color)
        ---@cast paint NVGpaint
        nvgFillPaint(vg,paint)
    else
        local paint=nvgImagePattern(vg,ox,oy,w,h,angle,image,clamp(alpha))
        ---@cast paint NVGpaint
        nvgFillPaint(vg,paint)
    end
    nvgFill(vg)
end
local function vectorAPI()
    return type(nvgSave)=="function" and type(nvgRestore)=="function" and type(nvgTranslate)=="function"
        and type(nvgScale)=="function" and type(nvgBeginPath)=="function" and type(nvgMoveTo)=="function"
        and type(nvgLineTo)=="function" and type(nvgClosePath)=="function" and type(nvgFillColor)=="function"
        and type(nvgFill)=="function" and type(nvgRGBA)=="function"
end
local function polygon(vg,points,color,alpha)
    nvgBeginPath(vg); nvgMoveTo(vg,points[1][1],points[1][2])
    for i=2,#points do nvgLineTo(vg,points[i][1],points[i][2]) end
    nvgClosePath(vg)
    local rgba=nvgRGBA(color[1],color[2],color[3],math.floor(clamp(alpha)*255+.5))
    ---@cast rgba NVGcolor
    nvgFillColor(vg,rgba); nvgFill(vg)
end
local function ringGeometry(vg,cx,cy,r,width,alpha)
    for i=0,63 do
        local a,b=i*math.pi/32,(i+1)*math.pi/32
        polygon(vg,{{cx+math.cos(a)*r,cy+math.sin(a)*r},{cx+math.cos(b)*r,cy+math.sin(b)*r},
            {cx+math.cos(b)*(r-width),cy+math.sin(b)*(r-width)},{cx+math.cos(a)*(r-width),cy+math.sin(a)*(r-width)}},BRONZE,alpha)
    end
end
local function drawFallback(vg,context,cx,cy,size,elapsed,alpha,entry)
    local sampled=entry and math.max(elapsed,entry.lastElapsed,entry.lastFallback) or elapsed
    local intro=clamp(sampled/.27); local t=math.max(0,sampled-.8)%3
    if entry then entry.lastFallback=sampled end
    if not context.broken and not (entry and entry.pngFailed) and (context.images.seal_ring or 0)>0 and (context.images.ember or 0)>0 then
        local ok,err,restored=isolated(vg,function()
            local s=size/240
            local ring=164*(.68+.32*intro)*s
            sprite(vg,context,"seal_ring",cx,cy,ring,ring,(sampled<.8 and (-24+24*clamp(sampled/.8)) or t*120)*math.pi/180,alpha*intro*.82)
            for side=1,2 do for i=1,4 do
                local sign=side==1 and -1 or 1
                local pulse=.5+.5*math.sin(t*math.pi*2/3+i*.6)
                sprite(vg,context,"ember",cx+sign*(80+i%3*7)*s,cy+(-55+i*23-pulse*12)*s,
                    (5+i%2)*s,(11+i%3)*s,sign*.12,alpha*intro*(.28+pulse*.22))
            end end
        end)
        if ok then return "png" end
        if entry then entry.pngFailed=true else context.broken=true end
        if not restored then error(err,0) end
        print("[TowerOathEffect] PNG单次降级："..tostring(err))
    end
    if (entry and entry.vectorFailed) or not vectorAPI() then return "none" end
    local ok,err,restored=isolated(vg,function()
        local s=size/240
        ringGeometry(vg,cx,cy,72*s,2*s,alpha*intro*.65)
        for side=1,2 do for i=1,3 do
            local sign=side==1 and -1 or 1; local x=cx+sign*(80+i*4)*s; local y=cy+(-50+i*25)*s
            polygon(vg,{{x-1*s,y},{x,y-4*s},{x+1*s,y},{x,y+2*s}},BLOOD,alpha*intro*.45)
        end end
    end)
    if ok then return "vector" end
    if entry then entry.vectorFailed=true else context.broken=true end
    if not restored then error(err,0) end
    print("[TowerOathEffect] 几何装饰停用："..tostring(err)); return "none"
end
---@param vg NVGContextWrapper
---@param cx number
---@param cy number
---@param size number
---@param elapsed number
---@param token? table
---@param quality? number|string
---@return string backend native|png|vector|released|none
function M.draw(vg,cx,cy,size,elapsed,token,quality)
    if destroying or (type(token)=="table" and retired[token]) then return "released" end
    if not vg or not validBox(cx,cy,size) or not finite(elapsed) or elapsed<0 then return "none" end
    local entry=type(token)=="table" and playbackFor(vg,token) or nil
    if type(token)=="table" and (not entry or entry.released) then return "released" end
    local alpha=qualityAlpha(quality)
    if entry and quality~="png" and drawNative(vg,entry,cx,cy,size,elapsed,alpha) then return "native" end
    if entry and entry.released then return "released" end
    M.preload(vg)
    return drawFallback(vg,contextFor(vg),cx,cy,size,elapsed,alpha,entry)
end
-- 简化但对应七主题的几何兜底。只在PNG失败时绘制，不用文字/箭头替所有主题。
local function iconGeometry(vg,theme,alpha)
    if theme=="blade" then
        polygon(vg,{{-10,25},{-3,-32},{4,-40},{11,-31},{4,26}},BONE,alpha)
        polygon(vg,{{-22,20},{20,20},{22,27},{-22,27}},BRONZE,alpha)
        polygon(vg,{{-4,27},{4,27},{4,42},{-4,42}},IRON,alpha)
    elseif theme=="tome" then
        polygon(vg,{{-32,-35},{27,-40},{34,-32},{34,35},{-25,41},{-32,34}},BRONZE,alpha)
        polygon(vg,{{-24,-28},{24,-33},{24,28},{-24,34}},IRON,alpha)
        polygon(vg,{{0,-23},{12,-4},{7,18},{-7,18},{-12,-4}},BLOOD,alpha)
    elseif theme=="blood" then
        polygon(vg,{{-31,-28},{14,-28},{10,4},{-3,18},{-3,32},{18,40},{-33,40},{-12,32},{-12,18},{-27,4}},BRONZE,alpha)
        polygon(vg,{{-28,-23},{11,-23},{8,-17},{-25,-17}},BLOOD,alpha)
        polygon(vg,{{23,-35},{31,-42},{36,-29},{31,20},{25,20}},BONE,alpha)
    elseif theme=="eye" then
        polygon(vg,{{-34,-26},{-18,-40},{19,-40},{34,-26},{32,20},{0,42},{-32,20}},IRON,alpha)
        polygon(vg,{{-30,-5},{0,-23},{30,-5},{0,13}},BONE,alpha)
        polygon(vg,{{0,-18},{9,-5},{0,9},{-9,-5}},BLOOD,alpha)
        polygon(vg,{{-2,-13},{2,-13},{2,4},{-2,4}},IRON,alpha)
    elseif theme=="shield" then
        polygon(vg,{{-34,-32},{0,-42},{34,-32},{34,10},{25,25},{0,42},{-25,25},{-34,10}},BRONZE,alpha)
        polygon(vg,{{-25,-25},{0,-32},{25,-25},{24,12},{0,31},{-24,12}},IRON,alpha)
        polygon(vg,{{-29,-5},{29,-5},{29,5},{-29,5}},BONE,alpha*.7)
    elseif theme=="chain" then
        ringGeometry(vg,-22,-25,16,5,alpha); ringGeometry(vg,22,-25,16,5,alpha)
        polygon(vg,{{-25,-1},{25,-1},{31,12},{26,36},{0,42},{-26,36},{-31,12}},BRONZE,alpha)
        polygon(vg,{{-7,13},{7,13},{10,29},{-10,29}},IRON,alpha)
    else
        ringGeometry(vg,0,-28,13,4,alpha)
        polygon(vg,{{-34,27},{-27,16},{-20,-8},{-12,-15},{12,-15},{20,-8},{27,16},{34,27},{31,34},{-31,34}},BRONZE,alpha)
        polygon(vg,{{-5,34},{5,34},{4,42},{-4,42}},BONE,alpha)
    end
end
---@param vg NVGContextWrapper
---@param theme string
---@param cx number
---@param cy number
---@param size number
---@param alpha? number
---@return string backend png|vector|none
function M.drawIcon(vg,theme,cx,cy,size,alpha)
    local opacity=alpha==nil and 1 or alpha
    if destroying or not vg or not THEMES[theme] or not validBox(cx,cy,size) or not finite(opacity) or opacity<=0 then return "none" end
    opacity=clamp(opacity); M.preload(vg); local context=contextFor(vg)
    if not context.broken and not context.badImages[theme] and (context.images[theme] or 0)>0 then
        local ok,err,restored=isolated(vg,function() sprite(vg,context,theme,cx,cy,size,size,0,opacity) end)
        if ok then return "png" end
        context.badImages[theme]=true
        if not restored then error(err,0) end
        print("[TowerOathEffect] 纹章PNG失败已锁存："..theme)
    end
    if context.badImages["geometry:"..theme] or not vectorAPI() then return "none" end
    local ok,err,restored=isolated(vg,function()
        nvgTranslate(vg,cx,cy); nvgScale(vg,size/100,size/100); iconGeometry(vg,theme,opacity)
    end)
    if ok then return "vector" end
    context.badImages["geometry:"..theme]=true
    if not restored then error(err,0) end
    print("[TowerOathEffect] 纹章几何停用："..theme); return "none"
end
function M.destroy()
    if destroying then return end
    destroying=true
    local oldPlaybacks,oldContexts=playbacks,contexts; playbacks,contexts={},{}
    for token,entry in pairs(oldPlaybacks) do retired[token]=true; entry.released=true; unload(entry) end
    for _,context in pairs(oldContexts) do
        context.broken=true; local images=context.images; context.images={}
        local deleted={} ---@type table<number, boolean>
        for _,image in pairs(images) do
            if image>0 and not deleted[image] then
                deleted[image]=true
                local ok,err=pcall(nvgDeleteImage,context.vg,image)
                if not ok then print("[TowerOathEffect] PNG释放失败："..tostring(err)) end
            end
        end
    end
    destroying=false
end
return M
