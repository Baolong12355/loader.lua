assert(writefile and getconnections and isfile and delfile, "⚠️ Cần exploit hỗ trợ writefile/getconnections!")

-- ========== CẤU HÌNH ==========
local positionsToCheck = {
    Vector3.new(-746.103271484375, 86.75001525878906, -620.12060546875),
    Vector3.new(-353.05078125, 132.3436279296875, 50.36767578125),
    Vector3.new(-70.82891845703125, 81.39054107666016, 834.0664672851562)
}
local checkDelay = 0.25
local crateRoot = workspace.ItemSpawns.LabCrate
local logFile = "ChatDump.txt"
local debugFile = "DebugLog.txt"
local lastChat = ""
local chatHistory = {}

-- ========== TẠO FILES ==========
if isfile(logFile) then delfile(logFile) end
if isfile(debugFile) then delfile(debugFile) end
writefile(logFile, "")
writefile(debugFile, "")

local function debugLog(text)
    local timestamp = os.date("[%H:%M:%S]")
    appendfile(debugFile, timestamp .. " " .. text .. "\n")
end

local function logToFile(text)
    if text and text ~= lastChat then
        appendfile(logFile, text .. "\n")
        lastChat = text
        table.insert(chatHistory, text:lower())
        debugLog("[CHAT] " .. text)
    end
end

-- ========== THEO DÕI CHAT ==========
local function monitorChat()
    debugLog("Starting chat monitor...")
    
    local Players = game:GetService("Players")
    
    -- Hook chat system
    local function hookChatEvent()
        local success, err = pcall(function()
            local chatService = game:GetService("TextChatService")
            if chatService then
                chatService.MessageReceived:Connect(function(textChatMessage)
                    if textChatMessage.Text then
                        logToFile("[System] " .. textChatMessage.Text)
                    end
                end)
                debugLog("Hooked into TextChatService")
            end
        end)
        
        if not success then
            debugLog("Chat hook failed: " .. tostring(err))
        end
    end
    
    -- Fallback: GUI scanning
    local function scanGUI(container)
        local function onDescendantAdded(desc)
            if desc:IsA("TextLabel") or desc:IsA("TextBox") then
                if desc.Text and #desc.Text > 0 and desc.Text ~= lastChat then
                    logToFile("[GUI] " .. desc.Text)
                end
                
                desc:GetPropertyChangedSignal("Text"):Connect(function()
                    if desc.Text and #desc.Text > 0 and desc.Text ~= lastChat then
                        logToFile("[GUI Update] " .. desc.Text)
                    end
                end)
            end
        end
        
        container.DescendantAdded:Connect(onDescendantAdded)
        for _, desc in pairs(container:GetDescendants()) do
            onDescendantAdded(desc)
        end
    end

    hookChatEvent()
    
    local guiTargets = {
        Players.LocalPlayer:WaitForChild("PlayerGui"),
        game:GetService("CoreGui")
    }

    for _, gui in ipairs(guiTargets) do
        scanGUI(gui)
        gui.ChildAdded:Connect(scanGUI)
    end
    
    debugLog("Chat monitoring setup complete")
end

-- ========== TELEPORT ==========
local function teleportTo(pos)
    local char = game:GetService("Players").LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char.HumanoidRootPart.CFrame = CFrame.new(pos)
        task.wait(0.1)
        debugLog("Teleported to: " .. tostring(pos))
    else
        debugLog("ERROR: Cannot teleport - no character/HRP")
    end
end

-- ========== KIỂM TRA CRATE ==========
local function getValidCrate()
    for i, spawn in ipairs(crateRoot:GetChildren()) do
        if spawn:FindFirstChild("Crate") then
            local crate = spawn.Crate
            local prox = crate:FindFirstChild("ProximityAttachment") and crate.ProximityAttachment:FindFirstChild("Interaction")
            if prox then
                debugLog("Found crate at " .. tostring(crate.Position) .. " | Enabled: " .. tostring(prox.Enabled))
                return crate.Position, prox
            end
        end
    end
    debugLog("No valid crates found")
    return nil, nil
end

-- ========== GỬI TURN IN ==========
local function turnInCrate()
    local args = { [1] = "TurnInCrate" }
    local success, result = pcall(function()
        return game:GetService("ReplicatedStorage")
            :WaitForChild("ReplicatedModules"):WaitForChild("KnitPackage")
            :WaitForChild("Knit"):WaitForChild("Services")
            :WaitForChild("DialogueService"):WaitForChild("RF")
            :WaitForChild("CheckRequirement"):InvokeServer(unpack(args))
    end)
    debugLog("TurnIn result - Success: " .. tostring(success) .. " | Result: " .. tostring(result))
end

-- ========== CHAT UTILITIES ==========
local function waitForChatKeyword(keyword, timeout)
    local startTime = tick()
    timeout = timeout or 30
    debugLog("Waiting for keyword: '" .. keyword .. "' (timeout: " .. timeout .. "s)")
    
    while true do
        if lastChat:lower():find(keyword:lower()) then 
            debugLog("Found keyword in latest chat: " .. keyword)
            return true 
        end
        
        for _, chat in pairs(chatHistory) do
            if chat:find(keyword:lower()) then
                debugLog("Found keyword in history: " .. keyword)
                return true
            end
        end
        
        if tick() - startTime > timeout then
            debugLog("TIMEOUT waiting for: " .. keyword)
            return false
        end
        
        task.wait(0.25)
    end
end

local function hasDespawned()
    local despawnKeyword = "equipment crate+has despawned or been turned in!"
    local result = lastChat:lower():find(despawnKeyword:lower()) or 
                   (#chatHistory > 0 and chatHistory[#chatHistory]:find(despawnKeyword:lower()))
    if result then
        debugLog("Crate has despawned!")
    end
    return result
end

-- ========== MAIN LOOP ==========
local function mainLoop()
    debugLog("=== STARTING MAIN LOOP ===")
    
    -- Teleport ban đầu
    teleportTo(positionsToCheck[1])

    -- Kiểm tra crates có sẵn
    debugLog("Checking for existing enabled crates...")
    for i, pos in ipairs(positionsToCheck) do
        debugLog("Checking position " .. i .. ": " .. tostring(pos))
        teleportTo(pos)
        task.wait(checkDelay * 2)

        local cratePos, prox = getValidCrate()
        if prox and prox.Enabled then
            debugLog("Found enabled crate! Collecting...")
            teleportTo(cratePos)
            task.wait(0.3)
            fireproximityprompt(prox, 1, true)
            repeat task.wait(0.1) until not prox.Enabled
            debugLog("Crate collected, turning in...")
            turnInCrate()
            waitForChatKeyword("equipment crate+has despawned or been turned in!", 10)
            debugLog("=== MAIN LOOP COMPLETE ===")
            return
        end
    end

    -- Reset và chờ spawn notification
    lastChat = ""
    chatHistory = {}
    debugLog("No enabled crates found. Waiting for spawn notification...")
    
    if not waitForChatKeyword("equipment crate+has been reported!", 60) then
        debugLog("No spawn notification - restarting loop")
        return
    end

    debugLog("Crate spawned! Starting search loop...")
    
    -- Main search loop
    local maxAttempts = 100
    local attempts = 0
    local lastFoundPosition = nil
    
    while attempts < maxAttempts do
        attempts = attempts + 1
        debugLog("=== ATTEMPT " .. attempts .. " ===")
        
        local crateFound = false
        local enabledCrateFound = false

        for i, pos in ipairs(positionsToCheck) do
            debugLog("Checking position " .. i .. ": " .. tostring(pos))
            teleportTo(pos)
            task.wait(checkDelay * 2)

            local cratePos, prox = getValidCrate()
            if prox then
                crateFound = true
                lastFoundPosition = i
                
                if prox.Enabled then
                    debugLog("ENABLED CRATE FOUND! Collecting...")
                    enabledCrateFound = true
                    teleportTo(cratePos)
                    task.wait(0.3)
                    fireproximityprompt(prox, 1, true)
                    repeat task.wait(0.1) until not prox.Enabled
                    debugLog("Crate collected, turning in...")
                    turnInCrate()
                    waitForChatKeyword("equipment crate+has despawned or been turned in!", 10)
                    debugLog("=== MAIN LOOP COMPLETE ===")
                    return
                else
                    debugLog("Crate found but not enabled yet at position " .. i)
                end
            end
        end

        -- Nếu tìm thấy crate nhưng chưa enabled, camp ở đó
        if crateFound and not enabledCrateFound and lastFoundPosition then
            debugLog("Camping at position " .. lastFoundPosition .. " where crate exists...")
            for campAttempt = 1, 20 do -- Camp 20 lần
                teleportTo(positionsToCheck[lastFoundPosition])
                task.wait(checkDelay)
                
                local cratePos, prox = getValidCrate()
                if prox and prox.Enabled then
                    debugLog("Crate enabled while camping! Collecting...")
                    teleportTo(cratePos)
                    task.wait(0.3)
                    fireproximityprompt(prox, 1, true)
                    repeat task.wait(0.1) until not prox.Enabled
                    debugLog("Crate collected, turning in...")
                    turnInCrate()
                    waitForChatKeyword("equipment crate+has despawned or been turned in!", 10)
                    debugLog("=== MAIN LOOP COMPLETE ===")
                    return
                end
                
                if hasDespawned() then
                    debugLog("Crate despawned while camping")
                    return
                end
            end
        end

        -- Check nếu crate đã despawn
        if not crateFound and hasDespawned() then
            debugLog("No crate found and despawn detected - ending loop")
            return
        end
        
        if not crateFound then
            debugLog("No crates found in any position")
        end

        task.wait(checkDelay)
    end
    
    debugLog("Max attempts reached - ending loop")
end

-- ========== KHỞI ĐỘNG ==========
debugLog("Script starting...")
monitorChat()

while true do
    local success, err = pcall(mainLoop)
    if not success then
        debugLog("ERROR in mainLoop: " .. tostring(err))
        task.wait(5) -- Chờ 5s trước khi thử lại
    end
    task.wait(1)
end