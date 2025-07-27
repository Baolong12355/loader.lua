local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

pcall(function() HttpService.HttpEnabled = true end)

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

local function fieldsFromTable(tab, prefix)
    local fields = {}
    prefix = prefix and (prefix .. " ") or ""
    for k,v in pairs(tab) do
        if typeof(v) == "table" then
            if #v > 0 then
                table.insert(fields, {name = prefix .. tostring(k), value = table.concat(v, ", "), inline = true})
            else
                for _,f in ipairs(fieldsFromTable(v, prefix .. k)) do
                    table.insert(fields, f)
                end
            end
        else
            table.insert(fields, {name = prefix .. tostring(k), value = tostring(v), inline = true})
        end
    end
    return fields
end

local function formatDiscordEmbed(data, title)
    title = title or (data.type == "game" and "match" or "stats")
    local fields = {}
    if data.type == "lobby" and data.stats then
        fields = fieldsFromTable(data.stats)
    elseif data.type == "game" and data.rewards then
        fields = fieldsFromTable(data.rewards)
    else
        fields = fieldsFromTable(data)
    end
    return HttpService:JSONEncode({
        embeds = {{
            title = title,
            color = 0x5B9DFF,
            fields = fields
        }}
    })
end

local function sendToWebhook(data)
    if not canSend() then return end
    local url = "https://discord.com/api/webhooks/972059328276201492/DPHtxfsIldI5lND2dYUbA8WIZwp4NLYsPDG1Sy6-MKV9YMgV8OohcTf-00SdLmyMpMFC"
    local body = formatDiscordEmbed(data)
    if typeof(http_request) == "function" then
        pcall(function()
            http_request({
                Url = url,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = body
            })
        end)
    else
        pcall(function()
            HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
        end)
    end
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

-- Helper: Nếu có bonus visible, hiển thị "gốc + bonus", ngược lại chỉ trả về giá trị gốc
local function valueWithBonus(value, bonus)
    if bonus and tostring(bonus) ~= "" then
        return tostring(value) .. " + " .. tostring(bonus)
    else
        return tostring(value)
    end
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
        -- Gold
        local gold = rewards.Gold and rewards.Gold.TextLabel and rewards.Gold.TextLabel.Text or "N/A"
        local goldBonus = (rewards.Gold and rewards.Gold.BonusTextLabel and rewards.Gold.BonusTextLabel.Visible) and rewards.Gold.BonusTextLabel.Text or nil
        result.Gold = goldBonus and valueWithBonus(gold, goldBonus) or gold

        -- XP
        local xp = rewards.XP and rewards.XP.TextLabel and rewards.XP.TextLabel.Text or "N/A"
        local xpBonus = (rewards.XP and rewards.XP.BonusTextLabel and rewards.XP.BonusTextLabel.Visible) and rewards.XP.BonusTextLabel.Text or nil
        result.XP = xpBonus and valueWithBonus(xp, xpBonus) or xp

        -- Tokens (nếu có)
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