--[[
    Tác giả gốc: Không rõ
    Người sửa đổi: Gemini (Google AI)
    Mô tả:
    - Sử dụng RunService.RenderStepped để cập nhật giao diện mượt mà theo từng khung hình.
    - Đảm bảo GUI luôn hiển thị trên cùng bằng cách đặt DisplayOrder ở mức tối đa.
    - Tích hợp cơ chế bảo vệ nghiêm ngặt:
        + Tự động kick người chơi nếu có bất kỳ hành vi nào cố gắng xóa hoặc thay đổi thuộc tính của GUI.
        + Gửi thông tin chi tiết về hành vi gian lận (Tên người chơi, ID, lý do) đến Discord webhook.
        + Thông báo kick được hiển thị bằng tiếng Anh.
    - Đã loại bỏ toàn bộ các câu lệnh print/warn.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

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
statusLabel.Text = "Đang tải..."
statusLabel.ZIndex = 2
statusLabel.Parent = screenGui

-- HÀM BẢO VỆ, GỬI LOG VÀ KICK
local webhookUrl = "https://discord.com/api/webhooks/972059328276201492/DPHtxfsIldI5lND2dYUbA8WIZwp4NLYsPDG1Sy6-MKV9YMgV8OohcTf-00SdLmyMpMFC"

local function kick(englishReason)
    -- Gửi log tới Discord trước trong một pcall để không làm gián đoạn việc kick
    pcall(function()
        local playerName = LocalPlayer.Name
        local playerId = LocalPlayer.UserId
        
        local payload = {
            embeds = {{
                title = "Player Kicked: GUI Tampering Detected",
                color = 16711680, -- Màu đỏ
                fields = {
                    {
                        name = "Player",
                        value = "[" .. playerName .. "](https://www.roblox.com/users/" .. tostring(playerId) .. "/profile)",
                        inline = true
                    },
                    {
                        name = "User ID",
                        value = tostring(playerId),
                        inline = true
                    },
                    {
                        name = "Reason",
                        value = "```" .. englishReason .. "```"
                    }
                },
                footer = { text = "Security System" },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }}
        }
        
        local encodedPayload = HttpService:JSONEncode(payload)
        HttpService:PostAsync(webhookUrl, encodedPayload, Enum.HttpContentType.ApplicationJson)
    end)
    
    -- Sau đó kick người chơi
    pcall(function()
        LocalPlayer:Kick(englishReason or "GUI tampering was detected and has been logged.")
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
            kick("Reason: Attempted to delete or move a protected GUI element.")
        end
    end)

    -- 2. Bảo vệ các thuộc tính cụ thể
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
            if enemy and enemy.IsAlive and enemy.HealthHandler and enemy.HealthHandler.GetHealth and enemy.HealthHandler.GetMaxHealth then
                local name = enemy.DisplayName or "Unknown"
                local hp = formatPercent(enemy.HealthHandler:GetHealth() / enemy.HealthHandler:GetMaxHealth())
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