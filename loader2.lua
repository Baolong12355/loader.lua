-- Requires an executor that supports filesystem: Synapse, Fluxus (PC), or Hydrogen (Android)

-- Settings
local keyURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/key.txt" -- Replace with your actual key list URL
local jsonURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/x.json"
local macroFolder = "tdx/macros"
local macroFile = macroFolder.."/x.json"
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

-- Validate key from config
local inputKey = getgenv().TDX_Config and getgenv().TDX_Config.Key
if not inputKey or inputKey == "" then
    warn("[✘] No key found in getgenv().TDX_Config.Key")
    warn("[ℹ] Please set your key in getgenv().TDX_Config.Key before running this script")
    return
end

-- Clean the input key
local cleanKey = inputKey:match("^%s*(.-)%s*$")
if not cleanKey or #cleanKey == 0 then
    warn("[✘] Invalid key format in config")
    return
end

print("[ℹ] Validating key from config...")
print("[ℹ] Checking key:", cleanKey:sub(1, 8).."...")

local valid = validateKey(cleanKey)
if not valid then
    warn("[✘] Invalid key provided in config:", cleanKey)
    warn("[ℹ] Please check your key and make sure it's in the valid key list")
    return
else
    print("[✔] Key is valid. Continuing script...")
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
    ["Key"] = "your_access_key_here", -- Chỉ 1 key duy nhất
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
