-- Auto Key Press Script với 2 tab riêng biệt
-- Tải Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Tạo Window
local Window = Rayfield:CreateWindow({
   Name = "Auto Key Press Pro",
   Icon = 0,
   LoadingTitle = "Auto Key Press Tool",
   LoadingSubtitle = "Công cụ ấn phím chuyên nghiệp",
   ShowText = "Auto Key Press",
   Theme = "Default",
   ToggleUIKeybind = "K",
   
   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false,
   
   ConfigurationSaving = {
      Enabled = true,
      FolderName = nil,
      FileName = "AutoKeyPressPro"
   },
})

-- Services
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Variables cho Tab 1 (Ấn 1 lần)
local singleMode = {
    isRunning = false,
    selectedKeys = {},
    currentKeyIndex = 1,
    cycleConnection = nil,
    keyToggles = {}
}

-- Variables cho Tab 2 (Ấn liên tục)
local continuousMode = {
    isRunning = false,
    selectedKeys = {},
    currentKeyIndex = 1,
    cycleConnection = nil,
    keyToggles = {},
    keyDuration = 2
}

-- ===== TAB 1: ẤN 1 LẦN =====
local SingleTab = Window:CreateTab("Ấn 1 lần", "mouse-pointer-click")

-- Section điều khiển Tab 1
local SingleControlSection = SingleTab:CreateSection("Điều khiển - Ấn 1 lần mỗi phím")

-- Toggle chính cho Tab 1
local SingleMainToggle = SingleTab:CreateToggle({
    Name = "Bật chu kỳ ấn 1 lần",
    CurrentValue = false,
    Flag = "SingleMainToggle",
    Callback = function(Value)
        singleMode.isRunning = Value
        
        if Value then
            if #singleMode.selectedKeys > 0 then
                startSingleCycle()
                Rayfield:Notify({
                    Title = "Chu kỳ ấn 1 lần đã bắt đầu",
                    Content = "Phím: " .. table.concat(singleMode.selectedKeys, " → "),
                    Duration = 3,
                    Image = "play-circle"
                })
            else
                singleMode.isRunning = false
                Rayfield:Notify({
                    Title = "Lỗi",
                    Content = "Vui lòng chọn ít nhất 1 phím!",
                    Duration = 3,
                    Image = "alert-circle"
                })
            end
        else
            stopSingleCycle()
            Rayfield:Notify({
                Title = "Đã dừng chu kỳ ấn 1 lần",
                Content = "Chu kỳ đã được dừng",
                Duration = 2,
                Image = "pause-circle"
            })
        end
    end,
})

-- Slider tốc độ chuyển phím cho Tab 1
local SingleSpeedSlider = SingleTab:CreateSlider({
    Name = "Tốc độ chuyển phím (giây)",
    Range = {0.1, 3},
    Increment = 0.1,
    Suffix = "s",
    CurrentValue = 0.5,
    Flag = "SingleSpeedSlider",
    Callback = function(Value)
        singleMode.switchDelay = Value
        Rayfield:Notify({
            Title = "Tốc độ đã thay đổi",
            Content = "Chuyển phím sau " .. Value .. " giây",
            Duration = 2,
            Image = "zap"
        })
    end,
})

-- Section chọn phím cho Tab 1
local SingleKeySection = SingleTab:CreateSection("Chọn phím cho chu kỳ ấn 1 lần")

-- Tạo toggle cho từng chữ cái A-Z (Tab 1)
for i = 1, 26 do
    local letter = string.char(64 + i)
    
    singleMode.keyToggles[letter] = SingleTab:CreateToggle({
        Name = "Phím " .. letter,
        CurrentValue = false,
        Flag = "Single" .. letter,
        Callback = function(Value)
            if Value then
                if not table.find(singleMode.selectedKeys, letter) then
                    table.insert(singleMode.selectedKeys, letter)
                    table.sort(singleMode.selectedKeys)
                end
            else
                local index = table.find(singleMode.selectedKeys, letter)
                if index then
                    table.remove(singleMode.selectedKeys, index)
                end
            end
        end,
    })
end

-- Buttons điều khiển nhanh Tab 1
local SingleQuickSection = SingleTab:CreateSection("Điều khiển nhanh")

local SingleSelectAllButton = SingleTab:CreateButton({
    Name = "Chọn tất cả A-Z",
    Callback = function()
        singleMode.selectedKeys = {}
        for i = 1, 26 do
            local letter = string.char(64 + i)
            table.insert(singleMode.selectedKeys, letter)
        end
        Rayfield:Notify({
            Title = "Đã chọn tất cả",
            Content = "26 phím A-Z đã được chọn",
            Duration = 2,
            Image = "check-circle"
        })
    end,
})

local SingleClearButton = SingleTab:CreateButton({
    Name = "Bỏ chọn tất cả",
    Callback = function()
        singleMode.selectedKeys = {}
        singleMode.isRunning = false
        stopSingleCycle()
        Rayfield:Notify({
            Title = "Đã xóa tất cả",
            Content = "Danh sách phím đã được xóa",
            Duration = 2,
            Image = "x-circle"
        })
    end,
})

-- ===== TAB 2: ẤN LIÊN TỤC =====
local ContinuousTab = Window:CreateTab("Ấn liên tục", "zap")

-- Section điều khiển Tab 2
local ContinuousControlSection = ContinuousTab:CreateSection("Điều khiển - Ấn liên tục mỗi phím")

-- Toggle chính cho Tab 2
local ContinuousMainToggle = ContinuousTab:CreateToggle({
    Name = "Bật chu kỳ ấn liên tục",
    CurrentValue = false,
    Flag = "ContinuousMainToggle",
    Callback = function(Value)
        continuousMode.isRunning = Value
        
        if Value then
            if #continuousMode.selectedKeys > 0 then
                startContinuousCycle()
                Rayfield:Notify({
                    Title = "Chu kỳ ấn liên tục đã bắt đầu",
                    Content = "Phím: " .. table.concat(continuousMode.selectedKeys, " → "),
                    Duration = 3,
                    Image = "play-circle"
                })
            else
                continuousMode.isRunning = false
                Rayfield:Notify({
                    Title = "Lỗi",
                    Content = "Vui lòng chọn ít nhất 1 phím!",
                    Duration = 3,
                    Image = "alert-circle"
                })
            end
        else
            stopContinuousCycle()
            Rayfield:Notify({
                Title = "Đã dừng chu kỳ ấn liên tục",
                Content = "Chu kỳ đã được dừng",
                Duration = 2,
                Image = "pause-circle"
            })
        end
    end,
})

-- Slider thời gian ấn cho Tab 2
local ContinuousDurationSlider = ContinuousTab:CreateSlider({
    Name = "Thời gian ấn mỗi phím (giây)",
    Range = {1, 10},
    Increment = 1,
    Suffix = "s",
    CurrentValue = 2,
    Flag = "ContinuousDurationSlider",
    Callback = function(Value)
        continuousMode.keyDuration = Value
        Rayfield:Notify({
            Title = "Thời gian đã thay đổi",
            Content = "Mỗi phím ấn liên tục " .. Value .. " giây",
            Duration = 2,
            Image = "clock"
        })
    end,
})

-- Section chọn phím cho Tab 2
local ContinuousKeySection = ContinuousTab:CreateSection("Chọn phím cho chu kỳ ấn liên tục")

-- Tạo toggle cho từng chữ cái A-Z (Tab 2)
for i = 1, 26 do
    local letter = string.char(64 + i)
    
    continuousMode.keyToggles[letter] = ContinuousTab:CreateToggle({
        Name = "Phím " .. letter,
        CurrentValue = false,
        Flag = "Continuous" .. letter,
        Callback = function(Value)
            if Value then
                if not table.find(continuousMode.selectedKeys, letter) then
                    table.insert(continuousMode.selectedKeys, letter)
                    table.sort(continuousMode.selectedKeys)
                end
            else
                local index = table.find(continuousMode.selectedKeys, letter)
                if index then
                    table.remove(continuousMode.selectedKeys, index)
                end
            end
        end,
    })
end

-- Buttons điều khiển nhanh Tab 2
local ContinuousQuickSection = ContinuousTab:CreateSection("Điều khiển nhanh")

local ContinuousSelectAllButton = ContinuousTab:CreateButton({
    Name = "Chọn tất cả A-Z",
    Callback = function()
        continuousMode.selectedKeys = {}
        for i = 1, 26 do
            local letter = string.char(64 + i)
            table.insert(continuousMode.selectedKeys, letter)
        end
        Rayfield:Notify({
            Title = "Đã chọn tất cả",
            Content = "26 phím A-Z đã được chọn",
            Duration = 2,
            Image = "check-circle"
        })
    end,
})

local ContinuousClearButton = ContinuousTab:CreateButton({
    Name = "Bỏ chọn tất cả",
    Callback = function()
        continuousMode.selectedKeys = {}
        continuousMode.isRunning = false
        stopContinuousCycle()
        Rayfield:Notify({
            Title = "Đã xóa tất cả",
            Content = "Danh sách phím đã được xóa",
            Duration = 2,
            Image = "x-circle"
        })
    end,
})

-- ===== TAB TRẠNG THÁI =====
local StatusTab = Window:CreateTab("Trạng thái", "activity")

local StatusSection = StatusTab:CreateSection("Thông tin hoạt động")

-- Labels hiển thị trạng thái
local SingleStatusLabel = StatusTab:CreateLabel("Tab 1 - Ấn 1 lần: Dừng", "mouse-pointer-click", Color3.fromRGB(255, 100, 100))
local ContinuousStatusLabel = StatusTab:CreateLabel("Tab 2 - Ấn liên tục: Dừng", "zap", Color3.fromRGB(255, 100, 100))

-- Cập nhật trạng thái liên tục
spawn(function()
    while true do
        wait(1)
        
        -- Cập nhật trạng thái Tab 1
        if singleMode.isRunning and #singleMode.selectedKeys > 0 then
            local currentKey = singleMode.selectedKeys[singleMode.currentKeyIndex] or "N/A"
            SingleStatusLabel:Set("Tab 1 - Đang ấn: " .. currentKey .. " (" .. singleMode.currentKeyIndex .. "/" .. #singleMode.selectedKeys .. ")", "mouse-pointer-click", Color3.fromRGB(100, 255, 100))
        else
            SingleStatusLabel:Set("Tab 1 - Ấn 1 lần: Dừng", "mouse-pointer-click", Color3.fromRGB(255, 100, 100))
        end
        
        -- Cập nhật trạng thái Tab 2
        if continuousMode.isRunning and #continuousMode.selectedKeys > 0 then
            local currentKey = continuousMode.selectedKeys[continuousMode.currentKeyIndex] or "N/A"
            ContinuousStatusLabel:Set("Tab 2 - Đang ấn: " .. currentKey .. " (" .. continuousMode.currentKeyIndex .. "/" .. #continuousMode.selectedKeys .. ")", "zap", Color3.fromRGB(100, 255, 100))
        else
            ContinuousStatusLabel:Set("Tab 2 - Ấn liên tục: Dừng", "zap", Color3.fromRGB(255, 100, 100))
        end
    end
end)

-- ===== FUNCTIONS =====

-- Hàm cho Tab 1 (Ấn 1 lần)
function startSingleCycle()
    singleMode.currentKeyIndex = 1
    
    singleMode.cycleConnection = spawn(function()
        while singleMode.isRunning and #singleMode.selectedKeys > 0 do
            local currentKey = singleMode.selectedKeys[singleMode.currentKeyIndex]
            
            -- Ấn phím 1 lần
            game:GetService("VirtualInputManager"):SendKeyEvent(true, Enum.KeyCode[currentKey], false, game)
            wait(0.05)
            game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode[currentKey], false, game)
            
            -- Chuyển sang phím tiếp theo
            singleMode.currentKeyIndex = singleMode.currentKeyIndex + 1
            if singleMode.currentKeyIndex > #singleMode.selectedKeys then
                singleMode.currentKeyIndex = 1
            end
            
            -- Chờ trước khi ấn phím tiếp theo
            wait(singleMode.switchDelay or 0.5)
        end
    end)
end

function stopSingleCycle()
    if singleMode.cycleConnection then
        singleMode.cycleConnection = nil
    end
    singleMode.currentKeyIndex = 1
end

-- Hàm cho Tab 2 (Ấn liên tục)
function startContinuousCycle()
    continuousMode.currentKeyIndex = 1
    
    continuousMode.cycleConnection = spawn(function()
        while continuousMode.isRunning and #continuousMode.selectedKeys > 0 do
            local currentKey = continuousMode.selectedKeys[continuousMode.currentKeyIndex]
            
            -- Ấn phím liên tục trong thời gian quy định
            local startTime = tick()
            while continuousMode.isRunning and (tick() - startTime) < continuousMode.keyDuration do
                game:GetService("VirtualInputManager"):SendKeyEvent(true, Enum.KeyCode[currentKey], false, game)
                wait(0.05)
                game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode[currentKey], false, game)
                wait(0.1)
            end
            
            -- Chuyển sang phím tiếp theo
            continuousMode.currentKeyIndex = continuousMode.currentKeyIndex + 1
            if continuousMode.currentKeyIndex > #continuousMode.selectedKeys then
                continuousMode.currentKeyIndex = 1
            end
            
            -- Nghỉ ngắn giữa các phím
            wait(0.2)
        end
    end)
end

function stopContinuousCycle()
    if continuousMode.cycleConnection then
        continuousMode.cycleConnection = nil
    end
    continuousMode.currentKeyIndex = 1
end

-- ===== TAB HƯỚNG DẪN =====
local InfoTab = Window:CreateTab("Hướng dẫn", "info")

local InfoSection = InfoTab:CreateSection("Cách sử dụng")

local Tab1Info = InfoTab:CreateParagraph({
    Title = "Tab 1: Ấn 1 lần",
    Content = "• Ấn từng phím 1 lần rồi chuyển sang phím tiếp theo\n• Điều chỉnh tốc độ chuyển phím bằng slider\n• VD: A (1 lần) → B (1 lần) → C (1 lần) → quay lại A\n• Phù hợp cho game cần ấn phím nhẹ nhàng"
})

local Tab2Info = InfoTab:CreateParagraph({
    Title = "Tab 2: Ấn liên tục",
    Content = "• Ấn từng phím liên tục trong X giây rồi chuyển tiếp\n• Điều chỉnh thời gian ấn mỗi phím\n• VD: A (ấn liên tục 3s) → B (ấn liên tục 3s) → C (ấn liên tục 3s)\n• Phù hợp cho game cần giữ phím"
})

local GeneralInfo = InfoTab:CreateParagraph({
    Title = "Thông tin chung",
    Content = "• Hai tab hoạt động độc lập với nhau\n• Có thể chạy đồng thời cả 2 tab\n• Mỗi tab có danh sách phím riêng\n• Tab Trạng thái hiển thị thông tin real-time\n• Nhấn K để ẩn/hiện GUI"
})

-- Cleanup
game.Players.LocalPlayer.AncestryChanged:Connect(function()
    singleMode.isRunning = false
    continuousMode.isRunning = false
    stopSingleCycle()
    stopContinuousCycle()
end)

-- Load configuration
Rayfield:LoadConfiguration()