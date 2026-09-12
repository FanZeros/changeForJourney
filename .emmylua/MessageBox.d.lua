---@meta

--- Auto-generated from UI/MessageBox

---@class MessageBox : Object
---@overload fun(messageString?: string, titleString?: string, layoutFile?: XMLFile, styleFile?: XMLFile): MessageBox
---@overload fun(): MessageBox
---@field title string
---@field message string
---@field window UIElement
MessageBox = {}

---@overload fun(self: MessageBox, messageString?: string, titleString?: string, layoutFile?: XMLFile, styleFile?: XMLFile): MessageBox
---@overload fun(messageString?: string, titleString?: string, layoutFile?: XMLFile, styleFile?: XMLFile): MessageBox
---@return MessageBox
function MessageBox.new() end

---@param text string
---@return nil
function MessageBox:SetTitle(text) end

---@param text string
---@return nil
function MessageBox:SetMessage(text) end

---@return string
function MessageBox:GetTitle() end

---@return string
function MessageBox:GetMessage() end

---@return UIElement
function MessageBox:GetWindow() end

