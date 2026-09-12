---@meta

--- Auto-generated from UI/FileSelector

---@class FileSelectorEntry
---@field name string
---@field directory boolean
FileSelectorEntry = {}


---@class FileSelector : Object
---@overload fun(): FileSelector
---@field defaultStyle XMLFile
---@field window Window
---@field titleText Text
---@field fileList ListView
---@field pathEdit LineEdit
---@field fileNameEdit LineEdit
---@field filterList DropDownList
---@field okButton Button
---@field cancelButton Button
---@field closeButton Button
---@field title string
---@field path string
---@field fileName string
---@field filter string
---@field filterIndex integer
---@field directoryMode boolean
FileSelector = {}

---@return FileSelector
function FileSelector.new() end

---@param style XMLFile
---@return nil
function FileSelector:SetDefaultStyle(style) end

---@param text string
---@return nil
function FileSelector:SetTitle(text) end

---@param okText string
---@param cancelText string
---@return nil
function FileSelector:SetButtonTexts(okText, cancelText) end

---@param path string
---@return nil
function FileSelector:SetPath(path) end

---@param fileName string
---@return nil
function FileSelector:SetFileName(fileName) end

---@param filters string[]
---@param defaultIndex integer
---@return nil
function FileSelector:SetFilters(filters, defaultIndex) end

---@param enable boolean
---@return nil
function FileSelector:SetDirectoryMode(enable) end

---@return nil
function FileSelector:UpdateElements() end

---@return XMLFile
function FileSelector:GetDefaultStyle() end

---@return Window
function FileSelector:GetWindow() end

---@return Text
function FileSelector:GetTitleText() end

---@return ListView
function FileSelector:GetFileList() end

---@return LineEdit
function FileSelector:GetPathEdit() end

---@return LineEdit
function FileSelector:GetFileNameEdit() end

---@return DropDownList
function FileSelector:GetFilterList() end

---@return Button
function FileSelector:GetOKButton() end

---@return Button
function FileSelector:GetCancelButton() end

---@return Button
function FileSelector:GetCloseButton() end

---@return string
function FileSelector:GetTitle() end

---@return string
function FileSelector:GetPath() end

---@return string
function FileSelector:GetFileName() end

---@return string
function FileSelector:GetFilter() end

---@return integer
function FileSelector:GetFilterIndex() end

---@return boolean
function FileSelector:GetDirectoryMode() end

