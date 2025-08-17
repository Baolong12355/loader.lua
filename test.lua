-- Auto Crate Farm Script
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

-- Cấu hình
local TELEPORT_SPEED = 50 -- Tốc độ teleport
local CHECK_DELAY = 0.1 -- Delay giữa các lần check
local FARMING_ENABLED = true

-- Các vị trí spawn crate
local SPAWN_POSITIONS = {
    Vector3.new(-746.103271484375, 86.75001525878906, -620.12060546875),
    Vector3.new(-353.05078125, 132.3436279296875, 50.36767578125),
    Vector3.new(-70.82891845703125, 81.39054107666016, 834.0664672851562)
}

-- Biến trạng thái
local isWaitingForSpawn = false
local lastChatMessage = ""

print("🚀 Auto Crate Farm Script đã khởi động!")

-- Hàm teleport với animation mượt
local function teleportToPosition(position)
    if not Character or not HumanoidRootPart then return end
    
    local tweenInfo = TweenInfo.new(
        (HumanoidRootPart.Position - position).Magnitude / TELEPORT_SPEED,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.InOut
    )
    
    local tween = TweenService:Create(HumanoidRootPart, tweenInfo, {CFrame = CFrame.new(position)})
    tween:Play()
    tween.Completed:Wait()
    wait(CHECK_DELAY)
end

-- Hàm gọi remote TurnInCrate
local function turnInCrate()
    local success, result = pcall(function()
        local args = {
            [1] = "TurnInCrate"
        }
        
        return ReplicatedStorage:WaitForChild("ReplicatedModules")
            :WaitForChild("KnitPackage")
            :WaitForChild("Knit")
            :WaitForChild("Services")
            :WaitForChild("DialogueService")
            :WaitForChild("RF")
            :WaitForChild("CheckRequirement"):InvokeServer(unpack(args))
    end)
    
    if success then
        print("✅ Đã gọi TurnInCrate thành công!")
    else
        warn("❌ Lỗi khi gọi TurnInCrate: " .. tostring(result))
    end
end

-- Hàm kiểm tra và tương tác với crate
local function checkAndInteractWithCrate()
    local itemSpawns = workspace:FindFirstChild("ItemSpawns")
    if not itemSpawns then return false end
    
    local labCrate = itemSpawns:FindFirstChild("LabCrate")
    if not labCrate then return false end
    
    local children = labCrate:GetChildren()
    if #children < 2 then return false end
    
    local crateChild = children[2]
    local crate = crateChild:FindFirstChild("Crate")
    if not crate then return false end
    
    local proximityAttachment = crate:FindFirstChild("ProximityAttachment")
    if not proximityAttachment then return false end
    
    local interaction = proximityAttachment:FindFirstChild("Interaction")
    if not interaction then return false end
    
    -- Kiểm tra nếu interaction enabled
    if interaction.Enabled then
        print("🎯 Tìm thấy crate có thể tương tác!")
        
        -- Kích hoạt proximity cho đến khi disabled
        while interaction.Enabled and FARMING_ENABLED do
            -- Trigger proximity prompt
            if interaction:IsA("ProximityPrompt") then
                fireproximityprompt(interaction)
            end
            wait(0.1)
        end
        
        print("📦 Đã tương tác xong với crate!")
        
        -- Gọi remote sau khi tương tác
        wait(0.5) -- Đợi một chút trước khi gọi remote
        turnInCrate()
        
        return true
    end
    
    return false
end

-- Hàm theo dõi chat để phát hiện thông báo spawn
local function setupChatMonitoring()
    -- Tạo file log chat
    local LogFile = "CrateFarm_ChatLog_" .. os.time() .. ".txt"
    if writefile then
        writefile(LogFile, "=== Auto Crate Farm Chat Monitor ===\n")
    end
    
    local function logChat(text)
        lastChatMessage = text
        if writefile then
            appendfile(LogFile, "[" .. os.date() .. "] " .. text .. "\n")
        end
        print("💬 Chat: " .. text)
        
        -- Kiểm tra thông báo spawn crate
        if string.find(text, "lost equipment crate") and string.find(text, "has been reported!") then
            print("🚨 Phát hiện crate mới spawn!")
            isWaitingForSpawn = false
        end
        
        -- Kiểm tra thông báo crate despawn
        if string.find(text, "lost equipment crate") and (string.find(text, "despawned") or string.find(text, "turned in")) then
            print("⏰ Crate đã despawn hoặc được turn in")
            isWaitingForSpawn = true
        end
    end
    
    -- Theo dõi chat GUI
    local function scanChatLabels(container)
        if not container then return end
        
        -- Theo dõi TextLabel mới được thêm
        container.DescendantAdded:Connect(function(desc)
            if desc:IsA("TextLabel") and desc.Text and #desc.Text > 0 then
                logChat("[GUI Chat] " .. desc.Text)
            end
        end)
        
        -- Kiểm tra TextLabel hiện có
        for _, desc in pairs(container:GetDescendants()) do
            if desc:IsA("TextLabel") and desc.Text and #desc.Text > 0 then
                logChat("[GUI Chat] " .. desc.Text)
            end
        end
    end
    
    -- Theo dõi các GUI container có thể chứa chat
    local guiContainers = {
        LocalPlayer:WaitForChild("PlayerGui"),
        game:GetService("CoreGui")
    }
    
    for _, gui in ipairs(guiContainers) do
        scanChatLabels(gui)
        
        -- Theo dõi GUI mới được tạo
        gui.ChildAdded:Connect(function(child)
            wait(0.1) -- Đợi GUI load xong
            scanChatLabels(child)
        end)
    end
end

-- Vòng lặp chính
local function mainLoop()
    -- Dịch chuyển một lần đầu tiên
    print("🎯 Bắt đầu kiểm tra các vị trí spawn...")
    
    while FARMING_ENABLED do
        if not isWaitingForSpawn then
            local foundCrate = false
            
            -- Kiểm tra từng vị trí spawn
            for i, position in ipairs(SPAWN_POSITIONS) do
                if not FARMING_ENABLED then break end
                
                print("🔍 Kiểm tra vị trí " .. i .. ": " .. tostring(position))
                teleportToPosition(position)
                
                -- Kiểm tra crate tại vị trí hiện tại
                if checkAndInteractWithCrate() then
                    foundCrate = true
                    break
                end
            end
            
            -- Nếu không tìm thấy crate nào, chuyển sang chế độ chờ
            if not foundCrate then
                print("⌛ Không tìm thấy crate khả dụng, chuyển sang chế độ chờ...")
                isWaitingForSpawn = true
            end
        else
            print("⏳ Đang chờ thông báo spawn crate mới...")
            wait(1) -- Chờ lâu hơn khi không có crate
        end
        
        wait(CHECK_DELAY)
    end
end

-- Khởi động script
setupChatMonitoring()

-- Đợi một chút để chat system load
wait(2)

-- Bắt đầu vòng lặp chính
spawn(function()
    mainLoop()
end)

-- Lệnh điều khiển
local function stopFarming()
    FARMING_ENABLED = false
    print("🛑 Đã dừng Auto Crate Farm!")
end

local function startFarming()
    FARMING_ENABLED = true
    print("▶️ Đã khởi động lại Auto Crate Farm!")
    spawn(function()
        mainLoop()
    end)
end

-- Export functions để có thể điều khiển từ console
_G.StopCrateFarm = stopFarming
_G.StartCrateFarm = startFarming

print("📋 Lệnh điều khiển:")
print("   _G.StopCrateFarm() - Dừng farm")
print("   _G.StartCrateFarm() - Bắt đầu farm")
print("🎮 Script đã sẵn sàng!")