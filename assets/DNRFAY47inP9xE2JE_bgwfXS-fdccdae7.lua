-- ============================================================================
-- 游戏事件名称常量 - 所有模块间通信的事件定义
-- ============================================================================

local GameEvents = {
    -- 状态事件
    STATE_LOADED         = "CG_StateLoaded",
    STATE_SAVED          = "CG_StateSaved",

    -- 卡牌事件
    CARD_DRAWN           = "CG_CardDrawn",
    CARD_PLACED          = "CG_CardPlaced",
    CARD_REMOVED         = "CG_CardRemoved",
    CARD_MERGED          = "CG_CardMerged",
    CARD_UPGRADED        = "CG_CardUpgraded",

    -- 棋盘事件
    BOARD_CHANGED        = "CG_BoardChanged",
    SLOT_SELECTED        = "CG_SlotSelected",

    -- 经济事件
    CURRENCY_CHANGED     = "CG_CurrencyChanged",
    IDLE_TICK            = "CG_IdleTick",
    OFFLINE_REWARD       = "CG_OfflineReward",

    -- 收集事件
    CARD_UNLOCKED        = "CG_CardUnlocked",
    DECK_CHANGED         = "CG_DeckChanged",

    -- 玩家事件
    PLAYER_LEVEL_UP      = "CG_PlayerLevelUp",
    PLAYER_EXP_CHANGED   = "CG_PlayerExpChanged",
    PLAYER_POWER_CHANGED = "CG_PlayerPowerChanged",

    -- UI 事件
    SHOP_OPENED          = "CG_ShopOpened",
    SHOP_CLOSED          = "CG_ShopClosed",

    -- 副本事件
    DUNGEON_SWEEP_DONE   = "CG_DungeonSweepDone",
    DUNGEON_FLOOR_CLEAR  = "CG_DungeonFloorClear",
    DUNGEON_ENTER_BATTLE = "CG_DungeonEnterBattle",
}

return GameEvents
