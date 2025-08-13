-- ⚠️ CHỈ DÀNH CHO MỤC ĐÍCH HỌC TẬP - KHÔNG KHUYẾN KHÍCH SỬ DỤNG TRONG GAME THẬT
-- Simple Auto Mining GUI using Rayfield

-- Load Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- Variables
local isAutoRunning = false
local connection = nil
local stats = {
    totalHits = 0,
    totalMisses = 0,
    totalGames = 0,
    specialHits = 0
}

-- Create Window
local Window = Rayfield:CreateWindow({
   Name = "Auto Mining Tool",
   Icon = "pickaxe",
   LoadingTitle = "Mining Assistant",
   LoadingSubtitle = "by AI Helper",
   ShowText = "Mining Tool",
   Theme = "DarkBlue",
   ToggleUIKeybind = Enum.KeyCode.RightControl,
   
   ConfigurationSaving = {
      Enabled = true,
      FolderName = "AutoMining",
      FileName = "MiningConfig"
   },
   
   Discord = {
      Enabled = false,
   },
   
   KeySystem = false,
})

-- Create Tabs
local MainTab = Window:CreateTab("🏠 Main", "home")
local SettingsTab = Window:CreateTab("⚙️ Settings", "settings")
local StatsTab = Window:CreateTab("📊 Stats", "bar-chart")

-- Main Tab Elements
MainTab:CreateSection("Auto Mining Controls")

-- Auto Mining Toggle
local AutoToggle = MainTab:CreateToggle({
   Name = "Auto Mining",
   CurrentValue = false,
   Flag = "AutoMining",
   Callback = function(Value)
       if Value then
           StartAutoMining()
       else
           StopAutoMining()
       end
   end,
})

-- Auto Accept Toggle
local AcceptToggle = MainTab:CreateToggle({
   Name = "Auto Accept Prompts",
   CurrentValue = true,
   Flag = "AutoAccept",
   Callback = function(Value)
       if Value then
           setupAutoAccept()
       end
   end,
})

-- Status Label
local StatusLabel = MainTab:CreateLabel("Status: Stopped", "activity")

-- Settings Tab
SettingsTab:CreateSection("Performance Settings")

-- Accuracy Slider
local AccuracySlider = SettingsTab:CreateSlider({
   Name = "Hit Accuracy",
   Range = {50, 100},
   Increment = 5,
   Suffix = "%",
   CurrentValue = 85,
   Flag = "Accuracy",
   Callback = function(Value)
       -- Update accuracy setting
   end,
})

-- Delay Slider  
local DelaySlider = SettingsTab:CreateSlider({
   Name = "Click Randomness",
   Range = {0, 100},
   Increment = 10,
   Suffix = "%",
   CurrentValue = 50,
   Flag = "ClickRandom",
   Callback = function(Value)
       -- Update click randomness setting
   end,
})

-- Zone Priority Dropdown
local PriorityDropdown = SettingsTab:CreateDropdown({
   Name = "Target Priority",
   Options = {"Special > Gold > Normal", "Gold > Special > Normal", "Highest Value Only"},
   CurrentOption = {"Special > Gold > Normal"},
   Flag = "Priority",
   Callback = function(Options)
       -- Update priority setting
   end,
})

-- Stats Tab
StatsTab:CreateSection("Session Statistics")

local HitsLabel = StatsTab:CreateLabel("Total Hits: 0", "target")
local MissesLabel = StatsTab:CreateLabel("Total Misses: 0", "x")
local GamesLabel = StatsTab:CreateLabel("Games Played: 0", "gamepad-2")
local SpecialLabel = StatsTab:CreateLabel("Special Hits: 0", "star")
local AccuracyLabel = StatsTab:CreateLabel("Accuracy: 0%", "trending-up")

-- Reset Stats Button
local ResetStatsButton = StatsTab:CreateButton({
   Name = "Reset Statistics",
   Callback = function()
       stats = {totalHits = 0, totalMisses = 0, totalGames = 0, specialHits = 0}
       updateStatsDisplay()
       Rayfield:Notify({
           Title = "Stats Reset",
           Content = "All statistics have been reset!",
           Duration = 3,
           Image = "refresh-cw",
       })
   end,
})

-- Utility Functions
local function updateStatsDisplay()
    HitsLabel:Set(string.format("🎯 Total Hits: %d", stats.totalHits))
    MissesLabel:Set(string.format("❌ Total Misses: %d", stats.totalMisses))
    GamesLabel:Set(string.format("🎮 Games Played: %d", stats.totalGames))
    SpecialLabel:Set(string.format("⭐ Special Hits: %d", stats.specialHits))
    
    local totalAttempts = stats.totalHits + stats.totalMisses
    local accuracy = totalAttempts > 0 and math.floor((stats.totalHits / totalAttempts) * 100) or 0
    AccuracyLabel:Set(string.format("📈 Accuracy: %d%%", accuracy))
end

local function findMiningMinigame()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local ui = playerGui:FindFirstChild("UI")
    if not ui then return nil end
    
    local gameplay = ui:FindFirstChild("Gameplay")
    if not gameplay then return nil end
    
    -- Đường dẫn chính xác từ user
    local minigame = gameplay:FindFirstChild("MinigameUI")
    
    return minigame
end

local function findSlider(minigame)
    if not minigame then return nil end
    
    local bar = minigame:FindFirstChild("Bar")
    if not bar then return nil end
    
    local slider = bar:FindFirstChild("Slider")
    if slider and slider:IsA("GuiObject") then
        return slider
    end
    
    return nil
end

local function getZonePriority(zone)
    local color = zone.BackgroundColor3
    
    if color == Color3.fromRGB(255, 140, 64) then
        return 3 -- Special zone (cam)
    elseif color == Color3.fromRGB(255, 227, 114) then  
        return 2 -- Gold zone (vàng)
    elseif color == Color3.fromRGB(224, 175, 255) then
        return 1 -- Normal zone (tím)
    else
        return 1 -- Default
    end
end

local function findZones(minigame)
    if not minigame then return {} end
    
    local zones = {}
    local bar = minigame:FindFirstChild("Bar")
    if not bar then return zones end
    
    for _, child in pairs(bar:GetChildren()) do
        if child:IsA("Frame") and child.Name ~= "Slider" and child.Visible then
            if child.BackgroundTransparency < 1 then
                table.insert(zones, {
                    frame = child,
                    position = child.AbsolutePosition.X,
                    size = child.AbsoluteSize.X,
                    priority = getZonePriority(child)
                })
            end
        end
    end
    
    return zones
end

local function detectOptimalHit(minigame)
    local slider = findSlider(minigame)
    local zones = findZones(minigame)
    
    if not slider or #zones == 0 then
        return false, nil
    end
    
    -- Sử dụng AbsolutePosition và AbsoluteSize như user chỉ dẫn
    local sliderPos = slider.AbsolutePosition.X
    local sliderSize = slider.AbsoluteSize.X
    local sliderCenter = sliderPos + sliderSize/2
    
    local bestZone = nil
    local highestPriority = 0
    
    for _, zone in pairs(zones) do
        local zonePos = zone.frame.AbsolutePosition.X
        local zoneSize = zone.frame.AbsoluteSize.X
        local zoneStart = zonePos
        local zoneEnd = zonePos + zoneSize
        
        -- Check collision: slider center trong zone
        if sliderCenter >= zoneStart and sliderCenter <= zoneEnd then
            if zone.priority >= highestPriority then
                bestZone = zone
                highestPriority = zone.priority
            end
        end
    end
    
    return bestZone ~= nil, bestZone
end

local function simulateClick(zone)
    local accuracy = AccuracySlider.CurrentValue / 100
    
    -- Check accuracy
    if math.random() > accuracy then
        stats.totalMisses = stats.totalMisses + 1
        updateStatsDisplay()
        return
    end
    
    -- Không dùng delay, thay vào đó click random trong zone size
    local clickX, clickY = 0, 0
    
    if zone and zone.frame then
        -- Click vào vị trí random trong zone để bypass detection
        local zonePos = zone.frame.AbsolutePosition
        local zoneSize = zone.frame.AbsoluteSize
        
        clickX = zonePos.X + math.random(0, zoneSize.X)
        clickY = zonePos.Y + math.random(0, zoneSize.Y)
    end
    
    -- Click tại vị trí random trong zone
    VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 1)
    wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 1)
    
    -- Update stats
    stats.totalHits = stats.totalHits + 1
    if zone and zone.priority >= 3 then
        stats.specialHits = stats.specialHits + 1
    end
    updateStatsDisplay()
end

function StartAutoMining()
    if isAutoRunning then return end
    
    isAutoRunning = true
    StatusLabel:Set("🟢 Status: Running")
    stats.totalGames = stats.totalGames + 1
    
    Rayfield:Notify({
        Title = "Auto Mining Started",
        Content = "Bot is now running! Good luck!",
        Duration = 3,
        Image = "play",
    })
    
    connection = RunService.Heartbeat:Connect(function()
        if not isAutoRunning then return end
        
        local minigame = findMiningMinigame()
        if not minigame then return end
        
        local canHit, zone = detectOptimalHit(minigame)
        if canHit then
            spawn(function()
                simulateClick(zone)
            end)
            wait(0.2) -- Cooldown
        end
    end)
end

function StopAutoMining()
    isAutoRunning = false
    StatusLabel:Set("⏸️ Status: Stopped")
    
    if connection then
        connection:Disconnect()
        connection = nil
    end
    
    Rayfield:Notify({
        Title = "Auto Mining Stopped",
        Content = "Bot has been stopped successfully!",
        Duration = 3,
        Image = "pause",
    })
end

function setupAutoAccept()
    spawn(function()
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local SystemRemotes = ReplicatedStorage:WaitForChild("SystemRemotes", 5)
        if not SystemRemotes then return end
        
        local ClientPrompt = SystemRemotes:WaitForChild("ClientPrompt", 5)  
        if not ClientPrompt then return end
        
        ClientPrompt.OnClientInvoke = function(minigameName)
            if minigameName and string.find(minigameName:lower(), "mining") then
                Rayfield:Notify({
                    Title = "Auto Accepted",
                    Content = "Mining prompt accepted automatically!",
                    Duration = 2,
                    Image = "check",
                })
                return true
            else
                return false
            end
        end
    end)
end

-- Initialize
spawn(function()
    wait(2)
    if AcceptToggle.CurrentValue then
        setupAutoAccept()
    end
    updateStatsDisplay()
    
    Rayfield:Notify({
        Title = "Mining Tool Loaded",
        Content = "Ready to start mining! Check the settings first.",
        Duration = 4,
        Image = "pickaxe",
    })
end)

-- Cleanup
Players.PlayerRemoving:Connect(function(player)
    if player == LocalPlayer then
        StopAutoMining()
    end
end)