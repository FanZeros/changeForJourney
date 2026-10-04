-- SamsaraSliceConfig.lua — N02/N03、N12–N14与N07/N09无奖切片；不注册旧情景编号或经济奖励。
-- 正文来源：未寄出的撤离令-剧情正文普通至炼狱-1003.md；N14采用接线方案独立语境。
-- N07/N09仅提供E03-A/C初片，后续批注未开放，不补造E03-B。
-- 已核对人物映射：1=大狗嚼，2=黄桃龙，3=叮咚鸡，10=铁匠，21=圣女。

---@class SamsaraSliceStep
---@field characterId number?
---@field name string
---@field text string

---@class SamsaraSliceEvidence
---@field id string
---@field title string
---@field text string
---@field annotation string?
---@field continuation string?
---@field people string?

---@class SamsaraSliceDefinition
---@field title string
---@field mode string
---@field steps SamsaraSliceStep[]
---@field evidence SamsaraSliceEvidence
---@field requiredStage number?
---@field dependency string?
---@field unlockText string?

local Config = {
    NODE_KEY = "samsara.log_leaf",
    CARGO_KEY = "samsara.cargo_match",
    ORDER_KEY = "samsara.gray_order",
    PEOPLE_KEY = "samsara.people_record",
    MANIFEST_KEY = "samsara.returned_manifest",
    DOG_MIRROR_KEY = "samsara.dog_mirror",
    BELL_MIRROR_KEY = "samsara.bell_mirror",
    CONTENT_VERSION = 1,
}
-- 旧五项顺序不变；镜像两项追加，不建立N08或其他处理前置。
Config.KEYS = { Config.NODE_KEY, Config.CARGO_KEY, Config.ORDER_KEY, Config.PEOPLE_KEY, Config.MANIFEST_KEY,
    Config.DOG_MIRROR_KEY, Config.BELL_MIRROR_KEY }

local E02_TEXT = "商队药箱十二。\n内装药、夹板、干粮。箱底补铆一次。\n押运：城镇医所支队。\n遇截地点：林道路标外。\n截取方口令：“先救人。”\n回收：货牌。箱体未回。\n\n铁匠手注：\n图中歪铆是箱底修补位置，不是货牌铆钉。货能认，人别再认错。"
local E02_ANNOTATION = "货牌位置与保全库十二号箱底拓片吻合。同物件跨两次交接有完整编号，未发现复制箱体。受害押运者另记人员卷，不并入“物资损失”。"
local E05_TEXT = "急救物资征用令。\n调取：商队药箱十二。\n送达：城镇登记接驳处。\n目的：保全三名受援人。\n签发：第三十七任远征长〔旧登记页〕。\n手令：“先救人，回来再结。”"
local E05_CONTINUATION = "先期物资不足。允许拦截护送支队，缴械接驳。\n遇阻待签发方答复。\n〔“停止拦截”栏：空白〕"
local E05_PEOPLE = "物资卷与人员卷分列。\n旧远征护送支队失踪：有登记名单。\n找回胸牌、外衣标识及两封未送达的家书。\n幸存者证言已保存；遗物不得换算成可交付的救援配额。"
local E03_A_TEXT = "请先护送远征长离开。\n若他还没到，就让我守在接驳处。\n到了，请告诉我下一次该守谁。\n申请人：大狗嚼〔旧登记页〕。\n答复：任务续征。撤离未结。"
local E03_C_TEXT = "出征通知：已发。\n死亡通知：已发。\n请求结束通知。\n撤离收件人：〔空白〕。\n答复：收到。下一任务续征。"

--- 静态原件返回副本；没有首次处理标记时展示方不得公开后续核验/续令。
---@param id string
---@return SamsaraSliceEvidence?
function Config.getEvidence(id)
    if id == "E02" then
        return { id = id, title = "退回货单", text = E02_TEXT, annotation = E02_ANNOTATION }
    elseif id == "E05" then
        return { id = id, title = "灰印征用令与人员卷", text = E05_TEXT,
            continuation = E05_CONTINUATION, people = E05_PEOPLE }
    elseif id == "E03-A" then
        return { id = id, title = "大狗嚼的申请", text = E03_A_TEXT }
    elseif id == "E03-C" then
        return { id = id, title = "叮咚鸡的申请", text = E03_C_TEXT }
    end
    return nil
end

--- 每次返回独立配置，展示方的临时修改不会污染首次阅读或回看。
---@param key string
---@param source string? N12原件来源：player_record / case_archive
---@return SamsaraSliceDefinition?
function Config.get(key, source)
    if key == Config.NODE_KEY then
        return {
            title = "夹在日志里的回程页", mode = "small", requiredStage = 104,
            unlockText = "通关普通1-4后开放",
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
                id = "E01", title = "日志夹页",
                text = "出征：三人。\n归还：待填。\n干粮留一份在林道路标下。\n若铃声第三下迟了，不要换收件人。\n回……〔被划去〕\n先救人，回来再结。\n〔签名末笔重落两次，登记页号缺损〕",
            },
        }
    elseif key == Config.CARGO_KEY then
        local cargo = source == "player_record" and "你带来的货牌" or "铁匠保存的货牌副本"
        return {
            title = "货牌找到了箱子", mode = "small", requiredStage = 4905,
            unlockText = "通关噩梦3-5后开放",
            steps = {
                { name = "旁白", text = "铁匠请核对一张旧货牌。教堂登记台上放着旧交接记录的箱底拓片。铁匠把“" .. cargo .. "”的补铆位置图与拓片叠合。" },
                { characterId = 10, name = "铁匠", text = "不是同款。是同一只箱子。这里打歪过，又补了一次。" },
                { name = "远征长", text = "它后来去哪了？" },
                { characterId = 21, name = "圣女", text = "这份交接底档说，药箱十二入了保全库。" },
                { characterId = 2, name = "黄桃龙", text = "保全库……是救人用的？" },
                { characterId = 10, name = "铁匠", text = "货是救人用的。抢货的时候，押车的人可没有被救。" },
            },
            evidence = assert(Config.getEvidence("E02")),
        }
    elseif key == Config.ORDER_KEY then
        local evidence = assert(Config.getEvidence("E05"))
        evidence.continuation, evidence.people = nil, nil
        return {
            title = "与自己相同的印", mode = "small", dependency = Config.CARGO_KEY,
            unlockText = "处理“货牌找到了箱子”后开放",
            steps = {
                { name = "旁白", text = "圣女拿出独立保存的征用签发底档。印鉴裂角吻合，正文抄件标有旧登记页号。这份附录不是道具掉落奖励。" },
                { name = "远征长", text = "我的印。不是我签的。" },
                { characterId = 21, name = "圣女", text = "这印是真的，不代表这句话是你写的。还要找到拿它下令的人。" },
                { characterId = 3, name = "叮咚鸡", text = "页号不对。先留着原件，别急着认人。" },
                { characterId = 10, name = "铁匠", text = "那我留着押车人的话。有人穿得像你们，不是说现在这三个人动的手。" },
                { name = "远征长", text = "找到签发的人，当面问。" },
            },
            evidence = evidence,
        }
    elseif key == Config.PEOPLE_KEY then
        return {
            title = "箱子以外的失物", mode = "small", dependency = Config.ORDER_KEY,
            unlockText = "处理“与自己相同的印”后开放",
            steps = {
                { name = "旁白", text = "登记台上保存着一名商队幸存者的证言。旁边挂着旧护送队胸牌，绳带断在结的内侧。" },
                { name = "幸存者证言", text = "第一次拦车，他们只搬药箱。第二次，他们说护送队也在征用名单里。" },
                { name = "幸存者证言", text = "我听见一个声音叫他们先停。命令没有撤下。刀也没有。" },
                { name = "远征长", text = "不是只有商队。" },
                { name = "旁白", text = "叮咚鸡把胸牌从物资清单边移开，另铺一张纸。断绳没有接回，也没有被换算成救援名额。" },
                { characterId = 3, name = "叮咚鸡", text = "另开一页。人不能记成一箱东西。" },
                { characterId = 1, name = "大狗嚼", text = "叫……被征用的不只是箱子，还有护送的人？" },
                { characterId = 21, name = "圣女", text = "这几件遗物有主人。别把所有战利品都算到这案子里，也别把这案子漏掉。" },
            },
            evidence = assert(Config.getEvidence("E05")),
        }
    elseif key == Config.MANIFEST_KEY then
        local evidence = assert(Config.getEvidence("E02"))
        evidence.annotation = nil
        return {
            title = "十二号箱", mode = "small", requiredStage = 204,
            unlockText = "普通2-4货牌交接记录未确认",
            steps = {
                { name = "旁白", text = "铁匠整理被砸坏的货牌。焦黑的一片上还能辨认“药箱十二”，下角画着箱底补铆的位置图，其中一枚打歪。" },
                { characterId = 10, name = "铁匠", text = "认错你们，我道歉。丢了什么，我记得。" },
                { name = "远征长", text = "药箱？" },
                { characterId = 10, name = "铁匠", text = "药、夹板，还有给伤员留的干粮。不是兵器。" },
                { characterId = 2, name = "黄桃龙", text = "干粮也抢？这不行。" },
                { characterId = 10, name = "铁匠", text = "他们说“先救人”。押车的人问救谁，没等到回答。" },
                { characterId = 1, name = "大狗嚼", text = "叫！下次遇见，我替你问。" },
                { characterId = 10, name = "铁匠", text = "货牌拿着。别只看它烧黑了。图上这处歪铆，是我给箱底补的。" },
            },
            evidence = evidence,
        }
    elseif key == Config.DOG_MIRROR_KEY then
        return {
            title = "狗留下的绳结", mode = "small", requiredStage = 2505,
            unlockText = "通关2505并处理旧遭遇后开放",
            steps = {
                -- 凭片由当前页载体生成，不是旧页实体在非接驳关跨页掉落。
                { name = "旁白", text = "镜像投影败退，当前页既有登记载体根据回声生成一张本地抄片。绳结画成三股，中间的一股被收得最紧。" },
                { characterId = 1, name = "大狗嚼", text = "叫！我不会那样绑人。" },
                { name = "远征长", text = "这里写着“请先带远征长走”。" },
                { characterId = 1, name = "大狗嚼", text = "……是我会说的话。" },
                { characterId = 3, name = "叮咚鸡", text = "名字是你的。抄的是别页的申请。留下。" },
                { name = "旁白", text = "大狗嚼指甲已划开纸角。听见“请先带远征长走”，他松开了手。" },
                { characterId = 1, name = "大狗嚼", text = "本狗没说它就是真的。" },
                { name = "远征长", text = "我也没说。先让它把话留下。" },
            },
            evidence = assert(Config.getEvidence("E03-A")),
        }
    elseif key == Config.BELL_MIRROR_KEY then
        return {
            title = "停不了的第三声", mode = "small", requiredStage = 2905,
            unlockText = "通关2905并处理旧遭遇后开放",
            steps = {
                { name = "旁白", text = "凭片上有“请求结束通知”。下方的处理结果只有“收到”，没有“批准”。镜像退去后，远处又响两声铃。" },
                { characterId = 3, name = "叮咚鸡", text = "死亡通知：收到。回程那行，还是空的。" },
                { name = "远征长", text = "我们照她说的做了。为什么还响？" },
                { characterId = 3, name = "叮咚鸡", text = "也许她请求的是另一件事。" },
                { characterId = 1, name = "大狗嚼", text = "叫……她说不想再走。" },
                { characterId = 2, name = "黄桃龙", text = "那为什么每张纸都叫她继续？" },
                -- 无尸体复活镜头；不把普通死亡统统改成投影。
                { name = "旁白", text = "第三声迟到。" },
                { characterId = 3, name = "叮咚鸡", text = "这次把铃声也记下来。" },
            },
            evidence = assert(Config.getEvidence("E03-C")),
        }
    end
    return nil
end

return Config
