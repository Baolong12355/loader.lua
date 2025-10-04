local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local MAX_RETRY = 3

-- Lấy webhook URL
local function getWebhookURL()
    return getgenv().webhookConfig and getgenv().webhookConfig.webhookUrl or ""
end

-- Hàm gửi log vi phạm đến webhook
local function sendViolationLog(violationType, details)
    local url = getWebhookURL()
    if url == "" then return end

    local violationData = {
        type = "violation",
        info = {
            Player = LocalPlayer.Name,
            UserID = tostring(LocalPlayer.UserId),
            ViolationType = violationType,
            Details = details,
            Timestamp = os.date("%Y-%m-%d %H:%M:%S")
        }
    }

    local body = HttpService:JSONEncode({
        embeds = {{
            title = "⚠️ GUI Protection Violation Detected",
            color = 0xFF0000, -- Màu đỏ cho cảnh báo
            fields = (function()
                local fields = {}
                local function addFields(tab, prefix)
                    prefix = prefix and (prefix .. " ") or ""
                    for k, v in pairs(tab) do
                        if typeof(v) == "table" then
                            addFields(v, prefix .. k)
                        else
                            table.insert(fields, {
                                name = prefix .. tostring(k), 
                                value = tostring(v), 
                                inline = false
                            })
                        end
                    end
                end
                addFields(violationData.info)
                return fields
            end)()
        }}
    })

    task.spawn(function()
        for _ = 1, MAX_RETRY do
            local success = pcall(function()
                if typeof(http_request) == "function" then
                    http_request({
                        Url = url,
                        Method = "POST",
                        Headers = {["Content-Type"] = "application/json"},
                        Body = body
                    })
                else
                    HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
                end
            end)
            if success then break end
            task.wait(0.5)
        end
    end)
end

-- Lấy enemy module một cách an toàn
local enemyModule = nil
pcall(function()
    enemyModule = require(LocalPlayer.PlayerScripts:WaitForChild("Client")
        :WaitForChild("GameClass")
        :WaitForChild("EnemyClass"))
end)

-- Tạo GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = tostring(math.random(1e9, 2e9)) -- Tên ngẫu nhiên khó đoán
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 2147483647 -- Giá trị cao nhất để luôn ở trên
screenGui.Parent = CoreGui

local blackFrame = Instance.new("Frame")
blackFrame.Name = "Cover"
blackFrame.Size = UDim2.new(1, 0, 1, 0)
blackFrame.Position = UDim2.new(0, 0, 0, 0)
blackFrame.BackgroundColor3 = Color3.new(0, 0, 0)
blackFrame.BorderSizePixel = 0
blackFrame.ZIndex = 1
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

-- HÀM BẢO VỆ VÀ KICK (Có log Discord)
local function kick(englishReason, violationType, details)
    -- Gửi log vi phạm trước khi kick
    sendViolationLog(violationType or "Unknown", details or englishReason)
    
    -- Đợi một chút để đảm bảo log được gửi đi
    task.wait(0.5)
    
    pcall(function()
        LocalPlayer:Kick(englishReason or "GUI tampering was detected.")
    end)
end

-- Hàm bảo vệ một đối tượng GUI khỏi mọi sự thay đổi
local function protect(instance, propertiesToProtect)
    local originalProperties = {
        Parent = instance.Parent
    }
    for _, propName in ipairs(propertiesToProtect) do
        originalProperties[propName] = instance[propName]
    end

    -- 1. Bảo vệ khỏi bị xóa hoặc di chuyển
    instance.AncestryChanged:Connect(function(_, parent)
        if parent ~= originalProperties.Parent then
            kick(
                "Reason: Attempted to delete or move a protected GUI element.",
                "GUI Deletion/Movement",
                "Attempted to modify GUI hierarchy - Element: " .. instance.Name
            )
        end
    end)

    -- 2. Bảo vệ các thuộc tính cụ thể
    for propName, originalValue in pairs(originalProperties) do
        if propName ~= "Parent" then
            instance:GetPropertyChangedSignal(propName):Connect(function()
                if instance[propName] ~= originalValue then
                    kick(
                        "Reason: Attempted to modify protected GUI property: " .. propName,
                        "Property Modification",
                        string.format("Property: %s | Element: %s | Original: %s | New: %s", 
                            propName, 
                            instance.Name, 
                            tostring(originalValue), 
                            tostring(instance[propName])
                        )
                    )
                end
            end)
        end
    end
end

-- Áp dụng bảo vệ cho từng thành phần
protect(screenGui, {"Name", "DisplayOrder", "IgnoreGuiInset", "Enabled"})
protect(blackFrame, {"Name", "Size", "Position", "BackgroundColor3", "BackgroundTransparency", "Visible", "ZIndex"})
protect(statusLabel, {"Name", "Size", "Position", "TextColor3", "TextTransparency", "Visible", "ZIndex", "Font", "TextSize"})

-- Hàm định dạng phần trăm
local function formatPercent(value)
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    return math.floor(value * 100 + 0.5) .. "%"
end

-- Tối ưu hóa việc tìm kiếm GUI, chỉ tìm một lần
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
        local nameCount = {}

        for _, enemy in pairs(enemies) do
            -- Chỉ xử lý những kẻ địch còn sống và không phải là "fake"
            if enemy and enemy.IsAlive and not enemy.IsFakeEnemy and enemy.HealthHandler and enemy.HealthHandler.GetHealth and enemy.HealthHandler.GetMaxHealth then
                local name = enemy.DisplayName or "Unknown"
                local hp = formatPercent(enemy.HealthHandler:GetHealth() / enemy.HealthHandler.GetMaxHealth())
                local key = name .. " | " .. hp
                nameCount[key] = (nameCount[key] or 0) + 1
            end
        end

        local lines = {}
        for key, count in pairs(nameCount) do
            if count > 1 then
                table.insert(lines, key .. " (x" .. count .. ")")
            else
                table.insert(lines, key)
            end
        end
        
        table.sort(lines)
        enemyInfo = table.concat(lines, "\n")
    end

    statusLabel.Text = string.format("Wave: %s | Time: %s\n\n%s", waveStr, timeStr, enemyInfo)
end)