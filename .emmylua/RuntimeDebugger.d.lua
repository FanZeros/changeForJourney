---@meta

--- Auto-generated from RuntimeDebugger/RuntimeDebugger

---@class RuntimeDebugger : Object
---@field visible boolean
---@field paused boolean
RuntimeDebugger = {}

---@return nil
function RuntimeDebugger:Show() end

---@return nil
function RuntimeDebugger:Hide() end

---@return nil
function RuntimeDebugger:Toggle() end

---@return boolean
function RuntimeDebugger:IsVisible() end

---@return nil
function RuntimeDebugger:Pause() end

---@return nil
function RuntimeDebugger:Resume() end

---@return nil
function RuntimeDebugger:TogglePause() end

---@return nil
function RuntimeDebugger:Step() end

---@return boolean
function RuntimeDebugger:IsPaused() end

---@return Node
function RuntimeDebugger:GetSelectedNode() end

---@return Component
function RuntimeDebugger:GetSelectedComponent() end

---@param node Node
---@return nil
function RuntimeDebugger:SetSelectedNode(node) end

---@param component Component
---@return nil
function RuntimeDebugger:SetSelectedComponent(component) end


-- Global functions
---@return RuntimeDebugger
function GetRuntimeDebugger() end

-- Global variables
---@type RuntimeDebugger
runtimeDebugger = nil
