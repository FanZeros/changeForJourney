-- Extra UI + names + letter. Faithful-but-witty, no real-person names.
-- Loaded by I18n.lookup via I18nDict merge.
local D = { zh_TW = {}, en = {}, ja = {}, ko = {} }

local function add(zh, tw, en, ja, ko)
    D.zh_TW[zh] = tw
    D.en[zh] = en
    D.ja[zh] = ja
    D.ko[zh] = ko
end

-- ===== 奖励用途与离线结算来源 =====
add("小队%d · %s", "小隊%d · %s", "Squad %d · %s", "小隊%d・%s", "소대%d · %s")
add("用于角色转职、装备升阶和市场购买。", "用於角色轉職、裝備升階和市場購買。", "Used for class advancement, gear ascension, and market purchases.", "転職、装備昇格、マーケットでの購入に使用。", "전직, 장비 승급 및 시장 구매에 사용합니다.")
add("用于酒馆招募、神器宝箱和市场购买。", "用於酒館招募、神器寶箱和市場購買。", "Used for tavern recruitment, artifact chests, and market purchases.", "酒場の募集、神器宝箱、マーケットでの購入に使用。", "주점 모집, 신기 보물상자 및 시장 구매에 사용합니다.")
add("用于开启神器宝箱：普通宝箱每次1把，高级宝箱每次5把。每把钥匙的购买价格为150黑晶。", "用於開啟神器寶箱：普通寶箱每次1把，高級寶箱每次5把。每把鑰匙的購買價格為150黑晶。", "Opens artifact chests: 1 key for a normal chest, 5 for an advanced chest. Each key costs 150 black crystals.", "神器宝箱の開封に使用。通常は1回1本、上級は5本。鍵1本の価格は黒晶150個。", "신기 보물상자를 엽니다. 일반은 1회 1개, 고급은 5개가 필요합니다. 열쇠 1개 가격은 흑수정 150개입니다.")
add("用于扫荡已通关关卡：每券结算一场重复战斗奖励，不含首通奖励；主线与资源副本均按所选关卡计算。", "用於掃蕩已通關關卡：每券結算一場重複戰鬥獎勵，不含首通獎勵；主線與資源副本均按所選關卡計算。", "Sweeps a cleared stage. Each ticket grants one repeat battle's rewards, excluding first-clear rewards. Story and resource dungeons use the selected stage.", "クリア済みステージを掃討。券1枚で再戦1回分の報酬を獲得し、初回報酬は含みません。メインと資源ダンジョンは選択ステージで計算。", "완료한 스테이지를 소탕합니다. 표 1장으로 반복 전투 1회 보상을 받으며 첫 클리어 보상은 제외됩니다. 메인과 자원 던전 모두 선택한 스테이지를 기준으로 계산합니다.")
add("用于酒馆普通远征招募，每次招募消耗1张。", "用於酒館普通遠征招募，每次招募消耗1張。", "Used for normal tavern recruitment; 1 ticket per pull.", "酒場の通常遠征募集に使用。1回につき1枚消費。", "주점 일반 원정 모집에 사용합니다. 1회에 1장을 소비합니다.")
add("用于酒馆星辰招募，每次招募消耗1张。", "用於酒館星辰招募，每次招募消耗1張。", "Used for stellar tavern recruitment; 1 ticket per pull.", "酒場の星辰募集に使用。1回につき1枚消費。", "주점 성진 모집에 사용합니다. 1회에 1장을 소비합니다.")
add("用于酒馆商店兑换英雄碎片等物品。", "用於酒館商店兌換英雄碎片等物品。", "Exchanged for hero shards and other items in the tavern shop.", "酒場ショップで英雄の欠片などと交換。", "주점 상점에서 영웅 조각 등과 교환합니다.")
add("奥术材料，可在背包查看持有数量，当前没有消耗入口。", "奧術材料，可在背包查看持有數量，目前沒有消耗入口。", "An arcane material. View the amount in your bag; there is no current spending option.", "奥術素材。所持数は鞄で確認できます。現在は消費用途がありません。", "비전 재료입니다. 가방에서 보유량을 볼 수 있으며 현재 소비하는 곳은 없습니다.")
add("小队%d · %s · 暂停离线收益", "小隊%d · %s · 暫停離線收益", "Squad %d · %s · Offline income paused", "小隊%d・%s・オフライン報酬停止", "소대%d · %s · 오프라인 수익 중지")
add("通天塔 第%d层", "通天塔 第%d層", "Tower Floor %d", "通天塔・第%d層", "통천탑 %d층")
add("普通神器宝箱", "普通神器寶箱", "Normal Artifact Chest", "通常神器宝箱", "일반 신기 보물상자")
add("高级神器宝箱", "高級神器寶箱", "Advanced Artifact Chest", "上級神器宝箱", "고급 신기 보물상자")
add("直接开放", "直接開放", "Available immediately", "最初から開放", "즉시 개방")
add("通关普通%d-%d解锁", "通關普通%d-%d解鎖", "Clear Normal %d-%d to unlock", "ノーマル%d-%dクリアで開放", "일반 %d-%d 완료 시 개방")
add("每抽独立随机，无保底", "每抽獨立隨機，無保底", "Every pull is independent; no guaranteed drops", "毎回独立抽選・確定保証なし", "매회 독립 추첨, 확정 보상 없음")
add("%s：%s", "%s：%s", "%s: %s", "%s：%s", "%s: %s")
add("每次%d黑晶或%d把黄金钥匙", "每次%d黑晶或%d把黃金鑰匙", "%d black crystals or %d golden keys per pull", "1回につき黒晶%d個または黄金の鍵%d本", "1회 흑수정 %d개 또는 황금 열쇠 %d개")
add("优先使用钥匙，不足按150黑晶/把补齐", "優先使用鑰匙，不足按150黑晶/把補齊", "Keys first; pay 150 black crystals per missing key", "鍵を優先使用。不足分は1本につき黒晶150個", "열쇠 우선 사용, 부족분은 1개당 흑수정 150개로 충당")
add("普通宝箱每日免费单抽一次（UTC+8）", "普通寶箱每日免費單抽一次（UTC+8）", "One free normal pull daily (UTC+8)", "通常宝箱は毎日1回無料（UTC+8）", "일반 보물상자 매일 1회 무료（UTC+8）")
add("至臻品质不进入宝箱抽池", "至臻品質不進入寶箱抽池", "Supreme rarity is not in chest pools", "至臻品質は宝箱の抽選対象外", "지극 품질은 보물상자 추첨에 포함되지 않음")
add("普通神器宝箱每次1把，高级每次5把", "普通神器寶箱每次1把，高級每次5把", "Normal chests use 1 key; advanced chests use 5", "通常神器宝箱は1回1本、上級は5本", "일반 신기 보물상자는 1회 1개, 고급은 5개")
add("每把价值150黑晶", "每把價值150黑晶", "Each key is worth 150 black crystals", "1本あたり黒晶150個", "열쇠 1개는 흑수정 150개")
add("神器宝箱类型错误", "神器寶箱類型錯誤", "Invalid artifact chest type", "神器宝箱の種類が不正です", "신기 보물상자 유형 오류")
add("每日免费仅限普通神器宝箱", "每日免費僅限普通神器寶箱", "Daily free pulls are only for normal artifact chests", "毎日の無料抽選は通常神器宝箱のみ", "일일 무료는 일반 신기 보물상자만 가능")
add("神器支付方式错误", "神器支付方式錯誤", "Invalid artifact payment method", "神器の支払方法が不正です", "신기 결제 방식 오류")
add("获得时立即生效，持续24小时，使在线挂机收益提高20%；不提高离线收益。", "獲得時立即生效，持續24小時，使線上掛機收益提高20%；不提高離線收益。", "Activates immediately for 24 hours, increasing online idle income by 20%. Does not boost offline income.", "獲得時から24時間、オンライン放置報酬を20%増加。オフライン報酬には適用されません。", "획득 즉시 24시간 동안 온라인 방치 수익을 20% 높입니다. 오프라인 수익은 증가하지 않습니다.")
add("兼容存档中的退级保护材料，当前没有使用入口。", "相容存檔中的退級保護材料，目前沒有使用入口。", "Retained for legacy saves; no current use.", "既存セーブとの互換用素材。現在は使用不可。", "기존 저장 호환용 재료로 현재 사용처가 없습니다.")
add("用于对应部位装备升阶，提升装备主属性、固定副属性及普通随机词条。", "用於對應部位裝備升階，提升裝備主屬性、固定副屬性及普通隨機詞條。", "Ascends gear of the matching slot, improving its primary stat, fixed substats, and normal random affixes.", "対応部位の装備昇格に使用。主能力、固定副能力、通常ランダム効果を強化。", "해당 부위 장비를 승급하여 주 능력치, 고정 보조 능력치 및 일반 무작위 옵션을 강화합니다.")
add("可获得随机部位的装备升阶卷轴。", "可獲得隨機部位的裝備升階卷軸。", "Grants a gear ascension scroll for a random slot.", "ランダム部位の装備昇格巻物を獲得。", "무작위 부위 장비 승급 두루마리를 획득합니다.")
add("用于角色穿戴；可在铁匠铺升阶、洗练或分解。", "用於角色穿戴；可在鐵匠鋪升階、洗練或分解。", "Equipped by heroes; can be ascended, refined, or salvaged at the blacksmith.", "キャラの装備品。鍛冶屋で昇格、精錬、分解が可能。", "영웅이 착용합니다. 대장간에서 승급, 제련 또는 분해할 수 있습니다.")
add("用于招募对应英雄和英雄觉醒。", "用於招募對應英雄和英雄覺醒。", "Used to recruit and awaken the matching hero.", "対応する英雄の募集と覚醒に使用。", "해당 영웅 모집과 각성에 사용합니다.")

add("普通神器宝箱每次1把，高级每次5把；每把价值150黑晶。", "普通神器寶箱每次1把，高級每次5把；每把價值150黑晶。", "Normal artifact chests use 1 key, advanced chests use 5; each key is worth 150 black crystals.", "通常神器宝箱は1回1本、上級は5本。1本あたり黒晶150個。", "일반 신기 보물상자는 1회 1개, 고급은 5개이며 열쇠 1개는 흑수정 150개입니다.")
add("点击物品查看详情", "點擊物品查看詳情", "Tap an item for details", "アイテムをタップして詳細を表示", "아이템을 눌러 상세 정보 보기")
add("待鉴定装备", "待鑑定裝備", "Unidentified Gear", "未鑑定装備", "미감정 장비")
-- ===== 两段装备教学：战斗卡与队伍头像入口 =====
add("点击战斗中的己方角色卡，打开角色详情", "點擊戰鬥中的己方角色卡，開啟角色詳情",
    "Tap your hero's battle card to open their details", "戦闘中の味方カードをタップして詳細を開こう",
    "전투 중 아군 캐릭터 카드를 눌러 상세 정보를 여세요")
add("又掉落了新装备，点击右侧队伍头像打开角色详情", "又掉落了新裝備，點擊右側隊伍頭像開啟角色詳情",
    "New gear! Tap a squad portrait on the right to open hero details",
    "新しい装備を入手！右側の小隊アイコンからキャラ詳細を開こう",
    "새 장비를 획득했어요! 오른쪽 소대 초상화를 눌러 캐릭터 상세 정보를 여세요")

-- ===== 遗匣地点与奖励去向 =====
add("已入遗匣", "已入遺匣", "In coffer", "遺匣に保管", "유물함 보관")
add("遗匣领取", "遺匣領取", "Coffer rewards", "遺匣の受取", "유물함 수령")
add("已领取 %d 件装备", "已領取 %d 件裝備", "Claimed %d items", "%d点の装備を受取", "장비 %d개 수령")
add("回收 %d 件装备 · 精华 +%d", "回收 %d 件裝備 · 精華 +%d", "Salvaged %d items · Essence +%d", "%d点回収・精華 +%d", "장비 %d개 회수 · 정수 +%d")
add("背包已满，其余装备保留在遗匣", "背包已滿，其餘裝備保留在遺匣", "Bag full. Remaining gear stays in the coffer.", "鞄が満杯です。残りは遺匣に保管。", "가방이 가득 찼습니다. 나머지는 유물함에 보관됩니다.")
add("旅途所得，暂存于此", "旅途所得，暫存於此", "Treasures of the journey", "旅の戦利品をここに", "여정의 전리품 보관소")
add("挂机掉落与背包溢出装备均可在此领取", "掛機掉落與背包溢出裝備均可在此領取", "Collect idle drops and overflow gear here", "放置報酬と鞄に入らない装備を受取", "방치 보상과 가방 초과 장비를 수령하세요")
add("背包溢出 · 原装备暂存", "背包溢出 · 原裝備暫存", "Overflow · original gear", "鞄超過・元の装備を保管", "가방 초과 · 원본 장비 보관")
add("挂机掉落 · 装备已暂存", "掛機掉落 · 裝備已暫存", "Idle drop · stored gear", "放置報酬・装備を保管", "방치 보상 · 장비 보관")
add("继续远征，新的战利品会存放在这里", "繼續遠征，新的戰利品會存放在這裡", "Keep exploring. More loot awaits.", "遠征を続けて戦利品を集めよう", "원정을 계속하면 새 전리품이 보관됩니다")
add("切换分解模式", "切換分解模式", "Salvage mode", "分解モード", "분해 모드")
add("全部领取", "全部領取", "Claim all", "すべて受取", "모두 수령")

add("回收奖励", "回收獎勵", "Salvage rewards", "回収報酬", "회수 보상")
add("一键回收", "一鍵回收", "Salvage all", "一括回収", "일괄 회수")
add("一键领取", "一鍵領取", "Claim all", "一括受取", "일괄 수령")
add("领取筛选", "領取篩選", "Claim filtered", "絞込分を受取", "필터 수령")
add("回收筛选", "回收篩選", "Salvage filtered", "絞込分を回収", "필터 회수")
add("扫荡小队", "掃蕩小隊", "Sweep squad", "掃討小隊", "소탕 소대")
add("领取勾选", "領取勾選", "Claim checked", "チェック分を受取", "체크 수령")
add("回收勾选", "回收勾選", "Salvage checked", "チェック分を回収", "체크 회수")
add("共 %d 种品质", "共 %d 種品質", "%d rarities", "全%dレア度", "희귀도 %d종")
add("调整上方勾选或取消全部勾选查看全部", "調整上方勾選或取消全部勾選查看全部",
    "Adjust the checks above, or clear them all to view everything",
    "上部のチェックを調整、または全て外すと全表示", "위 체크를 조정하거나 모두 해제하면 전체 표시")
add("暂无该稀有度装备", "暫無該稀有度裝備", "No gear of this rarity", "このレア度の装備なし", "해당 희귀도 장비 없음")
add("回收", "回收", "Salvage", "回収", "회수")
add("取消回收", "取消回收", "Cancel salvage", "回収解除", "회수 취소")
add("切换回收", "切換回收", "Salvage mode", "回収モード", "회수 모드")
add("全部品质", "全部品質", "All rarities", "全レア度", "모든 희귀도")
add("确认一键回收", "確認一鍵回收", "Confirm salvage", "一括回収の確認", "일괄 회수 확인")
add("确认回收", "確認回收", "Salvage", "回収する", "회수 확인")
add("回收范围：%s装备", "回收範圍：%s裝備", "Scope: %s gear", "回収対象：%s装備", "회수 범위: %s 장비")
add("共 %d 件，回收后无法撤回", "共 %d 件，回收後無法撤回", "%d items. This cannot be undone.", "%d点。回収は取り消せません", "%d개. 회수 후 되돌릴 수 없습니다")
add("%s · 待领取 %d 件", "%s · 待領取 %d 件", "%s · %d to claim", "%s・受取待ち %d点", "%s · 수령 대기 %d개")
add(" · 待整理 %d 件", " · 待整理 %d 件", " · %d pending", "・整理待ち %d点", " · 정리 대기 %d개")
add(" · 回收模式", " · 回收模式", " · Salvage mode", "・回収モード", " · 회수 모드")
add("切换其他品质或查看全部装备", "切換其他品質或查看全部裝備", "Choose another rarity or view all gear", "別のレア度または全装備を表示", "다른 희귀도나 모든 장비를 선택하세요")
add("品质待整理", "品質待整理", "Rarity pending", "レア度整理待ち", "희귀도 정리 대기")
add("装备内容待整理", "裝備內容待整理", "Gear pending", "装備整理待ち", "장비 정리 대기")
add("暂不可领取或回收", "暫不可領取或回收", "Not ready to claim or salvage", "受取・回収は準備中", "아직 수령하거나 회수할 수 없습니다")
add("待整理", "待整理", "Pending", "整理待ち", "정리 대기")

-- ===== 漏翻 HUD / 属性 / 职业 =====
add("装备加成", "裝備加成", "Gear bonus", "装備補正", "장비 보너스")
add("暂无装备增益", "暫無裝備增益", "No gear bonuses", "装備補正なし", "장비 보너스 없음")
add("装备加成暂不可用", "裝備加成暫不可用", "Gear bonuses unavailable", "装備補正を表示できません", "장비 보너스를 표시할 수 없습니다")
add("运气", "運氣", "Luck", "運", "운")
add("精神", "精神", "Spirit", "精神", "정신")
add("智慧", "智慧", "Wit", "知力", "지혜")
add("终焉·？？", "終焉·？？", "Finality · ??", "終焉・？？", "종언·??")
add("远征点", "遠征點", "Expedition pts", "遠征P", "원정 포인트")
add("远征点不足", "遠征點不足", "Not enough expedition pts", "遠征P不足", "원정 포인트 부족")
add("余烬回春", "餘燼回春", "Ember Mend", "残り火の回春", "잔화 회복")
add("终焉圣愈", "終焉聖癒", "Final Benediction", "終焉の聖癒", "종언 성유")
add("终焉法盾", "終焉法盾", "Final Ward", "終焉の法盾", "종언 마방")
add("终焉奥术", "終焉奧術", "Final Arcana", "終焉の奥術", "종언 비전")
add("终焉破击", "終焉破擊", "Final Sunder", "終焉の破撃", "종언 파격")
add("终焉狩猎", "終焉狩獵", "Final Hunt", "終焉の狩猟", "종언 사냥")
add("终焉影步", "終焉影步", "Final Shadowstep", "終焉の影歩", "종언 영보")
add("终焉连斩", "終焉連斬", "Final Flurry", "終焉の連斬", "종언 연참")
add("全体生命加成+8%，每秒回血+10，体质+1；触发：生命低于30%时，每场战斗回复12%最大生命", "全體生命加成+8%，每秒回血+10，體質+1；觸發：生命低於30%時，每場戰鬥回復12%最大生命", "All HP+8%, regen+10, VIT+1; Trigger: below 30% HP, heal 12% max HP once per battle", "全体HP+8%、毎秒回復+10、体力+1；発動：HP30%未満で戦闘ごとに最大HP12%回復", "전체 생명+8%, 초당 회복+10, 체질+1; 발동: 생명 30% 미만 시 전투당 최대 생명 12% 회복")
add("全体治疗加成+16%，治疗暴击率+6%，护甲+4；触发：治疗生命低于40%的目标时，额外回复本次治疗15%", "全體治療加成+16%，治療暴擊率+6%，護甲+4；觸發：治療生命低於40%的目標時，額外回復本次治療15%", "All heal+16%, heal crit+6%, armor+4; Trigger: healing a target below 40% HP adds 15% of that heal", "全体回復+16%、回復会心+6%、防御+4；発動：HP40%未満を治療すると治療量15%を追加", "전체 회복+16%, 회복 치명+6%, 방어+4; 발동: 생명 40% 미만 치료 시 해당 회복의 15% 추가")
add("全体护盾加成+10%，魔法格挡概率+4%，护盾减伤+6%；触发：护盾被击破时，回复15%护盾上限，8秒冷却", "全體護盾加成+10%，魔法格擋機率+4%，護盾減傷+6%；觸發：護盾被擊破時，回復15%護盾上限，8秒冷卻", "All shield+10%, magic block+4%, shield DR+6%; Trigger: on shield break, restore 15% max shield, 8s CD", "全体盾+10%、魔法ガード+4%、盾軽減+6%；発動：盾破壊時に最大盾15%回復、CT8秒", "전체 보호막+10%, 마법 막기+4%, 보호막 감면+6%; 발동: 보호막 파괴 시 최대 보호막 15% 회복, 8초 쿨")
add("全体魔法伤害加成+16%，魔法暴击伤害+24%，魔法穿透+6；触发：魔法暴击时20%概率追加18%伤害", "全體魔法傷害加成+16%，魔法暴擊傷害+24%，魔法穿透+6；觸發：魔法暴擊時20%機率追加18%傷害", "All magic DMG+16%, magic crit DMG+24%, magic pen+6; Trigger: magic crit has 20% chance to add 18% damage", "全体魔法ダメージ+16%、魔法会心+24%、魔法貫通+6；発動：魔法会心時20%で18%追加ダメージ", "전체 마법 피해+16%, 마법 치명피해+24%, 마법 관통+6; 발동: 마법 치명타 시 20% 확률로 18% 추가 피해")
add("全体物理暴击伤害+32%，物理伤害加成+10%，物理穿透+8；触发：物理暴击时使目标护甲-8，持续4秒", "全體物理暴擊傷害+32%，物理傷害加成+10%，物理穿透+8；觸發：物理暴擊時使目標護甲-8，持續4秒", "All phys crit DMG+32%, phys DMG+10%, phys pen+8; Trigger: phys crit reduces target armor by 8 for 4s", "全体物理会心+32%、物理ダメージ+10%、物理貫通+8；発動：物理会心で対象防御-8、4秒", "전체 물리 치명피해+32%, 물리 피해+10%, 물리 관통+8; 발동: 물리 치명타 시 대상 방어 -8, 4초")
add("全体暴击率+4%，暴击伤害+20%，命中值+3，物理攻击加成+4%；触发：攻击生命低于35%的目标时追加12%伤害", "全體暴擊率+4%，暴擊傷害+20%，命中值+3，物理攻擊加成+4%；觸發：攻擊生命低於35%的目標時追加12%傷害", "All crit+4%, crit DMG+20%, hit+3, ATK+4%; Trigger: attacks on targets below 35% HP add 12% damage", "全体会心+4%、会心ダメージ+20%、命中+3、物理攻撃+4%；発動：HP35%未満への攻撃で12%追加", "전체 치명+4%, 치명 피해+20%, 명중+3, 물공+4%; 발동: 생명 35% 미만 공격 시 12% 추가 피해")
add("全体攻击速度+14%，闪避值+4，连击概率+8%；触发：闪避后攻击速度+12%，持续3秒，6秒冷却", "全體攻擊速度+14%，閃避值+4，連擊機率+8%；觸發：閃避後攻擊速度+12%，持續3秒，6秒冷卻", "All ASPD+14%, dodge+4, combo+8%; Trigger: after dodge, ASPD+12% for 3s, 6s CD", "全体攻撃速度+14%、回避+4、連撃+8%；発動：回避後攻撃速度+12%、3秒、CT6秒", "전체 공속+14%, 회피+4, 연격+8%; 발동: 회피 후 공속+12%, 3초, 6초 쿨")
add("全体连击概率+12%，连击增伤+8%，暴击率+3%；触发：连击命中时追加该次连击12%伤害", "全體連擊機率+12%，連擊增傷+8%，暴擊率+3%；觸發：連擊命中時追加該次連擊12%傷害", "All combo+12%, combo DMG+8%, crit+3%; Trigger: combo hits add 12% of that hit", "全体連撃+12%、連撃ダメージ+8%、会心+3%；発動：連撃命中時その12%を追加", "전체 연격+12%, 연격 피해+8%, 치명+3%; 발동: 연격 명중 시 해당 피해의 12% 추가")
add("致命", "致命", "Lethal", "致命", "치명")
add("急速", "急速", "Haste", "急速", "신속")
add("磨刃", "磨刃", "Hone", "刃研ぎ", "연마")
add("物理穿透", "物理穿透", "Phys pen", "物理貫通", "물리 관통")
add("魔法穿透", "魔法穿透", "Magic pen", "魔法貫通", "마법 관통")
add("治疗加成", "治療加成", "Heal bonus", "回復強化", "회복 보너스")
add("优质", "優質", "Fine", "上質", "우수")
add("至臻", "至臻", "Prime", "至高", "최상")
add("加载中...", "載入中...", "Loading...", "読み込み中...", "로딩 중...")
add("查看全图", "查看全圖", "View full image", "全体画像を見る", "전체 이미지 보기")
add("点击关闭", "點擊關閉", "Tap to close", "タップで閉じる", "눌러서 닫기")
add("已嵌合", "已嵌合", "Socketed", "嵌合済", "장착됨")
add("一转", "一轉", "1st seal", "一転", "1차")
add("二转", "二轉", "2nd seal", "二転", "2차")
add("不可转职", "不可轉職", "Can't convert", "転職不可", "전직 불가")
add("需要Lv", "需要Lv", "Need Lv", "必要Lv", "필요 Lv")
add("达到Lv", "達到Lv", "Reach Lv", "到達Lv", "도달 Lv")
add("级解锁", "級解鎖", "Lv unlock", "Lv解放", "Lv 해금")
add("级远征队员", "級遠征隊員", "Lv expeditioner", "Lv隊員", "Lv 원정대원")
add("远征等级达到", "遠征等級達到", "Expedition Lv", "遠征Lv", "원정 레벨")
add("远征等级 Lv.", "遠征等級 Lv.", "Expedition Lv.", "遠征Lv.", "원정 Lv.")
add("级及以下", "級及以下", "Lv and below", "Lv以下", "Lv 이하")
add("级星辰远征队员", "級星辰遠征隊員", "Lv Stardust Expeditioner", "Lv星辰遠征隊員", "Lv 성진 원정대원")
add("次招募必定获得", "次招募必定獲得", "pulls: guaranteed", "回で確定", "회 내 확정")
add("各品质基础概率：", "各品質基礎機率：", "Base rates:", "基礎確率：", "기본 확률:")
add("普通:", "普通:", "Common:", "ノーマル:", "일반:")
add("稀有:", "稀有:", "Rare:", "レア:", "레어:")
add("史诗:", "史詩:", "Epic:", "エピック:", "에픽:")
add("传说:", "傳說:", "Legendary:", "レジェンダリー:", "전설:")
add("是否使用黑晶快速购买", "是否使用黑晶快速購買", "Buy instantly with black crystal?", "黒晶で即購入？", "흑수정으로 즉시 구매?")
add("随机属性", "隨機屬性", "Random stat", "ランダム能力", "무작위 능력")
add("粉尘", "粉塵", "Dust", "粉塵", "가루")
add("精粹 +", "精粹 +", "Essence +", "精粋 +", "정수 +")
add("恢复 +", "恢復 +", "Regen +", "回復 +", "회복 +")
add("替换失败", "替換失敗", "Swap failed", "置換失敗", "교체 실패")
add("装备生成", "裝備生成", "Gear roll", "装備生成", "장비 생성")
add("治疗暴击率", "治療暴擊率", "Heal crit", "回復会心", "회복 치명타")
add("物理暴击率", "物理暴擊率", "Phys crit", "物理会心", "물리 치명타")
add("魔法暴击率", "魔法暴擊率", "Magic crit", "魔法会心", "마법 치명타")
add("远征团", "遠征團", "Expedition", "遠征団", "원정대")
add("封门人", "封門人", "Gatewarden", "門を封ずる者", "봉문인")
add("拾骸者", "拾骸者", "Bonepicker", "骸拾い", "습해자")
add("裂隙使", "裂隙使", "Riftweaver", "裂け目使い", "열극사")
add("回响客", "回響客", "Echoist", "残響客", "메아리객")
add("换面人", "換面人", "Facestealer", "面替え", "환면인")
add("司仪", "司儀", "Officiant", "司式", "사제")
add("岩龟", "岩龜", "Stone Turtle", "岩亀", "바위거북")
add("毒蛇", "毒蛇", "Viper", "毒蛇", "독사")
add("白鹿", "白鹿", "White Stag", "白鹿", "흰사슴")
add("灰狼", "灰狼", "Ash Wolf", "灰狼", "회색늑대")
add("猎鹰", "獵鷹", "Falcon", "鷹", "매")
add("终焉", "終焉", "Finality", "終焉", "종언")
add("本座", "本座", "True seat", "本座", "본좌")
add("仁心", "仁心", "Mercy", "仁心", "인심")
add("圣徽", "聖徽", "Sigil", "聖印", "성휘")
add("破甲稿", "破甲稿", "Sunder", "破甲", "파갑")
add("法盾", "法盾", "Wards", "法盾", "마방패")
add("秘法暴击", "秘法暴擊", "Arcane crit", "秘法会心", "비법 치명")
add("猎弓", "獵弓", "Longbow", "猟弓", "사냥활")
add("自愈", "自癒", "Mend", "自癒", "자유")
add("魔杖", "魔杖", "Wand", "魔杖", "마법봉")
add("战锤", "戰錘", "Warhammer", "戦槌", "전투망치")
add("魔焰", "魔焰", "Witchfire", "魔炎", "마염")
add("灵巧", "靈巧", "Nimble", "器用", "영교")
add("刚力", "剛力", "Might", "剛力", "강력")
add("体魄", "體魄", "Bulk", "体躯", "체백")
add("聪颖", "聰穎", "Bright", "聡明", "총영")
add("幸运草", "幸運草", "Clover", "四つ葉", "클로버")
add("冥想", "冥想", "Meditate", "瞑想", "명상")
add("连斩", "連斬", "Flurry", "連斬", "연참")
add("秘法注能", "秘法注能", "Infuse", "秘法付与", "비법 주입")
add("钻心箭", "鑽心箭", "Heartseeker", "心臓貫き", "심장화살")
add("门缝", "門縫", "Door-gap", "隙間", "문틈")
add("拾骸", "拾骸", "Scavenge", "拾骸", "습해")
add("裂隙", "裂隙", "Rift", "裂け目", "열극")
add("诊断结果", "診斷結果", "Diagnosis", "診断", "진단")
add("请先输入目标 UID", "請先輸入目標 UID", "Enter target UID first", "UIDを入力", "대상 UID 입력")
add("踢出", "踢出", "Kick", "追放", "추방")
add("封禁", "封禁", "Ban", "BAN", "차단")
add("解封", "解封", "Unban", "解除", "해제")
add("请输入邮件标题", "請輸入郵件標題", "Enter mail title", "件名を入力", "메일 제목 입력")
add("正常", "正常", "OK", "正常", "정상")
add("一键合成(", "一鍵合成(", "Craft all (", "一括合成(", "일괄 합성(")
add("全体力量+2", "全體力量+2", "All STR+2", "全体力+2", "전체 힘+2")
add("全体敏捷+2", "全體敏捷+2", "All AGI+2", "全体敏捷+2", "전체 민첩+2")
add("全体体质+2", "全體體質+2", "All VIT+2", "全体体力+2", "전체 체질+2")
add("全体智慧+2", "全體智慧+2", "All WIT+2", "全体知力+2", "전체 지혜+2")
add("全体运气+2", "全體運氣+2", "All LUK+2", "全体運+2", "전체 운+2")
add("全体精神+2", "全體精神+2", "All SPI+2", "全体精神+2", "전체 정신+2")
add("全体每秒回血+10", "全體每秒回血+10", "All regen+10/s", "全体回復+10/秒", "전체 초당회복+10")
add("全体连击概率+10%", "全體連擊機率+10%", "All combo+10%", "全体連撃+10%", "전체 연격+10%")
add("全体护甲+4", "全體護甲+4", "All armor+4", "全体装甲+4", "전체 방어+4")
add("全体护盾+28", "全體護盾+28", "All shield+28", "全体シールド+28", "전체 보호막+28")
add("全体魔法攻击加成+5%", "全體魔法攻擊加成+5%", "All MATK+5%", "全体魔法攻撃+5%", "전체 마공+5%")
add("全体物理攻击加成+5%", "全體物理攻擊加成+5%", "All ATK+5%", "全体物理攻撃+5%", "전체 물공+5%")
add("全体魔法伤害加成+10%", "全體魔法傷害加成+10%", "All magic DMG+10%", "全体魔法ダメージ+10%", "전체 마법 피해+10%")
add("全体物理伤害加成+10%", "全體物理傷害加成+10%", "All phys DMG+10%", "全体物理ダメージ+10%", "전체 물리 피해+10%")
add("全体魔法暴击伤害+20%", "全體魔法暴擊傷害+20%", "All magic crit DMG+20%", "全体魔法会心+20%", "전체 마법 치명피해+20%")
add("全体物理暴击伤害+20%", "全體物理暴擊傷害+20%", "All phys crit DMG+20%", "全体物理会心+20%", "전체 물리 치명피해+20%")
add("全体暴击伤害+15%", "全體暴擊傷害+15%", "All crit DMG+15%", "全体会心ダメージ+15%", "전체 치명 피해+15%")
add("全体攻击速度+8%", "全體攻擊速度+8%", "All ASPD+8%", "全体攻撃速度+8%", "전체 공속+8%")
add("获取途径：获取该远征队员", "獲取途徑：獲取該遠征隊員", "Source: recruit this hero", "入手：この隊員を獲得", "획득 경로: 해당 원정대원")
add("(已解锁)", "(已解鎖)", "(Unlocked)", "(解放済)", "(해금됨)")
add("(未解锁)", "(未解鎖)", "(Locked)", "(未解放)", "(미해금)")
add("洗练数值", "洗練數值", "Reroll values", "数値洗練", "수치 재련")
add("剩余敌人 ", "剩餘敵人 ", "Enemies left ", "残り敵 ", "남은 적 ")
add("狂暴中 剩余%.0fs", "狂暴中 剩餘%.0fs", "Berserk %.0fs", "狂暴 残り%.0fs", "광폭 %.0fs")
add("远征长！远征长！", "遠征長！遠征長！", "Marshal! Marshal!", "遠征長！遠征長！", "원정장! 원정장!")
add("→碎片×", "→碎片×", "→shards×", "→欠片×", "→조각×")
add("→酒馆币×", "→酒館幣×", "→coins×", "→コイン×", "→코인×")
add("/分钟", "/分鐘", "/min", "/分", "/분")
add(" 或 ", " 或 ", " or ", " または ", " 또는 ")
add("发送失败: ", "發送失敗: ", "Send failed: ", "送信失敗: ", "전송 실패: ")
add("操作失败: ", "操作失敗: ", "Failed: ", "失敗: ", "실패: ")
add("删除 ", "刪除 ", "Delete ", "削除 ", "삭제 ")
add("品质: ", "品質: ", "Rarity: ", "レア度: ", "등급: ")
add("灼烧 ", "灼燒 ", "Burn ", "灼熱 ", "화상 ")
add("暴击 ", "暴擊 ", "Crit ", "会心 ", "치명 ")
add("格挡 ", "格擋 ", "Block ", "ガード ", "막기 ")

-- ===== 六契转职显示名（ChurchClassChange 旧名也翻） =====
add("守誓者", "守誓者", "Oathkeeper", "誓い守", "수서자")
add("破阵者", "破陣者", "Linebreaker", "陣崩し", "파진자")
add("咒术师", "咒術師", "Hexer", "呪術師", "주술사")
add("夜猎者", "夜獵者", "Nightstalker", "夜狩り", "야렵자")
add("无痕者", "無痕者", "Unseen", "無痕", "무흔자")
add("提灯者", "提燈者", "Lampbearer", "灯持ち", "제등자")

-- ===== 信件（信达雅：冷幽默遗嘱，不直译公文） =====
add("致我从未谋面的孩子：", "致我從未謀面的孩子：", "To the child I never met:", "会ったことのない子へ：", "한 번도 못 본 아이에게:")
add("拆开这封信时，我已经死了。", "拆開這封信時，我已經死了。", "If you're reading this, I'm already dead.", "これを開く頃、私は死んでいる。", "이 편지를 펼칠 때면, 나는 이미 죽었다.")
add("按公会规矩，这叫「荣休」。", "按工會規矩，這叫「榮休」。", "Guild rules call it an “honorable retirement.”", "組合の決まりでは「栄休」という。", "공회 규정으로는 「영예로운 은퇴」란다.")
add("帽子、印鉴、名册，都留给你。", "帽子、印鑑、名冊，都留給你。", "The hat, the seal, the roster—yours now.", "帽子も印も名冊も、お前のものだ。", "모자, 인장, 명부, 다 네 것이다.")
add("塔底下的东西不讲道理，", "塔底下的東西不講道理，", "What lives under the tower does not argue.", "塔の下の連中は理屈が通じない。", "탑 아래 것들은 도리가 없다.")
add("但他们够吵。", "但他們夠吵。", "They are, however, extremely loud.", "だが、とにかくうるさい。", "다만 아주 시끄럽다.")
add("公会不需要英雄，", "工會不需要英雄，", "The guild does not need a hero,", "組合に英雄は要らない。", "공회는 영웅이 필요 없다.")
add("需要一个签字的傻子。", "需要一個簽字的傻子。", "It needs a fool who will sign.", "サインする馬鹿が一人いればいい。", "서명할 바보 하나면 된다.")
add("——第三十六任远征长，你的外祖父", "——第三十六任遠征長，你的外祖父", "— 36th Marshal, your grandfather", "——第三十六代遠征長、お前の祖父", "——제36대 원정장, 너의 외조부")

-- ===== 角色名（梗味保留，不露真名） =====
add("大狗嚼", "大狗嚼", "Chewchow", "ワン噛み", "큰개씹")
add("黄桃龙", "黃桃龍", "Peach Drake", "黄桃竜", "황도룡")
add("叮咚鸡", "叮咚雞", "Dingdong", "ピンポン鶏", "띵동닭")
add("接化发掌门", "接化發掌門", "Master Bounce", "接化発掌門", "접화발 장문")
add("叠甲怪", "疊甲怪", "Stackplate", "重ね甲", "겹갑괴")
add("压一压", "壓一壓", "Press-a-Beat", "プレスビート", "눌러비트")
add("压一压碎片", "壓一壓碎片", "Press-a-Beat Shard", "プレスビートの欠片", "눌러비트 조각")
add("压一压-碎片", "壓一壓-碎片", "Press-a-Beat Shard", "プレスビートの欠片", "눌러비트 조각")
add("压一压的碎片", "壓一壓的碎片", "Press-a-Beat's Shard", "プレスビートの欠片", "눌러비트의 조각")
add("Are you OK~？压一压~", "Are you OK~？壓一壓~", "Are you OK~? Press-a-Beat~",
    "Are you OK~？プレスビート~", "Are you OK~? 눌러비트~")
add("信光机兵", "信光機兵", "Timer Trooper", "信光機兵", "신광기병")
add("愤怒的小雀", "憤怒的小雀", "Rage Sparrow", "怒り雀", "분노참새")
add("卡皮巴拉", "卡皮巴拉", "Capyboss", "カピバラ", "카피바라")
add("铁憨憨", "鐵憨憨", "Iron Doof", "鉄おバカ", "철한한")
add("熬夜冠军", "熬夜冠軍", "All-Nighter", "徹夜王", "올나잇 챔프")
add("雪皇", "雪皇", "Snow Empress", "雪皇", "설황")
add("弹弹弹", "彈彈彈", "Boingboing", "弾弾弾", "탱탱탱")
add("内鬼", "內鬼", "Mole", "内通者", "내부자")
add("复活吧爱人", "復活吧愛人", "Rise, Beloved", "よみがえれ恋人", "부활하라 연인")
add("蓝色大肥鱼", "藍色大肥魚", "Blue Fatfish", "青の大魚", "파란 큰물고기")
add("万剑归宗", "萬劍歸宗", "Myriad Swords", "万剣帰宗", "만검귀종")
add("摘星星星人", "摘星星星人", "Starpicker", "星摘み人", "별따기인")
add("雷电麦坤", "閃電賣雞", "Thunder Drumstick", "稲妻唐揚げ", "번개치킨")
add("小黑子", "小黑子", "Lil' Crow", "黒子くん", "꼬마흑자")
add("真布诗人", "真布詩人", "Trueverse", "真布詩人", "진포시인")

-- ===== 称号 =====
add("汪卫先锋", "汪衛先鋒", "Barkguard Vanguard", "ワン衛先鋒", "멍경비 선봉")
add("火球一本龙", "火球一本龍", "One-Spell Dragon", "火球一本書", "화구 한 권 용")
add("等通知哨兵", "等通知哨兵", "Awaiting Notice", "連絡待ち哨兵", "합격통보 보초")
add("浑元形意宗师", "渾元形意宗師", "Hunyuan Grandmaster", "渾元形意宗師", "혼원형의 종사")
add("叠甲战神", "疊甲戰神", "Stackplate War-god", "重ね甲の戦神", "겹갑 전신")
add("电音天后", "電音天后", "Bass Empress", "電音の天后", "일렉 여제")
add("光之巨人", "光之巨人", "Giant of Light", "光の巨人", "빛의 거인")
add("弹弓怒鸟", "彈弓怒鳥", "Slingshot Fury", "パチンコ怒鳥", "새총 성난새")
add("温泉教主", "溫泉教主", "Hot-spring Pontiff", "温泉教主", "온천교주")
add("扛门大将军", "扛門大將軍", "Door-bearer General", "門担ぎ大将", "문짝 대장군")
add("熬夜修仙党", "熬夜修仙黨", "Night-cultivator", "徹夜修仙党", "철야 수선파")
add("甜蜜冰后", "甜蜜冰後", "Sugar Ice Queen", "甘い氷后", "달콤 빙후")
add("鱼尾纹克星", "魚尾紋剋星", "Crow's-feet Killer", "しわ潰し", "잔주름 킬러")
add("藏得最深的人", "藏得最深的人", "The Deepest Cover", "最も深く潜む者", "가장 깊이 숨은 자")
add("急救复活甲", "急救復活甲", "Crash-rez Plate", "救急蘇生甲", "응급 부활갑")
add("爱吃白饭的摸鱼员", "愛吃白飯的摸魚員", "Rice-only Slacker", "白米好きのサボり", "흰밥 좋아하는 농땡이")
add("御剑飞行家", "御劍飛行家", "Sword-rider", "御剣飛行家", "어검 비행가")
add("太空出差人", "太空出差人", "Space on Business", "宇宙出張員", "우주 출장인")
add("赛道之王", "賽道之王", "King of the Strip", "コースの王", "트랙의 왕")
add("两年半练习生", "兩年半練習生", "Two-and-a-half-year Trainee", "二年半練習生", "2년반 연습생")
add("即兴说唱王", "即興說唱王", "Freestyle King", "即興ラップ王", "즉흥 랩왕")

-- ===== 天赋短名（机制感，不直译拼音） =====
add("衔骨狂", "銜骨狂", "Bone-in-mouth", "銜骨狂", "뼈문 광")
add("一本火球", "一本火球", "One Fireball", "火球一冊", "화구 한 권")
add("已读不回", "已讀不回", "Seen, No Reply", "既読スルー", "읽씹")
add("化劲", "化勁", "Turn-force", "化勁", "화경")
add("叠甲", "疊甲", "Stackplate", "重ね甲", "겹갑")
add("安可", "安可", "Encore", "アンコール", "앙코르")
add("必杀蓄力", "必殺蓄力", "Finisher Charge", "必殺溜め", "필살 축력")
add("仇册", "仇冊", "Grudge Ledger", "仇帳", "원수명부")
add("温泉", "溫泉", "Hot Spring", "温泉", "온천")
add("扛门", "扛門", "Door Carry", "門担ぎ", "문짝")
add("通宵斩", "通宵斬", "All-night Cut", "徹夜斬", "철야참")
add("冰雕术", "冰雕術", "Ice Sculpture", "氷彫術", "빙조술")
add("抄作业", "抄作業", "Copy Homework", "宿題コピー", "숙제 베끼기")
add("圣光复活", "聖光復活", "Holy Rez", "聖光蘇生", "성광 부활")
add("高压水枪", "高壓水槍", "Pressure Hose", "高圧放水", "고압 물총")
add("万剑", "萬劍", "Myriad Blades", "万剣", "만검")
add("出差星门", "出差星門", "Business Stargate", "出張星門", "출장 성문")
add("氮气", "氮氣", "NOS", "ニトロ", "아산화질소")
add("两年半连打", "兩年半連打", "2.5-Year Combo", "二年半連打", "2년반 연타")
add("护盾说唱", "護盾說唱", "Shield Rap", "シールドラップ", "보호막 랩")

-- ===== 觉醒/基础天赋原文同步，不将觉醒效果塞回基础详情 =====
add("【水压图鉴】：每次击杀永久魔法攻击+0.2；潮湿目标受到的伤害加成由20%提升至30%，持续时间延长至3秒。",
    "【水壓圖鑑】：每次擊殺永久魔法攻擊+0.2；潮濕目標受到的傷害加成由20%提升至30%，持續時間延長至3秒。",
    "[Water Pressure Ledger]: Each kill permanently grants +0.2 Magic ATK. Wet targets take 30% extra damage instead of 20%, lasting 3 seconds.",
    "【水圧図鑑】：撃破ごとに魔法攻撃が永久に+0.2。濡れた対象の被ダメージ増加が20%から30%になり、持続が3秒に延長。",
    "[수압 도감]: 처치할 때마다 마법 공격력이 영구적으로 +0.2. 젖은 대상의 받는 피해 증가가 20%에서 30%로 오르고 지속 시간이 3초로 늘어납니다.")
add("过量治疗先补足目标护盾，超过护盾上限的部分再转为临时护盾（最多为目标护盾上限的50%）。",
    "過量治療先補足目標護盾，超過護盾上限的部分再轉為臨時護盾（最多為目標護盾上限的50%）。",
    "Overhealing first restores the target's shield. Excess beyond its cap becomes a temporary shield, up to 50% of the target's shield cap.",
    "過剰回復はまず対象のシールドを補充し、上限を超えた分を一時シールドに変換する（対象のシールド上限の50%まで）。",
    "초과 치유는 먼저 대상의 보호막을 채우고, 보호막 상한을 넘는 양은 임시 보호막으로 전환됩니다(대상 보호막 상한의 최대 50%).")

-- ===== 传说觉醒：保留旧效果并追加专属联动 =====
add("飞剑命中时有10%概率将本柄伤害计入下次飞剑；触发间隔缩短至3秒，基础每轮最多7柄。【剑冢列阵】：剑冢每40层额外召唤1柄飞剑，最多额外5柄。",
    "飛劍命中時有10%機率將本柄傷害計入下次飛劍；觸發間隔縮短至3秒，基礎每輪最多7柄。【劍冢列陣】：劍冢每40層額外召喚1柄飛劍，最多額外5柄。",
    "Flying sword hits have a 10% chance to carry their damage into the next volley. Interval: 3s; up to 7 base swords per volley. [Sword Tomb Formation]: Every 40 Sword Tomb stacks adds 1 sword, up to 5 extra.",
    "飛剣命中時、10%の確率でそのダメージを次の飛剣に持ち越す。発動間隔3秒、基本の飛剣は1回最大7本。【剣塚の陣】：剣塚40層ごとに飛剣1本追加、最大5本追加。",
    "비검 적중 시 10% 확률로 해당 피해를 다음 비검에 이월합니다. 발동 간격 3초, 기본 비검은 회당 최대 7자루. [검총 진형]: 검총 40중첩마다 비검 1자루 추가, 최대 5자루 추가.")
add("飞剑命中后的飞回概率提升至50%。【万剑天倾】：剑冢提供的飞剑伤害比例加成翻倍；每第3轮飞剑额外发射一轮等伤剑雨，剑雨不触发飞回或伤害记录。",
    "飛劍命中後的飛回機率提升至50%。【萬劍天傾】：劍冢提供的飛劍傷害比例加成翻倍；每第3輪飛劍額外發射一輪等傷劍雨，劍雨不觸發飛回或傷害記錄。",
    "Flying sword return chance rises to 50%. [Heavenfall]: Doubles the sword damage coefficient gained from Sword Tomb. Every third volley fires an extra sword rain for equal damage; it cannot return or record damage.",
    "命中後の飛剣帰還率が50%になる。【万剣天墜】：剣塚による飛剣ダメージ倍率の成長分が2倍。3回目の斉射ごとに同ダメージの剣雨を追加。剣雨は帰還やダメージ記録を発動しない。",
    "비검 적중 후 귀환 확률이 50%로 증가합니다. [만검천경]: 검총의 비검 피해 계수 성장 보너스가 2배. 세 번째 일제사격마다 같은 피해의 검우를 추가 발사하며 귀환이나 피해 기록을 발동하지 않습니다.")
add("星门基础伤害提升至400%，开战时开启2扇门；星门成长每累计40层额外增加1扇，总数最多3扇。角色阵亡后星门仍可攻击。【殖民共振】：每轮星门发射后，每扇门为下一轮留下1层星痕。",
    "星門基礎傷害提升至400%，開戰時開啟2扇門；星門成長每累計40層額外增加1扇，總數最多3扇。角色陣亡後星門仍可攻擊。【殖民共振】：每輪星門發射後，每扇門為下一輪留下1層星痕。",
    "Stargate base damage rises to 400%. Start with 2 gates; every 40 growth stacks adds a gate, up to 3. Gates keep attacking after the hero dies. [Colony Resonance]: Each gate leaves 1 Star Mark for the next volley.",
    "星門の基礎ダメージ400%、開戦時2門。成長40層ごとに1門追加、合計最大3門。本人の死亡後も攻撃する。【植民共振】：斉射後、各星門が次の斉射に星痕1層を残す。",
    "성문 기본 피해가 400%로 증가하며 시작 시 2개 개방. 성장 40중첩마다 1개 추가, 최대 3개. 영웅 사망 후에도 공격합니다. [식민 공진]: 일제사격 후 각 성문이 다음 사격에 별흔 1중첩을 남깁니다.")
add("星象共鸣效果提升50%。【群星坍缩】：觉醒1的星门伤害成长加成翻倍，每层星痕增伤由12%提升至24%；满5层星痕发射时，额外对最多4名敌人各造成首扇成功星门本轮发射伤害的150%。",
    "星象共鳴效果提升50%。【群星坍縮】：覺醒1的星門傷害成長加成翻倍，每層星痕增傷由12%提升至24%；滿5層星痕發射時，額外對最多4名敵人各造成首扇成功星門本輪發射傷害的150%。",
    "Astral Resonance is 50% stronger. [Stellar Collapse]: Doubles Awakening I's stargate damage growth. Star Marks grant 24% damage per stack instead of 12%. Firing with 5 marks also hits up to 4 enemies for 150% of the first successfully fired gate's damage this volley each.",
    "星象共鳴の効果が50%増加。【群星崩壊】：覚醒Ⅰの星門ダメージ成長分が2倍。星痕1層の増傷が12%から24%に。星痕5層で斉射すると、敵最大4体に最初に発射成功した星門の今回の発射ダメージの150%を追加。",
    "성상 공명 효과 50% 증가. [군성 붕괴]: 각성Ⅰ의 성문 피해 성장 보너스가 2배. 별흔 중첩당 피해 증가가 12%에서 24%로 증가. 5중첩 사격 시 적 최대 4명에게 이번에 처음 발사에 성공한 성문의 발사 피해 150%를 각각 추가로 가합니다.")
add("延迟结算缩短至1.2秒；结算时若目标生命比例低于出手时，该次延迟伤害提高50%。【补偿增幅】：丢包补偿每累计1次成长，使延迟包伤害额外提高0.5%，最多提高200%。",
    "延遲結算縮短至1.2秒；結算時若目標生命比例低於出手時，該次延遲傷害提高50%。【補償增幅】：丟包補償每累計1次成長，使延遲包傷害額外提高0.5%，最多提高200%。",
    "Delayed damage resolves after 1.2s. If the target's HP ratio has fallen since firing, damage increases by 50%. [Compensation Amplifier]: Each Packet Compensation growth stack grants 0.5% extra packet damage, up to +200%.",
    "遅延精算が1.2秒に短縮。発射時より対象のHP割合が低ければ遅延ダメージ+50%。【補償増幅】：パケット補償の成長1層につき遅延パケットのダメージ+0.5%、最大+200%。",
    "지연 정산이 1.2초로 단축. 정산 시 대상의 생명력 비율이 발사 시보다 낮으면 지연 피해 50% 증가. [보상 증폭]: 패킷 보상 성장 1중첩마다 지연 패킷 피해 0.5% 추가 증가, 최대 +200%.")
add("延迟结算时若目标生命低于30%，该次延迟伤害再提高25%。【可靠传输】：补偿增幅提升为每层1%、最多400%；目标阵亡时延迟包转向其他存活敌人，结算后0.6秒重传一次等量伤害，重传不再次生成延迟包。",
    "延遲結算時若目標生命低於30%，該次延遲傷害再提高25%。【可靠傳輸】：補償增幅提升為每層1%、最多400%；目標陣亡時延遲包轉向其他存活敵人，結算後0.6秒重傳一次等量傷害，重傳不再次生成延遲包。",
    "Delayed damage gains another 25% if the target is below 30% HP. [Reliable Transmission]: Compensation grants 1% per stack, up to +400%. Packets retarget living enemies if their target dies, then retransmit equal damage once after 0.6s. Retransmissions cannot create more packets.",
    "精算時に対象HPが30%未満なら遅延ダメージがさらに25%増加。【信頼伝送】：補償増幅が1層につき1%、最大400%に。対象死亡時は生存敵に転送し、精算0.6秒後に同ダメージを1回再送。再送は遅延パケットを生成しない。",
    "지연 정산 시 대상 생명력이 30% 미만이면 피해가 추가로 25% 증가. [신뢰 전송]: 보상 증폭이 중첩당 1%, 최대 400%로 증가. 대상 사망 시 살아 있는 적에게 전환하고 정산 0.6초 후 같은 피해를 한 번 재전송. 재전송은 새 지연 패킷을 만들지 않습니다.")

-- ===== 史诗觉醒Ⅱ：保留旧正文并追加成长联动，Ⅲ不改 =====
add("生命较低时护甲+12；开战生命加成提升至35%。【门板罩】：分摊回血成功后获得独立护罩，持续3秒，护罩量为最大生命的4%；门板每累计1次分摊成长，护罩比例+0.25个百分点，总比例最高8%。沿原3秒冷却刷新，不叠加。",
    "生命較低時護甲+12；開戰生命加成提升至35%。【門板罩】：分攤回血成功後獲得獨立護罩，持續3秒，護罩量為最大生命的4%；門板每累計1次分攤成長，護罩比例+0.25個百分點，總比例最高8%。沿原3秒冷卻刷新，不疊加。",
    "Armor +12 at low HP; the starting HP bonus rises to 35%. [Door Ward]: Successfully healing from shared damage grants a separate ward for 3s, equal to 4% of max HP. Each accumulated Door growth from sharing damage adds 0.25 percentage points, up to 8% total. Refreshes on the original 3s cooldown; does not stack.",
    "低HP時に防御+12、開戦時のHP補正が35%に上昇。【門板の護り】：肩代わりによるHP回復に成功すると、最大HPの4%の独立した護りを3秒間獲得。門板の肩代わり成長1回ごとに割合+0.25ポイント、合計最大8%。元の3秒クールダウンに従って更新し、重複しない。",
    "생명력이 낮으면 방어력 +12, 전투 시작 생명력 보너스가 35%로 증가. [문짝 수호]: 피해 분담 회복에 성공하면 최대 생명력의 4%인 독립 수호막을 3초간 얻습니다. 누적 문짝 분담 성장 1회마다 비율 +0.25%p, 총 최대 8%. 기존 3초 재사용 대기시간에 따라 갱신되며 중첩되지 않습니다.")
add("通宵斩击杀可记录斩影（最多4道）；物理暴击率+10%、暴击伤害+35%。【斩影追斩】：每2道已存斩影追加1次追斩，最多2次；各复制本轮对应普通单斩伤害的50%，继承暴击，不递归。觉醒Ⅰ每累计50次通宵斩击杀，追斩增伤12.5%，最多50%，最高为普通单斩本轮伤害的75%。",
    "通宵斬擊殺可記錄斬影（最多4道）；物理暴擊率+10%、暴擊傷害+35%。【斬影追斬】：每2道已存斬影追加1次追斬，最多2次；各複製本輪對應普通單斬傷害的50%，繼承暴擊，不遞迴。覺醒Ⅰ每累計50次通宵斬擊殺，追斬增傷12.5%，最多50%，最高為普通單斬本輪傷害的75%。",
    "All-night Cut kills store slash shadows (up to 4); Physical Crit +10%, Crit DMG +35%. [Shadow Follow-up]: Every 2 stored shadows adds 1 follow-up, up to 2. Each copies 50% of its corresponding normal slash's damage this volley, inherits its crit, and cannot recurse. Every 50 Awakening I All-night Cut kills boosts follow-up damage by 12.5%, up to +50%, for at most 75% of the normal slash's damage this volley.",
    "徹夜斬の撃破で斬影を記録（最大4本）。物理会心率+10%、会心ダメージ+35%。【斬影の追撃】：保存した斬影2本ごとに追撃1回追加、最大2回。各追撃は今回の対応する通常単斬のダメージの50%を複製し、会心を継承。再帰しない。覚醒Ⅰの徹夜斬撃破50回ごとに追撃ダメージ+12.5%、最大+50%、今回の通常単斬ダメージの最大75%。",
    "철야참 처치 시 참격 그림자를 기록(최대 4개). 물리 치명타 확률 +10%, 치명타 피해 +35%. [그림자 추격]: 저장된 그림자 2개마다 추격 1회 추가, 최대 2회. 각각 이번 연속참의 대응하는 일반 단일 참격 피해 50%를 복사하고 치명타를 계승하며 재귀하지 않습니다. 각성Ⅰ 철야참 처치 누적 50회마다 추격 피해 +12.5%, 최대 +50%로 이번 일반 단일 참격 피해의 최대 75%.")
add("冰冻目标被击杀时生成冰雕（最多3座）；冰雕可替队友抵挡一次伤害，碎裂时冰冻敌人。首次冰冻延长2秒；自身首次低于半血时冰冻全场3秒。【碎冰回响】：冰雕挡伤碎裂时，对最多3名不同存活敌人各造成魔法攻击×攻击系数×80%的冰伤；觉醒Ⅰ每累计50次击杀，此伤害提高10%，最多40%，最高系数112%。",
    "冰凍目標被擊殺時生成冰雕（最多3座）；冰雕可替隊友抵擋一次傷害，碎裂時冰凍敵人。首次冰凍延長2秒；自身首次低於半血時冰凍全場3秒。【碎冰回響】：冰雕擋傷碎裂時，對最多3名不同存活敵人各造成魔法攻擊×攻擊係數×80%的冰傷；覺醒Ⅰ每累計50次擊殺，此傷害提高10%，最多40%，最高係數112%。",
    "Killing frozen targets creates ice statues (up to 3). Each blocks one hit for an ally and freezes enemies when shattered. First freeze lasts 2s longer; first falling below half HP freezes all enemies for 3s. [Shatter Echo]: Shattering while blocking damage deals Magic ATK × attack coefficient × 80% Ice damage to each of up to 3 distinct living enemies. Every 50 Awakening I kills boosts this damage by 10%, up to +40%, for a maximum coefficient of 112%.",
    "凍結した対象の撃破で氷像を生成（最大3体）。味方のダメージを1回防ぎ、砕けると敵を凍結。初回凍結が2秒延長。自身のHPが初めて半分未満になると敵全体を3秒凍結。【砕氷の残響】：氷像がダメージを防いで砕けると、異なる生存敵最大3体それぞれに魔法攻撃×攻撃係数×80%の氷ダメージ。覚醒Ⅰの撃破50回ごとにこのダメージ+10%、最大+40%、係数は最大112%。",
    "빙결 대상 처치 시 얼음 조각상 생성(최대 3개). 아군 피해를 한 번 막고 부서질 때 적을 빙결시킵니다. 첫 빙결 2초 연장, 자신이 처음 절반 생명력 미만이 되면 적 전체를 3초 빙결. [쇄빙 메아리]: 피해를 막고 부서지면 서로 다른 살아 있는 적 최대 3명에게 각각 마법 공격력×공격 계수×80%의 얼음 피해. 각성Ⅰ 처치 누적 50회마다 이 피해 +10%, 최대 +40%로 계수 최대 112%.")
add("弹射击杀积累分裂层，每8层额外弹射一次（最多+5）；物理攻击加成+25%、攻击速度+25%。【分裂增幅】：各次弹跳伤害系数+10个百分点；每累计50次分裂击杀，再+5个百分点，成长最多+20个百分点。",
    "彈射擊殺積累分裂層，每8層額外彈射一次（最多+5）；物理攻擊加成+25%、攻擊速度+25%。【分裂增幅】：各次彈跳傷害係數+10個百分點；每累計50次分裂擊殺，再+5個百分點，成長最多+20個百分點。",
    "Ricochet kills build Split stacks; every 8 stacks adds 1 bounce, up to +5. Physical ATK bonus +25%, Attack Speed +25%. [Split Amplifier]: Each bounce's damage coefficient gains 10 percentage points. Every 50 accumulated Split kills adds another 5 percentage points, with growth capped at +20 percentage points.",
    "跳弾撃破で分裂層を蓄積し、8層ごとに跳弾1回追加（最大+5回）。物理攻撃補正+25%、攻撃速度+25%。【分裂増幅】：各跳弾のダメージ係数+10ポイント。累計分裂撃破50回ごとにさらに+5ポイント、成長分は最大+20ポイント。",
    "도탄 처치로 분열 중첩을 쌓으며 8중첩마다 도탄 1회 추가(최대 +5회). 물리 공격력 보너스 +25%, 공격 속도 +25%. [분열 증폭]: 각 도탄 피해 계수 +10%p. 누적 분열 처치 50회마다 추가 +5%p, 성장분 최대 +20%p.")
add("开战获得10次受击免疫；敌人死亡后额外获得1至2次免疫。每次敌人死亡暴击伤害+10%，最多+100%。【满分抄袭】：本场偷取攻速满40%后，暴击追加主攻伤害15%的暗影副包；觉醒Ⅰ每累计50次暴击击杀，副包比例+5个百分点，最高30%。",
    "開戰獲得10次受擊免疫；敵人死亡後額外獲得1至2次免疫。每次敵人死亡暴擊傷害+10%，最多+100%。【滿分抄襲】：本場偷取攻速滿40%後，暴擊追加主攻傷害15%的暗影副包；覺醒Ⅰ每累計50次暴擊擊殺，副包比例+5個百分點，最高30%。",
    "Start with immunity to 10 hits; each enemy death grants 1–2 more. Each enemy death grants +10% Crit DMG, up to +100%. [Perfect Copy]: Once stolen Attack Speed reaches 40% this battle, crits add a Shadow packet for 15% of the main hit's damage. Every 50 Awakening I crit kills adds 5 percentage points to the packet ratio, up to 30%.",
    "開戦時に10回の被弾無効を獲得。敵死亡後にさらに1～2回獲得。敵死亡ごとに会心ダメージ+10%、最大+100%。【満点コピー】：この戦闘で奪った攻撃速度が40%に達すると、会心時に主攻撃ダメージの15%の影追加ダメージ。覚醒Ⅰの会心撃破50回ごとに追加割合+5ポイント、最大30%。",
    "전투 시작 시 피격 10회 면역, 적 사망 후 추가 1~2회 면역. 적 사망마다 치명타 피해 +10%, 최대 +100%. [만점 베끼기]: 이번 전투에서 훔친 공격 속도가 40%에 도달하면 치명타에 주 공격 피해 15%의 암흑 추가 패킷이 붙습니다. 각성Ⅰ 치명타 처치 누적 50회마다 패킷 비율 +5%p, 최대 30%.")
add("为复活的队友留下一次濒死保护；复活概率提升至60%，复活时获得相当于最大生命20%的护盾，持续5秒。【爱人护佑】：上述复活护盾额外+5个百分点；觉醒Ⅰ每累计1次已提交的正常复活成长，再+0.5个百分点，成长最多+15个百分点，总比例最高40%。普通复活与救援票复活均享此护盾强化，持续5秒。",
    "為復活的隊友留下一次瀕死保護；復活機率提升至60%，復活時獲得相當於最大生命20%的護盾，持續5秒。【愛人護佑】：上述復活護盾額外+5個百分點；覺醒Ⅰ每累計1次已提交的正常復活成長，再+0.5個百分點，成長最多+15個百分點，總比例最高40%。普通復活與救援票復活均享此護盾強化，持續5秒。",
    "Revived allies gain one near-death protection. Revive chance rises to 60%; revival grants a shield equal to 20% of max HP for 5s. [Beloved's Ward]: This revive shield gains 5 percentage points. Each accumulated, committed normal-revival growth in Awakening I adds another 0.5 percentage points, with growth capped at +15 points and the total at 40%. Both normal and rescue-ticket revivals receive this shield boost for 5s.",
    "蘇生した味方に1回の瀕死保護。蘇生率が60%になり、蘇生時に最大HPの20%のシールドを5秒獲得。【愛人の加護】：この蘇生シールドの割合+5ポイント。覚醒Ⅰの確定反映された通常蘇生成長1回ごとにさらに+0.5ポイント、成長分は最大+15ポイント、合計最大40%。通常蘇生と救援券蘇生の両方にこの強化を適用し、5秒持続。",
    "부활한 아군에게 빈사 보호 1회 부여. 부활 확률 60%로 증가, 부활 시 최대 생명력의 20%인 보호막을 5초 획득. [연인의 가호]: 이 부활 보호막 비율 +5%p. 각성Ⅰ에서 확정 반영된 일반 부활 성장 누적 1회마다 추가 +0.5%p, 성장분 최대 +15%p, 총 최대 40%. 일반 부활과 구조권 부활 모두 이 보호막 강화를 5초간 받습니다.")
add("氮气触发后，下次攻击进度+15%；每80点命中额外获得5点护甲。【满速氮气】：本场氮气叠速满5层后，氮气伤害额外提高20%；每累计40次氮气击杀，再提高5%，成长最多20%，合计最多40%。贯穿仍为强化氮气伤害的60%。",
    "氮氣觸發後，下次攻擊進度+15%；每80點命中額外獲得5點護甲。【滿速氮氣】：本場氮氣疊速滿5層後，氮氣傷害額外提高20%；每累計40次氮氣擊殺，再提高5%，成長最多20%，合計最多40%。貫穿仍為強化氮氣傷害的60%。",
    "After Nitro triggers, next attack progress +15%; every 80 Hit grants 5 Armor. [Full-Speed Nitro]: Once Nitro speed reaches 5 stacks this battle, Nitro damage gains an extra 20%. Every 40 accumulated Nitro kills adds another 5%, with growth capped at +20% and the total at +40%. Piercing remains 60% of the enhanced Nitro damage.",
    "ニトロ発動後、次の攻撃進行+15%。命中80ごとに防御5追加。【最高速ニトロ】：この戦闘でニトロの速度が5層に達すると、ニトロダメージがさらに20%増加。累計ニトロ撃破40回ごとにさらに+5%、成長分は最大20%、合計最大40%。貫通は強化後のニトロダメージの60%のまま。",
    "니트로 발동 후 다음 공격 진행도 +15%, 명중 80마다 방어력 5 추가. [최고속 니트로]: 이번 전투에서 니트로 속도 5중첩을 채우면 니트로 피해 추가 +20%. 누적 니트로 처치 40회마다 추가 +5%, 성장분 최대 20%, 총 최대 40%. 관통은 강화된 니트로 피해의 60%를 유지합니다.")
add("连续攻击期间击杀可积累预存次数；触发间隔缩短至每15次攻击，连续攻击时攻击速度+50%并积累过载。【课时扩容】：每累计40次课时击杀成长，正常连射额外1发，最多额外4发，12发增至最多16发；每轮启动时冻结发数，途中成长不即时续弹。",
    "連續攻擊期間擊殺可積累預存次數；觸發間隔縮短至每15次攻擊，連續攻擊時攻擊速度+50%並積累過載。【課時擴容】：每累計40次課時擊殺成長，正常連射額外1發，最多額外4發，12發增至最多16發；每輪啟動時凍結發數，途中成長不即時續彈。",
    "Kills during continuous attacks build reserves. Trigger interval drops to 15 attacks; Attack Speed +50% during continuous attacks, which build Overload. [Lesson Expansion]: Every 40 accumulated Lesson kill-growth stacks adds 1 shot to normal volleys, up to 4 extra, raising 12 shots to at most 16. Shot count is frozen when each volley starts; growth during it does not add shots immediately.",
    "連続攻撃中の撃破でストックを蓄積。発動間隔が15回攻撃に短縮し、連続攻撃中は攻撃速度+50%と過負荷を蓄積。【課時拡張】：課時の撃破成長40回ごとに通常連射1発追加、最大4発追加で12発から最大16発に。各連射開始時に発数を固定し、途中の成長で即時補充しない。",
    "연속 공격 중 처치하면 비축 횟수 축적. 발동 간격이 공격 15회로 단축, 연속 공격 시 공격 속도 +50% 및 과부하 축적. [수업 확장]: 수업 처치 성장 누적 40회마다 일반 연사 1발 추가, 최대 4발 추가로 12발에서 최대 16발. 매 연사 시작 시 발수를 고정하며 도중 성장은 즉시 탄을 보충하지 않습니다.")
add("有盾队友的下次攻击可附带本次治疗量20%的额外伤害；临时护盾上限提高20%，治疗暴击率+10%。【护盾韵脚】：上述附伤比例由20%提升至30%；每累计40层护盾积累，再+2.5个百分点，最高40%。多次赋予取较大附伤，不累加。",
    "有盾隊友的下次攻擊可附帶本次治療量20%的額外傷害；臨時護盾上限提高20%，治療暴擊率+10%。【護盾韻腳】：上述附傷比例由20%提升至30%；每累計40層護盾積累，再+2.5個百分點，最高40%。多次賦予取較大附傷，不累加。",
    "Shielded allies can add 20% of this heal as extra damage to their next attack. Temporary shield cap +20%, Healing Crit +10%. [Shield Rhyme]: That extra-damage ratio rises from 20% to 30%. Every 40 accumulated Shield growth stacks adds 2.5 percentage points, up to 40%. Repeated grants keep the larger extra damage; they do not add together.",
    "シールドのある味方は、次の攻撃に今回の治療量の20%の追加ダメージを付与できる。一時シールド上限+20%、回復会心率+10%。【シールドの韻】：この追加割合が20%から30%に上昇。護盾蓄積40層ごとにさらに+2.5ポイント、最大40%。複数回付与された場合は大きい追加ダメージを採用し、加算しない。",
    "보호막이 있는 아군의 다음 공격에 이번 치유량 20%의 추가 피해 부여 가능. 임시 보호막 상한 +20%, 치유 치명타 확률 +10%. [보호막 운율]: 이 추가 피해 비율이 20%에서 30%로 증가. 누적 보호막 성장 40중첩마다 추가 +2.5%p, 최대 40%. 여러 번 부여하면 더 큰 추가 피해만 적용하며 합산하지 않습니다.")
add("加载条容量由最大生命的10%提升至14%；释放的伤害按粉碎属性结算。【满载分流】：仅满条释放时，对另一名不同的存活敌人追加加载条释放量50%的粉碎副包；觉醒Ⅰ每累计50层加载条成长，副包比例+5个百分点，最高75%。闲置释放不产生副包。",
    "載入條容量由最大生命的10%提升至14%；釋放的傷害按粉碎屬性結算。【滿載分流】：僅滿條釋放時，對另一名不同的存活敵人追加載入條釋放量50%的粉碎副包；覺醒Ⅰ每累計50層載入條成長，副包比例+5個百分點，最高75%。閒置釋放不產生副包。",
    "Loading Bar capacity rises from 10% to 14% of max HP; releases deal Crush damage. [Full-Load Split]: Only a full-bar release adds a Crush packet to a different living enemy, equal to 50% of the released bar amount. Every 50 accumulated Awakening I Loading Bar growth stacks adds 5 percentage points to the packet ratio, up to 75%. Idle releases do not create this packet.",
    "ロードバー容量が最大HPの10%から14%に増加。放出ダメージは粉砕属性。【満載分流】：満タンでの放出時のみ、別の生存敵1体に放出量の50%の粉砕追加ダメージ。覚醒Ⅰのロードバー成長50層ごとに追加割合+5ポイント、最大75%。待機による放出では追加ダメージを生成しない。",
    "로딩 바 용량이 최대 생명력의 10%에서 14%로 증가, 방출 피해는 분쇄 속성. [만재 분류]: 가득 찬 바 방출 시에만 다른 살아 있는 적 1명에게 방출량 50%의 분쇄 추가 패킷. 각성Ⅰ 로딩 바 성장 누적 50중첩마다 패킷 비율 +5%p, 최대 75%. 유휴 방출은 추가 패킷을 생성하지 않습니다.")

-- ===== 觉醒阶段累计状态：先翻译模板，再填入真实数值 =====
add("生命上限 +%d", "生命上限 +%d", "Max HP +%d", "最大HP +%d", "최대 생명력 +%d")
add("生命上限 +%.1f", "生命上限 +%.1f", "Max HP +%.1f", "最大HP +%.1f", "최대 생명력 +%.1f")
add("魔攻 +%.1f", "魔攻 +%.1f", "Magic ATK +%.1f", "魔法攻撃 +%.1f", "마법 공격력 +%.1f")
add("魔攻 +%.1f · 累计冰冻成长 +%.2f%%（总概率上限80%%）",
    "魔攻 +%.1f · 累計冰凍成長 +%.2f%%（總機率上限80%%）",
    "Magic ATK +%.1f · Accumulated freeze growth +%.2f%% (total chance capped at 80%%)",
    "魔法攻撃 +%.1f · 累計凍結成長 +%.2f%%（合計確率の上限80%%）",
    "마법 공격력 +%.1f · 누적 빙결 성장 +%.2f%%(총 확률 상한 80%%)")
add("累计课时缩短 %.2f（最短8次攻击）",
    "累計課時縮短 %.2f（最短8次攻擊）",
    "Accumulated attack interval reduction %.2f (minimum 8 attacks)",
    "累計攻撃間隔短縮 %.2f（最短8回攻撃）",
    "누적 공격 간격 감소 %.2f(최소 8회 공격)")
add("生命上限 +%d · 累计复活成长 +%.1f%%（总概率上限80%%）",
    "生命上限 +%d · 累計復活成長 +%.1f%%（總機率上限80%%）",
    "Max HP +%d · Accumulated revive growth +%.1f%% (total chance capped at 80%%)",
    "最大HP +%d · 累計復活成長 +%.1f%%（合計確率の上限80%%）",
    "최대 생명력 +%d · 누적 부활 성장 +%.1f%%(총 확률 상한 80%%)")
add("物攻 +%.1f", "物攻 +%.1f", "Physical ATK +%.1f", "物理攻撃 +%.1f", "물리 공격력 +%.1f")
add("护甲 +%.1f", "護甲 +%.1f", "Armor +%.1f", "防御 +%.1f", "방어력 +%.1f")
add("连击率 +%.1f%%", "連擊率 +%.1f%%", "Combo chance +%.1f%%", "連撃率 +%.1f%%", "연격 확률 +%.1f%%")
add("全伤害 +%.2f%%", "全傷害 +%.2f%%", "All damage +%.2f%%", "全ダメージ +%.2f%%", "전체 피해 +%.2f%%")
add("魂火 +%.2f", "魂火 +%.2f", "Spirit +%.2f", "魂火 +%.2f", "혼화 +%.2f")
add("双攻 +%.1f%%", "雙攻 +%.1f%%", "Both ATK +%.1f%%", "両攻撃 +%.1f%%", "양 공격력 +%.1f%%")
add("生命上限 +%d · 复活率 +%.1f%%", "生命上限 +%d · 復活率 +%.1f%%", "Max HP +%d · Revive chance +%.1f%%", "最大HP +%d・蘇生率 +%.1f%%", "최대 생명력 +%d · 부활 확률 +%.1f%%")
add("飞剑系数 +%.1f%%", "飛劍係數 +%.1f%%", "Flying sword coefficient +%.1f%%", "飛剣倍率 +%.1f%%", "비검 계수 +%.1f%%")
add("暴击率 +%.1f%%", "暴擊率 +%.1f%%", "Crit chance +%.1f%%", "会心率 +%.1f%%", "치명타 확률 +%.1f%%")
add("星门伤害 +%.1f%%", "星門傷害 +%.1f%%", "Stargate damage +%.1f%%", "星門ダメージ +%.1f%%", "성문 피해 +%.1f%%")
add("氮气率 +%.2f%%", "氮氣率 +%.2f%%", "Nitro chance +%.2f%%", "ニトロ発動率 +%.2f%%", "니트로 확률 +%.2f%%")
add("课时 -%.2f（连打间隔）", "課時 -%.2f（連打間隔）", "Trigger interval -%.2f attacks", "連打間隔 -%.2f回", "연타 발동 간격 -%.2f회")
add("护盾上限 +%d", "護盾上限 +%d", "Max shield +%d", "最大シールド +%d", "최대 보호막 +%d")
add("图鉴 %d/8", "圖鑑 %d/8", "Bestiary %d/8", "図鑑 %d/8", "도감 %d/8")
add("预存精准 %d/5", "預存精準 %d/5", "Precision reserve %d/5", "精密ストック %d/5", "정밀 비축 %d/5")
add("武德库存 %d", "武德庫存 %d", "Counter reserve %d", "反撃ストック %d", "반격 비축 %d")
add("开场甲片 %d", "開場甲片 %d", "Starting plates %d", "開戦時の甲片 %d", "시작 갑편 %d")
add("预存光线 %d/3", "預存光線 %d/3", "Beam reserve %d/3", "光線ストック %d/3", "광선 비축 %d/3")
add("仇种 %d/8", "仇種 %d/8", "Grudge types %d/8", "仇種 %d/8", "원수 유형 %d/8")
add("斩影 %d/4", "斬影 %d/4", "Slash shadows %d/4", "斬影 %d/4", "참격 그림자 %d/4")
add("冰雕 %d/3", "冰雕 %d/3", "Ice statues %d/3", "氷像 %d/3", "얼음 조각상 %d/3")
add("分裂击杀 %d · 额外弹射 +%d", "分裂擊殺 %d · 額外彈射 +%d", "Ricochet kills %d · Extra bounces +%d", "跳弾撃破 %d・追加跳弾 +%d", "도탄 처치 %d · 추가 도탄 +%d")
add("预存票 %d", "預存票 %d", "Revive tickets %d", "蘇生券 %d", "부활권 %d")
add("预存连打 %d/10", "預存連打 %d/10", "Gatling reserve %d/10", "連打ストック %d/10", "연타 비축 %d/10")

-- ===== 套装筛选（仓库/遗匣共用弹窗）=====
add("套装筛选", "套裝篩選", "Set filter", "セット絞り込み", "세트 필터")
add("套装", "套裝", "Sets", "セット", "세트")
add("无套装", "無套裝", "No set", "セットなし", "세트 없음")
add("清空", "清空", "Clear", "クリア", "초기화")
add("完成", "完成", "Done", "完了", "완료")
add("共 %d 种套装", "共 %d 種套裝", "%d sets", "全%dセット", "세트 %d종")
add("暂无符合筛选的装备", "暫無符合篩選的裝備", "No gear matches the filters", "条件に合う装備なし", "해당 조건 장비 없음")

-- ===== 当前基线的小队解锁与行军提示：保持按通关进度解锁 =====
add("通关9-5解锁", "通關9-5解鎖", "Clear 9-5 to unlock", "9-5クリアで解放", "9-5 클리어 시 해제")
add("通关19-5解锁", "通關19-5解鎖", "Clear 19-5 to unlock", "19-5クリアで解放", "19-5 클리어 시 해제")
add("正在前进中", "正在前進中", "Moving forward", "移動中", "이동 중")

-- ===== 首批关卡相关动态模板：先翻译，再填参数 =====
add("套装 · %d", "套裝 · %d", "Sets · %d", "セット・%d", "세트 · %d")
add("【小队%d】%s", "【小隊%d】%s", "[Squad %d] %s", "【小隊%d】%s", "[소대 %d] %s")
add("%s（已失守）", "%s（已失守）", "%s (Defeated)", "%s（陥落）", "%s (함락)")
add("共享生命 %s / %s", "共享生命 %s / %s", "Shared HP %s / %s", "共有HP %s / %s", "공유 생명력 %s / %s")
add("限时 %d:%02d", "限時 %d:%02d", "Time %d:%02d", "制限時間 %d:%02d", "제한 시간 %d:%02d")
add("关卡进度 %s", "關卡進度 %s", "Stage progress %s", "ステージ進行 %s", "스테이지 진행 %s")
add("远征等级达到 %s 解锁", "遠征等級達到 %s 解鎖", "Unlocks at Expedition Lv.%s", "遠征レベル%sで解放", "원정 레벨 %s 달성 시 해제")
add("准备中", "準備中", "Preparing", "準備中", "준비 중")
add("待解锁", "待解鎖", "Locked", "未解放", "잠김")
add("抵达%s难度后开放", "抵達%s難度後開放", "Unlocks on reaching %s difficulty", "%s難易度に到達すると解放", "%s 난이도 도달 시 개방")
add("当前进度：%s", "目前進度：%s", "Current progress: %s", "現在の進行：%s", "현재 진행: %s")
add("[%s] %s", "[%s] %s", "[%s] %s", "[%s] %s", "[%s] %s")
add("通关%s", "通關%s", "Clear %s", "%sをクリア", "%s 클리어")
add("进度 %d/%d", "進度 %d/%d", "Progress %d/%d", "進行 %d/%d", "진행 %d/%d")
add("一键领取 %d", "一鍵領取 %d", "Claim all %d", "%d件を一括受取", "%d개 일괄 수령")
add("可三队一起上场", "可三隊一起上場", "All 3 squads can join", "3小隊で参加可能", "소대 3개 동시 참가 가능")
add("左右拖动查看敌人", "左右拖動查看敵人", "Drag left or right to view enemies", "左右にドラッグして敵を確認", "좌우로 드래그하여 적 확인")
add("最多三队一起上场，不必三队全部存活。", "最多三隊一起上場，不必三隊全部存活。", "Up to 3 squads can join. Not all squads need to survive.", "最大3小隊で参加可能。全小隊の生存は不要です。", "최대 3개 소대가 함께 참가하며, 모든 소대가 생존할 필요는 없습니다.")
add("同编号敌人跨队共享生命，击败全部三名敌人即可通关。", "同編號敵人跨隊共享生命，擊敗全部三名敵人即可通關。", "Each enemy shares HP across squads. Defeat all 3 enemies to clear.", "同じ番号の敵は小隊間でHPを共有。敵3体をすべて倒せばクリア。", "같은 번호의 적은 소대 간 생명력을 공유합니다. 적 3명을 모두 처치하면 클리어합니다.")
add("不限时", "不限時", "No time limit", "時間制限なし", "시간 제한 없음")
add("不限时；全部参战队伍失守才失败。", "不限時；全部參戰隊伍失守才失敗。", "No time limit. Failure only if all participating squads are defeated.", "時間制限なし。参加した全小隊が全滅した場合のみ失敗。", "시간 제한은 없습니다. 참가한 모든 소대가 전멸해야 실패합니다.")
add("胜利进入下一难度，失败退回本难度最后一关。", "勝利進入下一難度，失敗退回本難度最後一關。", "Win to enter the next difficulty. Failure returns to this difficulty's final stage.", "勝利すると次の難易度へ進み、失敗すると現在の難易度の最終ステージへ戻ります。", "승리하면 다음 난이도로 진입하며, 실패하면 현재 난이도의 마지막 스테이지로 돌아갑니다.")
add("未编队，请在右侧部署队员", "未編隊，請在右側部署隊員", "No squad. Deploy heroes on the right.", "未編成です。右側で隊員を配置してください", "미편성 상태입니다. 오른쪽에서 영웅을 배치하세요")

add("%s %s 至 %s", "%s %s 至 %s", "%s %s to %s", "%s %s ～ %s", "%s %s ~ %s")
add("即将进入%s难度...", "即將進入%s難度...", "Entering %s difficulty...", "%s難易度へ移行中...", "%s 난이도로 진입 중...")
add("通关后进入「%s」轮回", "通關後進入「%s」輪迴", "Clear to reincarnate into %s", "クリア後に「%s」へ転生", "클리어 후 %s 난이도로 윤회")
add("剩余敌人 %s", "剩餘敵人 %s", "Enemies left: %s", "残りの敵 %s", "남은 적 %s")
add("剩余 %d 秒", "剩餘 %d 秒", "%d seconds left", "残り%d秒", "남은 시간 %d초")
add("超级狂暴! %.0fs", "超級狂暴! %.0fs", "Super rage! %.0fs", "超狂暴！%.0f秒", "초광폭! %.0f초")
add("狂暴中 %.0fs", "狂暴中 %.0fs", "Raging %.0fs", "狂暴中 %.0f秒", "광폭 중 %.0f초")
add("已用时 %.0fs", "已用時 %.0fs", "Elapsed %.0fs", "経過 %.0f秒", "경과 %.0f초")

return D
