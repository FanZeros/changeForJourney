local GameAlgoConfigLocal = {
    -- 单机回环模式下关闭 GameAlgo（无服务端代理、无埋点/远程配置需求）
    ENABLED = false,
}
-- 本地开发覆写文件。正式服 key 请配置在 .project/settings.json 的 @runtime.gamealgo.server_game_key
-- 或云端环境变量 GAMEALGO_KEY，避免本地覆写覆盖发布配置。
return GameAlgoConfigLocal
