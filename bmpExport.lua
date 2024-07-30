local formatOptions <const> = {
    "IDX4",
    "IDX8",
    "RGB15",
    "RGB24",
    "RGB32",
    "RGBA16",
    "RGBA32",
}

local defaults <const> = {
    -- Krita opens both this RGBA16 and Gimp RGBA16 as translucent.
    -- TODO: Look into difference between RGBA16 and RGBX16. (initial guess
    -- is that it's a double high bmp like those in an ico.)
    formatOption = "RGB24"
}

local dlg <const> = Dialog { title = "Export BMP 2" }

dlg:combobox {
    id = "formatOption",
    label = "Format:",
    option = defaults.formatOption,
    options = formatOptions,
    focus = false,
}

dlg:newrow { always = false }

dlg:file {
    id = "filename",
    label = "File:",
    filetypes = { "bmp" },
    save = true,
    focus = true
}

dlg:newrow { always = false }

dlg:button {
    id = "confirm",
    text = "&OK",
    onclick = function()
        local activeSprite <const> = app.sprite
        if not activeSprite then
            app.alert { title = "Error", text = "There is no active sprite." }
            return
        end

        local args <const> = dlg.data
        local exportFilepath = args.filename --[[@as string]]

        if (not exportFilepath) or (#exportFilepath < 1) then
            app.alert { title = "Error", text = "Invalid file path." }
            return
        end

        local fileExt <const> = app.fs.fileExtension(exportFilepath)
        local fileExtLc <const> = string.lower(fileExt)
        local extIsBmp <const> = fileExtLc == "bmp"
        if (not extIsBmp) then
            app.alert { title = "Error", text = "Extension must be bmp." }
            return
        end

        -- Acquire tool to prevent errors.
        local tool <const> = app.tool
        if tool then
            local toolName <const> = tool.id
            if toolName == "slice" then
                app.tool = "hand"
            end
        end

        -- Unpack sprite.
        local spriteSpec <const> = activeSprite.spec
        local wSprite <const> = spriteSpec.width
        local hSprite <const> = spriteSpec.height
        local colorMode <const> = spriteSpec.colorMode
        local alphaIdx <const> = spriteSpec.transparentColor

        local hasBkg <const> = activeSprite.backgroundLayer ~= nil

        local activeFrObj <const> = app.frame or activeSprite.frames[1]
        local activeFrIdx <const> = activeFrObj.frameNumber

        local cmIsRgb <const> = colorMode == ColorMode.RGB
        local cmIsGry <const> = colorMode == ColorMode.GRAY
        local cmIsIdx <const> = colorMode == ColorMode.INDEXED

        local formatOption <const> = args.formatOption
            or defaults.formatOption --[[@as string]]

        local fmtIsIdx1 <const> = formatOption == "IDX1"
        local fmtIsIdx2 <const> = formatOption == "IDX2"
        local fmtIsIdx4 <const> = formatOption == "IDX4"
        local fmtIsIdx8 <const> = formatOption == "IDX8"
        local fmtIsIdx <const> = fmtIsIdx1
            or fmtIsIdx2
            or fmtIsIdx4
            or fmtIsIdx8

        local fmtIsRgb15 <const> = formatOption == "RGB15"
        local fmtIsRgb24 <const> = formatOption == "RGB24"
        local fmtIsRgb32 <const> = formatOption == "RGB32"

        local fmtIsRgba16 <const> = formatOption == "RGBA16"
        local fmtIsRgba32 <const> = formatOption == "RGBA32"
        local fmtIsRgba <const> = fmtIsRgba16
            or fmtIsRgba32

        -- TODO: Instead of returning early, create an AseColor
        -- then use the index function?
        if fmtIsIdx and cmIsRgb then
            app.alert {
                title = "Error",
                text = "Sprite is not in indexed color mode."
            }
            return
        end

        local spritePalettes <const> = activeSprite.palettes
        local lenSpritePalettes <const> = #spritePalettes
        local palette <const> = (activeFrIdx <= lenSpritePalettes and cmIsIdx)
            and spritePalettes[activeFrIdx]
            or spritePalettes[1]
        local lenPalette <const> = #palette

        local lenWritePal = lenPalette
        if fmtIsIdx8 then
            lenWritePal = 256
        elseif fmtIsIdx4 then
            lenWritePal = 16
        elseif fmtIsIdx2 then
            lenWritePal = 4
        elseif fmtIsIdx1 then
            lenWritePal = 2
        end

        local lenPalClamped = math.min(lenWritePal, lenPalette)
        local alphaIdxVerif <const> = alphaIdx < lenPalClamped
            and alphaIdx
            or 0

        local flatImage <const> = Image(spriteSpec)
        flatImage:drawSprite(activeSprite, activeFrIdx)
        local flatBytes <const> = flatImage.bytes
        local areaSprite <const> = wSprite * hSprite

        local floor <const> = math.floor
        local ceil <const> = math.ceil
        local strbyte <const> = string.byte
        local strpack <const> = string.pack
        local strchar <const> = string.char
        local strsub <const> = string.sub

        ---@type integer[]
        local abgr32s <const> = {}
        ---@type integer[]
        local idcs <const> = {}

        if cmIsRgb then
            local h = 0
            while h < areaSprite do
                local h4 <const> = h * 4
                local r8 <const>,
                g8 <const>,
                b8 <const>,
                a8 <const> = strbyte(flatBytes, 1 + h4, 4 + h4)
                local abgr32 <const> = a8 << 0x18 | b8 << 0x10 | g8 << 0x08 | r8
                abgr32s[1 + h] = abgr32
                h = h + 1
            end
        elseif cmIsGry then
            if fmtIsIdx8 then
                local h = 0
                while h < areaSprite do
                    local h2 <const> = h * 2
                    local v8 <const>, _ <const> = strbyte(flatBytes, 1 + h2, 2 + h2)
                    idcs[1 + h] = v8
                    h = h + 1
                end
            elseif fmtIsIdx4 then
                local convert <const> = 15.0 / 255.0

                local h = 0
                while h < areaSprite do
                    local h2 <const> = h * 2
                    local v8 <const>, _ <const> = strbyte(flatBytes, 1 + h2, 2 + h2)
                    idcs[1 + h] = floor(v8 * convert + 0.5)
                    h = h + 1
                end
            elseif fmtIsIdx2 then
                local convert <const> = 3.0 / 255.0

                local h = 0
                while h < areaSprite do
                    local h2 <const> = h * 2
                    local v8 <const>, _ <const> = strbyte(flatBytes, 1 + h2, 2 + h2)
                    idcs[1 + h] = floor(v8 * convert + 0.5)
                    h = h + 1
                end
            elseif fmtIsIdx1 then
                local h = 0
                while h < areaSprite do
                    local h2 <const> = h * 2
                    local v8 <const>, _ <const> = strbyte(flatBytes, 1 + h2, 2 + h2)
                    idcs[1 + h] = v8 >= 128 and 1 or 0
                    h = h + 1
                end
            else
                local h = 0
                while h < areaSprite do
                    local h2 <const> = h * 2
                    local v8 <const>,
                    a8 <const> = strbyte(flatBytes, 1 + h2, 2 + h2)
                    local abgr32 <const> = a8 << 0x18 | v8 << 0x10 | v8 << 0x08 | v8
                    abgr32s[1 + h] = abgr32
                    h = h + 1
                end
            end
        elseif cmIsIdx then
            if fmtIsIdx then
                local h = 0
                while h < areaSprite do
                    local idx <const> = strbyte(flatBytes, 1 + h)
                    local idxVerif <const> = idx < lenPalClamped
                        and idx
                        or alphaIdxVerif
                    idcs[1 + h] = idxVerif
                    h = h + 1
                end
            else
                local h = 0
                while h < areaSprite do
                    local idx <const> = strbyte(flatBytes, 1 + h)
                    local idxVerif <const> = idx < lenPalClamped
                        and idx
                        or alphaIdxVerif

                    local r8 = 0
                    local g8 = 0
                    local b8 = 0
                    local a8 = 0

                    if hasBkg or idxVerif ~= alphaIdxVerif then
                        local aseColor <const> = palette:getColor(idxVerif)

                        r8 = aseColor.red
                        g8 = aseColor.green
                        b8 = aseColor.blue
                        a8 = aseColor.alpha
                    end

                    local abgr32 <const> = a8 << 0x18 | b8 << 0x10 | g8 << 0x08 | r8
                    abgr32s[1 + h] = abgr32

                    h = h + 1
                end
            end
        else
            app.alert { title = "Error", text = "Unrecognized color mode." }
            return
        end

        -- Write the palette.
        local palStr = ""
        if fmtIsIdx then
            ---@type string[]
            local palStrArr <const> = {}
            local zeroChar <const> = strchar(0)

            if cmIsGry then
                local toFac <const> = lenWritePal > 0
                    and 1.0 / (lenWritePal - 1.0)
                    or 0.0
                local i = 0
                while i < lenWritePal do
                    local fac <const> = i * toFac
                    local v8 <const> = floor(fac * 255.0 + 0.5)
                    local v8Char <const> = strchar(v8)

                    local i4 <const> = i * 4
                    palStrArr[1 + i4] = v8Char
                    palStrArr[2 + i4] = v8Char
                    palStrArr[3 + i4] = v8Char
                    palStrArr[4 + i4] = zeroChar

                    i = i + 1
                end
            else
                local i = 0
                while i < lenPalClamped do
                    local aseColor <const> = palette:getColor(i)
                    local r8 <const> = aseColor.red
                    local g8 <const> = aseColor.green
                    local b8 <const> = aseColor.blue

                    local i4 <const> = i * 4
                    palStrArr[1 + i4] = strchar(b8)
                    palStrArr[2 + i4] = strchar(g8)
                    palStrArr[3 + i4] = strchar(r8)
                    palStrArr[4 + i4] = zeroChar

                    i = i + 1
                end

                -- Pad shorter palettes to fit write length.
                while i < lenWritePal do
                    palStrArr[#palStrArr + 1] = zeroChar
                    palStrArr[#palStrArr + 1] = zeroChar
                    palStrArr[#palStrArr + 1] = zeroChar
                    palStrArr[#palStrArr + 1] = zeroChar
                    i = i + 1
                end
            end

            palStr = table.concat(palStrArr)
        end

        ---@type string[]
        local trgStrArr <const> = {}
        local hn1 <const> = hSprite - 1

        if fmtIsRgb32 or fmtIsRgba32 then
            local j = 0
            while j < areaSprite do
                local abgr32 <const> = abgr32s[1 + j]

                local a8 <const> = abgr32 >> 0x18 & 0xff
                local b8 <const> = abgr32 >> 0x10 & 0xff
                local g8 <const> = abgr32 >> 0x08 & 0xff
                local r8 <const> = abgr32 & 0xff

                local x <const> = j % wSprite
                local y <const> = j // wSprite
                local yFlipped <const> = hn1 - y
                local n <const> = yFlipped * wSprite + x

                trgStrArr[1 + n] = strpack("B B B B", b8, g8, r8, a8)

                j = j + 1
            end
        elseif fmtIsRgb24 then
            local bytesPerRow <const> = 4 * ceil((wSprite * 24) / 32)
            local hbpr <const> = hSprite * bytesPerRow

            local n = 0
            while n < hbpr do
                local xByte <const> = n % bytesPerRow
                local yFlipped <const> = n // bytesPerRow
                local x <const> = xByte // 3

                local value = 0
                if x < wSprite then
                    local y <const> = hn1 - yFlipped
                    local j <const> = y * wSprite + x
                    local abgr32 <const> = abgr32s[1 + j]

                    local channel <const> = xByte % 3
                    if channel == 2 then
                        value = abgr32 & 0xff
                    elseif channel == 1 then
                        value = (abgr32 >> 0x08) & 0xff
                    else
                        value = (abgr32 >> 0x10) & 0xff
                    end
                end

                trgStrArr[1 + n] = strchar(value)

                n = n + 1
            end
        elseif fmtIsRgb15 or fmtIsRgba16 then
            local bytesPerRow <const> = 4 * ceil((wSprite * 16) / 32)
            local hbpr <const> = hSprite * bytesPerRow
            local from8to5 <const> = 31.0 / 255.0

            local n = 0
            while n < hbpr do
                local xByte <const> = n % bytesPerRow
                local yFlipped <const> = n // bytesPerRow
                local x <const> = xByte // 2

                local value = 0
                if x < wSprite then
                    local y <const> = hn1 - yFlipped
                    local j <const> = y * wSprite + x
                    local abgr32 <const> = abgr32s[1 + j]

                    local a8 <const> = abgr32 >> 0x18 & 0xff
                    local b8 <const> = abgr32 >> 0x10 & 0xff
                    local g8 <const> = abgr32 >> 0x08 & 0xff
                    local r8 <const> = abgr32 & 0xff

                    local a1 <const> = a8 >= 128 and 1 or 0
                    local r5 <const> = floor(0.5 + r8 * from8to5)
                    local g5 <const> = floor(0.5 + g8 * from8to5)
                    local b5 <const> = floor(0.5 + b8 * from8to5)

                    local rgb555 <const> = a1 << 0xf | r5 << 0xa | g5 << 0x5 | b5

                    local channel <const> = xByte % 2
                    if channel == 1 then
                        value = (rgb555 >> 0x08) & 0xff
                    else
                        value = rgb555 & 0xff
                    end
                end

                trgStrArr[1 + n] = strchar(value)

                n = n + 1
            end
        elseif fmtIsIdx8 then
            local bytesPerRow <const> = 4 * ceil((wSprite * 8) / 32)
            local hbpr <const> = hSprite * bytesPerRow

            local n = 0
            while n < hbpr do
                local x <const> = n % bytesPerRow
                local yFlipped <const> = n // bytesPerRow

                local idxVerif = 0
                if x < wSprite then
                    local y <const> = hn1 - yFlipped
                    local j <const> = y * wSprite + x
                    local idx <const> = idcs[1 + j]
                    idxVerif = idx < lenPalClamped
                        and idx
                        or alphaIdxVerif
                end

                trgStrArr[1 + n] = strchar(idxVerif)

                n = n + 1
            end

            -- TODO: Implement.
        elseif fmtIsIdx4 then
            -- TODO: Implement.
        elseif fmtIsIdx2 then
            -- TODO: Implement.
        elseif fmtIsIdx1 then
            -- TODO: Implement.
        end
        local trgStr <const> = table.concat(trgStrArr)

        local dibLen = 40
        local headerLen = 54
        if fmtIsRgba then
            -- V4
            dibLen = 108
            headerLen = 122
        end
        local dataLen = headerLen + #trgStr
        local dataOffset = headerLen + #palStr

        local bpp = 32
        if fmtIsRgb32 or fmtIsRgba32 then
            bpp = 32
        elseif fmtIsRgb24 then
            bpp = 24
        elseif fmtIsRgb15 or fmtIsRgba16 then
            bpp = 16
        elseif fmtIsIdx8 then
            bpp = 8
        elseif fmtIsIdx4 then
            bpp = 4
        elseif fmtIsIdx2 then
            bpp = 2
        elseif fmtIsIdx1 then
            bpp = 1
        end

        local header = ""
        if fmtIsRgba then
            -- https://learn.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-bitmapv4header

            local rMask = 0x00ff0000
            local gMask = 0x0000ff00
            local bMask = 0x000000ff
            local aMask = 0xff000000

            if fmtIsRgba16 then
                -- TODO: Requires testing.

                rMask = 0x7c00 -- 0x1f << 0xa
                gMask = 0x03e0 -- 0x1f << 0x5
                bMask = 0x001f -- 0x1f << 0x0
                aMask = 0x8000 -- 0x01 << 0xf
            end

            header = table.concat({
                string.pack("I4", dataLen),    -- 006
                string.pack("I4", 0),          -- 010
                string.pack("I4", dataOffset), -- 014
                string.pack("I4", dibLen),     -- 018
                string.pack("i4", wSprite),    -- 022
                string.pack("i4", hSprite),    -- 026
                string.pack("I2", 1),          -- 030 bit planes
                string.pack("I2", bpp),        -- 032 bits per pixel
                string.pack("I4", 3),          -- 034 compression
                string.pack("I4", 0),          -- 038 size of compressed image
                string.pack("I4", 0),          -- 042 x res
                string.pack("I4", 0),          -- 046 y res
                string.pack("I4", 0),          -- 050 colors used
                string.pack("I4", 0),          -- 054 important colors

                string.pack("I4", rMask),      -- 058 red bit mask
                string.pack("I4", gMask),      -- 062 green bit mask
                string.pack("I4", bMask),      -- 066 blue bit mask
                string.pack("I4", aMask),      -- 070 alpha bit mask

                string.pack("c1 c1 c1 c1", 'B', 'G', 'R', 's'),
                string.pack("f f f f f f f f f", 0, 0, 0, 0, 0, 0, 0, 0, 0),

                string.pack("I4", 0), -- 114 r gamma
                string.pack("I4", 0), -- 118 g gamma
                string.pack("I4", 0), -- 122 b gamma
            })
        else
            -- https://learn.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-bitmapinfoheader

            header = table.concat({
                string.pack("I4", dataLen),    -- 06
                string.pack("I4", 0),          -- 10
                string.pack("I4", dataOffset), -- 14
                string.pack("I4", dibLen),     -- 18
                string.pack("i4", wSprite),    -- 22
                string.pack("i4", hSprite),    -- 26
                string.pack("I2", 1),          -- 30 bit planes
                string.pack("I2", bpp),        -- 32 bits per pixel
                string.pack("I4", 0),          -- 34 compression
                string.pack("I4", 0),          -- 38 size of compressed image
                string.pack("I4", 0),          -- 42 x res
                string.pack("I4", 0),          -- 46 y res
                string.pack("I4", 0),          -- 50 colors used
                string.pack("I4", 0),          -- 54 important colors
            })
        end

        local binFile <const>, err <const> = io.open(exportFilepath, "wb")
        if err ~= nil then
            if binFile then binFile:close() end
            app.alert { title = "Error", text = err }
            return
        end
        if binFile == nil then return end

        local fileStr = table.concat({
            "BM",
            header,
            palStr,
            trgStr
        })

        binFile:write(fileStr)
        binFile:close()

        app.alert {
            title = "Success",
            text = "File exported."
        }
    end
}

dlg:button {
    id = "cancel",
    text = "&CANCEL",
    focus = false,
    onclick = function()
        dlg:close()
    end
}

dlg:show {
    autoscrollbars = true,
    wait = false
}