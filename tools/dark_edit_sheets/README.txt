暗黑改造 · 待改原图拼板（1:1，可回拆）

目录: assets/image/dark_edit_sheets/
清单: manifest.json  （每张图的 src / x / y / w / h）

怎么改:
  1. 直接在对应分组 PNG 上改像素（保持画布尺寸、每块位置不变）
  2. 或按 manifest 把某一块抠出去单独改，再贴回同一 x,y
  3. 改完后运行:  python tools/dark_edit_sheets/split_edit_sheets.py
     会按坐标裁回 assets/image/<src>（覆盖原文件）

注意:
  - 原资源很多是 KTX（.png 扩展名），拼板已解码成真 PNG
  - 回拆写出的是 PNG；引擎可直接读 PNG，无需再压 KTX
  - 不要缩放整张拼板；缩放会导致回拆尺寸对不上

分组:
  dark_edit_sheets/P0_货币道具.png  851x1344  28张
  dark_edit_sheets/P0_小图标角标.png  442x660  24张
  dark_edit_sheets/P1_底栏导航.png  1222x1709  11张
  dark_edit_sheets/P1_进度条横.png  892x498  13张
  dark_edit_sheets/P1_进度条竖.png  114x604  2张
  dark_edit_sheets/P1_商店卡槽.png  692x1370  7张
  dark_edit_sheets/P1_按钮条.png  858x1189  14张
  dark_edit_sheets/P2_装备图标.png  1392x1920  33张
  dark_edit_sheets/P2_神器图标.png  848x1648  16张
  dark_edit_sheets/P2_职业大图标.png  1808x2088  42张
  dark_edit_sheets/P2_角色头像.png  1120x1376  20张
  dark_edit_sheets/P2_遗物.png  864x1888  10张
  dark_edit_sheets/P2_段位.png  1088x2128  8张
  dark_edit_sheets/P2_品质角标.png  155x276  4张
  dark_edit_sheets/P2_品质立绘框.png  650x771  3张
  dark_edit_sheets/P2_头像框.png  664x964  6张

合计 241 张