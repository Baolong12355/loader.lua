-- TDX Macro Runner - Rebuild (Fixed & Loadstring-Compatible with Be logic)

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
        if ok and pos == x then 
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
        warn("[RETRY] Đặt thất bại:", name, x) 
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
local macroRun = {} 
local placedTowers = {} 
local beFlag = false 
local placedBeforeRebuild = {}

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
        beFlag = line.Be or false 
        rebuildTime = i 
        task.spawn(function() 
            while rebuildActive do 
                for x, name in pairs(placedTowers) do 
                    local _, t = GetTowerByAxis(x) 
                    if not t then 
                        placedTowers[x] = nil 
                        local actionsToApply = {} 
                        for j = 1, rebuildTime do 
                            local step = macro[j] 
                            if step.TowerVector then 
                                local v = step.TowerVector:split(", ") 
                                local vx = tonumber(v[1]) 
                                if vx == x then 
                                    local skip = false 
                                    if beFlag then 
                                        if placedBeforeRebuild[vx] and skipSet[step.TowerPlaced] then 
                                            skip = true 
                                        end 
                                    else 
                                        if skipSet[step.TowerPlaced] then 
                                            skip = true 
                                        end 
                                    end 
                                    if not skip then 
                                        table.insert(actionsToApply, { type = "place", data = step, x = vx }) 
                                    end 
                                end 
                            elseif step.TowerUpgraded and tonumber(step.TowerUpgraded) == x then 
                                table.insert(actionsToApply, { type = "upgrade", data = step, x = x }) 
                            elseif step.ChangeTarget and tonumber(step.ChangeTarget) == x then 
                                table.insert(actionsToApply, { type = "target", data = step, x = x }) 
                            end 
                        end 
                        for _, action in ipairs(actionsToApply) do 
                            if action.type == "place" then 
                                local step = action.data 
                                local v = step.TowerVector:split(", ") 
                                local args = { tonumber(step.TowerA1), step.TowerPlaced, Vector3.new(unpack(v)), tonumber(step.Rotation or 0) } 
                                WaitForCash(step.TowerPlaceCost or 0) 
                                PlaceTowerRetry(args, action.x, step.TowerPlaced) 
                                placedTowers[action.x] = step.TowerPlaced 
                            elseif action.type == "upgrade" then 
                                UpgradeTowerRetry(action.x, action.data.UpgradePath) 
                            elseif action.type == "target" then 
                                ChangeTargetRetry(action.x, action.data.TargetType) 
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
            local args = { tonumber(line.TowerA1), line.TowerPlaced, pos, tonumber(line.Rotation or 0) } 
            WaitForCash(line.TowerPlaceCost or 0) 
            PlaceTowerRetry(args, pos.X, line.TowerPlaced) 
            placedTowers[pos.X] = line.TowerPlaced 
            if not rebuildActive then 
                placedBeforeRebuild[pos.X] = true 
            end 
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
