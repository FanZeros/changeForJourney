---@meta

--- Auto-generated from Input/Controls

---@class Controls
---@overload fun(): Controls
---@field buttons integer
---@field yaw number
---@field pitch number
---@field extraData VariantMap
Controls = {}

---@return Controls
function Controls.new() end

---@return nil
function Controls:Reset() end

---@param buttons integer
---@param down? boolean
---@return nil
function Controls:Set(buttons, down) end

---@param button integer
---@return boolean
function Controls:IsDown(button) end

---@param button integer
---@param previousControls Controls
---@return boolean
function Controls:IsPressed(button, previousControls) end

