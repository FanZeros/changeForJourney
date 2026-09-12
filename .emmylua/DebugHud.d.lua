---@meta

--- Auto-generated from Engine/DebugHud

---@class DebugHud : Object
---@field defaultStyle XMLFile
---@field statsText Text
---@field modeText Text
---@field profilerText Text
---@field mode integer
---@field profilerMaxDepth integer
---@field profilerInterval number
---@field useRendererStats boolean
DebugHud = {}

---@return nil
function DebugHud:Update() end

---@param style XMLFile
---@return nil
function DebugHud:SetDefaultStyle(style) end

---@param mode integer
---@return nil
function DebugHud:SetMode(mode) end

---@param depth integer
---@return nil
function DebugHud:SetProfilerMaxDepth(depth) end

---@param interval number
---@return nil
function DebugHud:SetProfilerInterval(interval) end

---@param enable boolean
---@return nil
function DebugHud:SetUseRendererStats(enable) end

---@param mode integer
---@return nil
function DebugHud:Toggle(mode) end

---@return nil
function DebugHud:ToggleAll() end

---@return XMLFile
function DebugHud:GetDefaultStyle() end

---@return Text
function DebugHud:GetStatsText() end

---@return Text
function DebugHud:GetModeText() end

---@return Text
function DebugHud:GetProfilerText() end

---@return integer
function DebugHud:GetMode() end

---@return integer
function DebugHud:GetProfilerMaxDepth() end

---@return number
function DebugHud:GetProfilerInterval() end

---@return boolean
function DebugHud:GetUseRendererStats() end

---@param label string
---@param stats Variant
---@return nil
function DebugHud:SetAppStats(label, stats) end

---@param label string
---@param stats string
---@return nil
function DebugHud:SetAppStats(label, stats) end

---@param label string
---@return boolean
function DebugHud:ResetAppStats(label) end

---@return nil
function DebugHud:ClearAppStats() end


-- Global functions
---@return DebugHud
function GetDebugHud() end

-- Global variables
---@type integer
DEBUGHUD_SHOW_NONE = nil
---@type integer
DEBUGHUD_SHOW_STATS = nil
---@type integer
DEBUGHUD_SHOW_MODE = nil
---@type integer
DEBUGHUD_SHOW_PROFILER = nil
---@type integer
DEBUGHUD_SHOW_MEMORY = nil
---@type integer
DEBUGHUD_SHOW_EVENTPROFILER = nil
---@type integer
DEBUGHUD_SHOW_ALL = nil
---@type DebugHud
debugHud = nil
