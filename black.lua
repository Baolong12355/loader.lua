local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local enemyModule = nil
pcall(function()
    enemyModule = require(LocalPlayer.PlayerScripts:WaitForChild("Client")
        :WaitForChild("GameClass")
        :WaitForChild("EnemyClass"))
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = tostring(math.random(1e9, 2e9))
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 2147483647
screenGui.Parent = CoreGui

local blackFrame = Instance.new("Frame")
blackFrame.Name = "Cover"
blackFrame.Size = UDim2.new(1, 0, 1, 0)
blackFrame.Position = UDim2.new(0, 0, 0, 0)
blackFrame.BackgroundColor3 = Color3.new(0, 0, 0)
blackFrame.BorderSizePixel = 0
blackFrame.ZIndex = 1
blackFrame.Active = true
blackFrame.Parent = screenGui

local headerLabel = Instance.new("TextLabel")
headerLabel.Name = "Header"
headerLabel.Size = UDim2.new(1, -20, 0, 30)
headerLabel.Position = UDim2.new(0, 10, 0, 10)
headerLabel.BackgroundTransparency = 1
headerLabel.TextColor3 = Color3.new(1, 1, 1)
headerLabel.TextStrokeTransparency = 0
headerLabel.Font = Enum.Font.SourceSansBold
headerLabel.TextSize = 24
headerLabel.TextYAlignment = Enum.TextYAlignment.Top
headerLabel.TextXAlignment = Enum.TextXAlignment.Left
headerLabel.ZIndex = 2
headerLabel.Parent = screenGui

local enemyListFrame = Instance.new("ScrollingFrame")
enemyListFrame.Name = "EnemyList"
enemyListFrame.Size = UDim2.new(1, -20, 1, -50)
enemyListFrame.Position = UDim2.new(0, 10, 0, 40)
enemyListFrame.BackgroundTransparency = 1
enemyListFrame.BorderSizePixel = 0
enemyListFrame.ScrollBarThickness = 6
enemyListFrame.ZIndex = 2
enemyListFrame.Parent = screenGui

local uiListLayout = Instance.new("UIListLayout")
uiListLayout.Padding = UDim.new(0, 2)
uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
uiListLayout.Parent = enemyListFrame

local function kick(englishReason)
    pcall(function() LocalPlayer:Kick(englishReason or "GUI tampering was detected.") end)
end

local function protect(instance, propertiesToProtect)
    local originalProperties = { Parent = instance.Parent }
    for _, propName in ipairs(propertiesToProtect) do originalProperties[propName] = instance[propName] end
    instance.AncestryChanged:Connect(function(_, parent)
        if parent ~= originalProperties.Parent then kick("Reason: Attempted to delete or move a protected GUI element.") end
    end)
    for propName, originalValue in pairs(originalProperties) do
        if propName ~= "Parent" then
            instance:GetPropertyChangedSignal(propName):Connect(function()
                if instance[propName] ~= originalValue then kick("Reason: Attempted to modify protected GUI property: " .. propName) end
            end)
        end
    end
end

protect(screenGui, {"Name", "DisplayOrder", "IgnoreGuiInset", "Enabled"})
protect(blackFrame, {"Name", "Size", "Position", "BackgroundColor3", "BackgroundTransparency", "Visible", "ZIndex", "Active"})
protect(headerLabel, {"Name", "Size", "Position", "TextColor3", "Visible", "ZIndex"})
protect(enemyListFrame, {"Name", "Size", "Position", "Visible", "ZIndex"})

local function formatPercent(value)
    if value < 0 then value = 0 end
    return math.floor(value * 100 + 0.5) .. "%"
end

local waveTextLabel, timeTextLabel
pcall(function()
    local interface = PlayerGui:WaitForChild("Interface", 15)
    local gameInfoBar = interface and interface:WaitForChild("GameInfoBar", 15)
    if gameInfoBar then
        waveTextLabel = gameInfoBar:WaitForChild("Wave", 5) and gameInfoBar.Wave:WaitForChild("WaveText", 5)
        timeTextLabel = gameInfoBar:WaitForChild("TimeLeft", 5) and gameInfoBar.TimeLeft:WaitForChild("TimeLeftText", 5)
    end
end)

local SHIELD_COLOR = Color3.fromRGB(0, 170, 255)
local NORMAL_COLOR = Color3.new(1, 1, 1)

RunService.RenderStepped:Connect(function()
    local waveStr = (waveTextLabel and waveTextLabel.Text) or "?"
    local timeStr = (timeTextLabel and timeTextLabel.Text) or "??:??"
    headerLabel.Text = string.format("Wave: %s | Time: %s", waveStr, timeStr)

    local enemyGroups = {}
    if enemyModule and enemyModule.GetEnemies then
        for _, enemy in pairs(enemyModule.GetEnemies()) do
            pcall(function()
                if enemy and enemy.IsAlive and not enemy.IsFakeEnemy and enemy.HealthHandler then
                    local maxHealth = enemy.HealthHandler:GetMaxHealth()
                    if maxHealth > 0 then
                        local currentHealth = enemy.HealthHandler:GetHealth()
                        local currentShield = enemy.HealthHandler:GetShield()
                        local hasShield = currentShield > 0
                        
                        local percentValue = (currentHealth + currentShield) / maxHealth
                        local hp = formatPercent(percentValue)
                        local name = enemy.DisplayName or "Unknown"

                        if not enemyGroups[name] then
                            enemyGroups[name] = { count = 0, hps = {}, hasShield = false }
                        end
                        
                        local group = enemyGroups[name]
                        group.count += 1
                        table.insert(group.hps, hp)
                        if hasShield then
                            group.hasShield = true
                        end
                    end
                end
            end)
        end
    end

    enemyListFrame:ClearAllChildren()
    uiListLayout.Parent = enemyListFrame

    local sortedNames = {}
    for name in pairs(enemyGroups) do
        table.insert(sortedNames, name)
    end
    table.sort(sortedNames)

    for i, name in ipairs(sortedNames) do
        local data = enemyGroups[name]
        local newLine = Instance.new("TextLabel")
        newLine.Name = name
        newLine.LayoutOrder = i
        newLine.Size = UDim2.new(1, 0, 0, 22)
        newLine.BackgroundTransparency = 1
        newLine.Font = Enum.Font.SourceSansBold
        newLine.TextSize = 22
        newLine.TextXAlignment = Enum.TextXAlignment.Left
        newLine.TextColor3 = data.hasShield and SHIELD_COLOR or NORMAL_COLOR
        
        table.sort(data.hps)
        local hpString = table.concat(data.hps, ", ")
        newLine.Text = string.format("%s (x%d): %s", name, data.count, hpString)
        
        newLine.Parent = enemyListFrame
    end
end)

RunService.RenderStepped:Connect(function()
    if screenGui.Parent ~= CoreGui then screenGui.Parent = CoreGui end
    screenGui.DisplayOrder = 2147483647
end)