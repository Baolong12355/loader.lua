repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- urls
local keyFile = "tdx/key.txt"
local sheetURL = "https://api.sheetbest.com/sheets/15da3e15-a25e-423c-bdbf-92a1deaae024"
local jsonURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/x.json"
local loaderURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/loader.lua"
local skipWaveURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/auto_skip.lua"
local macroFolder = "tdx/macros"
local macroFile = macroFolder.."/x.json"

local maxSlots = 5
local pingInterval = 30
local username = Players.LocalPlayer.Name
local inputKey = getgenv().TDX_Config.Key

-- check key local
local function validateLocalKey(key)
    if not isfile(keyFile) then return false end
    local content = readfile(keyFile)
    for line in content:gmatch("[^\r\n]+") do
        if line:match("^%s*(.-)%s*$") == key then
            return true
        end
    end
    return false
end

if not validateLocalKey(inputKey) then
    Players.LocalPlayer:Kick("Invalid key")
    return
end

-- update trạng thái online lên sheet
local function updateStatus(username, key, status)
    local data = {
        username = username,
        key = key,
        status = status,
        last_ping = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    game:HttpPost(sheetURL, HttpService:JSONEncode(data), Enum.HttpContentType.ApplicationJson)
end

-- kiểm tra slot key
local function checkKeySlot()
    local response = game:HttpGet(sheetURL)
    local data = HttpService:JSONDecode(response)
    local count = 0
    for _, row in pairs(data) do
        if row.key == inputKey and row.status == "online" then
            local success, lastPing = pcall(function()
                return os.time(os.date("!*t", os.time(row.last_ping)))
            end)
            if success and os.time() - lastPing <= pingInterval * 2 then
                count = count + 1
            end
        end
    end
    return count < maxSlots
end

-- main
if checkKeySlot() then
    updateStatus(username, inputKey, "online")
    print("[✔] Key slot available. You are online.")

    spawn(function()
        while true do
            wait(pingInterval)
            updateStatus(username, inputKey, "online")
        end
    end)
else
    Players.LocalPlayer:Kick("Your key is currently maxed out. Please wait until slots become available")
    return
end

-- tạo folder macro nếu chưa có
if not isfolder("tdx") then makefolder("tdx") end
if not isfolder(macroFolder) then makefolder(macroFolder) end

-- download macro file
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

-- cấu hình loader
getgenv().TDX_Config = getgenv().TDX_Config or {
    ["Key"] = inputKey,
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

-- skip wave config
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

-- chạy loader & auto skip
loadstring(game:HttpGet(loaderURL))()
loadstring(game:HttpGet(skipWaveURL))()