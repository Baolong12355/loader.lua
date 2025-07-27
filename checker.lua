local loadstring = loadstring or load
local http_request = http_request or request or (syn and syn.request) or (fluxus and fluxus.request) or http.request

local WEBHOOK_URL = "https://discord.com/api/webhooks/972059328276201492/DPHtxfsIldI5lND2dYUbA8WIZwp4NLYsPDG1Sy6-MKV9YMgV8OohcTf-00SdLmyMpMFC"

local function sendToDiscord(data)
    local success, err = pcall(function()
        local payload = {
            ["content"] = data.content,
            ["embeds"] = data.embeds
        }
        
        http_request({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = game:GetService("HttpService"):JSONEncode(payload)
        })
    end)
    
    if not success then
        warn("Failed to send to Discord:", err)
    end
end

local function getLobbyStats()
    local player = game:GetService("Players").LocalPlayer
    local stats = {}
    
    if player:FindFirstChild("leaderstats") then
        stats.Level = player.leaderstats.Level.Value
        stats.Wins = player.leaderstats.Wins.Value
    end
    
    if player.PlayerGui:FindFirstChild("GUI") and player.PlayerGui.GUI:FindFirstChild("NewGoldDisplay") then
        stats.Gold = player.PlayerGui.GUI.NewGoldDisplay.GoldText.Text
    end
    
    return stats
end

local function getMatchResults()
    local player = game:GetService("Players").LocalPlayer
    local results = {}
    
    -- Wait for GameOverScreen to be visible
    while not (player.PlayerGui.Interface.GameOverScreen and player.PlayerGui.Interface.GameOverScreen.Visible) do
        wait(1)
    end
    
    local gameOverScreen = player.PlayerGui.Interface.GameOverScreen
    local rewardsFrame = gameOverScreen.Main.RewardsFrameWithTokens.Visible and 
                         gameOverScreen.Main.RewardsFrameWithTokens or 
                         gameOverScreen.Main.RewardsFrame
    
    -- Get rewards
    if rewardsFrame:FindFirstChild("InnerFrame") then
        local innerFrame = rewardsFrame.InnerFrame
        
        -- Gold
        if innerFrame:FindFirstChild("Gold") then
            results.Gold = innerFrame.Gold.TextLabel.Text
            if innerFrame.Gold:FindFirstChild("BonusTextLabel") then
                results.GoldBonus = innerFrame.Gold.BonusTextLabel.Text
            end
        end
        
        -- XP
        if innerFrame:FindFirstChild("XP") then
            results.XP = innerFrame.XP.TextLabel.Text
            if innerFrame.XP:FindFirstChild("BonusTextLabel") then
                results.XPBonus = innerFrame.XP.BonusTextLabel.Text
            end
        end
        
        -- Tokens (only if WithTokens frame)
        if rewardsFrame.Name == "RewardsFrameWithTokens" and innerFrame:FindFirstChild("Tokens") then
            results.Tokens = innerFrame.Tokens.TextLabel.Text
            if innerFrame.Tokens:FindFirstChild("BonusTextLabel") then
                results.TokensBonus = innerFrame.Tokens.BonusTextLabel.Text
            end
        end
    end
    
    -- Get match info
    if gameOverScreen.Main:FindFirstChild("InfoFrame") then
        local infoFrame = gameOverScreen.Main.InfoFrame
        results.Map = infoFrame.Map.Text
        results.Time = infoFrame.Time.Text
        results.Mode = infoFrame.Mode.Text
    end
    
    -- Check win/lose
    if gameOverScreen.Main:FindFirstChild("VictoryText") and gameOverScreen.Main.VictoryText.Visible then
        results.Result = "Victory"
    elseif gameOverScreen.Main:FindFirstChild("DefeatText") and gameOverScreen.Main.DefeatText.Visible then
        results.Result = "Defeat"
    else
        results.Result = "Unknown"
    end
    
    -- Get powerups
    results.Powerups = {}
    for i = 1, 5 do -- Assuming max 5 powerup sections
        local powerupsContainer = gameOverScreen.Rewards.Content:FindFirstChild("PowerUps"..i)
        if powerupsContainer then
            for _, item in ipairs(powerupsContainer.Items:GetChildren()) do
                if item.Name ~= "ItemTemplate" and item:IsA("Frame") then
                    table.insert(results.Powerups, item.Name)
                end
            end
        end
    end
    
    return results
end

local function createLobbyEmbed(stats)
    local embed = {
        title = "Lobby Stats",
        color = 0x00FF00,
        fields = {
            {
                name = "Level",
                value = tostring(stats.Level or "N/A"),
                inline = true
            },
            {
                name = "Wins",
                value = tostring(stats.Wins or "N/A"),
                inline = true
            },
            {
                name = "Gold",
                value = tostring(stats.Gold or "N/A"),
                inline = true
            }
        },
        timestamp = DateTime.now():ToIsoDate()
    }
    
    return embed
end

local function createMatchEmbed(results)
    local embed = {
        title = "Match Results - " .. results.Result,
        color = results.Result == "Victory" and 0x00FF00 or 0xFF0000,
        fields = {}
    }
    
    -- Add basic info
    table.insert(embed.fields, {
        name = "Map",
        value = results.Map or "N/A",
        inline = true
    })
    table.insert(embed.fields, {
        name = "Mode",
        value = results.Mode or "N/A",
        inline = true
    })
    table.insert(embed.fields, {
        name = "Time",
        value = results.Time or "N/A",
        inline = true
    })
    
    -- Add rewards
    table.insert(embed.fields, {
        name = "Gold",
        value = (results.Gold or "0") .. (results.GoldBonus and (" (+" .. results.GoldBonus .. ")") or "",
        inline = true
    })
    table.insert(embed.fields, {
        name = "XP",
        value = (results.XP or "0") .. (results.XPBonus and (" (+" .. results.XPBonus .. ")") or ""),
        inline = true
    })
    
    if results.Tokens then
        table.insert(embed.fields, {
            name = "Tokens",
            value = results.Tokens .. (results.TokensBonus and (" (+" .. results.TokensBonus .. ")") or ""),
            inline = true
        })
    end
    
    -- Add powerups if any
    if #results.Powerups > 0 then
        table.insert(embed.fields, {
            name = "Powerups (" .. #results.Powerups .. ")",
            value = table.concat(results.Powerups, "\n"),
            inline = false
        })
    end
    
    embed.timestamp = DateTime.now():ToIsoDate()
    
    return embed
end

-- Main logic
local function main()
    -- Check if we're in lobby or in match
    local inLobby = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("GUI") ~= nil
    
    if inLobby then
        local stats = getLobbyStats()
        sendToDiscord({
            content = "Lobby stats update",
            embeds = {createLobbyEmbed(stats)}
        })
    else
        local results = getMatchResults()
        sendToDiscord({
            content = "Match completed: " .. results.Result,
            embeds = {createMatchEmbed(results)}
        })
    end
end

-- Run the script
main()