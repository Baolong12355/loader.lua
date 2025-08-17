assert(writefile and getconnections and isfile and delfile, "⚠️ Cần exploit hỗ trợ writefile/getconnections!")

-- ========== CẤU HÌNH ==========
local positionsToCheck = {
    Vector3.new(-746.103271484375, 86.75001525878906, -620.12060546875),
    Vector3.new(-353.05078125, 132.3436279296875, 50.36767578125),
    Vector3.new(-70.82891845703125, 81.39054107666016, 834.0664672851562)
}
local checkDelay = 0.05
local crateRoot = workspace.ItemSpawns.LabCrate
local lastChat = ""
local chatHistory = {}
local proximityMethod = 2 -- 1 = Distance, 2 = Invisible Part
local invisiblePart = nil

-- ========== THEO DÕI CHAT ==========
local function monitorChat()
    local Players = game:GetService("Players")
    
    local function hookChatEvent()
        pcall(function()
            local chatService = game:GetService("TextChatService")
            if chatService then
                chatService.MessageReceived:Connect(function(textChatMessage)
                    if textChatMessage.Text then
                        lastChat = textChatMessage.Text
                        table.insert(chatHistory, textChatMessage.Text:lower())
                    end
                end)
            end
        end)
    end
    
    local function scanGUI(container)
        local function onDescendantAdded(desc)
            if desc:IsA("TextLabel") or desc:IsA("TextBox") then
                if desc.Text and #desc.Text > 0 and desc.Text ~= lastChat then
                    lastChat = desc.Text
                    table.insert(chatHistory, desc.Text:lower())
                end
                
                desc:GetPropertyChangedSignal("Text"):Connect(function()
                    if desc.Text and #desc.Text > 0 and desc.Text ~= lastChat then
                        lastChat = desc.Text
                        table.insert(chatHistory, desc.Text:lower())
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
end

-- ========== TELEPORT ==========
local function aggressiveTeleport(pos)
    local char = game:GetService("Players").LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char.HumanoidRootPart.CFrame = CFrame.new(pos)
    end
end

local function teleportTo(pos)
    local char = game:GetService("Players").LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char.HumanoidRootPart.CFrame = CFrame.new(pos)
    end
end

-- ========== METHOD 1: DISTANCE & RAYCAST ==========
local function modifyProximityDistance(prox)
    pcall(function()
        prox.MaxActivationDistance = 50
        prox.RequiresLineOfSight = false
    end)
    
    pcall(function()
        if prox:FindFirstChild("ProximityPrompt") then
            prox.ProximityPrompt.MaxActivationDistance = 50
            prox.ProximityPrompt.RequiresLineOfSight = false
        end
    end)
end

local function lookAtCrate(cratePos)
    pcall(function()
        local camera = workspace.CurrentCamera
        camera.CFrame = CFrame.lookAt(camera.CFrame.Position, cratePos)
    end)
end

-- ========== METHOD 2: INVISIBLE PART ==========
local function createInvisiblePart()
    if invisiblePart then
        pcall(function() invisiblePart:Destroy() end)
    end
    
    invisiblePart = Instance.new("Part")
    invisiblePart.Name = "ProximityCarrier"
    invisiblePart.Size = Vector3.new(0.001, 0.001, 0.001)
    invisiblePart.Material = Enum.Material.ForceField
    invisiblePart.Transparency = 1
    invisiblePart.CanCollide = false
    invisiblePart.Anchored = true
    invisiblePart.Parent = workspace
    
    return invisiblePart
end

local function movePartToCamera()
    if invisiblePart and invisiblePart.Parent then
        pcall(function()
            local camera = workspace.CurrentCamera
            invisiblePart.CFrame = camera.CFrame * CFrame.new(0, 0, -2)
        end)
    end
end

local function hijackProximity(originalProx)
    local carrier = invisiblePart or createInvisiblePart()
    
    -- Cắt trực tiếp proximity từ crate gốc
    originalProx.Parent = carrier
    
    pcall(function()
        originalProx.MaxActivationDistance = 50
        originalProx.RequiresLineOfSight = false
        if originalProx:FindFirstChild("ProximityPrompt") then
            originalProx.ProximityPrompt.MaxActivationDistance = 50
            originalProx.ProximityPrompt.RequiresLineOfSight = false
        end
    end)
    
    game:GetService("RunService").Heartbeat:Connect(movePartToCamera)
    
    return originalProx
end

-- ========== KIỂM TRA CRATE ==========
local function getValidCrate()
    for i, spawn in ipairs(crateRoot:GetChildren()) do
        if spawn:FindFirstChild("Crate") then
            local crate = spawn.Crate
            local prox = crate:FindFirstChild("ProximityAttachment") and crate.ProximityAttachment:FindFirstChild("Interaction")
            if prox then
                return crate.Position, prox
            end
        end
    end
    return nil, nil
end

-- ========== GỬI TURN IN ==========
local function turnInCrate()
    local args = { [1] = "TurnInCrate" }
    pcall(function()
        game:GetService("ReplicatedStorage")
            :WaitForChild("ReplicatedModules"):WaitForChild("KnitPackage")
            :WaitForChild("Knit"):WaitForChild("Services")
            :WaitForChild("DialogueService"):WaitForChild("RF")
            :WaitForChild("CheckRequirement"):InvokeServer(unpack(args))
    end)
end

-- ========== CHAT UTILITIES ==========
local function waitForChatKeyword(keyword)
    while true do
        if lastChat:lower():find(keyword:lower()) then 
            return true 
        end
        
        for _, chat in pairs(chatHistory) do
            if chat:find(keyword:lower()) then
                return true
            end
        end
        
        task.wait(0.05)
    end
end

local function hasDespawned()
    local despawnKeyword = "equipment crate+has despawned or been turned in!"
    return lastChat:lower():find(despawnKeyword:lower()) or 
           (#chatHistory > 0 and chatHistory[#chatHistory]:find(despawnKeyword:lower()))
end

-- ========== ENHANCED COLLECTION ==========
local function collectCrateMethod1(cratePos, prox)
    modifyProximityDistance(prox)
    aggressiveTeleport(cratePos)
    lookAtCrate(cratePos)
    
    if prox.Enabled then
        fireproximityprompt(prox, 1, true)
        for i = 1, 100 do
            if not prox.Enabled then
                return true
            end
            task.wait(0.01)
        end
    end
    return false
end

local function collectCrateMethod2(cratePos, prox)
    local hijackedProx = hijackProximity(prox)
    task.wait(0.1)
    
    if hijackedProx and hijackedProx.Enabled then
        fireproximityprompt(hijackedProx, 1, true)
        for i = 1, 100 do
            if not hijackedProx.Enabled then
                return true
            end
            task.wait(0.01)
        end
    end
    return false
end

-- ========== AGGRESSIVE LOOP ==========
local function aggressiveLoopToCrate(cratePos, prox)
    while true do
        local success = false
        
        if proximityMethod == 1 then
            success = collectCrateMethod1(cratePos, prox)
        else
            success = collectCrateMethod2(cratePos, prox)
        end
        
        if success then
            turnInCrate()
            return true
        end
        
        if hasDespawned() then
            return false
        end
        
        task.wait(0.01)
    end
end

-- ========== MAIN LOOP ==========
local function mainLoop()
    if proximityMethod == 2 then
        createInvisiblePart()
    end
    
    teleportTo(positionsToCheck[1])

    for i, pos in ipairs(positionsToCheck) do
        teleportTo(pos)
        task.wait(checkDelay)

        local cratePos, prox = getValidCrate()
        if prox then
            if prox.Enabled or proximityMethod == 2 then
                if aggressiveLoopToCrate(cratePos, prox) then
                    waitForChatKeyword("equipment crate+has despawned or been turned in!")
                    return
                end
            else
                if aggressiveLoopToCrate(cratePos, prox) then
                    waitForChatKeyword("equipment crate+has despawned or been turned in!")
                    return
                end
            end
        end
    end

    lastChat = ""
    chatHistory = {}
    waitForChatKeyword("equipment crate+has been reported!")

    while true do
        for i, pos in ipairs(positionsToCheck) do
            teleportTo(pos)
            task.wait(checkDelay)

            local cratePos, prox = getValidCrate()
            if prox then
                if aggressiveLoopToCrate(cratePos, prox) then
                    waitForChatKeyword("equipment crate+has despawned or been turned in!")
                    return
                end
            end
            
            if hasDespawned() then
                return
            end
        end

        task.wait(checkDelay)
    end
end

-- ========== KHỞI ĐỘNG ==========
monitorChat()

while true do
    pcall(mainLoop)
    task.wait(0.1)
end