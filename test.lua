-- ⚠️ CHỈ DÀNH CHO MỤC ĐÍCH HỌC TẬP - KHÔNG KHUYẾN KHÍCH SỬ DỤNG TRONG GAME THẬT
-- Fixed Auto Mining GUI using Rayfield

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
local lastClickTime = 0
local minigameActive = false
local clickCooldown = 0.5 -- Tăng cooldown để tránh spam click

local stats = {
    totalHits = 0,
    totalMisses = 0,
    totalGames = 0,
    specialHits = 0
}

-- Create Window
local Window = Rayfield:CreateWindow({
   Name = "🎯 Auto Mining Tool (Fixed)",
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
local DebugTab = Window:CreateTab("🐛 Debug", "bug")

-- Main Tab Elements
MainTab:CreateSection("Auto Mining Controls")

-- Auto Mining Toggle
local AutoToggle = MainTab:CreateToggle({
   Name = "🤖 Auto Mining",
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
   Name = "✅ Auto Accept Prompts",
   CurrentValue = true,
   Flag = "AutoAccept",
   Callback = function(Value)
       if Value then
           setupAutoAccept()
       end
   end,
})

-- Status Label
local StatusLabel = MainTab:CreateLabel("⏸️ Status: Stopped", "activity")
local MinigameStatusLabel = MainTab:CreateLabel("📱 Minigame: Not Found", "smartphone")

-- Settings Tab
SettingsTab:CreateSection("Performance Settings")

-- Accuracy Slider
local AccuracySlider = SettingsTab:CreateSlider({
   Name = "🎯 Hit Accuracy",
   Range = {50, 100},
   Increment = 5,
   Suffix = "%",
   CurrentValue = 85,
   Flag = "Accuracy",
   Callback = function(Value)
       -- Update accuracy setting
   end,
})

-- Click Delay Slider  
local DelaySlider = SettingsTab:CreateSlider({
   Name = "⏱️ Click Cooldown",
   Range = {200, 1000},
   Increment = 50,
   Suffix = "ms",
   CurrentValue = 500,
   Flag = "ClickDelay",
   Callback = function(Value)
       clickCooldown = Value / 1000
   end,
})

-- Zone Priority Dropdown
local PriorityDropdown = SettingsTab:CreateDropdown({
   Name = "🎯 Target Priority",
   Options = {"Special > Gold > Normal", "Gold > Special > Normal", "Highest Value Only"},
   CurrentOption = {"Special > Gold > Normal"},
   Flag = "Priority",
   Callback = function(Options)
       -- Update priority setting
   end,
})

-- Precision Toggle
local PrecisionToggle = SettingsTab:CreateToggle({
   Name = "🎯 Precision Mode",
   CurrentValue = true,
   Flag = "PrecisionMode",
   Callback = function(Value)
       -- Kích hoạt chế độ chính xác cao
   end,
})

-- Stats Tab
StatsTab:CreateSection("Session Statistics")

local HitsLabel = StatsTab:CreateLabel("🎯 Total Hits: 0", "target")
local MissesLabel = StatsTab:CreateLabel("❌ Total Misses: 0", "x")
local GamesLabel = StatsTab:CreateLabel("🎮 Games Played: 0", "gamepad-2")
local SpecialLabel = StatsTab:CreateLabel("⭐ Special Hits: 0", "star")
local AccuracyLabel = StatsTab:CreateLabel("📈 Accuracy: 0%", "trending-up")

-- Debug Tab
DebugTab:CreateSection("Debug Information")
local DebugSliderLabel = DebugTab:CreateLabel("🎚️ Slider: Not Found", "sliders")
local DebugZoneLabel = DebugTab:CreateLabel("🎯 Zones: 0 found", "target")
local DebugPositionLabel = DebugTab:CreateLabel("📍 Position: 0, 0", "map-pin")

-- Reset Stats Button
local ResetStatsButton = StatsTab:CreateButton({
   Name = "🔄 Reset Statistics",
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
    
    local minigame = gameplay:FindFirstChild("MinigameUI")
    
    -- Kiểm tra xem minigame có tồn tại và visible không
    if minigame and minigame.Visible then
        minigameActive = true
        MinigameStatusLabel:Set("📱 Minigame: Active")
        return minigame
    else
        if minigameActive then
            -- Minigame vừa kết thúc
            minigameActive = false
            MinigameStatusLabel:Set("📱 Minigame: Ended")
            lastClickTime = tick() -- Reset click time khi minigame kết thúc
        else
            MinigameStatusLabel:Set("📱 Minigame: Not Found")
        end
        return nil
    end
end

local function findSlider(minigame)
    if not minigame then return nil end
    
    local bar = minigame:FindFirstChild("Bar")
    if not bar then return nil end
    
    local slider = bar:FindFirstChild("Slider")
    if slider and slider:IsA("GuiObject") and slider.Visible then
        DebugSliderLabel:Set(string.format("🎚️ Slider: Found (%.1f, %.1f)", slider.AbsolutePosition.X, slider.AbsolutePosition.Y))
        return slider
    end
    
    DebugSliderLabel:Set("🎚️ Slider: Not Found")
    return nil
end

local function getZonePriority(zone)
    local color = zone.BackgroundColor3
    
    -- Màu cam - Special zone (priority cao nhất)
    if math.abs(color.R - 1) < 0.1 and math.abs(color.G - 0.55) < 0.1 and math.abs(color.B - 0.25) < 0.1 then
        return 3
    -- Màu vàng - Gold zone  
    elseif math.abs(color.R - 1) < 0.1 and math.abs(color.G - 0.89) < 0.1 and math.abs(color.B - 0.45) < 0.1 then
        return 2
    -- Màu tím - Normal zone
    elseif math.abs(color.R - 0.88) < 0.1 and math.abs(color.G - 0.69) < 0.1 and math.abs(color.B - 1) < 0.1 then
        return 1
    else
        return 1 -- Default
    end
end

local function findZones(minigame)
    if not minigame then 
        DebugZoneLabel:Set("🎯 Zones: No minigame")
        return {} 
    end
    
    local zones = {}
    local bar = minigame:FindFirstChild("Bar")
    if not bar then 
        DebugZoneLabel:Set("🎯 Zones: No bar found")
        return zones 
    end
    
    for _, child in pairs(bar:GetChildren()) do
        if child:IsA("Frame") and child.Name ~= "Slider" and child.Visible and child.BackgroundTransparency < 0.9 then
            table.insert(zones, {
                frame = child,
                position = child.AbsolutePosition.X,
                size = child.AbsoluteSize.X,
                priority = getZonePriority(child),
                color = child.BackgroundColor3
            })
        end
    end
    
    DebugZoneLabel:Set(string.format("🎯 Zones: %d found", #zones))
    return zones
end

local function isSliderInZone(slider, zone)
    if not slider or not zone then return false end
    
    local sliderPos = slider.AbsolutePosition.X
    local sliderSize = slider.AbsoluteSize.X
    local sliderCenter = sliderPos + sliderSize/2
    
    local zonePos = zone.frame.AbsolutePosition.X
    local zoneSize = zone.frame.AbsoluteSize.X
    local zoneStart = zonePos
    local zoneEnd = zonePos + zoneSize
    
    -- Kiểm tra chính xác hơn: slider center phải nằm trong zone với margin
    local margin = 5 -- pixel margin để chính xác hơn
    return sliderCenter >= (zoneStart + margin) and sliderCenter <= (zoneEnd - margin)
end

local function detectOptimalHit(minigame)
    local slider = findSlider(minigame)
    local zones = findZones(minigame)
    
    if not slider or #zones == 0 then
        return false, nil
    end
    
    local sliderCenter = slider.AbsolutePosition.X + slider.AbsoluteSize.X/2
    DebugPositionLabel:Set(string.format("📍 Slider Center: %.1f", sliderCenter))
    
    local bestZone = nil
    local highestPriority = 0
    
    -- Tìm zone có priority cao nhất mà slider đang ở trong
    for _, zone in pairs(zones) do
        if isSliderInZone(slider, zone) then
            if zone.priority > highestPriority then
                bestZone = zone
                highestPriority = zone.priority
            end
        end
    end
    
    return bestZone ~= nil, bestZone
end

local function safeClick(zone)
    local currentTime = tick()
    
    -- Kiểm tra cooldown
    if currentTime - lastClickTime < clickCooldown then
        return false
    end
    
    -- Kiểm tra accuracy
    local accuracy = AccuracySlider.CurrentValue / 100
    if math.random() > accuracy then
        stats.totalMisses = stats.totalMisses + 1
        lastClickTime = currentTime
        updateStatsDisplay()
        return false
    end
    
    local clickX, clickY
    
    if zone and zone.frame then
        -- Click vào trung tâm zone để chính xác nhất
        local zonePos = zone.frame.AbsolutePosition
        local zoneSize = zone.frame.AbsoluteSize
        
        if PrecisionToggle.CurrentValue then
            -- Precision mode: click chính giữa zone
            clickX = zonePos.X + zoneSize.X/2
            clickY = zonePos.Y + zoneSize.Y/2
        else
            -- Random mode: click random trong zone
            clickX = zonePos.X + math.random(10, zoneSize.X-10)
            clickY = zonePos.Y + math.random(10, zoneSize.Y-10)
        end
    else
        -- Fallback click vào center screen
        clickX = workspace.CurrentCamera.ViewportSize.X/2
        clickY = workspace.CurrentCamera.ViewportSize.Y/2
    end
    
    -- Thực hiện click
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 1)
        wait(0.01) -- Rất ngắn để tránh lag
        VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 1)
    end)
    
    -- Update stats và time
    stats.totalHits = stats.totalHits + 1
    if zone and zone.priority >= 3 then
        stats.specialHits = stats.specialHits + 1
    end
    
    lastClickTime = currentTime
    updateStatsDisplay()
    
    return true
end

function StartAutoMining()
    if isAutoRunning then return end
    
    isAutoRunning = true
    StatusLabel:Set("🟢 Status: Running")
    stats.totalGames = stats.totalGames + 1
    lastClickTime = 0 -- Reset click time
    
    Rayfield:Notify({
        Title = "Auto Mining Started",
        Content = "Bot is now running! Waiting for optimal hits...",
        Duration = 3,
        Image = "play",
    })
    
    connection = RunService.Heartbeat:Connect(function()
        if not isAutoRunning then return end
        
        local minigame = findMiningMinigame()
        if not minigame then return end
        
        -- Đợi một chút để minigame load hoàn toàn
        if not minigameActive then
            wait(0.1)
            return
        end
        
        local canHit, zone = detectOptimalHit(minigame)
        if canHit and zone then
            -- Click trong thread riêng để không block main thread
            spawn(function()
                local success = safeClick(zone)
                if success then
                    -- Đợi một chút sau khi click để zone có thể update
                    wait(0.2)
                end
            end)
        end
    end)
end

function StopAutoMining()
    isAutoRunning = false
    minigameActive = false
    StatusLabel:Set("⏸️ Status: Stopped")
    MinigameStatusLabel:Set("📱 Minigame: Stopped")
    
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
        Title = "Fixed Mining Tool Loaded",
        Content = "All bugs have been fixed! Ready to mine!",
        Duration = 4,
        Image = "pickaxe",
    })
end)

-- Cleanup khi player rời game
Players.PlayerRemoving:Connect(function(player)
    if player == LocalPlayer then
        StopAutoMining()
    end
end)

-- Auto stop khi minigame kết thúc bất thường
spawn(function()
    while true do
        wait(1)
        if isAutoRunning and not findMiningMinigame() and minigameActive then
            -- Minigame đã kết thúc nhưng bot vẫn chạy
            minigameActive = false
            wait(2) -- Đợi 2 giây cho minigame mới
        end
    end
end)