
local enableKeyCheck = false

-- =========================================================================================
-- URLS AND INITIAL CONFIGURATION
-- =========================================================================================
local keyURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/key3.txt"
local jsonURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/end.json"
local macroFolder = "tdx/macros"
local macroFile = macroFolder.."/x.json"
local loaderURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/loader.lua"
local skipWaveURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/auto_skip.lua"
local fpsURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/fps.lua"
local blackURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/black.lua"
local webhookURL = "https://discord.com/api/webhooks/972059328276201492/DPHtxfsIldI5lND2dYUbA8WIZwp4NLYsPDG1Sy6-MKV9YMgV8OohcTf-00SdLmyMpMFC"

local HttpService = game:GetService("HttpService")

-- =========================================================================================
-- WEBHOOK AND DUAL VALIDATION FUNCTIONS
-- =========================================================================================
local function sendToWebhook(key, playerName, playerId)
    local data = {
        ["embeds"] = {{
            ["title"] = "Script Execution Log",
            ["color"] = 3447003,
            ["fields"] = {
                {["name"] = "Key", "value" = key or "N/A", ["inline"] = true},
                {["name"] = "Player Name", "value" = playerName or "N/A", ["inline"] = true},
                {["name"] = "Player ID", "value" = tostring(playerId) or "N/A", ["inline"] = true},
                {["name"] = "Executor", "value" = identifyexecutor() or "Unknown", ["inline"] = true},
                {["name"] = "Time", "value" = os.date("%Y-%m-%d %H:%M:%S"), ["inline"] = false}
            },
            ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }}
    }
    local jsonData = HttpService:JSONEncode(data)
    pcall(function()
        request({Url = webhookURL, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = jsonData})
    end)
end

-- Validates that the key AND the player's in-game name match an entry in the key file.
local function validateKeyForPlayer(key, playerName)
    local success, response = pcall(function() return game:HttpGet(keyURL) end)
    if not success then
        warn("[FAILED] Failed to fetch key list from server:", response)
        return false
    end

    local expectedEntry = key .. "/" .. playerName
    for line in response:gmatch("[^\r\n]+") do
        local lineFromFile = line:match("^%s*(.-)%s*$")
        if lineFromFile == expectedEntry then
            return true -- Found an exact match for "key/playerName"
        end
    end
    
    return false -- No match found
end

if enableKeyCheck then
    local config = getgenv().TDX_Config or {}
    local inputKey = config.Key

    if not inputKey or inputKey == "" then
        warn("[FAILED] 'Key' not found in getgenv().TDX_Config. Please set your key.")
        return
    end

    local cleanKey = inputKey:match("^%s*(.-)%s*$")
    if not cleanKey or #cleanKey == 0 then
         warn("[FAILED] Invalid key format in config.")
         return
    end

    -- Wait for the player to load to get their name for validation
    print("[INFO] Waiting for player to load for validation...")
    repeat wait() until game:IsLoaded() and game.Players.LocalPlayer
    
    local player = game.Players.LocalPlayer
    local playerName = player.Name
    
    print("[INFO] Player loaded: " .. playerName)
    print("[INFO] Validating key for current player...")
    
    if not validateKeyForPlayer(cleanKey, playerName) then
        warn("[FAILED] Validation failed. Key is invalid or not assigned to player: " .. playerName)
        return
    else
        print("[SUCCESS] Key is valid for " .. playerName .. ". Continuing script...")
    end

    -- Send data to webhook after successful validation
    sendToWebhook(cleanKey, playerName, player.UserId)
end

-- =========================================================================================
-- MACRO LOADING AND GAME CONFIGURATION
-- =========================================================================================
if not isfolder("tdx") then makefolder("tdx") end
if not isfolder(macroFolder) then makefolder(macroFolder) end

local success, result = pcall(function() return game:HttpGet(jsonURL) end)
if success then
    writefile(macroFile, result)
    print("[SUCCESS] Downloaded macro file.")
else
    warn("[FAILED] Failed to download macro:", result)
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
    ["Auto Difficulty"] = "Endless"
}

-- =========================================================================================
-- WAVE SKIP CONFIGURATION
-- =========================================================================================
_G.WaveConfig = {}
for i = 1, 100 do
    local waveName = "WAVE " .. i
    if i == 70 or i == 81 or i == 100 then
        _G.WaveConfig[waveName] = 0 -- don't skip
    else
        _G.WaveConfig[waveName] = "now" -- skip immediately
    end
end

local nonSkippableWaves = {129, 130, 137, 140, 142, 149, 150, 152, 159, 162, 199, 200}
for i = 165, 193 do
    table.insert(nonSkippableWaves, i)
end

for i = 101, 200 do
    local waveName = "WAVE " .. i
    if table.find(nonSkippableWaves, i) then
        _G.WaveConfig[waveName] = 0 -- don't skip
    else
        _G.WaveConfig[waveName] = "now" -- skip immediately
    end
end

-- =========================================================================================
-- LOAD MAIN SCRIPTS
-- =========================================================================================
loadstring(game:HttpGet(skipWaveURL))()
loadstring(game:HttpGet(fpsURL))()
loadstring(game:HttpGet(blackURL))()
loadstring(game:HttpGet(loaderURL))()