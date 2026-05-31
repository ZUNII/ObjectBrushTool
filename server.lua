local brushHistory = {}

addEvent("onBrushCreateObjects", true)
addEventHandler("onBrushCreateObjects", resourceRoot, function(objectsData)
    if not client then return end

    local edfRunning = getResourceState(getResourceFromName("edf")) == "running"
    if not edfRunning or not exports.edf then
        outputChatBox("[Brush Tool] Error: Map Editor (EDF) is not running!", client, 255, 0, 0)
        return
    end

    local hostElement = false
    for _, obj in ipairs(getElementsByType("object")) do
        if getElementID(obj) then
            hostElement = obj
            break
        end
    end

    if not hostElement then
        outputChatBox("[Brush Tool] Please place at least ONE object manually in the editor first!", client, 255, 200, 0)
        return
    end

    local playerDim = getElementDimension(client)
    local playerInt = getElementInterior(client)
    local currentStroke = {} 

    for _, data in ipairs(objectsData) do
        -- Now unpacking rotX and rotY sent from the client
        local model, x, y, z, rotX, rotY, rotZ, scale, collisions = unpack(data)
        
        local finalObj = exports.edf:edfCloneElement(hostElement)
        
        if finalObj then
            exports.edf:edfSetElementProperty(finalObj, "model", model)
            
            exports.edf:edfSetElementPosition(finalObj, x, y, z)
            -- Apply full X, Y, and Z rotations to the editor properties
            exports.edf:edfSetElementRotation(finalObj, rotX, rotY, rotZ)
            exports.edf:edfSetElementProperty(finalObj, "scale", tostring(scale))
            exports.edf:edfSetElementProperty(finalObj, "collisions", tostring(collisions))
            
            local newID = "BrushObj_" .. model .. "_" .. math.random(1000, 9999)
            exports.edf:edfSetElementProperty(finalObj, "id", newID)
            setElementID(finalObj, newID)
            
            setElementDimension(finalObj, playerDim)
            setElementInterior(finalObj, playerInt)
            setObjectScale(finalObj, scale)
            setElementCollisionsEnabled(finalObj, collisions)
            
            table.insert(currentStroke, finalObj)
        end
    end

    if not brushHistory[client] then brushHistory[client] = {} end
    table.insert(brushHistory[client], currentStroke)
end)

-- Undo Event Handler
addEvent("onBrushUndo", true)
addEventHandler("onBrushUndo", resourceRoot, function()
    if not client or not brushHistory[client] then return end
    
    local historyCount = #brushHistory[client]
    if historyCount > 0 then
        local lastStroke = table.remove(brushHistory[client], historyCount)
        local removedCount = 0
        
        for _, obj in ipairs(lastStroke) do
            if isElement(obj) then
                destroyElement(obj)
                removedCount = removedCount + 1
            end
        end
        
        if removedCount > 0 then
            outputChatBox("[Brush Tool] Undid last brush stroke (" .. removedCount .. " objects).", client, 255, 200, 0)
        end
    end
end)

-- Clear All Event Handler
addEvent("onBrushClearAll", true)
addEventHandler("onBrushClearAll", resourceRoot, function()
    if not client or not brushHistory[client] then return end
    local removedCount = 0
    for _, stroke in ipairs(brushHistory[client]) do
        for _, obj in ipairs(stroke) do
            if isElement(obj) then
                destroyElement(obj)
                removedCount = removedCount + 1
            end
        end
    end
    brushHistory[client] = {}
    if removedCount > 0 then
        outputChatBox("[Brush Tool] Cleared all session objects.", client, 255, 100, 100)
    end
end)

-- Clear history when a new map is opened to prevent "Undo" bugs across maps
addEvent("onMapOpened", true)
addEventHandler("onMapOpened", root, function()
    brushHistory = {}
end)
