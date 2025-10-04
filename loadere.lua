
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

-- Make sure the config table exists. This is the fix for the 'nil' error.
getgenv().TDX_Config = getgenv().TDX_Config or {}

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

local function validateKeyForPlayer(key, playerName)
    local success, response = pcall(function() return game:HttpGet(keyURL) end)
    if not success then
        warn("[FAILED] Failed to fetch key list from server:", response)
        return false
    end
    local expectedEntry = key .. "/" .. playerName
    for line in response:gmatch("[^\r\n]+") do
        if line:match("^%s*(.-)%s*$") == expectedEntry then
            return true
        end
    end
    return false
end

if enableKeyCheck then
    local inputKey = getgenv().TDX_Config.Key
    if not inputKey or inputKey == "" then
        warn("[FAILED] 'Key' not found or is empty in getgenv().TDX_Config. Please set your key.")
        return
    end
    local cleanKey = inputKey:match("^%s*(.-)%s*$")
    
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

-- This section now MERGES settings instead of OVERWRITING the table, preserving your Key.
local config = getgenv().TDX_Config
config["Return Lobby"] = true
config["x1.5 Speed"] = true
config["DOKf"] = true
config["Auto Skill"] = true
config["Map"] = "SCORCHED PASSAGE"
config["Macros"] = "run"
config["Macro Name"] = "x"
config["Auto Difficulty"] = "Endless"

-- =========================================================================================
-- WAVE SKIP CONFIGURATION
-- =========================================================================================
_G.WaveConfig = {}
for i = 1, 100 do
    local waveName = "WAVE " .. i
    if i == 70 or i == 81 or i == 100 then
        _G.WaveConfig[waveName] = 0
    else
        _G.WaveConfig[waveName] = "now"
    end
end

local nonSkippableWaves = {129, 130, 137, 140, 142, 149, 150, 152, 159, 162, 199, 200}
for i = 165, 193 do
    table.insert(nonSkippableWaves, i)
end

for i = 101, 200 do
    local waveName = "WAVE " .. i
    if table.find(nonSkippableWaves, i) then
        _G.WaveConfig[waveName] = 0
    else
        _G.WaveConfig[waveName] = "now"
    end
end

-- =========================================================================================
-- LOAD MAIN SCRIPTS
-- =========================================================================================
loadstring(game:HttpGet(skipWaveURL))()
loadstring(game:HttpGet(fpsURL))()
loadstring(game:HttpGet(blackURL))()
loadstring(game:HttpGet(loaderURL))()