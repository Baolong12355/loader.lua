-- Webhook sender dành riêng cho executor, không chạy trên Roblox server/Studio
-- Tự động tương thích với loadstring và mọi executor phổ biến
-- FIX: Chỉ cho phép HTTPS requests (method 2: http_request)
-- Đã loại bỏ debug log, gửi format đẹp

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- FORCE ENABLE HTTP SERVICE
pcall(function() HttpService.HttpEnabled = true end)

-- Chỉ cho phép trên executor, kiểm tra cả server-side và client-side
local function isExecutor()
    local hasExecutor = typeof(getgenv) == "function" or 
                        typeof(syn) == "table" or 
                        typeof(is_synapse_function) == "function" or
                        typeof(http_request) == "function"
    local RunService = game:GetService("RunService")
    local isServer = RunService:IsServer()
    return hasExecutor and not isServer
end

local function canSend()
    local ok, httpEnabled = pcall(function() return HttpService.HttpEnabled end)
    return ok and httpEnabled and isExecutor()
end

local function formatDiscordEmbed(data, title)
    -- Format theo Discord Embed cho đẹp, chỉ gửi json nếu không có embed
    title = title or (data.type == "game" and "Kết quả trận đấu" or "Thông tin Lobby")
    return HttpService:JSONEncode({
        embeds = {{
            title = title,
            description = "```json\n" .. HttpService:JSONEncode(data) .. "\n```",
            color = 0x5B9DFF
        }}
    })
end

local function sendToWebhook(data)
    if not canSend() then
        return
    end
    local url = "https://discord.com/api/webhooks/972059328276201492/DPHtxfsIldI5lND2dYUbA8WIZwp4NLYsPDG1Sy6-MKV9YMgV8OohcTf-00SdLmyMpMFC"
    local body = formatDiscordEmbed(data)
    -- Method 2: http_request (Universal/Executor)
    if typeof(http_request) == "function" then
        local success, result = pcall(function()
            return http_request({
                Url = url,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = body
            })
        end)
        -- Không log gì thêm
        return
    end
    -- Nếu executor không hỗ trợ, thử fallback (rất hiếm)
    pcall(function()
        HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
    end)
end

local function checkLobby()
    local stats = {
        Level = LocalPlayer.leaderstats and LocalPlayer.leaderstats.Level and LocalPlayer.leaderstats.Level.Value or "N/A",
        Wins  = LocalPlayer.leaderstats and LocalPlayer.leaderstats.Wins and LocalPlayer.leaderstats.Wins.Value or "N/A",
        Gold  = LocalPlayer.PlayerGui and LocalPlayer.PlayerGui.GUI and LocalPlayer.PlayerGui.GUI.NewGoldDisplay 
            and LocalPlayer.PlayerGui.GUI.NewGoldDisplay.GoldText and LocalPlayer.PlayerGui.GUI.NewGoldDisplay.GoldText.Text or "N/A"
    }
    sendToWebhook({type = "lobby", stats = stats})
end

local function waitForGameOverScreen()
    local gui = LocalPlayer.PlayerGui:WaitForChild("Interface")
    local gos = gui:WaitForChild("GameOverScreen", 60)
    if not gos then return end
    repeat wait() until gos.Visible
    return gos
end

local function checkGameOver()
    local gos = waitForGameOverScreen()
    if not gos then return end
    local main = gos.Main
    local rewards, withTokens = nil, false
    local result = {}

    if main:FindFirstChild("RewardsFrameWithTokens") and main.RewardsFrameWithTokens.Visible then
        rewards = main.RewardsFrameWithTokens.InnerFrame
        withTokens = true
    elseif main:FindFirstChild("RewardsFrame") and main.RewardsFrame.Visible then
        rewards = main.RewardsFrame.InnerFrame
        withTokens = false
    end

    if rewards then
        result.Gold = rewards.Gold and rewards.Gold.TextLabel and rewards.Gold.TextLabel.Text or "N/A"
        result.GoldBonus = rewards.Gold and rewards.Gold.BonusTextLabel and rewards.Gold.BonusTextLabel.Text or "N/A"
        result.XP = rewards.XP and rewards.XP.TextLabel and rewards.XP.TextLabel.Text or "N/A"
        result.XPBonus = rewards.XP and rewards.XP.BonusTextLabel and rewards.XP.BonusTextLabel.Text or "N/A"
        if withTokens then
            result.Tokens = rewards.Tokens and rewards.Tokens.TextLabel and rewards.Tokens.TextLabel.Text or "N/A"
        end
    end

    if main:FindFirstChild("InfoFrame") then
        result.Map = main.InfoFrame.Map and main.InfoFrame.Map.Text or "N/A"
        result.Time = main.InfoFrame.Time and main.InfoFrame.Time.Text or "N/A"
        result.Mode = main.InfoFrame.Mode and main.InfoFrame.Mode.Text or "N/A"
    end

    local powerups = {}
    local content = gos.Rewards and gos.Rewards.Content
    if content then
        for _,v in pairs(content:GetChildren()) do
            if v.Name:find("PowerUps") then
                for _,item in pairs(v.Items:GetChildren()) do
                    if item.Name ~= "ItemTemplate" then
                        table.insert(powerups, item.Name)
                    end
                end
            end
        end
    end
    result.PowerUps = powerups

    if main:FindFirstChild("VictoryText") and main.VictoryText.Visible then
        result.Result = "Victory"
    elseif main:FindFirstChild("DefeatText") and main.DefeatText.Visible then
        result.Result = "Defeat"
    else
        result.Result = "Unknown"
    end

    sendToWebhook({type = "game", rewards = result})
end

local function isLobby()
    local gui = LocalPlayer.PlayerGui:FindFirstChild("GUI")
    return gui and gui:FindFirstChild("NewGoldDisplay")
end

if isLobby() then
    checkLobby()
else
    checkGameOver()
end