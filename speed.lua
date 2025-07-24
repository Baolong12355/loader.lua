local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")

-- Kiểm tra Remotes
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
    warn("⚠️ Không tìm thấy Remotes")
    return
end

local Remote = Remotes:FindFirstChild("SoloToggleSpeedControl")
if not Remote then
    warn("⚠️ Không tìm thấy SoloToggleSpeedControl")
    return
end

-- Hàm kiểm tra Active Frame an toàn
local function getActiveFrame()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return nil end
    
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return nil end
    
    local speedChangeScreen = interface:FindFirstChild("SpeedChangeScreen")
    if not speedChangeScreen then return nil end
    
    local owned = speedChangeScreen:FindFirstChild("Owned")
    if not owned then return nil end
    
    return owned:FindFirstChild("Active")
end

-- Biến kiểm soát
local isWaiting = false
local monitoring = true

-- Chế độ giám sát thông minh
RunService.Heartbeat:Connect(function()
    if not monitoring then return end
    
    local activeFrame = getActiveFrame()
    if not activeFrame then
        warn("⚠️ Mất kết nối UI, đang thử lại sau 5 giây...")
        task.wait(5)
        return
    end

    if not activeFrame.Visible and not isWaiting then
        isWaiting = true
        
        -- Đếm ngược 3 giây trước khi kích hoạt
        for i = 3, 1, -1 do
            print("⏳ Đã phát hiện tắt, sẽ kích hoạt sau "..i.."s...")
            task.wait(1)
        end

        -- Gửi remote
        if Remote:IsA("RemoteEvent") then
            Remote:FireServer(true, true)
        elseif Remote:IsA("RemoteFunction") then
            Remote:InvokeServer(true, true)
        end
        print("✅ Đã gửi yêu cầu bật lại")
        
        -- Chờ xác nhận
        task.wait(0.5)
        if activeFrame.Visible then
            print("🌈 Kích hoạt thành công!")
        else
            warn("❌ Vẫn không thấy hiển thị, sẽ thử lại lần tới")
        end
        
        isWaiting = false
    end
    
    task.wait(0.5) -- Kiểm tra mỗi 0.5 giây
end)

-- Cách tắt script: gõ monitoring = false trong console
print("🚀 Đã bật chế độ giám sát (Delay 3s khi phát hiện tắt)")
