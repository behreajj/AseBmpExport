local formatOptions <const> = {
    "IDX1",
    "IDX4",
    "IDX8",
    "RGB15",  -- RGB_5550
    "RGB16",  -- RGB565
    "RGB24",  -- RGB888
    "RGB32",  -- RGB_8880
    "RGBA16", -- RGBA5551
    "RGBA32", -- RGBA8888
}

local frameOptions <const> = {
    "ACTIVE",
    "ALL",
    "TAG",
}

local layerOptions <const> = {
    "ACTIVE",
    "CANVAS",
}

local defaults <const> = {
    layerOption = "CANVAS",
    frameOption = "ACTIVE",
    formatOption = "RGB24",
    upscale = 1,
    applyRatio = false,
}

---@param source Image
---@param wScale integer
---@param hScale integer
---@return Image
---@nodiscard
local function upscaleImageForExport(source, wScale, hScale)
    local wScaleVrf <const> = math.max(1, math.abs(wScale))
    local hScaleVrf <const> = math.max(1, math.abs(hScale))
    if wScaleVrf == 1 and hScaleVrf == 1 then
        return source
    end

    local srcByteStr <const> = source.bytes
    local bpp <const> = source.bytesPerPixel
    local srcSpec <const> = source.spec
    local wSrc <const> = srcSpec.width
    local hSrc <const> = srcSpec.height

    ---@type string[]
    local resized <const> = {}
    local lenKernel <const> = wScaleVrf * hScaleVrf
    local lenSrc <const> = wSrc * hSrc
    local wTrg <const> = wSrc * wScaleVrf
    local hTrg <const> = hSrc * hScaleVrf

    local trgSpec <const> = ImageSpec {
        width = wTrg,
        height = hTrg,
        colorMode = srcSpec.colorMode,
        transparentColor = srcSpec.transparentColor
    }
    trgSpec.colorSpace = srcSpec.colorSpace
    local target <const> = Image(trgSpec)

    local strsub <const> = string.sub
    local i = 0
    while i < lenSrc do
        local xTrg <const> = wScaleVrf * (i % wSrc)
        local yTrg <const> = hScaleVrf * (i // wSrc)
        local ibpp <const> = i * bpp
        local srcStr <const> = strsub(srcByteStr, 1 + ibpp, bpp + ibpp)
        local j = 0
        while j < lenKernel do
            local xKernel <const> = xTrg + j % wScaleVrf
            local yKernel <const> = yTrg + j // wScaleVrf
            resized[1 + yKernel * wTrg + xKernel] = srcStr
            j = j + 1
        end
        i = i + 1
    end

    target.bytes = table.concat(resized)
    return target
end

local dlg <const> = Dialog { title = "Export BMP" }

dlg:combobox {
    id = "layerOption",
    label = "Layers:",
    option = defaults.layerOption,
    options = layerOptions,
    focus = false,
}

dlg:newrow { always = false }

dlg:combobox {
    id = "frameOption",
    label = "Frames:",
    option = defaults.frameOption,
    options = frameOptions,
    focus = false,
}

dlg:newrow { always = false }

dlg:combobox {
    id = "formatOption",
    label = "Format:",
    option = defaults.formatOption,
    options = formatOptions,
    focus = false,
}

dlg:newrow { always = false }

dlg:slider {
    id = "upscale",
    label = "Scale:",
    value = defaults.upscale,
    min = 1,
    max = 10,
    focus = false,
}

dlg:newrow { always = false }

dlg:check {
    id = "applyRatio",
    label = "Apply:",
    text = "Pixel Ratio",
    selected = defaults.applyRatio,
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
        local layerOption <const> = args.layerOption
            or defaults.layerOption --[[@as string]]
        local frameOption <const> = args.frameOption
            or defaults.frameOption --[[@as string]]
        local formatOption <const> = args.formatOption
            or defaults.formatOption --[[@as string]]
        local upscale <const> = args.upscale
            or defaults.upscale --[[@as integer]]
        local applyRatio <const> = args.applyRatio --[[@as boolean]]
        local exportFilepath <const> = args.filename --[[@as string]]

        if (not exportFilepath) or (#exportFilepath < 1) then
            app.alert { title = "Error", text = "Invalid file path." }
            return
        end

        local fileSys <const> = app.fs
        local fileExt <const> = fileSys.fileExtension(exportFilepath)
        if string.lower(fileExt) ~= "bmp" then
            app.alert { title = "Error", text = "Extension must be bmp." }
            return
        end

        local activeLayer <const> = app.layer or activeSprite.layers[1]
        local useFlatten <const> = layerOption == "CANVAS"
        if layerOption == "ACTIVE" then
            if activeLayer.isReference then
                app.alert { title = "Error", text = "Reference layers not supported." }
                return
            end

            if activeLayer.isGroup then
                app.alert { title = "Error", text = "Group layers not supported." }
                return
            end

            if activeLayer.isTilemap then
                app.alert { title = "Error", text = "Tile map layers not supported." }
                return
            end
        end

        -- Acquire tool to prevent errors.
        local tool <const> = app.tool
        if tool then
            local toolName <const> = tool.id
            if toolName == "slice" then
                app.tool = "hand"
            end
        end

        -- Cache format option string comparisons to booleans.
        local fmtIsIdx1 <const> = formatOption == "IDX1"
        local fmtIsIdx2 <const> = formatOption == "IDX2"
        local fmtIsIdx4 <const> = formatOption == "IDX4"
        local fmtIsIdx8 <const> = formatOption == "IDX8"

        local fmtIsIdx <const> = fmtIsIdx1
            or fmtIsIdx2
            or fmtIsIdx4
            or fmtIsIdx8

        local fmtIsRgb15 <const> = formatOption == "RGB15"
        local fmtIsRgb16 <const> = formatOption == "RGB16"
        local fmtIsRgb24 <const> = formatOption == "RGB24"
        local fmtIsRgb32 <const> = formatOption == "RGB32"
        local fmtIsRgba16 <const> = formatOption == "RGBA16"
        local fmtIsRgba32 <const> = formatOption == "RGBA32"

        local writeV4Header <const> = fmtIsRgba32
            or fmtIsRgba16
            or fmtIsRgb16

        local bpp = 32
        if fmtIsRgb32 or fmtIsRgba32 then
            bpp = 32
        elseif fmtIsRgb24 then
            bpp = 24
        elseif fmtIsRgb15
            or fmtIsRgb16
            or fmtIsRgba16 then
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

        local dibLen = 40
        local headerLen = 54
        local compression = 0
        if writeV4Header then
            -- V4
            dibLen = 108
            headerLen = 122
            compression = 3
        end

        -- For V4 header, which includes alpha.
        local rMask = 0x00ff0000
        local gMask = 0x0000ff00
        local bMask = 0x000000ff
        local aMask = 0xff000000
        if fmtIsRgb16 then
            rMask = 0xf800 -- 0x1f << 0xb
            gMask = 0x07e0 -- 0x3f << 0x5
            bMask = 0x001f -- 0x1f << 0x0
            aMask = 0x0000
        elseif fmtIsRgba16 then
            -- Krita opens both this RGBA16 and Gimp RGBA16 as translucent.

            rMask = 0x7c00 -- 0x1f << 0xa
            gMask = 0x03e0 -- 0x1f << 0x5
            bMask = 0x001f -- 0x1f << 0x0
            aMask = 0x8000 -- 0x01 << 0xf
        end

        -- Unpack sprite spec.
        local spriteSpec <const> = activeSprite.spec
        local colorMode <const> = spriteSpec.colorMode
        local alphaIdx <const> = spriteSpec.transparentColor

        local cmIsRgb <const> = colorMode == ColorMode.RGB
        local cmIsGry <const> = colorMode == ColorMode.GRAY
        local cmIsIdx <const> = colorMode == ColorMode.INDEXED

        -- Whether or not a background layer is present changes whether a
        -- color index in the image map that is equal to the alpha index is
        -- treated as clear black or as the opaque color.
        local hasBkg <const> = activeSprite.backgroundLayer ~= nil

        -- Find pixel aspect ratio in case image needs to be scaled.
        local pxRatio <const> = activeSprite.pixelRatio
        local wPixel <const> = applyRatio
            and math.max(1, math.abs(pxRatio.width)) or 1
        local hPixel <const> = applyRatio
            and math.max(1, math.abs(pxRatio.height)) or 1
        local wScalar <const> = wPixel * upscale
        local hScalar <const> = hPixel * upscale

        ---@type integer[]
        local chosenFrIdcs <const> = {}
        if frameOption == "ACTIVE" then
            local activeFrObj <const> = app.frame or activeSprite.frames[1]
            local activeFrIdx <const> = activeFrObj.frameNumber
            chosenFrIdcs[1] = activeFrIdx
        elseif frameOption == "TAG" then
            local activeTag <const> = app.tag
            if activeTag then
                local spriteFrObjs <const> = activeSprite.frames
                local lenSpriteFrObjs <const> = #spriteFrObjs

                local frIdxOrig = activeTag.fromFrame
                    and activeTag.fromFrame.frameNumber
                    or 1
                local frIdxDest = activeTag.toFrame
                    and activeTag.toFrame.frameNumber
                    or lenSpriteFrObjs

                frIdxOrig = math.min(frIdxOrig, lenSpriteFrObjs)
                frIdxDest = math.min(frIdxDest, lenSpriteFrObjs)

                if frIdxOrig > frIdxDest then
                    frIdxOrig, frIdxDest = frIdxDest, frIdxOrig
                end

                if frIdxOrig == frIdxDest then
                    chosenFrIdcs[1] = frIdxOrig
                else
                    local h = frIdxOrig - 1
                    while h < frIdxDest do
                        h = h + 1
                        chosenFrIdcs[#chosenFrIdcs + 1] = h
                    end
                end
            else
                local activeFrObj <const> = app.frame or activeSprite.frames[1]
                local activeFrIdx <const> = activeFrObj.frameNumber
                chosenFrIdcs[1] = activeFrIdx
            end
        else
            -- Default to all.
            local spriteFrObjs <const> = activeSprite.frames
            local lenSpriteFrObjs <const> = #spriteFrObjs
            local h = 0
            while h < lenSpriteFrObjs do
                h = h + 1
                chosenFrIdcs[h] = h
            end
        end

        local lenChosenFrIdcs <const> = #chosenFrIdcs
        if lenChosenFrIdcs <= 0 then
            app.alert { title = "Error", text = "No frames were chosen." }
            return
        end

        -- Handle possibility of multiple palettes in a sprite.
        local spritePalettes <const> = activeSprite.palettes
        local lenSpritePalettes <const> = #spritePalettes
        local firstPalette <const> = spritePalettes[1]

        -- Cached methods used in while loops.
        local ceil <const> = math.ceil
        local floor <const> = math.floor
        local min <const> = math.min
        local strbyte <const> = string.byte
        local strchar <const> = string.char
        local strfmt <const> = string.format
        local strpack <const> = string.pack
        local tconcat <const> = table.concat
        local ioopen <const> = io.open

        -- Cached constants used in while loops.
        local zeroi1 <const> = strchar(0)
        local zeroi4 <const> = strpack("<I4", 0)
        local rgb8to5 <const> = 31.0 / 255.0
        local rgb8to6 <const> = 63.0 / 255.0
        local gray8to4 <const> = 15.0 / 255.0
        local gray8to2 <const> = 3.0 / 255.0

        local filePrefix <const> = fileSys.filePathAndTitle(exportFilepath)

        local planesPacked <const> = strpack("<I2", 1)
        local bppPacked <const> = strpack("<I2", bpp)
        local compressPacked <const> = strpack("<I4", compression)
        local rMaskPacked <const> = strpack("<I4", rMask)
        local gMaskPacked <const> = strpack("<I4", gMask)
        local bMaskPacked <const> = strpack("<I4", bMask)
        local aMaskPacked <const> = strpack("<I4", aMask)
        local srgbPacked <const> = strpack(
            "c1 c1 c1 c1",
            'B', 'G', 'R', 's')
        local ciexyzPacked <const> = strpack(
            "f f f f f f f f f",
            0, 0, 0, 0, 0, 0, 0, 0, 0)

        local g = 0
        while g < lenChosenFrIdcs do
            g = g + 1
            local frIdx <const> = chosenFrIdcs[g]

            local palette <const> = (frIdx <= lenSpritePalettes and cmIsIdx)
                and spritePalettes[frIdx]
                or firstPalette
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

            local lenPalClamped = min(lenWritePal, lenPalette)
            local alphaIdxVerif <const> = alphaIdx < lenPalClamped
                and alphaIdx
                or 0

            local flatImage = nil
            if useFlatten then
                flatImage = Image(spriteSpec)
                flatImage:drawSprite(activeSprite, frIdx)
            else
                local activeCel <const> = activeLayer:cel(frIdx)
                if activeCel then
                    flatImage = activeCel.image
                else
                    flatImage = Image(spriteSpec)
                end
            end

            flatImage = upscaleImageForExport(flatImage, wScalar, hScalar)

            local flatBytes <const> = flatImage.bytes
            local wTarget <const> = flatImage.width
            local hTarget <const> = flatImage.height
            local areaTarget <const> = wTarget * hTarget

            ---@type integer[]
            local abgr32s <const> = {}
            ---@type integer[]
            local idcs <const> = {}

            if cmIsRgb then
                if fmtIsIdx then
                    if fmtIsIdx1 then
                        local h = 0
                        while h < areaTarget do
                            local h4 <const> = h * 4
                            local r8 <const>,
                            g8 <const>,
                            b8 <const>,
                            a8 <const> = strbyte(flatBytes, 1 + h4, 4 + h4)

                            local idxVerif = 0
                            if a8 >= 128 then
                                local v8 <const> = (r8 * 30 + g8 * 59 + b8 * 11) // 100
                                idxVerif = v8 >= 128 and 1 or 0
                            end
                            idcs[1 + h] = idxVerif
                            h = h + 1
                        end
                    else
                        local h = 0
                        while h < areaTarget do
                            local h4 <const> = h * 4
                            local r8 <const>,
                            g8 <const>,
                            b8 <const>,
                            a8 <const> = strbyte(flatBytes, 1 + h4, 4 + h4)
                            local aseColor <const> = Color { r = r8, g = g8, b = b8, a = 255 }
                            local idx <const> = aseColor.index
                            local idxVerif <const> = (a8 > 0 and idx < lenPalClamped)
                                and idx
                                or alphaIdxVerif
                            idcs[1 + h] = idxVerif
                            h = h + 1
                        end
                    end
                else
                    local h = 0
                    while h < areaTarget do
                        local h4 <const> = h * 4
                        local r8 <const>,
                        g8 <const>,
                        b8 <const>,
                        a8 <const> = strbyte(flatBytes, 1 + h4, 4 + h4)
                        local abgr32 <const> = a8 << 0x18 | b8 << 0x10 | g8 << 0x08 | r8
                        abgr32s[1 + h] = abgr32
                        h = h + 1
                    end
                end
            elseif cmIsGry then
                if fmtIsIdx8 then
                    local h = 0
                    while h < areaTarget do
                        local v8 <const> = strbyte(flatBytes, 1 + h * 2)
                        idcs[1 + h] = v8
                        h = h + 1
                    end
                elseif fmtIsIdx4 then
                    local h = 0
                    while h < areaTarget do
                        local v8 <const> = strbyte(flatBytes, 1 + h * 2)
                        idcs[1 + h] = floor(v8 * gray8to4 + 0.5)
                        h = h + 1
                    end
                elseif fmtIsIdx2 then
                    local h = 0
                    while h < areaTarget do
                        local v8 <const> = strbyte(flatBytes, 1 + h * 2)
                        idcs[1 + h] = floor(v8 * gray8to2 + 0.5)
                        h = h + 1
                    end
                elseif fmtIsIdx1 then
                    local h = 0
                    while h < areaTarget do
                        local h2 <const> = h * 2
                        local v8 <const>,
                        a8 <const> = strbyte(flatBytes, 1 + h2, 2 + h2)
                        idcs[1 + h] = (a8 >= 128 and v8 >= 128) and 1 or 0
                        h = h + 1
                    end
                else
                    local h = 0
                    while h < areaTarget do
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
                    while h < areaTarget do
                        local idx <const> = strbyte(flatBytes, 1 + h)
                        local idxVerif <const> = idx < lenPalClamped
                            and idx
                            or alphaIdxVerif
                        idcs[1 + h] = idxVerif
                        h = h + 1
                    end
                else
                    local h = 0
                    while h < areaTarget do
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
                        palStrArr[4 + i4] = zeroi1

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
                        palStrArr[4 + i4] = zeroi1

                        i = i + 1
                    end

                    -- Pad shorter palettes to fit write length.
                    while i < lenWritePal do
                        local i4 <const> = i * 4
                        palStrArr[1 + i4] = zeroi1
                        palStrArr[2 + i4] = zeroi1
                        palStrArr[3 + i4] = zeroi1
                        palStrArr[4 + i4] = zeroi1
                        i = i + 1
                    end
                end

                palStr = tconcat(palStrArr)
            end

            ---@type string[]
            local trgStrArr <const> = {}
            local hn1 <const> = hTarget - 1

            if fmtIsRgb32 or fmtIsRgba32 then
                local j = 0
                while j < areaTarget do
                    local abgr32 <const> = abgr32s[1 + j]

                    local a8 <const> = abgr32 >> 0x18 & 0xff
                    local b8 <const> = abgr32 >> 0x10 & 0xff
                    local g8 <const> = abgr32 >> 0x08 & 0xff
                    local r8 <const> = abgr32 & 0xff

                    local x <const> = j % wTarget
                    local y <const> = j // wTarget
                    local yFlipped <const> = hn1 - y
                    local n <const> = yFlipped * wTarget + x

                    trgStrArr[1 + n] = strpack("B B B B", b8, g8, r8, a8)

                    j = j + 1
                end
            elseif fmtIsRgb24 then
                local bytesPerRow <const> = 4 * ceil((wTarget * 24) / 32)
                local hbpr <const> = hTarget * bytesPerRow

                local n = 0
                while n < hbpr do
                    local xByte <const> = n % bytesPerRow
                    local x <const> = xByte // 3

                    local c8 = 0
                    if x < wTarget then
                        local yFlipped <const> = n // bytesPerRow
                        local y <const> = hn1 - yFlipped
                        local j <const> = y * wTarget + x
                        local abgr32 <const> = abgr32s[1 + j]

                        local channel <const> = xByte % 3
                        if channel == 2 then
                            c8 = abgr32 & 0xff
                        elseif channel == 1 then
                            c8 = (abgr32 >> 0x08) & 0xff
                        else
                            c8 = (abgr32 >> 0x10) & 0xff
                        end
                    end

                    trgStrArr[1 + n] = strchar(c8)

                    n = n + 1
                end
            elseif fmtIsRgb16 then
                local bytesPerRow <const> = 4 * ceil((wTarget * 16) / 32)
                local hbpr <const> = hTarget * bytesPerRow

                local n = 0
                while n < hbpr do
                    local xByte <const> = n % bytesPerRow
                    local x <const> = xByte // 2

                    local c8 = 0
                    if x < wTarget then
                        local yFlipped <const> = n // bytesPerRow
                        local y <const> = hn1 - yFlipped
                        local j <const> = y * wTarget + x
                        local abgr32 <const> = abgr32s[1 + j]

                        local b8 <const> = abgr32 >> 0x10 & 0xff
                        local g8 <const> = abgr32 >> 0x08 & 0xff
                        local r8 <const> = abgr32 & 0xff

                        local r5 <const> = floor(r8 * rgb8to5 + 0.5)
                        local g6 <const> = floor(g8 * rgb8to6 + 0.5)
                        local b5 <const> = floor(b8 * rgb8to5 + 0.5)

                        local rgb565 <const> = r5 << 0xb | g6 << 0x5 | b5

                        local channel <const> = xByte % 2
                        if channel == 1 then
                            c8 = (rgb565 >> 0x08) & 0xff
                        else
                            c8 = rgb565 & 0xff
                        end
                    end

                    trgStrArr[1 + n] = strchar(c8)

                    n = n + 1
                end
            elseif fmtIsRgb15 or fmtIsRgba16 then
                local bytesPerRow <const> = 4 * ceil((wTarget * 16) / 32)
                local hbpr <const> = hTarget * bytesPerRow

                local n = 0
                while n < hbpr do
                    local xByte <const> = n % bytesPerRow
                    local x <const> = xByte // 2

                    local c8 = 0
                    if x < wTarget then
                        local yFlipped <const> = n // bytesPerRow
                        local y <const> = hn1 - yFlipped
                        local j <const> = y * wTarget + x
                        local abgr32 <const> = abgr32s[1 + j]

                        local a8 <const> = abgr32 >> 0x18 & 0xff
                        local b8 <const> = abgr32 >> 0x10 & 0xff
                        local g8 <const> = abgr32 >> 0x08 & 0xff
                        local r8 <const> = abgr32 & 0xff

                        local a1 <const> = a8 >= 128 and 1 or 0
                        local r5 <const> = floor(r8 * rgb8to5 + 0.5)
                        local g5 <const> = floor(g8 * rgb8to5 + 0.5)
                        local b5 <const> = floor(b8 * rgb8to5 + 0.5)

                        local rgb555 <const> = a1 << 0xf | r5 << 0xa | g5 << 0x5 | b5

                        local channel <const> = xByte % 2
                        if channel == 1 then
                            c8 = (rgb555 >> 0x08) & 0xff
                        else
                            c8 = rgb555 & 0xff
                        end
                    end

                    trgStrArr[1 + n] = strchar(c8)

                    n = n + 1
                end
            elseif fmtIsIdx8 then
                local bytesPerRow <const> = 4 * ceil((wTarget * 8) / 32)
                local hbpr <const> = hTarget * bytesPerRow

                local n = 0
                while n < hbpr do
                    local x <const> = n % bytesPerRow

                    local idxVerif = 0
                    if x < wTarget then
                        local yFlipped <const> = n // bytesPerRow
                        local y <const> = hn1 - yFlipped
                        local j <const> = y * wTarget + x
                        local idx <const> = idcs[1 + j]
                        idxVerif = idx < lenPalClamped
                            and idx
                            or alphaIdxVerif
                    end

                    trgStrArr[1 + n] = strchar(idxVerif)

                    n = n + 1
                end
            elseif fmtIsIdx4 then
                -- TODO: Any way this can be a more efficient 1D loop?

                local bytesPerRow <const> = 4 * ceil((wTarget * 4) / 32)

                local y = hTarget - 1
                while y >= 0 do
                    ---@type string[]
                    local rowStr <const> = {}

                    local x = 0
                    while x < wTarget do
                        local i0 <const> = y * wTarget + x
                        local idx0 <const> = idcs[1 + i0]
                        local idxVerif0 <const> = idx0 < lenPalClamped
                            and idx0
                            or alphaIdxVerif

                        local i1 <const> = y * wTarget + x + 1
                        local idx1 <const> = (x + 1) < wTarget
                            and idcs[1 + i1]
                            or 0
                        local idxVerif1 <const> = idx1 < lenPalClamped
                            and idx1
                            or alphaIdxVerif

                        local comp = idxVerif0 << 4 | idxVerif1
                        rowStr[#rowStr + 1] = strchar(comp)

                        x = x + 2
                    end

                    while #rowStr < bytesPerRow do
                        rowStr[#rowStr + 1] = zeroi1
                    end

                    local lenRowStr <const> = #rowStr
                    local n = 0
                    while n < lenRowStr do
                        n = n + 1
                        trgStrArr[#trgStrArr + 1] = rowStr[n]
                    end

                    y = y - 1
                end
            elseif fmtIsIdx2 then
                -- TODO: Implement.
            elseif fmtIsIdx1 then
                ---@type integer[]
                local dWords <const> = {}
                local dWordsPerRow <const> = ceil(wTarget / 32)

                local j = 0
                while j < areaTarget do
                    local x <const> = j % wTarget
                    local y <const> = j // wTarget

                    local yFlipped <const> = hTarget - 1 - y
                    local n <const> = yFlipped * wTarget + x

                    local idx = idcs[1 + n]
                    local idxVerif <const> = idx < lenPalClamped
                        and idx
                        or alphaIdxVerif

                    local xDWord <const> = x // 32
                    local xBit <const> = 31 - x % 32
                    local idxDWord <const> = y * dWordsPerRow + xDWord
                    local dWord <const> = dWords[1 + idxDWord] or 0
                    dWords[1 + idxDWord] = dWord | (idxVerif << xBit)

                    j = j + 1
                end

                local lenDWords <const> = #dWords
                local k = 0
                while k < lenDWords do
                    k = k + 1
                    trgStrArr[k] = strpack(">I4", dWords[k])
                end
            end

            local trgStr <const> = tconcat(trgStrArr)
            local dataLen <const> = headerLen + #trgStr + #palStr
            local dataOffset <const> = headerLen + #palStr

            local header = ""
            if writeV4Header then
                -- https://learn.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-bitmapv4header

                header = tconcat({
                    strpack("<I4", dataLen),    -- 006
                    zeroi4,                     -- 010
                    strpack("<I4", dataOffset), -- 014
                    strpack("<I4", dibLen),     -- 018
                    strpack("<i4", wTarget),    -- 022 signed width
                    strpack("<i4", hTarget),    -- 026 signed height
                    planesPacked,               -- 030 bit planes
                    bppPacked,                  -- 032 bits per pixel
                    compressPacked,             -- 034 compression
                    zeroi4,                     -- 038 size of compressed image
                    zeroi4,                     -- 042 x res
                    zeroi4,                     -- 046 y res
                    zeroi4,                     -- 050 colors used
                    zeroi4,                     -- 054 important colors

                    rMaskPacked,                -- 058 red bit mask
                    gMaskPacked,                -- 062 green bit mask
                    bMaskPacked,                -- 066 blue bit mask
                    aMaskPacked,                -- 070 alpha bit mask

                    srgbPacked,
                    ciexyzPacked,
                    zeroi4, -- 114 r gamma
                    zeroi4, -- 118 g gamma
                    zeroi4, -- 122 b gamma
                })
            else
                -- https://learn.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-bitmapinfoheader

                header = tconcat({
                    strpack("<I4", dataLen),    -- 06
                    zeroi4,                     -- 10
                    strpack("<I4", dataOffset), -- 14
                    strpack("<I4", dibLen),     -- 18
                    strpack("<i4", wTarget),    -- 22 signed width
                    strpack("<i4", hTarget),    -- 26 signed height
                    planesPacked,               -- 30 bit planes
                    bppPacked,                  -- 32 bits per pixel
                    compressPacked,             -- 34 compression
                    zeroi4,                     -- 38 size of compressed image
                    zeroi4,                     -- 42 x res
                    zeroi4,                     -- 46 y res
                    zeroi4,                     -- 50 colors used
                    zeroi4,                     -- 54 important colors
                })
            end

            local filePath <const> = lenChosenFrIdcs > 1
                and strfmt("%s_%03d.%s", filePrefix, frIdx - 1, fileExt)
                or exportFilepath
            local binFile <const>, err <const> = ioopen(filePath, "wb")
            if err ~= nil then
                if binFile then binFile:close() end
                app.alert { title = "Error", text = err }
                return
            end
            if binFile == nil then return end

            local fileStr = tconcat({
                "BM",
                header,
                palStr,
                trgStr
            })

            binFile:write(fileStr)
            binFile:close()
        end

        app.alert {
            title = "Success",
            text = "File(s) exported."
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