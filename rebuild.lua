-- TDX Macro Runner - Rebuild (New Logic with Exact X Matching, Retry, and Skip)

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Safe require function
local function SafeRequire(path)
    local ok, result = pcall(require, path)
    return ok and result or nil
end

-- Load TowerClass module
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

-- Get tower by exact X position
local function GetTowerByAxis(x)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local ok, pos = pcall(function()
            local model = tower.Character:GetCharacterModel()
            return model and model.PrimaryPart.Position.X
        end)
        
        if ok and pos == x then
            local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
            if hp and hp > 0 then
                return hash, tower
            end
        end
    end
    return nil, nil
end

-- Wait for sufficient cash
local function WaitForCash(amount)
    while cashStat.Value < amount do
        task.wait()
    end
end

-- Place tower with retry mechanism
local function PlaceTowerRetry(args, x, name)
    while true do
        Remotes.PlaceTower:InvokeServer(unpack(args))
        task.wait(0.1)
        
        local hash = GetTowerByAxis(x)
        if hash then
            print("[REBUILD] Đặt thành công:", name, "X:", x)
            return
        end
        
        warn("[RETRY] Đặt thất bại:", name, x)
    end
end

-- Upgrade tower with retry mechanism
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
            print("[REBUILD] Upgrade thành công tại X:", x, "path:", path)
            return
        end
        
        warn("[RETRY] Upgrade thất bại tại X:", x, "path:", path)
    end
end

-- Sell tower with retry
local function SellTowerRetry(x)
    local hash = GetTowerByAxis(x)
    if hash then
        Remotes.SellTower:FireServer(hash)
        print("[SUPER] Sell:", x)
    end
end

-- Change target with retry
local function ChangeTargetRetry(x, t)
    local hash = GetTowerByAxis(x)
    if hash then
        Remotes.ChangeQueryType:FireServer(hash, t)
        print("[REBUILD] Đổi target X:", x, "type:", t)
    end
end

-- Load macro configuration
local cfg = getgenv().TDX_Config or {}
local macroPath = "tdx/macros/" .. (cfg["Macro Name"] or "event") .. ".json"
local mode = cfg["PlaceMode"] or "ashed"
local macro = HttpService:JSONDecode(readfile(macroPath))

-- Setup variables
local rebuildActive = false
local skipSet, rebuildTime = {}, 0
local macroRun = {}

-- Main macro execution loop
for i, line in ipairs(macro) do
    if line.SuperFunction == "SellAll" then
        -- Handle SellAll command
        local skip = {}
        for _, name in ipairs(line.Skip or {}) do
            skip[name] = true
        end
        
        for hash, tower in pairs(TowerClass.GetTowers()) do
            local model = tower.Character:GetCharacterModel()
            if model and not skip[model.Name] then
                Remotes.SellTower:FireServer(hash)
                print("[SUPER] Sell:", model.Name)
            end
        end
        
    elseif line.SuperFunction == "rebuild" then
        -- Handle rebuild command
        rebuildActive = true
        
        for _, name in ipairs(line.Skip or {}) do
            skipSet[name] = true
        end
        
        rebuildTime = i
        
        -- Start rebuild monitoring task
        task.spawn(function()
            while rebuildActive do
                for _, old in ipairs(macroRun) do
                    if old.TowerVector then
                        local vec = old.TowerVector:split(", ")
                        local x = tonumber(vec[1])
                        local _, t = GetTowerByAxis(x)
                        
                        if not t then
                            print("[DETECT] Tower mất tại X:", x)
                            
                            -- Rebuild tower and apply all related actions
                            for j = 1, rebuildTime do
                                local step = macro[j]
                                
                                if step.TowerVector then
                                    local v = step.TowerVector:split(", ")
                                    local vx = tonumber(v[1])
                                    
                                    if vx == x and not skipSet[step.TowerPlaced] then
                                        local args = {
                                            tonumber(step.TowerA1),
                                            step.TowerPlaced,
                                            Vector3.new(unpack(v)),
                                            tonumber(step.Rotation or 0)
                                        }
                                        
                                        WaitForCash(step.TowerPlaceCost or 0)
                                        PlaceTowerRetry(args, vx, step.TowerPlaced)
                                        
                                    elseif step.TowerUpgraded and step.TowerUpgraded == x then
                                        UpgradeTowerRetry(x, step.UpgradePath)
                                        
                                    elseif step.ChangeTarget and step.ChangeTarget == x then
                                        ChangeTargetRetry(x, step.TargetType)
                                    end
                                end
                            end
                        end
                    end
                end
                task.wait(1)
            end
        end)
        
    else
        -- Handle normal macro commands
        table.insert(macroRun, line)
        
        if line.TowerPlaced and line.TowerVector then
            -- Place tower
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
            
        elseif line.TowerUpgraded then
            -- Upgrade tower
            UpgradeTowerRetry(tonumber(line.TowerUpgraded), line.UpgradePath)
            
        elseif line.SellTower then
            -- Sell tower
            SellTowerRetry(line.SellTower)
            
        elseif line.ChangeTarget then
            -- Change target
            ChangeTargetRetry(tonumber(line.ChangeTarget), line.TargetType)
        end
    end
end

print("✅ Macro hoàn tất")
