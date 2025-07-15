-- TDX Macro Runner - Replay Per Tower Death (Optimized by Axis X)

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

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

local function WaitForCash(amount)
    while cashStat.Value < amount do
        task.wait()
    end
end

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
    local tries = 0
    while tries < 5 do
        local hash, tower = GetTowerByAxis(axisValue)
        if not hash or not tower then
            tries += 1
            task.wait()
            continue
        end
        local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
        if not hp or hp <= 0 then
            tries += 1
            task.wait()
            continue
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

-- Load macro
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "event"
local macroPath = "tdx/macros/" .. macroName .. ".json"
if not isfile(macroPath) then
    error("Không tìm thấy macro: " .. macroPath)
end

local success, macro = pcall(function()
    return HttpService:JSONDecode(readfile(macroPath))
end)
if not success then
    error("Lỗi khi đọc macro")
end

-- Build cache + run
local macroHistory = {}
local activeTowers = {}

local function ReplayEntriesAtX(x)
    for _, entry in ipairs(macroHistory) do
        if entry.TowerPlaced and entry.TowerVector then
            local vec = entry.TowerVector:split(", ")
            if math.abs(tonumber(vec[1]) - x) <= 0.1 then
                local args = {
                    tonumber(entry.TowerA1),
                    entry.TowerPlaced,
                    Vector3.new(unpack(vec)),
                    tonumber(entry.Rotation or 0)
                }
                WaitForCash(entry.TowerPlaceCost or 0)
                PlaceTowerRetry(args, x, entry.TowerPlaced)
            end
        elseif entry.TowerUpgraded and math.abs(entry.TowerUpgraded - x) <= 0.1 then
            UpgradeTowerRetry(x, entry.UpgradePath)
        elseif entry.ChangeTarget and math.abs(entry.ChangeTarget - x) <= 0.1 then
            ChangeTargetRetry(x, entry.TargetType)
        elseif entry.SellTower and math.abs(entry.SellTower - x) <= 0.1 then
            SellTowerRetry(x)
        end
    end
end

local function TrackDeaths()
    while true do
        for x, _ in pairs(activeTowers) do
            local _, t = GetTowerByAxis(x)
            if not t then
                print("[REBUILD] Tower chết tại X =", x)
                ReplayEntriesAtX(x)
                activeTowers[x] = nil
            end
        end
        task.wait(1)
    end
end

task.spawn(TrackDeaths)

for _, entry in ipairs(macro) do
    table.insert(macroHistory, entry)
    
    if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
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
        activeTowers[pos.X] = true
    
    elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
        UpgradeTowerRetry(entry.TowerUpgraded, entry.UpgradePath)
    
    elseif entry.ChangeTarget and entry.TargetType then
        ChangeTargetRetry(entry.ChangeTarget, entry.TargetType)
    
    elseif entry.SellTower then
        SellTowerRetry(entry.SellTower)
    end
end

print("✅ Macro hoàn tất")
