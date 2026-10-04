-- Auto UI source-string dictionary. Meme names / story kept out.
local D = {
  zh_TW = {},
  en = {},
  ja = {},
  ko = {},
}

require("core.i18n.I18nDictPart1").fill(D)
require("core.i18n.I18nDictPart2").fill(D)
require("core.i18n.I18nDictPart3").fill(D)

return D
