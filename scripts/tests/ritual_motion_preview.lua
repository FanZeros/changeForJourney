-- 独立暗黑动效验收页：基于 scaffold-2d 的 UI.Init → build → SetRoot 范式。
-- 三个受控时间样本在真实 native Spine 路径绘制；不载入游戏/存档/消费逻辑。
-- 使用原项目固定设计空间，标签全部为 UI.Label，矢量层只画自定义图形。
local UI = require("urhox-libs/UI")
local Sprites = require("ui.fx.DarkEffectSprites")
local SAMPLE = {.12, .40, .84}
local KINDS = {"level", "job", "revive", "success", "failure", "power"}
local TITLES = {"升阶 · 铜印升焰", "转职 · 双门铸纹", "复活 · 骨白回魂", "成功 · 桂冠定印", "失败 · 裂印灰落", "战力 · 两翼魂火"}
local DURATION = {level=1.3333, job=1.3333, revive=.9, success=1.6667, failure=1.3333, power=3.2}
local ROW_Y = {70, 360, 650, 935, 1155, 1365}
local ROW_H = {275, 275, 275, 205, 205, 235}
local tokens = {}
local loaded, renders = 0, 0
local originalCreate = nvgSpineCreate
local originalRender = nvgSpineRender
-- 仅本验收页的模块包装，生产全局未改写；实证不能拿 PNG 兜底充当 native 成功。
local nativeEnv = setmetatable({}, {__index=_G})
nativeEnv.nvgSpineCreate = function(vg)
    local instance = originalCreate(vg)
    assert(instance, "验收真实 Spine 创建失败")
    local proxy = {native=instance}
    for _,name in ipairs({"SetAnimation", "GetAnimationDuration", "Update", "UpdateWorldTransform", "SetPosition", "SetScale", "SetColor", "SetSpeed", "SetTimeScale", "SetPremultipliedAlpha", "FindSlot", "Unload", "Dispose"}) do
        local method = instance[name]
        if type(method)=="function" then proxy[name]=function(_,...) return method(instance,...) end end
    end
    function proxy:Load(path)
        local ok=instance:Load(path)
        assert(ok and instance:IsLoaded(), "验收真实 Spine 加载失败 "..path)
        loaded=loaded+1
        print("[ritual_motion_preview] actual native Load "..path)
        return ok
    end
    return proxy
end
nativeEnv.nvgSpineRender = function(vg, proxy)
    originalRender(vg,proxy.native)
    renders=renders+1
end
local function source(path)
    local file=assert(cache:GetFile(path))
    local lines={}
    while not file:IsEof() do lines[#lines+1]=file:ReadLine() end
    file:Dispose()
    return table.concat(lines,"\n")
end
Sprites = assert(load(source("ui/fx/DarkEffectSprites.lua"), "@ritual-preview-real/DarkEffectSprites.lua", "t", nativeEnv))()
local Canvas = UI.Widget:Extend("RitualMotionPreview")
function Canvas:Render(vg)
    for row,kind in ipairs(KINDS) do
        for col,p in ipairs(SAMPLE) do
            local cx=240+(col-1)*480
            local cy=ROW_Y[row]+ROW_H[row]*.5
            local token=tokens[row][col]
            if kind=="power" then
                Sprites.drawPower(vg,cx,cy,450,198,p*DURATION[kind],DURATION[kind],1,token)
            elseif kind=="success" or kind=="failure" then
                Sprites.drawResult(vg,kind=="success",cx,cy,176,p*DURATION[kind],DURATION[kind],1,token)
            else
                Sprites.drawCard(vg,kind,cx,cy,150,262.5,p*DURATION[kind],DURATION[kind],1,token)
            end
        end
    end
end
function Start()
    for row=1,#KINDS do tokens[row]={{},{},{}} end
    UI.Init({theme="default-dark",scale=UI.Scale.DESIGN_RESOLUTION(1440,1610)})
    local children={Canvas{width="100%",height="100%",position="absolute",pointerEvents="none"}}
    for col,p in ipairs(SAMPLE) do
        children[#children+1]=UI.Label{position="absolute",left=(col-1)*480,top=14,width=480,height=30,
            text=string.format("前奏 / 峰值 / 余烬  ·  p = %.2f",p),textAlign="center",fontSize=18,fontColor={216,201,163,255}}
    end
    for row,title in ipairs(TITLES) do
        children[#children+1]=UI.Label{position="absolute",left=18,top=ROW_Y[row]-22,width=1420,height=25,
            text=title,fontSize=16,fontColor={201,151,59,255}}
        if KINDS[row]=="power" then
            for col=1,3 do
                children[#children+1]=UI.Label{position="absolute",left=(col-1)*480+72,top=ROW_Y[row]+67,width=336,height=44,
                    text="总战力提升",textAlign="center",fontSize=19,fontColor={216,201,163,255}}
                children[#children+1]=UI.Label{position="absolute",left=(col-1)*480+72,top=ROW_Y[row]+108,width=336,height=44,
                    text="128,640   +8,240",textAlign="center",fontSize=22,fontColor={240,199,94,255}}
            end
        end
    end
    UI.SetRoot(UI.Panel{width="100%",height="100%",backgroundColor={13,11,9,255},children=children})
    print("[ritual_motion_preview] deterministic native samples p=.12/.40/.84; six themes; no player IO/RNG")
end
function Stop()
    print(string.format("[ritual_motion_preview] actualNativeLoads=%d actualNativeRenders=%d expectedLoads=18",loaded,renders))
    Sprites.destroy()
    UI.Shutdown()
end
