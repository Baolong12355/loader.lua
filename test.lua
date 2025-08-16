-- QTE Auto Perfect Script for Mobile (Focus on Most Effective Method)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local pressedThisQTE = false

print("QTE Auto Perfect Script Activated - Mobile Focus")

RunService.Heartbeat:Connect(function()
    -- Kiểm tra nhanh các điều kiện cần thiết
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return end
    
    local qteGui = playerGui:FindFirstChild("QuickTimeEvent")
    if not qteGui then return end
    
    local button = qteGui:FindFirstChild("Button")
    if not button then return end
    
    local ring = qteGui:FindFirstChild("Ring")
    if not ring then return end
    
    -- Chỉ tập trung vào phương pháp hiệu quả nhất: kích hoạt trực tiếp sự kiện Activated
    local ringSize = ring.Size.X.Scale
    if ringSize >= 0.15 and ringSize <= 0.17 and not pressedThisQTE then
        pressedThisQTE = true
        print("PERFECT TIMING DETECTED! Auto-pressing button...")
        
        -- Phương pháp hiệu quả nhất: Kích hoạt trực tiếp các kết nối Activated
        for _, connection in ipairs(getconnections(button.Activated)) do
            connection:Fire()
        end
        
        -- Thêm độ trễ nhỏ trước khi reset để tránh kích hoạt nhiều lần
        task.delay(0.5, function()
            pressedThisQTE = false
        end)
    elseif ringSize > 0.17 then
        pressedThisQTE = false -- Reset khi QTE mới bắt đầu
    end
end)