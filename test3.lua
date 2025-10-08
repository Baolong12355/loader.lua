
repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local MAX_RETRY = 3

local function getWebhookURL()
    return getgenv().webhookConfig and getgenv().webhookConfig.webhookUrl or ""
end

local function formatTime(seconds)
    seconds = tonumber(seconds)
    if not seconds then return "N/A" end
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%dm %ds", mins, secs)
end

local function sendToWebhook(data)
    local url = getWebhookURL()
    if url == "" then return end

    local body = HttpService:JSONEncode({
        embeds = {{
            title = data.type == "game" and "Game Result" or "Lobby Info",
            color = 0x5B9DFF,
            fields = (function()
                local fields = {}
                local function addFields(tab, prefix)
                    prefix = prefix and (prefix .. " ") or ""
                    for k, v in pairs(tab) do
                        if typeof(v) == "table" then
                            addFields(v, prefix .. k)
                        else
                            table.insert(fields, {name = prefix .. tostring(k), value = tostring(v), inline = false})
                        end
                    end
                end
                addFields(data.rewards or data.stats or data)
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
        end
    end)
end

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

            local success, result = pcall(function()
                local ReplicatedStorage = game:GetService("ReplicatedStorage")
                local Data = require(ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Client"):WaitForChild("Services"):WaitForChild("Data"))
                local ShopData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ShopDataV2"))

                local inventory = Data.Get("Inventory")
                local ownedTowers = inventory.Towers or {}
                local ownedPowerUps = inventory.PowerUps or {}
                local allTowers = ShopData.Items.Towers

                local towerList = {}
                if getgenv().webhookConfig and getgenv().webhookConfig.logInventory then
                    for id, data in pairs(allTowers) do
                        if ownedTowers[id] then
                            table.insert(towerList, data.ViewportName or tostring(id))
                        end
                    end
                end

                local powerupList = {}
                for id, amount in pairs(ownedPowerUps) do
                    if type(amount) == "number" and amount > 0 then
                        table.insert(powerupList, id .. " x" .. tostring(amount))
                    end
                end

                local statsData = {
                    PowerUps = table.concat(powerupList, ", ")
                }

                if #towerList > 0 then
                    statsData.Towers = table.concat(towerList, ", ")
                end

                sendToWebhook({
                    type = "lobby",
                    stats = statsData
                })
            end)
        end
    end)
end

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
                                message = "Target gold reached",
                                Gold = tostring(goldAmount),
                                Player = LocalPlayer.Name
                            }
                        })
                        if ENABLE_KICK then
                            LocalPlayer:Kick("Reached " .. goldAmount .. " gold")
                        end
                        break
                    end
                end
            end
            task.wait(0.25)
        end
    end)
end

local function hookGameReward()
    task.spawn(function()
        local handler
        local ok = pcall(function()
            handler = require(LocalPlayer.PlayerScripts.Client.UserInterfaceHandler:WaitForChild("GameOverScreenHandler"))
        end)
        if not ok or not handler then return end

        local old = handler.DisplayScreen
        handler.DisplayScreen = function(data)
            task.spawn(function()
                local name = LocalPlayer.Name
                local result = {
                    type = "game",
                    rewards = {
                        Map = data.MapName or "Unknown",
                        Mode = tostring(data.Difficulty or "Unknown"),
                        Result = data.Victory and "Victory" or "Defeat",
                        Wave = data.LastPassedWave and tostring(data.LastPassedWave) or "N/A",
                        Time = formatTime(data.TimeElapsed),
                        Gold = tostring((data.PlayerNameToGoldMap and data.PlayerNameToGoldMap[name]) or 0),
                        Tokens = tostring((data.PlayerNameToTokensMap and data.PlayerNameToTokensMap[name]) or 0),
                        XP = tostring((data.PlayerNameToXPMap and data.PlayerNameToXPMap[name]) or 0),
                        PowerUps = {}
                    }
                }
                local powerups = (data.PlayerNameToPowerUpsRewardedMapMap or {})[name] or {}
                for id, count in pairs(powerups) do
                    table.insert(result.rewards.PowerUps, id .. " x" .. tostring(count or 1))
                end

                pcall(function()
                    local EnemyClass = require(LocalPlayer.PlayerScripts.Client.GameClass:WaitForChild("EnemyClass"))
                    local remainingEnemies = EnemyClass.GetEnemies()
                    local enemyList = {}

                    for _, enemy in pairs(remainingEnemies) do
                        if enemy and enemy:Alive() then -- Only log living enemies
                            local enemyName = enemy.DisplayName or enemy.Type or "Unknown Enemy"
                            
                            -- Health
                            local hp = "N/A"
                            if enemy.HealthHandler then
                                hp = string.format("%.0f/%.0f", enemy.HealthHandler:GetHealth(), enemy.HealthHandler:GetMaxHealth())
                            end
                            
                            -- Shield (conditional)
                            local shieldInfo = ""
                            if enemy.HealthHandler and enemy.HealthHandler:GetMaxShield and enemy.HealthHandler:GetMaxShield() > 0 then
                                local shield = string.format("%.0f/%.0f", enemy.HealthHandler:GetShield(), enemy.HealthHandler:GetMaxShield())
                                shieldInfo = " | Shield: " .. shield
                            end

                            -- Special Attributes (conditional)
                            local attributes = {}
                            if enemy.IsBoss then table.insert(attributes, "Boss") end
                            if enemy.IsMiniBoss then table.insert(attributes, "Mini-Boss") end
                            if enemy.Stealth then table.insert(attributes, "Stealth") end
                            if enemy.Invulnerable then table.insert(attributes, "Invulnerable") end
                            if enemy.TakeNoDamage then table.insert(attributes, "Damage Immune") end

                            -- Resistances (conditional)
                            if enemy.DamageReductionMap then
                                for dmgType, reduction in pairs(enemy.DamageReductionMap) do
                                    if reduction > 0 then
                                        table.insert(attributes, string.format("%s Resistance (%.0f%%)", tostring(dmgType), reduction * 100))
                                    end
                                end
                            end

                            -- Build the final string
                            local enemyInfo = string.format("%s - HP: %s%s", enemyName, hp, shieldInfo)
                            if #attributes > 0 then
                                enemyInfo = enemyInfo .. " (" .. table.concat(attributes, ", ") .. ")"
                            end
                            table.insert(enemyList, enemyInfo)
                        end
                    end

                    if #enemyList > 0 then
                        -- Discord's character limit for a field value is 1024
                        local enemyString = table.concat(enemyList, "\n")
                        if string.len(enemyString) > 1024 then
                            enemyString = string.sub(enemyString, 1, 1020) .. "\n..."
                        end
                        result.rewards["Remaining Enemies"] = enemyString
                    end
                end)
                --- END OF NEW CODE ---

                sendToWebhook(result)
            end)
            return old(data)
        end
    end)
end

local function isLobby()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    return gui and gui:FindFirstChild("GUI") and gui.GUI:FindFirstChild("CurrencyDisplay") ~= nil
end

if isLobby() then
    sendLobbyInfo()
    loopCheckLobbyGold()
else
    hookGameReward()
end
