// 把自定义图标与版本信息写入 Windows 可执行文件。
//
// 为什么需要这一步：electron-builder 写入 exe 图标/版本信息靠 rcedit，而 rcedit 是
// Windows PE，在 Linux 上必须借助 wine。本项目在无 wine 环境打包，package.json 里
// 用 build.win.signAndEditExecutable:false 跳过该步骤，代价是 exe 一直保留 Electron
// 默认图标与 "Electron" 版本信息。这里用纯 JS 的 resedit 直接改 PE 资源，不依赖 wine，
// 跨平台行为一致。
//
// 用法：
//   node patch_win_icon.mjs --exe <path> --icon <icon.ico> --version <1.2.3>
//                           [--product-name NAME] [--description TEXT]
//
// 幂等：重复执行结果一致（图标组与版本字符串都是替换而非追加）。

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const require_ = createRequire(path.join(HERE, 'package.json'));

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    out[key] = argv[i + 1];
    i += 1;
  }
  return out;
}

function loadResedit() {
  try {
    return require_('resedit');
  } catch (err) {
    console.error('[patch_win_icon] 找不到 resedit，请先在 electron-shell/ 执行 npm install');
    throw err;
  }
}

/** 从 "1.2.3" / "1.2.3.4" 解析出 PE 固定版本号的四段数字。 */
function parseVersion(text) {
  const parts = String(text).split('.').map((piece) => Number.parseInt(piece, 10));
  if (parts.some((n) => !Number.isFinite(n) || n < 0)) return null;
  while (parts.length < 4) parts.push(0);
  return parts.slice(0, 4);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const exePath = args.exe;
  const iconPath = args.icon;
  if (!exePath || !iconPath) {
    console.error('[patch_win_icon] 缺少 --exe 或 --icon');
    process.exit(2);
  }
  if (!fs.existsSync(exePath)) {
    console.error('[patch_win_icon] 可执行文件不存在：' + exePath);
    process.exit(1);
  }
  if (!fs.existsSync(iconPath)) {
    console.error('[patch_win_icon] 图标不存在：' + iconPath);
    process.exit(1);
  }

  const R = loadResedit();
  const nt = R.NtExecutable.from(fs.readFileSync(exePath), { ignoreCert: true });
  const res = R.NtExecutableResource.from(nt);

  // ---- 图标：替换已有图标组的全部子图 ----
  const ico = R.Data.IconFile.from(fs.readFileSync(iconPath));
  const groups = R.Resource.IconGroupEntry.fromEntries(res.entries);
  const groupId = groups.length > 0 ? groups[0].id : 1;
  const groupLang = groups.length > 0 ? groups[0].lang : 1033;
  R.Resource.IconGroupEntry.replaceIconsForResource(
    res.entries, groupId, groupLang, ico.icons.map((icon) => icon.data));
  const iconSizes = ico.icons.map((icon) => {
    const w = icon.width === 0 ? 256 : icon.width;
    const h = icon.height === 0 ? 256 : icon.height;
    return w + 'x' + h;
  });

  // ---- 版本信息：字符串表 + 固定版本号 ----
  const versionInfos = R.Resource.VersionInfo.fromEntries(res.entries);
  if (versionInfos.length === 0) {
    console.error('[patch_win_icon] 未找到版本信息资源，无法写入版本信息');
    process.exit(1);
  }
  const vi = versionInfos[0];
  // getDefaultVersionLang() 只返回语言号；字符串表按 (lang, codepage) 匹配，
  // 必须用完整语言对象，否则 setStringValues 会新建一张空表、原值原样保留。
  const lang = vi.getAllLanguagesForStringValues()[0]
    ?? vi.getAvailableLanguages()[0]
    ?? { lang: 1033, codepage: 1200 };
  const version = String(args.version || '').trim();
  const productName = args.productName || 'ZhongYanZhiMen';
  const description = args.description || productName;

  const strings = {
    ProductName: productName,
    FileDescription: description,
    OriginalFilename: path.basename(exePath),
    InternalName: productName.replace(/\.exe$/i, ''),
  };
  if (version) {
    strings.FileVersion = version;
    strings.ProductVersion = version;
  }
  vi.setStringValues(lang, strings);

  const numeric = version ? parseVersion(version) : null;
  if (numeric) {
    // setFileVersion 接受 "1.2.3.4" 字符串 + 语言号；传数组会被当作 NaN 处理。
    vi.setFileVersion(numeric.join('.'), lang.lang);
    vi.setProductVersion(numeric.join('.'), lang.lang);
  }
  vi.outputToResourceEntries(res.entries);

  res.outputResource(nt);
  fs.writeFileSync(exePath, Buffer.from(nt.generate()));

  console.log('[patch_win_icon] 已写入图标 ' + iconSizes.join(', '));
  console.log('[patch_win_icon] 已写入版本信息 ' +
    (version ? 'v' + version : '(未指定版本)') + ' / ' + productName);
}

main();
