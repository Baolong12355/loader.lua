-- run_macro v15_min.lua
local game = game
local HttpService = game.GetService(game, "HttpService")
local ReplicatedStorage = game.GetService(game, "ReplicatedStorage")
local Players = game.GetService(game, "Players")
local player = Players.LocalPlayer
local cash = player.leaderstats.Cash
local remotes = ReplicatedStorage.Remotes

local towers = function()
    return (require(player.PlayerScripts.Client.GameClass.TowerClass)).GetTowers()
end

local POS = function(t)
    local m = t.Character.GetCharacterModel(t)
    return m and m.PrimaryPart and m.PrimaryPart.Position
end

local BYX = function(x)
    for h, t in pairs(towers()) do
        local p = POS(t)
        if p and math.abs(p.X - x) <= 1 then
            return h
        end
    end
end

local waitCash = function(c)
    while cash.Value < c do
        task.wait()
    end
end

local place = function(cost, nme, vec)
    waitCash(cost)
    for i = 1, 10 do
        remotes.PlaceTower.InvokeServer(remotes.PlaceTower, 0, nme, vec, 0)
        task.wait(0.1)
        if BYX(vec.X) then
            break
        end
    end
end

local upg = function(x, path)
    local h, t = BYX(x), nil
    for hash, tower in pairs(towers()) do
        if hash == h then
            t = tower
            break
        end
    end
    if not t then return end
    local cost = t.LevelHandler.GetLevelUpgradeCost(t, path, 1)
    waitCash(cost)
    remotes.TowerUpgradeRequest.FireServer(remotes.TowerUpgradeRequest, h, path, 1)
end

local target = function(x, typ)
    local h = BYX(x)
    if h then
        remotes.ChangeQueryType.FireServer(remotes.ChangeQueryType, h, typ)
    end
end

local sell = function(x)
    for i = 1, 10 do
        local h = BYX(x)
        if h then
            remotes.SellTower.FireServer(remotes.SellTower, h)
            task.wait(0.1)
        else
            break
        end
    end
end

local cfg = getgenv().TDX_Config or {}
local macroName = cfg["Macro Name"] or "ooooo"
local macroDir = "tdx/macros/"
local fileName = macroDir .. macroName .. ".json"
if not isfile(fileName) then
    warn("File macro không tồn tại:", fileName)
    return
end

local ok, macroData = pcall(function()
    return HttpService.JSONDecode(HttpService, readfile(fileName))
end)
if not ok then
    warn("Lỗi JSON:", fileName)
    return
end

for _, entry in ipairs(macroData) do
    if entry.TowerPlaced and entry.TowerPlaceCost and entry.TowerVector then
        local vecTab = entry.TowerVector:gsub("Vector3new%(%s*([^)]*)%)", "%1"):gsub("%s*", "")
        local coords = {}
        for c in vecTab:gmatch("([^,]+)") do
            table.insert(coords, tonumber(c))
        end
        local posVec = { X = coords[1] or 0, Y = coords[2] or 0, Z = coords[3] or 0 }
        place(tonumber(entry.TowerPlaceCost), entry.TowerPlaced, posVec)
    elseif entry.TowerUpgraded and entry.UpgradePath then
        upg(tonumber(entry.TowerUpgraded), entry.UpgradePath)
    elseif entry.ChangeTarget and entry.TargetType then
        target(tonumber(entry.ChangeTarget), entry.TargetType)
    elseif entry.SellTower then
        sell(tonumber(entry.SellTower))
    end
end

print("✅ Macro xong:", macroName)
