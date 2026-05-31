local sx, sy = guiGetScreenSize()
local brushUI = {}
local lastBrushTime = 0
local BRUSH_COOLDOWN = 150 

-- Create GUI
function createBrushGUI()
    brushUI.window = guiCreateWindow(sx - 320, sy / 2 - 255, 300, 510, "Object Brush Tool", false)
    guiWindowSetSizable(brushUI.window, false)
    guiSetVisible(brushUI.window, false)

    -- Object ID
    guiCreateLabel(10, 30, 100, 20, "Object ID:", false, brushUI.window)
    brushUI.objID = guiCreateEdit(110, 25, 180, 25, "1337", false, brushUI.window)

    -- Radius
    guiCreateLabel(10, 70, 100, 20, "Radius:", false, brushUI.window)
    brushUI.radiusScroll = guiCreateScrollBar(110, 70, 140, 20, true, false, brushUI.window)
    guiScrollBarSetScrollPosition(brushUI.radiusScroll, 20)
    brushUI.radiusLabel = guiCreateLabel(260, 70, 30, 20, "10", false, brushUI.window)

    -- Density
    guiCreateLabel(10, 110, 100, 20, "Density:", false, brushUI.window)
    brushUI.densityScroll = guiCreateScrollBar(110, 110, 140, 20, true, false, brushUI.window)
    guiScrollBarSetScrollPosition(brushUI.densityScroll, 10)
    brushUI.densityEdit = guiCreateEdit(260, 105, 30, 30, "5", false, brushUI.window)

    -- Size (Scale)
    guiCreateLabel(10, 150, 100, 20, "Base Size:", false, brushUI.window)
    brushUI.scaleEdit = guiCreateEdit(110, 145, 180, 25, "1.0", false, brushUI.window)

    -- Z-Offset
    guiCreateLabel(10, 190, 100, 20, "Z-Offset (Height):", false, brushUI.window)
    brushUI.offsetEdit = guiCreateEdit(110, 185, 180, 25, "0.0", false, brushUI.window)

    -- Checkboxes
    brushUI.collisionCheck = guiCreateCheckBox(10, 225, 280, 20, "Enable Collisions", true, false, brushUI.window)
    brushUI.randomRotCheck = guiCreateCheckBox(10, 250, 280, 20, "Randomize Rotation (Natural look)", true, false, brushUI.window)
    brushUI.randomScaleCheck = guiCreateCheckBox(10, 275, 280, 20, "Randomize Size (+/- 25%)", true, false, brushUI.window)
    
    -- Align to Surface
    brushUI.alignCheck = guiCreateCheckBox(10, 300, 280, 20, "Align to Surface Angle (Slopes)", false, false, brushUI.window)

    -- Buttons
    brushUI.undoBtn = guiCreateButton(10, 335, 280, 30, "Undo Last Stroke (Z)", false, brushUI.window)
    brushUI.clearBtn = guiCreateButton(10, 375, 280, 30, "Clear All Brushed Objects", false, brushUI.window)

    -- Info
    guiCreateLabel(10, 415, 280, 60, "Press 'B' to close menu & stop brushing.\nPress 'Z' while brushing to Undo.", false, brushUI.window)

    -- Update Labels dynamically
    addEventHandler("onClientGUIScroll", brushUI.radiusScroll, function()
        local val = math.floor(guiScrollBarGetScrollPosition(source) / 2) + 1
        guiSetText(brushUI.radiusLabel, tostring(val))
    end, false)

    addEventHandler("onClientGUIScroll", brushUI.densityScroll, function()
        local val = math.floor(guiScrollBarGetScrollPosition(source) / 5) + 1
        guiSetText(brushUI.densityEdit, tostring(val))
    end, false)

    -- Button Click Handlers
    addEventHandler("onClientGUIClick", brushUI.undoBtn, function()
        triggerServerEvent("onBrushUndo", resourceRoot)
    end, false)

    addEventHandler("onClientGUIClick", brushUI.clearBtn, function()
        triggerServerEvent("onBrushClearAll", resourceRoot)
    end, false)
end
addEventHandler("onClientResourceStart", resourceRoot, createBrushGUI)

-- Toggle Menu
bindKey("b", "down", function()
    local state = not guiGetVisible(brushUI.window)
    guiSetVisible(brushUI.window, state)
    showCursor(state)
end)

-- Undo Hotkey
bindKey("z", "down", function()
    if guiGetVisible(brushUI.window) then
        triggerServerEvent("onBrushUndo", resourceRoot)
    end
end)

-- Helper to check if cursor is over our GUI
function isMouseOverGUI(cx, cy)
    if not guiGetVisible(brushUI.window) then return false end
    local wx, wy = guiGetPosition(brushUI.window, false)
    local ww, wh = guiGetSize(brushUI.window, false)
    return (cx >= wx and cx <= wx + ww and cy >= wy and cy <= wy + wh)
end

-- Math & Visuals
addEventHandler("onClientRender", root, function()
    if not guiGetVisible(brushUI.window) then return end

    local cx, cy = getCursorPosition()
    if not cx then return end

    local absX, absY = cx * sx, cy * sy
    if isMouseOverGUI(absX, absY) then return end

    local camX, camY, camZ = getCameraMatrix()
    local cursorX, cursorY, cursorZ = getWorldFromScreenPosition(absX, absY, 1000)
    
    -- Grab the normal vectors (nX, nY, nZ) directly from the camera raycast
    local hit, hitX, hitY, hitZ, hitElement, nX, nY, nZ = processLineOfSight(camX, camY, camZ, cursorX, cursorY, cursorZ, true, false, false, true, false, true)

    if hit then
        local radius = tonumber(guiGetText(brushUI.radiusLabel)) or 10
        local zOffset = tonumber(guiGetText(brushUI.offsetEdit)) or 0.0
        local alignSurface = guiCheckBoxGetSelected(brushUI.alignCheck)
        
        local segments = 36
        
        if alignSurface and nX and nY and nZ then
            -- TILTED CIRCLE LOGIC: Use Cross Products to align the circle to the surface normal
            local ux, uy, uz = 0, 0, 1 -- World Up Vector
            
            -- Right Vector
            local rx = uy * nZ - uz * nY
            local ry = uz * nX - ux * nZ
            local rz = ux * nY - uy * nX
            
            local rLen = math.sqrt(rx*rx + ry*ry + rz*rz)
            if rLen == 0 then
                rx, ry, rz = 1, 0, 0
            else
                rx, ry, rz = rx/rLen, ry/rLen, rz/rLen
            end
            
            -- Forward Vector
            local fx = nY * rz - nZ * ry
            local fy = nZ * rx - nX * rz
            local fz = nX * ry - nY * rx
            
            local fLen = math.sqrt(fx*fx + fy*fy + fz*fz)
            if fLen > 0 then
                fx, fy, fz = fx/fLen, fy/fLen, fz/fLen
            end

            for i = 0, segments - 1 do
                local angle1 = (i / segments) * math.pi * 2
                local angle2 = ((i + 1) / segments) * math.pi * 2

                local c1 = math.cos(angle1) * radius
                local s1 = math.sin(angle1) * radius
                local px1 = hitX + c1 * rx + s1 * fx
                local py1 = hitY + c1 * ry + s1 * fy
                local pz1 = hitZ + c1 * rz + s1 * fz

                local c2 = math.cos(angle2) * radius
                local s2 = math.sin(angle2) * radius
                local px2 = hitX + c2 * rx + s2 * fx
                local py2 = hitY + c2 * ry + s2 * fy
                local pz2 = hitZ + c2 * rz + s2 * fz

                dxDrawLine3D(px1, py1, pz1 + 0.1 + zOffset, px2, py2, pz2 + 0.1 + zOffset, tocolor(255, 0, 0, 200), 2)
            end
            
        else
            -- FLAT CIRCLE LOGIC: Conforms to the bumps on the terrain
            for i = 0, segments - 1 do
                local angle1 = (i / segments) * math.pi * 2
                local angle2 = ((i + 1) / segments) * math.pi * 2

                local px1 = hitX + math.cos(angle1) * radius
                local py1 = hitY + math.sin(angle1) * radius
                local px2 = hitX + math.cos(angle2) * radius
                local py2 = hitY + math.sin(angle2) * radius
                
                local g1 = getGroundPosition(px1, py1, hitZ + 50) or hitZ
                local g2 = getGroundPosition(px2, py2, hitZ + 50) or hitZ

                dxDrawLine3D(px1, py1, g1 + 0.1 + zOffset, px2, py2, g2 + 0.1 + zOffset, tocolor(255, 0, 0, 200), 2)
            end
        end

        if getKeyState("mouse1") and getTickCount() - lastBrushTime > BRUSH_COOLDOWN then
            lastBrushTime = getTickCount()
            brushObjects(hitX, hitY, hitZ, radius, zOffset)
        end
    end
end)

function brushObjects(cX, cY, cZ, radius, zOffset)
    local objID = tonumber(guiGetText(brushUI.objID))
    local density = tonumber(guiGetText(brushUI.densityEdit)) or 1
    local baseScale = tonumber(guiGetText(brushUI.scaleEdit)) or 1.0
    local collisions = guiCheckBoxGetSelected(brushUI.collisionCheck)
    
    local randRot = guiCheckBoxGetSelected(brushUI.randomRotCheck)
    local randScale = guiCheckBoxGetSelected(brushUI.randomScaleCheck)
    local alignSurface = guiCheckBoxGetSelected(brushUI.alignCheck)

    if not objID then return end

    local objectsToSpawn = {}
    for i = 1, density do
        local angle = math.random() * math.pi * 2
        local dist = math.random() * radius
        local pX = cX + math.cos(angle) * dist
        local pY = cY + math.sin(angle) * dist
        
        local hit, hX, hY, hZ, hitElement, nX, nY, nZ = processLineOfSight(pX, pY, cZ + 100, pX, pY, cZ - 100, true, false, false, true, false, true)
        
        local pZ = cZ
        local rotX, rotY = 0, 0
        
        if hit then
            pZ = hZ + zOffset
            
            if alignSurface then
                rotX = -math.deg(math.atan2(nY, nZ))
                rotY = math.deg(math.atan2(nX, nZ))
            end
        else
            pZ = (getGroundPosition(pX, pY, cZ + 50) or cZ) + zOffset
        end
        
        local rotZ = 0
        if randRot then
            rotZ = math.random(0, 360)
        end
        
        local finalScale = baseScale
        if randScale then
            local variation = (math.random() * 0.5) - 0.25
            finalScale = baseScale + variation
            if finalScale < 0.1 then finalScale = 0.1 end 
        end

        table.insert(objectsToSpawn, {objID, pX, pY, pZ, rotX, rotY, rotZ, finalScale, collisions})
    end

    playSoundFrontEnd(1) 
    triggerServerEvent("onBrushCreateObjects", resourceRoot, objectsToSpawn)
end
