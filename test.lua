-- QTE Auto Perfect Script for Mobile
-- Uses touch/click simulation at GUI position

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

print("QTE Auto Script for Mobile Loaded!")

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

-- Touch/Click simulation function
local function simulateTouch(element)
    pcall(function()
        print("Attempting touch simulation...")
        
        -- Get element position and size
        local absPos = element.AbsolutePosition
        local absSize = element.AbsoluteSize
        local centerX = absPos.X + absSize.X / 2
        local centerY = absPos.Y + absSize.Y / 2
        
        print("Touch position:", centerX, centerY)
        
        -- Method 1: VirtualInputManager touch
        pcall(function()
            local vim = game:GetService("VirtualInputManager")
            vim:SendMouseButtonEvent(centerX, centerY, 0, true, game, 1)
            task.wait(0.05)
            vim:SendMouseButtonEvent(centerX, centerY, 0, false, game, 1)
            print("VirtualInputManager touch sent!")
        end)
        
        -- Method 2: Mouse simulation functions
        pcall(function()
            if mouse1click then
                mouse1click(centerX, centerY)
                print("mouse1click executed!")
            elseif mousemoveabs and mouse1press and mouse1release then
                mousemoveabs(centerX, centerY)
                mouse1press()
                task.wait(0.05)
                mouse1release()
                print("Manual mouse click executed!")
            end
        end)
        
        -- Method 3: Touch event simulation
        pcall(function()
            local touchInput = {
                UserInputType = Enum.UserInputType.Touch,
                Position = Vector3.new(centerX, centerY, 0)
            }
            
            -- Fire touch began
            for _, connection in pairs(getconnections(UserInputService.TouchTapInWorld)) do
                connection:Fire(touchInput, nil)
            end
            
            for _, connection in pairs(getconnections(UserInputService.TouchTap)) do
                connection:Fire(touchInput, nil)
            end
            print("Touch events fired!")
        end)
        
        -- Method 4: Direct GuiButton activation
        pcall(function()
            if element:IsA("GuiButton") or element:IsA("TextButton") then
                -- Fire all Activated connections
                for i, connection in pairs(getconnections(element.Activated)) do
                    connection:Fire()
                    print("Button Activated connection", i, "fired!")
                end
                
                -- Fire MouseButton1Click connections
                for i, connection in pairs(getconnections(element.MouseButton1Click)) do
                    connection:Fire()
                    print("MouseButton1Click connection", i, "fired!")
                end
            end
        end)
        
    end)
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
                            print("Ring size:", math.floor(sizeScale * 1000) / 1000, "Button text:", buttonText)
                        end
                        
                        -- Check if ring is at perfect timing
                        if sizeScale <= 0.17 and sizeScale >= 0.15 then
                            print("PERFECT TIMING DETECTED! Ring size:", sizeScale)
                            print("Button absolute position:", button.AbsolutePosition)
                            print("Button absolute size:", button.AbsoluteSize)
                            
                            -- Simulate touch on button
                            simulateTouch(button)
                            
                            -- Also try keyboard input as backup
                            local keyName = safeGetProperty(button, "Text")
                            if keyName and keyName ~= "" then
                                local keyCode = Enum.KeyCode[keyName]
                                if keyCode then
                                    pcall(function()
                                        local vim = game:GetService("VirtualInputManager")
                                        vim:SendKeyEvent(true, keyCode, false, game)
                                        task.wait(0.01)
                                        vim:SendKeyEvent(false, keyCode, false, game)
                                        print("Backup keyboard input sent:", keyName)
                                    end)
                                end
                            end
                            
                            print("All touch methods attempted!")
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