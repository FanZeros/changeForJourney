---@meta

--- Score Module - Game scoring, leaderboard, messaging and item system Lua API
--- Auto-generated from docs/Leaderboard_CloudVariable_API.md

---@alias ScoreValue number|string|table

---@class ScoreEvents Callback table for async operations
---@field ok? fun(...) Success callback
---@field error? fun(code: integer, reason: string) Error callback
---@field timeout? fun() Timeout callback

---@class ScoreData Score data returned from queries
---@field [string] ScoreValue

---@class RankItem Rank list item
---@field player number Player user ID (注意是 number 不是 string)
---@field score ScoreData Any type score data (通过 Set 写入)
---@field iscore ScoreData Integer type score data (通过 SetInt/Add 写入)
---@field sscore ScoreData String type score data (已废弃，总是空表)

---@class MessageItem Message data
---@field message_id integer Message ID
---@field src_user_id integer Sender user ID
---@field target_user_id integer Receiver user ID
---@field key string Message type key
---@field read boolean Is read
---@field value any Message content
---@field time integer Timestamp

---@class ListItem List item data
---@field user_id integer User ID
---@field key string List key
---@field value any Item value
---@field list_id integer List ID
---@field time integer Timestamp

---@class Item Item data
---@field user_id integer User ID
---@field key string Item key
---@field item_name string Item name
---@field expire_type integer Expire type: 0=permanent, 1=deadline, 2=duration
---@field expire_time integer|string Expire time
---@field count integer Item count
---@field value any Extra data
---@field item_id integer Item ID

---@class MoneyDetail Money detail
---@field key string Currency key
---@field value number Currency amount
---@field user_id integer User ID

---@class ScoreCommit Commit object for batch operations
local ScoreCommit = {}

--- Commit all changes
---@param description string Operation description
---@param events? ScoreEvents Callback table
---@return nil
function ScoreCommit:commit(description, events) end

--- Set any type client score (client only, no player_id needed)
---@param key string Score key
---@param value ScoreValue Score value
---@return nil
function ScoreCommit:client_score_set(key, value) end

--- Set integer client score (client only, no player_id needed)
---@param key string Score key
---@param value integer Score value
---@return nil
function ScoreCommit:client_score_seti(key, value) end

--- Add integer client score (client only, no player_id needed)
---@param key string Score key
---@param delta integer Delta value
---@return nil
function ScoreCommit:client_score_addi(key, delta) end

--- Delete any type client score (client only, no player_id needed)
---@param key string Score key
---@return nil
function ScoreCommit:client_score_delete(key) end

--- Delete integer client score (client only, no player_id needed)
---@param key string Score key
---@return nil
function ScoreCommit:client_score_deletei(key) end

--- Set any type server score (server only)
---@param player_id integer Player ID
---@param key string Score key
---@param value ScoreValue Score value
---@return nil
function ScoreCommit:score_set(player_id, key, value) end

--- Set integer server score (server only)
---@param player_id integer Player ID
---@param key string Score key
---@param value integer Score value
---@return nil
function ScoreCommit:score_seti(player_id, key, value) end

--- Add integer server score (server only)
---@param player_id integer Player ID
---@param key string Score key
---@param delta integer Delta value
---@param target_map? string Target map name
---@return nil
function ScoreCommit:score_addi(player_id, key, delta, target_map) end

--- Set string server score (server only)
---@param player_id integer Player ID
---@param key string Score key
---@param value string Score value
---@return nil
function ScoreCommit:score_sets(player_id, key, value) end

--- Delete any type server score (server only)
---@param player_id integer Player ID
---@param key string Score key
---@return nil
function ScoreCommit:score_delete(player_id, key) end

--- Delete integer server score (server only)
---@param player_id integer Player ID
---@param key string Score key
---@return nil
function ScoreCommit:score_deletei(player_id, key) end

--- Delete string server score (server only)
---@param player_id integer Player ID
---@param key string Score key
---@return nil
function ScoreCommit:score_deletes(player_id, key) end

--- Add money (server only)
---@param player_id integer Player ID
---@param key string Currency key
---@param amount number Amount to add
---@return nil
function ScoreCommit:money_add(player_id, key, amount) end

--- Cost money (server only, amount must > 0)
---@param player_id integer Player ID
---@param key string Currency key
---@param amount number Amount to cost
---@return nil
function ScoreCommit:money_cost(player_id, key, amount) end

--- Platform money cost (server only)
---@param player_id integer Player ID
---@param order any Order data
---@return nil
function ScoreCommit:platform_money_cost(player_id, order) end

--- Add list item (server only)
---@param player_id integer Player ID
---@param key string List key
---@param value any Item value
---@return integer list_id
function ScoreCommit:list_add(player_id, key, value) end

--- Modify list item (server only, first two params are placeholders)
---@param _ any Placeholder (ignored)
---@param _ any Placeholder (ignored)
---@param list_id integer List ID
---@param value any New value
---@return nil
function ScoreCommit:list_modify(_, _, list_id, value) end

--- Delete list item (server only, first two params are placeholders)
---@param _ any Placeholder (ignored)
---@param _ any Placeholder (ignored)
---@param list_id integer List ID
---@return nil
function ScoreCommit:list_delete(_, _, list_id) end

--- Modify list item key (server only)
---@param list_id integer List ID
---@param key string New key
---@return nil
function ScoreCommit:list_modify_key(list_id, key) end

--- Add item (server only)
---@param player_id integer Player ID
---@param key string Item key
---@param item_name string Item name
---@param count integer Item count
---@param value any Extra data
---@param expire_type integer Expire type: 0=permanent, 1=deadline, 2=duration
---@param expire_time? integer|string Expire time
---@return nil
function ScoreCommit:item_add(player_id, key, item_name, count, value, expire_type, expire_time) end

--- Use item (server only)
---@param player_id integer Player ID
---@param item_id integer Item ID
---@param count integer Use count
---@return nil
function ScoreCommit:item_use(player_id, item_id, count) end

--- Create named score (server only)
---@param key string Score key
---@param name string Name
---@param value any Value
---@return nil
function ScoreCommit:name_new(key, name, value) end

--- Delete named score (server only)
---@param key string Score key
---@param name string Name
---@return nil
function ScoreCommit:name_delete(key, name) end

--- Add score with limit (server only)
---@param player_id integer Player ID
---@param key string Score key
---@param value number Value to add
---@param limit number Max limit
---@param refresh_type? string Refresh type
---@param refresh_count? integer Refresh count
---@return nil
function ScoreCommit:withlimit_add(player_id, key, value, limit, refresh_type, refresh_count) end

--- Reset score with limit (server only)
---@param player_id integer Player ID
---@param key string Score key
---@return nil
function ScoreCommit:withlimit_reset(player_id, key) end

--- Set world data (server only)
---@param player_id integer Player ID
---@param key string Data key
---@param world_id integer World ID
---@param value any Data value
---@return nil
function ScoreCommit:world_data_set(player_id, key, world_id, value) end

--- Delete world data (server only)
---@param player_id integer Player ID
---@param key string Data key
---@param world_id integer World ID
---@return nil
function ScoreCommit:world_data_delete(player_id, key, world_id) end

--- Add world list item (server only)
---@param player_id integer Player ID
---@param key string List key
---@param world_id integer World ID
---@param value any Item value
---@return nil
function ScoreCommit:world_list_add(player_id, key, world_id, value) end

--- Modify world list item (server only)
---@param list_id integer List ID
---@param value any New value
---@return nil
function ScoreCommit:world_list_modify(list_id, value) end

--- Delete world list item (server only)
---@param list_id integer List ID
---@return nil
function ScoreCommit:world_list_delete(list_id) end

---@class score Score module
score = {}

--- Client readonly map identifier
---@type string
score.readonly_map = "ClientReadonlyMap"

--- Client read-write map identifier
---@type string
score.readwrite_map = "ClientReadWriteMap"

-- ============================================================================
-- Client API
-- ============================================================================

--- Query client score data
---@param player_id integer|nil Player ID, nil for current player
---@param events? ScoreEvents Callback table
---@param ... string Score keys to query
---@return nil
---@overload fun(player_id: integer|nil, key1: string, ...): nil
function score.client_score_init(player_id, events, ...) end

--- Get client score rank list
---@param key string Rank key
---@param start integer Start rank (0-based)
---@param count integer Number of items to get
---@param type? string Score type, default "iscore"
---@param events ScoreEvents Callback table
---@param ... string Additional score keys to return
---@return nil
function score.client_get_rank_list(key, start, count, type, events, ...) end

--- Get player's rank in client score leaderboard
---@param player_id integer Player ID
---@param key string Rank key
---@param type? string Score type, default "iscore"
---@param events? ScoreEvents Callback table
---@return nil
function score.client_get_user_rank(player_id, key, type, events) end

--- Get total count of client score leaderboard
---@param key string Rank key
---@param type? string Score type, default "iscore"
---@param events ScoreEvents Callback table
---@return nil
function score.client_get_rank_total(key, type, events) end

--- Get a commit object for batch operations (client version)
---@return ScoreCommit
function score.get_commit() end

-- ============================================================================
-- Server API
-- ============================================================================

--- Query server score data (server only)
---@param map_name? string Map name, nil for current map
---@param player_id integer|integer[]|nil Player ID, array for multi-player query, nil for current player
---@param events? ScoreEvents Callback table
---@param ... string Score keys to query
---@return nil
function score.score_init(map_name, player_id, events, ...) end

--- Query money data (server only)
---@param map_name? string Map name
---@param player_id integer|integer[]|nil Player ID, supports array for multi-player query
---@param events? ScoreEvents Callback table
---@param ... string|table Currency keys
---@return nil
function score.money_init(map_name, player_id, events, ...) end

--- Query message list (server only)
---@param player_id integer|nil Player ID
---@param key string Message type key
---@param read boolean|nil Filter by read status, nil for all
---@param events ScoreEvents Callback table
---@return nil
function score.message_query(player_id, key, read, events) end

--- Send message (server only)
---@param player_id integer Sender player ID
---@param key string Message type key
---@param target_user_id integer Receiver user ID
---@param value any Message content
---@param events? ScoreEvents Callback table
---@return integer message_id
function score.message_send(player_id, key, target_user_id, value, events) end

--- Modify message read status (server only)
---@param _ any Placeholder (ignored)
---@param message_id integer Message ID
---@param read boolean Read status
---@param events? ScoreEvents Callback table
---@return nil
function score.message_modify_read(_, message_id, read, events) end

--- Delete message (server only)
---@param _ any Placeholder (ignored)
---@param message_id integer Message ID
---@param events? ScoreEvents Callback table
---@return nil
function score.message_delete(_, message_id, events) end

--- Subscribe to channel (server only)
---@param player_id integer Player ID
---@param channel_name string Channel name
---@param events ScoreEvents Callback table
---@return boolean success
function score.subscribe_channel(player_id, channel_name, events) end

--- Subscribe to channel message without user ID (server only)
---@param channel_name string Channel name
---@param events ScoreEvents Callback table
---@return boolean success
function score.subscribe_message(channel_name, events) end

--- Unsubscribe from channel message (server only)
---@param channel_name string Channel name
---@return boolean success
function score.unsubscribe_message(channel_name) end

--- Publish message to channel (server only)
---@param channel_name string Channel name
---@param value any Message content
---@return nil
function score.publish_message(channel_name, value) end

--- Unsubscribe from channel (server only)
---@param player_id integer Player ID
---@param channel_name string Channel name
---@return nil
function score.unsubscribe_channel(player_id, channel_name) end

--- Query list data (server only)
---@param map_name? string Map name
---@param player_id integer|nil Player ID
---@param key string List key
---@param limit? integer Number limit
---@param events ScoreEvents Callback table
---@param timetype? string Time type
---@return nil
function score.list_query(map_name, player_id, key, limit, events, timetype) end

--- Query list item by list_id (server only)
---@param map_name? string Map name
---@param list_id integer List ID
---@param events ScoreEvents Callback table
---@param timetype? string Time type
---@return nil
function score.list_query_by_listid(map_name, list_id, events, timetype) end

--- Query items (server only)
---@param player_id integer Player ID
---@param events ScoreEvents Callback table
---@param key? string Item key filter
---@return nil
function score.query_item(player_id, events, key) end

--- Search by name (server only)
---@param map_name? string Map name
---@param key string Score key
---@param name_substr string Name substring to search
---@param events? ScoreEvents Callback table
---@return nil
function score.name_search(map_name, key, name_substr, events) end

--- Check if name exists (server only)
---@param map_name? string Map name
---@param key string Score key
---@param name string Name to check
---@param events? ScoreEvents Callback table
---@return nil
function score.name_exist(map_name, key, name, events) end

--- Get user status synchronously (server only)
---@param player_id integer Player ID
---@return any status
function score.get_user_status(player_id) end

--- Get user status asynchronously (server only)
---@param player_or_players integer|integer[] Player ID or array of IDs
---@param events ScoreEvents Callback table
---@return nil
function score.async_get_user_status(player_or_players, events) end

--- Set user status asynchronously (server only)
---@param player_id integer Player ID
---@param status any Status data
---@return nil
function score.async_set_user_status(player_id, status) end

--- Query world data (server only)
---@param map_name? string Map name
---@param world_id integer World ID
---@param player_id integer|nil Player ID
---@param events? ScoreEvents Callback table
---@param ... string Data keys to query
---@return nil
function score.world_data_init(map_name, world_id, player_id, events, ...) end

--- Query world list data (server only)
---@param map_name? string Map name
---@param world_id integer World ID
---@param player_id integer|nil Player ID
---@param key string List key
---@param limit? integer Number limit
---@param events ScoreEvents Callback table
---@param timetype? string Time type
---@return nil
function score.world_list_query(map_name, world_id, player_id, key, limit, events, timetype) end

--- Query world list item by list_id (server only)
---@param map_name? string Map name
---@param list_id integer List ID
---@param events ScoreEvents Callback table
---@param timetype? string Time type
---@return nil
function score.world_list_query_by_listid(map_name, list_id, events, timetype) end

--- Query score with limit (server only)
---@param map_name? string Map name
---@param player_id integer|nil Player ID
---@param key string Score key
---@param events ScoreEvents Callback table
---@return nil
function score.withlimit_query(map_name, player_id, key, events) end

--- Async Redis HSET operation (server only)
---@param key string Redis key
---@param field string Hash field
---@param value any Value
---@return nil
function score.async_hset(key, field, value) end

--- Async Redis HDEL operation (server only)
---@param key string Redis key
---@param field string Hash field
---@return nil
function score.async_hdel(key, field) end

--- Redis channel push (server only)
---@param channel string Channel name
---@param value any Value to push
---@return nil
function score.channel_push(channel, value) end

--- Upload statistics data (server only)
---@param player_id integer Player ID
---@param key string Stat key
---@param value any Stat value
---@param events? ScoreEvents Callback table
---@return nil
function score.stat_upload(player_id, key, value, events) end

--- Rollback score operation (server only)
---@param map_name string Map name
---@param player_id integer|nil Player ID
---@param req_id string Request ID to rollback
---@param events? ScoreEvents Callback table
---@return nil
function score.rollback_score(map_name, player_id, req_id, events) end

--- Check if player is an old player (server only)
---@param player_id integer Player ID
---@param events ScoreEvents Callback table
---@return nil
function score.is_old_player(player_id, events) end

--- Test cloud value serialization size (server only)
---@param value any Value to test
---@param events ScoreEvents Callback table
---@return nil
function score.test_cloud_value(value, events) end

return score
