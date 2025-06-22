local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Ensure LocalPlayer exists
local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait()
    LocalPlayer = Players.LocalPlayer
end

-- Safely load TowerClass
local TowerClass
local ok, err = pcall(function()
    TowerClass = require(LocalPlayer.PlayerScripts.Client.GameClass.TowerClass)
end)
if not ok then
    warn("Failed to load TowerClass:", err)
    return
end

-- Verify Remotes folder exists
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
    warn("Remotes folder not found in ReplicatedStorage")
    return
end

local recorded = {}
local towerPrices = {}

local SAVE_FOLDER = "tdx/macros"
local SAVE_NAME = "recorded.json"
local SAVE_PATH = SAVE_FOLDER .. "/" .. SAVE_NAME

-- Initialize folder and file
if type(makefolder) == "function" and not isfolder(SAVE_FOLDER) then
    makefolder(SAVE_FOLDER)
end

if type(writefile) == "function" and not isfile(SAVE_PATH) then
    writefile(SAVE_PATH, "[]")
end

-- Load existing data
if type(readfile) == "function" and isfile(SAVE_PATH) then
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(SAVE_PATH))
    end)
    if ok and type(data) == "table" then
        recorded = data
    end
end

-- Add new record function
local function add(entry)
    if not entry or type(entry) ~= "table" then return end
    
    local ok, result = pcall(function()
        table.insert(recorded, entry)
        print("[RECORD]", HttpService:JSONEncode(entry))
    end)
    if not ok then
        warn("[RECORD ERROR]", result)
    end
end

-- Get remaining time function
local function getTimeLeft()
    local ok, result = pcall(function()
        local gui = LocalPlayer:WaitForChild("PlayerGui")
        local interface = gui:WaitForChild("Interface")
        local gameInfoBar = interface:WaitForChild("GameInfoBar")
        local timeLeft = gameInfoBar:WaitForChild("TimeLeft")
        local text = timeLeft:WaitForChild("TimeLeftText").Text
        
        local minutes, seconds = text:match("^(%d+):(%d+)$")
        if not minutes or not seconds then return 0 end
        return (tonumber(minutes) or 0) * 60 + (tonumber(seconds) or 0)
    end)
    return ok and result or 0
end

-- Get tower X position from hash
local function GetTowerXFromHash(hash)
    local tower = TowerClass.GetTower(hash)
    if not tower or not tower.Character then return nil end
    
    local model = tower.Character:GetCharacterModel()
    if not model then return nil end
    
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    return root and tonumber(string.format("%.15f", root.Position.X))
end

-- Load tower prices
local function loadTowerPrices()
    local ok, gui = pcall(function()
        return LocalPlayer:WaitForChild("PlayerGui")
    end)
    if not ok then return end
    
    local ok, bar = pcall(function()
        return gui:WaitForChild("Interface"):WaitForChild("BottomBar"):WaitForChild("TowersBar")
    end)
    if not ok then return end
    
    for _, tower in ipairs(bar:GetChildren()) do
        if tower:IsA("ImageButton") and tower:FindFirstChild("CostFrame") then
            local text = tower.CostFrame:FindFirstChild("CostText")
            if text then
                local price = tonumber(text.Text:match("%d+"))
                if price then
                    towerPrices[tower.Name] = price
                end
            end
        end
    end
end

-- Initialize tower prices
loadTowerPrices()

-- Auto-save data
if type(writefile) == "function" then
    task.spawn(function()
        while task.wait(5) do
            local ok, json = pcall(HttpService.JSONEncode, HttpService, recorded)
            if ok and type(json) == "string" then
                pcall(function()
                    writefile(SAVE_PATH, json)
                end)
            end
        end
    end)
end

-- Hook PlaceTower remote
local rawPlace = Remotes:FindFirstChild("PlaceTower")
if rawPlace then
    Remotes.PlaceTower = setmetatable({}, {
        __index = function(_, key)
            if key == "InvokeServer" then
                return function(_, a1, towerName, pos, rotation)
                    local vectorString = "0, 0, 0"
                    pcall(function()
                        vectorString = string.format("%.15f, %.15f, %.15f", pos.X, pos.Y, pos.Z)
                    end)
                    
                    add({
                        type = "PlaceTower",
                        a1 = tostring(a1),
                        tower = towerName,
                        position = vectorString,
                        rotation = rotation,
                        cost = towerPrices[towerName] or 0,
                        time = getTimeLeft()
                    })
                    
                    return rawPlace:InvokeServer(a1, towerName, pos, rotation)
                end
            end
            return rawPlace[key]
        end
    })
end

-- Hook SellTower remote
local rawSell = Remotes:FindFirstChild("SellTower")
if rawSell then
    Remotes.SellTower = setmetatable({}, {
        __index = function(_, key)
            if key == "FireServer" then
                return function(_, hash)
                    local x = GetTowerXFromHash(hash)
                    if x then
                        add({
                            type = "SellTower",
                            positionX = x,
                            time = getTimeLeft()
                        })
                    end
                    return rawSell:FireServer(hash)
                end
            end
            return rawSell[key]
        end
    })
end

-- Hook UpgradeTower remote
local rawUpgrade = Remotes:FindFirstChild("TowerUpgradeRequest")
if rawUpgrade then
    Remotes.TowerUpgradeRequest = setmetatable({}, {
        __index = function(_, key)
            if key == "FireServer" then
                return function(_, hash, path, level)
                    local x = GetTowerXFromHash(hash)
                    if x then
                        add({
                            type = "UpgradeTower",
                            positionX = x,
                            path = path,
                            level = level,
                            time = getTimeLeft()
                        })
                    end
                    return rawUpgrade:FireServer(hash, path, level)
                end
            end
            return rawUpgrade[key]
        end
    })
end

-- Hook ChangeTarget remote
local rawTarget = Remotes:FindFirstChild("ChangeQueryType")
if rawTarget then
    Remotes.ChangeQueryType = setmetatable({}, {
        __index = function(_, key)
            if key == "FireServer" then
                return function(_, hash, targetType)
                    local x = GetTowerXFromHash(hash)
                    if x then
                        add({
                            type = "ChangeTarget",
                            positionX = x,
                            target = targetType,
                            time = getTimeLeft()
                        })
                    end
                    return rawTarget:FireServer(hash, targetType)
                end
            end
            return rawTarget[key]
        end
    })
end

print("✅ Macro Recorder successfully initialized!")
