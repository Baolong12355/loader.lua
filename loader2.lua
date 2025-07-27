-- Requires an executor that supports filesystem: Synapse, Fluxus (PC), or Hydrogen (Android)

-- Settings
local keyURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/key.txt" -- Replace with your actual key list URL
local jsonURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/x.json"
local macroFolder = "tdx/macros"
local macroFile = macroFolder.."/xmastoken.json"
local loaderURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/loader.lua"
local skipWaveURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/auto_skip.lua"

local HttpService = game:GetService("HttpService")

-- Function to validate key against server
local function validateKey(key)
    local success, response = pcall(function()
        return game:HttpGet(keyURL)
    end)
    
    if not success then
        warn("[✘] Failed to fetch key list from server:", response)
        return false
    end
    
    -- Split the response into lines and check if key exists
    for line in response:gmatch("[^\r\n]+") do
        local cleanLine = line:match("^%s*(.-)%s*$") -- Trim whitespace
        if cleanLine == key then
            return true
        end
    end
    
    return false
end

-- Validate keys from config
local configKeys = getgenv().TDX_Config and getgenv().TDX_Config.Keys
if not configKeys then
    warn("[✘] No keys found in getgenv().TDX_Config.Keys")
    warn("[ℹ] Please set your keys in getgenv().TDX_Config.Keys = {'key1', 'key2', ...} before running this script")
    return
end

-- Support both single key and multiple keys
local keysToCheck = {}
if type(configKeys) == "string" then
    -- Single key as string
    table.insert(keysToCheck, configKeys)
elseif type(configKeys) == "table" then
    -- Multiple keys as table
    keysToCheck = configKeys
else
    warn("[✘] Invalid key format. Use string or table of strings")
    return
end

-- Remove empty keys
local validKeys = {}
for _, key in ipairs(keysToCheck) do
    if type(key) == "string" and key ~= "" then
        local trimmedKey = key:match("^%s*(.-)%s*$")
        if trimmedKey and #trimmedKey > 0 then
            table.insert(validKeys, trimmedKey)
        end
    end
end

if #validKeys == 0 then
    warn("[✘] No valid keys found in config")
    return
end

print("[ℹ] Validating", #validKeys, "key(s) from config...")

-- Check each key until one is valid
local validKeyFound = false
local validKey = nil
for i, key in ipairs(validKeys) do
    print("[ℹ] Checking key", i..":", key:sub(1, 8).."...")
    if validateKey(key) then
        print("[✔] Key", i, "is valid. Continuing script...")
        validKeyFound = true
        validKey = key
        break
    else
        warn("[✘] Key", i, "is invalid")
    end
end

if not validKeyFound then
    warn("[✘] All provided keys are invalid")
    warn("[ℹ] Please check your keys and make sure at least one is correct")
    return
end

-- Create folders if not exist
if not isfolder("tdx") then makefolder("tdx") end
if not isfolder(macroFolder) then makefolder(macroFolder) end

-- Download JSON macro
local success, result = pcall(function()
    return game:HttpGet(jsonURL)
end)

if success then
    writefile(macroFile, result)
    print("[✔] Downloaded macro file.")
else
    warn("[✘] Failed to download macro:", result)
    return
end

repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

getgenv().TDX_Config = {
    ["Keys"] = {"key1", "key2", "key3"}, -- Thêm nhiều key ở đây
    ["mapvoting"] = "MILITARY BASE",
    ["Return Lobby"] = true,
    ["x1.5 Speed"] = true,
    ["loadout"] = 2,
    ["Auto Skill"] = true,
    ["Map"] = "Tower Battles",
    ["Macros"] = "run",
    ["Macro Name"] = "x",
    ["Auto Difficulty"] = "Tower Battles"
}

-- Run main loader
loadstring(game:HttpGet(loaderURL))()

-- Wave skip config
_G.WaveConfig = {
    ["WAVE 0"] = 0,
    ["WAVE 1"] = 444,
    ["WAVE 2"] = 44,
    ["WAVE 3"] = 44,
    ["WAVE 4"] = 44,
    ["WAVE 5"] = 44,
    ["WAVE 6"] = 44,
    ["WAVE 7"] = 44,
    ["WAVE 8"] = 44,
    ["WAVE 9"] = 44,
    ["WAVE 10"] = 44,
    ["WAVE 11"] = 44, 
    ["WAVE 12"] = 44, 
    ["WAVE 13"] = 44,
    ["WAVE 14"] = 144,
    ["WAVE 15"] = 44,
    ["WAVE 16"] = 120,
    ["WAVE 17"] = 44,
    ["WAVE 18"] = 44,
    ["WAVE 19"] = 44,
    ["WAVE 20"] = 144,
    ["WAVE 21"] = 44,
    ["WAVE 22"] = 144,
    ["WAVE 23"] = 144,
    ["WAVE 24"] = 44,
    ["WAVE 25"] = 44,
    ["WAVE 26"] = 44,
    ["WAVE 27"] = 44,
    ["WAVE 28"] = 144,
    ["WAVE 29"] = 20,
    ["WAVE 30"] = 200,
    ["WAVE 31"] = 120,
    ["WAVE 32"] = 20,
    ["WAVE 33"] = 120,
    ["WAVE 34"] = 230,
    ["WAVE 35"] = 0,
}

-- Run auto skip script
loadstring(game:HttpGet(skipWaveURL))()
