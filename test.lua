-- Auto Mining Minigame Script
-- Tự động chơi minigame mining bằng cách click vào zone màu vàng và cam
-- Hỗ trợ Mobile và click nhiều lần

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

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
local lastClickTime = 0
local clickCooldown = 0.1 -- Giảm cooldown để có thể click nhiều lần
local isOnMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local lastZonePositions = {} -- Lưu vị trí zones cũ
local waitingForNewZone = false
local lastClickedZone = nil

-- Hàm kiểm tra xem màu có khớp với target colors không
local function isTargetColor(color)
    for _, targetColor in pairs(TARGET_COLORS) do
        if color.R == targetColor.R and color.G == targetColor.G and color.B == targetColor.B then
            return true
        end
    end
    return false
end

-- Hàm kiểm tra xem zone có thay đổi vị trí hay không
local function hasZoneChanged(zones)
    if #lastZonePositions == 0 then
        -- Lần đầu tiên, lưu vị trí
        lastZonePositions = {}
        for i, zone in pairs(zones) do
            lastZonePositions[i] = {
                position = zone.AbsolutePosition,
                size = zone.AbsoluteSize,
                color = zone.BackgroundColor3
            }
        end
        return true
    end
    
    -- Kiểm tra xem có zone mới hoặc vị trí thay đổi không
    if #zones ~= #lastZonePositions then
        return true
    end
    
    for i, zone in pairs(zones) do
        local oldData = lastZonePositions[i]
        if not oldData or 
           zone.AbsolutePosition ~= oldData.position or
           zone.AbsoluteSize ~= oldData.size or
           zone.BackgroundColor3 ~= oldData.color then
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
    
    -- Tìm tất cả zones trong bar và children của nó (bao gồm zones riêng lẻ)
    local function searchZones(parent)
        for _, child in pairs(parent:GetChildren()) do
            if child:IsA("GuiObject") and child.Name ~= "Slider" and child.Name ~= "Time" then
                -- Kiểm tra nếu có BackgroundColor3 và là màu target
                if child.BackgroundColor3 and isTargetColor(child.BackgroundColor3) then
                    table.insert(zones, child)
                end
                -- Đệ quy tìm trong children để tìm zone cam riêng lẻ
                searchZones(child)
            end
        end
    end
    
    -- Tìm zones trực tiếp trong bar
    searchZones(bar)
    
    -- Tìm thêm zones có thể nằm riêng lẻ
    for _, child in pairs(bar:GetChildren()) do
        if child:IsA("GuiObject") and child.Name == "Zone" then
            if child.BackgroundColor3 and isTargetColor(child.BackgroundColor3) then
                table.insert(zones, child)
            end
        end
    end
    
    return zones
end

-- Hàm simulate click cho cả PC và Mobile
local function simulateClick(zone)
    local currentTime = tick()
    if currentTime - lastClickTime < clickCooldown then
        return false -- Còn trong cooldown
    end
    
    lastClickTime = currentTime
    lastClickedZone = zone
    waitingForNewZone = true
    
    if isOnMobile then
        -- Mobile: Sử dụng Touch input
        local fakeInputObject = {
            UserInputType = Enum.UserInputType.Touch,
            KeyCode = Enum.KeyCode.Unknown,
            Position = Vector3.new(0, 0, 0)
        }
        
        -- Fire touch event
        for _, connection in pairs(getconnections(UserInputService.InputBegan)) do
            pcall(function()
                connection:Fire(fakeInputObject, false)
            end)
        end
    else
        -- PC: Sử dụng MouseButton1
        local fakeInputObject = {
            UserInputType = Enum.UserInputType.MouseButton1,
            KeyCode = Enum.KeyCode.Unknown
        }
        
        -- Fire mouse event
        for _, connection in pairs(getconnections(UserInputService.InputBegan)) do
            pcall(function()
                connection:Fire(fakeInputObject, false)
            end)
        end
    end
    
    return true
end

-- Hàm main auto play với khả năng đợi zone mới
local function autoPlay()
    local minigame = findMiningMinigame()
    if not minigame then return end
    
    local bar = minigame:FindFirstChild("Bar")
    if not bar then return end
    
    local slider = bar:FindFirstChild("Slider")
    if not slider then return end
    
    -- Lấy tất cả target zones
    local targetZones = getTargetZones(minigame)
    if #targetZones == 0 then 
        -- Reset nếu không còn zone nào
        if waitingForNewZone then
            waitingForNewZone = false
            lastClickedZone = nil
            print("No zones found, ready for new zones")
        end
        return 
    end
    
    -- Kiểm tra xem có zone mới hay không
    if waitingForNewZone then
        local hasChanged = hasZoneChanged(targetZones)
        if not hasChanged then
            return -- Vẫn đang đợi zone mới
        else
            waitingForNewZone = false
            lastClickedZone = nil
            updateZonePositions(targetZones)
            print("New zones detected, ready to click")
        end
    end
    
    -- Kiểm tra collision với từng zone
    local foundCollision = false
    for _, zone in pairs(targetZones) do
        if zone.Parent and zone.Visible then
            local sliderPos = slider.AbsolutePosition
            local sliderSize = slider.AbsoluteSize
            local zonePos = zone.AbsolutePosition
            local zoneSize = zone.AbsoluteSize
            
            -- Kiểm tra collision
            if checkCollision(sliderPos, sliderSize, zonePos, zoneSize) then
                local clicked = simulateClick(zone)
                if clicked then
                    print("Auto clicked on zone with color:", zone.BackgroundColor3)
                    updateZonePositions(targetZones)
                    foundCollision = true
                    -- Chỉ click một zone mỗi lần để tránh spam
                    break
                end
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

-- Bind phím Toggle cho cả PC và Mobile (cả hai đều có thể dùng F)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.F then
        toggleAutoPlay()
    end
end)

-- Thêm button cho mobile (tùy chọn)
if isOnMobile then
    -- Mobile: Tạo toggle button (backup cho trường hợp không có bàn phím)
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoMiningToggle"
    screenGui.Parent = PlayerGui
    screenGui.ResetOnSpawn = false
    
    local toggleButton = Instance.new("TextButton")
    toggleButton.Size = UDim2.new(0, 100, 0, 50)
    toggleButton.Position = UDim2.new(0, 10, 0, 100)
    toggleButton.Text = "Auto: OFF"
    toggleButton.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
    toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleButton.TextScaled = true
    toggleButton.Parent = screenGui
    
    -- Làm cho button có thể kéo
    local dragging = false
    local dragStart = nil
    local startPos = nil
    
    toggleButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = toggleButton.Position
        end
    end)
    
    toggleButton.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            toggleButton.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    
    toggleButton.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                -- Nếu không kéo nhiều thì coi như click
                local delta = input.Position - dragStart
                if math.abs(delta.X) < 10 and math.abs(delta.Y) < 10 then
                    toggleAutoPlay()
                    toggleButton.Text = isAutoPlaying and "Auto: ON" or "Auto: OFF"
                    toggleButton.BackgroundColor3 = isAutoPlaying and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
                end
            end
        end
    end)
end

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
print("Press F to toggle auto play ON/OFF (works on both PC and Mobile)")
if isOnMobile then
    print("Mobile detected: Also use the toggle button on screen if needed")
else
    print("PC detected")
end
print("Target colors: Yellow (255,227,114) and Orange (255,140,64)")
print("Script waits for new zones after each click")