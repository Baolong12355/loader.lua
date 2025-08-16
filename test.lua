-- Simple QTE Auto Perfect Script
-- Automatically hits perfect timing on Quick Time Events
-- No GUI, no console output, always enabled

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- Monitor for QTE and auto-press at perfect timing
RunService.Heartbeat:Connect(function()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if playerGui then
        local qteGui = playerGui:FindFirstChild("QuickTimeEvent")
        if qteGui then
            local ring = qteGui:FindFirstChild("Ring")
            local button = qteGui:FindFirstChild("Button")
            
            if ring and button and ring:IsA("ImageLabel") and button:IsA("TextButton") then
                -- Check if ring is at perfect timing (small size)
                if ring.Size.X.Scale <= 0.17 and ring.Size.X.Scale >= 0.15 then
                    local keyName = button.Text
                    if keyName and keyName ~= "" then
                        -- Method 1: Fire InputBegan connections
                        local keyCode = Enum.KeyCode[keyName]
                        if keyCode then
                            local fakeInput = {
                                KeyCode = keyCode,
                                UserInputType = Enum.UserInputType.Keyboard
                            }
                            for _, connection in pairs(getconnections(UserInputService.InputBegan)) do
                                connection:Fire(fakeInput, false)
                            end
                        end
                        
                        -- Method 2: Click button directly
                        for _, connection in pairs(getconnections(button.Activated)) do
                            connection:Fire()
                        end
                        
                        -- Method 3: Use VirtualInputManager
                        pcall(function()
                            local vim = game:GetService("VirtualInputManager")
                            vim:SendKeyEvent(true, keyCode, false, game)
                            wait(0.01)
                            vim:SendKeyEvent(false, keyCode, false, game)
                        end)
                    end
                end
            end
        end
    end
end)