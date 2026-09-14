暗黑改造 · 拼板 / 回拆

目录: tools/dark_edit_sheets/
清单: manifest.json（每张图的 src / x / y / w / h）

拼板（从 assets/image 原图生成 1:1 分组 PNG）:
  python tools/dark_edit_sheets/compose_edit_sheets.py
  输出到 assets/image/dark_edit_sheets/<分组>.png

回拆（按坐标裁回 assets/image/<原路径>，覆盖原文件）:
  python tools/dark_edit_sheets/split_edit_sheets.py

注意:
  - 改拼板时不要缩放整张图，否则回拆尺寸对不上
  - 回拆写出的是 PNG；引擎可直接读
  - compose 依赖 pillow + texture2ddecoder（KTX 解码）
  - 拼板 PNG 本身不入库，只提交脚本和 manifest
