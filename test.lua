-- Kiểm tra writefile
assert(writefile and getconnections, "⚠️ Cần exploit hỗ trợ writefile và getconnections!")

local LogFile = "CrateChatLog.txt"
local TimestampFile = "ProcessedTimestamps.txt"
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

-- Vị trí spawn crates
local spawnPositions = {
    Vector3.new(-746.103271484375, 86.75001525878906, -620.12060546875),
    Vector3.new(-353.05078125, 132.3436279296875, 50.36767578125),
    Vector3.new(-70.82891845703125, 81.39054107666016, 834.0664672851562)
}

-- Reset log file
writefile(LogFile, "")

-- Tạo file timestamp nếu chưa có
if not isfile(TimestampFile) then
    writefile(TimestampFile, "")
end

-- Hàm ghi log
local function logToFile(text)
    appendfile(LogFile, text .. "\n")
end

-- Hàm lưu timestamp đã xử lý
local function saveProcessedTimestamp(timestamp)
    processedTimestamps[timestamp] = true
    appendfile(TimestampFile, tostring(timestamp) .. "\n")
end

-- Biến theo dõi chat
local waitingForCrate = false
local processedTimestamps = {}
local lastCrateMessage = ""

-- Đọc timestamps đã xử lý (nếu có)
if isfile(TimestampFile) then
    local content = readfile(TimestampFile)
    for timestamp in string.gmatch(content, "[^\n]+") do
        processedTimestamps[tonumber(timestamp)] = true
    end
end

-- Theo dõi chat (chỉ crate-related với timestamp)
local function scanForChatLabels(container)
    container.DescendantAdded:Connect(function(desc)
        if desc:IsA("TextLabel") and desc.Text and #desc.Text > 0 then
            local chatText = desc.Text
            local messageTime = tick()
            
            -- Chỉ xử lý chat liên quan đến crate và chưa được xử lý
            if string.find(chatText, "lost equipment crate") and not processedTimestamps[messageTime] then
                local timestamp = os.date("[%H:%M:%S]", messageTime)
                logToFile(timestamp .. " [GUI Chat] " .. chatText)
                
                -- Lưu timestamp đã xử lý
                saveProcessedTimestamp(messageTime)
                
                -- Cập nhật tin nhắn crate cuối cùng
                lastCrateMessage = chatText
                
                -- Kiểm tra spawn crate
                if string.find(chatText, "has been reported!") then
                    waitingForCrate = false
                end
            end
        end
    end)
end

-- Theo dõi GUI
local guiTargets = {
    player:WaitForChild("PlayerGui"),
    game:GetService("CoreGui")
}

for _, gui in ipairs(guiTargets) do
    scanForChatLabels(gui)
    gui.ChildAdded:Connect(function(child)
        scanForChatLabels(child)
    end)
end

-- Hàm teleport với loop
local function teleportLoop(position)
    local connection
    connection = RunService.Heartbeat:Connect(function()
        if humanoidRootPart and humanoidRootPart.Parent then
            humanoidRootPart.CFrame = CFrame.new(position)
        end
    end)
    
    wait(0.1)
    connection:Disconnect()
end

-- Hàm kiểm tra và thu thập crate
local function checkAndCollectCrates()
    local labCrate = workspace.ItemSpawns:FindFirstChild("LabCrate")
    if not labCrate then return false end
    
    for _, child in pairs(labCrate:GetChildren()) do
        local crate = child:FindFirstChild("Crate")
        if crate then
            local proximityAttachment = crate:FindFirstChild("ProximityAttachment")
            if proximityAttachment then
                local interaction = proximityAttachment:FindFirstChild("Interaction")
                if interaction and interaction.Enabled then
                    -- Teleport đến crate
                    teleportLoop(crate.Position)
                    
                    -- Kích hoạt proximity cho đến khi disabled
                    while interaction.Enabled do
                        fireproximityprompt(interaction)
                        wait(0.1)
                    end
                    
                    -- Chạy remote
                    local args = {
                        [1] = "TurnInCrate"
                    }
                    
                    ReplicatedStorage:WaitForChild("ReplicatedModules"):WaitForChild("KnitPackage"):WaitForChild("Knit"):WaitForChild("Services"):WaitForChild("DialogueService"):WaitForChild("RF"):WaitForChild("CheckRequirement"):InvokeServer(unpack(args))
                    
                    return true
                end
            end
        end
    end
    return false
end

-- Main loop
while true do
    -- Reset log mỗi lần bắt đầu vòng lập mới (giữ nguyên timestamp file)
    writefile(LogFile, "")
    
    -- Chỉ teleport nếu tin nhắn crate cuối cùng là spawn
    if string.find(lastCrateMessage, "has been reported!") then
        -- Teleport và kiểm tra các vị trí spawn
        for _, position in ipairs(spawnPositions) do
            teleportLoop(position)
            wait(0.1)
        end
        
        -- Kiểm tra và thu thập crates
        if checkAndCollectCrates() then
            -- Đã thu thập được crate, đợi chat thông báo crate mới
            waitingForCrate = true
            while waitingForCrate do
                wait(1)
            end
        else
            -- Không có crate, đợi chat thông báo spawn
            waitingForCrate = true
            while waitingForCrate do
                wait(1)
            end
        end
    else
        -- Tin nhắn cuối không phải spawn, chỉ đợi
        waitingForCrate = true
        while waitingForCrate do
            wait(1)
        end
    end
end