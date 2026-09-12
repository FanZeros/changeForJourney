-- ============================================================================
-- MailConfig - 邮件配置（双端共享）
-- 职责: 定义所有系统邮件的内容和奖励
-- 运行端: shared（服务端读取配置推送，客户端可用于类型校验）
-- ============================================================================

local MailConfig = {}

--- 邮件列表（按 id 索引）
--- 每封邮件字段:
---   id           string   唯一标识
---   title        string   邮件标题
---   body         string   正文内容
---   type         string   "permanent" 长期 | "timed" 限时
---   remainDays   number   邮件过期天数（从发送日起算）
---   rewards      table[]  奖励列表 { type=string, amount=number }
MailConfig.MAILS = {
    {
        id         = "mail_open_gift",
        title      = "开服礼包",
        body       = "亲爱的团长，欢迎加入游戏！\n\n为庆祝开服，我们特别为你准备了一份丰厚的开服礼包，助你在冒险初期快速成长。\n\n请领取附件中的奖励，开启你的冒险之旅吧！\n\n——运营团队 敬上",
        type       = "permanent",
        remainDays = 30,
        rewards    = {
            { type = "privilege_point", amount = 5 },
            { type = "diamond",         amount = 888 },
        },
    },
    {
        id         = "mail_20_pull",
        title      = "惊喜二十连抽",
        body       = "亲爱的团长，感谢你的支持！\n\n为回馈广大冒险者，我们特别赠送20张冒险招募券，快去酒馆试试手气吧！\n\n也许命运之神会眷顾你，让你招募到传说中的英雄！\n\n——运营团队 敬上",
        type       = "permanent",
        remainDays = 30,
        rewards    = {
            { type = "adventure_ticket", amount = 20 },
        },
    },
    {
        id         = "mail_bug_compensate_server_overload",
        title      = "BUG补偿",
        body       = "亲爱的团长，非常抱歉！\n\n由于刚刚玩家过多，造成了服务器拥挤，给您带来了不好的游戏体验。目前问题已修复，服务器已恢复正常运行。\n\n为表歉意，特此赠送20张冒险招募券作为补偿，祝您抽卡好运！\n\n——运营团队 敬上",
        type       = "timed",
        excludeChallenger = true,
        remainDays = 7,
        rewards    = {
            { type = "adventure_ticket", amount = 20 },
        },
    },
    {
        id         = "mail_bug_compensate_ad_stuck",
        title      = "广告异常补偿",
        body       = "亲爱的团长，非常抱歉！\n\n我们发现上版本存在观看广告后特权点未正常到账的问题，可能导致您的部分广告观看未能获得应有的奖励。\n\n目前该问题已在新版本中修复。为表歉意，特此补偿15个特权点，请注意查收！\n\n——运营团队 敬上",
        type       = "timed",
        excludeChallenger = true,
        remainDays = 7,
        rewards    = {
            { type = "privilege_point", amount = 15 },
        },
    },
    {
        id         = "mail_dragon_boat_2026",
        title      = "端午节福利",
        body       = "亲爱的团长，端午安康！\n\n值此佳节，特别为你送上一份节日福利，祝你粽子飘香、冒险顺利！\n\n请领取附件中的奖励，愿好运常伴！\n\n——运营团队 敬上",
        type       = "timed",
        sendDate   = os.time({year=2026, month=6, day=19, hour=0, min=0, sec=0}),
        remainDays = 7,
        rewards    = {
            { type = "adventure_ticket", amount = 50 },
            { type = "diamond",          amount = 1888 },
        },
    },
    {
        id         = "mail_v1014_terminal_fix",
        title      = "V1.0.14 终焉神殿修复补偿",
        body       = "亲爱的团长，非常抱歉！\n\n我们发现噩梦难度的终焉神殿存在异常问题，部分玩家在通关或中途退出后出现无法前进、卡在关卡等情况。\n\n目前该问题已紧急修复。为表歉意，特此补偿10张冒险招募券，请注意查收！\n\n感谢各位团长的耐心与理解！\n\n——运营团队 敬上",
        type       = "timed",
        excludeChallenger = true,
        remainDays = 7,
        rewards    = {
            { type = "adventure_ticket", amount = 10 },
        },
    },
    {
        id         = "mail_v1015_balance_compensate",
        title      = "V1.0.15 版本大改补偿",
        body       = "亲爱的团长，你好！\n\n本次V1.0.15版本进行了一次重要的系统大改。\n\n由于原先版本的玩法过于畸形——所有角色都需要堆格挡才能通关，这严重限制了构筑多样性和游戏乐趣。因此我们做出了大幅度调整，包括属性系统重做、关卡等级压缩等改动。\n\n这可能会导致已有的高等级装备被降级，我们深知这会影响到大家的游戏体验，但这是为了游戏长期健康运营而必须经历的改动。\n\n希望各位团长能够理解，我们会持续优化平衡，让每种流派都有可玩性。\n\n为表歉意，特此补偿以下物资：\n· 精粹 ×200000\n· 冒险招募券 ×30\n· 特权点 ×30\n· 洗练石 ×100\n\n感谢你的支持与理解！\n\n——运营团队 敬上",
        type       = "permanent",
        excludeChallenger = true,
        remainDays = 30,
        rewards    = {
            { type = "essence",          amount = 200000 },
            { type = "adventure_ticket", amount = 30 },
            { type = "privilege_point",  amount = 30 },
            { type = "enhance_star",     amount = 100 },
        },
    },
    {
        id         = "mail_v1013_hotfix_compensate",
        title      = "V1.0.13 临时修复补偿",
        body       = "亲爱的团长，非常抱歉！\n\n我们发现V1.0.13版本更新后，市场商品出现了「刚更新就已售罄」的异常问题，同时通天塔挑战也出现了错误。\n\n目前上述问题均已紧急修复。为表歉意，特此补偿20个特权点，请注意查收！\n\n感谢各位团长的耐心与理解！\n\n——运营团队 敬上",
        type       = "timed",
        excludeChallenger = true,
        remainDays = 7,
        rewards    = {
            { type = "privilege_point", amount = 20 },
        },
    },

}

return MailConfig
