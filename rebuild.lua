-- TDX Macro Runner - Rebuild (Fixed & Loadstring-Compatible)

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function SafeRequire(path)
    local ok, result = pcall(require, path)
    return ok and result or nil
end

local function LoadTowerClass()
    local ps = player:WaitForChild("PlayerScripts")
    local client = ps:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    return SafeRequire(towerModule)
end

local TowerClass = LoadTowerClass()
if not TowerClass then
    error("Không thể tải TowerClass")
end

local function GetTowerByAxis(x)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local ok, pos = pcall(function()
            local model = tower.Character:GetCharacterModel()
            return model and model.PrimaryPart.Position.X
        end)
        if ok and pos and math.abs(pos - x) <= 0.001 then
            local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
            if hp and hp > 0 then
                return hash, tower
            end
        end
    end
    return nil, nil
end

local function WaitForCash(amount)
    while cashStat.Value < amount do
        task.wait()
    end
end

local function PlaceTowerRetry(args, x, name)
    while true do
        Remotes.PlaceTower:InvokeServer(unpack(args))
        task.wait(0.1)
        local hash = GetTowerByAxis(x)
        if hash then
            return
        end
    end
end

local function UpgradeTowerRetry(x, path)
    while true do
        local hash, tower = GetTowerByAxis(x)
        if not tower then
            task.wait()
            continue
        end
        local lvlBefore = tower.LevelHandler:GetLevelOnPath(path)
        local max = tower.LevelHandler:GetMaxLevel()
        if lvlBefore >= max then
            return
        end
        local ok, cost = pcall(function()
            return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
        end)
        if not ok or not cost then
            return
        end
        WaitForCash(cost)
        Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
        task.wait(0.1)
        local lvlAfter = tower.LevelHandler:GetLevelOnPath(path)
        if lvlAfter > lvlBefore then
            return
        end
    end
end

local function SellTowerRetry(x)
    local hash = GetTowerByAxis(x)
    if hash then
        Remotes.SellTower:FireServer(hash)
    end
end

local function ChangeTargetRetry(x, t)
    local hash = GetTowerByAxis(x)
    if hash then
        Remotes.ChangeQueryType:FireServer(hash, t)
    end
end

local cfg = _G.TDX_Config or {}
local macroPath = "tdx/macros/" .. (cfg["Macro Name"] or "event") .. ".json"
local macro = HttpService:JSONDecode(readfile(macroPath))

local rebuildActive = false
local skipSet, rebuildTime = {}, 0
local macroRun, placedTowers = {}, {}

for i, line in ipairs(macro) do
    if line.SuperFunction == "SellAll" then
        local skip = {}
        for _, name in ipairs(line.Skip or {}) do
            skip[name] = true
        end
        for hash, tower in pairs(TowerClass.GetTowers()) do
            local model = tower.Character:GetCharacterModel()
            if model and not skip[model.Name] then
                Remotes.SellTower:FireServer(hash)
            end
        end
    elseif line.SuperFunction == "rebuild" then
        rebuildActive = true
        for _, name in ipairs(line.Skip or {}) do
            skipSet[name] = true
        end
        rebuildTime = i
        task.spawn(function()
            while rebuildActive do
                for x, _ in pairs(placedTowers) do
                    local _, t = GetTowerByAxis(x)
                    if not t then
                        placedTowers[x] = nil
                        local actions = {}
                        for j = 1, rebuildTime do
                            local step = macro[j]
                            if step.TowerVector then
                                local v = step.TowerVector:split(", ")
                                local vx = tonumber(v[1])
                                if math.abs(vx - x) <= 0.001 and not skipSet[step.TowerPlaced] then
                                    table.insert(actions, {type = "place", data = step, x = vx})
                                end
                            elseif step.TowerUpgraded then
                                local ux = tonumber(step.TowerUpgraded)
                                if math.abs(ux - x) <= 0.001 then
                                    table.insert(actions, {type = "upgrade", data = step, x = ux})
                                end
                            elseif step.ChangeTarget then
                                local tx = tonumber(step.ChangeTarget)
                                if math.abs(tx - x) <= 0.001 then
                                    table.insert(actions, {type = "target", data = step, x = tx})
                                end
                            end
                        end
                        for _, a in ipairs(actions) do
                            if a.type == "place" then
                                local v = a.data.TowerVector:split(", ")
                                local args = {
                                    tonumber(a.data.TowerA1),
                                    a.data.TowerPlaced,
                                    Vector3.new(unpack(v)),
                                    tonumber(a.data.Rotation or 0)
                                }
                                WaitForCash(a.data.TowerPlaceCost or 0)
                                PlaceTowerRetry(args, a.x, a.data.TowerPlaced)
                                placedTowers[a.x] = true
                            elseif a.type == "upgrade" then
                                UpgradeTowerRetry(a.x, a.data.UpgradePath)
                            elseif a.type == "target" then
                                ChangeTargetRetry(a.x, a.data.TargetType)
                            end
                        end
                    end
                end
                task.wait(1)
            end
        end)
    else
        table.insert(macroRun, line)
        if line.TowerPlaced and line.TowerVector then
            local vec = line.TowerVector:split(", ")
            local pos = Vector3.new(unpack(vec))
            local args = {
                tonumber(line.TowerA1),
                line.TowerPlaced,
                pos,
                tonumber(line.Rotation or 0)
            }
            WaitForCash(line.TowerPlaceCost or 0)
            PlaceTowerRetry(args, pos.X, line.TowerPlaced)
            placedTowers[pos.X] = true
        elseif line.TowerUpgraded then
            UpgradeTowerRetry(tonumber(line.TowerUpgraded), line.UpgradePath)
        elseif line.SellTower then
            SellTowerRetry(line.SellTower)
        elseif line.ChangeTarget then
            ChangeTargetRetry(tonumber(line.ChangeTarget), line.TargetType)
        end
    end
end

print("✅ Macro hoàn tất")
