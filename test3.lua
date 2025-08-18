local Players = game:GetService("Players")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

local function isPlayerWhitelisted(chest)
    local whitelisted = chest:FindFirstChild("Whitelisted")
    if not whitelisted then
        print("DEBUG: " .. chest.Name .. " - Không có Whitelisted")
        return false
    end
    
    local children = whitelisted:GetChildren()
    print("DEBUG: " .. chest.Name .. " - Whitelisted children count: " .. #children)
    for _, child in pairs(children) do
        print("DEBUG: Child name: " .. child.Name .. " | Player UserId: " .. tostring(player.UserId))
        if child.Name == tostring(player.UserId) then
            print("DEBUG: " .. chest.Name .. " - Player có trong whitelist!")
            return true
        end
    end
    print("DEBUG: " .. chest.Name .. " - Player KHÔNG có trong whitelist")
    return false
end

local function hasProximityInteraction(chest)
    local proximityAttachment = chest:FindFirstChild("ProximityAttachment")
    if not proximityAttachment then
        print("DEBUG: " .. chest.Name .. " - Không có ProximityAttachment")
        return false
    end
    
    local hasInteraction = proximityAttachment:FindFirstChild("Interaction") ~= nil
    print("DEBUG: " .. chest.Name .. " - Có Interaction: " .. tostring(hasInteraction))
    return hasInteraction
end

local function teleportToChest(chest)
    if chest and chest:FindFirstChild("ProximityAttachment") then
        print("DEBUG: Teleporting to " .. chest.Name)
        local proximityPos = chest.ProximityAttachment.WorldPosition
        humanoidRootPart.CFrame = CFrame.new(proximityPos + Vector3.new(0, 5, 0))
        wait(0.1)
        
        local proximityAttachment = chest:FindFirstChild("ProximityAttachment")
        if proximityAttachment and proximityAttachment:FindFirstChild("Interaction") then
            print("DEBUG: Firing proximity for " .. chest.Name)
            fireproximityprompt(proximityAttachment.Interaction)
        else
            print("DEBUG: Không thể fire proximity cho " .. chest.Name)
        end
    else
        print("DEBUG: Không thể teleport đến " .. chest.Name)
    end
end

local function local function startContinuousScanning()
    print("DEBUG: Starting continuous scanning...")
    print("DEBUG: Player UserId: " .. tostring(player.UserId))
    
    while true do
        findAndProcessChests()
        print("DEBUG: Waiting 1 second before next scan...")
        wait(1)
    end
end

startContinuousScanning()
    for _, obj in pairs(workspace:GetDescendants()) do
        if string.find(obj.Name, "Chest") then
            if hasProximityInteraction(obj) and isPlayerWhitelisted(obj) then
                teleportToChest(obj)
            end
        end
    end
end

findAndProcessChests()