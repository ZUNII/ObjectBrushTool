local sx, sy = guiGetScreenSize()
local brushUI = {}
local lastBrushTime = 0
local BRUSH_COOLDOWN = 150 

-- Helper to check if cursor is over our GUI
function isMouseOverGUI(cx, cy)
    if not brushUI.window or not guiGetVisible(brushUI.window) then return false end
    local wx, wy = guiGetPosition(brushUI.window, false)
    local ww, wh = guiGetSize(brushUI.window, false)
    return (cx >= wx and cx <= wx + ww and cy >= wy and cy <= wy + wh)
end

-- Create GUI
function createBrushGUI()
    brushUI.window = guiCreateWindow(sx - 320, sy / 2 - 240, 300, 480, "Object Brush Tool", false)
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

    -- Buttons
    brushUI.undoBtn = guiCreateButton(10, 310, 280, 30, "Undo Last Stroke (Z)", false, brushUI.window)
    brushUI.clearBtn = guiCreateButton(10, 350, 280, 30, "Clear All Brushed Objects", false, brushUI.window)

    -- Info
    guiCreateLabel(10, 395, 280, 60, "Press 'B' to close menu & stop brushing.\nPress 'Z' while brushing to Undo.", false, brushUI.window)

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

-- Suppress Map Editor click interaction when brush window is active
addEventHandler("onClientClick", root, function(button, state, absoluteX, absoluteY)
    if brushUI.window and guiGetVisible(brushUI.window) then
        if not isMouseOverGUI(absoluteX, absoluteY) then
            if button == "left" then
                cancelEvent()
            end
        end
    end
end)

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

-- Standard Raycast with complex mesh test
local function standardRaycast(startX, startY, startZ, endX, endY, endZ)
    return processLineOfSight(
        startX, startY, startZ,
        endX, endY, endZ,
        true, false, false, true, false, false, false, false, nil, false, false, true
    )
end

-- Vector Rotation Basis
local function getObjectAxes(rx, ry, rz)
    local radX, radY, radZ = math.rad(rx), math.rad(ry), math.rad(rz)
    local cx, sx = math.cos(radX), math.sin(radX)
    local cy, sy = math.cos(radY), math.sin(radY)
    local cz, sz = math.cos(radZ), math.sin(radZ)

    local right = {x = cz * cy, y = sz * cy, z = -sy}
    local fwd   = {x = cz * sy * sx - sz * cx, y = sz * sy * sx + cz * cx, z = cy * sx}
    local up    = {x = cz * sy * cx + sz * sx, y = sz * sy * cx - cz * sx, z = cy * cx}
    return right, fwd, up
end

-- Samples uneven scaled geometries via local transformation
local function testScaledObjectSurface(startX, startY, startZ, endX, endY, endZ, obj)
    local ox, oy, oz = getElementPosition(obj)
    local rx, ry, rz = getElementRotation(obj)
    local scale = getObjectScale(obj) or 1.0
    if scale <= 0.001 then return false end

    local right, fwd, up = getObjectAxes(rx, ry, rz)

    local function toLocal(wx, wy, wz)
        local dx = wx - ox
        local dy = wy - oy
        local dz = wz - oz
        return (dx * right.x + dy * right.y + dz * right.z) / scale,
               (dx * fwd.x   + dy * fwd.y   + dz * fwd.z)   / scale,
               (dx * up.x    + dy * up.y    + dz * up.z)    / scale
    end

    local function toWorld(lx, ly, lz)
        lx, ly, lz = lx * scale, ly * scale, lz * scale
        local wx = ox + lx * right.x + ly * fwd.x + lz * up.x
        local wy = oy + lx * right.y + ly * fwd.y + lz * up.y
        local wz = oz + lx * right.z + ly * fwd.z + lz * up.z
        return wx, wy, wz
    end

    local lStartX, lStartY, lStartZ = toLocal(startX, startY, startZ)
    local lEndX, lEndY, lEndZ = toLocal(endX, endY, endZ)

    local dummyStartX = ox + lStartX * right.x + lStartY * fwd.x + lStartZ * up.x
    local dummyStartY = oy + lStartX * right.y + lStartY * fwd.y + lStartZ * up.y
    local dummyStartZ = oz + lStartX * right.z + lStartY * fwd.z + lStartZ * up.z

    local dummyEndX = ox + lEndX * right.x + lEndY * fwd.x + lEndZ * up.x
    local dummyEndY = oy + lEndX * right.y + lEndY * fwd.y + lEndZ * up.y
    local dummyEndZ = oz + lEndX * right.z + lEndY * fwd.z + lEndZ * up.z

    local hit, hitX, hitY, hitZ, hitElement, nX, nY, nZ = standardRaycast(dummyStartX, dummyStartY, dummyStartZ, dummyEndX, dummyEndY, dummyEndZ)

    if hit and (hitElement == obj or not hitElement) then
        local dx = hitX - ox
        local dy = hitY - oy
        local dz = hitZ - oz
        local lHitX = dx * right.x + dy * right.y + dz * right.z
        local lHitY = dx * fwd.x   + dy * fwd.y   + dz * fwd.z
        local lHitZ = dx * up.x    + dy * up.y    + dz * up.z

        local finalX, finalY, finalZ = toWorld(lHitX, lHitY, lHitZ)
        return true, finalX, finalY, finalZ, obj, nX, nY, nZ
    end

    return false
end

-- Universal Scanner (Prioritizes nearby scaled geometries)
local function scanAccurateSurface(startX, startY, startZ, endX, endY, endZ)
    local nearbyObjects = getElementsByType("object", root, true)
    local bestDist = math.huge
    local bestResult = nil

    for _, obj in ipairs(nearbyObjects) do
        local scale = getObjectScale(obj) or 1.0
        if math.abs(scale - 1.0) > 0.01 then
            local hit, hX, hY, hZ, elem, nX, nY, nZ = testScaledObjectSurface(startX, startY, startZ, endX, endY, endZ, obj)
            if hit then
                local dist = (hX - startX)^2 + (hY - startY)^2 + (hZ - startZ)^2
                if dist < bestDist then
                    bestDist = dist
                    bestResult = {hit = true, x = hX, y = hY, z = hZ, elem = elem, nx = nX, ny = nY, nz = nZ}
                end
            end
        end
    end

    if bestResult then
        return true, bestResult.x, bestResult.y, bestResult.z, bestResult.elem, bestResult.nx, bestResult.ny, bestResult.nz
    end

    return standardRaycast(startX, startY, startZ, endX, endY, endZ)
end

-- Tangent Vector Basis for surface projection
local function getSurfaceBasis(nX, nY, nZ)
    local ux, uy, uz = 0, 0, 1
    if math.abs(nZ) > 0.99 then
        ux, uy, uz = 1, 0, 0
    end
    
    local rx = uy * nZ - uz * nY
    local ry = uz * nX - ux * nZ
    local rz = ux * nY - uy * nX
    local rLen = math.sqrt(rx*rx + ry*ry + rz*rz)
    if rLen > 0 then rx, ry, rz = rx/rLen, ry/rLen, rz/rLen else rx, ry, rz = 1, 0, 0 end

    local fx = nY * rz - nZ * ry
    local fy = nZ * rx - nX * rz
    local fz = nX * ry - nY * rx
    local fLen = math.sqrt(fx*fx + fy*fy + fz*fz)
    if fLen > 0 then fx, fy, fz = fx/fLen, fy/fLen, fz/fLen else fx, fy, fz = 0, 1, 0 end

    return rx, ry, rz, fx, fy, fz
end

-- Render loop & Paint trigger
addEventHandler("onClientRender", root, function()
    if not guiGetVisible(brushUI.window) then return end

    local cx, cy = getCursorPosition()
    if not cx then return end

    local absX, absY = cx * sx, cy * sy
    if isMouseOverGUI(absX, absY) then return end

    local camX, camY, camZ = getCameraMatrix()
    local cursorX, cursorY, cursorZ = getWorldFromScreenPosition(absX, absY, 1500)
    
    local hit, hitX, hitY, hitZ, hitElement, nX, nY, nZ = scanAccurateSurface(camX, camY, camZ, cursorX, cursorY, cursorZ)

    if hit and nX and nY and nZ then
        local radius = tonumber(guiGetText(brushUI.radiusLabel)) or 10
        local zOffset = tonumber(guiGetText(brushUI.offsetEdit)) or 0.0
        
        local rx, ry, rz, fx, fy, fz = getSurfaceBasis(nX, nY, nZ)
        local segments = 36

        for i = 0, segments - 1 do
            local angle1 = (i / segments) * math.pi * 2
            local angle2 = ((i + 1) / segments) * math.pi * 2

            local px1 = hitX + (math.cos(angle1) * radius) * rx + (math.sin(angle1) * radius) * fx + nX * (0.05 + zOffset)
            local py1 = hitY + (math.cos(angle1) * radius) * ry + (math.sin(angle1) * radius) * fy + nY * (0.05 + zOffset)
            local pz1 = hitZ + (math.cos(angle1) * radius) * rz + (math.sin(angle1) * radius) * fz + nZ * (0.05 + zOffset)

            local px2 = hitX + (math.cos(angle2) * radius) * rx + (math.sin(angle2) * radius) * fx + nX * (0.05 + zOffset)
            local py2 = hitY + (math.cos(angle2) * radius) * ry + (math.sin(angle2) * radius) * fy + nY * (0.05 + zOffset)
            local pz2 = hitZ + (math.cos(angle2) * radius) * rz + (math.sin(angle2) * radius) * fz + nZ * (0.05 + zOffset)

            dxDrawLine3D(px1, py1, pz1, px2, py2, pz2, tocolor(0, 255, 120, 230), 2)
        end

        if getKeyState("mouse1") and getTickCount() - lastBrushTime > BRUSH_COOLDOWN then
            lastBrushTime = getTickCount()
            brushObjects(hitX, hitY, hitZ, nX, nY, nZ, radius, zOffset)
        end
    end
end)

function brushObjects(cX, cY, cZ, nX, nY, nZ, radius, zOffset)
    local objID = tonumber(guiGetText(brushUI.objID))
    local density = tonumber(guiGetText(brushUI.densityEdit)) or 1
    local baseScale = tonumber(guiGetText(brushUI.scaleEdit)) or 1.0
    local collisions = guiCheckBoxGetSelected(brushUI.collisionCheck)
    local randRot = guiCheckBoxGetSelected(brushUI.randomRotCheck)
    local randScale = guiCheckBoxGetSelected(brushUI.randomScaleCheck)

    if not objID then return end

    local rx, ry, rz, fx, fy, fz = getSurfaceBasis(nX, nY, nZ)
    local objectsToSpawn = {}

    for i = 1, density do
        local angle = math.random() * math.pi * 2
        local dist = math.sqrt(math.random()) * radius
        
        local testX = cX + (math.cos(angle) * dist) * rx + (math.sin(angle) * dist) * fx
        local testY = cY + (math.cos(angle) * dist) * ry + (math.sin(angle) * dist) * fy
        local testZ = cZ + (math.cos(angle) * dist) * rz + (math.sin(angle) * dist) * fz

        local rayStartDist = math.max(radius, 40)
        local sX = testX + nX * rayStartDist
        local sY = testY + nY * rayStartDist
        local sZ = testZ + nZ * rayStartDist

        local eX = testX - nX * rayStartDist
        local eY = testY - nY * rayStartDist
        local eZ = testZ - nZ * rayStartDist

        local hit, hitX, hitY, hitZ = scanAccurateSurface(sX, sY, sZ, eX, eY, eZ)

        local finalX, finalY, finalZ
        if hit then
            finalX, finalY, finalZ = hitX, hitY, hitZ
        else
            finalX, finalY, finalZ = testX, testY, testZ
        end

        -- Add vertical Z-Offset
        finalZ = finalZ + zOffset

        -- Keep objects upright (rotX = 0, rotY = 0)
        local rotX, rotY = 0, 0
        local rotZ = randRot and math.random(0, 360) or 0
        
        local finalScale = baseScale
        if randScale then
            local variation = (math.random() * 0.5) - 0.25
            finalScale = math.max(0.1, baseScale + variation)
        end

        table.insert(objectsToSpawn, {objID, finalX, finalY, finalZ, rotX, rotY, rotZ, finalScale, collisions})
    end

    playSoundFrontEnd(1) 
    triggerServerEvent("onBrushCreateObjects", resourceRoot, objectsToSpawn)
end
