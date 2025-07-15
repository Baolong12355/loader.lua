-- TDX Macro Runner - Full Version with SuperFunction Integration
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Utility Functions
local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local t0 = os.clock()
    
    while os.clock() - t0 < timeout do
        local success, result = pcall(function()
            return require(path)
        end)
        if success then
            return result
        end
        task.wait()
    end
    return nil
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

-- Tower Management Functions
local function GetTowerByAxis(axisX)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local success, pos = pcall(function()
            local model = tower.Character:GetCharacterModel()
            local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
            return root and root.Position
        end)
        
        if success and pos and math.abs(pos.X - axisX) <= 0.1 then
            local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
            if hp and hp > 0 then
                return hash, tower
            end
        end
    end
    return nil, nil
end

local function GetCurrentUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then
        return nil
    end
    
    local maxLvl = tower.LevelHandler:GetMaxLevel()
    local curLvl = tower.LevelHandler:GetLevelOnPath(path)
    
    if curLvl >= maxLvl then
        return nil
    end
    
    local ok, cost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
    end)
    
    return ok and cost or nil
end

local function WaitForCash(amount)
    while cashStat.Value < amount do
        task.wait()
    end
end

-- Tower Operation Functions
local function PlaceTowerRetry(args, axisValue, towerName)
    while true do
        Remotes.PlaceTower:InvokeServer(unpack(args))
        local t0 = tick()
        
        repeat
            task.wait(0.1)
            local hash = GetTowerByAxis(axisValue)
            if hash then
                return
            end
        until tick() - t0 > 2
        
        warn("[RETRY] Đặt tower thất bại, thử lại:", towerName, "X =", axisValue)
    end
end

local function UpgradeTowerRetry(axisValue, upgradePath)
    local mode = globalPlaceMode
    local maxTries = mode == "rewrite" and math.huge or 3
    local tries = 0
    
    while tries < maxTries do
        local hash, tower = GetTowerByAxis(axisValue)
        if not hash or not tower then
            if mode == "rewrite" then
                tries += 1
                task.wait()
                continue
            end
            warn("[SKIP] Không thấy tower tại X =", axisValue)
            return
        end

        local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
        if not hp or hp <= 0 then
            if mode == "rewrite" then
                tries += 1
                task.wait()
                continue
            end
            warn("[SKIP] Tower đã chết tại X =", axisValue)
            return
        end

        local before = tower.LevelHandler:GetLevelOnPath(upgradePath)
        local cost = GetCurrentUpgradeCost(tower, upgradePath)
        if not cost then
            return
        end

        WaitForCash(cost)
        Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)

        local upgraded = false
        local t0 = tick()
        
        repeat
            task.wait(0.25)
            local _, t = GetTowerByAxis(axisValue)
            if t and t.LevelHandler then
                local after = t.LevelHandler:GetLevelOnPath(upgradePath)
                if after > before then
                    upgraded = true
                    break
                end
            end
        until tick() - t0 > 2

        if upgraded then
            return
        end
        tries += 1
        task.wait()
    end
end

local function ChangeTargetRetry(axisValue, targetType)
    while true do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            Remotes.ChangeQueryType:FireServer(hash, targetType)
            return
        end
        task.wait()
    end
end

local function SellTowerRetry(axisValue)
    while true do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            Remotes.SellTower:FireServer(hash)
            task.wait(0.1)
            if not GetTowerByAxis(axisValue) then
                return
            end
        end
        task.wait()
    end
end

-- SuperFunction Implementation
local team, skipNames, skipOnlyBefore, trackedX = {}, {}, false, {}

local function SaveTeam()
    team = {}
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local model = tower.Character:GetCharacterModel()
        local root = model and model.PrimaryPart
        if root then
            table.insert(team, {
                name = model.Name,
                x = root.Position.X,
                vec = {root.Position.X, root.Position.Y, root.Position.Z},
                a1 = math.random(9999999),
                rot = 0,
                cost = 0,
                upgrades = {}
            })
        end
    end
end

local function RebuildTeam()
    local priority = {
        Medic = 1,
        ["Golden Mobster"] = 2,
        Mobster = 2,
        DJ = 3,
        Commander = 4
    }
    
    table.sort(team, function(a, b)
        return (priority[a.name] or 5) < (priority[b.name] or 5)
    end)
    
    for _, t in ipairs(team) do
        if not trackedX[t.x] then
            if not skipNames[t.name] then
                WaitForCash(t.cost or 0)
                local args = {t.a1, t.name, Vector3.new(unpack(t.vec)), t.rot or 0}
                PlaceTowerRetry(args, t.x, t.name)
                task.wait(0.1)
                
                for _, u in ipairs(t.upgrades or {}) do
                    UpgradeTowerRetry(t.x, u)
                    task.wait(0.1)
                end
                
                trackedX[t.x] = true
                task.wait(2)
            end
        end
    end
end

local function TrackDead()
    while true do
        for _, t in ipairs(team) do
            if not trackedX[t.x] then
                local _, tower = GetTowerByAxis(t.x)
                if not tower then
                    RebuildTeam()
                    return
                end
            end
        end
        task.wait(1)
    end
end

-- Main Execution
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "ooooo"
local macroPath = "tdx/macros/" .. macroName .. ".json"
globalPlaceMode = config["PlaceMode"] or "normal"

if globalPlaceMode == "unsure" then
    globalPlaceMode = "rewrite"
elseif globalPlaceMode == "normal" then
    globalPlaceMode = "ashed"
end

if not isfile(macroPath) then
    error("Không tìm thấy macro: " .. macroPath)
end

local success, macro = pcall(function()
    return HttpService:JSONDecode(readfile(macroPath))
end)

if not success then
    error("Lỗi khi đọc macro")
end

for _, entry in ipairs(macro) do
    if entry.SuperFunction == "SellAll" then
        local skipSet = {}
        for _, v in ipairs(entry.Skip or {}) do
            skipSet[v] = true
        end
        
        for hash, tower in pairs(TowerClass.GetTowers()) do
            local model = tower.Character:GetCharacterModel()
            if model and not skipSet[model.Name] then
                Remotes.SellTower:FireServer(hash)
                trackedX[model.PrimaryPart.Position.X] = true
                task.wait(0.1)
            end
        end
        
    elseif entry.SuperFunction == "rebuild" then
        for _, name in ipairs(entry.Skip or {}) do
            skipNames[name] = true
        end
        skipOnlyBefore = entry.Be == true
        SaveTeam()
        task.spawn(TrackDead)
        
    elseif entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
        local vecTab = entry.TowerVector:split(", ")
        local pos = Vector3.new(unpack(vecTab))
        local args = {
            tonumber(entry.TowerA1),
            entry.TowerPlaced,
            pos,
            tonumber(entry.Rotation or 0)
        }
        WaitForCash(entry.TowerPlaceCost)
        PlaceTowerRetry(args, pos.X, entry.TowerPlaced)
        
    elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
        local axisValue = tonumber(entry.TowerUpgraded)
        UpgradeTowerRetry(axisValue, entry.UpgradePath)
        
        if team then
            for _, t in ipairs(team) do
                if t.x == axisValue then
                    t.upgrades = t.upgrades or {}
                    table.insert(t.upgrades, entry.UpgradePath)
                end
            end
        end
        
    elseif entry.ChangeTarget and entry.TargetType then
        ChangeTargetRetry(tonumber(entry.ChangeTarget), entry.TargetType)
        
    elseif entry.SellTower then
        trackedX[tonumber(entry.SellTower)] = true
        SellTowerRetry(entry.SellTower)
    end
end

print("✅ Macro hoàn tất")
