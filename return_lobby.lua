local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Kiểm tra và lấy các instance một cách an toàn
local player = Players.LocalPlayer
if not player then return end

local playerGui = player:WaitForChild("PlayerGui")
local interface = playerGui and playerGui:WaitForChild("Interface")
local gameOverScreen = interface and interface:WaitForChild("GameOverScreen")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local teleportRemote = remotes and remotes:FindFirstChild("RequestTeleportToLobby")

-- THÊM KIỂM TRA QUAN TRỌNG
if not teleportRemote or not (teleportRemote:IsA("RemoteEvent") or teleportRemote:IsA("RemoteFunction")) then
    warn("❌ Không tìm thấy RemoteEvent/Function hợp lệ")
    return
end

local function tryTeleport()
    local maxAttempts = 5
    for attempt = 1, maxAttempts do
        local success, response = pcall(function()
            if teleportRemote:IsA("RemoteEvent") then
                teleportRemote:FireServer()
            else
                return teleportRemote:InvokeServer()
            end
            return true
        end)
        
        if success then
            print("✅ Teleport thành công")
            return true
        else
            warn(`❌ Lỗi lần {attempt}:`, response)
            task.wait(1)
        end
    end
    return false
end

if gameOverScreen and gameOverScreen.Visible then
    tryTeleport()
end

if gameOverScreen then
    gameOverScreen:GetPropertyChangedSignal("Visible"):Connect(function()
        if gameOverScreen.Visible then
            tryTeleport()
        end
    end)
end
