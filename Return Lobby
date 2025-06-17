local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local Interface = PlayerGui:WaitForChild("Interface")
local GameOverScreen = Interface:WaitForChild("GameOverScreen")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestTeleport = Remotes:FindFirstChild("RequestTeleportToLobby")

if GameOverScreen and RequestTeleport then
    -- Theo dõi thay đổi trạng thái Visible
    GameOverScreen:GetPropertyChangedSignal("Visible"):Connect(function()
        if GameOverScreen.Visible then
            -- Đợi nhẹ 1 giây rồi gửi teleport về lobby
            task.wait(1)
            if RequestTeleport:IsA("RemoteEvent") then
                RequestTeleport:FireServer()
            elseif RequestTeleport:IsA("RemoteFunction") then
                RequestTeleport:InvokeServer()
            end
        end
    end)
end
