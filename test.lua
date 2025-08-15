-- Auto Key Press Script với Rayfield GUI
-- Tải Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Tạo Window
local Window = Rayfield:CreateWindow({
   Name = "Auto Key Press",
   Icon = 0,
   LoadingTitle = "Auto Key Press Tool",
   LoadingSubtitle = "Công cụ ấn phím tự động",
   ShowText = "Auto Key Press",
   Theme = "Default",
   ToggleUIKeybind = "K",
   
   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false,
   
   ConfigurationSaving = {
      Enabled = true,
      FolderName = nil,
      FileName = "AutoKeyPress"
   },
})

-- Services
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Variables
local keyPressConnections = {}
local isEnabled = {}

-- Tạo Tab chính
local MainTab = Window:CreateTab("Key Press", "keyboard")

-- Section cho các chữ cái
local LetterSection = MainTab:CreateSection("Chữ cái A-Z")

-- Tạo toggle cho từng chữ cái A-Z
local letters = {}
for i = 1, 26 do
    local letter = string.char(64 + i) -- A=65, B=66, etc.
    letters[letter] = false
    
    local toggle = MainTab:CreateToggle({
        Name = "Auto Press " .. letter,
        CurrentValue = false,
        Flag = "Toggle" .. letter,
        Callback = function(Value)
            letters[letter] = Value
            isEnabled[letter] = Value
            
            if Value then
                -- Bắt đầu ấn phím
                keyPressConnections[letter] = RunService.Heartbeat:Connect(function()
                    if isEnabled[letter] then
                        -- Mô phỏng ấn phím
                        game:GetService("VirtualInputManager"):SendKeyEvent(true, Enum.KeyCode[letter], false, game)
                        wait(0.1) -- Delay nhỏ giữa các lần ấn
                        game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode[letter], false, game)
                    end
                end)
                
                Rayfield:Notify({
                    Title = "Đã bật",
                    Content = "Auto press " .. letter .. " đã được bật",
                    Duration = 2,
                    Image = "check"
                })
            else
                -- Dừng ấn phím
                if keyPressConnections[letter] then
                    keyPressConnections[letter]:Disconnect()
                    keyPressConnections[letter] = nil
                end
                
                Rayfield:Notify({
                    Title = "Đã tắt",
                    Content = "Auto press " .. letter .. " đã được tắt",
                    Duration = 2,
                    Image = "x"
                })
            end
        end,
    })
end

-- Section cho điều khiển
local ControlSection = MainTab:CreateSection("Điều khiển tổng quát")

-- Slider để điều chỉnh tốc độ
local speedMultiplier = 1
local SpeedSlider = MainTab:CreateSlider({
    Name = "Tốc độ ấn phím",
    Range = {0.1, 2},
    Increment = 0.1,
    Suffix = "x",
    CurrentValue = 1,
    Flag = "SpeedSlider",
    Callback = function(Value)
        speedMultiplier = Value
        Rayfield:Notify({
            Title = "Tốc độ đã thay đổi",
            Content = "Tốc độ mới: " .. Value .. "x",
            Duration = 2,
            Image = "zap"
        })
    end,
})

-- Button để bật tất cả
local EnableAllButton = MainTab:CreateButton({
    Name = "Bật tất cả phím",
    Callback = function()
        for letter, _ in pairs(letters) do
            if not isEnabled[letter] then
                -- Trigger toggle
                letters[letter] = true
                isEnabled[letter] = true
                
                keyPressConnections[letter] = RunService.Heartbeat:Connect(function()
                    if isEnabled[letter] then
                        game:GetService("VirtualInputManager"):SendKeyEvent(true, Enum.KeyCode[letter], false, game)
                        wait(0.1 / speedMultiplier)
                        game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode[letter], false, game)
                    end
                end)
            end
        end
        
        Rayfield:Notify({
            Title = "Đã bật tất cả",
            Content = "Tất cả phím đã được bật",
            Duration = 3,
            Image = "check-circle"
        })
    end,
})

-- Button để tắt tất cả
local DisableAllButton = MainTab:CreateButton({
    Name = "Tắt tất cả phím",
    Callback = function()
        for letter, connection in pairs(keyPressConnections) do
            if connection then
                connection:Disconnect()
            end
        end
        
        keyPressConnections = {}
        for letter, _ in pairs(letters) do
            letters[letter] = false
            isEnabled[letter] = false
        end
        
        Rayfield:Notify({
            Title = "Đã tắt tất cả",
            Content = "Tất cả phím đã được tắt",
            Duration = 3,
            Image = "x-circle"
        })
    end,
})

-- Tab thông tin
local InfoTab = Window:CreateTab("Thông tin", "info")

local InfoSection = InfoTab:CreateSection("Hướng dẫn sử dụng")

local InfoParagraph = InfoTab:CreateParagraph({
    Title = "Cách sử dụng",
    Content = "1. Chọn các chữ cái bạn muốn ấn tự động\n2. Điều chỉnh tốc độ bằng slider\n3. Sử dụng nút 'Bật/Tắt tất cả' để điều khiển nhanh\n4. Nhấn K để ẩn/hiện GUI"
})

local WarningParagraph = InfoTab:CreateParagraph({
    Title = "Lưu ý",
    Content = "- Chỉ sử dụng trong các game cho phép\n- Có thể bị phát hiện bởi anti-cheat\n- Sử dụng có trách nhiệm"
})

-- Cleanup khi script kết thúc
game.Players.LocalPlayer.AncestryChanged:Connect(function()
    for letter, connection in pairs(keyPressConnections) do
        if connection then
            connection:Disconnect()
        end
    end
end)

-- Load configuration
Rayfield:LoadConfiguration()