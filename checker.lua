--[[ 
    Script này chỉ gửi webhook khi chạy dưới executor (loadstring, synapse, etc)
    và KHÔNG hoạt động trên Roblox server hoặc môi trường không hỗ trợ HTTP client-side.
    Đảm bảo an toàn, không lỗi trên môi trường Roblox gốc!
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Kiểm tra có phải executor, có HTTP client-side và có thể gửi HTTPS request
local function isExecutor()
    -- Hầu hết executor đều có getgenv, is_synapse_function hoặc syn
    if typeof(getgenv) == "function" then return true end
    if typeof(is_synapse_function) == "function" then return true end
    if typeof(syn) == "table" then return true end
    -- Có thể bổ sung thêm các check đặc trưng executor khác ở đây nếu cần
    return false
end

local function canSend()
    -- Chỉ gửi nếu là executor, và HttpService cho phép, Roblox chỉ cho HTTPS
    local ok, httpEnabled = pcall(function() return HttpService.HttpEnabled end)
    return ok and httpEnabled and isExecutor()
end

local function sendToWebhook(data)
    if not canSend() then
        warn("[Webhook] Không phải executor hoặc HttpService không cho phép, dừng gửi.")
        return
    end
    local url = "https://discord.com/api/webhooks/972059328276201492/DPHtxfsIldI5lND2dYUbA8WIZwp4NLYsPDG1Sy6-MKV9YMgV8OohcTf-00SdLmyMpMFC"
    local body = HttpService:JSONEncode({content = "```json\n"..HttpService:JSONEncode(data).."\n```"})
    -- Sử dụng pcall để không crash script nếu lỗi
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

    -- Kiểm tra RewardsFrameWithTokens hay RewardsFrame
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

    -- InfoFrame
    if main:FindFirstChild("InfoFrame") then
        result.Map = main.InfoFrame.Map and main.InfoFrame.Map.Text or "N/A"
        result.Time = main.InfoFrame.Time and main.InfoFrame.Time.Text or "N/A"
        result.Mode = main.InfoFrame.Mode and main.InfoFrame.Mode.Text or "N/A"
    end

    -- PowerUps
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

    -- Win/Lose
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