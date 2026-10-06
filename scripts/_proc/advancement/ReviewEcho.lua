-- 残响107 / 叠声108审核主体。复用主生成器CPU闭包，不创建画布或读写资源。
-- 机制对照AdvancementConfig：107缩短回响延迟并允许概率暴击；108同目标最多两层。
-- 底板、560母图、预乘降采样及PNG输出均由调用方负责；本模块没有安装入口。
-- 中心139.5；弓、箭及暗描边按半径112内设计，不用声量波/十字/皇冠。

---@class AdvancementReviewEchoDraw
---@field polygon fun(points: number[][], top: number[], bottom?: number[], opacity?: number)
---@field line fun(x0: number, y0: number, x1: number, y1: number, width: number, color: number[], opacity?: number)
---@field stroke fun(points: number[][], width: number, color: number[], closed?: boolean, opacity?: number)
---@field curve fun(points: number[][], c1x: number, c1y: number, c2x: number, c2y: number, endx: number, endy: number)
---@field emblem fun(points: number[][], top?: number[], bottom?: number[])
---@field DARK number[]
---@field GOLD number[]
---@field BONE number[]
---@field SHADE number[]

---@param d AdvancementReviewEchoDraw
---@param branchId number
return function(d, branchId)
    assert(branchId == 107 or branchId == 108, "ReviewEcho仅绘制107/108审核主体")
    local polygon, line, stroke = d.polygon, d.line, d.stroke
    local curve, emblem = d.curve, d.emblem
    local DARK, GOLD, BONE, SHADE = d.DARK, d.GOLD, d.BONE, d.SHADE

    -- 同向实体箭：轴向坐标只改变主体几何，不改变调用方画布/底板。
    -- 箭杆宽度8px，加7px暗轮廓；宽箭头与双羽尾保证缩小时仍像箭。
    ---@param sx number
    ---@param sy number
    ---@param tx number
    ---@param ty number
    ---@param top number[]
    ---@param bottom number[]
    local function arrow(sx, sy, tx, ty, top, bottom)
        local dx, dy = tx - sx, ty - sy
        local length = math.sqrt(dx * dx + dy * dy)
        local ux, uy = dx / length, dy / length
        ---@param along number
        ---@param across number
        ---@return number[]
        local function p(along, across)
            return { sx + ux * along - uy * across, sy + uy * along + ux * across }
        end
        -- 连贯箭杆先铺暗边；细的单侧高光不承担主体识别。
        emblem({ p(-10, -4), p(length - 24, -4),
            p(length - 24, 4), p(-10, 4) }, top, bottom)
        local bevelStart, bevelEnd = p(8, -2), p(length - 29, -2)
        line(bevelStart[1], bevelStart[2], bevelEnd[1], bevelEnd[2], 2, BONE)

        -- 两片旧铜羽尾，中间箭杆保持清晰，非三叉箭或职业徽记。
        emblem({ p(-18, -15), p(5, -15), p(19, -3), p(-5, -3) }, top, GOLD)
        emblem({ p(-5, 3), p(19, 3), p(5, 15), p(-18, 15) }, GOLD, bottom)
        local tailA, tailB = p(-13, -11), p(3, -11)
        line(tailA[1], tailA[2], tailB[1], tailB[2], 2, BONE)
        local lowerA, lowerB = p(-12, 10), p(4, 10)
        line(lowerA[1], lowerA[2], lowerB[1], lowerB[2], 2.5, SHADE)

        -- 骨白三角刃和大块铜暗面，不使用星芒来代替暴击/伤害语义。
        local tip, shoulderA, shoulderB = p(length, 0), p(length - 37, -17), p(length - 37, 17)
        emblem({ tip, shoulderA, p(length - 29, 0), shoulderB }, top, GOLD)
        polygon({ tip, p(length - 29, 0), shoulderB }, GOLD, bottom)
        local ridge = p(length - 28, -1)
        line(tip[1] - ux * 5, tip[2] - uy * 5, ridge[1], ridge[2], 2.4, BONE)
    end

    -- 共用短反曲弓：大块骨白铜面与开放弓腹，先于箭绘制。
    -- 弓腹厚度约20px，右側弓弦与弓身间保留负空间。
    local bow = { { 132, 59 } }
    curve(bow, 122, 66, 126, 78, 118, 89)
    curve(bow, 108, 104, 72, 103, 64, 130)
    curve(bow, 55, 155, 91, 183, 116, 196)
    curve(bow, 127, 203, 124, 215, 132, 221)
    curve(bow, 143, 218, 141, 210, 135, 202)
    curve(bow, 132, 191, 133, 184, 118, 174)
    curve(bow, 102, 163, 88, 155, 86, 139)
    curve(bow, 83, 120, 113, 116, 129, 99)
    curve(bow, 141, 85, 144, 68, 132, 59)
    emblem(bow, BONE, GOLD)

    -- 外曲面旧铜暗面，内曲面少量骨白倒角，拒绝密集纹理和光晕。
    local outerShade = { { 72, 134 } }
    curve(outerShade, 65, 155, 102, 179, 122, 190)
    curve(outerShade, 120, 179, 102, 170, 93, 157)
    curve(outerShade, 84, 146, 89, 139, 87, 128)
    curve(outerShade, 82, 130, 76, 131, 72, 134)
    polygon(outerShade, GOLD, SHADE)
    local upperEdge = { { 128, 66 } }
    curve(upperEdge, 125, 91, 103, 103, 84, 113)
    curve(upperEdge, 76, 118, 69, 125, 68, 135)
    stroke(upperEdge, 3.4, BONE, false)
    local lowerEdge = { { 91, 166 } }
    curve(lowerEdge, 100, 178, 127, 194, 131, 210)
    stroke(lowerEdge, 3, SHADE, false)

    -- 弓弦是细而不透明的结构线，不当成残影声波。
    local string = { { 133, 66 }, { 123, 140 }, { 134, 214 } }
    stroke(string, 7, DARK, false)
    stroke(string, 2.8, BONE, false)
    emblem({ { 68, 129 }, { 82, 128 }, { 87, 151 }, { 76, 158 }, { 65, 146 } }, GOLD, SHADE)
    line(69, 134, 82, 132, 3, DARK)
    line(70, 143, 84, 141, 3, DARK)
    line(75, 151, 85, 148, 3, DARK)
    line(69, 132, 80, 130, 2, BONE)
    -- 弦扣仅为弓身结构；外缘不再增添装饰性圆环/金属底盘。
    emblem({ { 127, 59 }, { 136, 59 }, { 139, 68 }, { 131, 74 }, { 126, 69 } }, GOLD, SHADE)
    emblem({ { 126, 211 }, { 136, 208 }, { 140, 217 }, { 132, 224 }, { 126, 219 } }, GOLD, SHADE)

    if branchId == 107 then
        -- 残响：仅一支完整大箭。上方短截残影不足半箭，避免读成双层叠声。
        -- 短促尾迹指向同一方向；锐利骨白主刃表达更快、可暴击的回响。
        local remnant = { { 101, 118 }, { 128, 91 } }
        stroke(remnant, 11, DARK, false)
        stroke(remnant, 5, GOLD, false)
        emblem({ { 144, 75 }, { 122, 82 }, { 130, 89 }, { 137, 97 } }, GOLD, SHADE)
        polygon({ { 144, 75 }, { 127, 83 }, { 132, 88 } }, BONE, GOLD)
        line(89, 99, 103, 85, 7, DARK)
        line(89, 99, 103, 85, 3.4, GOLD)
        arrow(100, 190, 225, 80, BONE, SHADE)
    else
        -- 叠声：两支完整同向箭，轴线平行且等长，横向层距约35px。
        -- 后层旧铜、前层骨白，区分来自几何而非只换颜色；不画第三层。
        arrow(94, 173, 207, 65, GOLD, SHADE)
        arrow(119, 198, 232, 90, BONE, GOLD)
    end
end
