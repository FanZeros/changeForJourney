-- 借面 / 剥面审核主体；基于 generate_advancement_trials 的 CPU 闭包绘图。
-- 不创建画布、不读旧图、不画底板、不写PNG；父生成器负责560母图与降采样。
-- 109复制护甲克制并借取短时增益；110死亡时向附近敌人传播护甲削弱。
-- 所有坐标为280设计空间，中心139.5；描边也必须留在半径112以内。
---@class AdvancementReviewMaskDraw
---@field polygon fun(points: number[][], top: number[], bottom?: number[], opacity?: number)
---@field line fun(x0: number, y0: number, x1: number, y1: number, width: number, color: number[], opacity?: number)
---@field stroke fun(points: number[][], width: number, color: number[], closed?: boolean, opacity?: number)
---@field ellipse fun(cx: number, cy: number, rx: number, ry: number, top: number[], bottom?: number[])
---@field curve fun(points: number[][], c1x: number, c1y: number, c2x: number, c2y: number, endx: number, endy: number)
---@field emblem fun(points: number[][], top?: number[], bottom?: number[])
---@field DARK number[]
---@field GOLD number[]
---@field BONE number[]
---@field SHADE number[]

---@param d AdvancementReviewMaskDraw
---@param branchId integer
return function(d, branchId)
    assert(branchId == 109 or branchId == 110, "ReviewMask只绘制109/110审核主体")
    local polygon, line, stroke = d.polygon, d.line, d.stroke
    local ellipse, curve, emblem = d.ellipse, d.curve, d.emblem
    local DARK, GOLD, BONE, SHADE = d.DARK, d.GOLD, d.BONE, d.SHADE

    if branchId == 109 then
        -- 借面：右上旧铜影面与左下骨白主面错开，不靠单面左右换色。
        -- 影面的双眼位于前景额线以上；主面遮挡左下部分，仍能辨出第二张脸。
        local borrowed = { { 171, 54 }, { 197, 65 }, { 217, 84 }, { 222, 113 },
            { 213, 149 }, { 195, 174 }, { 175, 187 }, { 154, 171 },
            { 138, 144 }, { 130, 111 }, { 134, 82 }, { 149, 64 } }
        emblem(borrowed, GOLD, SHADE)
        polygon({ { 171, 61 }, { 172, 126 }, { 176, 179 }, { 155, 164 },
            { 143, 141 }, { 136, 110 }, { 140, 83 }, { 153, 69 } }, GOLD, SHADE)
        polygon({ { 179, 64 }, { 195, 72 }, { 209, 88 }, { 214, 112 },
            { 205, 138 }, { 192, 151 }, { 190, 112 } }, GOLD, DARK, 0.58)
        stroke({ { 150, 71 }, { 171, 61 }, { 194, 72 }, { 210, 90 } }, 3.3, BONE, false, 0.78)
        stroke({ { 218, 114 }, { 210, 147 }, { 193, 170 }, { 176, 181 } }, 2.5, SHADE, false)
        -- 两个宽眼孔用实体暗色负空间，不使用透明虚影或细密面纹。
        polygon({ { 144, 100 }, { 168, 106 }, { 167, 118 }, { 150, 112 } }, DARK)
        polygon({ { 177, 107 }, { 206, 98 }, { 202, 112 }, { 179, 119 } }, DARK)
        line(145, 97, 166, 103, 3, BONE, 0.85)
        line(180, 103, 206, 94, 3, BONE, 0.85)
        polygon({ { 174, 116 }, { 167, 141 }, { 182, 143 } }, SHADE, DARK)
        line(173, 120, 170, 137, 2.2, GOLD)
        stroke({ { 166, 157 }, { 176, 161 }, { 189, 154 } }, 4.4, DARK, false)
        line(185, 153, 193, 146, 2.3, GOLD)

        -- 借取轨迹从铜面侧缘朝骨白主面单向回卷，末端进入主面的颊侧。
        -- 最大控制点(229,181)也在安全圆内；轨迹在前景面具之前绘制。
        local transfer = { { 218, 156 } }
        curve(transfer, 229, 181, 215, 208, 188, 216)
        curve(transfer, 174, 221, 159, 212, 150, 199)
        stroke(transfer, 9, DARK, false)
        stroke(transfer, 3.8, GOLD, false)
        stroke({ { 204, 204 }, { 188, 214 }, { 174, 215 } }, 2, BONE, false)

        local face = { { 109, 102 }, { 137, 110 }, { 156, 129 }, { 161, 157 },
            { 151, 184 }, { 133, 212 }, { 112, 227 }, { 91, 212 },
            { 73, 184 }, { 61, 154 }, { 65, 128 }, { 83, 111 } }
        emblem(face, BONE, GOLD)
        -- 中央保留一大块骨白面，右侧一片铜色斜面承担体积而非铺满杂纹。
        polygon({ { 116, 109 }, { 136, 117 }, { 149, 133 }, { 154, 156 },
            { 144, 182 }, { 127, 208 }, { 114, 218 }, { 119, 166 } }, GOLD, SHADE)
        polygon({ { 77, 130 }, { 92, 117 }, { 105, 113 }, { 101, 145 },
            { 88, 154 }, { 75, 151 } }, BONE, GOLD)
        stroke({ { 83, 117 }, { 109, 109 }, { 131, 117 } }, 3.5, BONE, false)
        stroke({ { 66, 151 }, { 77, 181 }, { 94, 208 }, { 110, 219 } }, 2.8, BONE, false, 0.8)
        stroke({ { 154, 159 }, { 144, 185 }, { 130, 206 } }, 3.1, SHADE, false)
        polygon({ { 78, 142 }, { 104, 150 }, { 101, 163 }, { 82, 155 } }, DARK)
        polygon({ { 117, 150 }, { 146, 138 }, { 143, 153 }, { 120, 162 } }, DARK)
        line(80, 138, 102, 146, 3.4, BONE)
        line(120, 145, 145, 135, 3.4, BONE)
        polygon({ { 111, 156 }, { 104, 179 }, { 116, 182 } }, SHADE, DARK)
        line(109, 160, 106, 174, 2.3, BONE)
        stroke({ { 96, 194 }, { 110, 199 }, { 125, 192 } }, 5, DARK, false)
        line(98, 190, 108, 193, 2.2, GOLD)
        -- 颊侧落点在主体之后补出：不画吸血滴、速度翅或治疗十字以免抢脸。
        emblem({ { 144, 192 }, { 158, 199 }, { 156, 210 } }, BONE, GOLD)
        line(165, 211, 156, 206, 3.8, GOLD)
        return
    end

    -- 剥面：一张铁面甲失去右半骨白外壳；撕口与右侧剥开的甲片间留实空隙。
    -- 下部大碎甲与两块小碎片散开，结构不是借面的第二张完整脸。
    local inner = { { 128, 66 }, { 151, 78 }, { 173, 101 }, { 180, 132 },
        { 172, 166 }, { 155, 197 }, { 127, 221 }, { 103, 206 },
        { 83, 179 }, { 73, 149 }, { 76, 116 }, { 93, 88 } }
    emblem(inner, SHADE, DARK)
    polygon({ { 139, 85 }, { 161, 104 }, { 168, 132 }, { 160, 163 },
        { 147, 186 }, { 131, 205 }, { 134, 175 }, { 143, 151 } }, SHADE, DARK)
    -- 暴露的暗铁眼槽低亮度；未剥下的左眼孔留在下方骨白甲壳中。
    polygon({ { 143, 126 }, { 168, 119 }, { 164, 138 }, { 144, 143 } }, DARK)
    line(145, 121, 164, 115, 2.6, GOLD)
    stroke({ { 171, 143 }, { 163, 168 }, { 148, 190 } }, 3, GOLD, false, 0.6)

    local remaining = { { 126, 69 }, { 139, 82 }, { 135, 102 }, { 145, 120 },
        { 132, 140 }, { 140, 155 }, { 127, 174 }, { 135, 192 }, { 124, 219 },
        { 103, 203 }, { 86, 177 }, { 76, 148 }, { 80, 118 }, { 96, 91 } }
    emblem(remaining, BONE, GOLD)
    polygon({ { 87, 118 }, { 100, 96 }, { 120, 82 }, { 122, 113 },
        { 107, 129 }, { 91, 142 } }, BONE, GOLD)
    polygon({ { 89, 158 }, { 106, 167 }, { 121, 174 }, { 126, 193 },
        { 119, 208 }, { 104, 198 } }, GOLD, SHADE)
    stroke({ { 98, 96 }, { 125, 77 }, { 133, 85 } }, 3.4, BONE, false)
    stroke({ { 81, 149 }, { 90, 175 }, { 105, 200 }, { 119, 210 } }, 2.9, BONE, false)
    polygon({ { 87, 127 }, { 118, 139 }, { 115, 153 }, { 92, 144 } }, DARK)
    line(88, 123, 116, 134, 3.5, BONE)
    polygon({ { 127, 147 }, { 116, 167 }, { 126, 172 }, { 131, 158 } }, SHADE, DARK)
    stroke({ { 103, 184 }, { 116, 188 }, { 128, 182 } }, 4.7, DARK, false)
    -- 断口倒角由粗暗线与贴边骨白线形成，锯齿宽度足以在小图留下轮廓。
    local torn = { { 138, 83 }, { 134, 102 }, { 144, 120 }, { 131, 140 },
        { 139, 155 }, { 126, 174 }, { 134, 192 }, { 123, 216 } }
    stroke(torn, 5.5, DARK, false)
    stroke(torn, 2.5, BONE, false)

    -- 右半甲片向右扭开：仅一眼、内侧锯齿及厚卷边，不重复完整主面。
    local peeled = { { 173, 84 }, { 193, 95 }, { 215, 118 }, { 221, 147 },
        { 210, 177 }, { 185, 199 }, { 171, 189 }, { 179, 162 },
        { 173, 146 }, { 180, 126 }, { 167, 109 } }
    emblem(peeled, BONE, GOLD)
    polygon({ { 198, 109 }, { 210, 124 }, { 214, 146 }, { 204, 173 },
        { 188, 187 }, { 190, 163 }, { 200, 139 } }, GOLD, SHADE)
    polygon({ { 173, 89 }, { 176, 107 }, { 187, 125 }, { 180, 146 },
        { 185, 163 }, { 177, 188 }, { 171, 189 }, { 179, 162 },
        { 173, 146 }, { 180, 126 }, { 167, 109 } }, GOLD, SHADE)
    stroke({ { 176, 90 }, { 191, 99 }, { 210, 119 } }, 3.5, BONE, false)
    polygon({ { 183, 124 }, { 208, 129 }, { 202, 143 }, { 181, 138 } }, DARK)
    line(186, 120, 207, 124, 3, BONE)
    stroke({ { 215, 150 }, { 205, 175 }, { 187, 191 } }, 2.5, SHADE, false)
    line(190, 160, 198, 156, 3.5, DARK)
    line(188, 165, 196, 161, 2.3, GOLD)

    -- 大碎甲有平直甲带与铆钉，避免画成水晶；两小块只强调壳片崩落。
    emblem({ { 155, 207 }, { 173, 208 }, { 184, 219 }, { 177, 230 },
        { 157, 231 }, { 146, 223 }, { 150, 215 } }, GOLD, SHADE)
    line(154, 212, 172, 213, 2.8, BONE)
    line(153, 222, 176, 224, 3.4, DARK)
    ellipse(165, 216, 3.7, 3.7, DARK)
    ellipse(164.5, 215.5, 2.1, 2.1, BONE, GOLD)
    emblem({ { 211, 183 }, { 224, 193 }, { 213, 206 }, { 204, 196 } }, GOLD, SHADE)
    line(211, 188, 218, 193, 2.5, BONE)
    emblem({ { 210, 67 }, { 219, 77 }, { 210, 90 }, { 202, 78 } }, BONE, GOLD)
    line(206, 77, 213, 73, 2.2, BONE)
end
