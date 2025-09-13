local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- webhook
local function getWebhookURL()
    return getgenv().webhookConfig and getgenv().webhookConfig.webhookUrl or ""
end

local function canSend()
    local hasExecutor = typeof(getgenv) == "function" or typeof(http_request) == "function"
    local ok, httpEnabled = pcall(function() return HttpService.HttpEnabled end)
    return hasExecutor and ok and httpEnabled and getWebhookURL() ~= ""
end

local function fieldsFromTable(tab, prefix)
    local fields = {}
    prefix = prefix and (prefix .. " ") or ""
    for k, v in pairs(tab) do
        if typeof(v) == "table" then
            for _, f in ipairs(fieldsFromTable(v, prefix .. k)) do
                table.insert(fields, f)
            end
        else
            table.insert(fields, {name = prefix .. tostring(k), value = tostring(v), inline = false})
        end
    end
    return fields
end

local function sendToWebhook(data)
    if not canSend() then return end
    local body = HttpService:JSONEncode({
        embeds = {{
            title = data.type == "game" and "Game Result" or "Lobby Info",
            color = 0x5B9DFF,
            fields = fieldsFromTable(data.rewards or data.stats or data)
        }}
    })
    local url = getWebhookURL()
    task.spawn(function()
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
    end)
end

-- gửi thông tin lobby nhanh
local function sendLobbyInfo()
    task.spawn(function()
        local gui = LocalPlayer:WaitForChild("PlayerGui", 5)
        if gui then
            local mainGUI = gui:FindFirstChild("GUI")
            local currencyDisplay = mainGUI and mainGUI:FindFirstChild("CurrencyDisplay")
            local goldDisplay = currencyDisplay and currencyDisplay:FindFirstChild("GoldDisplay")
            local valueText = goldDisplay and goldDisplay:FindFirstChild("ValueText")
            local stats = {
                Level = LocalPlayer:FindFirstChild("leaderstats") and LocalPlayer.leaderstats:FindFirstChild("Level") and LocalPlayer.leaderstats.Level.Value or "N/A",
                Wins = LocalPlayer:FindFirstChild("leaderstats") and LocalPlayer.leaderstats:FindFirstChild("Wins") and LocalPlayer.leaderstats.Wins.Value or "N/A",
                Gold = valueText and valueText:IsA("TextLabel") and valueText.Text or "N/A"
            }
            sendToWebhook({type = "lobby", stats = stats})
        end
    end)
end

-- loop check vàng lobby cực nhanh
local function loopCheckLobbyGold()
    local config = getgenv().webhookConfig or {}
    local TARGET_GOLD = config.targetGold
    local ENABLE_KICK = TARGET_GOLD and true or false
    if not TARGET_GOLD then return end

    task.spawn(function()
        while true do
            local gui = LocalPlayer:FindFirstChild("PlayerGui")
            if gui then
                local mainGUI = gui:FindFirstChild("GUI")
                local currencyDisplay = mainGUI and mainGUI:FindFirstChild("CurrencyDisplay")
                local goldDisplay = currencyDisplay and currencyDisplay:FindFirstChild("GoldDisplay")
                local valueText = goldDisplay and goldDisplay:FindFirstChild("ValueText")
                if valueText and valueText:IsA("TextLabel") then
                    local goldAmount = tonumber(valueText.Text:gsub("[$,]", "")) or 0
                    if goldAmount >= TARGET_GOLD then
                        sendToWebhook({
                            type = "lobby",
                            stats = {
                                message = "đã đạt vàng mục tiêu",
                                Gold = tostring(goldAmount),
                                Player = LocalPlayer.Name
                            }
                        })
                        if ENABLE_KICK then
                            LocalPlayer:Kick("đã đạt " .. goldAmount .. " vàng")
                        end
                        break
                    end
                end
            end
            task.wait(0.05) -- tốc độ check cực nhanh
        end
    end)
end

-- hook game reward nhanh
local function hookGameReward()
    task.spawn(function()
        local handler
        local ok = pcall(function()
            handler = require(LocalPlayer.PlayerScripts.Client.UserInterfaceHandler:WaitForChild("GameOverRewardsScreenHandler"))
        end)
        if not ok or not handler then return end

        local old = handler.DisplayScreen
        handler.DisplayScreen = function(delay1, delay2, data)
            task.spawn(function()
                local name = LocalPlayer.Name
                local result = {
                    type = "game",
                    rewards = {
                        Map = data.MapName or "Unknown",
                        Mode = tostring(data.Difficulty or "Unknown"),
                        Time = data.TimeElapsed and tostring(data.TimeElapsed) or "N/A",
                        Result = data.Victory and "Victory" or "Defeat",
                        Gold = tostring((data.PlayerNameToGoldMap and data.PlayerNameToGoldMap[name]) or 0),
                        XP = tostring((data.PlayerNameToXPMap and data.PlayerNameToXPMap[name]) or 0),
                        Tokens = tostring((data.PlayerNameToTokensMap and data.PlayerNameToTokensMap[name]) or 0),
                        PowerUps = {}
                    }
                }
                local powerups = (data.PlayerNameToPowerUpsRewardedMapMap or {})[name] or {}
                for id, count in pairs(powerups) do
                    table.insert(result.rewards.PowerUps, id .. " x" .. tostring(count or 1))
                end
                sendToWebhook(result)
            end)
            return old(delay1, delay2, data)
        end
    end)
end

-- kiểm tra lobby
local function isLobby()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    return gui and gui:FindFirstChild("GUI") and gui.GUI:FindFirstChild("CurrencyDisplay") ~= nil
end

-- chạy nhanh tất cả
if isLobby() then
    sendLobbyInfo()
    loopCheckLobbyGold()
else
    hookGameReward()
end