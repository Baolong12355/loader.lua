-- QTE Auto Perfect Script (Fixed UI Access)
-- Automatically hits perfect timing on Quick Time Events

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

print("QTE Auto Script Loaded!")

-- Safely check for UI elements
local function safeGetProperty(obj, property)
    local success, result = pcall(function()
        return obj[property]
    end)
    return success and result or nil
end

local function safeGetChild(parent, childName)
    local success, result = pcall(function()
        return parent:FindFirstChild(childName)
    end)
    return success and result or nil
end

-- Monitor for QTE and auto-press at perfect timing
RunService.Heartbeat:Connect(function()
    pcall(function()
        local playerGui = safeGetChild(LocalPlayer, "PlayerGui")
        if playerGui then
            local qteGui = safeGetChild(playerGui, "QuickTimeEvent")
            if qteGui then
                local ring = safeGetChild(qteGui, "Ring")
                local button = safeGetChild(qteGui, "Button")
                
                if ring and button then
                    -- Safely get ring size
                    local ringSize = safeGetProperty(ring, "Size")
                    if ringSize then
                        local sizeScale = ringSize.X.Scale
                        
                        -- Debug info
                        if sizeScale <= 0.5 then
                            local buttonText = safeGetProperty(button, "Text") or "Unknown"
                            print("Ring size:", sizeScale, "Button text:", buttonText)
                        end
                        
                        -- Check if ring is at perfect timing
                        if sizeScale <= 0.17 and sizeScale >= 0.15 then
                            print("PERFECT TIMING DETECTED! Ring size:", sizeScale)
                            
                            local keyName = safeGetProperty(button, "Text")
                            if keyName and keyName ~= "" then
                                print("Attempting to press key:", keyName)
                                
                                -- Method 1: Fire InputBegan connections
                                local keyCode = Enum.KeyCode[keyName]
                                if keyCode then
                                    print("KeyCode found:", keyCode)
                                    
                                    pcall(function()
                                        local fakeInput = {
                                            KeyCode = keyCode,
                                            UserInputType = Enum.UserInputType.Keyboard
                                        }
                                        local inputConnections = getconnections(UserInputService.InputBegan)
                                        print("InputBegan connections found:", #inputConnections)
                                        for i, connection in pairs(inputConnections) do
                                            pcall(function()
                                                print("Firing InputBegan connection", i)
                                                connection:Fire(fakeInput, false)
                                            end)
                                        end
                                    end)
                                end
                                
                                -- Method 2: Click button directly
                                pcall(function()
                                    local buttonConnections = getconnections(button.Activated)
                                    print("Button connections found:", #buttonConnections)
                                    for i, connection in pairs(buttonConnections) do
                                        pcall(function()
                                            print("Firing button connection", i)
                                            connection:Fire()
                                        end)
                                    end
                                end)
                                
                                -- Method 3: Use VirtualInputManager
                                pcall(function()
                                    print("Trying VirtualInputManager...")
                                    local vim = game:GetService("VirtualInputManager")
                                    vim:SendKeyEvent(true, keyCode, false, game)
                                    task.wait(0.01)
                                    vim:SendKeyEvent(false, keyCode, false, game)
                                    print("VirtualInputManager key sent!")
                                end)
                                
                                -- Method 4: Direct firesignal if available
                                pcall(function()
                                    if firesignal then
                                        print("Trying firesignal...")
                                        firesignal(button.Activated)
                                        print("Firesignal executed!")
                                    end
                                end)
                                
                                -- Method 5: Mouse click simulation
                                pcall(function()
                                    if mousemoveabs and mouse1press and mouse1release then
                                        print("Trying mouse click simulation...")
                                        local buttonPos = button.AbsolutePosition
                                        local buttonSize = button.AbsoluteSize
                                        local centerX = buttonPos.X + buttonSize.X / 2
                                        local centerY = buttonPos.Y + buttonSize.Y / 2
                                        
                                        mousemoveabs(centerX, centerY)
                                        mouse1press()
                                        task.wait(0.01)
                                        mouse1release()
                                        print("Mouse click executed!")
                                    end
                                end)
                                
                                print("All methods attempted!")
                            else
                                print("No key name found on button")
                            end
                        end
                    end
                end
            else
                -- Only print occasionally to avoid spam
                if tick() % 5 < 0.1 then
                    print("No QuickTimeEvent GUI found")
                end
            end
        end
    end)
end)