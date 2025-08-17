assert(writefile and getconnections and isfile and delfile, "⚠️ Cần exploit hỗ trợ writefile/getconnections!")

-- ========== CẤU HÌNH ==========
local positionsToCheck = {
    Vector3.new(-746.103271484375, 86.75001525878906, -620.12060546875),
    Vector3.new(-353.05078125, 132.3436279296875, 50.36767578125),
    Vector3.new(-70.82891845703125, 81.39054107666016, 834.0664672851562)
}
local checkDelay = 0.1 -- Giảm delay cho phản ứng nhanh hơn
local fastTeleportDelay = 0.05 -- Delay cho loop teleport nhanh
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

-- ========== TELEPORT NHANH ==========
local function fastTeleport(pos)
    local char = game:GetService("Players").LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char.HumanoidRootPart.CFrame = CFrame.new(pos)
        task.wait(fastTeleportDelay)
    end
end

local function teleportTo(pos)
    local char = game:GetService("Players").LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char.HumanoidRootPart.CFrame = CFrame.new(pos)
        task.wait(0.05) -- Delay ngắn cho teleport thường
        debugLog("Teleported to: " .. tostring(pos))
    else
        debugLog("ERROR: Cannot teleport - no character/HRP")
    end
end

-- ========== KIỂM TRA CRATE NHANH ==========
local function getValidCrate()
    for i, spawn in ipairs(crateRoot:GetChildren()) do
        if spawn:FindFirstChild("Crate") then
            local crate = spawn.Crate
            local prox = crate:FindFirstChild("ProximityAttachment") and crate.ProximityAttachment:FindFirstChild("Interaction")
            if prox then
                return crate.Position, prox, i
            end
        end
    end
    return nil, nil, nil
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
        
        task.wait(0.1) -- Giảm delay check chat
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

-- ========== LOOP TELEPORT TỚI CRATE ==========
local function loopTeleportToCrate(cratePos, prox, duration)
    duration = duration or 2 -- 2 giây mặc định
    local startTime = tick()
    debugLog("Starting loop teleport to crate for " .. duration .. "s")
    
    while (tick() - startTime) < duration do
        fastTeleport(cratePos)
        
        -- Check xem crate có enabled không
        if prox.Enabled then
            debugLog("Crate enabled during loop teleport!")
            return true
        end
        
        -- Check xem crate có bị despawn không
        if hasDespawned() then
            debugLog("Crate despawned during loop teleport")
            return false
        end
    end
    
    debugLog("Loop teleport completed")
    return prox.Enabled
end

-- ========== COLLECT CRATE VỚI LOOP TP ==========
local function collectCrateWithLoop(cratePos, prox)
    debugLog("Collecting crate with loop teleport...")
    
    -- Loop teleport đến khi enabled hoặc timeout
    if not prox.Enabled then
        local enabled = loopTeleportToCrate(cratePos, prox, 3) -- Loop 3 giây
        if not enabled then
            debugLog("Crate not enabled after loop teleport")
            return false
        end
    end
    
    -- Collect crate
    fastTeleport(cratePos)
    task.wait(0.1)
    fireproximityprompt(prox, 1, true)
    
    -- Chờ disable
    local timeout = 0
    repeat 
        task.wait(0.05)
        timeout = timeout + 0.05
    until not prox.Enabled or timeout > 5
    
    if not prox.Enabled then
        debugLog("Crate collected successfully")
        turnInCrate()
        return true
    else
        debugLog("Failed to collect crate - timeout")
        return false
    end
end

-- ========== MAIN LOOP ==========
local function mainLoop()
    debugLog("=== STARTING MAIN LOOP ===")
    
    -- Teleport ban đầu
    teleportTo(positionsToCheck[1])

    -- Kiểm tra crates có sẵn với loop teleport
    debugLog("Checking for existing crates...")
    for i, pos in ipairs(positionsToCheck) do
        debugLog("Checking position " .. i .. ": " .. tostring(pos))
        teleportTo(pos)
        
        local cratePos, prox, crateIndex = getValidCrate()
        if prox then
            debugLog("Found crate at position " .. i .. " | Enabled: " .. tostring(prox.Enabled))
            
            if collectCrateWithLoop(cratePos, prox) then
                waitForChatKeyword("equipment crate+has despawned or been turned in!", 10)
                debugLog("=== MAIN LOOP COMPLETE ===")
                return
            end
        end
    end

    -- Reset và chờ spawn notification
    lastChat = ""
    chatHistory = {}
    debugLog("No crates found. Waiting for spawn notification...")
    
    if not waitForChatKeyword("equipment crate+has been reported!", 60) then
        debugLog("No spawn notification - restarting loop")
        return
    end

    debugLog("Crate spawned! Starting fast search...")
    
    -- Fast search loop
    local maxAttempts = 200 -- Tăng số lần thử
    local attempts = 0
    
    while attempts < maxAttempts do
        attempts = attempts + 1
        
        if attempts % 20 == 0 then -- Log mỗi 20 attempts
            debugLog("Fast search attempt: " .. attempts)
        end
        
        for i, pos in ipairs(positionsToCheck) do
            teleportTo(pos)
            
            local cratePos, prox, crateIndex = getValidCrate()
            if prox then
                debugLog("Found crate at position " .. i .. "! Starting loop collection...")
                
                if collectCrateWithLoop(cratePos, prox) then
                    waitForChatKeyword("equipment crate+has despawned or been turned in!", 10)
                    debugLog("=== MAIN LOOP COMPLETE ===")
                    return
                end
            end
            
            -- Check despawn giữa các vị trí
            if hasDespawned() then
                debugLog("Crate despawned during search")
                return
            end
        end

        task.wait(checkDelay)
    end
    
    debugLog("Max attempts reached - ending loop")
end

-- ========== KHỞI ĐỘNG ==========
debugLog("Script starting with fast reaction settings...")
monitorChat()

while true do
    local success, err = pcall(mainLoop)
    if not success then
        debugLog("ERROR in mainLoop: " .. tostring(err))
        task.wait(2) -- Giảm thời gian chờ khi lỗi
    end
    task.wait(0.5) -- Giảm delay giữa các loop chính
end