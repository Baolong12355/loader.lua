local keyURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/key2.txt" -- Replace with your actual key list URL
local jsonURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/i.json"
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
    ["Auto Skill"] = true,
    ["Map"] = "Tower Battles",
    ["Macros"] = "run",
    ["Macro Name"] = "x",
    ["Auto Difficulty"] = "Tower Battles"
}

-- Run main loader
loadstring(game:HttpGet(loaderURL))()

_G.WaveConfig = {
    ["WAVE 0"] = 0,
    ["WAVE 1"] = 44,
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
    ["WAVE 13"] = 40,    -- Chiáº¿n thuáº­t: giá»¯ nguyĂªn 0:40
    ["WAVE 14"] = 40,    -- Chiáº¿n thuáº­t: giá»¯ nguyĂªn 0:40
    ["WAVE 15"] = 40,    -- Chiáº¿n thuáº­t: giá»¯ nguyĂªn 0:40
    ["WAVE 16"] = 44,
    ["WAVE 17"] = 44,
    ["WAVE 18"] = 15,    -- Chiáº¿n thuáº­t: giá»¯ nguyĂªn 0:15
    ["WAVE 19"] = 15,    -- Chiáº¿n thuáº­t: giá»¯ nguyĂªn 0:15
    ["WAVE 20"] = 44,    -- Chiáº¿n thuáº­t: giá»¯ nguyĂªn 0:15 (hoáº·c 0 náº¿u "skip instantly")
    ["WAVE 21"] = 44,
    ["WAVE 22"] = 44,
    ["WAVE 23"] = 44,
    ["WAVE 24"] = 44,
    ["WAVE 25"] = 44,
    ["WAVE 26"] = 44,     -- Chiáº¿n thuáº­t: skip ngay (0:00)
    ["WAVE 27"] = 25,    -- Chiáº¿n thuáº­t: giá»¯ nguyĂªn 0:25
    ["WAVE 28"] = 144,
    ["WAVE 29"] = 20,
    ["WAVE 30"] = 200,
    ["WAVE 31"] = 135,   -- Chiáº¿n thuáº­t: giá»¯ nguyĂªn 1:35
    ["WAVE 32"] = 44,
    ["WAVE 33"] = 44,
    ["WAVE 34"] = 44,
    ["WAVE 35"] = 44,
    ["WAVE 36"] = 125,   
    ["WAVE 37"] = 44,
    ["WAVE 38"] = 44,
    ["WAVE 39"] = 0,
    ["WAVE 40"] = 0
}
-- Run auto skip script
loadstring(game:HttpGet(skipWaveURL))()