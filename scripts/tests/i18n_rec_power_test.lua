-- ============================================================================
-- i18n_rec_power_test.lua — 推荐战力五语键值验证（v2.61b）
--
-- 验证 I18n.t("rec_power"/"rec_power_approx", n) 在五语下：
--   1. {0} 占位符被正确替换为数字
--   2. 五种语言都返回非空、非原始 key 的译文
--   3. zh_CN（当前默认）返回简体中文原文
-- 运行: UrhoXRuntime tests/i18n_rec_power_test.lua -tapcode_dir=<root> -tool_mode -graphicsheadless
-- ============================================================================

local I18n = require("core.I18n")

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond then passed = passed + 1; print(string.format("[PASS] %s", name))
    else failed = failed + 1; print(string.format("[FAIL] %s %s", name, detail or "")) end
end

local LANGS = { "zh_CN", "zh_TW", "en", "ja", "ko" }
local N = 18110  -- 最长文本（ml46 外推上限），验占位替换 + 宽度

for _, lang in ipairs(LANGS) do
    local ok = I18n.set(lang)
    check(lang .. " set 成功", ok)
    local p = I18n.t("rec_power", N)
    local a = I18n.t("rec_power_approx", N)
    -- 占位符已替换（不再含 {0}），且含数字
    check(lang .. " rec_power 替换 {0}", type(p) == "string" and not p:find("{0}", 1, true) and p:find(tostring(N), 1, true),
        "got=" .. tostring(p))
    check(lang .. " rec_power_approx 替换 {0}", type(a) == "string" and not a:find("{0}", 1, true) and a:find(tostring(N), 1, true),
        "got=" .. tostring(a))
    -- 不是回退到 key 本身（说明五语表都有条目）
    check(lang .. " rec_power 非 key 回退", p ~= "rec_power", "got=" .. tostring(p))
    check(lang .. " rec_power_approx 非 key 回退", a ~= "rec_power_approx", "got=" .. tostring(a))
    print(string.format("    %s: rec_power=%q approx=%q", lang, p, a))
end

-- 恢复默认简体，验证 zh_CN 原文
I18n.set("zh_CN")
check("zh_CN rec_power = 推荐 N", I18n.t("rec_power", 318) == "推荐 318",
    "got=" .. tostring(I18n.t("rec_power", 318)))
check("zh_CN rec_power_approx = 推荐≈N", I18n.t("rec_power_approx", 1020) == "推荐≈1020",
    "got=" .. tostring(I18n.t("rec_power_approx", 1020)))
-- 未知 key 回退到 key 本身（I18n.t 既有行为）
check("未知 key 回退", I18n.t("no_such_key_xyz") == "no_such_key_xyz")

print(string.format("\n[i18n_rec_power_test] passed=%d failed=%d", passed, failed))
if failed == 0 then print("ALL PASS") end

engine:Exit()
