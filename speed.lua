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

-- Hàm truy cập TextLabel an toàn
local function getTextLabel()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if not gui then return end
    local interface = gui:FindFirstChild("Interface")
    if not interface then return end
    local screen = interface:FindFirstChild("SpeedChangeScreen")
    if not screen then return end
    local owned = screen:FindFirstChild("Owned")
    if not owned then return end
    local active = owned:FindFirstChild("Active")
    if not active then return end
    local content = active:FindFirstChild("Content")
    if not content then return end
    local button = content:FindFirstChild("Button")
    if not button then return end
    local label = button:FindFirstChild("TextLabel")
    return label
end

-- Biến kiểm soát
local isWaiting = false
local monitoring = true

RunService.Heartbeat:Connect(function()
    if not monitoring or isWaiting then return end

    local label = getTextLabel()
    if not label then
        warn("⚠️ Không tìm thấy TextLabel, thử lại sau 5 giây...")
        task.wait(5)
        return
    end

    local screen = LocalPlayer.PlayerGui:FindFirstChild("Interface")
        and LocalPlayer.PlayerGui.Interface:FindFirstChild("SpeedChangeScreen")

    if not screen or not screen.Active then
        task.wait(1)
        return
    end

    if not screen.Visible and label.Text ~= "Disabled" then
        isWaiting = true

        for i = 3, 1, -1 do
            print("⏳ Sẽ gửi remote sau "..i.."s...")
            task.wait(1)
        end

        if Remote:IsA("RemoteEvent") then
            Remote:FireServer(true, true)
        elseif Remote:IsA("RemoteFunction") then
            Remote:InvokeServer(true, true)
        end

        print("✅ Đã gửi yêu cầu bật lại")

        -- Đợi phản hồi sau khi gửi
        task.wait(0.5)

        -- Nếu Text lại thành "Disabled", tiếp tục đợi
        while label.Text == "Disabled" do
            warn("⛔ Giao diện báo 'Disabled', đang chờ khôi phục...")
            task.wait(1)
        end

        print("🌟 Đã sẵn sàng để gửi lại nếu cần")
        isWaiting = false
    end

    task.wait(0.5)
end)

print("🚀 Đã bật giám sát SpeedChangeScreen (có kiểm tra TextLabel 'Disabled')")