-- 装备图标组首图 fallback 回归测试
-- 背景：318 个装备模板 ID 共用 53 张组首图标（每 6 个 ID 一组：W1~W6→W1）。
-- 铁匠铺旧实现 getEquipIconCached 无 fallback，W2~W6 等非组首 ID 加载失败 → 分解/升阶页图标空白。
-- 修复后委托 ImageCache.getEquipIcon（含 fallback）。本测试用文件系统探针 mock nvgCreateImage，
-- 复现"文件不存在则返回 -1"的真实加载语义，断言全部 ID 都能解析到正 handle。

local ImageCache = require("ui.widget.ImageCache")
local EquipmentConfig = require("config.EquipmentConfig")

local pass, fail = 0, 0
local function check(cond, label)
    if cond then
        pass = pass + 1
        print("[icon_fallback] [PASS] " .. label)
    else
        fail = fail + 1
        print("[icon_fallback] [FAIL] " .. label)
    end
end

function Start()
    -- 探针式 mock：纹理文件存在 → 返回正 handle；不存在 → 返回 -1（复现原 bug 的加载失败条件）
    local nextHandle = 1000
    local createdPaths = {}
    nvgCreateImage = function(_vg, path, _flags)
        createdPaths[path] = (createdPaths[path] or 0) + 1
        local tex = cache:GetResource("Texture2D", path)
        if tex then
            nextHandle = nextHandle + 1
            return nextHandle
        end
        return -1
    end

    ImageCache.init({})  -- 假 vg 上下文（mock 不依赖真实 vg）

    -- 收集配置里全部 templateId
    local ids = {}
    for id in pairs(EquipmentConfig.ITEMS) do ids[#ids + 1] = id end
    table.sort(ids)
    check(#ids >= 300, "配置模板 ID 数量充足 (实际=" .. #ids .. ")")

    -- 断言 1：每个 ID 经 ImageCache.getEquipIcon 都返回正 handle（fallback 全覆盖）
    local ok, bad = 0, {}
    for _, id in ipairs(ids) do
        local h = ImageCache.getEquipIcon(id)
        if h and h > 0 then ok = ok + 1 else bad[#bad + 1] = id end
    end
    check(ok == #ids, "全部 " .. #ids .. " 个 ID 经 fallback 返回有效图标 (成功=" .. ok .. " 失败=" .. #bad
        .. (bad[1] and (" 首例=" .. bad[1]) or "") .. ")")

    -- 断言 2：非组首 ID（如 W2）确实走了 fallback，最终命中的是组首图 W1 的 path
    local w2 = ImageCache.getEquipIcon("W2")
    check(w2 and w2 > 0, "W2（非组首）返回有效 handle=" .. tostring(w2))
    check(createdPaths["image/装备图标/UI_icon_ZB_W1.png"] ~= nil,
        "W2 的加载尝试触达了组首图 W1（fallback 生效）")

    -- 断言 3：组首 ID 本身直接命中（无需 fallback）
    local w7 = ImageCache.getEquipIcon("W7")
    check(w7 and w7 > 0, "W7（组首）返回有效 handle=" .. tostring(w7))

    -- 断言 4：缓存幂等——同 ID 第二次取不重复创建纹理
    local before = createdPaths["image/装备图标/UI_icon_ZB_W1.png"] or 0
    ImageCache.getEquipIcon("W2")
    local after = createdPaths["image/装备图标/UI_icon_ZB_W1.png"] or 0
    check(before == after, "重复获取 W2 命中缓存，不再重复加载 W1 (前=" .. before .. " 后=" .. after .. ")")

    print("[icon_fallback] RESULT " .. (fail == 0 and ("ALL PASS (" .. pass .. ")") or (pass .. " PASS / " .. fail .. " FAIL")))
    if engine and engine.Exit then engine:Exit() end
end
