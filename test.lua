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

-- ========== AGGRESSIVE LOOP TELEPORT ==========
local function aggressiveLoopToCrate(cratePos, prox)
    -- Loop vô hạn cho đến khi thành công hoặc despawn
    while true do
        -- Teleport liên tục không ngừng để cạnh tranh
        aggressiveTeleport(cratePos)
        
        -- Check enabled ngay lập tức
        if prox.Enabled then
            -- Collect ngay lập tức
            fireproximityprompt(prox, 1, true)
            
            -- Chờ disable với loop teleport tiếp tục
            local collected = false
            for i = 1, 100 do -- Check 100 lần
                aggressiveTeleport(cratePos) -- Tiếp tục teleport trong khi chờ
                if not prox.Enabled then
                    collected = true
                    break
                end
            end
            
            if collected then
                turnInCrate()
                return true
            end
        end
        
        -- Check nếu crate bị despawn
        if hasDespawned() then
            return false
        end
    end
end

-- ========== MAIN LOOP ==========
local function mainLoop()
    -- Teleport ban đầu
    teleportTo(positionsToCheck[1])

    -- Kiểm tra crates có sẵn
    for i, pos in ipairs(positionsToCheck) do
        teleportTo(pos)
        task.wait(checkDelay)

        local cratePos, prox = getValidCrate()
        if prox then
            if prox.Enabled then
                aggressiveTeleport(cratePos)
                fireproximityprompt(prox, 1, true)
                repeat 
                    aggressiveTeleport(cratePos)
                    task.wait(0.01)
                until not prox.Enabled
                turnInCrate()
                waitForChatKeyword("equipment crate+has despawned or been turned in!")
                return
            else
                -- Crate tồn tại nhưng chưa enabled - bắt đầu aggressive loop
                if aggressiveLoopToCrate(cratePos, prox) then
                    waitForChatKeyword("equipment crate+has despawned or been turned in!")
                    return
                end
            end
        end
    end

    -- Reset và chờ spawn notification
    lastChat = ""
    chatHistory = {}
    waitForChatKeyword("equipment crate+has been reported!")

    -- Main search loop
    while true do
        for i, pos in ipairs(positionsToCheck) do
            teleportTo(pos)
            task.wait(checkDelay)

            local cratePos, prox = getValidCrate()
            if prox then
                -- Bắt đầu aggressive loop ngay khi tìm thấy crate
                if aggressiveLoopToCrate(cratePos, prox) then
                    waitForChatKeyword("equipment crate+has despawned or been turned in!")
                    return
                end
            end
            
            -- Check despawn
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