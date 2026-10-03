-- 第三版套装徽记结构细节；只在离线生成时调用，不参与游戏帧绘制。
local M = {}

function M.draw(id, d)
    local poly, circle, line, stroke = d.poly, d.circle, d.line, d.stroke
    local arc, bezier, glyph, mix = d.arc, d.bezier, d.glyph, d.mix
    local base, light, shade, dark, edge = d.base, d.light, d.shade, d.dark, d.edge
    local cold = mix(base, { 122, 127, 136 }, 0.52)
    local shadow = mix(shade, dark, 0.5)
    local function rivet(x, y, radius)
        circle(x, y + 1, radius + 1, dark)
        circle(x, y, radius, edge, shade)
        line(x - radius * 0.45, y, x + radius * 0.45, y, 1, shadow)
    end
    local function gem(x, y, r)
        glyph({ { x, y - r }, { x + r * 0.7, y }, { x, y + r }, { x - r * 0.7, y } }, 0.18)
        poly({ { x, y - r }, { x, y + r }, { x - r * 0.7, y } }, edge, base, 0.7)
    end
    local function rune(x, y, size, index)
        if index % 3 == 0 then
            stroke({ { x - size, y - size }, { x, y + size }, { x + size, y - size } }, 1.2, edge, false, 0.65)
            line(x, y + size, x, y - size * 1.4, 1.2, edge, 0.65)
        elseif index % 3 == 1 then
            stroke({ { x - size, y }, { x + size, y }, { x, y - size }, { x, y + size } }, 1.2, base, false, 0.8)
        else
            stroke({ { x - size, y - size }, { x + size, y }, { x - size, y + size }, { x - size, y - size } }, 1.2, edge, false, 0.6)
        end
    end
    if id == "carapace" then
        -- 六块独立甲片、脊梁、关节、暗金核心。
        for row = 0, 2 do
            local y = 101 + row * 25
            for _, side in ipairs({ -1, 1 }) do
                local points = { { 128 + side * 5, y }, { 128 + side * 33, y - 11 },
                    { 128 + side * 32, y + 8 }, { 128 + side * 8, y + 19 } }
                glyph(points, 0.22 + row * 0.17)
                line(128 + side * 10, y + 1, 128 + side * 27, y - 5, 1.8, edge, 0.75)
                rivet(128 + side * 25, y + 4, 2.5)
                rivet(128 + side * 52, 95 + row * 29, 3.5)
            end
        end
        glyph({ { 124, 92 }, { 132, 92 }, { 133, 172 }, { 128, 191 }, { 123, 172 } }, 0.58)
        gem(128, 83, 9)
        poly({ { 104, 74 }, { 111, 63 }, { 116, 74 } }, dark)
        poly({ { 152, 74 }, { 145, 63 }, { 140, 74 } }, dark)
        for _, side in ipairs({ -1, 1 }) do
            stroke({ { 128 + side * 31, 83 }, { 128 + side * 46, 68 }, { 128 + side * 39, 58 } }, 2.8, cold)
        end
    elseif id == "faceless" then
        -- 兜帽暗褶、额冠、面颊护片与封口缝线。
        for _, side in ipairs({ -1, 1 }) do
            poly({ { 128 + side * 22, 72 }, { 128 + side * 45, 93 }, { 128 + side * 53, 135 },
                { 128 + side * 40, 170 }, { 128 + side * 23, 184 }, { 128 + side * 36, 139 } }, cold, shadow, 0.9)
            stroke({ { 128 + side * 39, 86 }, { 128 + side * 48, 129 }, { 128 + side * 33, 175 } }, 1.6, edge, false, 0.6)
            glyph({ { 128 + side * 19, 130 }, { 128 + side * 29, 124 }, { 128 + side * 24, 150 },
                { 128 + side * 9, 163 } }, 0.68)
            rivet(128 + side * 24, 135, 2)
        end
        glyph({ { 104, 96 }, { 113, 81 }, { 125, 86 }, { 128, 79 }, { 132, 86 }, { 143, 81 }, { 152, 96 },
            { 143, 101 }, { 128, 94 }, { 113, 101 } }, 0.56)
        gem(128, 92, 5.5)
        glyph({ { 128, 112 }, { 134, 140 }, { 128, 148 }, { 121, 140 } }, 0.5)
        line(113, 163, 143, 163, 2.4, dark)
        for x = 116, 140, 6 do line(x, 158, x + 2, 169, 1.4, edge, 0.8) end
        stroke({ { 146, 103 }, { 141, 111 }, { 147, 118 }, { 145, 128 } }, 1.8, dark)
    elseif id == "riftcrystal" then
        -- 大小晶体多面镶嵌，石座、碎裂能量与内部裂纹。
        for _, p in ipairs({ { 73, 147, 6 }, { 176, 174, 7 }, { 91, 182, 5 }, { 162, 79, 5 } }) do gem(p[1], p[2], p[3]) end
        poly({ { 102, 93 }, { 125, 59 }, { 116, 101 }, { 111, 155 } }, cold, shade, 0.68)
        poly({ { 133, 106 }, { 154, 91 }, { 142, 140 }, { 129, 187 } }, base, shadow, 0.82)
        stroke({ { 124, 64 }, { 117, 99 }, { 125, 118 }, { 119, 139 }, { 129, 162 } }, 1.5, edge, false, 0.85)
        glyph({ { 97, 172 }, { 111, 182 }, { 128, 191 }, { 146, 180 }, { 163, 170 }, { 155, 187 },
            { 128, 203 }, { 101, 187 } }, 0.66)
        rivet(109, 185, 2.2); rivet(147, 185, 2.2)
        arc(128, 142, 71, 160, 208, 1.8, base, 0.65)
        arc(128, 142, 71, 322, 350, 1.8, base, 0.65)
        line(61, 92, 69, 105, 2, cold); line(194, 126, 189, 140, 2, cold)
    elseif id == "last_rite" then
        -- 带底座圣杯、曲柄雕花、宝石镶嵌与链饰。
        arc(128, 83, 44, 170, 365, 1.5, cold, 0.75)
        for i = 0, 5 do
            local a = (190 + i * 28) * math.pi / 180
            rune(128 + math.cos(a) * 50, 83 + math.sin(a) * 50, 3, i)
        end
        for _, side in ipairs({ -1, 1 }) do
            bezier({ 128 + side * 43, 101 }, { 128 + side * 74, 93 }, { 128 + side * 64, 143 },
                { 128 + side * 27, 139 }, 2.5, edge)
            stroke({ { 128 + side * 35, 107 }, { 128 + side * 23, 117 }, { 128 + side * 27, 133 },
                { 128 + side * 12, 143 } }, 1.6, shade)
            circle(128 + side * 21, 128, 8, shade)
            gem(128 + side * 21, 128, 5)
        end
        gem(128, 130, 10)
        glyph({ { 118, 152 }, { 138, 152 }, { 135, 159 }, { 121, 159 } }, 0.65)
        glyph({ { 114, 170 }, { 142, 170 }, { 146, 178 }, { 110, 178 } }, 0.45)
        line(102, 185, 153, 185, 1.6, shade)
        for _, x in ipairs({ 107, 118, 128, 139, 150 }) do rune(x, 187, 2.3, x) end
    elseif id == "tidepress" then
        -- 水脉被压力装置抱住，金属夹爪、阀环和悬浮水珠。
        arc(128, 137, 67, -18, 75, 5, cold)
        arc(128, 137, 67, 111, 168, 5, cold)
        for _, p in ipairs({ { 65, 127 }, { 98, 194 }, { 178, 171 } }) do
            rivet(p[1], p[2], 5)
            circle(p[1], p[2], 1.5, base)
        end
        glyph({ { 59, 111 }, { 76, 115 }, { 78, 126 }, { 66, 130 }, { 60, 121 } }, 0.6)
        glyph({ { 161, 185 }, { 178, 172 }, { 184, 180 }, { 169, 195 } }, 0.6)
        poly({ { 124, 75 }, { 113, 113 }, { 100, 131 }, { 111, 121 }, { 128, 103 } }, edge, base, 0.55)
        bezier({ 100, 154 }, { 116, 142 }, { 130, 184 }, { 157, 153 }, 2.2, edge, 0.65)
        bezier({ 93, 137 }, { 108, 109 }, { 144, 150 }, { 162, 134 }, 1.5, cold)
        for _, p in ipairs({ { 182, 108 }, { 76, 82 }, { 168, 65 } }) do gem(p[1], p[2], 3.5) end
    elseif id == "nitros" then
        -- 层叠轮胎、带螺栓的轮毂与机械火焰。
        circle(133, 142, 43, cold, shadow)
        circle(133, 142, 38, dark)
        circle(133, 142, 33, edge, shade)
        circle(133, 142, 27, dark)
        for i = 0, 7 do
            local a = i * math.pi / 4
            local x, y = 133 + math.cos(a) * 29, 142 + math.sin(a) * 29
            rivet(x, y, 2)
            line(133 + math.cos(a) * 40, 142 + math.sin(a) * 40,
                133 + math.cos(a + 0.09) * 44, 142 + math.sin(a + 0.09) * 44, 2.5, dark)
        end
        for i = 0, 5 do
            local a = i * math.pi / 3
            line(133 + math.cos(a) * 8, 142 + math.sin(a) * 8, 133 + math.cos(a) * 25,
                142 + math.sin(a) * 25, 4, light)
        end
        circle(133, 142, 9, base, shade); rivet(133, 142, 4)
        for _, x in ipairs({ 94, 111, 147, 165 }) do
            stroke({ { x, 98 }, { x + 4, 87 }, { x + 9, 106 } }, 1.6, edge)
        end
        stroke({ { 60, 128 }, { 80, 125 }, { 89, 121 } }, 2, base)
    elseif id == "swordgate" then
        -- 哥特门柱与长剑：分段握柄、双层护手、血槽和门缝符文。
        for _, x in ipairs({ 82, 174 }) do
            glyph({ { x - 7, 182 }, { x + 7, 182 }, { x + 10, 193 }, { x - 10, 193 } }, 0.7)
            line(x - 2, 93, x - 2, 169, 1.5, cold)
            for _, y in ipairs({ 102, 137, 169 }) do rune(x, y, 3, y) end
        end
        stroke({ { 83, 76 }, { 105, 69 }, { 128, 48 }, { 151, 69 }, { 173, 76 } }, 2, cold)
        for _, p in ipairs({ { 103, 104, 158 }, { 128, 87, 184 }, { 153, 104, 158 } }) do
            local x, y, endY = p[1], p[2], p[3]
            circle(x, y - 18, 3.5, edge, shade)
            for j = 0, 2 do line(x - 3, y - 14 + j * 4, x + 3, y - 12 + j * 4, 1.4, cold) end
            stroke({ { x - 14, y + 1 }, { x - 10, y - 5 }, { x, y - 3 }, { x + 10, y - 5 }, { x + 14, y + 1 } }, 2, edge)
            poly({ { x - 3, y + 7 }, { x + 3, y + 7 }, { x + 3, endY - 12 }, { x, endY - 3 }, { x - 3, endY - 12 } }, light, shade)
            line(x, y + 10, x, endY - 15, 1.7, dark)
        end
        gem(128, 60, 5)
    elseif id == "starless" then
        -- 多环星盘、刻度指针、断轨和星辰镶钉。
        arc(128, 126, 77, 165, 255, 2.2, cold, 0.8)
        arc(128, 126, 77, 305, 348, 2.2, cold, 0.8)
        for i = 0, 18 do
            local a = (8 + i * 18) * math.pi / 180
            line(128 + math.cos(a) * 67, 126 + math.sin(a) * 67,
                128 + math.cos(a) * (i % 3 == 0 and 73 or 70), 126 + math.sin(a) * (i % 3 == 0 and 73 or 70),
                1.1, cold, 0.75)
        end
        stroke({ { 106, 118 }, { 119, 113 }, { 128, 92 }, { 138, 114 }, { 150, 127 }, { 136, 140 },
            { 128, 160 }, { 116, 137 }, { 106, 118 } }, 1.3, shade, false, 0.85)
        line(128, 78, 128, 102, 1.7, edge, 0.75)
        for _, p in ipairs({ { 82, 82 }, { 128, 57 }, { 187, 109 }, { 157, 176 }, { 82, 171 } }) do rivet(p[1], p[2], 3.2) end
        rune(103, 183, 3, 0); rune(153, 72, 3, 1)
    elseif id == "ironwall" then
        -- 外围锻铁护板、城墙石缝、浮雕塔楼与深红护心石。
        for _, side in ipairs({ -1, 1 }) do
            glyph({ { 128 + side * 40, 86 }, { 128 + side * 33, 90 }, { 128 + side * 28, 142 },
                { 128 + side * 16, 163 }, { 128 + side * 25, 166 }, { 128 + side * 36, 145 } }, 0.75)
            for _, y in ipairs({ 97, 122, 147 }) do rivet(128 + side * (y > 140 and 28 or 36), y, 2.8) end
        end
        for _, y in ipairs({ 120, 130, 140 }) do
            line(107, y, 122, y, 1.4, dark); line(134, y, 149, y, 1.4, dark)
            line(113 + (y % 20), y - 9, 113 + (y % 20), y, 1.2, dark)
        end
        glyph({ { 118, 111 }, { 122, 104 }, { 135, 104 }, { 139, 111 }, { 137, 149 }, { 120, 149 } }, 0.44)
        poly({ { 125, 130 }, { 132, 130 }, { 132, 150 }, { 125, 150 } }, dark)
        rune(128, 165, 4.5, 0)
    elseif id == "emberscout" then
        -- 包金弓臂、皮革握把、多羽箭与余烬枝叶。
        bezier({ 143, 79 }, { 89, 90 }, { 77, 143 }, { 139, 182 }, 2.3, cold)
        for i = 0, 7 do line(86 + i * 0.8, 106 + i * 5, 94 + i * 0.8, 110 + i * 5, 2.2, shade) end
        line(91, 138, 176, 82, 1.8, cold)
        for i = 0, 2 do
            glyph({ { 88 + i * 5, 145 - i * 4 }, { 76 + i * 5, 142 - i * 4 },
                { 77 + i * 5, 151 - i * 4 }, { 85 + i * 5, 152 - i * 4 } }, 0.52)
        end
        stroke({ { 163, 185 }, { 173, 163 }, { 190, 147 } }, 2, shade)
        glyph({ { 172, 165 }, { 179, 148 }, { 185, 150 }, { 180, 163 } }, 0.8)
        glyph({ { 164, 178 }, { 163, 161 }, { 168, 157 }, { 173, 174 } }, 0.75)
        for _, p in ipairs({ { 183, 60 }, { 193, 74 }, { 178, 96 } }) do gem(p[1], p[2], 2.7) end
    elseif id == "gambler" then
        -- 骰子金属包角、内凿点数、残响弧与细链。
        for _, p in ipairs({ { 124, 67 }, { 72, 101 }, { 184, 101 }, { 73, 161 }, { 124, 192 }, { 184, 161 } }) do
            glyph({ { p[1], p[2] - 5 }, { p[1] + 5, p[2] }, { p[1], p[2] + 5 }, { p[1] - 5, p[2] } }, 0.65)
        end
        for _, p in ipairs({ { 113, 91 }, { 139, 107 }, { 92, 127 }, { 103, 153 }, { 149, 140 }, { 164, 159 } }) do
            circle(p[1], p[2], 5.7, shade); circle(p[1], p[2] + 1, 4, dark)
            arc(p[1], p[2], 5, 180, 315, 1.1, edge, 0.6)
        end
        stroke({ { 82, 112 }, { 118, 132 }, { 118, 178 } }, 1.1, edge, false, 0.8)
        for i = 0, 7 do circle(71 + i * 4, 176 + i * 1.7, 2.4, cold, shade) end
        rune(148, 91, 2.6, 2); rune(168, 148, 2.6, 1)
    elseif id == "bonehunger" then
        -- 双排牙根、骨脊、缠绕束带及不规则骨质裂纹。
        for _, side in ipairs({ -1, 1 }) do
            poly({ { 128 + side * 48, 77 }, { 128 + side * 42, 102 }, { 128 + side * 35, 120 },
                { 128 + side * 31, 143 }, { 128 + side * 38, 126 }, { 128 + side * 49, 111 } }, edge, base, 0.55)
            stroke({ { 128 + side * 42, 91 }, { 128 + side * 39, 108 }, { 128 + side * 44, 114 } }, 1.5, dark)
            for i = 0, 2 do line(128 + side * 40, 111 + i * 5, 128 + side * 48, 114 + i * 5, 2.5, shade) end
        end
        for _, x in ipairs({ 99, 111, 123, 135, 147, 159 }) do
            glyph({ { x - 4, 140 }, { x + 4, 140 }, { x + 2, 154 }, { x, 159 }, { x - 2, 154 } }, 0.28)
        end
        poly({ { 99, 123 }, { 107, 125 }, { 116, 121 }, { 123, 125 }, { 139, 121 }, { 151, 125 }, { 160, 122 },
            { 165, 137 }, { 94, 137 } }, light, shade)
        stroke({ { 106, 126 }, { 114, 130 }, { 119, 128 }, { 130, 134 }, { 145, 130 } }, 1.4, dark)
        gem(128, 181, 7)
    end
end

return M
