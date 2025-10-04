-- ============================================
-- CONFIG SETTINGS
-- ============================================
local CONFIG = {
    ["EnableKeyCheck"] = false,  -- Đặt false để tắt check key
}

-- ============================================
-- URLS
-- ============================================
local keyURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/key3.txt"
local jsonURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/end.json"
local loaderURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/loader.lua"
local skipWaveURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/auto_skip.lua"
local webhookURL = "https://discord.com/api/webhooks/972059328276201492/DPHtxfsIldI5lND2dYUbA8WIZwp4NLYsPDG1Sy6-MKV9YMgV8OohcTf-00SdLmyMpMFC"

local blackURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/black.lua"
local fpsURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/fps.lua"

local macroFolder = "tdx/macros"
local macroFile = macroFolder.."/x.json"

local HttpService = game:GetService("HttpService")

-- ============================================
-- WEBHOOK FUNCTION
-- ============================================
local function sendToWebhook(key, playerName, playerId)
    local data = {
        ["embeds"] = {{
            ["title"] = "Script Execution Log",
            ["color"] = 3447003,
            ["fields"] = {
                {
                    ["name"] = "Key",
                    ["value"] = key or "N/A",
                    ["inline"] = true
                },
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

-- ============================================
-- KEY VALIDATION (Format: key/name)
-- ============================================
local function validateKey(key, playerName)
    if not CONFIG.EnableKeyCheck then
        return true, "bypass"
    end
    
    local success, response = pcall(function()
        return game:HttpGet(keyURL)
    end)

    if not success then
        return false, "fetch_error"
    end

    local keyExists = false
    
    for line in response:gmatch("[^\r\n]+") do
        local cleanLine = line:match("^%s*(.-)%s*$")
        
        if cleanLine and #cleanLine > 0 then
            local keyPart, namePart = cleanLine:match("^(.+)/(.+)$")
            
            if keyPart and namePart then
                keyPart = keyPart:match("^%s*(.-)%s*$")
                namePart = namePart:match("^%s*(.-)%s*$")
                
                if keyPart == key then
                    keyExists = true
                    if namePart == playerName then
                        return true, "success"
                    else
                        return false, "wrong_name"
                    end
                end
            end
        end
    end

    if not keyExists then
        return false, "key_not_found"
    end
    
    return false, "unknown"
end

-- ============================================
-- MAIN EXECUTION
-- ============================================
repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

local player = game.Players.LocalPlayer
local playerName = player.Name
local playerId = player.UserId

-- Lưu key trước khi validate
local existingKey = getgenv().TDX_Config and getgenv().TDX_Config.Key

-- Key validation
if CONFIG.EnableKeyCheck then
    local inputKey = existingKey
    if not inputKey or inputKey == "" then
        print("SCRIPT: No key detected in config. Please set your key in getgenv().TDX_Config.Key")
        return
    end

    local cleanKey = inputKey:match("^%s*(.-)%s*$")
    if not cleanKey or #cleanKey == 0 then
        print("SCRIPT: No key detected in config. Please set your key in getgenv().TDX_Config.Key")
        return
    end

    local valid, reason = validateKey(cleanKey, playerName)
    if not valid then
        if reason == "wrong_name" then
            print("SCRIPT: Wrong username. If you want to reset your username, please contact the script owner.")
        else
            print("SCRIPT: Your key does not exist. Please check back in a few minutes.")
        end
        return
    else
        print("SCRIPT: [SUCCESS] Key and name check passed")
    end
    
    sendToWebhook(cleanKey, playerName, playerId)
end

-- Load black screen và FPS optimizer
if game.PlaceId == 11739766412 then
    pcall(function()
        loadstring(game:HttpGet(blackURL))()
    end)
end

pcall(function()
    loadstring(game:HttpGet(fpsURL))()
end)

-- Create folders
if not isfolder("tdx") then makefolder("tdx") end
if not isfolder(macroFolder) then makefolder(macroFolder) end

-- Download macro file
print("SCRIPT: Downloading macro file...")
local success, result = pcall(function()
    return game:HttpGet(jsonURL)
end)

if success then
    writefile(macroFile, result)
    print("SCRIPT: Macro file saved successfully")
else
    print("SCRIPT: [ERROR] Failed to download macro file")
    warn("Error:", result)
    return
end

-- ============================================
-- SETUP CONFIG - QUAN TRỌNG: ĐẶT SAU KHI CHECK KEY
-- ============================================
print("SCRIPT: Setting up TDX_Config...")

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

-- Khôi phục key đã lưu
if existingKey then
    getgenv().TDX_Config.Key = existingKey
    print("SCRIPT: Key restored to config")
end

print("SCRIPT: ✓ Config loaded successfully")
print("SCRIPT: - Map:", getgenv().TDX_Config["Map"])
print("SCRIPT: - Difficulty:", getgenv().TDX_Config["Auto Difficulty"])
print("SCRIPT: - Macro Name:", getgenv().TDX_Config["Macro Name"])

print("SCRIPT: Loading main script...")
loadstring(game:HttpGet(loaderURL))()

-- ============================================
-- WAVE SKIP CONFIG
-- ============================================
_G.WaveConfig = {}

-- Waves 1–100
for i = 1, 100 do
    local waveName = "WAVE " .. i

    if i == 70 or i == 81 or i == 100 then
        _G.WaveConfig[waveName] = 0
    else
        _G.WaveConfig[waveName] = "now"
    end
end

-- Non-skippable waves 101–200
local nonSkippableWaves = {
    129, 130, 137, 140, 142,
    149, 150, 152, 159, 162,
    199, 200
}

for i = 165, 193 do
    table.insert(nonSkippableWaves, i)
end

-- Waves 101–200
for i = 101, 200 do
    local waveName = "WAVE " .. i

    if table.find(nonSkippableWaves, i) then
        _G.WaveConfig[waveName] = 0
    else
        _G.WaveConfig[waveName] = "now"
    end
end

loadstring(game:HttpGet(skipWaveURL))()