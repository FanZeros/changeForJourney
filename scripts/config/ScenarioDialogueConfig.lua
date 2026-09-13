-- ============================================================================
-- ScenarioDialogueConfig.lua — 情景对话数据配置（玩梗版 v2.1 · 全剧情梗味统一）
-- 对应策划配置: docs/配置文件/剧情-情景对话.txt
-- characterId: 立绘编号 (UI_DLH_X.png 中的 X)
-- mode: "large" = 大情景(全屏覆盖), "small" = 小情景(弹窗)
-- 人设规则: 主角贴合 DialogueConfig v2.0 玩梗人设; NPC/黑暗镜像台词同步玩梗化;
--           怪物名与 MonsterConfig(山海经版) 对齐(雷神/天狗/山膏/毕方/金乌…)
-- 放弃内部剧情: 原"正剧"文本全部废弃, 本文件即为唯一剧情源
-- ============================================================================

local ScenarioDialogueConfig = {}

--- 情景 1：新手过场动画结束后触发
--- 出现条件: 结束新手剧情过场动画时接上该情景
--- 结束后衔接角色选择界面
ScenarioDialogueConfig.SCENARIO_1 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    eyeOpen = true,
    steps = {
        { characterId = 1, name = "大狗嚼", text = "叫！远征长起床啦！出发通知已经钉在门板上了！今天讨伐山海怪！" },
        { characterId = 1, name = "大狗嚼", text = "有我开路，天狗都得绕着飞！别问为什么，问就是狗鼻子灵，尾巴已经摇成风扇了！" },
        { characterId = 2, name = "黄桃龙", text = "哇！黄桃龙起得比太阳还早！作为奖励，加一根烤肠不过分吧！不过分！" },
        { characterId = 2, name = "黄桃龙", text = "远征长放心！火焰魔法满状态！...大概！这次保证只烧怪物，不烧地图，更不烧远征长的头发！" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~风向通知：东南风，适合出征。" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~物资通知：干粮备齐。另，黄桃龙私藏的黄桃罐头三罐，已没收充公。不是嘴馋，只是走流程。" },
        { characterId = 1, name = "大狗嚼", text = "全员就位！叫！远征长，点将吧！今天让谁打头阵？" },
    },
}

--- 情景 2：选择大狗嚼后的小情景对话
--- 出现条件: 初始角色选择了大狗嚼（战士）
ScenarioDialogueConfig.SCENARIO_2 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "选我？！叫！汪！这就对了嘛！赏你一根珍藏大骨头！不对，是赏你一个靠谱的先锋！" },
        { characterId = 1, name = "大狗嚼", text = "远征长坐稳了！天狗算什么，在狗面前它就是只大鸟！出发！" },
    },
}

--- 情景 3：选择黄桃龙后的小情景对话
--- 出现条件: 初始角色选择了黄桃龙（法师）
ScenarioDialogueConfig.SCENARIO_3 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "诶诶诶？！真的选黄桃龙了吗？好耶好耶！黄桃龙这就给远征长表演一个火球！" },
        { characterId = 2, name = "黄桃龙", text = "看好了！火球术，发射！……放心放心，这次真的只烧怪物！...大概！" },
    },
}

--- 情景 4：选择叮咚鸡后的小情景对话
--- 出现条件: 初始角色选择了叮咚鸡（射手）
ScenarioDialogueConfig.SCENARIO_4 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~已读通知：先锋，叮咚鸡。执行。" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~行军通知：前方情况不明，箭比回声先到。落单勿慌，先听铃声。" },
    },
}

--- 情景 5：大狗嚼首通1-1 后的小情景对话（获得武器奖励：优质 练习用大剑）
--- 出现条件: 初始角色为大狗嚼时首通1-1
ScenarioDialogueConfig.SCENARIO_5 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "叫！赢啦！刚才那一口，咬得天狗都当场改了航线！……咦？草丛里硌到我爪子了？" },
        { characterId = 1, name = "大狗嚼", text = "是把大剑！品相绝佳！比我现在这根竹竿强了八百个山头！远征长，批准换装！叫！" },
    },
    rewards = {
        { type = "equip", templateId = "W7", quality = 2, level = 1 },
    },
}

--- 情景 6：黄桃龙首通1-1 后的小情景对话（获得武器奖励：优质 学徒木杖）
--- 出现条件: 初始角色为黄桃龙时首通1-1
ScenarioDialogueConfig.SCENARIO_6 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "炸到了！这次居然没炸到黄桃龙自己？！……等等，怪物堆里有东西在发光！" },
        { characterId = 2, name = "黄桃龙", text = "是一根木杖！肯定是被黄桃龙的火球震出来的！天意！黄桃龙果然是天选之龙！大概！" },
    },
    rewards = {
        { type = "equip", templateId = "W25", quality = 2, level = 1 },
    },
}

--- 情景 7：叮咚鸡首通1-1 后的小情景对话（获得武器奖励：优质 木质短弓）
--- 出现条件: 初始角色为叮咚鸡时首通1-1
ScenarioDialogueConfig.SCENARIO_7 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~战报：目标全灭，零脱靶。回收箭矢时，发现遗留短弓一把。" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~装备通知：木质短弓，手感优于现役。已登记回收。并非捡漏，只是流程。" },
    },
    rewards = {
        { type = "equip", templateId = "W37", quality = 2, level = 1 },
    },
}

--- 情景 8：大狗嚼首通1-2 后的小情景对话（获得护甲奖励：优质 硬铁重衣）
--- 出现条件: 初始角色为大狗嚼时首通1-2
ScenarioDialogueConfig.SCENARIO_8 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "嘶——山膏的爪子是真疼！毛都拍乱了！没事！狗子抗造！叫！" },
        { characterId = 1, name = "大狗嚼", text = "咦？！硬铁重衣！穿上它，山膏再挠就纯属给我按摩了！我穿我穿！远征长帮我扣扣子！" },
    },
    rewards = {
        { type = "equip", templateId = "A25", quality = 2, level = 1 },
    },
}

--- 情景 9：黄桃龙首通1-2 后的小情景对话（获得护甲奖励：优质 粗布长袍）
--- 出现条件: 初始角色为黄桃龙时首通1-2
ScenarioDialogueConfig.SCENARIO_9 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "呜……火球又打偏了一点点，把黄桃龙自己的裙边燎了个洞……远征长不许笑！" },
        { characterId = 2, name = "黄桃龙", text = "诶？角落有件粗布长袍！摸起来居然防火！太贴心了！换上！以后火球随便丢！大概！" },
    },
    rewards = {
        { type = "equip", templateId = "A49", quality = 2, level = 1 },
    },
}

--- 情景 10：叮咚鸡首通1-2 后的小情景对话（获得护甲奖励：优质 破烂鳞甲）
--- 出现条件: 初始角色为叮咚鸡时首通1-2
ScenarioDialogueConfig.SCENARIO_10 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~战报：遭遇豪彘，毫毛带电，手臂轻微刮伤。防护等级不足，需升级。" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~装备通知：拾取鳞甲一件，外观破损，防护合格。已着装。勿视，影响作战形象。" },
    },
    rewards = {
        { type = "equip", templateId = "A19", quality = 2, level = 1 },
    },
}

--- 情景 11：大狗嚼首通1-3 后的大情景对话（获得角色奖励：随机获得黄桃龙或叮咚鸡）
--- 出现条件: 初始角色为大狗嚼时首通1-3
ScenarioDialogueConfig.SCENARIO_11 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "呼——打完了！叫！等等，黄桃龙和叮咚鸡呢？就我这暴脾气都打完了，她们不该还没到啊！" },
        { characterId = 1, name = "大狗嚼", text = "不会被九尾狐拐走了吧？！远征长，原地等待——叫！后面有动静！耳朵竖起来了！" },
    },
    rewards = {
        { type = "hero", heroPool = { 2, 3 } },
    },
}

--- 情景 12：黄桃龙首通1-3 后的大情景对话（获得角色奖励：随机获得大狗嚼或叮咚鸡）
--- 出现条件: 初始角色为黄桃龙时首通1-3
ScenarioDialogueConfig.SCENARIO_12 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "赢了赢了！黄桃龙赢了！……诶？等一下，大狗嚼和叮咚鸡呢？她们不是说要跟上来的吗？" },
        { characterId = 2, name = "黄桃龙", text = "呜呜……不会是黄桃龙火球太响，把她们吓跑了吧……远征长等等她们嘛……啊！有人来了！" },
    },
    rewards = {
        { type = "hero", heroPool = { 1, 3 } },
    },
}

--- 情景 13：叮咚鸡首通1-3 后的大情景对话（获得角色奖励：随机获得大狗嚼或黄桃龙）
--- 出现条件: 初始角色为叮咚鸡时首通1-3
ScenarioDialogueConfig.SCENARIO_13 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~战报：清点人员——缺编两名。大狗嚼、黄桃龙未归队。" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~安抚通知：她们很能打，不必担心。……行军声，自后方接近。转入戒备。" },
    },
    rewards = {
        { type = "hero", heroPool = { 1, 2 } },
    },
}

--- 情景 14：获得大狗嚼后的跟上对话
--- 出现条件: 通过情景11-13获得大狗嚼
ScenarioDialogueConfig.SCENARIO_14 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "哈…哈…终于追上了！半路杀出一窝山膏，我咬了它们一整路！叫！现在，全员到齐，万事大吉！" },
    },
}

--- 情景 15：获得黄桃龙后的跟上对话
--- 出现条件: 通过情景11-13获得黄桃龙
ScenarioDialogueConfig.SCENARIO_15 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "等等黄桃龙！呼……刚才有只窫窳扑过来，黄桃龙一火球把它送走了……顺便把路标也送走了……但没关系！黄桃龙靠鼻子找到你们的！连大狗嚼都夸黄桃龙厉害！大概！" },
    },
}

--- 情景 16：获得叮咚鸡后的跟上对话
--- 出现条件: 通过情景11-13获得叮咚鸡
ScenarioDialogueConfig.SCENARIO_16 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~迟到通知：已发出。迟到原因：处理长右三只。……从现在起，队形紧凑，不再脱节。" },
    },
}

--- 情景 17：大狗嚼首通1-4 后的小情景（发现日志）
--- 出现条件: 初始角色为大狗嚼时首通0104
ScenarioDialogueConfig.SCENARIO_17 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "远征长！看我鼻子发现了什么！是我们丢的远征日志！叫！自己的东西隔着八座山都闻得出来！" },
    },
}

--- 情景 18：黄桃龙首通1-4 后的小情景（发现日志）
--- 出现条件: 初始角色为黄桃龙时首通0104
ScenarioDialogueConfig.SCENARIO_18 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "日……日志找到了！差点就被黄桃龙当引火纸了……还好黄桃龙看它印了字，没舍得烧！" },
    },
}

--- 情景 19：叮咚鸡首通1-4 后的小情景（发现日志）
--- 出现条件: 初始角色为叮咚鸡时首通0104
ScenarioDialogueConfig.SCENARIO_19 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~寻回通知：远征日志，已找到。页数齐全。归档。" },
    },
}

--- 情景 20：大狗嚼首通1-5 后的大情景（到达城镇）
--- 出现条件: 初始角色为大狗嚼时首通0105
ScenarioDialogueConfig.SCENARIO_20 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "呼——毕方的火是真烫！毛都烤酥了！不过没掉毛，整体打满分！叫！" },
        { characterId = 1, name = "大狗嚼", text = "闻到了！前面就是城镇！有烤肉味！……啊不对，是文明的味道！远征长，进城逛逛！" },
    },
}

--- 情景 21：黄桃龙首通1-5 后的大情景（到达城镇）
--- 出现条件: 初始角色为黄桃龙时首通0105
ScenarioDialogueConfig.SCENARIO_21 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "成功了！黄桃龙把金乌都打下来了！远征长快夸我！夸完请吃饭！" },
        { characterId = 2, name = "黄桃龙", text = "好累呀……前面就是城镇了吧！听说镇上有卖黄桃罐头的！要去要去！现在就去！" },
    },
}

--- 情景 22：叮咚鸡首通1-5 后的大情景（到达城镇）
--- 出现条件: 初始角色为叮咚鸡时首通0105
ScenarioDialogueConfig.SCENARIO_22 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~战报：雷神，击破。我方战损：左箭三支。敌方战损：全部。性价比：极高。" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~情报通知：前方出现聚集地。建议：补给、修整。出发。" },
    },
}

--- 情景 23：首次进入城镇
--- 出现条件: 首次进入城镇
ScenarioDialogueConfig.SCENARIO_23 = {
    mode = "small",
    steps = {
        { characterId = 11, name = "卫兵", text = "站住！城门重地！报上名来！……先别紧张，我只是按流程喊的。" },
    },
}

--- 情景 24：大狗嚼结束情景23后
--- 出现条件: 初始角色为大狗嚼时结束情景23
ScenarioDialogueConfig.SCENARIO_24 = {
    mode = "small",
    steps = {
        { characterId = 1,  name = "大狗嚼", text = "叫！别挥锤别挥锤！我们是正经远征队，持证上路！这位就是我们的远征长，实拍，如假包换！" },
        { characterId = 11, name = "卫兵", text = "外来远征队一律先去教堂领祝福，这是城里的规矩。跟我走吧，别乱跑。" },
    },
}

--- 情景 25：黄桃龙结束情景23后
--- 出现条件: 初始角色为黄桃龙时结束情景23
ScenarioDialogueConfig.SCENARIO_25 = {
    mode = "small",
    steps = {
        { characterId = 2,  name = "黄桃龙", text = "呜哇！黄桃龙们是正经远征队！…对吧远征长？快点头快点头！" },
        { characterId = 11, name = "卫兵", text = "……规矩不变，先去教堂领祝福，才能在城里自由活动。走吧。" },
    },
}

--- 情景 26：叮咚鸡结束情景23后
--- 出现条件: 初始角色为叮咚鸡时结束情景23
ScenarioDialogueConfig.SCENARIO_26 = {
    mode = "small",
    steps = {
        { characterId = 3,  name = "叮咚鸡", text = "叮咚~申报通知：过境远征队，无恶意，欲补给。可配合检查。" },
        { characterId = 11, name = "卫兵", text = "先去教堂领祝福，这是规矩，谁都一样。跟我来。" },
    },
}

--- 情景 27：初次进入教堂
--- 出现条件: 初次进入教堂
ScenarioDialogueConfig.SCENARIO_27 = {
    mode = "small",
    steps = {
        { characterId = 21, name = "圣女", text = "新面孔呀~想得到祝福的话，请抬头看向天空吧……对，就是现在，姿势虔诚一点~" },
    },
}

--- 情景 28：大狗嚼首次离开教堂
--- 出现条件: 初始角色为大狗嚼时首次离开教堂
ScenarioDialogueConfig.SCENARIO_28 = {
    mode = "small",
    steps = {
        { characterId = 1,  name = "大狗嚼", text = "叫！！全身的毛都竖起来了！力量在血管里汪汪叫！这就是神明的抚摸吗！" },
        { characterId = 11, name = "卫兵", text = "祝福到手，看来不是什么邪祟。城里随便逛吧。" },
        { characterId = 11, name = "卫兵", text = "想找新伙伴的话，去酒馆看看，招募告示天天贴满墙。" },
        { characterId = 1,  name = "大狗嚼", text = "走！远征长！酒馆！听说那儿的骨头管够，还是无限续的！叫！" },
    },
}

--- 情景 29：黄桃龙首次离开教堂
--- 出现条件: 初始角色为黄桃龙时首次离开教堂
ScenarioDialogueConfig.SCENARIO_29 = {
    mode = "small",
    steps = {
        { characterId = 2,  name = "黄桃龙", text = "远征长远征长！黄桃龙的火球好像变大了！这祝福也太超值了吧！" },
        { characterId = 11, name = "卫兵", text = "祝福到手，不是邪祟，城里随便逛。" },
        { characterId = 11, name = "卫兵", text = "想找新伙伴，去酒馆看看。" },
        { characterId = 2,  name = "黄桃龙", text = "酒馆！肯定有吃的！烤肉片！芝士汉堡！还有黄桃派！黄桃龙先预定三份！……不对，四份！" },
    },
}

--- 情景 30：叮咚鸡首次离开教堂
--- 出现条件: 初始角色为叮咚鸡时首次离开教堂
ScenarioDialogueConfig.SCENARIO_30 = {
    mode = "small",
    steps = {
        { characterId = 3,  name = "叮咚鸡", text = "叮咚~祝福通知：已接收。生效情况：待验证。" },
        { characterId = 11, name = "卫兵", text = "祝福到手，不是邪祟。城里随便逛吧。" },
        { characterId = 11, name = "卫兵", text = "想找新伙伴，去酒馆看看。" },
        { characterId = 3,  name = "叮咚鸡", text = "叮咚~行军通知：目的地，酒馆。出发。" },
    },
}

--- 情景 31：首次进入酒馆
--- 出现条件: 首次进入酒馆
ScenarioDialogueConfig.SCENARIO_31 = {
    mode = "small",
    steps = {
        { characterId = 13, name = "老板娘", text = "哎呀！新远征队呀~来得正好！墙上招募告示随便揭，揭一张，送一杯酸梅汤~" },
    },
    rewards = {
        { type = "scroll", count = 10 },
    },
}

--- 情景 32：大狗嚼首次离开酒馆
--- 出现条件: 初始角色为大狗嚼时首次离开酒馆
ScenarioDialogueConfig.SCENARIO_32 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "叫！招到新伙伴了！队伍变强了！……工资预算好像也一起变强了，远征长你多担待！" },
    },
}

--- 情景 33：黄桃龙首次离开酒馆
--- 出现条件: 初始角色为黄桃龙时首次离开酒馆
ScenarioDialogueConfig.SCENARIO_33 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "交到新朋友啦！黄桃龙宣布：谁敢欺负新伙伴，就先尝黄桃龙的火球！...大概！" },
    },
}

--- 情景 34：叮咚鸡首次离开酒馆
--- 出现条件: 初始角色为叮咚鸡时首次离开酒馆
ScenarioDialogueConfig.SCENARIO_34 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~评估通知：新伙伴，战斗意图合格。……能否共存，待观察。" },
    },
}

--- 情景 35：大狗嚼首通2-1 后的大情景（铁匠求救）
--- 出现条件: 初始角色为大狗嚼时首通0201
ScenarioDialogueConfig.SCENARIO_35 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "救命啊——！有人吗——！我的铺子要塌啦——！" },
        { characterId = 1,  name = "大狗嚼", text = "叫！有呼救声！远征长，救援是狗子的天职！冲！" },
    },
}

--- 情景 36：黄桃龙首通2-1 后的大情景（铁匠求救）
--- 出现条件: 初始角色为黄桃龙时首通0201
ScenarioDialogueConfig.SCENARIO_36 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "救命啊——！有人吗——！我的铺子要塌啦——！" },
        { characterId = 2,  name = "黄桃龙", text = "有人在喊救命！黄桃龙们快去！救人要紧，火球收着点用！" },
    },
}

--- 情景 37：叮咚鸡首通2-1 后的大情景（铁匠求救）
--- 出现条件: 初始角色为叮咚鸡时首通0201
ScenarioDialogueConfig.SCENARIO_37 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "救命啊——！有人吗——！我的铺子要塌啦——！" },
        { characterId = 3,  name = "叮咚鸡", text = "叮咚~救援通知：求救声，前方两百米。加速。" },
    },
}


--- 情景 38：大狗嚼首次全体阵亡失败的大情景
--- 出现条件: 初始角色为大狗嚼时首次全体阵亡失败
ScenarioDialogueConfig.SCENARIO_38 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 1,  name = "大狗嚼",   text = "远征长……狗子……好像要掉线了……叫……" },
        { characterId = 5,  name = "神秘少女", text = "（一道神秘的光闪过）" },
        { characterId = 5,  name = "神秘少女", text = "哟，这就倒啦？新手保护期还没过呢~" },
        { characterId = 5,  name = "神秘少女", text = "没有我的批准，谁准你们在这里掉线的？站起来，继续赶路~" },
        { characterId = 1,  name = "大狗嚼",   text = "叫？！我复活了？！远征长，刚才那位姐姐是谁？比神明还豪横！" },
    },
}

--- 情景 39：黄桃龙首次全体阵亡失败的大情景
--- 出现条件: 初始角色为黄桃龙时首次全体阵亡失败
ScenarioDialogueConfig.SCENARIO_39 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 2,  name = "黄桃龙",   text = "呜呜远征长……黄桃龙的眼前……开始转圈圈了……" },
        { characterId = 5,  name = "神秘少女", text = "（一道神秘的光闪过）" },
        { characterId = 5,  name = "神秘少女", text = "哟，这就倒啦？新手保护期还没过呢~" },
        { characterId = 5,  name = "神秘少女", text = "没有我的批准，谁准你们在这里掉线的？站起来，继续赶路~" },
        { characterId = 2,  name = "黄桃龙",   text = "呜哇！黄桃龙回来了！谢谢姐姐！姐姐比黄桃罐头还甜！" },
    },
}

--- 情景 40：叮咚鸡首次全体阵亡失败的大情景
--- 出现条件: 初始角色为叮咚鸡时首次全体阵亡失败
ScenarioDialogueConfig.SCENARIO_40 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 3,  name = "叮咚鸡",   text = "叮……咚……远征长……信号……中断……" },
        { characterId = 5,  name = "神秘少女", text = "（一道神秘的光闪过）" },
        { characterId = 5,  name = "神秘少女", text = "哟，这就倒啦？新手保护期还没过呢~" },
        { characterId = 5,  name = "神秘少女", text = "没有我的批准，谁准你们在这里掉线的？站起来，继续赶路~" },
        { characterId = 3,  name = "叮咚鸡",   text = "叮咚~状态通知：信号恢复。来源：不明。……记下了。" },
    },
}

--- 情景 41：大狗嚼首次进入关卡0204（铁匠误会）
--- 出现条件: 初始角色为大狗嚼时首次进入关卡0204
ScenarioDialogueConfig.SCENARIO_41 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "愤怒的铁匠", text = "又是你们这帮打家劫舍的！吃我一锤！四十米长的大锤了解一下！" },
        { characterId = 1,  name = "大狗嚼",      text = "叫？！大爷冷静！我们刚在教堂盖过祝福章的！正经远征队，有编号的那种！" },
    },
}

--- 情景 42：黄桃龙首次进入关卡0204（铁匠误会）
--- 出现条件: 初始角色为黄桃龙时首次进入关卡0204
ScenarioDialogueConfig.SCENARIO_42 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "愤怒的铁匠", text = "又是你们这帮打家劫舍的！吃我一锤！四十米长的大锤了解一下！" },
        { characterId = 2,  name = "黄桃龙",      text = "误会！全是误会！黄桃龙们只是路过的！……远征长快解释，黄桃龙的火球已经捏手里了！" },
    },
}

--- 情景 43：叮咚鸡首次进入关卡0204（铁匠误会）
--- 出现条件: 初始角色为叮咚鸡时首次进入关卡0204
ScenarioDialogueConfig.SCENARIO_43 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "愤怒的铁匠", text = "又是你们这帮打家劫舍的！吃我一锤！四十米长的大锤了解一下！" },
        { characterId = 3,  name = "叮咚鸡",      text = "叮咚~澄清通知：身份不符。另：执锤距离不足四十米，威胁有限。……但，应战。" },
    },
}

--- 情景 44：大狗嚼首次通关关卡0204（铁匠道歉）
--- 出现条件: 初始角色为大狗嚼时首次通关关卡0204
ScenarioDialogueConfig.SCENARIO_44 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "停停停！等等！你们剑上没有黑气……你们真不是那伙人？！" },
        { characterId = 1,  name = "大狗嚼", text = "叫！本来就不是啊！抡锤之前一句都不问，差点把狗子锤出脑震荡！" },
        { characterId = 10, name = "铁匠", text = "抱歉抱歉，最近有伙穿得跟你们很像的家伙劫了商队……这样，作为赔罪，来我的铁匠铺，装备强化全包了！" },
    },
}

--- 情景 45：黄桃龙首次通关关卡0204（铁匠道歉）
--- 出现条件: 初始角色为黄桃龙时首次通关关卡0204
ScenarioDialogueConfig.SCENARIO_45 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "停停停！等等！你的火焰没有邪气……你们真不是那伙人？！" },
        { characterId = 2,  name = "黄桃龙", text = "早说了不是！让你听你不听！哼！知道错了吧！……那么，赔偿呢？" },
        { characterId = 10, name = "铁匠", text = "抱歉抱歉，最近有伙穿得跟你们很像的家伙劫了商队……这样，作为赔罪，来我的铁匠铺，装备强化全包了！" },
    },
}

--- 情景 46：叮咚鸡首次通关关卡0204（铁匠道歉）
--- 出现条件: 初始角色为叮咚鸡时首次通关关卡0204
ScenarioDialogueConfig.SCENARIO_46 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "停停停！等等！你的箭上没有暗响……你们真不是那伙人？！" },
        { characterId = 3,  name = "叮咚鸡", text = "叮咚~提问通知：'那伙人'，什么来头？" },
        { characterId = 10, name = "铁匠", text = "抱歉抱歉，最近有伙穿得跟你们很像的家伙劫了商队……这样，作为赔罪，来我的铁匠铺，装备强化全包了！" },
    },
}

--- 情景 47：首次进入铁匠铺
--- 出现条件: 首次进入铁匠铺
ScenarioDialogueConfig.SCENARIO_47 = {
    mode = "small",
    steps = {
        { characterId = 10, name = "铁匠", text = "欢迎欢迎！把武器拿来我瞅瞅……放心，我这锤子，专治各种卷刃！" },
    },
    rewards = {
        { type = "scroll", count = 20 },
    },
}

--- 情景 48：大狗嚼首次离开铁匠铺
--- 出现条件: 初始角色为大狗嚼时首次离开铁匠铺
ScenarioDialogueConfig.SCENARIO_48 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "叫！剑亮得能当镜子照！这下啃……咳，砍怪物更带劲了！" },
    },
}

--- 情景 49：黄桃龙首次离开铁匠铺
--- 出现条件: 初始角色为黄桃龙时首次离开铁匠铺
ScenarioDialogueConfig.SCENARIO_49 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "唔哇，法杖蓄魔力满格！感觉能连丢十个火球！……先说好，十个里偏一个，属于正常发挥！" },
    },
}

--- 情景 50：叮咚鸡首次离开铁匠铺
--- 出现条件: 初始角色为叮咚鸡时首次离开铁匠铺
ScenarioDialogueConfig.SCENARIO_50 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~装备通知：箭矢，已校直。命中率预估上调。……满意。" },
    },
}

--- 情景 51：大狗嚼首次通关关卡0205
--- 出现条件: 初始角色为大狗嚼时首次通关关卡0205
ScenarioDialogueConfig.SCENARIO_51 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "唔，这波的怪物有点扛咬……叫！听说城里新开了竞技场，去那练练爪子？" },
    },
}

--- 情景 52：黄桃龙首次通关关卡0205
--- 出现条件: 初始角色为黄桃龙时首次通关关卡0205
ScenarioDialogueConfig.SCENARIO_52 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "呜！这怪物皮好厚！黄桃龙的火球都烧不动了……需要加练！听说竞技场很锻炼龙！" },
    },
}

--- 情景 53：叮咚鸡首次通关关卡0205
--- 出现条件: 初始角色为叮咚鸡时首次通关关卡0205
ScenarioDialogueConfig.SCENARIO_53 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "……战况，比预期艰难。叮咚~建议通知：前往竞技场，特训。" },
    },
}

--- 情景 54：首次进入竞技场
--- 出现条件: 首次进入竞技场
ScenarioDialogueConfig.SCENARIO_54 = {
    mode = "small",
    steps = {
        { characterId = 9,  name = "村长",  text = "就这么办，竞技场的场子，你给我罩住了，我放心。" },
        { characterId = 20, name = "黑衣人", text = "包在我身上，保证场场'精彩'，让您满意。（离开）" },
        { characterId = 9,  name = "村长",  text = "哦？新面孔！来来来，登记一下就能上场！赢了有奖，输了……也有安慰奖！" },
    },
}

-- 情景 55：大狗嚼首次通关关卡1305
-- 出现条件: 初始角色为大狗嚼时首次通关关卡1305
ScenarioDialogueConfig.SCENARIO_55 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "叫！刚才好像掉了什么亮闪闪的东西！远征长快来看！" },
    },
}

-- 情景 56：黄桃龙首次通关关卡1305
-- 出现条件: 初始角色为黄桃龙时首次通关关卡1305
ScenarioDialogueConfig.SCENARIO_56 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "这是什么……上面有旧旧的痕迹，黄桃龙闻闻……是以前其他远征队留下的遗物吗？" },
    },
}

-- 情景 57：叮咚鸡首次通关关卡1305
-- 出现条件: 初始角色为叮咚鸡时首次通关关卡1305
ScenarioDialogueConfig.SCENARIO_57 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~发现通知：前任远征队遗留物一件。已封存。……默哀半秒。" },
    },
}

--- 情景 58：大狗嚼首通3-5 后的小情景对话（副本引导）
--- 出现条件: 初始角色为大狗嚼时首通0305
ScenarioDialogueConfig.SCENARIO_58 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "报告！叫！前方发现金矿洞！我可以去啃两……咳咳，探查两下吗！" },
    },
}

--- 情景 59：黄桃龙首通3-5 后的小情景对话（副本引导）
--- 出现条件: 初始角色为黄桃龙时首通0305
ScenarioDialogueConfig.SCENARIO_59 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "哇！！洞里全是金灿灿的！黄桃龙的眼睛都会发光了！远征长，挖矿！挖矿！" },
    },
}

--- 情景 60：叮咚鸡首通3-5 后的小情景对话（副本引导）
--- 出现条件: 初始角色为叮咚鸡时首通0305
ScenarioDialogueConfig.SCENARIO_60 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~风险通知：矿洞，未知。……未收到禁止进入的通知。默认结论：可进。" },
    },
}

--- 情景 61：首次进入终端关卡0999
--- 出现条件: 首次进入关卡0999
ScenarioDialogueConfig.SCENARIO_61 = {
    mode = "large",
    background = "image/关卡地图/MAP_999.png",
    steps = {
        { characterId = 4, name = "？？？", text = "哦？又走到这扇门前了？真勤快啊，小家伙们~" },
        { characterId = 1, name = "大狗嚼", text = "叫！你就是让山海怪物满地跑的元凶？！鼻子不会骗人，就是你！" },
        { characterId = 2, name = "黄桃龙", text = "大魔王受死吧！黄桃龙代表月亮、代表黄桃、代表远征长消灭你！" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~开战通知：已发出。箭，已上弦。" },
    },
}

--- 情景 62：通关关卡0999（轮回前播放）
--- 出现条件: 通关关卡0999，在进入轮回前播放
ScenarioDialogueConfig.SCENARIO_62 = {
    mode = "small",
    steps = {
        { characterId = 4, name = "？？？", text = "实力不错嘛~小家伙们~不过嘛……故事讲到这，就该翻页了！下一页，继续哦~" },
    },
}

--- 情景 63：首次进入困难模式关卡2401
--- 出现条件: 首次进入关卡2401
ScenarioDialogueConfig.SCENARIO_63 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "远征长！新的一圈开始了！叫！这次连闹钟都省了，狗子自然醒！" },
        { characterId = 1, name = "大狗嚼", text = "有我开路，天狗都得靠边站！就是……这次的怪物好像更硬了？不管，狗子不怕！叫！" },
        { characterId = 2, name = "黄桃龙", text = "哇，天气不错！最适合黄桃龙发挥了！火焰魔法满状态！...大概！" },
        { characterId = 2, name = "黄桃龙", text = "远征长放心！这次绝对不烧地图！……就算烧了，也是火球自己的主意，跟黄桃龙无关！" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~风向通知：正常。难度通知：上调。心态通知：稳定。" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~物资通知：干粮备齐。黄桃罐头存放位置：黄桃龙够不到的那一格。" },
        { characterId = 1, name = "大狗嚼", text = "全员就位！叫！第二轮，出发！" },
    },
}

--- 情景 64：首次进入关卡2505（假大狗嚼遭遇）
--- 出现条件: 首次进入关卡2505
ScenarioDialogueConfig.SCENARIO_64 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 6, name = "大狗嚼？", text = "远征长……你怎么一个人走这么远？我们不是说好，一起打败大魔王的吗……" },
        { characterId = 1, name = "大狗嚼", text = "叫?!这、这是谁？！远征长！那边有只……我？！" },
        { characterId = 6, name = "大狗嚼？", text = "远征长找到新的大狗嚼了嘛？不允许！汪——汪——！" },
        { characterId = 6, name = "大狗嚼？", text = "远征长只能属于我这只狗！别的狗，统统不许靠近！" },
        { characterId = 1, name = "大狗嚼", text = "喂喂，正主在这呢！叫！远征长别怕，是只野狗在冒充我！一起上，教教它狗界的规矩！" },
    },
}

--- 情景 65：首次进入关卡2705（假黄桃龙遭遇）
--- 出现条件: 首次进入关卡2705
ScenarioDialogueConfig.SCENARIO_65 = {
    mode = "large",
    background = "image/关卡地图/MAP_4.png",
    steps = {
        { characterId = 7, name = "黄桃龙？", text = "远征长~人家等你好久了呢~我们不是刚刚一起拯救了世界嘛~" },
        { characterId = 2, name = "黄桃龙", text = "咦？！这、这是另一个黄桃龙吗？！黄桃龙照镜子都没这么像！" },
        { characterId = 7, name = "黄桃龙？", text = "呜呜呜……远征长不要人家了吗~说好要组一辈子远征队的~" },
        { characterId = 7, name = "黄桃龙？", text = "既然你身边站了别的黄桃龙……那你们就一起留下吧~永远~哦~" },
        { characterId = 2, name = "黄桃龙", text = "远征长小心！她虽然和黄桃龙长得像，但她眼神凶凶的！黄桃龙的直觉：是坏人！大概！" },
    },
}

--- 情景 67：首次进入关卡2905（假叮咚鸡遭遇）
--- 出现条件: 首次进入关卡2905
ScenarioDialogueConfig.SCENARIO_67 = {
    mode = "large",
    background = "image/关卡地图/MAP_6.png",
    steps = {
        { characterId = 8, name = "叮咚鸡？", text = "远征长……你来了。请……不要再……继续前进了" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~疑问通知：理由？" },
        { characterId = 8, name = "叮咚鸡？", text = "只要一直前进……就永远停不下来……通知……发不完了……" },
        { characterId = 8, name = "叮咚鸡？", text = "快……杀了我……" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~通知：……已收到。箭，已搭。" },
    },
}

--- 情景 68：首次进入困难终端关卡1999
--- 出现条件: 首次进入关卡1999
ScenarioDialogueConfig.SCENARIO_68 = {
    mode = "large",
    background = "image/关卡地图/MAP_999.png",
    steps = {
        { characterId = 4, name = "？？？", text = "又见面了，真有毅力。" },
        { characterId = 4, name = "？？？", text = "这位「远征长」——亲手把过去的伙伴送走，是什么滋味呢？" },
        { characterId = 4, name = "？？？", text = "一路上收下的那些「馈赠」，还合胃口吗？" },
        { characterId = 1, name = "大狗嚼", text = "叫！胡说八道！那些只是冒牌货！远征长才不会抛弃我们！" },
        { characterId = 2, name = "黄桃龙", text = "少废话！黄桃龙代表月亮消灭你！这次可是新的一轮！" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~开战通知：箭雨，覆盖式。" },
        { characterId = 4, name = "？？？", text = "哦？真的只是「冒牌货」吗？呵呵……" },
    },
}

--- 情景 69：通关关卡1999（轮回前播放）
--- 出现条件: 通关关卡1999，在进入轮回前播放
ScenarioDialogueConfig.SCENARIO_69 = {
    mode = "large",
    background = "image/关卡地图/MAP_999.png",
    steps = {
        { characterId = 4, name = "？？？", text = "越来越强了嘛，小家伙们，真让人期待~" },
        { characterId = 4, name = "？？？", text = "不过……还是那句话，请继续上路吧！" },
        { characterId = 4, name = "？？？", text = "下一轮的「礼物」，我已经备好了哦~" },
    },
}

--- 情景 70：首次进入噩梦模式关卡4701
--- 出现条件: 首次进入关卡4701
ScenarioDialogueConfig.SCENARIO_70 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 6, name = "大狗嚼？", text = "远征长！别做白日梦了！出发了！" },
        { characterId = 6, name = "大狗嚼？", text = "有我开路，士兵都得绕道走！嘿嘿，狩猎，要开始了！" },
        { characterId = 7, name = "黄桃龙？", text = "天气真好~最适合狩猎了呢~" },
        { characterId = 7, name = "黄桃龙？", text = "我的火焰今天状态超好~...大概！只要别把远征长您烧到就行~" },
        { characterId = 8, name = "叮咚鸡？", text = "...风向正常。适合行动。" },
        { characterId = 8, name = "叮咚鸡？", text = "...物资里全是冒险家的遗物，快装不下了。" },
        { characterId = 6, name = "大狗嚼？", text = "都准备好了！走吧！狩猎开始！" },
        { characterId = 1, name = "大狗嚼", text = "远征长！远征长！发什么呆呀，叫？做噩梦了？梦里是不是也有我？！" },
        { characterId = 2, name = "黄桃龙", text = "远征长今天怪怪的……黄桃龙决定分你一半黄桃罐头压压惊！" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~状态通知：远征长，走神。处理方案：出发，走着走着就好了。" },
    },
}

--- 情景 71：首次进入关卡4705（假大狗嚼独白）
--- 出现条件: 首次进入关卡4705
ScenarioDialogueConfig.SCENARIO_71 = {
    mode = "small",
    steps = {
        { characterId = 6, name = "大狗嚼？", text = "远征长……我们不是说好，要一直一起狩猎的么……" },
    },
}

--- 情景 72：首次进入关卡4805（假黄桃龙独白）
--- 出现条件: 首次进入关卡4805
ScenarioDialogueConfig.SCENARIO_72 = {
    mode = "small",
    steps = {
        { characterId = 7, name = "黄桃龙？", text = "远征长……今天又'送走'了好多冒险家呢……可是，还是没有远征长有意思……" },
    },
}

--- 情景 73：首次进入关卡4905（假叮咚鸡独白）
--- 出现条件: 首次进入关卡4905
ScenarioDialogueConfig.SCENARIO_73 = {
    mode = "small",
    steps = {
        { characterId = 8, name = "叮咚鸡？", text = "远征长……你身边的那些人……好碍眼……" },
    },
}

return ScenarioDialogueConfig
