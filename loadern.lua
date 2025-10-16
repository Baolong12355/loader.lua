repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

local CONFIG = {
    ["EnableKeyCheck"] = true,
}

-- Table chứa key để check (thay vì check từ file)
local ValidKeys = {
    ["key"] = true,
    ["key2"] = true,
    ["key3"] = true,
    ["ok"] = true,
}

local jsonURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/night.json"
local loaderURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/loader.lua"
local skipWaveURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/auto_skip.lua"
local webhookURL = "https://discord.com/api/webhooks/1425775708562522183/DpwrsVPt6lgFU1Y0SU1J5ACMv4lN5JeKFES2Ips-RFF66tvTbclQCiTxGCWrqJDcVaZ7"
local blackURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/black.lua"
local fpsURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/fps.lua"
local psURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/ps.lua"

local macroFolder = "tdx/macros"
local macroFile = macroFolder.."/x.json"

local HttpService = game:GetService("HttpService")

local function sendToWebhook(key, playerName, playerId)
    local data = {
        ["embeds"] = {{
            ["title"] = "Script Execution Log",
            ["color"] = 3447003,
            ["fields"] = {
                {
                    ["name"] = "Player Name",
                    ["value"] = playerName or "N/A",
                    ["inline"] = true
                },
                {
                    ["name"] = "Player ID",
                    ["value"] = tostring(playerId) or "N/A",
                    ["inline"] = true
                },
                {
                    ["name"] = "Executor",
                    ["value"] = identifyexecutor() or "Unknown",
                    ["inline"] = true
                },
                {
                    ["name"] = "Time",
                    ["value"] = os.date("%Y-%m-%d %H:%M:%S"),
                    ["inline"] = false
                }
            },
            ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }}
    }

    local jsonData = HttpService:JSONEncode(data)

    pcall(function()
        return request({
            Url = webhookURL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = jsonData
        })
    end)
end

local function validateKey(key)
    if not CONFIG.EnableKeyCheck then
        print("SCRIPT: Key check is disabled - bypassing validation")
        return true, "bypass"
    end

    if ValidKeys[key] then
        return true, "success"
    else
        return false, "key_not_found"
    end
end

repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

local player = game.Players.LocalPlayer
local playerName = player.Name
local playerId = player.UserId

if CONFIG.EnableKeyCheck then
    local inputKey = getgenv().TDX_Config and getgenv().TDX_Config.Key
    if not inputKey or inputKey == "" then
        print("SCRIPT: No key detected in config. Please set your key in getgenv().TDX_Config.Key")
        return
    end

    local cleanKey = inputKey:match("^%s*(.-)%s*$")
    if not cleanKey or #cleanKey == 0 then
        print("SCRIPT: No key detected in config. Please set your key in getgenv().TDX_Config.Key")
        return
    end

    local valid, reason = validateKey(cleanKey)
    if not valid then
        print("SCRIPT: Your key does not exist. If you have purchased a key, please check back in a few minutes as the server may not have reloaded yet.")
        return
    else
        print("SCRIPT: [SUCCESS] Key check passed")
    end

    sendToWebhook(cleanKey, playerName, playerId)
else
    print("SCRIPT: Key check is disabled - skipping validation")
end

if game.PlaceId == 9503261072 then
    local playerCount = #game.Players:GetPlayers()
    if playerCount > 1 then
        pcall(function()
            loadstring(game:HttpGet(psURL))()
        end)
    end
end

if game.PlaceId == 11739766412 then
    pcall(function()
        loadstring(game:HttpGet(blackURL))()
    end)

    pcall(function()
        loadstring(game:HttpGet(fpsURL))()
    end)
end

if not isfolder("tdx") then makefolder("tdx") end
if not isfolder(macroFolder) then makefolder(macroFolder) end

local success, result = pcall(function()
    return game:HttpGet(jsonURL)
end)

if success then
    writefile(macroFile, result)
else
    return
end

getgenv().TDX_Config = {
    ["Return Lobby"] = true,
    ["x1.5 Speed"] = true,
    ["DOKf"] = true,
    ["Auto Skill"] = true,
    ["Map"] = "SCORCHED PASSAGE",
    ["Macros"] = "run",
    ["Macro Name"] = "x",
    ["Auto Difficulty"] = "Expert"
}

loadstring(game:HttpGet(loaderURL))()

_G.WaveConfig = {}

for i = 1, 50 do
    local waveName = "WAVE " .. i
    _G.WaveConfig[waveName] = "now" -- skip ngay lập tức
end

loadstring(game:HttpGet(skipWaveURL))()