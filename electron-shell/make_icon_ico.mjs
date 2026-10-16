// 由 icon.png 生成多尺寸 icon.ico。
//
// Windows 会按场景取用不同尺寸：任务栏/标题栏用 16/32，资源管理器用 48/128/256。
// 只提供单一尺寸会被系统放大，边缘发虚，因此这里一次性写入常用尺寸。
//
// 用法：
//   node make_icon_ico.mjs [--source icon.png] [--out icon.ico]
//
// 依赖：pngjs（纯 JS PNG 解码，跨平台无需 ImageMagick）。

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const require_ = createRequire(path.join(HERE, 'package.json'));

const SIZES = [16, 24, 32, 48, 64, 128, 256];

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

function loadPng() {
  try {
    // pngjs 以 { PNG } 形式导出
    return require_('pngjs').PNG;
  } catch (err) {
    console.error('[make_icon_ico] 找不到 pngjs，请先在 electron-shell/ 执行 npm install');
    throw err;
  }
}

/** 最近邻缩放（图标为线性几何图形，缩放后仍锐利；不引入额外依赖）。 */
function resizeNearest(src, srcW, srcH, dstW, dstH) {
  const dst = Buffer.alloc(dstW * dstH * 4);
  for (let y = 0; y < dstH; y += 1) {
    const sy = Math.min(srcH - 1, Math.floor((y * srcH) / dstH));
    for (let x = 0; x < dstW; x += 1) {
      const sx = Math.min(srcW - 1, Math.floor((x * srcW) / dstW));
      const si = (sy * srcW + sx) * 4;
      const di = (y * dstW + x) * 4;
      dst[di] = src[si];
      dst[di + 1] = src[si + 1];
      dst[di + 2] = src[si + 2];
      dst[di + 3] = src[si + 3];
    }
  }
  return dst;
}

/** 把 RGBA 像素编码成 PNG。 */
function encodePng(PNG, rgba, width, height) {
  const png = new PNG({ width, height });
  rgba.copy(png.data);
  return PNG.sync.write(png);
}

function buildIco(images) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0);              // reserved
  header.writeUInt16LE(1, 2);              // type: icon
  header.writeUInt16LE(images.length, 4);  // count

  const dir = Buffer.alloc(16 * images.length);
  let offset = 6 + dir.length;
  images.forEach((img, i) => {
    const base = i * 16;
    const dim = img.size >= 256 ? 0 : img.size; // 256 在目录里记 0
    dir.writeUInt8(dim, base + 0);             // width
    dir.writeUInt8(dim, base + 1);             // height
    dir.writeUInt8(0, base + 2);               // palette count
    dir.writeUInt8(0, base + 3);               // reserved
    dir.writeUInt16LE(1, base + 4);            // color planes
    dir.writeUInt16LE(32, base + 6);           // bits per pixel
    dir.writeUInt32LE(img.data.length, base + 8);
    dir.writeUInt32LE(offset, base + 12);
    offset += img.data.length;
  });

  return Buffer.concat([header, dir, ...images.map((img) => img.data)]);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const source = path.resolve(HERE, args.source || 'icon.png');
  const out = path.resolve(HERE, args.out || 'icon.ico');
  if (!fs.existsSync(source)) {
    console.error('[make_icon_ico] 找不到源图：' + source);
    process.exit(1);
  }

  const PNG = loadPng();
  const src = PNG.sync.read(fs.readFileSync(source));
  const images = SIZES.map((size) => {
    const rgba = resizeNearest(src.data, src.width, src.height, size, size);
    return { size, data: encodePng(PNG, rgba, size, size) };
  });

  fs.writeFileSync(out, buildIco(images));
  console.log('[make_icon_ico] 已生成 ' + path.basename(out) +
    ' (' + SIZES.join(', ') + ') 源自 ' + path.basename(source) +
    ' ' + src.width + 'x' + src.height);
}

main();
