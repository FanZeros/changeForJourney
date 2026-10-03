-- 剧情显示词典与 UTF-8 工具。仅完整原文匹配，不修改剧情配置、素材名或存档键。
-- 返回值的 zh_TW/en/ja/ko 可 mergeLang；lookup(text, lang) 未命中返回 nil。
local M = { zh_TW = {}, en = {}, ja = {}, ko = {} }
---@type string[]
M.SOURCES = {}
---@type string[]
M.LETTER = {}
---@type string[]
M.INTRO = {}

local function add(zh, tw, en, ja, ko)
    M.zh_TW[zh], M.en[zh], M.ja[zh], M.ko[zh] = tw, en, ja, ko
    M.SOURCES[#M.SOURCES + 1] = zh
end
local function letter(zh, tw, en, ja, ko)
    add(zh, tw, en, ja, ko)
    M.LETTER[#M.LETTER + 1] = zh
end
local function intro(zh, tw, en, ja, ko)
    add(zh, tw, en, ja, ko)
    M.INTRO[#M.INTRO + 1] = zh
end

-- 当前来信：严格对应 LetterIntro 的 4×3 行，不沿用旧遗嘱词条。
letter("致第三十七任远征长：", "致第三十七任遠征長：", "To the 37th Marshal:", "第三十七代遠征長へ：", "제37대 원정장에게:")
letter("拆开这封信时，我已经荣休了。", "拆開這封信時，我已經榮休了。", "By the time you open this, I will have honorably retired.", "この手紙を開く頃、私はもう晴れて引退している。", "이 편지를 펼칠 때면, 나는 이미 명예롭게 은퇴했을 거다.")
letter("公会管这叫交接。我管这叫甩锅。", "公會管這叫交接。我管這叫甩鍋。", "The guild calls it a handover. I call it passing the buck.", "組合は引き継ぎと呼ぶ。私は責任の丸投げと呼ぶ。", "공회는 인수인계라 부른다. 나는 책임 떠넘기기라 부르지.")
letter("帽子、印鉴、名册，都在桌上。", "帽子、印鑑、名冊，都在桌上。", "The hat, the seal, and the roster are on the desk.", "帽子、印章、名簿は、全部机の上だ。", "모자, 인장, 명부는 모두 책상 위에 있다.")
letter("塔底下的山海怪不讲道理，", "塔底下的山海怪不講道理，", "The Shanhai beasts beneath the tower won't listen to reason,", "塔の下の山海の怪物には理屈が通じないが、", "탑 아래 산해의 괴물들은 말이 통하지 않지만,")
letter("但它们会排队上门。", "但牠們會排隊上門。", "but they do queue up at our door.", "律儀に列を作って押しかけてくる。", "줄을 서서 문 앞으로 찾아오기는 한다.")
letter("门外有三条吵闹的命。", "門外有三條吵鬧的命。", "Three noisy souls are waiting outside.", "門の外には、騒がしい命が三つ待っている。", "문밖에는 시끄러운 목숨 셋이 기다리고 있다.")
letter("狗会咬，龙会烧，鸡会敲铃。", "狗會咬，龍會燒，雞會敲鈴。", "The dog bites, the dragon burns, and the chicken rings a bell.", "犬は噛み、竜は焼き、鶏は鈴を鳴らす。", "개는 물고, 용은 태우고, 닭은 종을 울린다.")
letter("先听他们把话说完，再出门。", "先聽他們把話說完，再出門。", "Hear them out before you head through the door.", "まず彼らの話を最後まで聞いてから、出かけなさい。", "먼저 저 녀석들 말을 끝까지 듣고 나서 나가거라.")
letter("公会不需要英雄。", "公會不需要英雄。", "The guild does not need a hero.", "組合に英雄は要らない。", "공회에 영웅은 필요 없다.")
letter("需要一个肯签字的傻子。", "需要一個肯簽字的傻子。", "It needs a fool willing to sign.", "署名してくれる馬鹿が一人いればいい。", "기꺼이 서명할 바보 하나면 된다.")
letter("——第三十六任，你的外祖父", "——第三十六任，你的外祖父", "— The 36th Marshal, your grandfather", "——第三十六代、お前の祖父", "——제36대, 너의 외할아버지")

-- 旧过场仍可重播，先译全文，再按译文长度压缩打字窗口。
intro("这就是……宿命吗？", "這就是……宿命嗎？", "So this is... fate?", "これが……宿命なのか？", "이것이…… 숙명인가?")
intro("我终究……还是倒在这里了吗", "我終究……還是倒在這裡了嗎", "In the end... is this where I fall?", "結局……ここで倒れてしまったのか", "결국…… 여기서 쓰러지고 만 건가")
intro("一切的轮回，再次开始了么……", "一切的輪迴，再次開始了麼……", "Has the cycle begun all over again...?", "すべての輪廻が、また始まったのか……", "모든 윤회가 다시 시작된 건가……")
intro("不知能否斩断宿命，挣脱轮回呢……", "不知能否斬斷宿命，掙脫輪迴呢……", "Can I sever fate and break free of the cycle...?", "宿命を断ち、輪廻から抜け出せるだろうか……", "숙명을 끊고 윤회에서 벗어날 수 있을까……")
intro("远征长！远征长！", "遠征長！遠征長！", "Marshal! Marshal!", "遠征長！遠征長！", "원정장! 원정장!")

-- 开场第二幕：门厅点卯（OPENING）。角色译名沿用 I18nDictExtra。
add("叫！信拆完了？门外三条命都在等你签字。再磨蹭，我先把门牌啃了。",
    "叫！信拆完了？門外三條命都在等你簽字。再磨蹭，我先把門牌啃了。",
    "Woof! Done with the letter? Three lives outside are waiting for your signature. Keep dawdling and I'll chew up the doorplate first.",
    "ワン！手紙は読んだ？門の外の三つの命が署名待ちだよ。ぐずぐずしてると、先に表札をかじっちゃうぞ。",
    "멍! 편지는 다 읽었어? 문밖의 목숨 셋이 서명을 기다리고 있어. 더 꾸물거리면 문패부터 씹어 버릴 거야.")
add("黄桃龙带了火把，也带了烤肠。塔底下那些山海怪，保证只烧怪！……大概。",
    "黃桃龍帶了火把，也帶了烤腸。塔底下那些山海怪，保證只燒怪！……大概。",
    "Peach Drake brought a torch—and sausages! Those Shanhai beasts under the tower? I promise to roast only the beasts! ...Probably.",
    "黄桃竜、松明もソーセージも持ってきたよ！塔の下の山海の怪物、怪物だけ焼くって約束する！……たぶん。",
    "황도룡은 횃불도, 소시지도 가져왔어! 탑 아래 산해의 괴물들, 괴물만 태우겠다고 약속할게! ……아마도.")
add("叮咚~编制通知：先锋位空缺。建议先带大狗嚼出门。理由：门槛已经有牙印了。",
    "叮咚~編制通知：先鋒位空缺。建議先帶大狗嚼出門。理由：門檻已經有牙印了。",
    "Ding-dong~ Staffing notice: vanguard position vacant. Recommendation: take Chewchow out first. Reason: the doorstep already has tooth marks.",
    "ピンポン〜配属通知：先鋒枠、空席。ワン噛みを先に連れ出すことを推奨。理由：敷居にすでに歯形あり。",
    "띵동~ 편제 통지: 선봉 자리 공석. 큰개씹을 먼저 데리고 나갈 것을 권고. 사유: 문턱에 이미 이빨 자국이 있음.")
add("远征长，帽子戴正。公会不发英雄光环，只发一张出门的单子。今天，我们去敲门。",
    "遠征長，帽子戴正。公會不發英雄光環，只發一張出門的單子。今天，我們去敲門。",
    "Straighten your hat, Marshal. The guild doesn't issue heroic halos, just a departure slip. Today, we go knocking.",
    "遠征長、帽子をちゃんとかぶって。組合がくれるのは英雄の光輪じゃなくて、外出許可の紙一枚。今日は、こっちから門を叩くんだ。",
    "원정장, 모자 똑바로 써. 공회는 영웅의 후광 대신 출문 서류 한 장만 줘. 오늘은 우리가 문을 두드리러 가는 거야.")

-- 开场第三幕：三人入队（OPENING_JOINS），只显示，不接管入队流程。
add("入队  ·  大狗嚼", "入隊  ·  大狗嚼", "Joining · Chewchow", "入隊・ワン噛み", "합류 · 큰개씹")
add("入队  ·  黄桃龙", "入隊  ·  黃桃龍", "Joining · Peach Drake", "入隊・黄桃竜", "합류 · 황도룡")
add("入队  ·  叮咚鸡", "入隊  ·  叮咚雞", "Joining · Dingdong", "入隊・ピンポン鶏", "합류 · 띵동닭")
add("叫！先锋位我占了。骨头先寄存在你那儿，人我带上。",
    "叫！先鋒位我佔了。骨頭先寄存在你那兒，人我帶上。",
    "Woof! I'm taking the vanguard slot. Keep my bone safe; I'll bring myself along.",
    "ワン！先鋒枠はいただき。骨は預けとくから、私自身を連れていくよ。",
    "멍! 선봉 자리는 내가 맡을게. 뼈다귀는 네게 맡기고, 이 몸은 따라간다.")
add("天狗算什么。在狗面前，它就是只大鸟。出发之前，先让后两位报到。",
    "天狗算什麼。在狗面前，牠就是隻大鳥。出發之前，先讓後兩位報到。",
    "What's a Tiangou to a dog? Just a big bird. Before we leave, let the other two report in.",
    "天狗が何だっていうの。犬の前じゃ、ただの大きな鳥だよ。出発する前に、残りの二人にも名乗ってもらおう。",
    "천구가 대수야? 개 앞에서는 그냥 큰 새일 뿐이지. 출발하기 전에 뒤의 두 명도 신고하게 하자.")
add("黄桃龙也要上车！火把、烤肠，还有大概不会烧到队友的火球，三件套齐了！",
    "黃桃龍也要上車！火把、烤腸，還有大概不會燒到隊友的火球，三件套齊了！",
    "Peach Drake wants aboard too! Torch, sausages, and a fireball that probably won't roast our teammates—the full set!",
    "黄桃竜も乗る！松明、ソーセージ、それからたぶん仲間を焼かない火球！三点セット、そろったよ！",
    "황도룡도 탈래! 횃불, 소시지, 그리고 아마 동료는 안 태울 화염구까지! 세트 완성!")
add("站中间就行。左边有狗咬，右边有铃。黄桃龙负责把路点亮。……大概。",
    "站中間就行。左邊有狗咬，右邊有鈴。黃桃龍負責把路點亮。……大概。",
    "The middle is fine. Bites on the left, bells on the right. Peach Drake will light the way. ...Probably.",
    "真ん中にいればいいね。左は犬の噛みつき、右は鈴。黄桃竜は道を照らす係。……たぶん。",
    "가운데 서면 돼. 왼쪽은 개가 물고, 오른쪽은 종이 울려. 황도룡은 길을 밝힐게. ……아마도.")
add("叮咚~入队通知：叮咚鸡，哨位。编制三人，已齐。",
    "叮咚~入隊通知：叮咚雞，哨位。編制三人，已齊。",
    "Ding-dong~ Joining notice: Dingdong, sentry duty. Three-person roster: complete.",
    "ピンポン〜入隊通知：ピンポン鶏、哨戒枠。定員三名、全員集合。",
    "띵동~ 합류 통지: 띵동닭, 경계 임무. 정원 세 명, 전원 집결.")
add("叮咚~下一步：出门。落单勿慌，先听铃声。远征长，可以签字了。",
    "叮咚~下一步：出門。落單勿慌，先聽鈴聲。遠征長，可以簽字了。",
    "Ding-dong~ Next step: head out. If separated, stay calm and listen for the bell. Marshal, you may sign now.",
    "ピンポン〜次の手順：出発。はぐれても慌てず、まず鈴の音を聞くこと。遠征長、署名どうぞ。",
    "띵동~ 다음 단계: 출문. 떨어져도 당황하지 말고 먼저 종소리를 들을 것. 원정장, 이제 서명하면 됩니다.")

-- 代表性剧情：城门、神器登记、酒馆招募、第二章潜能引导。
add("卫兵", "衛兵", "Guard", "衛兵", "경비병")
add("圣女", "聖女", "Saintess", "聖女", "성녀")
add("老板娘", "老闆娘", "Innkeeper", "女将", "주인장")
add("站住！城门重地！报上名来！……先别紧张，我只是按流程喊的。",
    "站住！城門重地！報上名來！……先別緊張，我只是按流程喊的。",
    "Halt! City gate! State your name! ...Don't panic. I'm only shouting because the procedure says so.",
    "止まれ！城門だ！名を名乗れ！……緊張しなくていい。手順どおりに叫んでるだけだ。",
    "멈춰라! 성문이다! 이름을 대라! ……긴장하지 마. 절차대로 외치는 것뿐이야.")
add("新面孔呀~别抬头找祝福啦，那套早就不兴了。现在教堂只办一件事：神器登记。",
    "新面孔呀~別抬頭找祝福啦，那套早就不興了。現在教堂只辦一件事：神器登記。",
    "New faces~ Don't look up for a blessing; that went out of fashion ages ago. The chapel handles just one thing now: artifact registration.",
    "新しい顔ね〜見上げて祝福を探しても無駄よ。あれはとっくに廃れたの。今、礼拝堂で扱うのは神器登録だけ。",
    "처음 보는 얼굴이네~ 축복을 찾으려고 올려다보지 마. 그런 건 진작 유행이 지났어. 지금 예배당은 딱 하나만 해: 신기 등록.")
add("战场上捡的神器都拿来吧~开好光、嵌进槽里，它们才肯干活。空着槽位出门，可是会被人笑话的哦~",
    "戰場上撿的神器都拿來吧~開好光、嵌進槽裡，它們才肯幹活。空著槽位出門，可是會被人笑話的喔~",
    "Bring every artifact you found in battle~ They'll only work once blessed and fitted into slots. Head out with empty slots and people will laugh, you know~",
    "戦場で拾った神器は全部持ってきて〜清めてスロットにはめてこそ、働いてくれるの。空のスロットのまま出かけたら、笑われちゃうわよ〜",
    "전장에서 주운 신기는 전부 가져와~ 축성하고 슬롯에 끼워야 일을 하거든. 슬롯을 비워 둔 채 나가면 놀림받을걸~")
add("哎呀！新远征队呀~来得正好！墙上招募告示随便揭，揭一张，送一杯酸梅汤~",
    "哎呀！新遠征隊呀~來得正好！牆上招募告示隨便揭，揭一張，送一杯酸梅湯~",
    "Oh! A new expedition team~ Perfect timing! Take any recruitment notice off the wall. One notice, one plum drink on the house~",
    "あら！新しい遠征隊ね〜ちょうどよかった！壁の募集告知、好きなのを剥がしてね。一枚につき酸梅湯を一杯サービスよ〜",
    "어머! 새 원정대네~ 잘 왔어! 벽의 모집 공고는 마음껏 떼어 가. 한 장 떼면 매실 음료 한 잔은 서비스야~")
add("叫！第二章啃完了！本狗的牙口还没尽兴，骨头缝里都在冒火星子！",
    "叫！第二章啃完了！本狗的牙口還沒盡興，骨頭縫裡都在冒火星子！",
    "Woof! Chapter two, chewed through! These jaws aren't done yet—there are sparks flying between my bones!",
    "ワン！第二章、かじり終わり！まだまだ噛み足りないよ。骨の隙間から火花が出てるんだから！",
    "멍! 2장을 다 씹어 넘겼다! 이 개의 턱은 아직 성에 안 차. 뼈 틈에서도 불꽃이 튀고 있어!")
add("远征长看好了——这 10 块碎片是本狗从怪堆里嚼出来的！塞进「潜能」里，就能嵌合第一阶！",
    "遠征長看好了——這 10 塊碎片是本狗從怪堆裡嚼出來的！塞進「潛能」裡，就能嵌合第一階！",
    "Watch this, Marshal—10 shards, chewed straight out of the beast pile! Put them into Potential to socket the first tier!",
    "遠征長、見てて——この10個の欠片、怪物の山から噛み出したんだ！「潜在能力」に入れれば、第一段階を嵌合できるよ！",
    "원정장, 잘 봐——이 조각 10개는 내가 괴물 더미에서 씹어 낸 거야! 「잠재력」에 넣으면 첫 단계를 장착할 수 있어!")
add("角色详情、觉醒页、嵌合！三步走！嵌完下一口，本狗直接啃boss的脑袋！叫！",
    "角色詳情、覺醒頁、嵌合！三步走！嵌完下一口，本狗直接啃boss的腦袋！叫！",
    "Hero Details, Awaken, Socket! Three steps! Once that's done, my next bite goes straight for the boss's head! Woof!",
    "キャラ詳細、覚醒ページ、嵌合！三つの手順！はめたら次はボスの頭を直接かじるよ！ワン！",
    "영웅 정보, 각성 페이지, 장착! 세 단계면 끝! 장착하고 나면 다음 한 입은 보스 머리다! 멍!")

-- 显示框架提示（旧词典已有的翻页/火漆保持既有译文）。
add("情景", "情景", "Story", "物語", "이야기")
add("闲谈", "閒談", "Conversation", "雑談", "잡담")
add("轻触继续", "輕觸繼續", "Tap to continue", "タップして続ける", "터치하여 계속")

-- 完整句包含两个源行；LetterIntro 合并显示，不修改其 12 行配置。
add("塔底下的山海怪不讲道理，但它们会排队上门。",
    "塔底下的山海怪不講道理，但牠們會排隊上門。",
    "The Shanhai beasts beneath the tower won't listen to reason, but they do queue up at our door.",
    "塔の下の山海の怪物には理屈が通じないが、律儀に列を作って押しかけてくる。",
    "탑 아래 산해의 괴물들은 말이 통하지 않지만, 줄을 서서 문 앞으로 찾아오기는 한다.")

---@param text any
---@param lang any
---@return string|nil
function M.lookup(text, lang)
    if type(text) ~= "string" or text == "" or type(lang) ~= "string" then return nil end
    if lang == "zh_CN" then return M.en[text] and text or nil end
    local pack = M[lang]
    if lang ~= "zh_TW" and lang ~= "en" and lang ~= "ja" and lang ~= "ko" then return nil end
    local hit = pack[text]
    return type(hit) == "string" and hit ~= "" and hit or nil
end

-- 工具的输入必须是已翻译的完整句。所有索引都是 UTF-8 码点，不是字节。
---@param text string
---@return integer
function M.length(text)
    return utf8.len(text) or 0
end

---@param text string
---@param first number
---@param last number
---@return string
function M.sub(text, first, last)
    local n = M.length(text)
    local a, b = math.max(1, math.floor(first)), math.min(n, math.floor(last))
    if a > b then return "" end
    local startByte = utf8.offset(text, a)
    local endByte = utf8.offset(text, b + 1)
    if not startByte then return "" end
    return text:sub(startByte, endByte and (endByte - 1) or #text)
end

-- 固定过场窗口不足时，压缩打字时间而非截掉译文尾部。
---@param text string 已翻译全文
---@param elapsed number
---@param cps number
---@param maxDur number|nil
---@return string visible
---@return integer count
---@return number typingDur
---@return number totalDur
function M.typed(text, elapsed, cps, maxDur)
    local n = M.length(text)
    local typingDur = n / math.max(1, cps)
    local totalDur = typingDur + 1.3
    if maxDur then
        totalDur = math.max(0, math.min(totalDur, maxDur))
        local tail = math.min(1.3, totalDur * 0.4)
        typingDur = math.min(typingDur, math.max(0.001, totalDur - tail))
    end
    local count = math.min(n, math.max(0, math.floor(elapsed / math.max(0.001, typingDur) * n)))
    return M.sub(text, 1, count), count, typingDur, totalDur
end

---@class StoryDisplayRow
---@field text string
---@field first integer
---@field last integer

-- 折完整译文，记录字符区间；打字时只截区间，不对残句重新翻译或重新折行。
-- 英文优先空白处换行，超长词及日韩中按码点兜底；不丢字符和显式换行。
---@param text string 已翻译全文
---@param width number
---@param measure fun(text:string):number 原样测量，禁止使用翻译 hook 测片段
---@return StoryDisplayRow[]
function M.wrap(text, width, measure)
    local rows = {} ---@type StoryDisplayRow[]
    local n = M.length(text)
    if n == 0 then return rows end
    local first, i, gap = 1, 1, 0
    local function push(last)
        rows[#rows + 1] = { text = M.sub(text, first, last), first = first, last = last }
    end
    while i <= n do
        local ch = M.sub(text, i, i)
        if ch == "\n" then
            push(i - 1)
            first, gap = i + 1, 0
        elseif i > first and measure(M.sub(text, first, i)) > math.max(1, width) then
            local last = gap >= first and gap or (i - 1)
            push(last)
            first, i, gap = last + 1, last, 0
        elseif ch:match("%s") then
            gap = i
        end
        i = i + 1
    end
    if first <= n then push(n) end
    return rows
end

---@param row StoryDisplayRow
---@param count number 可见码点总数
---@return string
function M.rowPrefix(row, count)
    return M.sub(row.text, 1, math.min(row.last, math.floor(count)) - row.first + 1)
end

return M
