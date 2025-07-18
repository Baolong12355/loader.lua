-- Services
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Configuration
getgenv().TDX_Config = getgenv().TDX_Config or {
    ["Macro Name"] = "event",
    ["PlaceMode"] = "rewrite",
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil, -- nil = infinite retries
    ["SellAllDelay"] = 0.1,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["RebuildCheckInterval"] = 0.25,
    ["PlacementTimeout"] = 2, -- seconds
    ["UpgradeTimeout"] = 2 -- seconds
}

-- Global variables
local macroPaused = false
local currentMacroIndex = 1
local towerRecords = {}
local skipTypesMap = {}
local rebuildLine = nil
local placedTowers = {} -- Tracks successfully placed towers
local soldPositions = {} -- Tracks sold towers
local rebuildAttempts = {} -- Tracks rebuild attempts per tower

-- Load TowerClass safely
local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local t0 = os.clock()
    while os.clock() - t0 < timeout do
        local success, result = pcall(function() return require(path) end)
        if success then return result end
        task.wait()
    end
    warn("⚠️ Failed to load:", path)
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
if not TowerClass then 
    warn("❌ Failed to load TowerClass")
    return 
end

-- Priority system
local function GetTowerPriority(towerName)
    if not towerName then return math.huge end
    for priority, name in ipairs(getgenv().TDX_Config.PriorityRebuildOrder or {}) do
        if towerName == name then
            return priority
        end
    end
    return math.huge -- Lowest priority if not in list
end

-- Tower utilities
local function GetTowerByAxis(axisX)
    if not placedTowers[axisX] then return nil, nil, nil end
    
    local success, towers = pcall(function() return TowerClass.GetTowers() end)
    if not success or not towers then return nil, nil, nil end
    
    for hash, tower in pairs(towers) do
        if tower and tower.Character then
            local success, pos, name = pcall(function()
                local model = tower.Character:GetCharacterModel()
                local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
                return root and root.Position, model and (root and root.Name or model.Name)
            end)
            if success and pos and math.floor(pos.X) == math.floor(axisX) then
                local hp = (tower.HealthHandler and tower.HealthHandler:GetHealth()) or 0
                if hp > 0 then
                    return hash, tower, name or "Unknown"
                end
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
    
    local ok, baseCost = pcall(function() 
        return tower.LevelHandler:GetLevelUpgradeCost(path, 1) 
    end)
    if not ok then return nil end
    
    local discount = 0
    local ok2, d = pcall(function() 
        return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0 
    end)
    if ok2 and typeof(d) == "number" then discount = d end
    
    return math.floor(baseCost * (1 - discount))
end

-- Economy
local function WaitForCash(amount)
    while cashStat.Value < amount do 
        task.wait(0.1) 
    end
end

-- Tower actions
local function PlaceTowerRetry(args, axisValue, towerName)
    local timeout = getgenv().TDX_Config.PlacementTimeout or 2
    local attempts = 0
    
    while true do
        attempts = attempts + 1
        Remotes.PlaceTower:InvokeServer(unpack(args))
        
        local t0 = tick()
        local placed = false
        
        repeat
            task.wait(0.1)
            local _, tower = GetTowerByAxis(axisValue)
            if tower then
                placedTowers[axisValue] = true
                placed = true
                break
            end
        until tick() - t0 > timeout
        
        if placed then
            return true
        elseif attempts >= 3 then
            warn("⚠️ Failed to place tower after 3 attempts")
            return false
        end
    end
end

local function UpgradeTowerRetry(axisValue, path)
    local timeout = getgenv().TDX_Config.UpgradeTimeout or 2
    
    while true do
        local hash, tower = GetTowerByAxis(axisValue)
        if not hash then 
            task.wait()
            continue 
        end
        
        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then return end
        
        WaitForCash(cost)
        Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
        
        local t0 = tick()
        repeat
            task.wait(0.1)
            local _, t = GetTowerByAxis(axisValue)
            if t and t.LevelHandler:GetLevelOnPath(path) > before then 
                return true
            end
        until tick() - t0 > timeout
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
                soldPositions[axisValue] = true
                placedTowers[axisValue] = nil
                return true
            end
        end
        task.wait()
    end
end

-- Sell all function
local function SellAllTowers(skipList)
    local skipMap = {}
    if skipList then
        for _, name in ipairs(skipList) do
            skipMap[name] = true
        end
    end
    
    local success, towers = pcall(function() return TowerClass.GetTowers() end)
    if not success or not towers then return end
    
    for hash, tower in pairs(towers) do
        local model = tower.Character and tower.Character:GetCharacterModel()
        local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
        if root and not skipMap[root.Name] then
            pcall(function() Remotes.SellTower:FireServer(hash) end)
            task.wait(getgenv().TDX_Config.SellAllDelay or 0.1)
        end
    end
    
    -- Reset tracking
    placedTowers = {}
    soldPositions = {}
end

-- Rebuild system
local function CheckPriorityTowersDestroyed()
    for x, records in pairs(towerRecords) do
        if placedTowers[x] and not soldPositions[x] then
            local _, t, name = GetTowerByAxis(x)
            if not t and name and GetTowerPriority(name) <= #getgenv().TDX_Config.PriorityRebuildOrder then
                return true, x, name
            end
        end
    end
    return false
end

local function RebuildTower(x, records)
    if not records or #records == 0 then return end
    
    local towerType
    for _, record in ipairs(records) do
        if record.entry.TowerPlaced then 
            towerType = record.entry.TowerPlaced 
            break
        end
    end
    
    -- Skip logic
    local skipRule = towerType and skipTypesMap[towerType]
    if skipRule then
        if (skipRule.beOnly and records[1].line < skipRule.fromLine) or (not skipRule.beOnly) then
            return
        end
    end
    
    -- Rebuild attempts tracking
    rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
    if getgenv().TDX_Config.MaxRebuildRetry and rebuildAttempts[x] > getgenv().TDX_Config.MaxRebuildRetry then
        return
    end
    
    -- Execute rebuild actions
    for _, record in ipairs(records) do
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
            if PlaceTowerRetry(args, pos.X, action.TowerPlaced) then
                placedTowers[pos.X] = true
                soldPositions[pos.X] = nil
            end
        elseif action.TowerUpgraded then
            UpgradeTowerRetry(tonumber(action.TowerUpgraded), action.UpgradePath)
        elseif action.ChangeTarget then
            ChangeTargetRetry(tonumber(action.ChangeTarget), action.TargetType)
        end
        task.wait(0.1)
    end
end

-- Main execution
local function LoadAndRunMacro()
    local config = getgenv().TDX_Config
    local macroName = config["Macro Name"] or "event"
    local macroPath = "tdx/macros/" .. macroName .. ".json"

    if not isfile(macroPath) then 
        warn("❌ Macro file not found:", macroPath)
        return 
    end

    local ok, macro = pcall(function() 
        return HttpService:JSONDecode(readfile(macroPath)) 
    end)
    
    if not ok or type(macro) ~= "table" then 
        warn("❌ Invalid macro file")
        return 
    end

    -- Main macro loop
    task.spawn(function()
        while currentMacroIndex <= #macro do
            -- Check for destroyed priority towers
            local priorityDestroyed, x, name = CheckPriorityTowersDestroyed()
            if priorityDestroyed and not macroPaused then
                macroPaused = true
                warn("⏸️ Pausing macro to rebuild priority tower:", name)
                RebuildTower(x, towerRecords[x])
                macroPaused = false
                warn("▶️ Resuming macro")
            end
            
            if not macroPaused then
                local entry = macro[currentMacroIndex]
                
                if entry.SuperFunction == "sell_all" then
                    SellAllTowers(entry.Skip)
                elseif entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
                    local vecTab = entry.TowerVector:split(", ")
                    local pos = Vector3.new(unpack(vecTab))
                    local axisX = pos.X
                    local args = {
                        tonumber(entry.TowerA1),
                        entry.TowerPlaced,
                        pos,
                        tonumber(entry.Rotation or 0)
                    }
                    WaitForCash(entry.TowerPlaceCost)
                    if PlaceTowerRetry(args, axisX, entry.TowerPlaced) then
                        towerRecords[axisX] = towerRecords[axisX] or {}
                        table.insert(towerRecords[axisX], { 
                            line = currentMacroIndex, 
                            entry = entry 
                        })
                        placedTowers[axisX] = true
                    end
                elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
                    local axis = tonumber(entry.TowerUpgraded)
                    UpgradeTowerRetry(axis, entry.UpgradePath)
                    towerRecords[axis] = towerRecords[axis] or {}
                    table.insert(towerRecords[axis], { 
                        line = currentMacroIndex, 
                        entry = entry 
                    })
                elseif entry.ChangeTarget and entry.TargetType then
                    local axis = tonumber(entry.ChangeTarget)
                    ChangeTargetRetry(axis, entry.TargetType)
                    towerRecords[axis] = towerRecords[axis] or {}
                    table.insert(towerRecords[axis], { 
                        line = currentMacroIndex, 
                        entry = entry 
                    })
                elseif entry.SellTower then
                    local axis = tonumber(entry.SellTower)
                    SellTowerRetry(axis)
                    towerRecords[axis] = towerRecords[axis] or {}
                    table.insert(towerRecords[axis], { 
                        line = currentMacroIndex, 
                        entry = entry 
                    })
                elseif entry.SuperFunction == "rebuild" then
                    rebuildLine = currentMacroIndex
                    for _, skip in ipairs(entry.Skip or {}) do
                        skipTypesMap[skip] = { 
                            beOnly = entry.Be == true, 
                            fromLine = currentMacroIndex 
                        }
                    end
                end
                
                currentMacroIndex = currentMacroIndex + 1
            end
            
            task.wait(config.RebuildCheckInterval or 0.25)
        end
    end)

    -- Background rebuild watcher for non-priority towers
    task.spawn(function()
        while true do
            if not macroPaused then
                for x, records in pairs(towerRecords) do
                    if placedTowers[x] and not soldPositions[x] then
                        local _, t, name = GetTowerByAxis(x)
                        if not t and name and GetTowerPriority(name) > #getgenv().TDX_Config.PriorityRebuildOrder then
                            RebuildTower(x, records)
                        end
                    end
                end
            end
            task.wait(config.RebuildCheckInterval or 0.25)
        end
    end)
end

-- Start the script
LoadAndRunMacro()