-- Equipment names: 36 original accessories and 35 appended templates.
-- Explicit translations only; no automatic character conversion.
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

-- Accessory subtypes.
add("戒指", "戒指", "Ring", "指輪", "반지")
add("项链", "項鍊", "Necklace", "ネックレス", "목걸이")
add("耳环", "耳環", "Earrings", "イヤリング", "귀걸이")

-- Original rings.
add("蓝宝石戒", "藍寶石戒", "Sapphire Ring", "サファイアの指輪", "사파이어 반지")
add("金光之戒", "金光之戒", "Goldgleam Ring", "金光の指輪", "금빛 반지")
add("珊瑚之戒", "珊瑚之戒", "Coral Ring", "珊瑚の指輪", "산호 반지")
add("海灵之戒", "海靈之戒", "Sea Spirit Ring", "海霊の指輪", "바다 정령의 반지")
add("黄宝石戒", "黃寶石戒", "Topaz Ring", "トパーズの指輪", "토파즈 반지")
add("红宝石戒", "紅寶石戒", "Ruby Ring", "ルビーの指輪", "루비 반지")
add("紫宝石戒", "紫寶石戒", "Amethyst Ring", "アメジストの指輪", "자수정 반지")
add("宝钻之戒", "寶鑽之戒", "Brilliant Diamond Ring", "輝くダイヤの指輪", "찬란한 다이아 반지")
add("月光之戒", "月光之戒", "Moonlight Ring", "月光の指輪", "달빛 반지")
add("蛋白石戒", "蛋白石戒", "Opal Ring", "オパールの指輪", "오팔 반지")
add("晶钻之戒", "晶鑽之戒", "Crystal Diamond Ring", "水晶ダイヤの指輪", "수정 다이아 반지")
add("水晶之戒", "水晶之戒", "Crystal Ring", "水晶の指輪", "수정 반지")

-- Original necklaces.
add("海灵吊饰", "海靈吊飾", "Sea Spirit Pendant", "海霊のペンダント", "바다 정령의 펜던트")
add("珊瑚吊饰", "珊瑚吊飾", "Coral Pendant", "珊瑚のペンダント", "산호 펜던트")
add("琥珀挂坠", "琥珀掛墜", "Amber Pendant", "琥珀のペンダント", "호박 펜던트")
add("翠玉挂坠", "翠玉掛墜", "Green Jade Pendant", "翠玉のペンダント", "비취 펜던트")
add("蓝玉挂坠", "藍玉掛墜", "Blue Jade Pendant", "青玉のペンダント", "청옥 펜던트")
add("金光挂坠", "金光掛墜", "Goldgleam Pendant", "金光のペンダント", "금빛 펜던트")
add("青玉挂坠", "青玉掛墜", "Azure Jade Pendant", "碧玉のペンダント", "벽옥 펜던트")
add("黄玉挂坠", "黃玉掛墜", "Yellow Jade Pendant", "黄玉のペンダント", "황옥 펜던트")
add("玛瑙挂坠", "瑪瑙掛墜", "Agate Pendant", "瑪瑙のペンダント", "마노 펜던트")
add("白玉挂坠", "白玉掛墜", "White Jade Pendant", "白玉のペンダント", "백옥 펜던트")
add("红玉挂坠", "紅玉掛墜", "Red Jade Pendant", "紅玉のペンダント", "홍옥 펜던트")
add("水晶挂坠", "水晶掛墜", "Crystal Pendant", "水晶のペンダント", "수정 펜던트")

-- Original earrings; hoop names remain earrings, not rings.
add("蓝宝石耳环", "藍寶石耳環", "Sapphire Earrings", "サファイアのイヤリング", "사파이어 귀걸이")
add("银质耳环", "銀質耳環", "Silver Earrings", "銀のイヤリング", "은 귀걸이")
add("珊瑚耳环", "珊瑚耳環", "Coral Earrings", "珊瑚のイヤリング", "산호 귀걸이")
add("海玉耳环", "海玉耳環", "Sea Jade Earrings", "海玉のイヤリング", "바다 옥 귀걸이")
add("黄宝石耳环", "黃寶石耳環", "Topaz Earrings", "トパーズのイヤリング", "토파즈 귀걸이")
add("红宝石耳环", "紅寶石耳環", "Ruby Earrings", "ルビーのイヤリング", "루비 귀걸이")
add("珍珠耳环", "珍珠耳環", "Pearl Earrings", "真珠のイヤリング", "진주 귀걸이")
add("紫晶耳环", "紫晶耳環", "Amethyst Earrings", "紫水晶のイヤリング", "자수정 귀걸이")
add("赌徒之环", "賭徒之環", "Gambler's Hoops", "賭博師の耳輪", "도박사의 고리 귀걸이")
add("羽制耳环", "羽製耳環", "Feather Earrings", "羽根のイヤリング", "깃털 귀걸이")
add("碎玉之环", "碎玉之環", "Jade Shard Hoops", "玉片の耳輪", "옥 조각 고리 귀걸이")
add("水晶耳环", "水晶耳環", "Crystal Earrings", "水晶のイヤリング", "수정 귀걸이")

-- Appended high-pressure tide, racing gunsmoke and imperial ironwall gear.
add("潮汐魔杖", "潮汐魔杖", "Tidal Wand", "潮汐の魔杖", "조수의 마법봉")
add("深潮魔杖", "深潮魔杖", "Deep-Tide Wand", "深潮の魔杖", "심해의 마법봉")
add("极速手弩", "極速手弩", "Swift Handbow", "極速の手弩", "초고속 손쇠뇌")
add("硝烟疾风盾", "硝煙疾風盾", "Gunsmoke Gale Shield", "硝煙の疾風盾", "화약 연기의 질풍 방패")
add("硝烟镜盾", "硝煙鏡盾", "Gunsmoke Mirror Shield", "硝煙の鏡盾", "화약 연기의 거울 방패")
add("铁壁佩剑", "鐵壁佩劍", "Ironwall Sword", "鉄壁の佩剣", "철벽의 검")
add("帝国佩剑", "帝國佩劍", "Imperial Sword", "帝国の佩剣", "제국의 검")
add("帝国守卫盾", "帝國守衛盾", "Imperial Guard Shield", "帝国守衛の盾", "제국 수호자의 방패")

-- Ember scout.
add("余烬手弩", "餘燼手弩", "Ember Handbow", "残り火の手弩", "잔불 손쇠뇌")
add("巡林叶盾", "巡林葉盾", "Ranger's Leaf Shield", "森巡りの葉盾", "숲 순찰자의 잎 방패")
add("余烬猎衣", "餘燼獵衣", "Ember Hunter Coat", "残り火の狩人服", "잔불 사냥꾼 외투")
add("余烬猎帽", "餘燼獵帽", "Ember Hunter Cap", "残り火の狩人帽", "잔불 사냥꾼 모자")
add("余烬猎靴", "餘燼獵靴", "Ember Hunter Boots", "残り火の狩人靴", "잔불 사냥꾼 장화")
add("巡林余烬坠", "巡林餘燼墜", "Ember Scout Pendant", "森巡りの残り火ペンダント", "숲 순찰자의 잔불 펜던트")

-- Sword gate.
add("门扉重铠", "門扉重鎧", "Gate Heavy Armor", "門扉の重鎧", "관문 중갑")
add("门扉战盔", "門扉戰盔", "Gate Warhelm", "門扉の戦兜", "관문 전투 투구")
add("门扉战靴", "門扉戰靴", "Gate Warboots", "門扉の戦靴", "관문 전투 장화")

-- Bone-in-mouth hunger.
add("衔骨利斧", "銜骨利斧", "Bonebite Axe", "銜骨の鋭斧", "뼈를 문 도끼")
add("衔骨巨盾", "銜骨巨盾", "Bonebite Greatshield", "銜骨の大盾", "뼈를 문 대방패")
add("饥渴重铠", "飢渴重鎧", "Hunger Heavy Armor", "飢渇の重鎧", "굶주림의 중갑")
add("饥渴战盔", "飢渴戰盔", "Hunger Warhelm", "飢渇の戦兜", "굶주림의 전투 투구")
add("饥渴战靴", "飢渴戰靴", "Hunger Warboots", "飢渇の戦靴", "굶주림의 전투 장화")

-- Rift crystal.
add("裂晶魔典", "裂晶魔典", "Riftcrystal Tome", "裂晶の魔導書", "균열 수정 마도서")
add("裂晶法袍", "裂晶法袍", "Riftcrystal Robe", "裂晶のローブ", "균열 수정 로브")
add("裂晶法冠", "裂晶法冠", "Riftcrystal Crown", "裂晶の法冠", "균열 수정 관")
add("裂晶法靴", "裂晶法靴", "Riftcrystal Boots", "裂晶の魔法靴", "균열 수정 장화")

-- Starless chart.
add("无光魔杖", "無光魔杖", "Lightless Wand", "無光の魔杖", "빛 없는 마법봉")
add("星图法袍", "星圖法袍", "Star Chart Robe", "星図のローブ", "성도 로브")
add("星图法冠", "星圖法冠", "Star Chart Crown", "星図の法冠", "성도 관")
add("星图法靴", "星圖法靴", "Star Chart Boots", "星図の魔法靴", "성도 장화")

-- Gambler's echo.
add("轮盘手铳", "輪盤手銃", "Roulette Pistol", "ルーレットの短銃", "룰렛 권총")
add("赔率魔典", "賠率魔典", "Odds Tome", "賭率の魔導書", "배당률 마도서")
add("荷官外衣", "荷官外衣", "Dealer's Coat", "ディーラーの外套", "딜러의 외투")
add("掷骰面罩", "擲骰面罩", "Dice-Roller's Mask", "賽振りの仮面", "주사위꾼의 가면")
add("走桌软靴", "走桌軟靴", "Tablewalker Softboots", "卓巡りの柔らかい靴", "도박장 순회용 부드러운 장화")

return D
