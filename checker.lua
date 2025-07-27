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
                table.insert(fields, {name = prefix .. tostring(k), value = table.concat(v, "\n"), inline = false})
            else
                for _,f in ipairs(fieldsFromTable(v, prefix .. k)) do
                    table.insert(fields, f)
                end
            end
        else
            table.insert(fields, {name = prefix .. tostring(k), value = tostring(v), inline = false})
        end
    end
    return fields
end

local function formatDiscordEmbed(data, title)
    title = title or (data.type == "game" and "Kết quả trận đấu" or "Thông tin Lobby")
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
    local url = (_G.urlConfig and _G.urlConfig.url) or ""
    if url == "" then
        warn("Chưa cấu hình _G.urlConfig.url")
        return
    end
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

local function extractNumber(str)
    if not str then return 1 end
    local n = string.match(str, "%d+")
    return n and tonumber(n) or 1
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
        -- Gold: chỉ lấy gốc, không cộng bonus
        result.Gold = rewards.Gold and rewards.Gold.TextLabel and rewards.Gold.TextLabel.Text or "N/A"

        -- XP: nếu có bonus visible thì lấy số bonus cộng với số gốc
        local xp = rewards.XP and rewards.XP.TextLabel and rewards.XP.TextLabel.Text or "0"
        local xpBase = tonumber((xp or ""):gsub(",", ""):match("%d+")) or 0
        local xpBonus = 0
        if rewards.XP and rewards.XP.BonusTextLabel and rewards.XP.BonusTextLabel.Visible then
            local bonusText = rewards.XP.BonusTextLabel.Text or ""
            xpBonus = tonumber(bonusText:gsub(",", ""):match("%d+")) or 0
        end
        result.XP = tostring(xpBase + xpBonus)

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
                    if item:IsA("UIListLayout") then continue end
                    local count = 1
                    if item:FindFirstChild("CountText") then
                        count = extractNumber(item.CountText.Text)
                    end
                    table.insert(powerups, item.Name .. " x" .. tostring(count))
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