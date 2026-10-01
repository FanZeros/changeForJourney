-- 卡片 Spine 特效跨页面隔离回归测试（模拟 NanoVG/Spine 实例）。
local function eq(actual, expected, message)
    assert(actual == expected, message .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end

function Start()
    time = { elapsedTime = 10 }
    local created, rendered, unloaded = {}, {}, {}
    nvgSpineCreate = function()
        local inst = {}
        function inst:Load() return true end
        function inst:SetPremultipliedAlpha() end
        function inst:SetSpeed() end
        function inst:SetAnimation(_, name) self.name = name end
        function inst:SetCompleteListener(listener) self.complete = listener end
        function inst:Update() end
        function inst:SetScale() end
        function inst:SetPosition() end
        function inst:Unload() unloaded[#unloaded + 1] = self.name end
        created[#created + 1] = inst
        return inst
    end
    nvgSpineRender = function(_, inst)
        rendered[#rendered + 1] = inst.name
    end

    local effect = require("ui.fx.SpineCardEffect")
    local done = 0
    effect.playLevelUp(100, 200)
    effect.playJobChange(300, 400, function() done = done + 1 end)
    effect.playRevive(500, 600)
    effect.playRevive(700, 800, nil, "dungeon")
    effect.draw({}, "church")
    eq(#rendered, 1, "礼拜堂只绘制转职")
    eq(rendered[1], "2", "礼拜堂动画编号")
    eq(#created, 1, "不能加载其他页面的动画")
    effect.draw({}, "battle")
    eq(#rendered, 3, "主线战斗绘制升级及复活")
    eq(rendered[2], "3", "主线复活动画编号")
    eq(rendered[3], "1", "升级动画编号")
    effect.draw({}, "dungeon")
    eq(rendered[4], "3", "副本只绘制副本复活")
    eq(#created, 4, "四个实例各加载一次")

    created[1].complete()
    effect.draw({}, "battle")
    eq(done, 0, "战斗页不能消费礼拜堂完成回调")
    effect.draw({}, "church")
    eq(done, 1, "转职完成回调只在礼拜堂执行")
    eq(unloaded[1], "2", "转职结束释放资源")

    time.elapsedTime = 13
    effect.draw({}, "church")
    eq(#unloaded, 4, "离开页面后旧动画被释放")
    eq(effect.isPlaying(), false, "过期实例被移出队列")
    local count = #rendered
    effect.draw({}, "battle")
    effect.draw({}, "dungeon")
    eq(#rendered, count, "重新进入战斗或副本不会补播旧特效")
    print("[SpineCardEffectTest] PASS: battle/church/dungeon scopes, callback, expiry")
end
