-- QTE Auto Perfect Script for Mobile (Optimized Version)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local pressedThisQTE = false

print("QTE")

-- Optimized monitoring with debounce
RunService.Heartbeat:Connect(function()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return end
    
    local qteGui = playerGui:FindFirstChild("QuickTimeEvent")
    if not qteGui then return end
    
    local ring = qteGui:FindFirstChild("Ring")
    local button = qteGui:FindFirstChild("Button")
    if not ring or not button then return end
    
    local ringSize = ring.Size.X.Scale
    if not ringSize then return end
    
    -- Check for perfect timing (0.15-0.17 scale)
    if ringSize >= 0.15 and ringSize <= 0.17 and not pressedThisQTE then
        pressedThisQTE = true
        print("Perfect timing detected! Attempting press...")
        
        -- Method 1: Directly fire button activation (most reliable)
        local success = pcall(function()
            for _, connection in ipairs(getconnections(button.Activated)) do
                connection:Fire()
            end
        end)
        
        -- Method 2: Virtual touch as fallback
        if not success then
            pcall(function()
                local absPos = button.AbsolutePosition
                local absSize = button.AbsoluteSize
                local centerX = absPos.X + absSize.X/2
                local centerY = absPos.Y + absSize.Y/2
                
                VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, true, game, 1)
                task.wait(0.05)
                VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, false, game, 1)
            end)
        end
        
        -- Method 3: Keyboard input as last resort
        local buttonText = button.Text
        if buttonText and Enum.KeyCode[buttonText] then
            pcall(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode[buttonText], false, game)
                task.wait(0.01)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode[buttonText], false, game)
            end)
        end
    elseif ringSize > 0.17 then
        pressedThisQTE = false -- Reset for next QTE
    end
end)