-- QTE Auto Perfect Script with Debug Console
-- Automatically hits perfect timing on Quick Time Events

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

print("QTE Auto Script Loaded!")

-- Monitor for QTE and auto-press at perfect timing
RunService.Heartbeat:Connect(function()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if playerGui then
        local qteGui = playerGui:FindFirstChild("QuickTimeEvent")
        if qteGui then
            local ring = qteGui:FindFirstChild("Ring")
            local button = qteGui:FindFirstChild("Button")
            
            if ring and button and ring:IsA("ImageLabel") and button:IsA("TextButton") then
                -- Debug info
                local ringSize = ring.Size.X.Scale
                if ringSize <= 0.5 then -- Only print when ring is getting smaller
                    print("Ring size:", ringSize, "Button text:", button.Text)
                end
                
                -- Check if ring is at perfect timing
                if ringSize <= 0.17 and ringSize >= 0.15 then
                    print("PERFECT TIMING DETECTED! Ring size:", ringSize)
                    
                    local keyName = button.Text
                    if keyName and keyName ~= "" then
                        print("Attempting to press key:", keyName)
                        
                        -- Method 1: Fire InputBegan connections
                        local keyCode = Enum.KeyCode[keyName]
                        if keyCode then
                            print("KeyCode found:", keyCode)
                            local fakeInput = {
                                KeyCode = keyCode,
                                UserInputType = Enum.UserInputType.Keyboard
                            }
                            local inputConnections = getconnections(UserInputService.InputBegan)
                            print("InputBegan connections found:", #inputConnections)
                            for i, connection in pairs(inputConnections) do
                                print("Firing InputBegan connection", i)
                                connection:Fire(fakeInput, false)
                            end
                        end
                        
                        -- Method 2: Click button directly
                        local buttonConnections = getconnections(button.Activated)
                        print("Button connections found:", #buttonConnections)
                        for i, connection in pairs(buttonConnections) do
                            print("Firing button connection", i)
                            connection:Fire()
                        end
                        
                        -- Method 3: Use VirtualInputManager
                        pcall(function()
                            print("Trying VirtualInputManager...")
                            local vim = game:GetService("VirtualInputManager")
                            vim:SendKeyEvent(true, keyCode, false, game)
                            wait(0.01)
                            vim:SendKeyEvent(false, keyCode, false, game)
                            print("VirtualInputManager key sent!")
                        end)
                        
                        print("All methods attempted!")
                    else
                        print("No key name found on button")
                    end
                end
            end
        else
            -- Check if QTE GUI exists at all
            local qteExists = qteGui ~= nil
            if not qteExists then
                -- Only print occasionally to avoid spam
                if tick() % 5 < 0.1 then
                    print("No QuickTimeEvent GUI found")
                end
            end
        end
    end
end)