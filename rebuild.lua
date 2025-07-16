-- TDX Macro Runner - Full Version with SuperFunction Integration + Fix for Upgrade Behavior + Debug for Rebuild

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Safe require function with timeout
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

-- Load tower class module
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

-- Get tower by X axis position
local function GetTowerByAxis(axisX)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local success, pos = pcall(function()
            local model = tower.Character:GetCharacterModel()
            local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
            return root and root.Position
        end)
        
        if success and pos and math.abs(pos.X - axisX) <= 1 then
            local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
            if hp and hp > 0 then
                return hash, tower
            end
        end
    end
    return nil, nil
end

-- Get current upgrade cost for a tower
local function GetCurrentUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then
        return nil
    end
    
    local curLvl = tower.LevelHandler:GetLevelOnPath(path)
    local maxLvl = tower.LevelHandler:GetMaxLevel()
    
    if curLvl >= maxLvl then
        return nil
    end
    
    local ok, cost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
    end)
    
    return ok and cost or nil
end

-- Wait for sufficient cash
local function WaitForCash(amount)
    while cashStat.Value < amount do
        task.wait()
    end
end

-- Place tower with retry mechanism
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

-- Upgrade tower with retry mechanism
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

-- Change target with retry
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

-- Sell tower with retry
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

-- Configuration
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "x"
local macroPath = "tdx/macros/" .. macroName .. ".json"
globalPlaceMode = config["PlaceMode"] or "normal"

if globalPlaceMode == "unsure" then
    globalPlaceMode = "rewrite"
elseif globalPlaceMode == "normal" then
    globalPlaceMode = "ashed"
end

-- Load macro file
if not isfile(macroPath) then
    error("Không tìm thấy macro: " .. macroPath)
end

local success, macro = pcall(function()
    return HttpService:JSONDecode(readfile(macroPath))
end)

if not success then
    error("Lỗi khi đọc macro")
end

-- Global variables
local team, skipNames, skipOnlyBefore, trackedX = {}, {}, false, {}

-- Save current team configuration
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

-- Rebuild team with priority system
local function RebuildTeam()
    print("[REBUILD] Bắt đầu rebuild đội hình...")
    
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
                print(string.format("[REBUILD] Đặt tower: %s tại X = %.1f", t.name, t.x))
                WaitForCash(t.cost or 0)
                
                local args = {t.a1, t.name, Vector3.new(unpack(t.vec)), t.rot or 0}
                PlaceTowerRetry(args, t.x, t.name)
                
                print(string.format("[REBUILD] Đặt thành công tower: %s tại X = %.1f", t.name, t.x))
                task.wait(0.1)
                
                for _, u in ipairs(t.upgrades or {}) do
                    print(string.format("[REBUILD] Nâng cấp path %d cho tower tại X = %.1f", u, t.x))
                    UpgradeTowerRetry(t.x, u)
                    task.wait(0.1)
                end
                
                trackedX[t.x] = true
                print(string.format("[REBUILD] Hoàn tất rebuild cho tower %s tại X = %.1f", t.name, t.x))
                task.wait(2)
            else
                print(string.format("[REBUILD] Bỏ qua tower %s vì nằm trong danh sách skip", t.name))
            end
        else
            print(string.format("[REBUILD] Tower tại X = %.1f đã được xử lý trước đó", t.x))
        end
    end
    
    print("[REBUILD] Đã hoàn thành rebuild toàn bộ team.")
end

-- Track dead towers and rebuild
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

-- Main macro execution
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
