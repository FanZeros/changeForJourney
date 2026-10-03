-- SamsaraSliceConfig.lua — N02 无奖文字切片；不注册旧情景编号或经济奖励。
-- 正文来源：未寄出的撤离令-剧情正文普通至炼狱-1003.md 的 N02 / E01。
-- 已核对 HeroConfig.HEROES：1=大狗嚼，2=黄桃龙，3=叮咚鸡。

---@class SamsaraSliceStep
---@field characterId number?
---@field name string
---@field text string

---@class SamsaraSliceEvidence
---@field id string
---@field title string
---@field text string

---@class SamsaraSliceDefinition
---@field title string
---@field mode string
---@field steps SamsaraSliceStep[]
---@field evidence SamsaraSliceEvidence

local Config = {
    NODE_KEY = "samsara.log_leaf",
    CONTENT_VERSION = 1,
}

--- 每次返回独立配置，展示方的临时修改不会污染下次首次阅读或回看。
---@param key string
---@return SamsaraSliceDefinition?
function Config.get(key)
    if key ~= Config.NODE_KEY then return nil end
    return {
        title = "夹在日志里的回程页",
        mode = "small",
        steps = {
            { name = "旁白", text = "日志靠近后缝的一页纸卷了角。纸上有一道细灰印，纸边露出被划掉的“回”字。" },
            { characterId = 1, name = "大狗嚼", text = "叫！说了是我们的。闻得出来。" },
            { characterId = 2, name = "黄桃龙", text = "有没有记我上次把火把弄丢的事？那页可以不找……" },
            { characterId = 3, name = "叮咚鸡", text = "页数齐全。夹页，多一张。" },
            { name = "远征长", text = "这字像我写的。" },
            { characterId = 3, name = "叮咚鸡", text = "叮咚。先记“像”。这页是谁写的，另查。" },
            { characterId = 1, name = "大狗嚼", text = "那先带着。自己家的东西，别又丢了。" },
        },
        evidence = {
            id = "E01",
            title = "日志夹页",
            text = "出征：三人。\n归还：待填。\n干粮留一份在林道路标下。\n若铃声第三下迟了，不要换收件人。\n回……〔被划去〕\n先救人，回来再结。\n〔签名末笔重落两次，登记页号缺损〕",
        },
    }
end

return Config
