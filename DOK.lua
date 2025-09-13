-- Load WindUI
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- Create Window
local Window = WindUI:CreateWindow({
    Title = "D.O.K (Drone Over Kill)",
    Author = "ngoài anh long còn thằng nào dùng làm 🐶",
    Folder = "DOK",
    Size = UDim2.fromOffset(350, 450),
    Transparent = false,
    Theme = "Dark",
    Resizable = false,
    SideBarWidth = 120,
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
    Title = "Khoảng Cách Bắn",
    Desc = "Thời gian giữa các phát bắn",
    Value = tostring(Config.DefaultShotInterval),
    Placeholder = "0.001",
    Type = "Input",
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
    Title = "Thời Gian Nạp Đạn",
    Desc = "Thời gian để nạp đạn",
    Value = tostring(Config.ReloadTime),
    Placeholder = "0.001",
    Type = "Input",
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
    Title = "Hệ Số Tốc Độ Bắn",
    Desc = "Hệ số nhân tốc độ bắn",
    Value = tostring(Config.CurrentFirerateMultiplier),
    Placeholder = "0.001",
    Type = "Input",
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
    Title = "Độ Giật Súng",
    Desc = "Độ lan tỏa đạn khi bắn",
    Value = tostring(Config.DefaultSpreadDegrees),
    Placeholder = "0",
    Type = "Input",
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
    Desc = "Bật/Tắt chế độ sửa đổi",
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
    Title = "Bước 1: Thiết Lập",
    Desc = "Nhập số vào các ô. Số nhỏ = hiệu ứng mạnh",
    Color = "Blue",
})

GuideTab:Paragraph({
    Title = "Bước 2: Kích Hoạt", 
    Desc = "Bật nút D.O.K để áp dụng thay đổi",
    Color = "Green",
})

GuideTab:Section({
    Title = "Thông Số Chi Tiết",
})

GuideTab:Paragraph({
    Title = "Khoảng Cách Bắn",
    Desc = "Thời gian giữa các phát bắn. Khuyến nghị: 0.001",
    Color = "White",
})

GuideTab:Paragraph({
    Title = "Thời Gian Nạp Đạn", 
    Desc = "Thời gian để nạp lại đạn. Khuyến nghị: 0.001",
    Color = "White",
})

GuideTab:Paragraph({
    Title = "Hệ Số Tốc Độ Bắn",
    Desc = "Hệ số nhân tốc độ bắn. Khuyến nghị: 0.001", 
    Color = "White",
})

GuideTab:Paragraph({
    Title = "Độ Giật Súng",
    Desc = "Độ lan tỏa đạn khi bắn. Khuyến nghị: 0",
    Color = "White",
})