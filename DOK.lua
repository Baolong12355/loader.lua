-- Load WindUI
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- Create Window
local Window = WindUI:CreateWindow({
    Title = "D.O.K (Drone Over Kill)",
    Author = "D.O.K PANEL",
    Folder = "DOK",
    Size = UDim2.fromOffset(580, 460),
    Transparent = false,
    Theme = "Dark",
    Resizable = true,
})

-- Configuration values
local Config = {
    DefaultShotInterval = 0.001,
    ReloadTime = 0.001,
    CurrentFirerateMultiplier = 0.001,
    DefaultSpreadDegrees = 0,
    Enabled = false
}

-- Main Tab
local MainTab = Window:Tab({
    Title = "Cài Đặt",
})

-- Weapon Parameters Section
MainTab:Section({
    Title = "Thông Số Vũ Khí",
})

local ShotIntervalInput = MainTab:Input({
    Title = "Khoảng Cách Bắn (Shot Interval)",
    Desc = "Thời gian giữa các phát bắn",
    Value = tostring(Config.DefaultShotInterval),
    Placeholder = "Nhập số (ví dụ: 0.001)",
    Callback = function(value)
        local num = tonumber(value)
        if num then
            Config.DefaultShotInterval = num
            WindUI:Notify({
                Title = "Đã Cập Nhật",
                Content = "Khoảng cách bắn: " .. value,
                Duration = 2,
            })
        else
            WindUI:Notify({
                Title = "Lỗi",
                Content = "Số không hợp lệ",
                Duration = 3,
            })
        end
    end
})

local ReloadTimeInput = MainTab:Input({
    Title = "Thời Gian Nạp Đạn (Reload Time)",
    Desc = "Thời gian để nạp đạn",
    Value = tostring(Config.ReloadTime),
    Placeholder = "Nhập số (ví dụ: 0.001)",
    Callback = function(value)
        local num = tonumber(value)
        if num then
            Config.ReloadTime = num
            WindUI:Notify({
                Title = "Đã Cập Nhật",
                Content = "Thời gian nạp đạn: " .. value,
                Duration = 2,
            })
        else
            WindUI:Notify({
                Title = "Lỗi",
                Content = "Số không hợp lệ",
                Duration = 3,
            })
        end
    end
})

local FirerateInput = MainTab:Input({
    Title = "Hệ Số Tốc Độ Bắn (Firerate)",
    Desc = "Hệ số nhân tốc độ bắn",
    Value = tostring(Config.CurrentFirerateMultiplier),
    Placeholder = "Nhập số (ví dụ: 0.001)",
    Callback = function(value)
        local num = tonumber(value)
        if num then
            Config.CurrentFirerateMultiplier = num
            WindUI:Notify({
                Title = "Đã Cập Nhật",
                Content = "Hệ số tốc độ bắn: " .. value,
                Duration = 2,
            })
        else
            WindUI:Notify({
                Title = "Lỗi",
                Content = "Số không hợp lệ",
                Duration = 3,
            })
        end
    end
})

local SpreadInput = MainTab:Input({
    Title = "Độ Giật Súng (Spread Degrees)",
    Desc = "Độ lan tỏa đạn khi bắn",
    Value = tostring(Config.DefaultSpreadDegrees),
    Placeholder = "Nhập số (ví dụ: 0)",
    Callback = function(value)
        local num = tonumber(value)
        if num then
            Config.DefaultSpreadDegrees = num
            WindUI:Notify({
                Title = "Đã Cập Nhật",
                Content = "Độ giật súng: " .. value,
                Duration = 2,
            })
        else
            WindUI:Notify({
                Title = "Lỗi",
                Content = "Số không hợp lệ",
                Duration = 3,
            })
        end
    end
})

-- Control Section
MainTab:Section({
    Title = "Điều Khiển",
})



-- Main Toggle
local MainToggle = MainTab:Toggle({
    Title = "Kích Hoạt D.O.K",
    Desc = "Bật/Tắt chế độ sửa đổi vũ khí",
    Type = "Toggle",
    Default = false,
    Callback = function(state)
        Config.Enabled = state
        
        if state then
            for _, mod in ipairs(getloadedmodules()) do
                if mod.Name == "FirstPersonAttackHandlerClass" then
                    local ModuleTable = require(mod)
                    if ModuleTable and ModuleTable.New then
                        local oldNew = ModuleTable.New
                        ModuleTable.New = function(...)
                            local obj = oldNew(...)
                            obj.DefaultShotInterval = Config.DefaultShotInterval
                            obj.ReloadTime = Config.ReloadTime
                            obj.CurrentFirerateMultiplier = Config.CurrentFirerateMultiplier
                            obj.DefaultSpreadDegrees = Config.DefaultSpreadDegrees
                            return obj
                        end
                    end
                elseif mod.Name == "FirstPersonCameraHandler" then
                    local cameraMod = require(mod)
                    if cameraMod and cameraMod.CameraShake then
                        cameraMod.CameraShake = function() end
                    end
                    if cameraMod and cameraMod.ApplyRecoil then
                        cameraMod.ApplyRecoil = function() end
                    end
                end
            end
            
            WindUI:Notify({
                Title = "Đã Kích Hoạt",
                Content = "D.O.K đang hoạt động",
                Duration = 3,
            })
        else
            WindUI:Notify({
                Title = "Đã Tắt", 
                Content = "D.O.K đã ngừng hoạt động",
                Duration = 3,
            })
        end
    end
})



-- Update status display
local originalCallback = MainToggle.Callback
MainToggle.Callback = function(state)
    originalCallback(state)
end

-- Guide Tab
local GuideTab = Window:Tab({
    Title = "Hướng Dẫn",
})

GuideTab:Section({
    Title = "Cách Sử Dụng",
})

GuideTab:Paragraph({
    Title = "Bước 1: Thiết Lập Thông Số",
    Desc = "• Nhập các giá trị số vào các ô tương ứng\n• Số càng nhỏ thì hiệu ứng càng mạnh\n• Có thể điều chỉnh từng thông số riêng biệt",
    Color = "Blue",
})

GuideTab:Paragraph({
    Title = "Bước 2: Kích Hoạt",
    Desc = "• Bật công tắc 'Kích Hoạt D.O.K' để áp dụng thay đổi\n• Có thể bật/tắt bất cứ lúc nào\n• Thay đổi có hiệu lực ngay lập tức",
    Color = "Green",
})

GuideTab:Section({
    Title = "Giải Thích Thông Số",
})

GuideTab:Paragraph({
    Title = "Khoảng Cách Bắn (Shot Interval)",
    Desc = "• Điều khiển thời gian giữa các phát bắn\n• Giá trị nhỏ = bắn nhanh hơn\n• ",
    Color = "White",
})

GuideTab:Paragraph({
    Title = "Thời Gian Nạp Đạn (Reload Time)",
    Desc = "• Thời gian cần để nạp lại đạn\n• Giá trị nhỏ = nạp đạn nhanh hơn\n• ",
    Color = "White",
})

GuideTab:Paragraph({
    Title = "Hệ Số Tốc Độ Bắn (Firerate)",
    Desc = "• Hệ số nhân cho tốc độ bắn súng\n• Giá trị nhỏ = bắn liên tục nhanh hơn\n• ",
    Color = "White",
})

GuideTab:Paragraph({
    Title = "Độ Giật Súng (Spread Degrees)",
    Desc = "• Độ lan tỏa của đạn khi bắn\n• 0 = bắn hoàn toàn chính xác\n• Số càng lớn càng kém chính xác\n• ",
    Color = "White",
})