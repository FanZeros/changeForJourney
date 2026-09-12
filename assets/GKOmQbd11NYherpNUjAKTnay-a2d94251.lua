-- ============================================================================
-- ChallengerConsts - 挑战者区服常量（双端共享）
-- ============================================================================

local C = {}

C.SERVER_KIND_CHALLENGER = "challenger"
C.SERVER_KIND_PERMANENT  = "permanent"

C.ACTIVITY_ID = "challenger_202607"
C.REWARD_CLAIM_SOURCE = C.ACTIVITY_ID .. "_settle"

C.CLAIM_SCOPE_PER_NON_CHALLENGER_SERVER = "perNonChallengerServer"

-- 同一区服待投递档位数达到此值时，合并为一封邮件
C.MERGE_MAIL_THRESHOLD = 8

C.STATUS_NOT_OPEN = "not_open"
C.STATUS_OPEN     = "open"
C.STATUS_CLOSED   = "closed"

return C
