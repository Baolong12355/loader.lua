-- 📦 TDX Runner & Rebuilder (Priority Rebuild + SellAll + Full Features)

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Cấu hình
getgenv().TDX_Config = getgenv().TDX_Config or {
    ["Macro Name"] = "event",
    ["PlaceMode"] = "rewrite",
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil, -- nil = infinite
    ["SellAllDelay"] = 0.1,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"} -- Danh sách ưu tiên
}

local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local t0 = os.clock()
    while os.clock() - t0 < timeout do
        local success, result = pcall(function() return require(path) end)
        if success then return result end
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

TowerClass = TowerClass or LoadTowerClass()
if not TowerClass then return end

-- Hàm xác định độ ưu tiên
local function GetTowerPriority(towerName)
    for priority, name in ipairs(getgenv().TDX_Config.PriorityRebuildOrder or {}) do
        if towerName == name then
            return priority
        end
    end
    return math.huge -- Mức ưu tiên thấp nhất nếu không có trong danh sách
end

-- Hàm SellAll hoàn chỉnh
local function SellAllTowers(skipList)
    local skipMap = {}
    if skipList then
        for _, name in ipairs(skipList) do
            skipMap[name] = true
        end
    end
    
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local model = tower.Character and tower.Character:GetCharacterModel()
        local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
        if root and not skipMap[root.Name] then
            Remotes.SellTower:FireServer(hash)
            task.wait(getgenv().TDX_Config.SellAllDelay or 0.1)
        end
    end
end

local function GetTowerByAxis(axisX)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local success, pos, name = pcall(function()
            local model = tower.Character:GetCharacterModel()
            local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
            return root and root.Position, model and (root and root.Name or model.Name)
        end)
        if success and pos and pos.X == axisX then
            local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
            if hp and hp > 0 then
                return hash, tower, name or "(NoName)"
            end
        end
    end
    return nil, nil, nil
end

local function GetCurrentUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return nil end
    local maxLvl = tower.LevelHandler:GetMaxLevel()
    local curLvl = tower.LevelHandler:GetLevelOnPath(path)
    if curLvl >= maxLvl then return nil end
    local ok, baseCost = pcall(function() return tower.LevelHandler:GetLevelUpgradeCost(path, 1) end)
    if not ok then return nil end
    local disc = 0
    local ok2, d = pcall(function() return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0 end)
    if ok2 and typeof(d) == "number" then disc = d end
    return math.floor(baseCost * (1 - disc))
end

local function WaitForCash(amount)
    while cashStat.Value < amount do task.wait() end
end

local function PlaceTowerRetry(args, axisValue, towerName)
    while true do
        Remotes.PlaceTower:InvokeServer(unpack(args))
        local t0 = tick()
        repeat task.wait(0.1) until tick() - t0 > 2 or GetTowerByAxis(axisValue)
        if GetTowerByAxis(axisValue) then return end
    end
end

local function UpgradeTowerRetry(axisValue, path)
    while true do
        local hash, tower = GetTowerByAxis(axisValue)
        if not hash then task.wait() continue end
        
        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then return end
        
        WaitForCash(cost)
        Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
        
        local t0 = tick()
        repeat
            task.wait(0.1)
            local _, t = GetTowerByAxis(axisValue)
            if t and t.LevelHandler:GetLevelOnPath(path) > before then return end
        until tick() - t0 > 2
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
            if not GetTowerByAxis(axisValue) then return true end
        end
        task.wait()
    end
end

-- Cơ chế rebuild với ưu tiên
local function StartPriorityRebuildWatcher(towerRecords, rebuildLine, skipTypesMap)
    local soldPositions = {}
    local rebuildAttempts = {}
    
    while true do
        -- Sắp xếp các tháp cần rebuild theo độ ưu tiên
        local rebuildQueue = {}
        for x, records in pairs(towerRecords) do
            local _, t, name = GetTowerByAxis(x)
            if not t then
                if soldPositions[x] and not getgenv().TDX_Config.ForceRebuildEvenIfSold then
                    continue
                end
                
                local towerType
                for _, record in ipairs(records) do
                    if record.entry.TowerPlaced then towerType = record.entry.TowerPlaced end
                end
                
                local skipRule = skipTypesMap[towerType]
                if skipRule then
                    if skipRule.beOnly and records[1].line < skipRule.fromLine then
                        continue
                    elseif not skipRule.beOnly then
                        continue
                    end
                end
                
                rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                local maxRetry = getgenv().TDX_Config.MaxRebuildRetry
                if maxRetry and rebuildAttempts[x] > maxRetry then
                    continue
                end
                
                table.insert(rebuildQueue, {
                    x = x,
                    records = records,
                    priority = GetTowerPriority(towerType),
                    name = towerType or "Unknown"
                })
            end
        end
        
        -- Sắp xếp theo độ ưu tiên
        table.sort(rebuildQueue, function(a, b)
            if a.priority == b.priority then
                return a.x < b.x
            end
            return a.priority < b.priority
        end)
        
        -- Thực hiện rebuild theo thứ tự ưu tiên
        for _, item in ipairs(rebuildQueue) do
            for _, record in ipairs(item.records) do
                local action = record.entry
                if action.TowerPlaced then
                    local vecTab = action.TowerVector:split(", ")
                    local pos = Vector3.new(unpack(vecTab))
                    local args = {
                        tonumber(action.TowerA1), 
                        action.TowerPlaced, 
                        pos, 
                        tonumber(action.Rotation or 0)
                    }
                    WaitForCash(action.TowerPlaceCost)
                    PlaceTowerRetry(args, pos.X, action.TowerPlaced)
                elseif action.TowerUpgraded then
                    UpgradeTowerRetry(tonumber(action.TowerUpgraded), action.UpgradePath)
                elseif action.ChangeTarget then
                    ChangeTargetRetry(tonumber(action.ChangeTarget), action.TargetType)
                elseif action.SellTower then
                    SellTowerRetry(tonumber(action.SellTower))
                end
                task.wait(0.1)
            end
        end
        
        task.wait(0.25)
    end
end

-- Main execution
local config = getgenv().TDX_Config
local macroName = config["Macro Name"] or "event"
local macroPath = "tdx/macros/" .. macroName .. ".json"

if not isfile(macroPath) then return end
local ok, macro = pcall(function() return HttpService:JSONDecode(readfile(macroPath)) end)
if not ok or type(macro) ~= "table" then return end

local towerRecords, skipTypesMap = {}, {}
local rebuildLine, watcherStarted = nil, false

for i, entry in ipairs(macro) do
    if entry.SuperFunction == "sell_all" then
        SellAllTowers(entry.Skip)
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
        towerRecords[pos.X] = towerRecords[pos.X] or {}
        table.insert(towerRecords[pos.X], { line = i, entry = entry })
    elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
        local axis = tonumber(entry.TowerUpgraded)
        UpgradeTowerRetry(axis, entry.UpgradePath)
        towerRecords[axis] = towerRecords[axis] or {}
        table.insert(towerRecords[axis], { line = i, entry = entry })
    elseif entry.ChangeTarget and entry.TargetType then
        local axis = tonumber(entry.ChangeTarget)
        ChangeTargetRetry(axis, entry.TargetType)
        towerRecords[axis] = towerRecords[axis] or {}
        table.insert(towerRecords[axis], { line = i, entry = entry })
    elseif entry.SellTower then
        local axis = tonumber(entry.SellTower)
        SellTowerRetry(axis)
        towerRecords[axis] = towerRecords[axis] or {}
        table.insert(towerRecords[axis], { line = i, entry = entry })
    elseif entry.SuperFunction == "rebuild" then
        rebuildLine = i
        for _, skip in ipairs(entry.Skip or {}) do
            skipTypesMap[skip] = { beOnly = entry.Be == true, fromLine = i }
        end

        if not watcherStarted then
            watcherStarted = true
            task.spawn(StartPriorityRebuildWatcher, towerRecords, rebuildLine, skipTypesMap)
        end
    end
end