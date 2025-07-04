local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Kiá»ƒm tra vĂ  láº¥y cĂ¡c instance má»™t cĂ¡ch an toĂ n
local player = Players.LocalPlayer
if not player then return end

local playerGui = player:WaitForChild("PlayerGui")
local interface = playerGui and playerGui:WaitForChild("Interface")
local gameOverScreen = interface and interface:WaitForChild("GameOverScreen")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local teleportRemote = remotes and remotes:FindFirstChild("RequestTeleportToLobby")

-- THĂM KIá»‚M TRA QUAN TRá»ŒNG
if not teleportRemote or not (teleportRemote:IsA("RemoteEvent") or teleportRemote:IsA("RemoteFunction")) then
    warn("âŒ KhĂ´ng tĂ¬m tháº¥y RemoteEvent/Function há»£p lá»‡")
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
            print("âœ… Teleport thĂ nh cĂ´ng")
            return true
        else
            warn(`âŒ Lá»—i láº§n {attempt}:`, response)
            task.wait(1)
        end
    end
    return false
end

-- HĂ m tá»± Ä‘á»™ng thá»­ láº¡i má»—i 4 giĂ¢y khi mĂ n hĂ¬nh GameOver Ä‘ang hiá»ƒn thá»‹
local function autoRetryTeleport()
    while true do
        if gameOverScreen and gameOverScreen.Visible then
            tryTeleport()
        end
        task.wait(4) -- Chá» 4 giĂ¢y trÆ°á»›c khi thá»­ láº¡i
    end
end

-- KĂ­ch hoáº¡t ngay láº­p tá»©c náº¿u mĂ n hĂ¬nh Ä‘ang hiá»ƒn thá»‹
if gameOverScreen and gameOverScreen.Visible then
    tryTeleport()
end

-- Theo dĂµi sá»± thay Ä‘á»•i tráº¡ng thĂ¡i hiá»ƒn thá»‹
if gameOverScreen then
    gameOverScreen:GetPropertyChangedSignal("Visible"):Connect(function()
        if gameOverScreen.Visible then
            -- Báº¯t Ä‘áº§u vĂ²ng láº·p tá»± Ä‘á»™ng thá»­ láº¡i
            coroutine.wrap(autoRetryTeleport)()
        end
    end)
end


local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local screen = player:WaitForChild("PlayerGui"):WaitForChild("Interface"):WaitForChild("CutsceneScreen")

local function fireOnce()
    local args = { true }
    ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CutsceneVoteCast"):FireServer(unpack(args))
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
