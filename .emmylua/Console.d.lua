---@meta

--- Auto-generated from Engine/Console

---@class Console : Object
---@field defaultStyle XMLFile
---@field background BorderImage
---@field lineEdit LineEdit
---@field closeButton Button
---@field visible boolean
---@field autoVisibleOnError boolean
---@field commandInterpreter string
---@field numBufferedRows integer
---@field numRows integer
---@field numHistoryRows integer
---@field historyPosition integer
---@field focusOnShow boolean
Console = {}

---@param style XMLFile
---@return nil
function Console:SetDefaultStyle(style) end

---@param enable boolean
---@return nil
function Console:SetVisible(enable) end

---@return nil
function Console:Toggle() end

---@param enable boolean
---@return nil
function Console:SetAutoVisibleOnError(enable) end

---@param interpreter string
---@return nil
function Console:SetCommandInterpreter(interpreter) end

---@param rows integer
---@return nil
function Console:SetNumBufferedRows(rows) end

---@param rows integer
---@return nil
function Console:SetNumRows(rows) end

---@param rows integer
---@return nil
function Console:SetNumHistoryRows(rows) end

---@param enable boolean
---@return nil
function Console:SetFocusOnShow(enable) end

---@param option string
---@return nil
function Console:AddAutoComplete(option) end

---@param option string
---@return nil
function Console:RemoveAutoComplete(option) end

---@return nil
function Console:UpdateElements() end

---@return XMLFile
function Console:GetDefaultStyle() end

---@return BorderImage
function Console:GetBackground() end

---@return LineEdit
function Console:GetLineEdit() end

---@return Button
function Console:GetCloseButton() end

---@return boolean
function Console:IsVisible() end

---@return boolean
function Console:IsAutoVisibleOnError() end

---@return string
function Console:GetCommandInterpreter() end

---@return integer
function Console:GetNumBufferedRows() end

---@return integer
function Console:GetNumRows() end

---@return nil
function Console:CopySelectedRows() end

---@return integer
function Console:GetNumHistoryRows() end

---@return integer
function Console:GetHistoryPosition() end

---@param index integer
---@return string
function Console:GetHistoryRow(index) end

---@return boolean
function Console:GetFocusOnShow() end


-- Global functions
---@return Console
function GetConsole() end

-- Global variables
---@type Console
console = nil
