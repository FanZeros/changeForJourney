-- 原始装备模板 W1-W72、O1-O30 与对应的 17 个子类型；不含后续套装模板。
-- 完整原文键的显式译文，不进行自动转换、拼接或回退。
local D = { zh_TW = {}, en = {}, ja = {}, ko = {} }

---@param zh string
---@param tw string
---@param en string
---@param ja string
---@param ko string
local function add(zh, tw, en, ja, ko)
    D.zh_TW[zh] = tw
    D.en[zh] = en
    D.ja[zh] = ja
    D.ko[zh] = ko
end

-- 单手剑 W1-W6
add("练习用剑", "練習用劍", "Training Sword", "練習用の剣", "연습용 검")
add("铁质长剑", "鐵質長劍", "Iron Longsword", "鉄の長剣", "철제 장검")
add("钢制长剑", "鋼製長劍", "Steel Longsword", "鋼の長剣", "강철 장검")
add("骑士佩剑", "騎士佩劍", "Knight's Sword", "騎士の佩剣", "기사의 검")
add("叠甲战神之剑", "疊甲戰神之劍", "Stackplate War-god's Sword", "重ね甲の戦神の剣", "겹갑 전신의 검")
add("水晶长剑", "水晶長劍", "Crystal Longsword", "水晶の長剣", "수정 장검")

-- 双手剑 W7-W12
add("练习用大剑", "練習用大劍", "Training Greatsword", "練習用の大剣", "연습용 대검")
add("生铁重剑", "生鐵重劍", "Pig Iron Heavy Sword", "銑鉄の重剣", "선철 중검")
add("黑铁大剑", "黑鐵大劍", "Black Iron Greatsword", "黒鉄の大剣", "흑철 대검")
add("斩铁巨刃", "斬鐵巨刃", "Ironcleaver", "斬鉄の巨刃", "철을 가르는 거검")
add("叠甲战神巨剑", "疊甲戰神巨劍", "Stackplate War-god's Greatsword", "重ね甲の戦神の巨剣", "겹갑 전신의 거검")
add("水晶大剑", "水晶大劍", "Crystal Greatsword", "水晶の大剣", "수정 대검")

-- 单手斧 W13-W18
add("伐木斧", "伐木斧", "Woodcutting Axe", "伐採斧", "벌목 도끼")
add("铁手斧", "鐵手斧", "Iron Hatchet", "鉄の手斧", "철제 손도끼")
add("钢斧", "鋼斧", "Steel Axe", "鋼の斧", "강철 도끼")
add("蛮族利斧", "蠻族利斧", "Barbarian's Keen Axe", "蛮族の鋭斧", "야만족의 예리한 도끼")
add("掠夺者之斧", "掠奪者之斧", "Raider's Axe", "略奪者の斧", "약탈자의 도끼")
add("水晶手斧", "水晶手斧", "Crystal Hatchet", "水晶の手斧", "수정 손도끼")

-- 双手斧 W19-W24
add("双刃巨斧", "雙刃巨斧", "Double-Bladed Greataxe", "双刃の大斧", "양날 대형 도끼")
add("铁巨斧", "鐵巨斧", "Iron Greataxe", "鉄の大斧", "철제 대형 도끼")
add("长柄战斧", "長柄戰斧", "Long-Hafted Battleaxe", "長柄の戦斧", "긴 자루 전투 도끼")
add("蛮族巨斧", "蠻族巨斧", "Barbarian's Greataxe", "蛮族の大斧", "야만족의 대형 도끼")
add("掠夺者巨斧", "掠奪者巨斧", "Raider's Greataxe", "略奪者の大斧", "약탈자의 대형 도끼")
add("水晶巨斧", "水晶巨斧", "Crystal Greataxe", "水晶の大斧", "수정 대형 도끼")

-- 法杖 W25-W30
add("学徒木杖", "學徒木杖", "Apprentice's Wooden Staff", "見習いの木杖", "견습생의 나무 지팡이")
add("符文长杖", "符文長杖", "Runic Staff", "ルーンの長杖", "룬 긴 지팡이")
add("铁质长杖", "鐵質長杖", "Iron Staff", "鉄の長杖", "철제 긴 지팡이")
add("银质长杖", "銀質長杖", "Silver Staff", "銀の長杖", "은제 긴 지팡이")
add("镀金长杖", "鍍金長杖", "Gilded Staff", "金鍍金の長杖", "금도금 긴 지팡이")
add("水晶长杖", "水晶長杖", "Crystal Staff", "水晶の長杖", "수정 긴 지팡이")

-- 魔杖 W31-W36
add("短魔杖", "短魔杖", "Short Wand", "短い魔杖", "짧은 마법봉")
add("符文魔杖", "符文魔杖", "Runic Wand", "ルーンの魔杖", "룬 마법봉")
add("仪式魔杖", "儀式魔杖", "Ritual Wand", "儀式の魔杖", "의식용 마법봉")
add("精灵魔杖", "精靈魔杖", "Elven Wand", "エルフの魔杖", "엘프 마법봉")
add("镀金魔杖", "鍍金魔杖", "Gilded Wand", "金鍍金の魔杖", "금도금 마법봉")
add("水晶魔杖", "水晶魔杖", "Crystal Wand", "水晶の魔杖", "수정 마법봉")

-- 弓箭 W37-W42
add("木质短弓", "木質短弓", "Wooden Shortbow", "木の短弓", "나무 단궁")
add("铁制长弓", "鐵製長弓", "Iron Longbow", "鉄の長弓", "철제 장궁")
add("狩猎弓", "狩獵弓", "Hunting Bow", "狩猟弓", "사냥 활")
add("游侠弓", "遊俠弓", "Ranger's Bow", "レンジャーの弓", "레인저의 활")
add("风行者之弓", "風行者之弓", "Windrunner's Bow", "風を駆ける者の弓", "바람의 질주자의 활")
add("水晶长弓", "水晶長弓", "Crystal Longbow", "水晶の長弓", "수정 장궁")

-- 单手弩 W43-W48
add("轻弩", "輕弩", "Light Crossbow", "軽弩", "경량 석궁")
add("铁弩", "鐵弩", "Iron Crossbow", "鉄の弩", "철제 석궁")
add("狩猎弩", "狩獵弩", "Hunting Crossbow", "狩猟用の弩", "사냥 석궁")
add("游侠弩", "遊俠弩", "Ranger's Crossbow", "レンジャーの弩", "레인저의 석궁")
add("风行者手弩", "風行者手弩", "Windrunner's Hand Crossbow", "風を駆ける者の手弩", "바람의 질주자의 손석궁")
add("水晶手弩", "水晶手弩", "Crystal Hand Crossbow", "水晶の手弩", "수정 손석궁")

-- 手铳 W49-W54
add("燧发手铳", "燧發手銃", "Flintlock Pistol", "フリントロック式拳銃", "수석식 권총")
add("铁质手铳", "鐵質手銃", "Iron Pistol", "鉄の拳銃", "철제 권총")
add("短铳", "短銃", "Short Pistol", "短銃", "단총")
add("矮人手枪", "矮人手槍", "Dwarven Pistol", "ドワーフの拳銃", "드워프 권총")
add("机械手铳", "機械手銃", "Mechanical Pistol", "機械式拳銃", "기계식 권총")
add("水晶手枪", "水晶手槍", "Crystal Pistol", "水晶の拳銃", "수정 권총")

-- 匕首 W55-W60
add("玻璃碎片", "玻璃碎片", "Glass Shard", "ガラスの破片", "유리 파편")
add("铜匕首", "銅匕首", "Copper Dagger", "銅の短剣", "구리 단검")
add("铁匕首", "鐵匕首", "Iron Dagger", "鉄の短剣", "철제 단검")
add("盗贼短匕", "盜賊短匕", "Thief's Short Dagger", "盗賊の小刀", "도적의 짧은 단검")
add("刺客之刃", "刺客之刃", "Assassin's Blade", "暗殺者の刃", "암살자의 칼날")
add("水晶之刃", "水晶之刃", "Crystal Blade", "水晶の刃", "수정 칼날")

-- 细剑 W61-W66
add("练习用刺剑", "練習用刺劍", "Training Rapier", "練習用の刺突剣", "연습용 레이피어")
add("刺剑", "刺劍", "Rapier", "刺突剣", "레이피어")
add("绅士细剑", "紳士細劍", "Gentleman's Rapier", "紳士の細剣", "신사의 레이피어")
add("练武者细剑", "練武者細劍", "Martial Adept's Rapier", "武芸者の細剣", "무인의 레이피어")
add("决斗者细剑", "決鬥者細劍", "Duelist's Rapier", "決闘者の細剣", "결투사의 레이피어")
add("水晶刺剑", "水晶刺劍", "Crystal Rapier", "水晶の刺突剣", "수정 레이피어")

-- 权杖 W67-W72
add("木质权杖", "木質權杖", "Wooden Scepter", "木の王笏", "나무 홀")
add("铁质权杖", "鐵質權杖", "Iron Scepter", "鉄の王笏", "철제 홀")
add("祭祀权杖", "祭祀權杖", "Ritual Scepter", "祭儀の王笏", "의식용 홀")
add("主教权杖", "主教權杖", "Bishop's Scepter", "司教の王笏", "주교의 홀")
add("光之权杖", "光之權杖", "Scepter of Light", "光の王笏", "빛의 홀")
add("水晶权杖", "水晶權杖", "Crystal Scepter", "水晶の王笏", "수정 홀")

-- 轻盾 O1-O6
add("陈旧木盾", "陳舊木盾", "Old Wooden Shield", "古びた木盾", "낡은 나무 방패")
add("镶皮圆盾", "鑲皮圓盾", "Leather-Bound Round Shield", "革張りの円盾", "가죽을 두른 원형 방패")
add("钢边轻鸢盾", "鋼邊輕鳶盾", "Steel-Rimmed Light Kite Shield", "鋼縁の軽量カイトシールド", "강철 테두리 경량 카이트 방패")
add("斥候疾风盾", "斥候疾風盾", "Scout's Gale Shield", "斥候の疾風盾", "정찰병의 질풍 방패")
add("守望者轻盾", "守望者輕盾", "Watcher's Light Shield", "見張りの軽盾", "파수꾼의 경량 방패")
add("流光镜盾", "流光鏡盾", "Shimmering Mirror Shield", "煌めきの鏡盾", "빛나는 거울 방패")

-- 重盾 O7-O12
add("厚实木盾", "厚實木盾", "Thick Wooden Shield", "分厚い木盾", "두꺼운 나무 방패")
add("铸铁方盾", "鑄鐵方盾", "Cast Iron Square Shield", "鋳鉄の角盾", "주철 사각 방패")
add("钢制塔盾", "鋼製塔盾", "Steel Tower Shield", "鋼のタワーシールド", "강철 타워 방패")
add("守卫巨盾", "守衛巨盾", "Guard's Greatshield", "衛兵の大盾", "경비병의 대형 방패")
add("蛮族巨盾", "蠻族巨盾", "Barbarian's Greatshield", "蛮族の大盾", "야만족의 대형 방패")
add("水晶巨盾", "水晶巨盾", "Crystal Greatshield", "水晶の大盾", "수정 대형 방패")

-- 魔典 O13-O18
add("学徒魔典", "學徒魔典", "Apprentice's Grimoire", "見習いの魔導書", "견습생의 마법서")
add("见习魔典", "見習魔典", "Novice's Grimoire", "初学者の魔導書", "수련생의 마법서")
add("咒文魔典", "咒文魔典", "Grimoire of Spells", "呪文の魔導書", "주문 마법서")
add("秘法魔典", "秘法魔典", "Mystic Grimoire", "秘法の魔導書", "비법 마법서")
add("奥术魔典", "奧術魔典", "Arcane Grimoire", "奥術の魔導書", "비전 마법서")
add("大法师魔典", "大法師魔典", "Archmage's Grimoire", "大魔導師の魔導書", "대마법사의 마법서")

-- 法珠 O19-O24
add("学徒法珠", "學徒法珠", "Apprentice's Orb", "見習いの魔珠", "견습생의 마법구")
add("见习法珠", "見習法珠", "Novice's Orb", "初学者の魔珠", "수련생의 마법구")
add("魔力法珠", "魔力法珠", "Mana Orb", "魔力の魔珠", "마력 마법구")
add("闪光法珠", "閃光法珠", "Gleaming Orb", "閃光の魔珠", "섬광 마법구")
add("奥术法珠", "奧術法珠", "Arcane Orb", "奥術の魔珠", "비전 마법구")
add("水晶法珠", "水晶法珠", "Crystal Orb", "水晶の魔珠", "수정 마법구")

-- 圣物 O25-O30
add("木质圣杯", "木質聖杯", "Wooden Chalice", "木の聖杯", "나무 성배")
add("铁质圣杯", "鐵質聖杯", "Iron Chalice", "鉄の聖杯", "철제 성배")
add("祭祀圣杯", "祭祀聖杯", "Ritual Chalice", "祭儀の聖杯", "의식용 성배")
add("主教圣杯", "主教聖杯", "Bishop's Chalice", "司教の聖杯", "주교의 성배")
add("光之圣杯", "光之聖杯", "Chalice of Light", "光の聖杯", "빛의 성배")
add("水晶圣杯", "水晶聖杯", "Crystal Chalice", "水晶の聖杯", "수정 성배")

-- 武器子类型（12）；与现有同名词条使用完全相同的译文。
add("单手剑", "單手劍", "One-Handed Sword", "片手剣", "한손검")
add("双手剑", "雙手劍", "Greatsword", "両手剣", "양손검")
add("单手斧", "單手斧", "One-Handed Axe", "片手斧", "한손도끼")
add("双手斧", "雙手斧", "Greataxe", "両手斧", "양손도끼")
add("法杖", "法杖", "Staff", "杖", "지팡이")
add("魔杖", "魔杖", "Wand", "魔杖", "마법봉")
add("弓箭", "弓箭", "Bow", "弓", "활")
add("单手弩", "單手弩", "Hand Crossbow", "手弩", "손석궁")
add("手铳", "手銃", "Handgun", "拳銃", "권총")
add("匕首", "匕首", "Dagger", "短剣", "단검")
add("细剑", "細劍", "Rapier", "細剣", "레이피어")
add("权杖", "權杖", "Scepter", "王笏", "홀")

-- 副手子类型（5）；整个装备配置实际共有 25 个唯一子类型。
add("轻盾", "輕盾", "Light Shield", "軽盾", "경량 방패")
add("重盾", "重盾", "Heavy Shield", "重盾", "중량 방패")
add("魔典", "魔典", "Grimoire", "魔導書", "마법서")
add("法珠", "法珠", "Orb", "魔珠", "마법구")
add("圣物", "聖物", "Relic", "聖遺物", "성물")

return D
