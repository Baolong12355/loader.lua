-- Script tự động ấn nút QTE khi vòng tròn đạt kích thước lý tưởng
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local lastPressTime = 0
local cooldown = 0.5 -- Giây

print("Script tự động ấn nút QTE đã kích hoạt!")

RunService.Heartbeat:Connect(function()
    -- Kiểm tra thời gian chờ
    if tick() - lastPressTime < cooldown then return end
    
    -- Tìm GUI QTE
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return end
    
    local qteGui = playerGui:FindFirstChild("QuickTimeEvent")
    if not qteGui then return end
    
    -- Tìm nút và vòng tròn
    local button = qteGui:FindFirstChild("Button")
    local ring = qteGui:FindFirstChild("Ring")
    if not button or not ring then return end
    
    -- Kiểm tra kích thước vòng tròn
    local ringSize = ring.Size.X.Scale
    if ringSize >= 0.15 and ringSize <= 0.17 then
        lastPressTime = tick()
        print("Phát hiện thời điểm hoàn hảo, tự động ấn nút...")
        
        -- Phương pháp 1: Kích hoạt trực tiếp (hiệu quả nhất)
        pcall(function()
            for _, conn in ipairs(getconnections(button.Activated)) do
                conn:Fire()
            end
        end)
        
        -- Phương pháp 2: Mô phỏng chạm (dự phòng)
        pcall(function()
            local absPos = button.AbsolutePosition
            local absSize = button.AbsoluteSize
            local centerX = absPos.X + absSize.X/2
            local centerY = absPos.Y + absSize.Y/2
            
            VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, true, game, 1)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, false, game, 1)
        end)
    end
end)