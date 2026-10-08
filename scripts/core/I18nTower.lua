-- 通天塔局部显示词典；不注册到 core.I18n，不安装绘制 hook，不读取或修改业务数据。
-- 每个描述以 TowerConfig 的完整原文为 key；数值、触发条件与职业限制保留。
local M = {}

---@type table<string, table<string, string>>
local dictionaries = { zh_TW = {}, en = {}, ja = {}, ko = {} }

---@param source string
---@param tw string
---@param en string
---@param ja string
---@param ko string
local function add(source, tw, en, ja, ko)
    dictionaries.zh_TW[source] = tw
    dictionaries.en[source] = en
    dictionaries.ja[source] = ja
    dictionaries.ko[source] = ko
end

-- 塔入口仍沿用既有正式名称；暗契仅是局内展示语汇。
add("通天塔", "通天塔", "Sky Tower", "通天塔", "통천탑")
add("塔之暗契", "塔之暗契", "Dark Pacts of the Tower", "塔の暗契", "탑의 어둠 계약")
add("三枚契印 · 择一承受", "三枚契印 · 擇一承受", "Three pact seals · Bear one", "三つの契印 · 一つを引き受けよ", "세 계약 인장 · 하나를 감당하라")
add("增益铭录", "增益銘錄", "Boon Ledger", "恩恵の銘録", "강화 각인록")
add("尚未缔结暗契", "尚未締結暗契", "No dark pact sealed yet", "暗契はまだ結ばれていない", "아직 어둠 계약을 맺지 않았습니다")
add("全部小队共享", "全部小隊共享", "Shared by all squads", "全小隊で共有", "모든 소대가 공유")
add("本层有效", "本層有效", "This floor only", "この階のみ有効", "현재 층에서만 유효")
add("铭刻", "銘刻", "Inscribe", "刻印", "각인")
add("正在铭刻", "正在銘刻", "Inscribing", "刻印中", "각인 중")
add("正在铭刻...", "正在銘刻...", "Inscribing...", "刻印中...", "각인 중...")
add("仅可重试原契印", "僅可重試原契印", "Retry only the original seal", "元の契印のみ再試行可能", "원래 인장만 다시 시도할 수 있습니다")
add("返回登塔", "返回登塔", "Return to the Tower", "登塔に戻る", "탑 등반으로 돌아가기")
add("取消", "取消", "Cancel", "キャンセル", "취소")
add("撤退", "撤退", "Retreat", "撤退", "후퇴")
add("确认撤退？", "確認撤退？", "Retreat?", "撤退しますか？", "후퇴할까요?")
add("本层进度将丢失", "本層進度將丟失", "Progress on this floor will be lost", "この階の進行状況は失われます", "현재 층의 진행 상황이 사라집니다")
add("第%d层", "第%d層", "Floor %d", "%d階", "%d층")
add("第%d层  剩余%.0fs", "第%d層  剩餘%.0fs", "Floor %d  %.0fs left", "%d階  残り%.0f秒", "%d층  남은 시간 %.0f초")
add("第%d-%d层 · 每层1波", "第%d-%d層 · 每層1波", "Floors %d-%d · 1 wave each", "%d-%d階 · 各階1ウェーブ", "%d-%d층 · 층당 1웨이브")
add("每层1波 · 每5层一组", "每層1波 · 每5層一組", "1 wave/floor · 5 floors/run", "各階1ウェーブ · 5階ごとに1組", "층당 1웨이브 · 5층씩 한 그룹")
add("起点", "起點", "Start", "開始", "시작")
add("路线只读 · 标记为每五层起点", "路線唯讀 · 標記為每五層起點", "View-only route · Starts every 5 floors", "閲覧専用 · 印は5階ごとの開始点", "경로는 확인 전용 · 표시는 5층마다 시작점")
add("首通奖励 ×%s", "首通獎勵 ×%s", "First-clear reward ×%s", "初回報酬 ×%s", "첫 클리어 보상 ×%s")
add("本组剩余首通黑钻 ×%s · 重打/扫荡0", "本組剩餘首通黑鑽 ×%s · 重打/掃蕩0",
    "Group first-clear diamonds left ×%s · Repeat/sweep 0",
    "組の未獲得初回黒ダイヤ ×%s · 再戦/掃討0", "그룹 미획득 첫 클리어 흑다이아 ×%s · 재도전/소탕0")
add("每层胜利神器%d%% · 品质1/2/3 %d/%d/%d%%", "每層勝利神器%d%% · 品質1/2/3 %d/%d/%d%%",
    "Artifact %d%% per floor win · Q1/2/3 %d/%d/%d%%",
    "各階勝利で神器%d%% · 品質1/2/3 %d/%d/%d%%", "층 승리당 신기%d%% · 품질1/2/3 %d/%d/%d%%")
add("组远征经验 首通2分/层 %s · 重打1分/层 %s", "組遠征經驗 首通2分/層 %s · 重打1分/層 %s",
    "Group EXP: first 2m/floor %s · Repeat 1m/floor %s",
    "組の遠征EXP 初回2分/階 %s · 再戦1分/階 %s", "그룹 원정EXP 첫승2분/층 %s · 재승1분/층 %s")
add("第 %d 层", "第 %d 層", "Floor %d", "%d階", "%d층")
add("波次 %d/%d", "波次 %d/%d", "Wave %d/%d", "ウェーブ %d/%d", "웨이브 %d/%d")
add("灰烬", "灰燼", "Ashes", "灰燼", "잿더미")
add("血契", "血契", "Blood Pact", "血契", "피의 계약")
add("渊誓", "淵誓", "Abyssal Oath", "深淵の誓い", "심연의 맹세")
add("普通", "普通", "Common", "コモン", "일반")
add("优质", "優質", "Uncommon", "アンコモン", "고급")
add("稀有", "稀有", "Rare", "レア", "레어")
add("史诗", "史詩", "Epic", "エピック", "에픽")
add("传说", "傳說", "Legendary", "レジェンダリー", "전설")
add("暗契", "暗契", "Dark Pact", "暗契", "어둠 계약")
add("选择一项强化", "選擇一項強化", "Pick a buff", "強化を選ぶ", "강화 선택")
add("继续战斗", "繼續戰鬥", "Continue Battle", "戦闘を続ける", "전투 계속")
add("塔之路线", "塔之路線", "Tower Route", "塔の道筋", "탑의 경로")
add("已获强化", "已獲強化", "Acquired Boons", "獲得済みの強化", "획득한 강화")
add("收起", "收起", "Collapse", "折りたたむ", "접기")
add("展开", "展開", "Expand", "展開", "펼치기")
add("暂无强化", "暫無強化", "No boons yet", "強化はまだない", "아직 강화 없음")
add("继续择契", "繼續擇契", "Resume Pact Choice", "契印選びを続ける", "계약 선택 계속")
add("待选暗契 ×%d", "待選暗契 ×%d", "Pending Pacts ×%d", "未選択の暗契 ×%d", "미선택 계약 ×%d")
add("稍后选择", "稍後選擇", "Choose Later", "後で選ぶ", "나중에 선택")
add("选择保留，战斗继续；强化从下一层生效", "選擇保留，戰鬥繼續；強化從下一層生效",
    "Choices stay available; battle continues. Boons apply next floor.",
    "選択肢は保持され、戦闘は継続。強化は次の階から有効。",
    "선택지는 유지되고 전투는 계속됩니다. 강화는 다음 층부터 적용됩니다.")
add("选择保留，战斗继续；强化从下一波生效", "選擇保留，戰鬥繼續；強化從下一波生效",
    "Choices stay available; battle continues. Boons apply next wave.",
    "選択肢は保持され、戦闘は継続。強化は次のウェーブから有効。",
    "선택지는 유지되고 전투는 계속됩니다. 강화는 다음 웨이브부터 적용됩니다.")
add("本层路线仅供查看", "本層路線僅供查看", "This floor's route is view-only", "この階の道筋は閲覧専用", "현재 층의 경로는 확인만 가능합니다")
add("次数仅作记录，效果按原规则生效", "次數僅作記錄，效果按原規則生效",
    "Counts are recorded only; effects follow the original rules.",
    "回数は記録のみ。効果は元のルールに従って適用される。",
    "횟수는 기록용이며, 효과는 원래 규칙에 따라 적용됩니다.")
add("未抵达", "未抵達", "Not reached", "未到達", "미도달")
add("已通过", "已通過", "Cleared", "クリア済み", "통과 완료")
add("正在攻坚", "正在攻堅", "In progress", "攻略中", "공략 중")
add("强化 ×%d", "強化 ×%d", "Boons ×%d", "強化 ×%d", "강화 ×%d")
add("取消只收起契印，当前选择仍会保留", "取消只收起契印，當前選擇仍會保留",
    "Cancel only hides the pact seals; the current choices are retained.",
    "キャンセルは契印を閉じるだけ。現在の選択肢は保持される。",
    "취소는 계약 인장만 숨기며, 현재 선택지는 유지됩니다.")
add("确认", "確認", "Confirm", "確認", "확인")
add("职业专属", "職業專屬", "Class-only", "クラス専用", "직업 전용")
add("封门人", "封門人", "Gatewarden", "門を封ずる者", "봉문인")
add("拾骸者", "拾骸者", "Bonepicker", "骸拾い", "습해자")
add("裂隙使", "裂隙使", "Riftweaver", "裂け目使い", "열극사")
add("回响客", "回響客", "Echoist", "残響客", "메아리객")
add("换面人", "換面人", "Facestealer", "面替え", "환면인")
add("司仪", "司儀", "Officiant", "司式", "사제")

-- ID 1..35 的展示名称；不取代配置原名或关键词业务 key。
add("墓铁磨刃", "墓鐵磨刃", "Grave-Iron Edge", "墓鉄の刃研ぎ", "묘철 칼날 연마")
add("幽典涌魔", "幽典湧魔", "Umbral Tome Surge", "幽典の魔力奔流", "어둠 서책의 마력 분출")
add("余烬续命", "餘燼續命", "Ember Lifeline", "残り火の延命", "잔불의 연명")
add("夜巡之眼", "夜巡之眼", "Nightwatch Eye", "夜巡りの眼", "야경의 눈")
add("断命刃", "斷命刃", "Life-Severing Blade", "命断ちの刃", "생명 절단검")
add("墓影步", "墓影步", "Graveshadow Step", "墓影の歩み", "묘영의 발걸음")
add("锁链连斩", "鎖鏈連斬", "Chained Slashes", "鎖の連斬", "사슬 연속 참격")
add("饮血续命", "飲血續命", "Blood-Drinker Lifeline", "血飲みの延命", "흡혈의 연명")
add("夜袭先手", "夜襲先手", "Night-Raid Initiative", "夜襲の先手", "야습 선공")
add("裂甲尖锋", "裂甲尖鋒", "Armor-Rending Edge", "装甲裂きの鋭刃", "갑옷을 찢는 예봉")
add("濒死狂焰", "瀕死狂焰", "Death's-Door Flame", "瀕死の狂炎", "빈사의 광염")
add("盛命凶怒", "盛命凶怒", "Vital Fury", "盛命の凶怒", "충만한 생명의 분노")
add("濒死铁幕", "瀕死鐵幕", "Death's-Door Iron Veil", "瀕死の鉄幕", "빈사의 철막")
add("开战血锋", "開戰血鋒", "Opening Blood Edge", "開戦の血刃", "개전의 혈봉")
add("墓铁坚壁", "墓鐵堅壁", "Grave-Iron Bulwark", "墓鉄の堅壁", "묘철 방벽")
add("斩魂血潮", "斬魂血潮", "Soul-Reaping Bloodtide", "魂狩りの血潮", "혼을 베는 혈조")
add("拾魂凝命", "拾魂凝命", "Soul-Gathered Vitality", "拾魂の命凝り", "혼을 모으는 생명")
add("连斩黑潮", "連斬黑潮", "Blacktide Combo", "連斬の黒潮", "흑조 연참")
add("终命审判", "終命審判", "Final-Life Judgment", "終命の審判", "종명의 심판")
add("奔雷夜刃", "奔雷夜刃", "Thunderous Nightblade", "奔雷の夜刃", "질뢰의 야검")
add("冥霜封域", "冥霜封域", "Deathfrost Domain", "冥霜の封域", "명상의 봉역")
add("战祸催燃", "戰禍催燃", "War-Fueled Frenzy", "戦禍の燃焼", "전쟁의 재앙이 부르는 광기")
add("亡者遗誓", "亡者遺誓", "Oath of the Fallen", "亡者の遺誓", "망자의 유언 맹세")
add("封门怨誓", "封門怨誓", "Gatewarden's Grudge Oath", "封門の怨誓", "봉문의 원한 맹세")
add("不屈墓盾", "不屈墓盾", "Unyielding Grave Shield", "不屈の墓盾", "불굴의 묘지 방패")
add("血骸狂战", "血骸狂戰", "Bloodbone Berserker", "血骸の狂戦", "혈해 광전")
add("残命战魂", "殘命戰魂", "Fading-Life War Soul", "残命の戦魂", "잔명의 전혼")
add("裂隙蓄爆", "裂隙蓄爆", "Charged Rift Burst", "裂け目の溜め爆発", "열극 충전 폭발")
add("幽典蓄魔", "幽典蓄魔", "Umbral Tome Charge", "幽典の魔力溜め", "어둠 서책의 마력 축적")
add("夜眼连射", "夜眼連射", "Night-Eye Volley", "夜眼の連射", "밤눈 연사")
add("墓阵援射", "墓陣援射", "Graveguard Support Fire", "墓陣の援護射撃", "묘진 지원 사격")
add("换面暗刃", "換面暗刃", "Facestealer's Dark Blade", "面替えの暗刃", "환면의 암흑 칼날")
add("虚面避祸", "虛面避禍", "Phantom Mask Evasion", "虚面の厄避け", "허면의 액막이")
add("烬灯赐祷", "燼燈賜禱", "Ember-Lamp Benediction", "燼灯の祈り", "잿불 등불의 축복")
add("余烬命契", "餘燼命契", "Ember Life Pact", "残り火の命契", "잔불의 생명 계약")

-- 完整原描述。加成是属性的加成值，不擅自改为基础属性最终增幅。
add("全体物理攻击力+8%", "全體物理攻擊力+8%",
    "All allies: physical attack +8%.", "味方全体の物理攻撃力+8%。", "아군 전체 물리 공격력+8%.")
add("全体魔法攻击力+8%", "全體魔法攻擊力+8%",
    "All allies: magic attack +8%.", "味方全体の魔法攻撃力+8%。", "아군 전체 마법 공격력+8%.")
add("全体生命加成+8%", "全體生命加成+8%",
    "All allies: HP bonus +8%.", "味方全体のHP補正+8%。", "아군 전체 체력 보너스+8%.")
add("全体暴击率+5%", "全體暴擊率+5%",
    "All allies: crit rate +5%.", "味方全体の会心率+5%。", "아군 전체 치명타율+5%.")
add("全体暴击伤害+24%", "全體暴擊傷害+24%",
    "All allies: crit damage +24%.", "味方全体の会心ダメージ+24%。", "아군 전체 치명 피해+24%.")
add("全体闪避值+5", "全體閃避值+5",
    "All allies: Dodge +5.", "味方全体の回避値+5。", "아군 전체 회피 수치+5.")
add("全体连击概率+6% 全体连击增伤+12%", "全體連擊機率+6% 全體連擊增傷+12%",
    "All allies: combo chance +6% and combo damage bonus +12%.",
    "味方全体の連撃率+6%、連撃ダメージ補正+12%。", "아군 전체 연격 확률+6%, 연격 피해 보너스+12%.")
add("全体生命加成+8% 全体攻击回血+8", "全體生命加成+8% 全體攻擊回血+8",
    "All allies: HP bonus +8% and HP restored per attack +8.",
    "味方全体のHP補正+8%、攻撃時HP回復+8。", "아군 전체 체력 보너스+8%, 공격 시 체력 회복+8.")
add("每次战斗开始时，全体攻击速度+20%", "每次戰鬥開始時，全體攻擊速度+20%",
    "At the start of each battle, all allies gain attack speed +20%.",
    "各戦闘の開始時、味方全体の攻撃速度+20%。", "매 전투 시작 시 아군 전체 공격 속도+20%.")
add("全体物理穿透与魔法穿透+8", "全體物理穿透與魔法穿透+8",
    "All allies: physical penetration and magic penetration +8 each.",
    "味方全体の物理貫通と魔法貫通がそれぞれ+8。", "아군 전체 물리 관통과 마법 관통 각각+8.")
add("远征队员生命低于30%时，额外伤害+25%（乘法计算）", "遠征隊員生命低於30%時，額外傷害+25%（乘法計算）",
    "When an expeditioner's HP is below 30%, their extra damage increases by 25% (multiplicative).",
    "遠征隊員のHPが30%未満の時、追加ダメージ+25%（乗算）。",
    "원정대원의 체력이 30% 미만일 때 추가 피해+25%(곱연산).")
add("远征队员生命高于80%时，额外伤害+20%（乘法计算）", "遠征隊員生命高於80%時，額外傷害+20%（乘法計算）",
    "When an expeditioner's HP is above 80%, their extra damage increases by 20% (multiplicative).",
    "遠征隊員のHPが80%を超える時、追加ダメージ+20%（乗算）。",
    "원정대원의 체력이 80% 초과일 때 추가 피해+20%(곱연산).")
add("远征队员生命低于30%时，受到伤害-50%（乘法计算）", "遠征隊員生命低於30%時，受到傷害-50%（乘法計算）",
    "When an expeditioner's HP is below 30%, their damage taken decreases by 50% (multiplicative).",
    "遠征隊員のHPが30%未満の時、被ダメージ-50%（乗算）。",
    "원정대원의 체력이 30% 미만일 때 받는 피해-50%(곱연산).")
add("战斗前30秒时，全体额外伤害+20%（乘法计算）", "戰鬥前30秒時，全體額外傷害+20%（乘法計算）",
    "During the first 30 seconds of battle, all allies gain extra damage +20% (multiplicative).",
    "戦闘開始から30秒間、味方全体の追加ダメージ+20%（乗算）。",
    "전투 시작 후 첫 30초 동안 아군 전체 추가 피해+20%(곱연산).")
add("全体格挡比例+10%", "全體格擋比例+10%",
    "All allies: block ratio +10%.", "味方全体のガード軽減率+10%。", "아군 전체 막기 비율+10%.")
add("每击杀一个敌人，全体伤害+5%，持续15秒（上限30%）", "每擊殺一個敵人，全體傷害+5%，持續15秒（上限30%）",
    "Each enemy killed grants all allies damage +5% for 15 seconds (cap: 30%).",
    "敵を1体倒すたびに、味方全体のダメージ+5%、15秒間持続（上限30%）。",
    "적을 하나 처치할 때마다 아군 전체 피해+5%, 15초 지속(상한 30%).")
-- 原文第17条的波次/击杀表述保留；不添加持久化、波间保留或额外重置承诺。
add("每波开始每击杀一个敌人，全体生命加成+5%（上限50%）", "每波開始每擊殺一個敵人，全體生命加成+5%（上限50%）",
    "Starting each wave, every enemy killed grants all allies HP bonus +5% (cap: 50%).",
    "各ウェーブの開始から、敵を1体倒すたびに味方全体のHP補正+5%（上限50%）。",
    "각 웨이브 시작부터 적을 하나 처치할 때마다 아군 전체 체력 보너스+5%(상한 50%).")
add("全体连击增伤X2", "全體連擊增傷X2",
    "All allies: combo damage bonus X2.", "味方全体の連撃ダメージ補正X2。", "아군 전체 연격 피해 보너스X2.")
add("对低于10%生命的目标，有10%概率直接消灭", "對低於10%生命的目標，有10%機率直接消滅",
    "Against a target below 10% HP, there is a 10% chance to kill it instantly.",
    "HPが10%未満の対象を10%の確率で即座に倒す。", "체력이 10% 미만인 대상을 10% 확률로 즉시 처치합니다.")
add("全体攻击间隔-25%（乘法，相当于攻速额外+33%）", "全體攻擊間隔-25%（乘法，相當於攻速額外+33%）",
    "All allies: attack interval -25% (multiplicative, equivalent to an extra +33% attack speed).",
    "味方全体の攻撃間隔-25%（乗算、攻撃速度への追加+33%に相当）。",
    "아군 전체 공격 간격-25%(곱연산, 공격 속도 추가+33%에 해당).")
add("每隔10秒，冰冻全体敌人2秒", "每隔10秒，冰凍全體敵人2秒",
    "Every 10 seconds, freeze all enemies for 2 seconds.",
    "10秒ごとに敵全体を2秒間凍結させる。", "10초마다 적 전체를 2초간 빙결시킵니다.")
add("己方将提前15秒进入狂暴与超级狂暴", "己方將提前15秒進入狂暴與超級狂暴",
    "Allies enter Rage and Super Rage 15 seconds earlier.",
    "味方が狂暴と超狂暴に入る時刻を15秒早める。", "아군이 광폭 및 초광폭에 15초 일찍 돌입합니다.")
add("当有己方死亡时，剩余的己方单位在5秒内无法受到任何伤害", "當有己方死亡時，剩餘的己方單位在5秒內無法受到任何傷害",
    "When an ally dies, the remaining allied units cannot take any damage for 5 seconds.",
    "味方が死亡すると、残りの味方ユニットは5秒間あらゆるダメージを受けない。",
    "아군이 사망하면 남은 아군 유닛은 5초간 어떠한 피해도 받지 않습니다.")
add("「封门人」仇恨值倍率+200%，且每场战斗开始时仇恨值额外+2000", "「封門人」仇恨值倍率+200%，且每場戰鬥開始時仇恨值額外+2000",
    "Gatewarden: threat multiplier +200%, and extra threat +2000 at the start of each battle.",
    "「門を封ずる者」のヘイト倍率+200%。さらに各戦闘の開始時にヘイト+2000。",
    "「봉문인」 위협 배율+200%, 매 전투 시작 시 위협 추가+2000.")
add("「封门人」生命低于[40%/20%]时，获得[20%/40%]伤害减免", "「封門人」生命低於[40%/20%]時，獲得[20%/40%]傷害減免",
    "Gatewarden: below [40%/20%] HP, gain [20%/40%] damage reduction respectively.",
    "「門を封ずる者」のHPが[40%/20%]未満の時、それぞれ[20%/40%]のダメージ軽減を得る。",
    "「봉문인」 체력이 [40%/20%] 미만일 때 각각 [20%/40%] 피해 감소를 얻습니다.")
add("「拾骸者」生命加成+1000%，但无法再受到任何恢复/治疗", "「拾骸者」生命加成+1000%，但無法再受到任何恢復/治療",
    "Bonepicker: HP bonus +1000%, but can no longer receive any recovery/healing.",
    "「骸拾い」のHP補正+1000%。ただし、いかなる回復・治療も受けられなくなる。",
    "「습해자」 체력 보너스+1000%, 하지만 더 이상 어떠한 회복/치유도 받을 수 없습니다.")
add("「拾骸者」生命值每减少5%，攻击速度+10%（实时检测）", "「拾骸者」生命值每減少5%，攻擊速度+10%（即時檢測）",
    "Bonepicker: for every 5% HP lost, attack speed +10% (checked in real time).",
    "「骸拾い」のHPが5%減るごとに攻撃速度+10%（リアルタイム判定）。",
    "「습해자」 체력이 5% 줄어들 때마다 공격 속도+10%(실시간 판정).")
add("「裂隙使」攻击间隔延长100%，但额外伤害+200%（额外乘法计算）", "「裂隙使」攻擊間隔延長100%，但額外傷害+200%（額外乘法計算）",
    "Riftweaver: attack interval increased by 100%, but extra damage +200% (additional multiplicative calculation).",
    "「裂け目使い」の攻撃間隔が100%延長する代わりに、追加ダメージ+200%（追加の乗算）。",
    "「열극사」 공격 간격이 100% 길어지지만 추가 피해+200%(별도의 곱연산).")
add("「裂隙使」每秒进行蓄力，获得20%额外伤害，当进行攻击时清空蓄力", "「裂隙使」每秒進行蓄力，獲得20%額外傷害，當進行攻擊時清空蓄力",
    "Riftweaver: charges each second to gain 20% extra damage; attacking clears the charge.",
    "「裂け目使い」は毎秒力を溜め、20%の追加ダメージを得る。攻撃すると溜めをすべて消費する。",
    "「열극사」는 매초 충전하여 추가 피해 20%를 얻으며, 공격 시 충전이 모두 사라집니다.")
add("「回响客」进行攻击时有概率暴击2次造成「超暴击」（暴击后额外再判断一次暴击）", "「回響客」進行攻擊時有機率暴擊2次造成「超暴擊」（暴擊後額外再判斷一次暴擊）",
    "Echoist: attacks may critically hit 2 times to cause a Super Crit (one extra crit check after a critical hit).",
    "「残響客」は攻撃時、確率で会心が2回発生して「超会心」となる（会心後にもう1回会心判定を行う）。",
    "「메아리객」은 공격 시 확률적으로 치명타가 2번 발동하여 「초치명타」를 일으킵니다(치명타 후 한 번 더 치명타 판정).")
add("「回响客」每当有一个「拾骸者/封门人」职业存活时，射手攻击速度额外+25%", "「回響客」每當有一個「拾骸者/封門人」職業存活時，射手攻擊速度額外+25%",
    "Echoist: for each living Bonepicker/Gatewarden, the archer gains extra attack speed +25%.",
    "「残響客」は、生存している「骸拾い／門を封ずる者」1人につき射手の攻撃速度が追加で+25%。",
    "「메아리객」은 살아 있는 「습해자/봉문인」 한 명당 궁수의 공격 속도 추가+25%.")
add("「换面人」暴击率+25%", "「換面人」暴擊率+25%",
    "Facestealer: crit rate +25%.", "「面替え」の会心率+25%。", "「환면인」 치명타율+25%.")
add("「换面人」每次战斗免疫次数+10", "「換面人」每次戰鬥免疫次數+10",
    "Facestealer: immunity count +10 per battle.", "「面替え」の各戦闘の無効化回数+10。", "「환면인」 매 전투 면역 횟수+10.")
add("「司仪」治疗加成额外+35%", "「司儀」治療加成額外+35%",
    "Officiant: extra healing bonus +35%.", "「司式」の回復補正が追加で+35%。", "「사제」 치유 보너스 추가+35%.")
add("「司仪」存活时，在场角色生命加成+30%", "「司儀」存活時，在場角色生命加成+30%",
    "While an Officiant is alive, characters on the field gain HP bonus +30%.",
    "「司式」が生存している間、場にいるキャラクターのHP補正+30%。",
    "「사제」가 살아 있는 동안 전장에 있는 캐릭터의 체력 보너스+30%.")

--- 只查完整原文；简体、未知语言与未知原文原样返回，不做子串改写。
---@param source string
---@param lang string|nil
---@return string
function M.lookup(source, lang)
    local pack = dictionaries[lang or "zh_CN"]
    return (pack and pack[source]) or source
end

return M
