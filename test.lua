-- ⚠️ CHỈ DÀNH CHO MỤC ĐÍCH HỌC TẬP - KHÔNG KHUYẾN KHÍCH SỬ DỤNG TRONG GAME THẬT
-- Fixed Auto Mining GUI with Correct Path Structure

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
local clickCooldown = 0.3 -- Giảm cooldown cho responsive hơn

local stats = {
    totalHits = 0,
    totalMisses = 0,
    totalGames = 0,
    specialHits = 0,
    goldHits = 0
}

-- Create Window
local Window = Rayfield:CreateWindow({
   Name = "🎯 Auto Mining Tool (Fixed Path)",
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
local StatusLabel = MainTab:CreateLabel("⏸️ Status: Stopped")
local MinigameStatusLabel = MainTab:CreateLabel("📱 Minigame: Not Found")

-- Settings Tab
SettingsTab:CreateSection("Performance Settings")

-- Accuracy Slider
local AccuracySlider = SettingsTab:CreateSlider({
   Name = "🎯 Hit Accuracy",
   Range = {60, 100},
   Increment = 5,
   Suffix = "%",
   CurrentValue = 90,
   Flag = "Accuracy",
   Callback = function(Value)
       -- Update accuracy setting
   end,
})

-- Click Delay Slider  
local DelaySlider = SettingsTab:CreateSlider({
   Name = "⏱️ Click Cooldown",
   Range = {100, 800},
   Increment = 50,
   Suffix = "ms",
   CurrentValue = 300,
   Flag = "ClickDelay",
   Callback = function(Value)
       clickCooldown = Value / 1000
   end,
})

-- Zone Priority Dropdown
local PriorityDropdown = SettingsTab:CreateDropdown({
   Name = "🎯 Target Priority",
   Options = {"Special > Gold > Normal", "Gold > Special > Normal", "Only Special", "Only Gold"},
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

-- Wait For Perfect Hit Toggle
local WaitPerfectToggle = SettingsTab:CreateToggle({
   Name = "⏰ Wait for Perfect Hit",
   CurrentValue = true,
   Flag = "WaitPerfect",
   Callback = function(Value)
       -- Đợi thời điểm hoàn hảo
   end,
})

-- Stats Tab
StatsTab:CreateSection("Session Statistics")

local HitsLabel = StatsTab:CreateLabel("🎯 Total Hits: 0", 4483362458, Color3.fromRGB(255, 255, 255), false)
local MissesLabel = StatsTab:CreateLabel("❌ Total Misses: 0", 4483362458, Color3.fromRGB(255, 255, 255), false) 
local GamesLabel = StatsTab:CreateLabel("🎮 Games Played: 0", 4483362458, Color3.fromRGB(255, 255, 255), false)
local SpecialLabel = StatsTab:CreateLabel("⭐ Special Hits: 0", 4483362458, Color3.fromRGB(255, 255, 255), false)
local GoldLabel = StatsTab:CreateLabel("🥇 Gold Hits: 0", 4483362458, Color3.fromRGB(255, 255, 255), false)
local AccuracyLabel = StatsTab:CreateLabel("📈 Accuracy: 0%", 4483362458, Color3.fromRGB(255, 255, 255), false)

-- Debug Tab
DebugTab:CreateSection("Debug Information")
local DebugMinigameLabel = DebugTab:CreateLabel("🎮 Minigame: Searching...", 4483362458, Color3.fromRGB(255, 255, 255), false)
local DebugSliderLabel = DebugTab:CreateLabel("🎚️ Slider: Not Found", 4483362458, Color3.fromRGB(255, 255, 255), false)
local DebugZoneLabel = DebugTab:CreateLabel("🎯 Zones: 0 found", 4483362458, Color3.fromRGB(255, 255, 255), false) 
local DebugPositionLabel = DebugTab:CreateLabel("📍 Position: Waiting...", 4483362458, Color3.fromRGB(255, 255, 255), false)
local DebugTimingLabel = DebugTab:CreateLabel("⏰ Last Click: Never", 4483362458, Color3.fromRGB(255, 255, 255), false)

-- Reset Stats Button
local ResetStatsButton = StatsTab:CreateButton({
   Name = "🔄 Reset Statistics", 
   Callback = function()
       stats = {totalHits = 0, totalMisses = 0, totalGames = 0, specialHits = 0, goldHits = 0}
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
local function updateLabel(label, text)
    if label and label.Text then
        label.Text = text
    end
end

local function updateStatsDisplay()
    updateLabel(HitsLabel, string.format("🎯 Total Hits: %d", stats.totalHits))
    updateLabel(MissesLabel, string.format("❌ Total Misses: %d", stats.totalMisses))
    updateLabel(GamesLabel, string.format("🎮 Games Played: %d", stats.totalGames))
    updateLabel(SpecialLabel, string.format("⭐ Special Hits: %d", stats.specialHits))
    updateLabel(GoldLabel, string.format("🥇 Gold Hits: %d", stats.goldHits))
    
    local totalAttempts = stats.totalHits + stats.totalMisses
    local accuracy = totalAttempts > 0 and math.floor((stats.totalHits / totalAttempts) * 100) or 0
    updateLabel(AccuracyLabel, string.format("📈 Accuracy: %d%%", accuracy))
end

local function findMiningMinigame()
    -- Đường dẫn chính xác theo user cung cấp
    local success, result = pcall(function()
        local playerGui = LocalPlayer:WaitForChild("PlayerGui", 1)
        local ui = playerGui:FindFirstChild("UI")
        if not ui then return nil end
        
        local gameplay = ui:FindFirstChild("Gameplay")  
        if not gameplay then return nil end
        
        -- Đúng tên: MiningMinigame (không phải MinigameUI)
        local minigame = gameplay:FindFirstChild("MiningMinigame")
        
        if minigame and minigame:IsA("CanvasGroup") and minigame.Visible then
            if not minigameActive then
                minigameActive = true
                updateLabel(MinigameStatusLabel, "📱 Minigame: Just Started")
                updateLabel(DebugMinigameLabel, "🎮 Minigame: Active (CanvasGroup)")
            else
                updateLabel(MinigameStatusLabel, "📱 Minigame: Running")
                updateLabel(DebugMinigameLabel, "🎮 Minigame: Running (CanvasGroup)")
            end
            return minigame
        else
            if minigameActive then
                minigameActive = false
                updateLabel(MinigameStatusLabel, "📱 Minigame: Just Ended")
                updateLabel(DebugMinigameLabel, "🎮 Minigame: Ended")
            else
                updateLabel(MinigameStatusLabel, "📱 Minigame: Not Found")
                updateLabel(DebugMinigameLabel, "🎮 Minigame: Searching...")
            end
            return nil
        end
    end)
    
    if success then
        updateLabel(DebugMinigameLabel, "🎮 Minigame: Error - " .. tostring(result))
        return result
    else
        updateLabel(DebugMinigameLabel, "🎮 Minigame: Error - " .. tostring(result))
        return nil
    end
end

local function findSliderAndZones(minigame)
    if not minigame then 
        DebugSliderLabel:Set("🎚️ Slider: No minigame")
        DebugZoneLabel:Set("🎯 Zones: No minigame")
        return nil, {}
    end
    
    local success, result = pcall(function()
        local bar = minigame:FindFirstChild("Bar")
        if not bar then 
            DebugSliderLabel:Set("🎚️ Slider: No Bar found")
            DebugZoneLabel:Set("🎯 Zones: No Bar found")
            return nil, {}
        end
        
        -- Tìm Slider
        local slider = bar:FindFirstChild("Slider")
        if not slider or not slider.Visible then
            DebugSliderLabel:Set("🎚️ Slider: Not found or invisible")
        else
            DebugSliderLabel:Set(string.format("🎚️ Slider: Found (%.0f, %.0f)", 
                slider.AbsolutePosition.X, slider.AbsolutePosition.Y))
        end
        
        -- Tìm Zone container
        local zoneContainer = bar:FindFirstChild("Zone")
        if not zoneContainer then
            DebugZoneLabel:Set("🎯 Zones: No Zone container")
            return slider, {}
        end
        
        -- Tìm các zone con trong container
        local zones = {}
        for _, child in pairs(zoneContainer:GetChildren()) do
            if child:IsA("GuiObject") and child.Visible and child.BackgroundTransparency < 0.9 then
                local priority = getZonePriority(child)
                table.insert(zones, {
                    frame = child,
                    position = child.AbsolutePosition.X,
                    size = child.AbsoluteSize.X,
                    priority = priority,
                    color = child.BackgroundColor3,
                    name = child.Name or "Unknown"
                })
            end
        end
        
        DebugZoneLabel:Set(string.format("🎯 Zones: %d found in container", #zones))
        return slider, zones
    end)
    
    if success then
        return result
    else
        DebugSliderLabel:Set("🎚️ Slider: Error - " .. tostring(result))
        DebugZoneLabel:Set("🎯 Zones: Error - " .. tostring(result))
        return nil, {}
    end
end

local function getZonePriority(zone)
    local color = zone.BackgroundColor3
    local r, g, b = math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255)
    
    -- Kiểm tra màu chính xác hơn với tolerance
    local function colorMatch(targetR, targetG, targetB, tolerance)
        tolerance = tolerance or 20
        return math.abs(r - targetR) <= tolerance and 
               math.abs(g - targetG) <= tolerance and 
               math.abs(b - targetB) <= tolerance
    end
    
    -- Màu cam/đỏ - Special zone (priority cao nhất)
    if colorMatch(255, 140, 64) or colorMatch(255, 100, 100) or colorMatch(255, 69, 0) then
        return 3, "Special"
    -- Màu vàng - Gold zone
    elseif colorMatch(255, 227, 114) or colorMatch(255, 215, 0) or colorMatch(255, 255, 0) then
        return 2, "Gold" 
    -- Màu tím/xanh - Normal zone
    elseif colorMatch(224, 175, 255) or colorMatch(147, 112, 219) or colorMatch(138, 43, 226) then
        return 1, "Normal"
    else
        -- Log màu không xác định để debug
        return 1, string.format("Unknown(%d,%d,%d)", r, g, b)
    end
end

local function isSliderInZone(slider, zone)
    if not slider or not zone or not slider.Visible or not zone.frame.Visible then 
        return false 
    end
    
    local sliderPos = slider.AbsolutePosition.X
    local sliderSize = slider.AbsoluteSize.X
    local sliderCenter = sliderPos + sliderSize/2
    
    local zonePos = zone.frame.AbsolutePosition.X
    local zoneSize = zone.frame.AbsoluteSize.X
    local zoneStart = zonePos
    local zoneEnd = zonePos + zoneSize
    
    -- Kiểm tra với margin nhỏ để chính xác
    local margin = 3
    local isInside = sliderCenter >= (zoneStart + margin) and sliderCenter <= (zoneEnd - margin)
    
    if isInside then
        DebugPositionLabel:Set(string.format("📍 In %s Zone! Slider: %.0f, Zone: %.0f-%.0f", 
            zone.name or "Unknown", sliderCenter, zoneStart, zoneEnd))
    else
        DebugPositionLabel:Set(string.format("📍 Outside zones. Slider: %.0f", sliderCenter))
    end
    
    return isInside
end

local function detectOptimalHit(minigame)
    local slider, zones = findSliderAndZones(minigame)
    
    if not slider or #zones == 0 then
        return false, nil
    end
    
    local prioritySetting = PriorityDropdown.CurrentOption[1]
    local bestZone = nil
    local highestPriority = 0
    
    -- Tìm zone tốt nhất dựa trên priority setting
    for _, zone in pairs(zones) do
        if isSliderInZone(slider, zone) then
            local shouldTake = false
            
            if prioritySetting == "Special > Gold > Normal" then
                shouldTake = zone.priority > highestPriority
            elseif prioritySetting == "Gold > Special > Normal" then
                -- Ưu tiên Gold trước, trừ khi đã có Special
                shouldTake = (zone.priority == 2 and highestPriority < 2) or 
                           (zone.priority > highestPriority and highestPriority ~= 2)
            elseif prioritySetting == "Only Special" then
                shouldTake = zone.priority == 3
            elseif prioritySetting == "Only Gold" then
                shouldTake = zone.priority == 2
            end
            
            if shouldTake then
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
        DebugTimingLabel:Set("⏰ Last Click: Miss (accuracy)")
        updateStatsDisplay()
        return false
    end
    
    local clickX, clickY
    
    if zone and zone.frame and zone.frame.Visible then
        -- Lấy vị trí zone để click
        local zonePos = zone.frame.AbsolutePosition
        local zoneSize = zone.frame.AbsoluteSize
        
        if PrecisionToggle.CurrentValue then
            -- Precision mode: click chính giữa zone
            clickX = zonePos.X + zoneSize.X/2
            clickY = zonePos.Y + zoneSize.Y/2
        else
            -- Random mode: click random trong zone với margin
            local margin = math.min(5, zoneSize.X/4, zoneSize.Y/4)
            clickX = zonePos.X + margin + math.random(0, zoneSize.X - 2*margin)
            clickY = zonePos.Y + margin + math.random(0, zoneSize.Y - 2*margin)
        end
    else
        -- Fallback: click center screen
        local viewportSize = workspace.CurrentCamera.ViewportSize
        clickX = viewportSize.X/2
        clickY = viewportSize.Y/2
    end
    
    -- Thực hiện click an toàn
    local clickSuccess = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 1)
        wait(0.01)
        VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 1)
    end)
    
    if not clickSuccess then
        DebugTimingLabel:Set("⏰ Last Click: Failed (error)")
        return false
    end
    
    -- Update stats
    stats.totalHits = stats.totalHits + 1
    if zone then
        if zone.priority == 3 then
            stats.specialHits = stats.specialHits + 1
        elseif zone.priority == 2 then
            stats.goldHits = stats.goldHits + 1
        end
    end
    
    lastClickTime = currentTime
    DebugTimingLabel:Set(string.format("⏰ Last Click: Success (%s)", 
        zone and zone.name or "Unknown"))
    updateStatsDisplay()
    
    return true
end

function StartAutoMining()
    if isAutoRunning then return end
    
    isAutoRunning = true
    StatusLabel:Set("🟢 Status: Running")
    stats.totalGames = stats.totalGames + 1
    lastClickTime = 0
    
    Rayfield:Notify({
        Title = "Auto Mining Started",
        Content = "Bot is now running with correct path detection!",
        Duration = 3,
        Image = "play",
    })
    
    connection = RunService.Heartbeat:Connect(function()
        if not isAutoRunning then return end
        
        local minigame = findMiningMinigame()
        if not minigame then return end
        
        -- Đợi minigame load đầy đủ
        if not minigameActive then
            return
        end
        
        local canHit, zone = detectOptimalHit(minigame)
        
        -- Chỉ click khi tìm được zone phù hợp
        if canHit and zone then
            -- Nếu bật Wait for Perfect, đợi slider gần center của zone
            if WaitPerfectToggle.CurrentValue then
                local slider, _ = findSliderAndZones(minigame)
                if slider then
                    local sliderCenter = slider.AbsolutePosition.X + slider.AbsoluteSize.X/2
                    local zoneCenter = zone.frame.AbsolutePosition.X + zone.frame.AbsoluteSize.X/2
                    local distance = math.abs(sliderCenter - zoneCenter)
                    local threshold = zone.frame.AbsoluteSize.X / 4 -- 25% của zone size
                    
                    if distance > threshold then
                        return -- Đợi gần center hơn
                    end
                end
            end
            
            -- Click trong thread riêng
            spawn(function()
                local success = safeClick(zone)
                if success then
                    wait(0.1) -- Đợi ngắn sau khi click
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
    DebugMinigameLabel:Set("🎮 Minigame: Stopped by user")
    
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
        local success, error = pcall(function()
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
                        Image = 4483362458,
                    })
                    return true
                end
                return false
            end
        end)
        
        if not success then
            Rayfield:Notify({
                Title = "Auto Accept Setup Failed",
                Content = "Could not setup auto accept: " .. tostring(error),
                Duration = 4,
                Image = 4483362458,
            })
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
        Content = "Fixed all Rayfield label update errors!",
        Duration = 4,
        Image = 4483362458,
    })
end)

-- Cleanup và monitoring
Players.PlayerRemoving:Connect(function(player)
    if player == LocalPlayer then
        StopAutoMining()
    end
end)

-- Background monitor
spawn(function()
    while true do
        wait(2)
        if isAutoRunning and not minigameActive then
            local timeout = 5
            local startTime = tick()
            while tick() - startTime < timeout do
                if findMiningMinigame() then
                    break
                end
                wait(0.5)
            end
            
            if tick() - startTime >= timeout and isAutoRunning then
                wait(1)
                if not findMiningMinigame() then
                    minigameActive = false
                end
            end
        end
    end
end)lower(), "mining") then
                    Rayfield:Notify({
                        Title = "Auto Accepted",
                        Content = "Mining prompt accepted automatically!",
                        Duration = 2,
                        Image = "check",
                    })
                    return true
                end
                return false
            end
        end)
        
        if not success then
            Rayfield:Notify({
                Title = "Auto Accept Setup Failed",
                Content = "Could not setup auto accept: " .. tostring(error),
                Duration = 4,
                Image = "x",
            })
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
        Title = "Mining Tool Loaded (Fixed Paths)",
        Content = "Using correct MiningMinigame path structure!",
        Duration = 4,
        Image = "pickaxe",
    })
end)

-- Cleanup và monitoring
Players.PlayerRemoving:Connect(function(player)
    if player == LocalPlayer then
        StopAutoMining()
    end
end)

-- Background monitor để cleanup
spawn(function()
    while true do
        wait(2)
        if isAutoRunning and not minigameActive then
            -- Tự động dừng nếu không tìm được minigame trong 5 giây
            local timeout = 5
            local startTime = tick()
            while tick() - startTime < timeout do
                if findMiningMinigame() then
                    break
                end
                wait(0.5)
            end
            
            if tick() - startTime >= timeout and isAutoRunning then
                -- Timeout - có thể minigame đã kết thúc
                wait(1) -- Đợi thêm 1 giây
                if not findMiningMinigame() then
                    -- Vẫn không tìm thấy, reset trạng thái
                    minigameActive = false
                end
            end
        end
    end
end)