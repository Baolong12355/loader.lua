-- Auto Mining Minigame Script
-- Tự động chơi minigame mining bằng cách click vào zone màu vàng và cam

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Màu sắc cần tìm (vàng và cam)
local TARGET_COLORS = {
    Color3.fromRGB(255, 227, 114), -- Vàng (Value = 5)
    Color3.fromRGB(255, 140, 64)   -- Cam (Value = 6)
}

-- Biến điều khiển
local isAutoPlaying = false
local connection = nil

-- Hàm kiểm tra xem màu có khớp với target colors không
local function isTargetColor(color)
    for _, targetColor in pairs(TARGET_COLORS) do
        if color.R == targetColor.R and color.G == targetColor.G and color.B == targetColor.B then
            return true
        end
    end
    return false
end

-- Hàm kiểm tra collision giữa slider và zone
local function checkCollision(sliderPos, sliderSize, zonePos, zoneSize)
    local sliderLeft = sliderPos.X
    local sliderRight = sliderPos.X + sliderSize.X
    local sliderCenter = sliderPos.X + sliderSize.X / 2
    
    local zoneLeft = zonePos.X
    local zoneRight = zonePos.X + zoneSize.X
    
    -- Kiểm tra xem slider có overlap với zone không
    return sliderCenter >= zoneLeft and sliderCenter <= zoneRight
end

-- Hàm tìm kiếm minigame UI
local function findMiningMinigame()
    local ui = PlayerGui:FindFirstChild("UI")
    if not ui then return nil end
    
    local gameplay = ui:FindFirstChild("Gameplay")
    if not gameplay then return nil end
    
    local minigame = gameplay:FindFirstChild("MiningMinigame")
    if not minigame then return nil end
    
    return minigame
end

-- Hàm lấy tất cả zones có màu target
local function getTargetZones(minigame)
    local zones = {}
    local bar = minigame:FindFirstChild("Bar")
    if not bar then return zones end
    
    -- Tìm tất cả zones trong bar và children của nó
    local function searchZones(parent)
        for _, child in pairs(parent:GetChildren()) do
            if child:IsA("GuiObject") and child.Name ~= "Slider" and child.Name ~= "Time" then
                -- Kiểm tra nếu có BackgroundColor3 và là màu target
                if child.BackgroundColor3 and isTargetColor(child.BackgroundColor3) then
                    table.insert(zones, child)
                end
                -- Đệ quy tìm trong children
                searchZones(child)
            end
        end
    end
    
    searchZones(bar)
    return zones
end

-- Hàm simulate click
local function simulateClick()
    -- Tạo fake input event cho MouseButton1
    local fakeInputObject = {
        UserInputType = Enum.UserInputType.MouseButton1,
        KeyCode = Enum.KeyCode.Unknown
    }
    
    -- Fire input event
    for _, connection in pairs(getconnections(UserInputService.InputBegan)) do
        connection:Fire(fakeInputObject, false)
    end
end

-- Hàm main auto play
local function autoPlay()
    local minigame = findMiningMinigame()
    if not minigame then return end
    
    local bar = minigame:FindFirstChild("Bar")
    if not bar then return end
    
    local slider = bar:FindFirstChild("Slider")
    if not slider then return end
    
    -- Lấy tất cả target zones
    local targetZones = getTargetZones(minigame)
    if #targetZones == 0 then return end
    
    -- Kiểm tra collision với từng zone
    for _, zone in pairs(targetZones) do
        if zone.Parent and zone.Visible then
            local sliderPos = slider.AbsolutePosition
            local sliderSize = slider.AbsoluteSize
            local zonePos = zone.AbsolutePosition
            local zoneSize = zone.AbsoluteSize
            
            -- Kiểm tra collision
            if checkCollision(sliderPos, sliderSize, zonePos, zoneSize) then
                simulateClick()
                print("Auto clicked on zone with color:", zone.BackgroundColor3)
                break
            end
        end
    end
end

-- Hàm toggle auto play
local function toggleAutoPlay()
    isAutoPlaying = not isAutoPlaying
    
    if isAutoPlaying then
        print("Auto Mining: ENABLED")
        connection = RunService.Heartbeat:Connect(autoPlay)
    else
        print("Auto Mining: DISABLED")
        if connection then
            connection:Disconnect()
            connection = nil
        end
    end
end

-- Bind phím Toggle (F key)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.F then
        toggleAutoPlay()
    end
end)

-- Tự động bật khi detect minigame
spawn(function()
    while true do
        wait()
        local minigame = findMiningMinigame()
        if minigame and not isAutoPlaying then
            print("Mining minigame detected! Press F to toggle auto play")
            wait() -- Đợi 1 giây trước khi check lại
        end
    end
end)

print("Auto Mining Minigame Script loaded!")
print("Press F to toggle auto play ON/OFF")
print("Target colors: Yellow (255,227,114) and Orange (255,140,64)")