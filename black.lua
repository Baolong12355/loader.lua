
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Lấy enemy module một cách an toàn
local enemyModule = nil
pcall(function()
    enemyModule = require(LocalPlayer.PlayerScripts:WaitForChild("Client")
        :WaitForChild("GameClass")
        :WaitForChild("EnemyClass"))
end)

-- Tạo GUI
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
blackFrame.Active = true -- SỬA LỖI: Đặt thành true để ngăn click xuyên qua
blackFrame.Parent = screenGui

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "WaveStatus"
statusLabel.Size = UDim2.new(1, -20, 1, -20)
statusLabel.Position = UDim2.new(0, 10, 0, 10)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.new(1, 1, 1)
statusLabel.TextStrokeTransparency = 0
statusLabel.Font = Enum.Font.SourceSansBold
statusLabel.TextSize = 24
statusLabel.TextWrapped = true
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Text = "Loading..."
statusLabel.ZIndex = 2
statusLabel.Parent = screenGui

-- HÀM BẢO VỆ VÀ KICK
local function kick(englishReason)
    pcall(function()
        LocalPlayer:Kick(englishReason or "GUI tampering was detected.")
    end)
end

-- Hàm bảo vệ một đối tượng GUI
local function protect(instance, propertiesToProtect)
    local originalProperties = { Parent = instance.Parent }
    for _, propName in ipairs(propertiesToProtect) do
        originalProperties[propName] = instance[propName]
    end

    instance.AncestryChanged:Connect(function(_, parent)
        if parent ~= originalProperties.Parent then
            kick("Reason: Attempted to delete or move a protected GUI element.")
        end
    end)

    for propName, originalValue in pairs(originalProperties) do
        if propName ~= "Parent" then
            instance:GetPropertyChangedSignal(propName):Connect(function()
                if instance[propName] ~= originalValue then
                    kick("Reason: Attempted to modify protected GUI property: " .. propName)
                end
            end)
        end
    end
end

-- Áp dụng bảo vệ
protect(screenGui, {"Name", "DisplayOrder", "IgnoreGuiInset", "Enabled"})
-- SỬA LỖI: Thêm "Active" vào danh sách bảo vệ
protect(blackFrame, {"Name", "Size", "Position", "BackgroundColor3", "BackgroundTransparency", "Visible", "ZIndex", "Active"})
protect(statusLabel, {"Name", "Size", "Position", "TextColor3", "TextTransparency", "Visible", "ZIndex", "Font", "TextSize"})

-- Hàm định dạng phần trăm
local function formatPercent(value)
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    return math.floor(value * 100 + 0.5) .. "%"
end

-- Tối ưu hóa việc tìm kiếm GUI
local waveTextLabel, timeTextLabel
pcall(function()
    local interface = PlayerGui:WaitForChild("Interface", 15)
    local gameInfoBar = interface and interface:WaitForChild("GameInfoBar", 15)
    if gameInfoBar then
        waveTextLabel = gameInfoBar:WaitForChild("Wave", 5) and gameInfoBar.Wave:WaitForChild("WaveText", 5)
        timeTextLabel = gameInfoBar:WaitForChild("TimeLeft", 5) and gameInfoBar.TimeLeft:WaitForChild("TimeLeftText", 5)
    end
end)

-- Cập nhật thông tin bằng RenderStepped
RunService.RenderStepped:Connect(function()
    local waveStr = (waveTextLabel and waveTextLabel.Text) or "?"
    local timeStr = (timeTextLabel and timeTextLabel.Text) or "??:??"

    local enemyInfo = ""
    if enemyModule and enemyModule.GetEnemies then
        local enemies = enemyModule.GetEnemies()
        local enemyGroups = {}

        for _, enemy in pairs(enemies) do
            pcall(function()
                if enemy and enemy.IsAlive and not enemy.IsFakeEnemy and enemy.HealthHandler then
                    local maxHealth = enemy.HealthHandler:GetMaxHealth()
                    if maxHealth > 0 then
                        local currentHealth = enemy.HealthHandler:GetHealth()
                        local name = enemy.DisplayName or "Unknown"
                        local hp = formatPercent(currentHealth / maxHealth)
                        
                        if not enemyGroups[name] then
                            enemyGroups[name] = { count = 1, hps = {hp} }
                        else
                            enemyGroups[name].count = enemyGroups[name].count + 1
                            table.insert(enemyGroups[name].hps, hp)
                        end
                    end
                end
            end)
        end

        local lines = {}
        for name, data in pairs(enemyGroups) do
            table.sort(data.hps)
            local hpString = table.concat(data.hps, ", ")
            local line = string.format("%s (x%d): %s", name, data.count, hpString)
            table.insert(lines, line)
        end
        
        table.sort(lines)
        enemyInfo = table.concat(lines, "\n")
    end

    statusLabel.Text = string.format("Wave: %s | Time: %s\n\n%s", waveStr, timeStr, enemyInfo)
end)