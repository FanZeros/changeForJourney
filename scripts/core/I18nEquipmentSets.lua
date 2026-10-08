-- 12 套装备名称与 36 条现行 2/4/6 件说明（20261008 方案 2）。
-- 只按完整简体原文匹配；整串键、数值与触发语义同步 EquipmentSetConfig 的最终描述。
-- 中文关键词交互仍由现有 KeywordText 管理，本词典不改变关键词/热区。
local D = { zh_TW = {}, en = {}, ja = {}, ko = {} }

---@param source string
---@param tw string
---@param en string
---@param ja string
---@param ko string
local function add(source, tw, en, ja, ko)
    D.zh_TW[source] = tw
    D.en[source] = en
    D.ja[source] = ja
    D.ko[source] = ko
end

-- 叠甲虫壳
add("叠甲虫壳", "疊甲蟲殼", "Stackplate Carapace", "重ね甲の虫殻", "겹갑 벌레껍질")
add("生命+12%，护甲加成+8%。", "生命+12%，護甲加成+8%。", "HP +12%, Armor Bonus +8%.", "HP+12%、防御補正+8%。", "생명 +12%, 방어 보너스 +8%.")
add("每次受击获得1层甲片（最多8）。每层受伤-3%。", "每次受擊獲得1層甲片（最多8）。每層受傷-3%。", "Each hit taken grants 1 Plate stack (max 8). Damage taken -3% per stack.", "被弾ごとに甲片を1層獲得（最大8層）。各層につき被ダメージ-3%。", "피격 시 갑편 1중첩 획득 (최대 8중첩). 중첩당 받는 피해 -3%.")
add("甲片满层时，下次攻击消耗全部层数，按层数×4%追加伤害并嘲讽2秒。", "甲片滿層時，下次攻擊消耗全部層數，按層數×4%追加傷害並嘲諷2秒。", "At max Plate stacks, the next attack consumes all stacks, adding stacks ×4% damage and taunting for 2s.", "甲片が最大層数になると、次の攻撃で全層を消費し、層数×4%の追加ダメージと2秒の挑発。", "갑편 최대 중첩 시 다음 공격이 모든 중첩을 소모하여 중첩 수 ×4% 추가 피해를 주고 2초간 도발.")

-- 夜行无面
add("夜行无面", "夜行無面", "Faceless Nightwalker", "夜行の無面", "밤의 무면")
add("暴击率+8%，闪避+10。", "暴擊率+8%，閃避+10。", "Crit Rate +8%, Evasion +10.", "会心率+8%、回避+10。", "치명타율 +8%, 회피 +10.")
add("攻击生命低于50%的敌人时，追加50%本次伤害。", "攻擊生命低於50%的敵人時，追加50%本次傷害。", "Attacks against enemies below 50% HP deal an extra 50% of that attack's damage.", "HP50%未満の敵を攻撃すると、その攻撃の50%を追加ダメージとして与える。", "생명 50% 미만인 적 공격 시 해당 공격 피해의 50%를 추가로 가함.")
add("敌人死亡后8秒进入无面：清空仇恨，期间不产生仇恨。", "敵人死亡後8秒進入無面：清空仇恨，期間不產生仇恨。", "When an enemy dies, enter Faceless for 8s: clear threat and generate no threat during this period.", "敵が死亡すると8秒間、無面状態になる：敵視をリセットし、その間は敵視が発生しない。", "적 사망 시 8초간 무면 상태: 위협을 초기화하고 지속 중 위협을 생성하지 않음.")

-- 裂隙水晶
add("裂隙水晶", "裂隙水晶", "Riftcrystal", "裂隙水晶", "균열 수정")
add("全伤害+8%，能量护盾加成+16%。", "全傷害+8%，能量護盾加成+16%。", "All DMG +8%, Energy Shield Bonus +16%.", "全ダメージ+8%、エネルギーシールド補正+16%。", "전체 피해 +8%, 에너지 보호막 보너스 +16%.")
add("攻击命中15%给目标1层晶蚀（最多5）。每层使目标受到的全伤害+3%。", "攻擊命中15%給目標1層晶蝕（最多5）。每層使目標受到的全傷害+3%。", "Attack hits have a 15% chance to apply 1 Crystal Erosion stack (max 5). Each stack increases all damage taken by the target by 3%.", "攻撃命中時、15%で対象に晶蝕を1層付与（最大5層）。各層につき対象の全被ダメージ+3%。", "공격 명중 시 15% 확률로 대상에게 수정 침식 1중첩 부여 (최대 5중첩). 중첩당 대상이 받는 모든 피해 +3%.")
add("晶蚀满5层碎裂：160%魔攻暗影伤害，并打断攻击进度。", "晶蝕滿5層碎裂：160%魔攻暗影傷害，並打斷攻擊進度。", "At 5 Crystal Erosion stacks, shatter for 160% Magic ATK as shadow damage and interrupt attack progress.", "晶蝕が5層で砕け、魔法攻撃力160%のシャドウダメージを与え、攻撃進行を中断。", "수정 침식 5중첩 시 파쇄: 마법 공격력 160%의 암영 피해를 주고 공격 진행을 중단.")

-- 终焉司仪袍
add("终焉司仪袍", "終焉司儀袍", "Finality Officiant's Robe", "終焉の司式者の衣", "종언 집례자의 로브")
add("治疗加成+16%，能量护盾加成+12%。", "治療加成+16%，能量護盾加成+12%。", "Heal Bonus +16%, Energy Shield Bonus +12%.", "回復補正+16%、エネルギーシールド補正+12%。", "회복 보너스 +16%, 에너지 보호막 보너스 +12%.")
add("过量治疗的40%转为能量护盾。", "過量治療的40%轉為能量護盾。", "Convert 40% of overhealing into Energy Shield.", "過剰回復の40%をエネルギーシールドに変換。", "초과 회복량의 40%를 에너지 보호막으로 전환.")
add("全队能量护盾加成+16%（不改写死亡）。", "全隊能量護盾加成+16%（不改寫死亡）。", "Team Energy Shield Bonus +16% (does not alter death).", "チーム全員のエネルギーシールド補正+16%（死亡処理は変更しない）。", "팀 전체 에너지 보호막 보너스 +16% (사망 처리는 변경하지 않음).")

-- 高压水脉
add("高压水脉", "高壓水脈", "High-pressure Tide", "高圧水脈", "고압 수맥")
add("魔法穿透+12，攻速+10%。", "魔法穿透+12，攻速+10%。", "Magic Penetration +12, Attack Speed +10%.", "魔法貫通+12、攻撃速度+10%。", "마법 관통 +12, 공격 속도 +10%.")
add("攻击主目标时30%溅射邻近1人，伤害70%。", "攻擊主目標時30%濺射鄰近1人，傷害70%。", "Attacking the main target has a 30% chance to splash 1 nearby enemy for 70% damage.", "主対象への攻撃時、30%で近くの敵1体に70%ダメージの飛沫。", "주 대상 공격 시 30% 확률로 인접한 적 1명에게 70% 피해의 광역 타격.")
add("被溅射目标立即扣除40%攻击进度。", "被濺射目標立即扣除40%攻擊進度。", "Splashed targets immediately lose 40% attack progress.", "飛沫を受けた対象は直ちに攻撃進行を40%失う。", "광역 타격을 받은 대상의 공격 진행을 즉시 40% 차감.")

-- 赛道硝烟
add("赛道硝烟", "賽道硝煙", "Racing Gunsmoke", "サーキットの硝煙", "경주로의 화약 연기")
add("攻速+16%，命中+12。", "攻速+16%，命中+12。", "Attack Speed +16%, Accuracy +12.", "攻撃速度+16%、命中+12。", "공격 속도 +16%, 명중 +12.")
add("每80点命中，连击率+4%（最多+20%）。", "每80點命中，連擊率+4%（最多+20%）。", "Every 80 Accuracy grants Combo Chance +4% (max +20%).", "命中80ごとに連撃率+4%（最大+20%）。", "명중 80마다 연격 확률 +4% (최대 +20%).")
add("连击时贯穿仇恨第二的目标（100%伤害）；仅1名敌人时自身攻速+24%持续2秒。", "連擊時貫穿仇恨第二的目標（100%傷害）；僅1名敵人時自身攻速+24%持續2秒。", "Combo hits pierce the second-highest-threat target for 100% damage; with only 1 enemy, gain Attack Speed +24% for 2s.", "連撃時、敵視が二番目の対象を貫通（100%ダメージ）。敵が1体だけなら自身の攻撃速度+24%、2秒間。", "연격 시 위협이 두 번째인 대상을 관통 (100% 피해). 적이 1명뿐이면 자신의 공격 속도 +24%, 2초 지속.")

-- 万剑门扉
add("万剑门扉", "萬劍門扉", "Myriad Sword Gate", "万剣の門扉", "만검의 문")
add("物理穿透+16，物伤+10%。", "物理穿透+16，物傷+10%。", "Physical Penetration +16, Phys. DMG +10%.", "物理貫通+16、物理ダメージ+10%。", "물리 관통 +16, 물리 피해 +10%.")
add("每6秒召唤1柄门缝飞剑，伤害=这6秒自身伤害的30%。", "每6秒召喚1柄門縫飛劍，傷害=這6秒自身傷害的30%。", "Every 6s, summon 1 Gate-gap Flying Sword; its damage equals 30% of your damage over those 6s.", "6秒ごとに門の隙間から飛剣を1本召喚。ダメージはその6秒間の自身のダメージの30%。", "6초마다 문틈 비검 1자루 소환. 피해는 해당 6초간 자신의 피해량의 30%.")
add("飞剑+1柄。穿套本人不额外飞一轮。", "飛劍+1柄。穿套本人不額外飛一輪。", "Flying Swords +1. The wearer does not gain an extra firing cycle.", "飛剣+1本。装備者本人の追加発射周期は発生しない。", "비검 +1자루. 착용자 본인의 추가 발사 주기는 발생하지 않음.")

-- 无光星图
add("无光星图", "無光星圖", "Starless Chart", "無光の星図", "빛 없는 성도")
add("魔法伤害+8%。", "魔法傷害+8%。", "Magic DMG +8%.", "魔法ダメージ+8%。", "마법 피해 +8%.")
add("魔法穿透+16。", "魔法穿透+16。", "Magic Penetration +16.", "魔法貫通+16。", "마법 관통 +16.")
add("每8秒对生命百分比最低的敌人打240%魔攻，不产生仇恨。", "每8秒對生命百分比最低的敵人打240%魔攻，不產生仇恨。", "Every 8s, deal 240% Magic ATK to the enemy with the lowest HP percentage, generating no threat.", "8秒ごとにHP割合が最も低い敵へ魔法攻撃力240%のダメージ。敵視は発生しない。", "8초마다 생명 비율이 가장 낮은 적에게 마법 공격력 240%의 피해를 가하며 위협을 생성하지 않음.")

-- 帝国铁壁
add("帝国铁壁", "帝國鐵壁", "Imperial Ironwall", "帝国の鉄壁", "제국의 철벽")
add("物理格挡+8%，生命+8%。", "物理格擋+8%，生命+8%。", "Physical Block +8%, HP +8%.", "物理ガード+8%、HP+8%。", "물리 막기 +8%, 생명 +8%.")
add("格挡成功时回复2%最大生命。", "格擋成功時回復2%最大生命。", "Successful blocks restore 2% max HP.", "ガード成功時、最大HPの2%を回復。", "막기 성공 시 최대 생명의 2% 회복.")
add("格挡成功时把挡掉伤害的60%反给攻击者（暗影，无仇恨）。", "格擋成功時把擋掉傷害的60%反給攻擊者（暗影，無仇恨）。", "Successful blocks reflect 60% of the blocked damage to the attacker (shadow, no threat).", "ガード成功時、防いだダメージの60%を攻撃者に反射（シャドウ、敵視なし）。", "막기 성공 시 막은 피해의 60%를 공격자에게 반사 (암영, 위협 없음).")

-- 巡林余烬
add("巡林余烬", "巡林餘燼", "Ember Scout", "森巡りの残り火", "숲 순찰자의 잔불")
add("命中+10，物理穿透+8。", "命中+10，物理穿透+8。", "Accuracy +10, Physical Penetration +8.", "命中+10、物理貫通+8。", "명중 +10, 물리 관통 +8.")
add("攻击施加余烬2秒：目标受伤+16%。", "攻擊施加餘燼2秒：目標受傷+16%。", "Attacks apply Ember for 2s: target takes +16% damage.", "攻撃で残り火を2秒間付与：対象の被ダメージ+16%。", "공격 시 2초간 잔불 부여: 대상이 받는 피해 +16%.")
add("余烬目标死亡时，余烬弹射到另外2名敌人。", "餘燼目標死亡時，餘燼彈射到另外2名敵人。", "When an Ember target dies, Ember jumps to 2 other enemies.", "残り火を受けた対象が死亡すると、残り火が別の敵2体へ移る。", "잔불 대상 사망 시 잔불이 다른 적 2명에게 전이.")

-- 赌徒残响
add("赌徒残响", "賭徒殘響", "Gambler's Echo", "賭博師の残響", "도박사의 잔향")
-- 旧属性名整句保留兼容，不作为现行两件说明。
add("命数+4，最大伤害加成+8%。", "命數+4，最大傷害加成+8%。", "Fate +4, Max DMG Bonus +8%.", "命数+4、最大ダメージ補正+8%。", "명수 +4, 최대 피해 보너스 +8%.")
add("命数+8，优势伤害+16%。", "命數+8，優勢傷害+16%。", "Fate +8, Advantage DMG +16%.", "命数+8、有利ダメージ+16%。", "명수 +8, 상성 우위 피해 +16%.")
add("未暴击时下次暴击率+12%（最多叠3层，暴击清空）。", "未暴擊時下次暴擊率+12%（最多疊3層，暴擊清空）。", "Non-critical hits grant next Crit Rate +12% (max 3 stacks; critical hits clear stacks).", "非会心時、次の会心率+12%（最大3層、会心で全層解除）。", "치명타가 아닐 때 다음 치명타율 +12% (최대 3중첩, 치명타 시 초기화).")
add("暴击时额外一段60%伤害；若未暴击则回复2%已损失生命。", "暴擊時額外一段60%傷害；若未暴擊則回復2%已損失生命。", "Critical hits deal an extra 60% damage hit; non-critical hits restore 2% of missing HP.", "会心時、60%ダメージを追加。非会心なら失ったHPの2%を回復。", "치명타 시 60% 피해를 추가로 가함. 치명타가 아니면 잃은 생명의 2% 회복.")

-- 衔骨饥渴
add("衔骨饥渴", "銜骨飢渴", "Bonebite Hunger", "銜骨の飢渇", "뼈를 문 굶주림")
add("攻速+10%，攻击回血+8。", "攻速+10%，攻擊回血+8。", "Attack Speed +10%, HP on Attack +8.", "攻撃速度+10%、攻撃時HP回復+8。", "공격 속도 +10%, 공격 시 생명 회복 +8.")
add("生命低于70%时攻速再+16%。", "生命低於70%時攻速再+16%。", "Below 70% HP, gain an additional Attack Speed +16%.", "HP70%未満で攻撃速度がさらに+16%。", "생명 70% 미만일 때 공격 속도 추가 +16%.")
add("敌人死亡后回复6%最大生命。", "敵人死亡後回復6%最大生命。", "When an enemy dies, restore 6% max HP.", "敵が死亡すると、最大HPの6%を回復。", "적 사망 시 최대 생명의 6% 회복.")

return D
