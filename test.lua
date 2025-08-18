-- Equipment Crate Auto Collector
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

-- Danh sách vị trí spawn
local spawnPositions = {
    Vector3.new(-746.103271484375, 86.75001525878906, -620.12060546875),
    Vector3.new(-353.05078125, 132.3436279296875, 50.36767578125),
    Vector3.new(-70.82891845703125, 81.39054107666016, 834.0664672851562)
}

local currentPositionIndex = 1

-- Hàm teleport tức thì
local function teleportTo(position)
    if humanoidRootPart then
        humanoidRootPart.CFrame = CFrame.new(position)
    end
end

-- Hàm kiểm tra crate và thu thập
local function checkAndCollectCrate()
    local itemSpawns = workspace:FindFirstChild("ItemSpawns")
    if not itemSpawns then return false end
    
    local labCrate = itemSpawns:FindFirstChild("LabCrate")
    if not labCrate then return false end
    
    for _, crateSpawn in pairs(labCrate:GetChildren()) do
        local crate = crateSpawn:FindFirstChild("Crate")
        if crate then
            local proximityAttachment = crate:FindFirstChild("ProximityAttachment")
            if proximityAttachment then
                local interaction = proximityAttachment:FindFirstChild("Interaction")
                if interaction and interaction.Enabled then
                    -- Teleport đến crate
                    teleportTo(crate.Position)
                    
                    -- Kích proximity cho đến khi disabled
                    while interaction.Enabled do
                        fireproximityprompt(interaction)
                        wait(0.1)
                    end
                    
                    -- Gọi remote
                    local args = {[1] = "TurnInCrate"}
                    ReplicatedStorage:WaitForChild("ReplicatedModules")
                        :WaitForChild("KnitPackage")
                        :WaitForChild("Knit")
                        :WaitForChild("Services")
                        :WaitForChild("DialogueService")
                        :WaitForChild("RF")
                        :WaitForChild("CheckRequirement")
                        :InvokeServer(unpack(args))
                    
                    return true
                end
            end
        end
    end
    return false
end

-- Hàm kiểm tra spawn location có tồn tại tại vị trí cụ thể
local function checkSpawnLocationAtPosition(position)
    local itemSpawns = workspace:FindFirstChild("ItemSpawns")
    if not itemSpawns then return false end
    
    local labCrate = itemSpawns:FindFirstChild("LabCrate")
    if not labCrate then return false end
    
    -- Kiểm tra có spawn location nào gần vị trí này không
    for _, spawnLocation in pairs(labCrate:GetChildren()) do
        if spawnLocation.Name == "SpawnLocation" and spawnLocation.Position then
            local distance = (spawnLocation.Position - position).Magnitude
            if distance < 5 then -- Trong phạm vi 50 studs
                return true
            end
        end
    end
    
    return false
end

-- Hàm chính chạy liên tục  
local function mainLoop()
    local heartbeatConnection
    
    heartbeatConnection = RunService.Heartbeat:Connect(function()
        -- Teleport đến vị trí hiện tại
        teleportTo(spawnPositions[currentPositionIndex])
        
        -- Đợi spawn location tại vị trí này load
        if not checkSpawnLocationAtPosition(spawnPositions[currentPositionIndex]) then
            return -- Chờ load spawn location tại vị trí này
        end
        
        -- Kiểm tra và thu thập crate
        if checkAndCollectCrate() then
            -- Đã thu thập thành công, reset về vị trí đầu
            currentPositionIndex = 1
        else
            -- Không có crate, chuyển vị trí tiếp theo
            currentPositionIndex = currentPositionIndex + 1
            if currentPositionIndex > #spawnPositions then
                currentPositionIndex = 1
            end
        end
        
        wait(0.1)
    end)
end

-- Bắt đầu sau 10 giây và lặp lại mỗi 10 giây
spawn(function()
    while true do
        wait(10)
        mainLoop()
    end
end)