local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
if not player then return end

local playerGui = player:WaitForChild("PlayerGui")
local interface = playerGui:WaitForChild("Interface")
local gameOverScreen = interface:WaitForChild("GameOverScreen")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local teleportRemote = remotes:FindFirstChild("RequestTeleportToLobby")

if not teleportRemote or not (teleportRemote:IsA("RemoteEvent") or teleportRemote:IsA("RemoteFunction")) then
    return
end

local function tryTeleport()
    local maxAttempts = 5
    for _ = 1, maxAttempts do
        local success = pcall(function()
            task.wait(1)
            if teleportRemote:IsA("RemoteEvent") then
                teleportRemote:FireServer()
            else
                teleportRemote:InvokeServer()
            end
        end)

        if success then
            return true
        else
            task.wait(1)
        end
    end
    return false
end

local function autoRetryTeleport()
    while true do
        if gameOverScreen and gameOverScreen.Visible then
            tryTeleport()
        end
        task.wait(4)
    end
end

if gameOverScreen and gameOverScreen.Visible then
    tryTeleport()
end

if gameOverScreen then
    gameOverScreen:GetPropertyChangedSignal("Visible"):Connect(function()
        if gameOverScreen.Visible then
            coroutine.wrap(autoRetryTeleport)()
        end
    end)
end

local screen = interface:WaitForChild("CutsceneScreen")

local function fireOnce()
    task.wait(1)
    ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CutsceneVoteCast"):FireServer(true)
end

if screen.Visible then
    fireOnce()
else
    local connection
    connection = screen:GetPropertyChangedSignal("Visible"):Connect(function()
        if screen.Visible then
            fireOnce()
            connection:Disconnect()
        end
    end)
end